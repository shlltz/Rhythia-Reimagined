extends Node
# Script cost per gameplay frame, by script and by NoteManager section. Needs the timing patches:
#   RR_SWAPS=tests/multiplayer/swaps/prof.py py -3 mpbench.py share "P=ProfProbe.gd" 200 "P=<map>"
# Autoplays @@MAP1@@ (vsync off, uncapped), measures RR_PROF_SECONDS (default 30) from 4 s into the
# run. Output: @@OUT@@/prof.txt (usec per frame, calls per frame, usec per call).
const OUT = "@@OUT@@/prof.txt"
var frames = 0
var counting = false
var last_us = 0
var ftot = 0.0

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
	if counting:
		frames += 1
		if last_us > 0: ftot += u - last_us
	last_us = u

func song(file):
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == file: return s
	return null

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
	var secs = float(OS.get_environment("RR_PROF_SECONDS")) if OS.get_environment("RR_PROF_SECONDS") != "" else 30.0
	Rhythia.select_song(song("@@MAP1@@"))
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
	yield(wait(4.0), "completed")
	while is_instance_valid(g) and int(g.get("hits")) < 20 and OS.get_ticks_msec() - t0 < 90000: # (start where the notes are)
		yield(wait(0.25), "completed")
	var h0 = int(g.get("hits")) if is_instance_valid(g) else 0
	Engine.set_meta("rr_prof", {})
	frames = 0; ftot = 0.0; last_us = 0
	counting = true
	yield(wait(secs), "completed")
	counting = false
	var d = Engine.get_meta("rr_prof").duplicate(true)
	Engine.remove_meta("rr_prof")
	var hits = (int(g.get("hits")) - h0) if is_instance_valid(g) else -1
	out("== prof @@NAME@@: %d frames, frame mean %.3f ms, hits in the window %s" % [frames, ftot / max(frames - 1, 1) / 1000.0, str(hits)])
	var keys = d.keys()
	var rows = []
	for k in keys: rows.append([d[k][0], k])
	rows.sort_custom(self, "_desc")
	for r in rows:
		var k = r[1]
		out("%-18s %8.2f us/frame  %6.2f calls/frame  %8.2f us/call" % [k, float(d[k][0]) / frames, float(d[k][1]) / frames, float(d[k][0]) / max(d[k][1], 1)])
	out("== done")
	OS.kill(OS.get_process_id())

func _desc(a, b): return a[0] > b[0]
