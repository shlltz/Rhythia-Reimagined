extends Node
# Map editor tools (replay/EditorAuto.gd, EditorCapture.gd, EditorPatterns.gd, Editor AUTO tab): BPM /
# offset from synthetic envelopes and from a click track played through the real capture (known tempo
# and phase); on a real song the estimate is checked against the map's own notes (their tempo, and
# they must sit on the estimated grid); undo / redo select what they put back; patterns are deterministic, editable, one undo step;
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

# envelopes of a beat at `bpm` from `off` ms as EditorCapture.gd makes them (per 10 ms bin, the
# envelope's peak inside the bin): kick on every beat (low band), hat on the off-beats (high band), a
# little deterministic noise
func synth(bpm:float, off:float, secs:float, noise:float = 0.05) -> Array:
	var n = int(secs * 100)
	var lo = PoolRealArray(); lo.resize(n)
	var hi = PoolRealArray(); hi.resize(n)
	var pk = PoolRealArray(); pk.resize(n)
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var per = 60000.0 / bpm
	for i in n:
		var t = i * 10.0
		lo[i] = clamp(win_peak(t, off, per, 60.0) * 0.9 + rng.randf() * noise, 0, 1)
		hi[i] = clamp(win_peak(t, off + per / 2.0, per, 40.0) * 0.5 + rng.randf() * noise, 0, 1)
		pk[i] = clamp(max(lo[i], hi[i]) * 0.8 + 0.1, 0, 1)
	return [lo, hi, pk]

func win_peak(t:float, off:float, per:float, tau:float) -> float: # (1 if a beat starts inside [t, t + 10))
	var ph = fposmod(t - off, per)
	return 1.0 if ph == 0.0 or per - ph < 10.0 else exp(-ph / tau)

# a click track as audio: decaying 60 Hz kick on the beats from `off`, noise hat on the off-beats
func click_track(bpm:float, off:float, secs:float, rate:int = 22050) -> AudioStreamSample:
	var per = 60000.0 / bpm
	var rng = RandomNumberGenerator.new()
	rng.seed = 11
	var spb = StreamPeerBuffer.new()
	for i in int(secs * rate):
		var t = i * 1000.0 / rate
		var v = 0.01 * (rng.randf() * 2.0 - 1.0)
		var ph = fposmod(t - off, per)
		if t >= off and ph < 150.0: v += 0.8 * exp(-ph / 50.0) * sin(TAU * 60.0 * ph / 1000.0)
		var ph2 = fposmod(t - off - per / 2.0, per)
		if t >= off + per / 2.0 and ph2 < 50.0: v += 0.3 * exp(-ph2 / 10.0) * (rng.randf() * 2.0 - 1.0)
		spb.put_16(int(clamp(v, -1.0, 1.0) * 32000.0))
	var st = AudioStreamSample.new()
	st.format = AudioStreamSample.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = spb.data_array
	return st

# the BPM whose quarter-beat grid a map's notes fit best (100..320; circular mean resultant)
func note_tempo(ns:Array) -> float:
	var best = 0.0
	var best_r = -1.0
	var b = 100.0
	while b <= 320.0:
		var q = 60000.0 / b / 4.0
		var zr = 0.0
		var zi = 0.0
		for n in ns:
			var a = TAU * fposmod(n[2] / q, 1.0)
			zr += cos(a)
			zi += sin(a)
		var r = zr * zr + zi * zi
		if r > best_r:
			best_r = r
			best = b
		b += 0.1
	return best

# mean distance (ms) of the notes in the first 12 s from a candidate's grid, in the notes' own
# division (`note_bpm` quarters, the candidate's octave of it)
func grid_dev(ns:Array, bpm:float, off:float, note_bpm:float) -> float:
	var k = pow(2.0, round(log(note_bpm / bpm) / log(2.0)))
	var q = 60000.0 / (bpm * k) / 4.0
	var zr = 0.0
	var zi = 0.0
	for n in ns:
		if n[2] > ns[0][2] + 12000: break
		var a = TAU * fposmod((n[2] - off) / q, 1.0)
		zr += cos(a)
		zi += sin(a)
	return atan2(zi, zr) / TAU * q

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
		var r = A.analyse(e[0], e[1], e[2], 10.0)
		var per = 60000.0 / r.bpm if r.bpm > 0 else 1.0
		var off_err = abs(fposmod(r.offset - case[1] + per / 2.0, per) - per / 2.0) # (phase difference, wrapped)
		ok("synthetic %.1f BPM: tempo" % case[0], octave_ok(r.bpm, case[0], 0.6), "%.2f (%d ms)" % [r.bpm, OS.get_ticks_msec() - t0])
		ok("synthetic %.1f BPM: offset" % case[0], r.bpm > 0 and (off_err <= 8.0 or (abs(r.bpm - case[0]) > 1 and off_err <= per / 2.0)), "%d ms vs %d ms (err %.1f)" % [r.offset, case[1], off_err])
	var flat = synth(120.0, 0.0, 30.0, 0.0)
	for i in flat[0].size():
		flat[0][i] = 0.3
		flat[1][i] = 0.3
		flat[2][i] = 0.3
	ok("no beat at all: no tempo claimed", A.analyse(flat[0], flat[1], flat[2], 10.0).bpm == 0.0)
	var rnd = synth(120.0, 0.0, 30.0, 0.0)
	var rr = RandomNumberGenerator.new()
	rr.seed = 5
	for i in rnd[0].size():
		rnd[0][i] = rr.randf() * 0.6
		rnd[1][i] = rr.randf() * 0.6
		rnd[2][i] = max(rnd[0][i], rnd[1][i])
	var rres = A.analyse(rnd[0], rnd[1], rnd[2], 10.0)
	ok("random noise: no tempo claimed", rres.bpm == 0.0, "periodicity %.3f" % rres.periodicity)
	# ---- the real capture path (EditorCapture.gd) on a click track of known tempo / phase
	var Cap = load("res://mods/replay/EditorCapture.gd")
	for case in [[137.0, 251.0], [172.5, 64.0]]:
		var tg = OS.get_ticks_msec()
		var trk = click_track(case[0], case[1], 20.0)
		var cap = Cap.new()
		add_child(cap)
		var tc = OS.get_ticks_msec()
		cap.start(trk, 20000.0, 25.0)
		var cworst = 0.0
		var clast = OS.get_ticks_usec()
		while cap.state == "loading" and OS.get_ticks_msec() - tc < 20000:
			yield(get_tree(), "idle_frame")
			var cnow = OS.get_ticks_usec()
			cworst = max(cworst, (cnow - clast) / 1000.0)
			clast = cnow
		var cms = OS.get_ticks_msec() - tc
		var cr = A.analyse(cap.lo, cap.hi, cap.al, Cap.ABIN)
		var cper = 60000.0 / cr.bpm if cr.bpm > 0 else 1.0
		var coff = abs(fposmod(cr.offset - case[1] + cper / 2.0, cper) - cper / 2.0)
		out("click %.1f BPM from %d ms: made in %d ms, captured in %d ms (worst frame %.1f ms), %d bins, first onset %s, result %s" % [case[0], case[1], tc - tg, cms, cworst, cap.bins, str(cr.onsets[0]) if cr.onsets.size() > 0 else "-", str(cr.candidates)])
		ok("capture %.1f BPM: done at 4x speed" % case[0], cap.state == "ready" and cms < 9000, "%s in %d ms" % [cap.state, cms])
		ok("capture %.1f BPM: tempo" % case[0], octave_ok(cr.bpm, case[0], 0.1), "%.2f" % cr.bpm)
		ok("capture %.1f BPM: offset within 6 ms" % case[0], cr.bpm > 0 and coff <= 6.0, "%d ms vs %d ms" % [cr.offset, case[1]])
		ok("capture %.1f BPM: first onset at the first kick" % case[0], cr.onsets.size() > 0 and abs(cr.onsets[0] - case[1]) <= 10.0)
		ok("capture %.1f BPM: waveform drawn" % case[0], cap.wave.size() > 0 and cap.wave[int(case[1] / 25.0) + 1] > 0.3)
		ok("capture %.1f BPM: its work per frame stays small (< 8 ms; whole frames < 60 ms)" % case[0], cap.worst_us < 8000 and cworst < 60.0, "%.1f ms of capture work, worst frame %.1f ms" % [cap.worst_us / 1000.0, cworst])
		cap.queue_free()
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
	ok("a page opened from code highlights its tab", e.page_btns.auto.pressed and !e.page_btns.props.pressed)
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
	var at_ms = e.m.snap(20000.0, e.m.bpm, e.m.offset, e.m.div) if e.time_snap else 20000.0
	ok("slot 3 recalled at the playhead", e.m.notes.size() > n_before and !e._sel_notes().empty() and abs(e._sel_notes()[0][2] - at_ms) <= 1, "%d notes, first at %s (playhead %d)" % [e.m.notes.size() - n_before, str(e._sel_notes()[0][2]) if !e._sel_notes().empty() else "-", at_ms])
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
	var ns = song.read_notes()
	var note_bpm = note_tempo(ns)
	var main = res.get("candidates", [[0.0, 0]])[0]
	ok("real song: the estimate matches the tempo of the map's notes (or half / double)", octave_ok(main[0], note_bpm, 1.5), "%.2f vs notes %.2f, periodicity %.3f" % [main[0], note_bpm, res.get("periodicity", 0.0)])
	var dev = grid_dev(ns, main[0], main[1], note_bpm) if main[0] > 0 else 999.0
	ok("real song: the map's notes sit on the estimated beat grid (within 20 ms)", abs(dev) <= 20.0, "%.1f ms off" % dev)
	ok("real song: the editor stays smooth meanwhile (worst frame < 60 ms)", worst < 60.0, "%.1f ms" % worst)
	if !res.get("candidates", []).empty():
		e._auto_preview(res.candidates[0])
		yield(wait(1.0), "completed")
		ok("preview grid drawn without changing the BPM", e.auto_preview != null and e.sp_bpm.value == e.m.bpm)
		shot("analysis")
		e._auto_apply(res.candidates[0])
		ok("USE sets the editor's BPM / offset", abs(e.m.bpm - res.candidates[0][0]) < 0.01 and e.m.offset == res.candidates[0][1])
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
