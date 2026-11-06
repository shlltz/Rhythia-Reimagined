extends CanvasLayer
# Screen changes without black (personal build): the last frame of the screen you leave is frozen on
# a layer over the root, the scene changes under it, and the frozen frame holds until the new screen
# draws smoothly (its first frames hitch while it builds), then moves away:
#   "back"    - shrinks and fades (Esc on the loading card)
#   "forward" - grows past the camera and fades (run -> results)
#   "fail"    - a live fail (not replays / autoplay / multiplayer): cut to black, the death log
#               (DeathLog.gd) types out over the stopped run; when it ends (or a key / click skips it)
#               the results load under it and it fades. R restarts instead: the fail sound, a quick
#               flash of a "you are dead" card (the square logo, black on red, between black bars),
#               eyelids close over it, the run restarts behind them and they open on it.
# Through menuload (the black loader between a run and the menu) its fades are skipped, so the menu
# comes up as soon as it is loaded. Frees itself when done.

const TIME = {"back": 0.42, "forward": 0.55, "fail": 0.3}
const MAX_HOLD = 6.0   # (still loading: the frozen frame waits for the next screen)
const MAX_SETTLE = 0.6 # s it waits for smooth frames once the next screen is up (a slow machine never gets them)
const FLASH = 0.15     # s the dead card flashes (R)
const CLOSE = 0.14     # s the eyelids take to close
const OPEN = 0.35      # s to open on the new run

var shot:TextureRect = null
var style:String = "back"
var from_sc = null     # weakref to the scene being left
var t:float = 0.0
var held:float = 0.0
var steady:int = 0
var settle:float = 0.0
var pending:String = ""  # (fail: the scene to change to once the log is over)
var dlog = null
var lids:Control = null
var eye:float = 1.0      # 1 open, 0 shut
var retrying:int = 0     # 1 closing, 2 waiting for the new run, 3 opening
var lid_t:float = 0.0
var dead:Control = null

static func go(tree:SceneTree, scene:String, style_:String = "back"):
	var old = tree.root.get_node_or_null("RRScreenSwap")
	if old: old.free()
	var n = load("res://mods/replay/ScreenSwap.gd").new()
	n.name = "RRScreenSwap"
	n.style = style_
	n.from_sc = weakref(tree.current_scene) if tree.current_scene else null
	if style_ == "fail":
		n.pending = scene
		tree.root.add_child(n)
		return
	var img = tree.root.get_texture().get_data()
	if img is Image and img.get_width() > 1:
		img.flip_y()
		var tex = ImageTexture.new()
		tex.create_from_image(img, 0)
		n.set_meta("tex", tex)
		tree.root.add_child(n)
	tree.change_scene(scene)

# on the loading card: the death log's blips made now (not on the fail)
static func warm(_parent:Node):
	load("res://mods/replay/DeathLog.gd").blips()

func _ready():
	layer = 99
	pause_mode = PAUSE_MODE_PROCESS
	process_priority = -100 # (before the loader's own _process: its fade is skipped the same frame)
	if has_meta("tex"):
		shot = TextureRect.new()
		shot.texture = get_meta("tex")
		shot.expand = true
		shot.anchor_right = 1
		shot.anchor_bottom = 1
		shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shot)
	if style == "fail":
		dlog = load("res://mods/replay/DeathLog.gd").new()
		add_child(dlog)
		lids = Control.new()
		lids.anchor_right = 1
		lids.anchor_bottom = 1
		lids.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lids.connect("draw", self, "_draw_lids")
		add_child(lids)
		dead = _dead_card() # (built and drawn faintly while the log runs: its big glyphs ready for R)
		dead.modulate.a = 0.004
		add_child(dead)
		move_child(dead, lids.get_index())

func _is_from(sc) -> bool:
	return from_sc != null and sc == from_sc.get_ref()

# R on the death log: restart the map
func retry():
	if retrying: return
	retrying = 1
	lid_t = 0.0
	if Rhythia.fail_asp: Rhythia.fail_asp.play()
	dead.modulate.a = 1.0
	if Rhythia.has_meta("last_run"): Rhythia.remove_meta("last_run") # (no stale results on the next menu)

func _retry_step(delta):
	var dt = min(delta, 1.0 / 30.0)
	lid_t += dt
	if retrying == 1:
		if dead and dead.modulate.a >= 1.0: # the card punches in (a slight zoom down to size)
			var f = min(lid_t / FLASH, 1.0)
			var z = 1.0 + 0.06 * (1.0 - f) * (1.0 - f)
			dead.rect_pivot_offset = dead.rect_size / 2
			dead.rect_scale = Vector2(z, z)
		if lid_t < FLASH: return
		var k = min((lid_t - FLASH) / CLOSE, 1.0)
		eye = 1.0 - k * k
		lids.update()
		if k >= 1.0:
			if dead: dead.visible = false
			retrying = 2
			steady = 0
			settle = 0.0
			Rhythia.replaying = false
			from_sc = weakref(get_tree().current_scene) if get_tree().current_scene else null
			# still on the stopped run: the same restart as the pause menu's; after the menu took over: the loading card
			get_tree().change_scene("res://scenes/song.tscn" if pending != "" else "res://scenes/loaders/songload.tscn")
			pending = ""
	elif retrying == 2:
		var sc = get_tree().current_scene
		if !sc or _is_from(sc): return
		var game = sc.get_node_or_null("Game")
		if !game and !("songload" in sc.filename): return # (the loading card: opens on it)
		if game and "black_fade" in game: game.black_fade = 0.0 # (the run's own fade from black: the eyelids do it)
		_hold_r(game)
		settle += delta
		steady = steady + 1 if delta < 0.05 else 0
		if steady >= 3 or settle > MAX_SETTLE:
			retrying = 3
			lid_t = 0.0
			dlog.visible = false
	else:
		var sc = get_tree().current_scene
		var game = sc.get_node_or_null("Game") if sc else null
		if game and "black_fade" in game: game.black_fade = 0.0
		var k = min(lid_t / OPEN, 1.0)
		eye = 1.0 - pow(1.0 - k, 3)
		lids.update()
		if k >= 1.0 and !_hold_r(game): queue_free() # (stays until R is let go)

# R is also the run's hold-to-give-up key: the restarted run ignores it until it's let go
func _hold_r(game) -> bool:
	if !Input.is_action_pressed("give_up"): return false
	if game and "giving_up" in game: game.giving_up = 0.0
	return true

# two lids meeting along an eye-shaped edge (eye = 1: open past the screen edges)
func _draw_lids():
	if eye >= 1.0: return
	var s = lids.rect_size
	var top = PoolVector2Array([Vector2(0, 0), Vector2(s.x, 0)])
	var bot = PoolVector2Array([Vector2(0, s.y), Vector2(s.x, s.y)])
	var n = 40
	for i in range(n, -1, -1):
		var x = s.x * i / n
		var u = (x - s.x / 2) / (s.x * 0.75)
		var h = s.y * 0.75 * eye * sqrt(max(0.0, 1.0 - u * u))
		top.append(Vector2(x, max(0.0, s.y / 2 - h)))
		bot.append(Vector2(x, min(s.y, s.y / 2 + h)))
	lids.draw_colored_polygon(top, Color(0, 0, 0))
	lids.draw_colored_polygon(bot, Color(0, 0, 0))

func _process(delta):
	if retrying:
		_retry_step(delta)
		return
	if pending != "": # the death log over the stopped run; the results load once it's over
		if dlog.done:
			get_tree().change_scene(pending)
			pending = ""
		return
	var sc = get_tree().current_scene
	var fn = sc.filename if sc else ""
	if steady < 3 and held < MAX_HOLD:
		held += delta
		if !sc or _is_from(sc): return
		if "/loaders/" in fn:
			if "menuload" in fn and "black_fade" in sc: # no black in or out: switch the moment the menu is loaded
				sc.black_fade = 1.0
				sc.black_fade_target = true
			return
		if "black_fade" in sc and sc.get("black_fade") > 0.0 and !sc.get("black_fade_target"): # (the menu's own fade in from black)
			sc.black_fade = 0.0
			var bf = sc.get_node_or_null("BlackFade")
			if bf: bf.visible = false
		settle += delta
		steady = steady + 1 if delta < 0.05 else 0
		if settle > MAX_SETTLE: steady = 3
		return
	t += min(delta, 1.0 / 30.0)
	var k = min(t / TIME.get(style, 0.45), 1.0)
	var e = 1.0 - pow(1.0 - k, 3)
	var a = 1.0 - k * k * (3.0 - 2.0 * k)
	if shot:
		shot.rect_pivot_offset = shot.rect_size / 2
		var s = (1.0 - 0.08 * e) if style == "back" else (1.0 + 0.12 * e)
		shot.rect_scale = Vector2(s, s)
		shot.modulate.a = a
	if dlog:
		dlog.set_process(false)
		dlog.modulate.a = a
	if k >= 1.0:
		queue_free()

# black bars, a red band with the square logo in black, big white text (VCR mono)
func _dead_card() -> Control:
	var c = Control.new()
	c.anchor_right = 1
	c.anchor_bottom = 1
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs = get_viewport().get_visible_rect().size
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(bg)
	var band = ColorRect.new()
	band.color = Color(1.0, 0.02, 0.02)
	band.rect_position = Vector2(0, vs.y * 0.185)
	band.rect_size = Vector2(vs.x, vs.y * 0.64)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(band)
	var sk = load("res://mods/replay/Reimagined.gd").skin_tex("logo")
	var tex = sk if sk else load("res://assets/images/branding/icon.png")
	var logo = TextureRect.new()
	logo.texture = tex
	logo.expand = true
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.modulate = Color(0, 0, 0)
	var ls = vs.y * 0.46
	logo.rect_position = Vector2(vs.x / 2 - ls / 2, vs.y * 0.505 - ls / 2)
	logo.rect_size = Vector2(ls, ls)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(logo)
	var font = DynamicFont.new()
	var fp = load("res://mods/replay/DeathLog.gd").FONT
	if ResourceLoader.exists(fp): font.font_data = load(fp)
	font.size = int(vs.y * 0.12)
	for row in [["[YOU ARE DEAD]", 0.0], ["Press [R] TO RESTART", vs.y * 0.825]]:
		var size = int(vs.y * 0.12)
		while size > 12 and font.get_string_size(row[0]).x > vs.x * 0.92: # (fits the width)
			size -= 2
			font.size = size
		var l = Label.new()
		l.text = row[0]
		l.add_font_override("font", font.duplicate())
		l.add_color_override("font_color", Color(1, 1, 1))
		l.align = Label.ALIGN_CENTER
		l.valign = Label.VALIGN_CENTER
		l.rect_position = Vector2(0, row[1])
		l.rect_size = Vector2(vs.x, vs.y * 0.18)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(l)
		font.size = int(vs.y * 0.12)
	return c
