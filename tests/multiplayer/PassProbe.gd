extends Node
# The pass moment: a run jumped to just before its last note (NoFail) - hit-stop + flash, slow motion,
# the camera pushing in, the white-out into the results; time scale back to 1; the results card's
# progress lines and the stamp. Then a give-up from the pause menu: timed, no pause menu in the frame.
# Output @@OUT@@/pass.txt (+ pass_*.png with RR_SHOTS)
const OUT = "@@OUT@@/pass.txt"
var passed = 0
var failed = 0
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")
func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()
func check(ok, s):
	if ok: passed += 1
	else: failed += 1
	out(("PASS  " if ok else "FAIL  ") + s)
func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")
func shot(n):
	if OS.get_environment("RR_SHOTS") == "": return
	var img = get_tree().root.get_texture().get_data()
	img.flip_y(); img.resize(640, 360)
	img.save_png("@@OUT@@/pass_%s.png" % n)
func real_wait(sec:float): # (the pass moment slows Engine.time_scale: game timers stretch)
	var u = OS.get_ticks_usec()
	while OS.get_ticks_usec() - u < sec * 1000000.0:
		yield(get_tree(), "idle_frame")
func run_up() -> bool:
	var sc = get_tree().current_scene
	return sc and sc.has_node("Game") and !get_tree().root.has_node("RRRunIntro")
func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	Rhythia.mod_nofail = true
	yield(wait(1.0), "completed")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var t = 0.0
	while t < 12 and !run_up():
		yield(wait(0.1), "completed"); t += 0.1
	yield(wait(4.0), "completed")
	var g = get_tree().current_scene.get_node("Game")
	var sp = g.get_node("Spawn")
	var cam = get_tree().current_scene.get_node("Camera")
	var fov0 = cam.fov
	sp.ms = g.last_ms - 400.0
	sp.emit_signal("ms_change", sp.ms)
	var pm = g.get_node_or_null("PassMoment")
	t = 0.0
	while t < 3.0 and !(pm and pm.started):
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	check(pm and pm.started, "pass moment starts on the last note")
	yield(get_tree(), "idle_frame")
	shot("0_stop")
	var ts0 = Engine.time_scale
	var fl = pm.flash.color.a
	yield(real_wait(0.5), "completed")
	shot("1_slow")
	var ts1 = Engine.time_scale
	check(ts0 == 0.0 and abs(ts1 - 0.3) < 0.01 and fl > 0.4, "hit-stop (time scale %.2f, flash %.2f) then slow motion (%.2f)" % [ts0, fl, ts1])
	check(cam.fov < fov0 - 4.0, "camera pushes in (fov %.1f -> %.1f)" % [fov0, cam.fov])
	yield(real_wait(0.85), "completed")
	shot("2_white")
	t = 0.0
	while t < 10 and !get_tree().root.has_node("Menu/ResultsScreen"):
		yield(wait(0.05), "completed"); t += 0.05
	var rs = get_tree().root.get_node_or_null("Menu/ResultsScreen")
	check(rs != null and Engine.time_scale == 1.0, "results after the white-out, time scale back to %.2f" % Engine.time_scale)
	yield(wait(1.5), "completed")
	shot("3_results")
	if rs:
		var pl = rs._progress()
		check(rs.run.get("prev") is Dictionary and rs.stamped and rs.shake >= 0.0, "results: history known (%s), stamped; progress lines: %s" % [str(rs.run.get("prev", {}).get("attempts")), str(pl)])
	Rhythia.mod_nofail = false
	# give up from the pause menu: timed, the frozen frame without the pause menu
	rs._retry()
	t = 0.0
	while t < 12 and !run_up():
		yield(wait(0.1), "completed"); t += 0.1
	yield(wait(2.5), "completed")
	g = get_tree().current_scene.get_node("Game")
	sp = g.get_node("Spawn")
	var e = InputEventKey.new(); e.scancode = KEY_ESCAPE; e.pressed = true
	Input.parse_input_event(e)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	e = InputEventKey.new(); e.scancode = KEY_ESCAPE; e.pressed = false
	Input.parse_input_event(e)
	yield(wait(0.6), "completed")
	var paused_menu = sp.get("pause_menu") != null and sp.pause_menu.is_open()
	out("  before quit: pause_state=%s menu_open=%s focus=%s" % [sp.pause_state, paused_menu, OS.is_window_focused()])
	var u0 = OS.get_ticks_usec()
	sp._pause_choice("quit")
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var sw = get_tree().root.get_node_or_null("RRScreenSwap")
	out("  2 frames after quit: swap=%s shot=%s ending=%s" % [sw != null, sw.shot != null if sw else false, g.ending])
	var frozen_has_menu = false
	if sw and sw.shot:
		var img = sw.shot.texture.get_data()
		img.resize(64, 36)
		img.lock()
		var c = img.get_pixel(32, 21) # (the pause box's white Continue button sits there; the cursor is at the centre)
		img.unlock()
		frozen_has_menu = c.r > 0.85 and c.g > 0.85 and c.b > 0.85
		yield(wait(0.3), "completed")
		shot("4_quit_drift")
		check(sw.drift_s > 1.0, "quit: the frozen frame drifts while the menu loads (scale %.3f)" % sw.drift_s)
	t = 0.0
	while t < 10 and !(get_tree().root.has_node("Menu/ResultsScreen") and !get_tree().root.has_node("RRScreenSwap")):
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	check(paused_menu and !frozen_has_menu, "quit from the pause menu -> results in %.2f s, no pause menu in the frame" % ((OS.get_ticks_usec() - u0) / 1e6))
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
