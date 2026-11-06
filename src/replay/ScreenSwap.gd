extends CanvasLayer
# Screen changes without black (personal build): the last frame of the screen you leave is frozen on
# a layer over the root, the scene changes under it, and the frozen frame holds until the new screen
# draws smoothly (its first frames hitch while it builds), then moves away:
#   "back"    - shrinks and fades (Esc on the loading card)
#   "forward" - grows past the camera and fades (run -> results)
#   "fail"    - a live fail (not replays / autoplay / multiplayer): cut to black, the death log
#               (DeathLog.gd) types out over the stopped run; when it ends (or a key / click skips it)
#               the results load under it and it fades. R restarts instead: the fail sound, eyelids
#               close over the log, the run restarts behind them and they open on it.
# Through menuload (the black loader between a run and the menu) its fades are skipped, so the menu
# comes up as soon as it is loaded. Frees itself when done.

const TIME = {"back": 0.42, "forward": 0.55, "fail": 0.3}
const MAX_HOLD = 6.0   # (still loading: the frozen frame waits for the next screen)
const MAX_SETTLE = 0.6 # s it waits for smooth frames once the next screen is up (a slow machine never gets them)
const CLOSE = 0.2      # s the eyelids take to close (R)
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

func _is_from(sc) -> bool:
	return from_sc != null and sc == from_sc.get_ref()

# R on the death log: restart the map
func retry():
	if retrying: return
	retrying = 1
	lid_t = 0.0
	if Rhythia.fail_asp: Rhythia.fail_asp.play()
	if Rhythia.has_meta("last_run"): Rhythia.remove_meta("last_run") # (no stale results on the next menu)

func _retry_step(delta):
	var dt = min(delta, 1.0 / 30.0)
	lid_t += dt
	if retrying == 1:
		var k = min(lid_t / CLOSE, 1.0)
		eye = 1.0 - k * k
		lids.update()
		if k >= 1.0:
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
