extends Node
# Replay Studio (replay/ReplayStats.gd): a real run is recorded with a cursor this test drives - it
# sits AIM off the centre of the next note, every 4th isolated note it arrives LATE ms after the
# note's time, from HIT_UNTIL on it stays away until the run fails. The replay is then parsed and
# analysed offline: score / hits / misses / max combo must equal what the game counted, the
# reconstructed aim and delays must match what the driver did. Bad files are refused cleanly.
# Map: @@MAP1@@. Output @@OUT@@/replay_studio.txt + rs_*.png
const OUT = "@@OUT@@/replay_studio.txt"
const AIM = Vector2(0.2, 0.1)   # grid units (x right, y down)
const LATE = 40.0
var HIT_UNTIL = 15000.0
const HOLD = 30.0
var passed = 0
var failed = 0
var drive = false
var game = null
var late_ids = {}               # note id -> true (the notes hit late on purpose)
var arrive = {}                 # late note id -> [ms after its time the driver moved onto it, frame ms]
var clock_min = 1e9
var clock_max = -1e9
var clock_log = []

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

func shot(n): # (after the frame is drawn: reading the texture earlier can return an old frame)
	if OS.window_minimized: # (a minimized window isn't drawn: its texture is an old frame)
		out("  (window minimized: no %s screenshot)" % n)
		yield(get_tree(), "idle_frame")
		return
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/rs_" + n + ".png")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func _process(_d):
	if !drive or !is_instance_valid(game) or game.ending: return
	var sp = game.get_node("Spawn")
	var cur = sp.get_node("Cursor")
	var g = Vector2(-0.3, -0.3) # (grid units; parked in a corner once HIT_UNTIL is reached)
	if sp.ms < HIT_UNTIL:
		for i in sp.notes.size(): # (each note held until HOLD ms after its time, like a follow-through)
			var n = sp.notes[i]
			if sp.ms >= n[1] + HOLD + (LATE if late_ids.has(i) else 0.0) and n[2] != Globals.NSTATE_ACTIVE: continue
			var ng = Vector2(n[0].x, -n[0].y)
			if late_ids.has(i) and sp.ms < n[1] + LATE:
				g = Vector2(ng.x + (1.0 if ng.x < 1.5 else -1.0), ng.y) # (one cell over: outside its box)
			else:
				g = ng + AIM
				if late_ids.has(i) and !arrive.has(i): arrive[i] = [sp.ms - n[1], get_process_delta_time() * 1000.0]
			break
	cur.transform.origin = Vector3(g.x, -g.y, cur.transform.origin.z)
	cur.rpos = g
	var d = sp.rms - sp.ms
	clock_min = min(clock_min, d)
	clock_max = max(clock_max, d)
	if clock_log.size() < 4000: clock_log.append([sp.rms, sp.ms])

func _play():
	var t = 0.0
	while t < 30 and !game:
		yield(wait(0.1), "completed"); t += 0.1
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"): game = sc.get_node("Game")
	drive = true
	t = 0.0
	while t < 70 and is_instance_valid(game) and !game.ending:
		yield(get_tree(), "idle_frame")
		t += get_process_delta_time()
	drive = false
	t = 0.0
	while t < 20 and !get_tree().root.has_node("Menu/ResultsScreen"):
		yield(wait(0.25), "completed"); t += 0.25
	yield(wait(0.5), "completed")

func _all(n:Node) -> Array:
	var out = [n]
	for c in n.get_children(): out += _all(c)
	return out

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var S = load("res://mods/replay/ReplayStats.gd")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	Rhythia.select_song(song)
	Rhythia.set("mod_nofail", false)
	Rhythia.set("record_replays", true)
	Rhythia.start_offset = 0
	# late notes: every 4th note with no other note within 150 ms either side (so arriving late
	# can't be confused with the neighbours)
	var ns = song.read_notes().duplicate(true)
	ns.sort_custom(S, "_by_time")
	for i in range(1, ns.size() - 1):
		if i % 4 == 1 and ns[i][2] < HIT_UNTIL - 500 and ns[i][2] - ns[i - 1][2] > 150 and ns[i + 1][2] - ns[i][2] > 150: late_ids[i] = true
	out("late on purpose: %d notes" % late_ids.size())
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	yield(_play(), "completed")
	var t = 0.0
	var rs = get_tree().root.get_node_or_null("Menu/ResultsScreen")
	var run = rs.run if rs and rs.get("run") is Dictionary else {}
	out("game: end %s score %d hits %d misses %d total %d max combo %d pauses %d, replay %s" % [run.get("end_type"), run.get("score", 0), run.get("hits", 0), run.get("misses", 0), run.get("total", 0), run.get("combo", 0), run.get("pauses", 0), run.get("replay_path", "")])
	out("game clock: rms - ms from %.1f to %.1f" % [clock_min, clock_max])
	var path = run.get("replay_path", "")
	ok("the run recorded a replay", path != "" and File.new().file_exists(path))
	# ---- offline parse + analysis
	var t0 = OS.get_ticks_msec()
	var rp = S.parse(path)
	ok("parsed", rp.ok, rp.error)
	if !rp.ok:
		out("== totals: %d passed, %d failed" % [passed, failed])
		OS.kill(OS.get_process_id())
		return
	var opts = S.opts_of(rp)
	var st = S.analyse(rp, song.read_notes(), opts)
	out("analysed in %d ms: %d cursor samples, %d judged, score %d, hits %d, misses %d, max combo %d, aim mean (%.3f, %.3f), aim error %.3f, delay median %.1f ms (%d known, %d unknown), travelled %.1f, avg speed %.2f/s" % [OS.get_ticks_msec() - t0, rp.cur_t.size(), st.judged, st.score, st.hits, st.misses, st.max_combo, st.aim_mean.x, st.aim_mean.y, st.aim_err, st.delay_median, st.delay_known, st.delay_unknown, st.travelled, st.avg_speed])
	ok("same score as the game", st.score == run.get("score", -1), "%d vs %d" % [st.score, run.get("score", -1)])
	ok("same hits / misses", st.hits == run.get("hits", -1) and st.misses == run.get("misses", -1))
	ok("same judged total", st.judged == run.get("total", -1))
	ok("same max combo", st.max_combo == run.get("combo", -1), "%d vs %d" % [st.max_combo, run.get("combo", -1)])
	ok("the replay's mods / hit window read back", opts.speed == 1.0 and opts.hitbox > 1.0 and opts.hit_window > 0, str(opts.speed) + " " + str(opts.hitbox) + " " + str(opts.hit_window))
	# aim: on-time hits sit AIM off the centre
	var on_aim = 0
	var on_n = 0
	var late_ok = 0
	var late_n = 0
	var on_delay_ok = 0
	var id_of_ms = {}
	for i in ns.size(): id_of_ms[ns[i][2]] = i
	for pn in st.per_note:
		if !pn[1]: continue
		var i = id_of_ms.get(int(pn[0]), -1)
		if late_ids.has(i):
			late_n += 1
			var av = arrive.get(i, [LATE, 0.0])
			out("  late note %d at %d: moved on %.1f ms after (frame %.1f), reconstructed %.1f (sample spacing %.1f)" % [i, pn[0], av[0], av[1], pn[4], pn[5]])
			if pn[4] >= av[0] - 1.0 and pn[4] <= min(av[0] + av[1] + pn[5] + 1.0, opts.hit_window): late_ok += 1
		elif pn[0] < HIT_UNTIL - 300 and i > 0 and ns[i][2] - ns[i - 1][2] >= 100: # (held still across the note time)
			on_n += 1
			if pn[4] < 0 or pn[4] > pn[5] + 1.0: out("  on-time note %d at %d: delay %.1f, resolution %.1f" % [i, pn[0], pn[4], pn[5]])
			if Vector2(pn[2], pn[3]).distance_to(AIM) < 0.05: on_aim += 1
			if pn[4] >= 0 and pn[4] <= pn[5] + 1.0: on_delay_ok += 1
	out("cursor sampled every %.1f ms (median)" % st.sample_ms)
	ok("aim: hits the cursor sat still on are reconstructed AIM off centre", on_n > 10 and on_aim == on_n, "%d / %d" % [on_aim, on_n])
	ok("delay: and within its sample spacing of the note time", on_n > 10 and on_delay_ok == on_n, "%d / %d" % [on_delay_ok, on_n])
	ok("delay: the late notes come out as late as the driver moved (+ a frame + their sample spacing)", late_n > 3 and late_ok == late_n, "%d / %d" % [late_ok, late_n])
	var rows_ok = st.rows.size() == st.judged and st.rows[st.rows.size() - 1][3] == st.score and st.rows[st.rows.size() - 1][1] == false
	ok("timeline rows: one per judgement, ends on the fail's misses", rows_ok)
	var heat_sum = 0.0
	for h in st.heat: heat_sum += h
	ok("heatmap and speed curve have data", heat_sum > 1000.0 and st.speed_curve.size() > 10)
	var worst = 0.0
	for cl in clock_log:
		if cl[1] > 0 and cl[0] <= st.length_rms: worst = max(worst, abs(S._sms(st.sms_at, cl[0]) - cl[1]))
	ok("the rebuilt song clock is the game's (within 2 ms)", worst <= 2.0, "worst %.1f ms over %d frames" % [worst, clock_log.size()])
	var r12 = S.rms_of(st, 12000.0)
	ok("song time -> replay time (watch from here)", r12 > 12000.0 and abs(S._sms(st.sms_at, r12) - 12000.0) < 1.0, r12)
	# ---- bad files
	var f = File.new()
	var tmp = Globals.p("user://rr_studio_test.sspre")
	var src = File.new()
	src.open(path, File.READ)
	var all = src.get_buffer(src.get_len())
	src.close()
	f.open(tmp, File.WRITE)
	f.store_buffer(all.subarray(0, all.size() / 2))
	f.close()
	var cut = S.parse(tmp)
	ok("a cut replay is refused with a reason", !cut.ok and cut.error != "", cut.error)
	f.open(tmp, File.WRITE)
	f.store_string("this is not a replay at all, just text")
	f.close()
	var junk = S.parse(tmp)
	ok("a non-replay is refused", !junk.ok and junk.error == "not a replay file", junk.error)
	Directory.new().remove(tmp)
	# ---- a second, shorter run; the studio opened from its results screen, compared with the best
	HIT_UNTIL = 8000.0
	late_ids = {}
	game = null
	Rhythia.select_song(song)
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	yield(_play(), "completed")
	rs = get_tree().root.get_node_or_null("Menu/ResultsScreen")
	var run2 = rs.run if rs and rs.get("run") is Dictionary else {}
	ok("second run recorded too", run2.get("replay_path", "") != "" and run2.get("score", 0) < run.get("score", 0), "%d vs %d" % [run2.get("score", 0), run.get("score", 0)])
	var has_btn = false
	for b in _all(rs):
		if b is Button and b.text == "Analyse": has_btn = true
	ok("results screen: Analyse button", has_btn)
	rs._analyse()
	var studio = get_tree().root.get_node_or_null("Menu/ReplayStudio")
	t = 0.0
	while t < 10 and (!studio or studio.A == null):
		yield(wait(0.1), "completed"); t += 0.1
	ok("studio opens on the run just played", studio and studio.A and studio.A.st.score == run2.get("score", -1), studio.A.st.score if studio and studio.A else "-")
	ok("its compare list has the other replay", studio and studio.cmp_paths.size() == 2 and studio.cmp_paths[1] == path)
	studio._cmp_best()
	t = 0.0
	while t < 10 and studio.B == null:
		yield(wait(0.1), "completed"); t += 0.1
	ok("best of this map = the first run", studio.B and studio.B.st.score == run.get("score", -1) and studio.B.of == 1)
	ok("miss list filled", studio.miss_ms.size() == studio.A.st.misses and studio.miss_list.get_item_count() == studio.A.st.misses)
	studio._jump_miss(1)
	ok("N picks the first miss", studio.pick_ms == studio.miss_ms[0] and !studio.btn_from.disabled)
	yield(wait(0.5), "completed")
	yield(shot("studio"), "completed")
	var want = S.rms_of(studio.A.st, max(studio.pick_ms - 2000.0, studio.A.st.song_from + 1.0))
	studio._watch(true)
	game = null
	t = 0.0
	while t < 30 and !game:
		yield(wait(0.1), "completed"); t += 0.1
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"): game = sc.get_node("Game")
	t = 0.0
	var seeked = false
	var got = 0.0
	while t < 15 and is_instance_valid(game) and !seeked:
		yield(get_tree(), "idle_frame")
		t += get_process_delta_time()
		got = game.get_node("Spawn").rms
		seeked = !Engine.has_meta("rr_replay_seek") and got >= want - 50.0
	ok("WATCH FROM opens the viewer at the picked time (2 s before the miss)", seeked and got < want + 1500.0, "replay at %.0f, wanted %.0f" % [got, want])
	yield(wait(1.0), "completed")
	yield(shot("viewer"), "completed")
	# ---- a 2 s clip of the first run: GIF + MP4 (ffmpeg is on PATH here)
	for n in _all(get_tree().root):
		if n.get_script() and str(n.get_script().resource_path).ends_with("ReplayViewer.gd"):
			n.leave()
			break
	t = 0.0
	while t < 20 and !get_tree().root.has_node("Menu"):
		yield(wait(0.25), "completed"); t += 0.25
	yield(wait(2.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	if menu.has_node("ResultsScreen"): menu.get_node("ResultsScreen").queue_free()
	studio = load("res://mods/replay/ReplayStudio.gd").open(menu, path)
	t = 0.0
	while t < 10 and studio.A == null:
		yield(wait(0.1), "completed"); t += 0.1
	var ff = load("res://mods/replay/ClipExport.gd").has_ffmpeg()
	ok("ffmpeg found on PATH (this machine has it)", ff)
	var req = studio.clip_request(5000.0, 2000.0, ff)
	ok("clip request in replay time", req.size() > 0 and abs(req.to_rms - req.from_rms - 2000.0) < 0.5 and req.audio_ok)
	OS.window_minimized = false # (a minimized window isn't drawn: no frames to record)
	Engine.set_meta("rr_clip", req)
	if Engine.has_meta("rr_clip_result"): Engine.remove_meta("rr_clip_result")
	var t_clip = OS.get_ticks_msec()
	studio._watch(false)
	t = 0.0
	while t < 90 and !Engine.has_meta("rr_clip_result"):
		yield(wait(0.25), "completed"); t += 0.25
	var cres = Engine.get_meta("rr_clip_result") if Engine.has_meta("rr_clip_result") else {"error": "no result in 90 s"}
	out("clip: %s in %.1f s" % [str(cres), (OS.get_ticks_msec() - t_clip) / 1000.0])
	ok("clip written", !cres.has("error"), cres.get("error", ""))
	if cres.has("gif"):
		var po = []
		OS.execute("ffprobe", ["-v", "error", "-count_frames", "-select_streams", "v:0", "-show_entries", "stream=nb_read_frames,width,height", "-of", "csv=p=0", ProjectSettings.globalize_path(cres.gif)], true, po, true)
		var parts = str(po[0] if po.size() > 0 else "").strip_edges().split(",")
		ok("GIF: 400 x 225, 2 s at 20 fps (40 frames)", parts.size() == 3 and parts[0] == "400" and parts[1] == "225" and abs(int(parts[2]) - 40) <= 1, str(parts))
	if cres.has("mp4"):
		var po2 = []
		OS.execute("ffprobe", ["-v", "error", "-count_frames", "-show_entries", "stream=codec_type,nb_read_frames:format=duration", "-of", "csv=p=0", ProjectSettings.globalize_path(cres.mp4)], true, po2, true)
		var txt = str(po2[0] if po2.size() > 0 else "")
		out("mp4 probe: %s" % txt.replace("\n", " | "))
		ok("MP4: 60 video frames + the song's audio", txt.find("video,60") >= 0 or txt.find("video,59") >= 0 or txt.find("video,61") >= 0, txt)
		ok("MP4 has sound", cres.get("mp4_audio", false) and txt.find("audio") >= 0)
	ok("frame folder cleaned up", !Directory.new().dir_exists("user://clips/%s_frames" % req.name))
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
