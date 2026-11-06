extends Node
# Screen transitions: Esc on the loading card -> map page, run -> results, retry -> run. For each: time
# until the next screen is up and the transition layer is gone, the darkest frame on the way (a black
# cut shows as ~0) and the slowest frame. Output @@OUT@@/swap.txt
const OUT = "@@OUT@@/swap.txt"
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
func lum() -> float:
	var img = get_tree().root.get_texture().get_data()
	img.resize(32, 18, Image.INTERPOLATE_NEAREST)
	img.lock()
	var sum = 0.0
	for y in 18:
		for x in 32:
			var c = img.get_pixel(x, y)
			sum += (c.r + c.g + c.b) / 3.0
	return sum / (32 * 18)
# frames until done(), returns [secs, darkest, slowest ms]
var tag = ""
var shot_n = 0
func watch(cond:String, limit:float):
	var t0 = OS.get_ticks_usec()
	var next_shot = 0.0
	var dark = 1.0
	var slow = 0.0
	var last = t0
	while (OS.get_ticks_usec() - t0) / 1e6 < limit:
		yield(get_tree(), "idle_frame")
		var now = OS.get_ticks_usec()
		slow = max(slow, (now - last) / 1000.0)
		last = now
		dark = min(dark, lum())
		var el = (now - t0) / 1e6
		var sw = get_tree().root.get_node_or_null("RRScreenSwap")
		if OS.get_environment("RR_SHOTS") != "" and sw and (sw.t > 0.0 or sw.snap_t > 0.0) and shot_n < 40:
			var img = get_tree().root.get_texture().get_data()
			img.flip_y()
			img.resize(640, 360)
			img.save_png("@@OUT@@/%s_%02d_%.2f.png" % [tag, shot_n, el])
			shot_n += 1
		if call(cond): break
	return [(OS.get_ticks_usec() - t0) / 1e6, dark, slow]
func overlays() -> bool:
	return get_tree().root.has_node("RRScreenSwap") or get_tree().root.has_node("RRRunIntro")
func at_menu() -> bool:
	var sc = get_tree().current_scene
	return sc and "menu" in sc.filename and !("loaders" in sc.filename) and !overlays()
func at_results() -> bool:
	var sc = get_tree().current_scene
	return at_menu() and sc.find_node("ResultsScreen", true, false) != null
func at_run() -> bool:
	var sc = get_tree().current_scene
	return sc and sc.has_node("Game") and !overlays()

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	yield(wait(1.5), "completed")
	out("base light on the menu %.3f" % lum())
	# 1. Esc on the loading card
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	yield(wait(0.7), "completed")
	var e = InputEventKey.new(); e.scancode = KEY_ESCAPE; e.pressed = true
	Input.parse_input_event(e)
	tag = "esc"
	var r = yield(watch("at_menu", 8.0), "completed")
	check(at_menu(), "Esc on the loading card -> map page in %.2f s (darkest %.3f, slowest frame %.0f ms)" % r)
	yield(wait(2.0), "completed")
	# 2. a run -> results
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	r = yield(watch("at_run", 12.0), "completed")
	check(at_run(), "loading card -> run in %.2f s (darkest %.3f, slowest %.0f ms)" % r)
	yield(wait(3.0), "completed")
	# 3. retry (pause menu path)
	load("res://mods/replay/RunIntro.gd").start(get_tree(), 0.5)
	get_tree().change_scene("res://scenes/song.tscn")
	r = yield(watch("at_run", 8.0), "completed")
	check(at_run(), "retry -> run in %.2f s (darkest %.3f, slowest %.0f ms)" % r)
	yield(wait(3.0), "completed")
	var g = get_tree().current_scene.get_node("Game")
	tag = "res"
	g.end(Globals.END_GIVEUP)
	r = yield(watch("at_results", 10.0), "completed")
	check(at_results(), "run -> results in %.2f s (darkest %.3f, slowest %.0f ms)" % r)
	# 4. fail: snaps out (zoom blur) at once; frame times during the snap vs the run before it
	yield(wait(2.0), "completed")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	r = yield(watch("at_run", 12.0), "completed")
	yield(wait(3.0), "completed")
	var run_ms = []
	for i in 30:
		var u = OS.get_ticks_usec()
		yield(get_tree(), "idle_frame")
		run_ms.append((OS.get_ticks_usec() - u) / 1000.0)
	Rhythia.restart_on_death = false
	tag = "fail"
	var snap_ms = []
	get_tree().current_scene.get_node("Game").end(Globals.END_FAIL)
	var t0 = OS.get_ticks_usec()
	while get_tree().root.has_node("RRScreenSwap") and get_tree().root.get_node("RRScreenSwap").pending != "":
		var u = OS.get_ticks_usec()
		yield(get_tree(), "idle_frame")
		snap_ms.append((OS.get_ticks_usec() - u) / 1000.0)
	var snap_s = (OS.get_ticks_usec() - t0) / 1e6
	out("snap frames in order: " + str(snap_ms.slice(0, 4)))
	run_ms.sort(); snap_ms.sort()
	out("run frames: median %.2f ms, worst %.2f | snap frames (%d in %.2f s): median %.2f ms, worst %.2f" % [run_ms[15], run_ms[29], snap_ms.size(), snap_s, snap_ms[snap_ms.size() / 2] if snap_ms.size() else 0.0, snap_ms[-1] if snap_ms.size() else 0.0])
	r = yield(watch("at_results", 10.0), "completed")
	check(at_results(), "fail -> results in %.2f s after the snap (darkest %.3f, slowest %.0f ms)" % r)
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
