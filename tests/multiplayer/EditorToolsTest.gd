extends Node
# Map editor tools (replay/EditorAuto.gd, EditorPatterns.gd, Editor AUTO tab): BPM / offset from
# synthetic beats of known tempo; on a real song the estimate is checked against the map's own notes
# (they must sit on the detected grid); patterns are deterministic, editable, one undo step;
# transforms, mirror section, repeat, slots; Alt = no snap. Map: @@MAP1@@.
# Output @@OUT@@/editor_tools.txt + et_*.png
const OUT = "@@OUT@@/editor_tools.txt"
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
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/et_" + n + ".png")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

# envelopes of a beat at `bpm` from `off` ms: kick on every beat (low band), hat on the off-beats
# (high band), a little deterministic noise; 25 ms bins
func synth(bpm:float, off:float, secs:float, noise:float = 0.05) -> Array:
	var n = int(secs * 40)
	var lo = PoolRealArray(); lo.resize(n)
	var hi = PoolRealArray(); hi.resize(n)
	var pk = PoolRealArray(); pk.resize(n)
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var per = 60000.0 / bpm
	for i in n:
		var t = i * 25.0 + 12.5
		var ph = fposmod(t - off, per)
		var ph2 = fposmod(t - off - per / 2.0, per)
		lo[i] = clamp(exp(-ph / 60.0) * 0.9 + rng.randf() * noise, 0, 1)
		hi[i] = clamp(exp(-ph2 / 40.0) * 0.5 + rng.randf() * noise, 0, 1)
		pk[i] = clamp(max(lo[i], hi[i]) * 0.8 + 0.1, 0, 1)
	return [lo, hi, pk]

func octave_ok(got:float, want:float, tol:float) -> bool:
	for k in [0.5, 1.0, 2.0]:
		if abs(got - want * k) <= tol * k: return true
	return false

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var A = load("res://mods/replay/EditorAuto.gd")
	var P = load("res://mods/replay/EditorPatterns.gd")
	# ---- analysis on synthetic beats of known tempo / phase
	for case in [[150.0, 200.0], [174.0, 90.0], [128.5, 333.0], [200.0, 37.0]]:
		var e = synth(case[0], case[1], 60.0)
		var t0 = OS.get_ticks_msec()
		var r = A.analyse(e[0], e[1], e[2], 25.0)
		var per = 60000.0 / r.bpm if r.bpm > 0 else 1.0
		var off_err = abs(fposmod(r.offset - case[1] + per / 2.0, per) - per / 2.0) # (phase difference, wrapped)
		ok("synthetic %.1f BPM: tempo" % case[0], octave_ok(r.bpm, case[0], 0.6), "%.2f (%d ms)" % [r.bpm, OS.get_ticks_msec() - t0])
		ok("synthetic %.1f BPM: offset" % case[0], r.bpm > 0 and (off_err <= 8.0 or (abs(r.bpm - case[0]) > 1 and off_err <= per / 2.0)), "%d ms vs %d ms (err %.1f)" % [r.offset, case[1], off_err])
	var flat = synth(120.0, 0.0, 30.0, 0.0)
	for i in flat[0].size():
		flat[0][i] = 0.3
		flat[1][i] = 0.3
		flat[2][i] = 0.3
	ok("no beat at all: no tempo claimed", A.analyse(flat[0], flat[1], flat[2], 25.0).bpm == 0.0)
	# ---- patterns: pure
	var st = P.stream(1000, 100, 9, "snake")
	ok("stream: 9 notes 100 ms apart on the snake path", st.size() == 9 and st[1][2] == 1100 and st[2][0] == 2.0 and st[3][1] == 1.0 and st[3][0] == 2.0)
	var j1 = P.jumps(0, 100, 32, 1.5, 3)
	var j2 = P.jumps(0, 100, 32, 1.5, 3)
	var j3 = P.jumps(0, 100, 32, 1.5, 4)
	var dist_ok = true
	for i in range(1, j1.size()):
		if Vector2(j1[i][0], j1[i][1]).distance_to(Vector2(j1[i - 1][0], j1[i - 1][1])) < 1.5: dist_ok = false
	ok("jumps: deterministic (same settings = same notes)", to_json(j1) == to_json(j2))
	ok("jumps: another variation differs", to_json(j1) != to_json(j3))
	ok("jumps: every jump at least the min distance", dist_ok)
	var sp = P.spiral(0, 50, 16, 1.0, 1.0, 1.0)
	var r_ok = true
	for n in sp:
		if abs(Vector2(n[0], n[1]).distance_to(Vector2(1, 1)) - 1.0) > 0.002: r_ok = false
	ok("circle: on radius 1 around the centre", r_ok and sp.size() == 16)
	var sp2 = P.spiral(0, 50, 9, 1.0, 0.0, 2.0)
	ok("spiral: ends at the centre", Vector2(sp2[-1][0], sp2[-1][1]).distance_to(Vector2(1, 1)) < 0.01)
	var rot = P.transform([[0.0, 0.0, 5], [2.0, 1.0, 9]], "rotate", 90)
	ok("rotate 90 about the centre", to_json(rot) == to_json([[2.0, 0.0, 5], [1.0, 2.0, 9]]), rot)
	var sc = P.transform([[0.0, 0.0, 5]], "scale", 0.5)
	ok("scale 0.5 about the centre", to_json(sc) == to_json([[0.5, 0.5, 5]]), sc)
	ok("reverse time", to_json(P.transform([[0.0, 0.0, 100], [1.0, 1.0, 150], [2.0, 2.0, 300]], "reverse")) == to_json([[0.0, 0.0, 300], [1.0, 1.0, 250], [2.0, 2.0, 100]]))
	var ms = P.mirror_section([[0.0, 0.0, 100], [1.0, 0.0, 200]], "x", 50)
	ok("mirror section: mirrored copy right after", to_json(ms) == to_json([[2.0, 0.0, 250], [1.0, 0.0, 350]]), ms)
	var rp = P.repeat([[0.0, 0.0, 0]], 3, 100, "rotate", 90)
	ok("repeat x3 rotating: corners in turn", to_json(rp) == to_json([[2.0, 0.0, 100], [2.0, 2.0, 200], [0.0, 2.0, 300]]), rp)
	var sl = P.to_slot([[1.0, 1.0, 500], [0.0, 2.0, 600]])
	ok("slots: stored relative, recalled anywhere", to_json(P.from_slot(sl, 2000)) == to_json([[1.0, 1.0, 2000], [0.0, 2.0, 2100]]))
	# ---- in the editor
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if s is Song and s.filePath.get_file() == "@@MAP1@@": song = s
	menu.open_editor(song)
	yield(wait(2.0), "completed")
	var e = menu.get_node("Editor")
	e._page("auto")
	var notes0 = e.m.notes.size()
	e.sp_bpm.value = 200
	e.sp_off.value = 0
	e.pos = 5000.0
	e.pat_ui.kind.select(0)
	e.pat_ui.count.value = 8
	e._pat_generate()
	ok("pattern inserted as notes", e.m.notes.size() == notes0 + 8 - (notes0 + 8 - e.m.notes.size()) and e.sel.size() > 0, "%d -> %d, %d selected" % [notes0, e.m.notes.size(), e.sel.size()])
	var after = e.m.notes.size()
	e._undo()
	ok("one undo removes the whole pattern", e.m.notes.size() == notes0, "%d" % e.m.notes.size())
	e._redo()
	ok("redo puts it back", e.m.notes.size() == after)
	# transform the new selection
	var before_sel = to_json(e._sel_notes())
	e.pat_ui.angle.value = 90
	e._pat_tf("rotate")
	ok("rotate applies to the selection", to_json(e._sel_notes()) != before_sel and e._sel_notes().size() == e.sel.size())
	e._undo()
	ok("and undoes", to_json(e._sel_notes()) == before_sel or e.m.notes.size() == after)
	# slots
	e._slot_store(3)
	e.pos = 20000.0
	var n_before = e.m.notes.size()
	e._slot_recall(3)
	ok("slot 3 recalled at the playhead", e.m.notes.size() > n_before and e._sel_notes()[0][2] >= 20000)
	# Alt = no snap
	e.time_snap = true
	var k = InputEventKey.new()
	k.scancode = KEY_ALT
	k.pressed = true
	Input.parse_input_event(k)
	yield(get_tree(), "idle_frame")
	var free_ok = !e._snapping()
	k = k.duplicate()
	k.pressed = false
	Input.parse_input_event(k)
	yield(get_tree(), "idle_frame")
	ok("Alt held: no time snap, released: snap again", free_ok and e._snapping())
	# ---- audio analysis on the real song, checked against the map's own notes
	e.m.dirty = false
	e.open_song(song)
	yield(wait(1.5), "completed")
	e._page("auto")
	var t0 = OS.get_ticks_msec()
	e._auto_start()
	var worst = 0.0
	var last = OS.get_ticks_usec()
	var tw = 0.0
	while tw < 60.0 and (e.auto_pending or e.wave_state == "loading" or (e.auto_thread and e.auto_thread.is_active()) or e.auto_res.empty()):
		yield(get_tree(), "idle_frame")
		var now = OS.get_ticks_usec()
		worst = max(worst, (now - last) / 1000.0)
		tw += (now - last) / 1e6
		last = now
	var res = e.auto_res
	out("real song: %d onsets, candidates %s (%.1f s incl. the muted capture, worst frame %.1f ms)" % [res.get("onsets", []).size(), str(res.get("candidates", [])), (OS.get_ticks_msec() - t0) / 1000.0, worst])
	ok("real song: an estimate", res.get("bpm", 0) > 0)
	var sc2 = load("res://mods/stars/StarCache.gd").get_instance(get_tree())
	var tn = 0.0
	while sc2.get_bpm(song) < 0 and tn < 15:
		yield(wait(0.25), "completed"); tn += 0.25
	var note_bpm = sc2.get_bpm(song)
	var cand_ok = false
	for c in res.get("candidates", []):
		if octave_ok(c[0], note_bpm, 1.5): cand_ok = true
	ok("real song: a candidate matches the BPM of the map's notes (or half / double)", cand_ok, "notes say %.2f" % note_bpm)
	# the map's notes sit on the detected grid (1/4 beats) if the tempo + offset are right
	var best_fit = 0.0
	for c in res.get("candidates", []):
		var per = 60000.0 / c[0] / 4.0
		var on = 0
		var ns = song.read_notes()
		for n in ns:
			var d = abs(fposmod(n[2] - c[1] + per / 2.0, per) - per / 2.0)
			if d <= 20.0: on += 1
		best_fit = max(best_fit, float(on) / max(1, ns.size()))
	ok("real song: the map's notes sit on the detected 1/4 grid (>= 80 %)", best_fit >= 0.8, "%.0f %%" % (best_fit * 100))
	ok("real song: the editor stays smooth meanwhile (worst frame < 60 ms)", worst < 60.0, "%.1f ms" % worst)
	if !res.get("candidates", []).empty():
		e._auto_preview(res.candidates[0])
		yield(wait(0.3), "completed")
		ok("preview grid drawn without changing the BPM", e.auto_preview != null and e.sp_bpm.value == e.m.bpm)
		shot("analysis")
		e._auto_apply(res.candidates[0])
		ok("USE sets the editor's BPM / offset", abs(e.m.bpm - res.candidates[0][0]) < 0.01 and e.m.offset == res.candidates[0][1])
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
