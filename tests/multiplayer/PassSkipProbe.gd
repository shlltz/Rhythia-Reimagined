extends Node
# The pass moment skipped with R: a run jumped to just before its last note (NoFail, the song left
# running 6 s): R held 0.3 s and let go (faster, then eased back, no skip), then held all the way -
# the speed builds smoothly, the white-out, the results (time scale back to 1). Output @@OUT@@/passskip.txt (+ skip_*.png with RR_SHOTS)
const OUT = "@@OUT@@/passskip.txt"
var passed = 0
var failed = 0
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
func real_wait(sec:float):
	var u = OS.get_ticks_usec()
	while OS.get_ticks_usec() - u < sec * 1000000.0:
		yield(get_tree(), "idle_frame")
func shot(n):
	if OS.get_environment("RR_SHOTS") == "": return
	var img = get_tree().root.get_texture().get_data()
	img.flip_y(); img.resize(640, 360)
	img.save_png("@@OUT@@/skip_%s.png" % n)
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")
func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	Rhythia.mod_nofail = true
	yield(wait(1.0), "completed")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var t = 0.0
	while t < 12 and !(get_tree().current_scene and get_tree().current_scene.has_node("Game") and !get_tree().root.has_node("RRRunIntro")):
		yield(wait(0.1), "completed"); t += 0.1
	yield(wait(4.0), "completed")
	var g = get_tree().current_scene.get_node("Game")
	var sp = g.get_node("Spawn")
	sp.ms = g.last_ms - 400.0
	sp.emit_signal("ms_change", sp.ms)
	var pm = g.get_node_or_null("PassMoment")
	t = 0.0
	while t < 3.0 and !(pm and pm.started):
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	check(pm and pm.started, "pass moment starts on the last note")
	Rhythia.disable_desync = true
	var mu = sp.get_node("Music")
	if mu.stream: mu.play(max(0.0, mu.stream.get_length() - 6.0))
	yield(real_wait(0.8), "completed")
	# hold R 0.3 s, let go: faster, then eases back off, no skip
	var e = InputEventAction.new(); e.action = "give_up"; e.pressed = true
	Input.parse_input_event(e)
	var sp0 = _speed(pm)
	yield(real_wait(0.3), "completed")
	var h1 = pm.hold
	var sp1 = _speed(pm)
	shot("0_holding")
	e = InputEventAction.new(); e.action = "give_up"; e.pressed = false
	Input.parse_input_event(e)
	yield(real_wait(0.6), "completed")
	check(h1 > 0.35 and h1 < 0.7 and sp1 > sp0 * 1.3, "holding R: the fall speeds up (hold %.2f, %.0f -> %.0f px/s)" % [h1, sp0, sp1])
	check(is_instance_valid(pm) and !pm.skipping and pm.hold == 0.0 and Engine.time_scale < 0.99, "let go early: eased back off, no skip (hold %.2f, time scale %.2f)" % [pm.hold if is_instance_valid(pm) else -1.0, Engine.time_scale])
	# hold again until it skips: the speed builds smoothly
	e = InputEventAction.new(); e.action = "give_up"; e.pressed = true
	Input.parse_input_event(e)
	var u0 = OS.get_ticks_usec()
	var speeds = []
	while OS.get_ticks_usec() - u0 < 900000 and is_instance_valid(pm) and !pm.skipping:
		yield(get_tree(), "idle_frame")
		speeds.append(_speed(pm))
	var jump = 0.0
	for i in range(1, speeds.size()): if speeds[i - 1] > 1.0: jump = max(jump, speeds[i] / speeds[i - 1])
	var held_s = (OS.get_ticks_usec() - u0) / 1e6
	check(is_instance_valid(pm) and pm.skipping, "held all the way: skipping after %.2f s" % held_s)
	check(speeds.size() > 10 and jump < 1.5, "the fall builds smoothly: %.0f -> %.0f px/s over %d frames, biggest step x%.2f a frame" % [speeds[0] if speeds.size() else 0.0, speeds[-1] if speeds.size() else 0.0, speeds.size(), jump])
	t = 0.0
	while t < 5 and !get_tree().root.has_node("Menu/ResultsScreen"):
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	var dt = (OS.get_ticks_usec() - u0) / 1e6
	e = InputEventAction.new(); e.action = "give_up"; e.pressed = false
	Input.parse_input_event(e)
	var rs = get_tree().root.get_node_or_null("Menu/ResultsScreen")
	check(rs != null and dt < 2.0 and Engine.time_scale == 1.0, "results %.2f s after R was pressed again, time scale %.2f" % [dt, Engine.time_scale])
	check(Rhythia.song_end_type == Globals.END_PASS, "counted as a pass (end type %d)" % Rhythia.song_end_type)
	Rhythia.disable_desync = false
	Rhythia.mod_nofail = false
	yield(wait(1.0), "completed")
	shot("2_results")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())

# how fast the glass is falling on screen (px/s): mean drop speed x the moment's speed-up
func _speed(pm) -> float:
	if !is_instance_valid(pm) or pm.shards.empty(): return 0.0
	var s = 0.0
	for x in pm.shards: s += x[1].y
	var ts = Engine.time_scale
	return s / pm.shards.size() * lerp(ts, pm.SKIP_SPEED, pm.skip_k * pm.skip_k) / max(ts, 0.01) * ts
