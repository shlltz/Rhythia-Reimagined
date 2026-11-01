extends Node
# The pass zoom at the end of a map (hype/PassFx.gd): autoplays the last seconds of @@MAP1@@
# (start offset near the end) and records every frame from the last note to the results screen.
# Reports the slowest frame of the zoom (the old version read the screen back from the GPU: one
# 35-50 ms frame). RR_SHOTS=1 instead saves two pictures during the zoom (measuring is off then).
# Output: @@OUT@@/passzoom.txt (+ zoom_a.png, zoom_b.png)
const OUT = "@@OUT@@/passzoom.txt"
var last_us = 0
var frames = []
var capturing = false

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func _process(_d):
	OS.vsync_enabled = false
	Engine.target_fps = 0
	var u = OS.get_ticks_usec()
	if capturing and last_us > 0: frames.append((u - last_us) / 1000.0)
	last_us = u

func song(file):
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == file: return s
	return null

func shot(name):
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png("@@OUT@@/" + name)

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var t = 0.0
	while t < 30:
		yield(wait(0.25), "completed"); t += 0.25
		var sc = get_tree().current_scene
		if !sc or sc.name != "Menu": continue
		var tm = sc.get_node_or_null("TitleMenu")
		if tm and tm.visible:
			tm._close("")
			yield(wait(1.0), "completed")
		break
	var s = song("@@MAP1@@")
	Rhythia.select_song(s)
	Rhythia.start_offset = max(0, s.last_ms - 6000) # (the last six seconds)
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = ""
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var g = null
	var t0 = OS.get_ticks_msec()
	while OS.get_ticks_msec() - t0 < 60000 and !g:
		yield(get_tree(), "idle_frame")
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game") and sc.get_node("Game").has_node("Spawn") and sc.get_node("Game/Spawn").active: g = sc.get_node("Game")
	if !g:
		out("FAIL no game"); OS.kill(OS.get_process_id()); return
	var shots = OS.get_environment("RR_SHOTS") == "1"
	if !shots: # (from the last notes on: the frame where the map ends is the one that matters)
		yield(wait(0.5), "completed")
		frames = []; last_us = 0
		capturing = true
	while is_instance_valid(g) and !g.ending and OS.get_ticks_msec() - t0 < 90000: yield(get_tree(), "idle_frame")
	if !is_instance_valid(g):
		out("FAIL game gone before the end"); OS.kill(OS.get_process_id()); return
	out("ending: passed %s, hits %s, misses %s" % [str(g.passed), str(g.hits), str(g.misses)])
	if shots:
		yield(wait(0.35), "completed")
		yield(shot("zoom_a.png"), "completed")
		yield(wait(0.3), "completed")
		yield(shot("zoom_b.png"), "completed")
	while OS.get_ticks_msec() - t0 < 120000 and is_instance_valid(g): yield(get_tree(), "idle_frame")
	capturing = false # (stops before the menu scene loads: that frame is a scene change, not the zoom)
	if !shots:
		var f = frames.duplicate(); f.sort()
		out("last notes + zoom + fade: %d frames, slowest %.2f ms, then %.2f, %.2f; median %.2f ms" % [f.size(), f[-1], f[-2], f[-3], f[f.size() / 2]])
		out("PASS" if f[-1] < 25.0 else "SLOW (a frame over 25 ms)")
	out("== done")
	OS.kill(OS.get_process_id())
