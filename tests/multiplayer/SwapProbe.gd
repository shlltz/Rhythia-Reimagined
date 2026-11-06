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
var in_ms = []
var last_in = 0
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
		var el = (now - t0) / 1e6
		var sw = get_tree().root.get_node_or_null("RRScreenSwap")
		var ri = get_tree().root.get_node_or_null("RRRunIntro")
		var snapping = ri and ri.blur and ri.blur.visible
		if snapping: in_ms.append((now - last_in) / 1000.0)
		if !snapping or in_ms.size() % 4 == 0: dark = min(dark, lum()) # (a screen readback costs ~9 ms: rarely while timing the snap)
		last_in = OS.get_ticks_usec()
		if OS.get_environment("RR_SHOTS") != "" and OS.get_environment("RR_SHOTS") in ["1", tag] and ((sw and (sw.t > 0.0 or sw.retrying > 0)) or snapping) and shot_n < 60:
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

func shoot_for(secs:float):
	var t0 = OS.get_ticks_msec()
	while OS.get_ticks_msec() - t0 < secs * 1000.0:
		yield(get_tree(), "idle_frame")
		var img = get_tree().root.get_texture().get_data()
		img.flip_y()
		img.resize(640, 360)
		img.save_png("@@OUT@@/log_%02d.png" % shot_n)
		shot_n += 1
		yield(get_tree().create_timer(0.25, true), "timeout")

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
	tag = "in"
	r = yield(watch("at_run", 12.0), "completed")
	check(at_run(), "loading card -> run in %.2f s (darkest %.3f, slowest %.0f ms)" % r)
	in_ms.sort()
	check(in_ms.size() > 3, "map start snaps in: %d frames, median %.2f ms, worst %.2f ms" % [in_ms.size(), in_ms[in_ms.size() / 2] if in_ms.size() else 0.0, in_ms[-1] if in_ms.size() else 0.0])
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
	# 4. fail: the death log over the stopped run; R restarts (eyelids), a key skips to the results
	yield(wait(2.0), "completed")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	r = yield(watch("at_run", 12.0), "completed")
	yield(wait(2.0), "completed")
	Rhythia.restart_on_death = false
	tag = "fail"
	get_tree().current_scene.get_node("Game").end(Globals.END_FAIL)
	var log_ms = []
	var u0 = OS.get_ticks_usec()
	while (OS.get_ticks_usec() - u0) < 700000:
		var u = OS.get_ticks_usec()
		yield(get_tree(), "idle_frame")
		log_ms.append((OS.get_ticks_usec() - u) / 1000.0)
	log_ms.sort()
	var sw = get_tree().root.get_node_or_null("RRScreenSwap")
	check(sw and sw.dlog and sw.dlog.cur > 3, "fail: death log typing (line %d at 0.7 s), frames median %.2f ms, worst %.2f ms" % [sw.dlog.cur if sw and sw.dlog else -1, log_ms[log_ms.size() / 2], log_ms[-1]])
	if OS.get_environment("RR_SHOTS") != "": yield(shoot_for(1.6), "completed")
	var k = InputEventKey.new(); k.scancode = KEY_R; k.pressed = true
	Input.parse_input_event(k)
	tag = "eyes"
	yield(wait(1.5), "completed") # (R held a while: must not give up the restarted run)
	k = InputEventKey.new(); k.scancode = KEY_R; k.pressed = false
	Input.parse_input_event(k)
	r = yield(watch("at_run", 8.0), "completed")
	check(at_run() and !Rhythia.has_meta("last_run"), "R on the death log -> restarted run in %.2f s (darkest %.3f, slowest %.0f ms)" % r)
	out("  after R: %s paused=%s ms=%s" % [get_tree().current_scene.filename, get_tree().paused, get_tree().current_scene.get_node("Game/Spawn").ms if get_tree().current_scene.has_node("Game/Spawn") else "?"])
	yield(wait(2.0), "completed")
	out("  2 s later: %s paused=%s ms=%s" % [get_tree().current_scene.filename, get_tree().paused, get_tree().current_scene.get_node("Game/Spawn").ms if get_tree().current_scene.has_node("Game/Spawn") else "?"])
	get_tree().current_scene.get_node("Game").end(Globals.END_FAIL)
	yield(wait(0.5), "completed")
	sw = get_tree().root.get_node_or_null("RRScreenSwap")
	out("  second fail: swap=%s dlog=%s scene=%s" % [sw != null, sw.dlog != null if sw else false, get_tree().current_scene.filename])
	k = InputEventKey.new(); k.scancode = KEY_SPACE; k.pressed = true
	Input.parse_input_event(k)
	k = InputEventKey.new(); k.scancode = KEY_SPACE; k.pressed = false
	Input.parse_input_event(k)
	tag = "skip"
	r = yield(watch("at_results", 10.0), "completed")
	check(at_results(), "key on the death log -> results in %.2f s (darkest %.3f, slowest %.0f ms)" % r)
	yield(wait(1.5), "completed")
	# 5. a failed replay: no death log
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	r = yield(watch("at_run", 12.0), "completed")
	yield(wait(1.0), "completed")
	Rhythia.replaying = true
	get_tree().current_scene.get_node("Game").end(Globals.END_FAIL)
	yield(get_tree(), "idle_frame")
	sw = get_tree().root.get_node_or_null("RRScreenSwap")
	check(sw and sw.dlog == null, "replay / autoplay fail: no death log")
	Rhythia.replaying = false
	r = yield(watch("at_results", 10.0), "completed")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
