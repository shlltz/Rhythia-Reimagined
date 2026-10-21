extends Node
# Retry from the fail point (replay/Checkpoint.gd). The test drives the cursor itself: it sits on the
# next note until HIT_UNTIL ms of map time, then parks in a corner, so the run fails at a fixed note.
# The resumed run uses the same rule, so if the restored state is exact it must fail at the same note
# with the same score / hits / misses / max combo. Also: snapshots are at exact points, the resumed
# run starts at the snapshot's note with its state, music in sync, no replay recorded, no personal
# best written, RESUMED shown, Start From back to the player's value afterwards.
# Map: @@MAP1@@. Output @@OUT@@/checkpoint.txt + ck_*.png
const OUT = "@@OUT@@/checkpoint.txt"
const HIT_UNTIL = 12000.0
var passed = 0
var failed = 0
var game = null
var drive = false
var moved_by_mouse = false

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
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/ck_" + n + ".png")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

var last_set = null
func _process(_d):
	if !drive or !is_instance_valid(game) or game.ending: return
	var sp = game.get_node("Spawn")
	var cur = sp.get_node("Cursor")
	if last_set != null and cur.transform.origin.distance_to(last_set) > 0.001: moved_by_mouse = true
	var target = Vector2(-5, -5) # (parked: off every note)
	if sp.ms < HIT_UNTIL:
		for n in sp.notes:
			if n[2] == Globals.NSTATE_ACTIVE:
				target = n[0]
				break
	cur.transform.origin = Vector3(target.x, target.y, cur.transform.origin.z)
	cur.rpos = Vector2(target.x, -target.y)
	last_set = cur.transform.origin

func play_until_end():
	var t = 0.0
	game = null
	while t < 30 and !game:
		yield(wait(0.1), "completed"); t += 0.1
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"): game = sc.get_node("Game")
	if !game: return
	last_set = null
	drive = true
	t = 0.0
	var next_log = 0.0
	while t < 60 and is_instance_valid(game) and !game.ending:
		yield(get_tree(), "idle_frame")
		t += get_process_delta_time()
		if t > next_log:
			next_log += 2.0
			var sp = game.get_node("Spawn")
			out("  t %.1f s: ms %d active %s hits %d misses %d energy %.1f" % [t, sp.ms, sp.active, game.hits, game.misses, game.energy])
	out("  ended: valid %s ending %s, checkpoint node %s, last_run %s" % [is_instance_valid(game), game.ending if is_instance_valid(game) else "-", is_instance_valid(game) and game.has_node("RRCheckpoint"), Rhythia.has_meta("last_run")])
	yield(wait(1.5), "completed")
	out("  scene now: %s, last_run %s" % [get_tree().current_scene.filename if get_tree().current_scene else "none", Rhythia.has_meta("last_run")])
	drive = false
	t = 0.0
	while t < 20 and !get_tree().root.has_node("Menu/ResultsScreen"):
		yield(wait(0.25), "completed"); t += 0.25

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	Rhythia.select_song(song)
	Rhythia.set("mod_nofail", false)
	Rhythia.set("record_replays", true)
	Rhythia.start_offset = 0
	var all_notes = song.read_notes()
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	yield(play_until_end(), "completed")
	var run1 = _last_run()
	ok("first run failed", run1.get("end_type", -1) == Globals.END_FAIL, run1.get("end_type"))
	out("first run: fail at %d ms, score %d, hits %d, misses %d, max combo %d" % [run1.get("position", 0), run1.get("score", 0), run1.get("hits", 0), run1.get("misses", 0), run1.get("combo", 0)])
	var offer = run1.get("resume")
	ok("fail point offered", offer is Dictionary, offer)
	if !(offer is Dictionary):
		out("== totals: %d passed, %d failed" % [passed, failed])
		OS.kill(OS.get_process_id())
		return
	var snap = offer.snap
	out("snapshot: at %d ms (fail %d ms): score %d combo %d hits %d misses %d energy %.1f" % [snap.at, offer.fail_ms, snap.score, snap.combo, snap.hits, snap.misses, snap.energy])
	ok("snapshot at least 2 s before the fail", snap.at <= offer.fail_ms - 2000)
	var before = 0
	for n in all_notes:
		if n[2] < snap.at: before += 1
	ok("snapshot is exact: every note before it judged, none after", int(snap.total) == before and int(snap.hits + snap.misses) == before, "%d judged, %d notes before" % [snap.total, before])
	var gap_ok = true
	for n in all_notes:
		if n[2] < snap.at and n[2] > snap.at - 55: gap_ok = false
	ok("snapshot sits in a gap longer than the hit window", gap_ok)
	var rs = get_tree().root.get_node_or_null("Menu/ResultsScreen")
	ok("results screen has the button", rs != null and rs.find_node("*", true, false) != null)
	var has_btn = false
	if rs:
		for b in _all(rs):
			if b is Button and b.text == "From fail point": has_btn = true
	ok("\"Retry from fail point\" button", has_btn)
	shot("results")
	var bests = Globals.p("user://bests/" + song.id)
	var md5_best = File.new().get_md5(bests) if File.new().file_exists(bests) else ""
	var replays_before = _count(Globals.p("user://replays"))
	rs._retry_resume()
	# ---- the resumed run
	var t = 0.0
	game = null
	while t < 30 and !game:
		yield(wait(0.05), "completed"); t += 0.05
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"): game = sc.get_node("Game")
	ok("resumed run started", game != null)
	if game:
		ok("state restored: score / combo / hits / misses / health", game.score == int(snap.score) and game.combo == int(snap.combo) and int(game.hits) == int(snap.hits) and int(game.misses) == int(snap.misses) and abs(game.energy - snap.energy) < 0.001, "%d %d %d %d %.1f" % [game.score, game.combo, game.hits, game.misses, game.energy])
		ok("starts at the snapshot's note (Start From)", Rhythia.start_offset == snap.at)
		var sp = game.get_node("Spawn")
		yield(wait(0.5), "completed")
		var first_ms = sp.notes[0][1] if sp.notes.size() > 0 else -1
		ok("earlier notes not replayed", first_ms >= snap.at and sp.notes.size() == all_notes.size() - before, "first %d, %d notes" % [first_ms, sp.notes.size()])
		ok("no replay recorded for a resumed run", !Rhythia.replay.recording)
		last_set = null
		drive = true
		# music in sync once it plays
		var worst = 0.0
		var n_s = 0
		var tt = 0.0
		while tt < 8.0 and is_instance_valid(game) and !game.ending:
			yield(get_tree(), "idle_frame")
			tt += get_process_delta_time()
			var mu = sp.get_node("Music")
			if mu.playing and sp.ms > snap.at + 300:
				var d = abs(mu.get_playback_position() * 1000.0 - (sp.ms + Rhythia.music_offset))
				worst = max(worst, d)
				n_s += 1
		ok("music in sync after the seek (within 80 ms)", n_s > 10 and worst < 80.0, "%d samples, worst %.0f ms" % [n_s, worst])
		shot("resumed")
	yield(play_until_end(), "completed")
	var run2 = _last_run()
	out("resumed run: fail at %d ms, score %d, hits %d, misses %d, max combo %d" % [run2.get("position", 0), run2.get("score", 0), run2.get("hits", 0), run2.get("misses", 0), run2.get("combo", 0)])
	if moved_by_mouse: out("  (the real mouse moved during the test: the comparison below may not hold)")
	ok("resumed run is marked resumed", run2.get("resumed", false))
	ok("same inputs -> same fail note and the same numbers (exact state)", abs(run2.get("position", 0) - run1.get("position", 0)) < 40 and run2.get("score", -1) == run1.get("score", -2) and run2.get("hits", -1) == run1.get("hits", -2) and run2.get("misses", -1) == run1.get("misses", -2) and run2.get("combo", -1) == run1.get("combo", -2))
	ok("personal best untouched", (File.new().get_md5(bests) if File.new().file_exists(bests) else "") == md5_best)
	ok("no new replay file", _count(Globals.p("user://replays")) == replays_before)
	ok("Start From back to the player's value", Rhythia.start_offset == 0)
	ok("RESUMED status on the results screen", _status_text().find("resumed") != -1, _status_text())
	ok("a resumed run can resume again from the same point", run2.get("resume") is Dictionary and run2.resume.snap.at == snap.at and run2.resume.prev_offset == 0)
	shot("results2")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())

# the run the results screen shows (the menu takes Rhythia's "last_run" meta when it opens it)
func _last_run() -> Dictionary:
	var rs = get_tree().root.get_node_or_null("Menu/ResultsScreen")
	return rs.run if rs and rs.get("run") is Dictionary else {}

func _status_text() -> String:
	var rs = get_tree().root.get_node_or_null("Menu/ResultsScreen")
	if !rs: return ""
	return str(rs._status()[0]).to_lower()

func _all(n:Node) -> Array:
	var out = [n]
	for c in n.get_children(): out += _all(c)
	return out

func _count(d:String) -> int:
	var dir = Directory.new()
	if dir.open(d) != OK: return 0
	var n = 0
	dir.list_dir_begin(true, true)
	var f = dir.get_next()
	while f != "":
		n += 1
		f = dir.get_next()
	dir.list_dir_end()
	return n
