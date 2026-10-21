extends Node
# Map editor parity with the Sound Space Quantum Editor (replay/Editor.gd, EditorModel.gd timing
# sections, EditorPatterns.gd bezier): grid keys (Q W E / A S D / Z X C, numpad) place notes at the
# playhead, auto-advance, Shift+H / Shift+V flip, Ctrl+Q free positions, Ctrl+T / Ctrl+B open TIMING,
# timing points (BPM changes: snap, grid steps, beats, measures, saved with the map's editor
# settings), Bezier curve through the selection (Shift+D, one undo step). Map: @@MAP1@@.
# Output @@OUT@@/editor_parity.txt + ep_*.png
const OUT = "@@OUT@@/editor_parity.txt"
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
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/ep_" + n + ".png")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func key(e, sc:int, shift:bool = false, ctrl:bool = false):
	var k = InputEventKey.new()
	k.scancode = sc
	k.pressed = true
	k.shift = shift
	k.control = ctrl
	e._input(k)

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var M = load("res://mods/replay/EditorModel.gd")
	var P = load("res://mods/replay/EditorPatterns.gd")
	# ---- timing sections (pure). 0: 120 BPM from 100 ms (125 ms steps); 1: 180 from 10100 (83.33);
	# 2: 90 from 20100 (166.67)
	var m = M.new()
	m.bpm = 120.0
	m.offset = 100
	m.div = 4
	ok("no points: snap = the single-BPM snap", m.snap_t(1234) == M.snap(1234, 120.0, 100, 4) and m.snap_t(-300) == M.snap(-300, 120.0, 100, 4))
	ok("a point before the offset is refused", !m.add_point(50, 180.0))
	ok("a point after it is kept", m.add_point(10100, 180.0))
	ok("a point on top of another is refused", !m.add_point(10101, 200.0))
	m.add_point(20100, 90.0)
	ok("BPM follows the sections", m.bpm_at(5000) == 120.0 and m.bpm_at(10100) == 180.0 and m.bpm_at(15000) == 180.0 and m.bpm_at(30000) == 90.0)
	ok("snap in section 0", m.snap_t(1180) == 1225 and m.snap_t(10000) == 9975, "%d %d" % [m.snap_t(1180), m.snap_t(10000)])
	ok("snap in section 1 on its own grid", m.snap_t(10300) == 10267, m.snap_t(10300))
	ok("a section start is a grid line", m.snap_t(10080) == 10100)
	ok("grid steps", abs(m.step_at(5000) - 125.0) < 0.001 and abs(m.step_at(15000) - 83.333) < 0.001 and abs(m.step_at(25000) - 166.667) < 0.001)
	ok("next / previous grid line across a change", abs(m.grid_next(10050, 1) - 10100) < 0.01 and abs(m.grid_next(10100, 1) - 10183.333) < 0.01 and abs(m.grid_next(10100, -1) - 9975) < 0.01, "%.2f %.2f %.2f" % [m.grid_next(10050, 1), m.grid_next(10100, 1), m.grid_next(10100, -1)])
	ok("measures restart at a point", abs(m.grid_next(10150, 1, 0.25) - 11433.333) < 0.01, m.grid_next(10150, 1, 0.25))
	ok("beats add up over the sections", abs(m.beat_at(10100) - 20.0) < 0.001 and abs(m.beat_at(10100 + 1000.0) - 23.0) < 0.001)
	var gl = m.grid_lines(10000, 10700, false)
	ok("grid lines: section 0 stops at the change, section 1 starts with a measure", gl.size() == 2 and abs(gl[0][0] - 10100) < 0.01 and gl[0][1] == 0 and gl[1][1] == 1, str(gl))
	var m2 = M.from_dict(m.to_dict())
	ok("points survive the session file", to_json(m2.points) == to_json(m.points), str(m2.points))
	ok("curve: 2 control notes = a straight line", to_json(P.bezier([[0.0, 0.0, 0], [2.0, 2.0, 100]], [0, 50, 100])) == to_json([[0.0, 0.0, 0], [1.0, 1.0, 50], [2.0, 2.0, 100]]))
	# ---- in the editor
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if s is Song and s.filePath.get_file() == "@@MAP1@@": song = s
	menu.open_editor(song)
	yield(wait(2.0), "completed")
	var e = menu.get_node("Editor")
	e._page("timing")
	e.sp_bpm.value = 200
	e.sp_off.value = 0
	e._set_div(4)
	e.time_snap = true
	e.advance = false
	e.pos = 35500.0
	var t = e.m.snap_t(35500.0)
	key(e, KEY_E)
	key(e, KEY_KP_1)
	ok("grid key E / numpad 1 place on their cells at the snapped playhead", e.m.has_note([2.0, 0.0, t]) and e.m.has_note([0.0, 2.0, t]), "t %d" % t)
	e.advance = true
	key(e, KEY_S)
	ok("auto-advance: S places the centre and moves one grid step", e.m.has_note([1.0, 1.0, t]) and abs(e.pos - (t + 75)) < 0.5, "pos %.1f" % e.pos)
	var t2 = int(round(e.pos))
	key(e, KEY_Q)
	e.advance = false
	e.sel = {M.key_of([2.0, 0.0, t]): [2.0, 0.0, t]}
	key(e, KEY_H, true)
	ok("Shift+H flips the selection left / right", e.m.has_note([0.0, 0.0, t]) and !e.m.has_note([2.0, 0.0, t]))
	e.sel = {M.key_of([0.0, 0.0, t2]): [0.0, 0.0, t2]}
	key(e, KEY_V, true)
	ok("Shift+V flips it up / down", e.m.has_note([0.0, 2.0, t2]) and !e.m.has_note([0.0, 0.0, t2]))
	key(e, KEY_Q, false, true)
	var q1 = e.pos_snap == "free" and e.pos_btns.free.pressed
	key(e, KEY_Q, false, true)
	ok("Ctrl+Q: free positions and back, the buttons follow", q1 and e.pos_snap == "cell" and e.pos_btns.cell.pressed)
	e._page("props")
	key(e, KEY_T, false, true)
	var tt = e.page_btns.timing.pressed
	e._page("props")
	key(e, KEY_B, false, true)
	ok("Ctrl+T / Ctrl+B open TIMING", tt and e.page_btns.timing.pressed)
	# timing point at 20 s, 150 BPM
	e.pos = 20010.0
	var tp = e.m.snap_t(20010.0)
	key(e, KEY_B, true, true)
	ok("Ctrl+Shift+B adds a timing point at the snapped playhead", e.m.points.size() == 1 and int(e.m.points[0][0]) == tp and e.pt_list.get_item_count() == 1, str(e.m.points))
	e.sp_pt.value = 150
	ok("its BPM is set from the TIMING tab", e.m.points.size() == 1 and e.m.points[0][1] == 150.0 and abs(e.m.step_at(25000) - 100.0) < 0.001)
	e.pos = float(tp)
	ok("arrow step from the point uses its grid", abs(e._step_from(e.pos, 1) - (tp + 100)) < 0.5 and abs(e._step_from(e.pos, -1) - (tp - 75)) < 0.5, "%.1f %.1f" % [e._step_from(e.pos, 1), e._step_from(e.pos, -1)])
	e._seek(25000.0)
	e._center_view()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	ok("the time line shows the BPM there", e.time_lbl.text.find("@ 150 BPM") >= 0, e.time_lbl.text)
	e._sidecar_write()
	var m3 = M.new()
	m3.meta.id = e.m.meta.id
	e._sidecar_read(m3)
	ok("timing points are saved with the map's editor settings", to_json(m3.points) == to_json(e.m.points), str(m3.points))
	e._seek(float(tp) - 1500.0)
	e._center_view()
	yield(wait(0.5), "completed")
	shot("timing")
	# curve through 3 control notes in the 150 BPM section (100 ms steps)
	var t3 = tp + 6000
	e._insert_notes("ctrl", [[0.0, 0.0, t3], [2.0, 0.0, t3 + 300], [2.0, 2.0, t3 + 600]])
	var n_before = e.m.notes.size()
	key(e, KEY_D, true)
	ok("Shift+D: a curve note on every grid step, ends on the first / last control note", e.m.notes.size() == n_before - 3 + 7 and e.m.has_note([0.0, 0.0, t3]) and e.m.has_note([2.0, 2.0, t3 + 600]) and e.m.has_note([1.5, 0.5, t3 + 300]), "%d -> %d" % [n_before, e.m.notes.size()])
	ok("the curve is selected", e.sel.size() == 7)
	e._undo()
	ok("one undo brings the control notes back", e.m.notes.size() == n_before and e.m.has_note([2.0, 0.0, t3 + 300]))
	e.m.dirty = false
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
