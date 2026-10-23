extends Node
# Map editor interaction (replay/Editor.gd, the Quantum Editor workflow): real mouse / key events sent
# through the engine's input (GUI routing, focus and modifiers included) - placing, hover, selection (click,
# Ctrl, Shift range, box), moving on the grid (cells, group kept inside) and on the track (time,
# snapped / Alt free), scrub / ruler / seek bar (playback pauses and resumes), wheel step / zoom /
# divisor, copy / cut / paste / duplicate / delete, undo / redo over mixed steps, moves across other
# notes, Esc, text-box focus, save -> reload, the map from before the update, missing audio, audio
# sync, a 20k-note map, window sizes and a test play. Map: @@MAP1@@.
# Output @@OUT@@/editor_interaction.txt + ei_*.png
const OUT = "@@OUT@@/editor_interaction.txt"
var passed = 0
var failed = 0
var e = null
var M = null

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

func frames(n):
	for i in n: yield(get_tree(), "idle_frame")

func shot(n):
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/ei_" + n + ".png")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	Input.use_accumulated_input = false # (motion events go through at once, in order)
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

# ---------------------------------------------------------------- input as the OS would send it
func gp(c:Control, p:Vector2) -> Vector2:
	return c.get_global_rect().position + p

func btn(c:Control, p:Vector2, b:int, down:bool, shift = false, ctrl = false):
	var ev = InputEventMouseButton.new()
	ev.button_index = b
	ev.pressed = down
	ev.position = gp(c, p)
	ev.global_position = ev.position
	ev.shift = shift
	ev.control = ctrl
	ev.button_mask = (1 << (b - 1)) if down else 0
	Input.parse_input_event(ev)

func move(c:Control, p:Vector2, mask:int = 0):
	var ev = InputEventMouseMotion.new()
	ev.position = gp(c, p)
	ev.global_position = ev.position
	ev.button_mask = mask
	Input.parse_input_event(ev)

func hover(c:Control, p:Vector2): # (straight to the control's input handler, local position)
	var ev = InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = gp(c, p)
	c.emit_signal("gui_input", ev)

func click(c:Control, p:Vector2, b:int = BUTTON_LEFT, shift = false, ctrl = false):
	move(c, p)
	btn(c, p, b, true, shift, ctrl)
	btn(c, p, b, false, shift, ctrl)

func drag(c:Control, a:Vector2, z:Vector2, b:int = BUTTON_LEFT, steps:int = 8):
	move(c, a)
	btn(c, a, b, true)
	for i in range(1, steps + 1): move(c, a.linear_interpolate(z, float(i) / steps), 1 << (b - 1))
	btn(c, z, b, false)

func wheel(c:Control, p:Vector2, up:bool, shift = false, ctrl = false):
	move(c, p)
	btn(c, p, BUTTON_WHEEL_UP if up else BUTTON_WHEEL_DOWN, true, shift, ctrl)
	btn(c, p, BUTTON_WHEEL_UP if up else BUTTON_WHEEL_DOWN, false, shift, ctrl)

func key(sc:int, shift = false, ctrl = false, alt = false, uni:int = 0):
	for down in [true, false]:
		var k = InputEventKey.new()
		k.scancode = sc
		k.pressed = down
		k.shift = shift
		k.control = ctrl
		k.alt = alt
		k.unicode = uni if down else 0
		Input.parse_input_event(k)

func hold_alt(down:bool):
	var k = InputEventKey.new()
	k.scancode = KEY_ALT
	k.pressed = down
	Input.parse_input_event(k)

# ---------------------------------------------------------------- editor geometry
func cell(gx:float, gy:float) -> Vector2:
	return e._to_field(gx, gy, e._field_geom())

func sq(n:Array) -> Vector2: # middle of a note's square on the track
	var r = e._sq_rect(n[2], e._lane_rect())
	return r.position + r.size / 2.0

func sig() -> String:
	return to_json(e.m.notes)

func has(n) -> bool:
	return e.m.has_note([float(n[0]), float(n[1]), int(n[2])])

func selected(ns:Array) -> bool:
	if e.sel.size() != ns.size(): return false
	for n in ns:
		if !e.sel.has(M.key_of([float(n[0]), float(n[1]), int(n[2])])): return false
	return true

func reset_notes(ns:Array):
	e.m.set_notes(ns)
	e.m.undo_stack = []
	e.m.redo_stack = []
	e.sel = {}
	e.sel_anchor = null
	e._sel_changed()

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	M = load("res://mods/replay/EditorModel.gd")
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if s is Song and s.filePath.get_file() == "@@MAP1@@": song = s
	menu.open_editor(song)
	yield(wait(2.0), "completed")
	e = menu.get_node("Editor")
	# ---- the map from before the update opens as it is
	var orig = song.read_notes()
	ok("a map from before the update opens with all its notes", e.m.notes.size() == orig.size() and orig.size() > 0, "%d / %d" % [e.m.notes.size(), orig.size()])
	var same = true
	var so = orig.duplicate(true)
	so.sort_custom(self, "_by_time")
	for i in min(so.size(), e.m.notes.size()):
		if abs(so[i][2] - e.m.notes[i][2]) > 0.5: same = false
	ok("... at the same times", same)
	shot("open_720")
	# ---- setup: 120 BPM from 0 (125 ms steps at 1/4), an empty map, playhead at 10 s
	e._page("timing")
	e.sp_bpm.value = 120
	e.sp_off.value = 0
	e._set_div(4)
	e.pos_snap = "cell"
	e.time_snap = true
	e.advance = false
	e.m.meta.id = "rr_ei_test"
	e.m.meta.name = "EI test"
	e.m.meta.creator = "test"
	reset_notes([])
	e._seek(10000.0)
	yield(frames(2), "completed")
	var F = e.field
	var T = e.tl
	# ---- place / hover
	click(F, cell(0, 0))
	ok("click an empty cell: a note there at the playhead, selected", has([0, 0, 10000]) and selected([[0, 0, 10000]]), sig())
	click(F, cell(0, 0) + Vector2(-8, -8))
	ok("a click left of the cell middle is the same cell (no -0 twin)", e.m.notes.size() == 1 and to_json(e.m.notes[0]) == to_json([0.0, 0.0, 10000]), sig())
	# hover (no button held) goes to the grid's handler directly: which control the engine sends a
	# plain move to also depends on where the real cursor is (outside the test window the grid can
	# get a "mouse left" instead, seen 2026-10-23 with sources that had passed before); presses and
	# drags below still go through the engine's own routing
	hover(F, cell(0, 0) + Vector2(3, 3))
	ok("hovering it: the grid reports that note (outlined, not a ghost)", e._note_at(e.field_mouse) != null and e.hint_lbl.text.begins_with("note 1"), e.hint_lbl.text)
	hover(F, cell(1, 2))
	ok("hovering an empty cell: placement hint with the snapped time", e._note_at(e.field_mouse) == null and "0:10.000" in e.hint_lbl.text, e.hint_lbl.text)
	click(F, cell(2, 2))
	ok("a second click: another note at the same time, only it selected", has([2, 2, 10000]) and selected([[2, 2, 10000]]))
	click(F, cell(2, 2))
	ok("clicking the note again selects it, places nothing", e.m.notes.size() == 2 and selected([[2, 2, 10000]]))
	e._seek(10010.0)
	click(F, cell(1, 1))
	ok("off-grid playhead: the note goes on the nearest grid line", has([1, 1, 10000]))
	# ---- wheel / grid keys / auto-advance
	e._seek(10000.0)
	wheel(F, cell(1, 0), false)
	ok("wheel down over the grid: one grid step back", abs(e.pos - 9875.0) < 0.5, e.pos)
	wheel(T, Vector2(200, 60), true)
	wheel(T, Vector2(200, 60), true)
	ok("wheel up over the track: steps forward the same way", abs(e.pos - 10125.0) < 0.5, e.pos)
	key(KEY_W)
	ok("grid key W: a note on the top middle cell at the playhead", has([1, 0, 10125]))
	e.advance = true
	key(KEY_KP_3)
	e.advance = false
	ok("numpad 3 + auto-advance: note, then one step on", has([2, 2, 10125]) and abs(e.pos - 10250.0) < 0.5, e.pos)
	wheel(F, cell(1, 1), true, true)
	var d5 = e.m.div
	wheel(F, cell(1, 1), false, true)
	ok("Shift + wheel: beat divisor up / down", d5 == 5 and e.m.div == 4, "%d %d" % [d5, e.m.div])
	# ---- selection on the grid
	reset_notes([[0.0, 0.0, 10000], [1.0, 1.0, 10125], [2.0, 2.0, 10250], [0.0, 2.0, 10375]])
	e._seek(10000.0)
	yield(frames(1), "completed")
	click(F, cell(1, 1))
	ok("click an approaching note: only it selected", selected([[1, 1, 10125]]))
	click(F, cell(2, 2), BUTTON_LEFT, false, true)
	ok("Ctrl+click adds", selected([[1, 1, 10125], [2, 2, 10250]]))
	click(F, cell(1, 1), BUTTON_LEFT, false, true)
	ok("Ctrl+click again removes", selected([[2, 2, 10250]]))
	click(F, cell(0, 0), BUTTON_LEFT, true)
	ok("Shift+click: the time range from the last clicked note", selected([[0, 0, 10000], [1, 1, 10125], [2, 2, 10250]]))
	click(F, cell(2, 0), BUTTON_RIGHT)
	ok("right-click on empty: deselect", e.sel.empty())
	# ---- moving on the grid
	click(F, cell(1, 1))
	var u0 = e.m.undo_stack.size()
	drag(F, cell(1, 1), cell(2, 1))
	ok("drag a note one cell: it moves there, one undo step", has([2, 1, 10125]) and !has([1, 1, 10125]) and e.m.undo_stack.size() == u0 + 1 and selected([[2, 1, 10125]]))
	key(KEY_Z, false, true)
	ok("Ctrl+Z puts it back (and selects it)", has([1, 1, 10125]) and !has([2, 1, 10125]) and selected([[1, 1, 10125]]))
	var before = sig()
	move(F, cell(1, 1))
	btn(F, cell(1, 1), BUTTON_LEFT, true)
	move(F, cell(1, 1) + Vector2(2, 1), 1)
	btn(F, cell(1, 1) + Vector2(2, 1), BUTTON_LEFT, false)
	ok("a click that wobbles 2 px moves nothing", sig() == before)
	move(F, cell(1, 1))
	btn(F, cell(1, 1), BUTTON_LEFT, true)
	move(F, cell(2, 1), 1)
	move(F, cell(2, 1), 0) # (the release happened outside the window: the next motion has no button)
	ok("a drag whose release was lost ends on the next motion", e.field_drag == null and has([2, 1, 10125]), sig())
	key(KEY_Z, false, true)
	click(F, cell(0, 0), BUTTON_LEFT, false, true)
	drag(F, cell(1, 1), cell(2, 2) + Vector2(e._field_geom().size.x, e._field_geom().size.x))
	ok("group drag past the edge: the group stops at the grid, shape kept", has([1, 1, 10000]) and has([2, 2, 10125]) and e.m.notes.size() == 4, sig())
	key(KEY_Z, false, true)
	ok("... one undo restores both", sig() == before)
	# ---- the track: zoom, select, move in time, Alt = free, scrub, box, right-click delete
	var cx = e._cursor_x()
	for i in 6: wheel(T, Vector2(300, 60), true, false, true)
	ok("Ctrl + wheel zooms the track around the fixed playhead", abs(e.ppm - 0.15 * pow(1.25, 6)) < 0.0001 and e._cursor_x() == cx and abs(e.pos - 10000.0) < 0.5 and abs(e._x_of(e.pos) - cx) < 0.01, e.ppm)
	yield(frames(1), "completed")
	var n4 = [0.0, 2.0, 10375]
	click(T, sq(n4))
	ok("click a note's square on the track: selected", selected([n4]))
	before = sig()
	drag(T, sq(n4), sq(n4) + Vector2(125 * e.ppm, 0))
	ok("drag it right one grid step: +125 ms, snapped", has([0, 2, 10500]) and !has(n4) and selected([[0, 2, 10500]]))
	key(KEY_Z, false, true)
	hold_alt(true)
	drag(T, sq(n4), sq(n4) + Vector2(37 * e.ppm, 0))
	hold_alt(false)
	var moved = null
	for n in e.m.notes:
		if n[0] == 0.0 and n[1] == 2.0: moved = n
	ok("Alt held: free time (off the grid)", moved != null and abs(moved[2] - 10412) <= 2 and int(moved[2]) % 125 != 0, moved)
	key(KEY_Z, false, true)
	ok("undo after the free move", sig() == before)
	var emp = Vector2(40, e._lane_rect().position.y + e._lane_rect().size.y * 0.6)
	drag(T, emp, emp + Vector2(250 * e.ppm, 0))
	ok("drag empty track right: scrubs back in time, snapped", abs(e.pos - 9750.0) < 0.5, e.pos)
	key(KEY_SPACE)
	yield(wait(0.3), "completed")
	var was = e.playing
	move(T, emp)
	btn(T, emp, BUTTON_LEFT, true)
	move(T, emp + Vector2(-60, 0), 1)
	var mid = e.playing
	btn(T, emp + Vector2(-60, 0), BUTTON_LEFT, false)
	yield(frames(2), "completed")
	ok("scrubbing while playing pauses the song and plays on after", was and !mid and e.playing, "%s %s %s" % [was, mid, e.playing])
	key(KEY_SPACE)
	e._seek(10000.0)
	yield(frames(1), "completed")
	click(T, Vector2(e._x_of(10250.0) + 3, 6))
	ok("click the ruler: the playhead goes there", abs(e.pos - 10250.0) < 0.5, e.pos)
	drag(T, Vector2(e._x_of(10250.0), 6), Vector2(e._x_of(10250.0) - 125 * e.ppm, 6))
	ok("drag along the ruler: it scrubs like the track (no run-away)", abs(e.pos - 10375.0) < 0.5, e.pos)
	e._seek(10000.0)
	yield(frames(1), "completed")
	var ly = e._lane_rect().position.y + e._lane_rect().size.y * 0.5
	drag(T, Vector2(e._x_of(9990.0), ly), Vector2(e._x_of(10300.0), ly), BUTTON_RIGHT)
	ok("right-drag on the track: box select", selected([[0, 0, 10000], [1, 1, 10125], [2, 2, 10250]]), e.sel.size())
	click(T, sq([1.0, 1.0, 10125]), BUTTON_RIGHT)
	ok("right-click a note on the track: deleted, the rest stay selected", !has([1, 1, 10125]) and selected([[0, 0, 10000], [2, 2, 10250]]))
	key(KEY_Z, false, true)
	# ---- seek bar
	var S = e.seekbar
	click(S, Vector2(S.rect_size.x * 0.5, S.rect_size.y / 2))
	var half = e._total_ms() * 0.5
	ok("seek bar click: the middle of the song (snapped)", abs(e.pos - half) <= 63.0 and int(e.pos) % 125 == 0, "%.1f vs %.1f" % [e.pos, half])
	# ---- clipboard / duplicate / delete / undo-redo chain
	reset_notes([[0.0, 0.0, 10000], [1.0, 1.0, 10125], [2.0, 2.0, 10250], [0.0, 2.0, 10375]])
	var s0 = sig()
	var chain = [s0]
	key(KEY_A, false, true)
	ok("Ctrl+A selects every note", e.sel.size() == 4)
	key(KEY_C, false, true)
	e._seek(20000.0)
	key(KEY_V, false, true)
	ok("Ctrl+V pastes at the playhead, pasted notes selected", has([0, 0, 20000]) and has([0, 2, 20375]) and e.sel.size() == 4 and e.m.notes.size() == 8)
	chain.append(sig())
	key(KEY_D, false, true)
	ok("Ctrl+D duplicates right after itself", has([0, 0, 20500]) and e.m.notes.size() == 12)
	chain.append(sig())
	key(KEY_X, false, true)
	ok("Ctrl+X cuts", e.m.notes.size() == 8 and e.clip.size() == 4)
	chain.append(sig())
	e._seek(30000.0)
	key(KEY_V, false, true)
	chain.append(sig())
	key(KEY_DELETE)
	ok("Delete removes the selection", e.m.notes.size() == 8 and e.sel.empty())
	chain.append(sig())
	click(F, cell(1, 0))
	chain.append(sig())
	var back_ok = true
	for i in range(chain.size() - 1, 0, -1):
		key(KEY_Z, false, true)
		if sig() != chain[i - 1]: back_ok = false
	ok("undo steps back through paste / duplicate / cut / paste / delete / place exactly", back_ok)
	var fwd_ok = true
	for i in range(1, chain.size()):
		if i % 2 == 0: key(KEY_Y, false, true)
		else: key(KEY_Z, true, true)
		if sig() != chain[i]: fwd_ok = false
	ok("redo (Ctrl+Y / Ctrl+Shift+Z) replays them exactly", fwd_ok)
	# ---- moves across notes
	reset_notes([[0.0, 0.0, 10000], [0.0, 0.0, 10125], [0.0, 0.0, 10250], [2.0, 2.0, 10000]])
	e.sel = {}
	for n in [[0.0, 0.0, 10000], [0.0, 0.0, 10125], [0.0, 0.0, 10250]]: e.sel[M.key_of(n)] = n
	e._sel_changed()
	e._op_step(1)
	ok("a stream moved one step along itself stays whole", e.m.notes.size() == 4 and has([0, 0, 10125]) and has([0, 0, 10250]) and has([0, 0, 10375]) and !has([0, 0, 10000]) and e.sel.size() == 3)
	reset_notes([[1.0, 1.0, 10000], [1.0, 1.0, 10125]])
	e.sel = {M.key_of([1.0, 1.0, 10000]): [1.0, 1.0, 10000]}
	e._sel_changed()
	e._op_step(1)
	ok("moved onto an unselected equal note: merged, and said so", e.m.notes.size() == 1 and "merged" in e.top_msg.text, e.top_msg.text)
	key(KEY_Z, false, true)
	ok("... undo brings both back", e.m.notes.size() == 2)
	# ---- the selection's properties
	reset_notes([[1.0, 1.0, 10000], [2.0, 0.0, 10500]])
	e._seek(10000.0)
	click(F, cell(1, 1))
	ok("one note selected: TIME / X / Y show it, the grid line is named", e.insp.t.value == 10000 and e.insp.x.value == 1.0 and "on the 1/4 grid" in e.beat_lbl.text, e.beat_lbl.text)
	e.insp.x.value = 0.5
	ok("typing X moves it", has([0.5, 1, 10000]))
	e.insp.t.value = 10003
	ok("typing TIME moves it, the panel says it is off the grid", has([0.5, 1, 10003]) and "3 ms after" in e.beat_lbl.text, e.beat_lbl.text)
	# ---- unsaved changes
	e.m.dirty = true
	e._ask_new()
	var asked = e.confirm.visible
	e.confirm.hide()
	ok("NEW with unsaved changes asks first", asked and e.m.notes.size() == 2)
	# ---- Esc, the shortcut list, focus in text boxes
	key(KEY_ESCAPE)
	ok("Esc with a selection: deselects and stays in the editor", e.sel.empty() and !e._closing)
	key(KEY_SLASH, true, false, false, 63)
	var kv = e.keys_panel.visible
	key(KEY_ESCAPE)
	ok("? opens the shortcut list, Esc closes it (editor stays)", kv and !e.keys_panel.visible and !e._closing)
	click(F, cell(1, 1))
	e._page("timing")
	yield(frames(1), "completed")
	var le = e.sp_bpm.get_line_edit()
	click(le, le.rect_size / 2)
	var n_before = e.m.notes.size()
	var focus_ok = e.root.get_focus_owner() == le
	key(KEY_BACKSPACE)
	key(KEY_SPACE)
	key(KEY_Q)
	key(KEY_DELETE)
	ok("in a number box Backspace / Space / Q / Delete stay in the box", focus_ok and e.m.notes.size() == n_before and !e.playing and e.sel.size() == 1, "%s %d %s %d" % [focus_ok, e.m.notes.size(), e.playing, e.sel.size()])
	key(KEY_ESCAPE)
	ok("Esc leaves the box, not the editor", e.root.get_focus_owner() == null and !e._closing)
	e.sp_bpm.value = 120
	# ---- audio sync
	e._seek(5000.0)
	key(KEY_SPACE)
	yield(wait(2.0), "completed")
	var drift = e.pos - (e.ap.get_playback_position() * 1000.0 - AudioServer.get_output_latency() * 1000.0)
	ok("playing 2 s: the playhead follows the audio clock (|drift| < 60 ms)", e.playing and abs(drift) < 60.0, "%.1f ms" % drift)
	ok("... and the track keeps the playhead fixed", abs(e._x_of(e.pos) - e._cursor_x()) < 0.01)
	key(KEY_SPACE)
	ok("Space pauses", !e.playing)
	# ---- save -> reload
	reset_notes([[0.0, 0.0, 1000], [1.0, 1.0, 1250], [2.0, 2.0, 1500], [0.5, 1.5, 1625], [2.1, -0.2, 1750], [1.0, 1.0, 1751]])
	var r = e.save_map()
	ok("save writes the map", r == "", r)
	var chk = Song.new()
	var lr = chk.load_from_sspm(Globals.p("user://maps/rr_ei_test.sspm"))
	var back = chk.read_notes() if !(lr is String) else []
	back.sort_custom(self, "_by_time")
	var exact = back.size() == e.m.notes.size()
	if exact:
		for i in back.size():
			var a = back[i]
			var b = e.m.notes[i]
			if int(a[2]) != int(b[2]) or abs(a[0] - b[0]) > 0.0001 or abs(a[1] - b[1]) > 0.0001: exact = false
	ok("the saved file loads back with the same times and positions", exact, str(back))
	# ---- missing audio
	var keep_audio = e.m.meta.audio
	e.m.meta.audio = "user://editor/nope_missing.mp3"
	e._load_audio()
	key(KEY_SPACE)
	ok("missing audio: no crash, play says so", !e.playing and !e.audio_ok and "no audio" in e.top_msg.text, e.top_msg.text)
	e.m.meta.audio = keep_audio
	e._load_audio()
	# ---- a 20k-note map
	var big = []
	for i in 20000: big.append([float(i % 3), float((i / 3) % 3), 1000 + i * 10])
	reset_notes(big)
	e.m.meta.id = "rr_ei_big"
	e._seek(60000.0)
	var t0 = OS.get_ticks_usec()
	key(KEY_A, false, true)
	var t_sel = (OS.get_ticks_usec() - t0) / 1000.0
	t0 = OS.get_ticks_usec()
	e._op_nudge(1)
	var t_move = (OS.get_ticks_usec() - t0) / 1000.0
	ok("20k notes: select all + move all in one step (%.0f + %.0f ms)" % [t_sel, t_move], e.m.notes.size() == 20000 and has([0, 0, 1001]) and t_sel < 1500 and t_move < 3000)
	key(KEY_Z, false, true)
	key(KEY_ESCAPE)
	key(KEY_SPACE)
	var worst = 0.0
	var last = OS.get_ticks_usec()
	var tot = 0.0
	for i in 120:
		yield(get_tree(), "idle_frame")
		var now = OS.get_ticks_usec()
		worst = max(worst, (now - last) / 1000.0)
		tot += (now - last) / 1000.0
		last = now
	key(KEY_SPACE)
	ok("20k notes playing: average frame %.1f ms, worst %.1f ms (< 33 / 100)" % [tot / 120.0, worst], tot / 120.0 < 33.0 and worst < 100.0)
	for i in 8: wheel(T, Vector2(300, 60), false, false, true)
	yield(frames(2), "completed")
	ok("zoomed far out the track shows density (no square per note)", e._tl_dense())
	shot("big")
	for i in 8: wheel(T, Vector2(300, 60), true, false, true)
	# ---- window sizes
	reset_notes([[0.0, 0.0, 10000], [1.0, 1.0, 10125], [2.0, 2.0, 10250], [0.0, 2.0, 10375]])
	e._seek(10000.0)
	for sz in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1080), Vector2(1440, 1080), Vector2(1024, 640)]:
		OS.window_size = sz
		yield(wait(0.6), "completed")
		var vs = get_viewport().get_visible_rect().size
		var fr = e.field.get_global_rect()
		var lr2 = e.left_panel.get_global_rect()
		var rr = e.right_panel.get_global_rect()
		var rv = e.right_panel.get_child(0).get_child(0)
		var top_min = e.top_bar.get_child(0).get_combined_minimum_size().x
		var g = e._field_geom()
		var fit = fr.position.x >= lr2.end.x - 1 and fr.end.x <= rr.position.x + 1 and rv.rect_size.x <= rr.size.x - 19 and top_min <= vs.x - 23 and g.size.x >= 200
		ok("%dx%d: panels, grid and tool bar fit (grid %d px)" % [sz.x, sz.y, g.size.x], fit, "field %s left %s right %s rv %.0f top %.0f/%.0f" % [fr, lr2, rr, rv.rect_size.x, top_min, vs.x])
		shot("%dx%d" % [sz.x, sz.y])
	OS.window_size = Vector2(1280, 720)
	yield(wait(0.6), "completed")
	# ---- test play: the map runs in the game, then back to the editor with the session
	reset_notes([[0.0, 0.0, 2000], [1.0, 1.0, 2500], [2.0, 2.0, 3000], [1.0, 0.0, 3500]])
	e.m.dirty = true
	var n_ed = e.m.notes.size()
	var nofail = Rhythia.get("mod_nofail")
	Rhythia.set("mod_nofail", true) # (the notes are left to pass: each is counted as it goes)
	key(KEY_F5)
	var gnode = null
	var t = 0.0
	while t < 30 and !gnode:
		yield(wait(0.25), "completed"); t += 0.25
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"): gnode = sc.get_node("Game")
	t = 0.0
	while gnode and is_instance_valid(gnode) and t < 15 and int(gnode.get("total_notes")) < n_ed:
		yield(wait(0.25), "completed"); t += 0.25
	ok("F5: the map plays in the game, all %d notes come by" % n_ed, gnode != null and is_instance_valid(gnode) and int(gnode.get("total_notes")) == n_ed, str(gnode.get("total_notes")) if gnode and is_instance_valid(gnode) else "no game")
	Rhythia.set("mod_nofail", nofail)
	if gnode and is_instance_valid(gnode):
		gnode.end(Globals.END_GIVEUP)
		var ed = null
		t = 0.0
		while t < 30 and !ed:
			yield(wait(0.25), "completed"); t += 0.25
			var sc2 = get_tree().current_scene
			if sc2 and sc2.has_node("Editor"): ed = sc2.get_node("Editor")
		ok("back in the editor after the run, notes intact", ed != null and ed.m != null and ed.m.notes.size() == n_ed, str(ed.m.notes.size()) if ed and ed.m else "no editor")
		if ed and ed.m: ed.m.dirty = false
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())

func _by_time(a, b):
	if a[2] != b[2]: return a[2] < b[2]
	if a[1] != b[1]: return a[1] < b[1]
	return a[0] < b[0]
