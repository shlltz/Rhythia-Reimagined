extends CanvasLayer
# Screen changes without black (personal build): the last frame of the screen you leave is frozen on
# a layer over the root, the scene changes under it, and the frozen frame holds until the new screen
# draws smoothly (its first frames hitch while it builds), then moves away:
#   "back"    - shrinks and fades (Esc on the loading card)
#   "forward" - grows past the camera and fades (run -> results)
#   "fail"    - a live fail (not replays / autoplay / multiplayer): the death log (DeathLog.gd) runs over
#               the run, which plays on under it. When the log ends, or a click / Esc skips it, the run
#               stops, a red card flashes (black bars, a red band): the square logo and a FAIL jump around
#               it glitching, then the logo alone snaps back to the centre, eyelids close, the fail sound
#               plays in the dark, the results load behind it and fade in. R: the same, but the run
#               restarts behind the closed eyes, which open on it.
# Through menuload (the black loader between a run and the menu) its fades are skipped, so the menu
# comes up as soon as it is loaded. Frees itself when done.

const TIME = {"back": 0.36, "forward": 0.4}
const MAX_HOLD = 6.0   # (still loading: the frozen frame waits for the next screen)
const MAX_SETTLE = 0.4 # s it waits for smooth frames once the next screen is up (a slow machine never gets them)
const FLASH = 0.28     # s the red card shows: the logo pops around the band (POPS s), then back to the centre
const POPS = 0.2
const POP_EVERY = 0.042
const CLOSE = 0.07     # s the eyelids take to close (a quick, subtle ending: the log is the show)
const EYE_W = 0.62     # the eye's half width (x screen width): an almond, the corners shut at once
const RIM = 0.03       # the lids' shaded rim (x screen height)
const OPEN = 0.35      # s to open on the restarted run
const FADE_IN = 0.4    # s the results take to come out of the black

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
var dead:Control = null
var eye:float = 1.0      # 1 open, 0 shut
var mode:String = ""     # fail, once answered: "retry" / "results"
var stage:int = 0        # 1 card + closing, 2 waiting for the next screen, 3 opening / fading in
var lid_t:float = 0.0
var dead_logo:TextureRect = null
var dead_fail:Label = null
var dead_glitch:ColorRect = null
var dead_copy:BackBufferCopy = null
var logo_home:Vector2
var band_rect:Rect2
var next_pop:float = 0.0
var pop_snd:AudioStreamPlayer = null
var prng = RandomNumberGenerator.new()
var up:bool = false     # (back / forward: the next screen is in)

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

# ---------- the menu kept asleep behind the loading card ----------
# A map start used to free the menu (1,800+ nodes) and Esc on the loading card built it again
# (~450 ms frame). Now launch() keeps it in the tree asleep - hidden, every node's processing and
# input off, its sounds / timers / animations / viewports paused, renamed so nothing finds it as the
# menu - and back_to_menu() wakes it exactly as it was. Freed once the run starts (songload).
const SLEEPING = "rr_sleeping_menu"
static func launch(tree:SceneTree):
	var m = tree.current_scene
	if m and m.name == "Menu" and m.filename.ends_with("menu2.tscn") and !Engine.has_meta(SLEEPING):
		_sleep(m)
		tree.current_scene = null # (so the scene change leaves it alone)
		Engine.set_meta(SLEEPING, m)
	tree.change_scene("res://scenes/loaders/songload.tscn")

static func _sleep(m:Node):
	var rec = []
	var st = [m]
	while !st.empty():
		var n = st.pop_back()
		for c in n.get_children(): st.append(c)
		var r = [n, n.is_processing(), n.is_physics_processing(), n.is_processing_input(), n.is_processing_unhandled_input(), n.is_processing_unhandled_key_input(), ""]
		n.set_process(false)
		n.set_physics_process(false)
		n.set_process_input(false)
		n.set_process_unhandled_input(false)
		n.set_process_unhandled_key_input(false)
		if (n == m or n is CanvasLayer) and "visible" in n and n.visible:
			n.visible = false
			r[6] = "visible"
		elif (n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D) and n.playing and !n.stream_paused:
			n.stream_paused = true
			r[6] = "audio"
		elif n is Timer and !n.paused and !n.is_stopped():
			n.paused = true
			r[6] = "timer"
		elif n is AnimationPlayer and n.playback_active:
			n.playback_active = false
			r[6] = "anim"
		elif n is Tween and n.is_active():
			n.set_active(false)
			r[6] = "tween"
		elif n is Viewport and n.render_target_update_mode == Viewport.UPDATE_ALWAYS:
			n.render_target_update_mode = Viewport.UPDATE_DISABLED
			r[6] = "viewport"
		rec.append(r)
	m.set_meta("rr_sleep", rec)
	m.name = "RRMenuAsleep"

# the sleeping menu, gone for good (the run started, or the card left some other way)
static func free_sleeping():
	if !Engine.has_meta(SLEEPING): return
	var m = Engine.get_meta(SLEEPING)
	Engine.remove_meta(SLEEPING)
	if is_instance_valid(m): m.queue_free()

# Esc on the loading card: the frozen card shrinks away over the menu woken up as it was
static func back_to_menu(tree:SceneTree, card:Node, song_pos:float = -1.0):
	var m = Engine.get_meta(SLEEPING) if Engine.has_meta(SLEEPING) else null
	if !is_instance_valid(m):
		go(tree, "res://scenes/loaders/menuload.tscn", "back")
		return
	Engine.remove_meta(SLEEPING)
	var old = tree.root.get_node_or_null("RRScreenSwap")
	if old: old.free()
	var n = load("res://mods/replay/ScreenSwap.gd").new()
	n.name = "RRScreenSwap"
	n.style = "back"
	n.from_sc = weakref(card)
	var img = tree.root.get_texture().get_data()
	if img is Image and img.get_width() > 1:
		img.flip_y()
		var tex = ImageTexture.new()
		tex.create_from_image(img, 0)
		n.set_meta("tex", tex)
	tree.root.add_child(n)
	# what menuload does on the way back (the map's notes stay: the woken map page still uses them)
	tree.paused = false
	PhysicsServer.set_active(true)
	Input.set_custom_mouse_cursor(null)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Rhythia.load_color_txt()
	Rhythia.conmgr_transit = null
	Rhythia.loaded_world = null
	Rhythia.was_replay = Rhythia.replaying
	Rhythia.replaying = false
	if Rhythia.was_replay: Rhythia.restore_prev_state()
	Rhythia.replay_path = ""
	# wake it
	for r in m.get_meta("rr_sleep"):
		var x = r[0]
		if !is_instance_valid(x): continue
		x.set_process(r[1])
		x.set_physics_process(r[2])
		x.set_process_input(r[3])
		x.set_process_unhandled_input(r[4])
		x.set_process_unhandled_key_input(r[5])
		match r[6]:
			"visible": x.visible = true
			"audio": x.stream_paused = false
			"timer": x.paused = false
			"anim": x.playback_active = true
			"tween": x.set_active(true)
			"viewport": x.render_target_update_mode = Viewport.UPDATE_ALWAYS
	m.remove_meta("rr_sleep")
	m.name = "Menu"
	tree.current_scene = m
	card.queue_free()
	# what the start left set (a fresh menu never had these)
	if "black_fade_target" in m: m.black_fade_target = false
	for p in ["Main/Maps/MapRegistry/S/VBoxContainer", "Main/Maps/Results/Results/RS/H1/Info/Run"]:
		var b = m.get_node_or_null(p)
		if b and "has_been_pressed" in b: b.has_been_pressed = false
	for p in ["Main/Maps/MapRegistry/T/Search", "Main/Maps/MapRegistry/T/AuthorSearch"]:
		var e = m.get_node_or_null(p)
		if e is LineEdit: e.editable = true
	var rb = m.get_node_or_null("ReplayBrowser")
	if rb and "starting" in rb: rb.starting = false
	if song_pos >= 0.0: # (the preview carries on from where the card's copy of it got to)
		var pm = m.find_node("PreviewMusic", true, false)
		if pm:
			for k in ["Song", "MenuSong"]:
				var pl = pm.get_node_or_null(k)
				if pl is AudioStreamPlayer and pl.playing: pl.seek(song_pos)

func _ready():
	layer = 99
	pause_mode = PAUSE_MODE_PROCESS
	process_priority = -100 # (before the loader's own _process: its fade is skipped the same frame; the death log's camera tilt comes off first)
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
		dead = _dead_card()
		dead.visible = false
		add_child(dead)
		lids = Control.new()
		lids.anchor_right = 1
		lids.anchor_bottom = 1
		lids.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lids.connect("draw", self, "_draw_lids")
		add_child(lids)

func _is_from(sc) -> bool:
	return from_sc != null and sc == from_sc.get_ref()

# the death log answered: R -> retry(), a click / Esc / the log's end -> finish()
func retry():
	_close("retry")

func finish():
	_close("results")

func _close(m:String):
	if mode != "": return
	mode = m
	stage = 1
	lid_t = 0.0
	get_tree().paused = true # (the run stops here)
	dlog.stop()
	dead.visible = true
	next_pop = 0.0
	prng.randomize()
	if m == "retry" and Rhythia.has_meta("last_run"): Rhythia.remove_meta("last_run") # (no stale results on the next menu)

# the next screen (after a change_scene) is up and drawing smoothly; the loaders' own fades skipped
func _next_ready(delta) -> bool:
	held += delta
	var sc = get_tree().current_scene
	if !sc or _is_from(sc): return held > MAX_HOLD
	var fn = sc.filename
	if "/loaders/" in fn:
		if "menuload" in fn and "black_fade" in sc: # no black in or out: switch the moment the menu is loaded
			sc.black_fade = 1.0
			sc.black_fade_target = true
		return held > MAX_HOLD
	if "black_fade" in sc and sc.get("black_fade") > 0.0 and !sc.get("black_fade_target"): # (the menu's own fade in from black)
		sc.black_fade = 0.0
		var bf = sc.get_node_or_null("BlackFade")
		if bf: bf.visible = false
	settle += delta
	steady = steady + 1 if delta < 0.05 else 0
	return steady >= 3 or settle > MAX_SETTLE or held > MAX_HOLD

func _fail_step(delta):
	var dt = min(delta, 1.0 / 30.0)
	lid_t += dt
	if stage == 1: # the red card: the logo pops around the band, snaps back to the centre, the eyelids close
		if lid_t < POPS:
			if lid_t >= next_pop:
				next_pop = lid_t + POP_EVERY
				var ls = dead_logo.rect_size
				dead_logo.rect_position = Vector2(prng.randf_range(band_rect.position.x, band_rect.end.x - ls.x), prng.randf_range(band_rect.position.y - ls.y * 0.15, band_rect.end.y - ls.y * 0.85))
				var sc = prng.randf_range(0.6, 1.15)
				dead_logo.rect_scale = Vector2(sc, sc)
				dead_logo.rect_rotation = prng.randf_range(-25.0, 25.0)
				var fs = dead_fail.rect_size # the FAIL jumps too (somewhere else on the band)
				dead_fail.visible = true
				dead_fail.rect_position = Vector2(prng.randf_range(band_rect.position.x, band_rect.end.x - fs.x), prng.randf_range(band_rect.position.y, band_rect.end.y - fs.y))
				dead_fail.rect_rotation = prng.randf_range(-12.0, 12.0)
				var fz = prng.randf_range(0.75, 1.25)
				dead_fail.rect_scale = Vector2(fz, fz)
			dead_copy.visible = true # glitching while they jump
			dead_glitch.visible = true
			dead_glitch.material.set_shader_param("seed", prng.randf() * 100.0)
			dead_glitch.material.set_shader_param("amount", prng.randf_range(0.45, 1.0))
		elif dead_logo.rect_position != logo_home: # back home, a punch (clean: no FAIL, no glitch)
			dead_fail.visible = false
			dead_copy.visible = false
			dead_glitch.visible = false
			dead_logo.rect_position = logo_home
			dead_logo.rect_rotation = 0.0
			dead_logo.rect_scale = Vector2(1.12, 1.12)
			_pop_sound(1.0, -14.0)
		else:
			dead_logo.rect_scale = dead_logo.rect_scale.linear_interpolate(Vector2.ONE, 1.0 - exp(-dt * 22.0))
		if lid_t < FLASH: return
		var k = min((lid_t - FLASH) / CLOSE, 1.0)
		eye = 0.55 * pow(1.0 - k, 2) # (starts already on the red band, closes fast)
		lids.update()
		if k < 1.0: return
		dead.visible = false
		dlog.untilt()
		dlog.visible = false
		if Rhythia.fail_asp: # the fail sound once the eyes are shut (the run is paused by now: it plays through it)
			Rhythia.fail_asp.pause_mode = Node.PAUSE_MODE_PROCESS
			Rhythia.fail_asp.play()
		var sc0 = get_tree().current_scene # the run's deferred bookkeeping (recent plays, ...): now, behind the shut eyes
		var game0 = sc0.get_node_or_null("Game") if sc0 else null
		if game0 and game0.has_method("rr_finish_books"): game0.rr_finish_books()
		stage = 2
		held = 0.0
		steady = 0
		settle = 0.0
		from_sc = weakref(get_tree().current_scene) if get_tree().current_scene else null
		if mode == "retry":
			Rhythia.replaying = false
			get_tree().change_scene("res://scenes/song.tscn" if pending != "" else "res://scenes/loaders/songload.tscn")
		elif pending != "":
			get_tree().change_scene(pending)
		pending = ""
	elif stage == 2:
		if mode == "retry":
			var sc = get_tree().current_scene
			if !sc or _is_from(sc): return
			var game = sc.get_node_or_null("Game")
			if !game and !("songload" in sc.filename): return # (the loading card: opens on it)
			if game and "black_fade" in game: game.black_fade = 0.0 # (the run's own fade from black: the eyelids do it)
			settle += delta
			steady = steady + 1 if delta < 0.05 else 0
			if steady < 3 and settle <= MAX_SETTLE: return
		elif !_next_ready(delta): return
		stage = 3
		lid_t = 0.0
	else:
		if mode == "retry": # the eyes open on the new run
			var sc = get_tree().current_scene
			var game = sc.get_node_or_null("Game") if sc else null
			if game and "black_fade" in game: game.black_fade = 0.0
			var k = min(lid_t / OPEN, 1.0)
			eye = 1.7 * (1.0 - pow(1.0 - k, 3)) # (past 1: the almond opens beyond the corners)
			lids.update()
			if k >= 1.0: queue_free()
		else: # the results come out of the black
			var k = min(lid_t / FADE_IN, 1.0)
			lids.modulate.a = 1.0 - k * k * (3.0 - 2.0 * k)
			if k >= 1.0: queue_free()

# two lids meeting along an almond edge, each with a shaded dark-red rim (eye = 1: no lids)
func _draw_lids():
	if mode == "": return
	var s = lids.rect_size
	var top = PoolVector2Array([Vector2(0, 0), Vector2(s.x, 0)])
	var bot = PoolVector2Array([Vector2(0, s.y), Vector2(s.x, s.y)])
	var te = []
	var be = []
	var n = 48
	for i in range(n, -1, -1):
		var x = s.x * i / n
		var u = (x - s.x / 2) / (s.x * EYE_W)
		var h = s.y * 0.62 * eye * sqrt(max(0.0, 1.0 - u * u))
		var yt = max(0.0, s.y / 2 - h)
		var yb = min(s.y, s.y / 2 + h)
		top.append(Vector2(x, yt))
		bot.append(Vector2(x, yb))
		te.append(Vector2(x, yt))
		be.append(Vector2(x, yb))
	lids.draw_colored_polygon(top, Color(0, 0, 0))
	lids.draw_colored_polygon(bot, Color(0, 0, 0))
	var rim = s.y * RIM * (0.4 + 0.6 * eye)
	var c0 = Color(0.18, 0.0, 0.0, 0.9)
	var c1 = Color(0.18, 0.0, 0.0, 0.0)
	for i in range(te.size() - 1):
		if te[i].y >= be[i].y and te[i + 1].y >= be[i + 1].y: continue # (shut there)
		lids.draw_polygon(PoolVector2Array([te[i], te[i + 1], te[i + 1] + Vector2(0, rim), te[i] + Vector2(0, rim)]), PoolColorArray([c0, c0, c1, c1]))
		lids.draw_polygon(PoolVector2Array([be[i], be[i + 1], be[i + 1] - Vector2(0, rim), be[i] - Vector2(0, rim)]), PoolColorArray([c0, c0, c1, c1]))

func _process(delta):
	if is_instance_valid(dlog): dlog.untilt() # (the death log's tilt off the camera before anything else runs)
	if style == "fail":
		if stage > 0: _fail_step(delta)
		elif dlog.done: finish()
		return
	if !up:
		up = _next_ready(delta)
		_drift() # (never a still frame while the next screen loads: it keeps moving)
		return
	t += min(delta, 1.0 / 30.0)
	var k = min(t / TIME.get(style, 0.45), 1.0)
	var e = 1.0 - pow(1.0 - k, 3)
	if shot:
		shot.rect_pivot_offset = shot.rect_size / 2
		var s = drift_s + ((-0.08 * e) if style == "back" else (0.12 * e))
		shot.rect_scale = Vector2(s, s)
		shot.modulate.a = 1.0 - k * k * (3.0 - 2.0 * k)
	if k >= 1.0:
		queue_free()

# while the next screen loads the frozen frame drifts (forward: on towards you, back: away) and dims a
# little, so the change is moving from the first frame; the move-away then carries on from there
var drift_s:float = 1.0
func _drift():
	if !shot: return
	var d = 1.0 - exp(-held * 2.5)
	drift_s = 1.0 + (0.04 * d if style == "forward" else -0.03 * d)
	shot.rect_pivot_offset = shot.rect_size / 2
	shot.rect_scale = Vector2(drift_s, drift_s)
	var v = 1.0 - 0.22 * d
	shot.modulate = Color(v, v, v, 1.0)

# black bars, a red band with the square logo in black
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
	band_rect = Rect2(band.rect_position, band.rect_size)
	var logo = TextureRect.new()
	dead_logo = logo
	var sk = load("res://mods/replay/Reimagined.gd").skin_tex("logo")
	logo.texture = sk if sk else load("res://assets/images/branding/icon.png")
	logo.expand = true
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.modulate = Color(0, 0, 0)
	var ls = vs.y * 0.46
	logo.rect_position = Vector2(vs.x / 2 - ls / 2, vs.y * 0.505 - ls / 2)
	logo.rect_size = Vector2(ls, ls)
	logo.rect_pivot_offset = logo.rect_size / 2
	logo_home = logo.rect_position
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(logo)
	var DL = load("res://mods/replay/DeathLog.gd")
	dead_fail = Label.new()
	dead_fail.text = "FAIL"
	var ff = DynamicFont.new()
	if ResourceLoader.exists(DL.FONT): ff.font_data = load(DL.FONT)
	ff.size = DL.fail_size(vs)
	dead_fail.add_font_override("font", ff)
	dead_fail.add_color_override("font_color", Color(0, 0, 0))
	dead_fail.rect_size = ff.get_string_size("FAIL") + Vector2(8, 0)
	dead_fail.rect_pivot_offset = dead_fail.rect_size / 2
	dead_fail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dead_fail.visible = false
	c.add_child(dead_fail)
	dead_copy = BackBufferCopy.new() # (the glitch reads the card as drawn)
	dead_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	dead_copy.visible = false
	c.add_child(dead_copy)
	dead_glitch = ColorRect.new()
	dead_glitch.anchor_right = 1
	dead_glitch.anchor_bottom = 1
	dead_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dead_glitch.material = ShaderMaterial.new()
	dead_glitch.material.shader = DL.shader(DL.GLITCH_SHADER)
	dead_glitch.visible = false
	c.add_child(dead_glitch)
	return c

# each pop of the logo: the map start's thump, pitched up
func _pop_sound(pitch:float, db:float):
	if !Engine.has_meta("rr_enter_sfx"): return
	if !pop_snd:
		pop_snd = AudioStreamPlayer.new()
		pop_snd.bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
		add_child(pop_snd)
	pop_snd.stream = Engine.get_meta("rr_enter_sfx")
	pop_snd.pitch_scale = pitch
	pop_snd.volume_db = db
	pop_snd.play()
