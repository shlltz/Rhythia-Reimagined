extends Node
# Replay analyzer (ReplayAnalyzer.gd): watches a copy of RR_REPLAY_FILE (a replay of @@MAP1@@) in the
# replay viewer, then checks the analysis came in, the running Delta / Avg / histogram, and saves a
# screenshot mid-replay. Output: @@OUT@@/analyzer.txt + analyzer.png
const OUT = "@@OUT@@/analyzer.txt"

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = OS.get_environment("RR_FULL") == "1"
	call_deferred("run")

func run():
	if get_tree().root.has_meta("rr_an_started"): return
	get_tree().root.set_meta("rr_an_started", true)
	Directory.new().remove(OUT)
	yield(wait(22.0), "completed")
	var src = OS.get_environment("RR_REPLAY_FILE")
	var dst = Globals.p("user://rr_analyzer_test.sspre")
	Directory.new().copy(src, dst)
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	out("map %s, replay copied %s" % [Rhythia.selected_song.name, File.new().file_exists(dst)])
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = dst
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	yield(wait(18.0), "completed")
	var an = null
	var stack = [get_tree().root]
	while !stack.empty():
		var n = stack.pop_back()
		if n.get_script() and str(n.get_script().resource_path).ends_with("ReplayAnalyzer.gd"): an = n
		for c in n.get_children(): stack.append(c)
	if !an:
		out("FAIL no analyzer in the replay viewer")
	else:
		var hs = 0
		for c in an.hist: hs += c
		out(("PASS" if an.st != null else "FAIL") + " analysis in: state '%s', notes judged %d, song %.0f ms" % [an.state_txt, an.st.per_note.size() if an.st else 0, an.spawn.ms])
		out(("PASS" if hs > 0 and an.avg >= 0 else "FAIL") + " delta %.1f ms, avg %.2f ms, histogram %s (%d hits)" % [an.last_delta, an.avg, str(an.hist), hs])
		out("overlay visible %s, samples %d" % [an.geo.visible, an.rp.cur_t.size() if an.rp else 0])
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png("@@OUT@@/analyzer.png")
	out("== done")
	OS.kill(OS.get_process_id())
