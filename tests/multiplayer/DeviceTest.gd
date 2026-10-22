extends Node
# Device options (replay/Device.gd, GyroCursor.gd, Customize > Device). No phone here, so the
# gyroscope is fed through Device.gyro()'s test hook (rr_fake_gyro) and the touch hint through
# rr_touch_ui; everything after the reading is the real path. Checks: the low-end profile changes the
# settings, saves them, and RESTORE puts back exactly what was there; in a run the gyroscope moves
# the cursor at the set speed and direction (inversion too), touch drags are blocked, a second finger
# recentres; with the touch hint, the mod panels' buttons are finger-sized (and not without it).
# Map: @@MAP1@@. Output @@OUT@@/device.txt + dv_*.png
const OUT = "@@OUT@@/device.txt"
var passed = 0
var failed = 0

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func ok(n, c, d = ""):
	if c: passed += 1
	else: failed += 1
	out(("PASS  " if c else "FAIL  ") + n + ("  " + str(d) if str(d) != "" else ""))

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func shot(n):
	if OS.window_minimized:
		out("  (window minimized: no %s screenshot)" % n)
		yield(get_tree(), "idle_frame")
		return
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/dv_" + n + ".png")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func _all(n:Node) -> Array:
	var o = [n]
	for c in n.get_children(): o += _all(c)
	return o

func _settings_json() -> Dictionary:
	var f = File.new()
	if f.open(Globals.p("user://settings.json"), File.READ) != OK: return {}
	var r = JSON.parse(f.get_as_text())
	f.close()
	return r.result if r.error == OK and r.result is Dictionary else {}

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var D = load("res://mods/replay/Device.gd")
	var R = load("res://mods/replay/Reimagined.gd")
	# ---- low-end profile
	R.cfg()["perf_saved"] = {}
	R.cfg()["lite_fx"] = false
	R.cfg()["glitch_fx"] = true
	R.cfg()["trail_style"] = "osu"
	Rhythia.cursor_trail = true
	Rhythia.bloom = 0.5
	Rhythia.render_scale = 1.0
	Rhythia.disable_bg_effects = false
	var before = [R.val("lite_fx"), R.val("glitch_fx"), R.val("trail_style"), Rhythia.cursor_trail, Rhythia.bloom, Rhythia.render_scale, Rhythia.disable_bg_effects]
	var n = D.apply_low()
	ok("low-end profile changes settings", n >= 6 and D.low_on(), n)
	ok("... to the light values (render scale left alone)", R.val("lite_fx") == true and R.val("glitch_fx") == false and R.val("trail_style") == "off" and !Rhythia.cursor_trail and Rhythia.bloom == 0.0 and Rhythia.render_scale == 1.0 and Rhythia.disable_bg_effects)
	var sj = _settings_json()
	ok("... saved to settings.json", sj.get("cursor_trail", true) == false and sj.get("disable_bg_effects", false) == true, "bg effects %s" % str(sj.get("disable_bg_effects")))
	ok("applying twice changes nothing", D.apply_low() == 0)
	var m = D.restore_low()
	var after = [R.val("lite_fx"), R.val("glitch_fx"), R.val("trail_style"), Rhythia.cursor_trail, Rhythia.bloom, Rhythia.render_scale, Rhythia.disable_bg_effects]
	ok("RESTORE puts back exactly what was there", m == n and to_json(after) == to_json(before) and !D.low_on(), "%s vs %s" % [to_json(after), to_json(before)])
	ok("restored values saved too", _settings_json().get("cursor_trail", false) == true)
	# ---- gyroscope cursor in a run
	R.cfg()["cursor_input"] = "gyro"
	R.cfg()["gyro_sens"] = 1.0
	R.cfg()["gyro_inv_x"] = false
	R.cfg()["gyro_inv_y"] = false
	Engine.set_meta("rr_fake_gyro", Vector3.ZERO)
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	Rhythia.select_song(song)
	Rhythia.set("mod_nofail", true)
	Rhythia.start_offset = 0
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var game = null
	var t = 0.0
	while t < 30 and !game:
		yield(wait(0.1), "completed"); t += 0.1
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"): game = sc.get_node("Game")
	yield(wait(1.0), "completed")
	var gc = game.get_node_or_null("RRGyroCursor") if game else null
	ok("the run has the gyro cursor", gc != null)
	var cur = game.get_node("Spawn/Cursor")
	cur.move_cursor_abs(Vector2(1, 1))
	var r = yield(_gyro_move(cur, Vector3(0, -0.2, 0), 0.5), "completed")
	ok("turning right moves the cursor right at 4 cells / rad", abs(r[0].x - r[1]) < 0.15 * r[1] + 0.01 and abs(r[0].y) < 0.01, "moved %s, expected %.3f" % [str(r[0]), r[1]])
	cur.move_cursor_abs(Vector2(1, 1))
	r = yield(_gyro_move(cur, Vector3(-0.2, 0, 0), 0.5), "completed")
	ok("tilting moves it down", abs(r[0].y - r[1]) < 0.15 * r[1] + 0.01 and abs(r[0].x) < 0.01, "moved %s, expected %.3f" % [str(r[0]), r[1]])
	R.cfg()["gyro_inv_x"] = true
	R.cfg()["gyro_sens"] = 2.0
	cur.move_cursor_abs(Vector2(1, 1))
	r = yield(_gyro_move(cur, Vector3(0, -0.1, 0), 0.5), "completed")
	ok("invert + sensitivity 2x", abs(r[0].x + r[1]) < 0.15 * r[1] + 0.01, "moved %s, expected -%.3f" % [str(r[0]), r[1]])
	Engine.set_meta("rr_fake_gyro", Vector3.ZERO)
	cur.move_cursor_abs(Vector2(0.5, 0.5))
	var p0 = cur.rpos
	var mm = InputEventMouseMotion.new()
	mm.relative = Vector2(60, 40)
	mm.position = Vector2(700, 400)
	Input.parse_input_event(mm)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	ok("touch drags (mouse motion) don't move it", cur.rpos.distance_to(p0) < 0.001, str(cur.rpos))
	var tch = InputEventScreenTouch.new()
	tch.index = 1
	tch.pressed = true
	tch.position = Vector2(900, 300)
	Input.parse_input_event(tch)
	yield(get_tree(), "idle_frame")
	ok("a second finger recentres", cur.rpos.distance_to(Vector2(1, 1)) < 0.001, str(cur.rpos))
	game.end(Globals.END_GIVEUP)
	R.cfg()["cursor_input"] = ""
	Engine.remove_meta("rr_fake_gyro")
	t = 0.0
	while t < 20 and !get_tree().root.has_node("Menu"):
		yield(wait(0.25), "completed"); t += 0.25
	yield(wait(2.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	if menu.has_node("ResultsScreen"): menu.get_node("ResultsScreen").queue_free()
	# ---- touch targets
	Engine.set_meta("rr_touch_ui", false)
	menu.open_customize()
	yield(wait(0.6), "completed")
	var cp = menu.get_node("ReimaginedPanel")
	var small = 0
	for b in _all(cp):
		if b is Button and b.is_visible_in_tree() and b.rect_size.y < 44: small += 1
	ok("without a touch screen buttons keep their size", small > 0, "%d below 44 px" % small)
	cp.close()
	yield(wait(0.5), "completed")
	Engine.set_meta("rr_touch_ui", true)
	menu.open_customize()
	yield(wait(0.6), "completed")
	cp = menu.get_node("ReimaginedPanel")
	cp.show_tab("device", false)
	yield(wait(0.3), "completed")
	var bad = []
	for b in _all(cp):
		if (b is BaseButton or b is OptionButton) and b.is_visible_in_tree() and b.rect_size.y < 44: bad.append("%s %s" % [b.get_class(), b.get("text")])
	ok("Customize: every visible button finger-sized (>= 44 px)", bad.empty(), str(bad).left(300))
	ok("the Device tab is there", cp.pages.has("device") and cp.pages.device.visible)
	yield(shot("customize_touch"), "completed")
	cp.close()
	yield(wait(0.5), "completed")
	menu.open_replays() # (was the Library panel: shelved in 2.2.3)
	yield(wait(0.8), "completed")
	var lp = menu.get_node("ReplayBrowser")
	bad = []
	for b in _all(lp):
		if b is BaseButton and b.is_visible_in_tree() and b.rect_size.y < 44: bad.append("%s %s" % [b.get_class(), b.get("text")])
	ok("Replays: every visible button finger-sized", bad.empty(), str(bad).left(300))
	yield(shot("replays_touch"), "completed")
	Engine.remove_meta("rr_touch_ui")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())

# feeds a gyroscope reading for `secs` and returns [cursor movement, the movement expected from the
# time that really passed]
func _gyro_move(cur, g:Vector3, secs:float) -> Array:
	var R = load("res://mods/replay/Reimagined.gd")
	var D = load("res://mods/replay/Device.gd")
	var p0 = cur.rpos
	var u0 = OS.get_ticks_usec()
	Engine.set_meta("rr_fake_gyro", g)
	yield(wait(secs), "completed")
	Engine.set_meta("rr_fake_gyro", Vector3.ZERO)
	var el = (OS.get_ticks_usec() - u0) / 1e6
	var e = D.gyro_delta(g, el, float(R.val("gyro_sens")), bool(R.val("gyro_inv_x")), bool(R.val("gyro_inv_y")))
	return [cur.rpos - p0, abs(e.x) + abs(e.y)]
