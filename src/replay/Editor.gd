extends CanvasLayer
# In-game beatmap editor (Rhythia-reimagined). Clean-room GDScript: Sound Space Quantum Editor is
# C# / AGPL-3.0, which cannot run inside this Godot 3 game and would put the whole mod pack under
# AGPL, so only its ideas are used (3x3 field + timeline + snapping, note clipboard, text format).
#
# Data: EditorModel.gd (notes [x, y, ms] as Song.notes, undo as commands). Save = the game's own
# Song.convert_to_sspm (a real .sspm v2 in user://maps, audio embedded); the old file is moved to
# user://editor/backup first and put back if the write or the check fails. Test = the real
# gameplay (a temporary in-memory Song, results / pbs of it are cleaned up on the way back, the
# editing session survives in Engine meta "rr_editor_model" and user://editor/session.json).
# Rhythia maps have no BPM / offset: those are editor aids kept only in the session file.

const Model = preload("res://mods/replay/EditorModel.gd")
const Look = preload("res://mods/replay/Look.gd")
const Cap = preload("res://mods/replay/EditorCapture.gd")
const UIAnim = preload("res://mods/replay/UIAnim.gd")
const DIR = "user://editor"
const SESSION = DIR + "/session.json"
const TEST_ID = "rr_editor_test"
const BIN = 25.0                     # waveform bin, ms
const APPROACH = 700.0               # how far ahead the field shows notes, ms
const DIFFS = ["Unknown", "Easy", "Medium", "Hard", "Logic", "Tasukete"]
const SNAPS = [1, 2, 3, 4, 6, 8, 12, 16]

var menu:Node
var m                                # Model
var src_song = null                  # library song this map was opened from (cover / extras / rating are kept)
var saved_once:bool = false          # the .sspm exists: the id is fixed
var root:Control
var tl:Control
var field:Control
var top_msg:Label
var state_lbl:Label
var time_lbl:Label
var fonts:Dictionary = {}

# audio / playback
var stream = null
var audio_len:float = 0.0            # ms
var audio_ok:bool = false
var ap:AudioStreamPlayer
var playing:bool = false
var pos:float = 0.0                  # playhead, ms
var speed:float = 1.0
var hit_players:Array = []
var hit_i:int = 0
var click_player:AudioStreamPlayer
var hit_sound:bool = true
var metronome:bool = false
var loop_on:bool = false
var loop_a:float = -1.0
var loop_b:float = -1.0

# view
var view0:float = 0.0                # left edge of the timeline, ms
var ppm:float = 0.15                 # pixels per ms
var follow:bool = true
var time_snap:bool = true
var pos_snap:String = "cell"         # cell | half | free
var advance:bool = false
var sel:Dictionary = {}              # key -> note
var clip:Array = []
var hover_cell:Vector2 = Vector2(-9, -9)
var show_cursor:bool = true # pattern cursor: glides from note to note, arriving on each note's time
var field_drag = null                # {start: Vector2 grid, keys}
var tl_drag = null
var drag_delta:Vector2 = Vector2.ZERO
var drag_dt:int = 0
var box_sel = null                   # {a: ms, b: ms, add: bool}

# waveform (peaks per BIN ms, 0..1; captured by playing the song muted at 4x)
var wave:PoolRealArray = PoolRealArray()
var env_lo:PoolRealArray = PoolRealArray()  # low / high / whole band peaks per Cap.ABIN (audio analysis, EditorAuto.gd)
var env_hi:PoolRealArray = PoolRealArray()
var env_all:PoolRealArray = PoolRealArray()
var wave_n:int = 0                   # bins captured so far
var wave_state:String = "none"       # none | loading | ready | failed
var wave_cap = null                  # EditorCapture node while capturing
var wave_lines = null
var wave_key:String = ""
var _tl_dirty:bool = true
var _field_dirty:bool = true
var _last_rev:int = -1

# panels
var pages:Dictionary = {}
var page_btns:Dictionary = {}
var f_id:LineEdit
var f_name:LineEdit
var f_creator:LineEdit
var f_diff:OptionButton
var audio_lbl:Label
var sp_bpm:SpinBox
var sp_off:SpinBox
var ob_div:OptionButton
var note_list:ItemList
var note_list_filter:LineEdit
var diag_list:ItemList
var hist_list:ItemList
var book_list:ItemList
var pt_list:ItemList                 # timing points (TIMING tab)
var sp_pt:SpinBox
var pos_btns:Dictionary = {}         # note position snap buttons by mode
var insp:Dictionary = {}
var start_panel:Control
var lib_list:ItemList
var lib_filter:LineEdit
var lib_songs:Array = []
var confirm:ConfirmationDialog
var confirm_cb:Array = []
var diags:Array = []
var _auto_t:float = 0.0
var _auto_rev:int = -1
var _saving:bool = false
var _last_save_msg:String = ""
var _lock_ui:bool = false
var tap_times:Array = []
var _closing:bool = false
var ack_markers:bool = false
var _prev_pos:float = 0.0

# ------------------------------------------------------------------ setup
func _ready():
	layer = 18
	menu = get_parent()
	pause_mode = Node.PAUSE_MODE_PROCESS
	var d = Directory.new()
	if !d.dir_exists(DIR): d.make_dir_recursive(DIR)
	root = Control.new()
	root.anchor_right = 1
	root.anchor_bottom = 1
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists("res://uitheme.tres"): root.theme = load("res://uitheme.tres")
	add_child(root)
	var bg = ColorRect.new()
	bg.color = Look.BG
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	_build_audio()
	_build_top()
	_build_left()
	_build_field()
	_build_timeline()
	_build_start()
	confirm = ConfirmationDialog.new()
	confirm.connect("confirmed", self, "_confirmed")
	root.add_child(confirm)
	_cover(true)
	_find_players()
	_hush()
	if Engine.has_meta("rr_editor_model"):
		var live = Engine.get_meta("rr_editor_model")
		Engine.remove_meta("rr_editor_model")
		_adopt(live, Engine.get_meta("rr_editor_pos") if Engine.has_meta("rr_editor_pos") else 0.0)
	UIAnim.play(root, Vector2(0, 18), Vector2.ZERO, 0.0, 1.0, 0.25)

# the menu pages behind stay hidden while the editor is open: the map search grabs focus on every
# typed character, the map list scrolls on the wheel and Space starts the map - none of that may
# reach the menu from here
var covered:Array = []
func _cover(on:bool):
	if on:
		var main = menu.get_node_or_null("Main")
		if main:
			for c in main.get_children():
				if c is CanvasItem and c.visible:
					c.visible = false
					covered.append(c)
	else:
		for c in covered:
			if is_instance_valid(c): c.visible = true
		covered = []

# the game's own music (menu music / the map-page preview, nodes named MenuSong) keeps playing
# behind the editor and mixes with the song being edited: pause every other player while the
# editor is open, put them back on exit
var other_players:Array = []
var hushed:Array = []
var _hush_t:float = 0.0
func _find_players():
	other_players = []
	var stack = [get_tree().root]
	while !stack.empty():
		var n = stack.pop_back()
		if n == self or n == ap: continue
		for c in n.get_children(): stack.append(c)
		if n is AudioStreamPlayer and !(self.is_a_parent_of(n)): other_players.append(n)

func _hush():
	for n in other_players:
		if is_instance_valid(n) and n.playing and !n.stream_paused:
			n.stream_paused = true
			hushed.append(n)

func _unhush():
	for n in hushed:
		if is_instance_valid(n): n.stream_paused = false
	hushed = []

func _exit_tree():
	_unhush()
	_cover(false)
	if is_instance_valid(ap): ap.stop()
	var eb = AudioServer.get_bus_index("RREdit")
	if eb >= 0: AudioServer.set_bus_effect_enabled(eb, 0, false)
	_wave_cleanup()
	if star_thread and star_thread.is_active(): star_thread.wait_to_finish()
	if auto_thread and auto_thread.is_active(): auto_thread.wait_to_finish()

# ------------------------------------------------------------------ live difficulty
# The game's own star rating (stars/StarRating.gd, the same numbers the map list shows), redone on a
# worker thread 0.4 s after the notes last changed - a 13k-note map takes ~70 ms, which must not
# stall editing - and only when the notes really differ from the last rated set. Also the average
# and peak (busiest second) notes per second. "..." = an update is pending / running.
const STAR_DEBOUNCE = 0.4
var star_lbl:Label
var star_thread:Thread = null
var star_rev:int = -1        # rev of the notes the shown rating belongs to
var star_due:float = -1.0    # seconds until the next rating starts (< 0 = none pending)
var star_key:String = ""
var star_val:float = -1.0
var star_nps:Array = [0.0, 0.0]

func _star_tick(delta:float):
	if !star_lbl or !m or !ResourceLoader.exists("res://mods/stars/StarRating.gd"): return
	if m.rev != star_rev and star_due < 0: star_due = STAR_DEBOUNCE
	if star_due >= 0:
		star_due -= delta
		if star_due < 0:
			if star_thread and star_thread.is_active(): star_due = 0.05 # (still busy with the previous set)
			else:
				star_rev = m.rev
				var notes = m.notes.duplicate(true) # (the worker gets its own copy)
				var key = str(notes.size()) + ":" + str(notes.hash())
				if key != star_key: # (an edit and its undo: same notes, same rating)
					star_key = key
					star_thread = Thread.new()
					star_thread.start(self, "_star_work", notes)
	_star_show()

func _star_work(notes:Array):
	var stars = load("res://mods/stars/StarRating.gd").new().calculate(notes, 1.0) if notes.size() > 1 else 0.0
	call_deferred("_star_done", stars, Model.nps(notes))

func _star_done(stars:float, nps:Array):
	if star_thread and star_thread.is_active(): star_thread.wait_to_finish()
	star_val = stars
	star_nps = nps
	_star_show()

func _star_show():
	var pending = star_due >= 0 or (star_thread and star_thread.is_active())
	if star_val < 0:
		star_lbl.text = "★ ..."
		return
	star_lbl.text = "★ %.2f%s   %.1f nps, peak %.0f" % [star_val, " ..." if pending else "", star_nps[0], star_nps[1]]
	star_lbl.hint_tooltip = "Star rating (the game's own formula, at 1.0x); updates a moment after you edit.\nAverage notes per second over the map, and the busiest second."

func _font(size:int):
	if fonts.has(size): return fonts[size]
	var base = root.get_font("font", "Label")
	var f = base
	if base is DynamicFont:
		f = base.duplicate()
		f.size = size
	f = load("res://mods/replay/Reimagined.gd").heading_font(f, size)
	fonts[size] = f
	return f

func _lbl(text:String, size:int = 14, col:Color = Look.TEXT_2) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", _font(size))
	l.add_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _btn(text:String, method:String, args:Array = [], toggle:bool = false, w:int = 0) -> Button:
	var b = Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.add_font_override("font", _font(14))
	b.rect_min_size = Vector2(w, 30)
	var ink = Look.TEXT
	b.add_stylebox_override("normal", Look.box(Look.SURFACE, Look.LINE_HI, 1, 0))
	b.add_stylebox_override("hover", Look.box(Look.accent(), Look.accent(), 1, 0))
	b.add_stylebox_override("pressed", Look.box(Look.accent(), Look.accent(), 1, 0))
	b.add_stylebox_override("hover_pressed", Look.box(Look.accent(), Look.accent(), 1, 0))
	b.add_stylebox_override("disabled", Look.box(Look.BG, Look.LINE, 1, 0))
	b.add_color_override("font_color", ink)
	b.add_color_override("font_color_hover", Look.on_accent())
	b.add_color_override("font_color_pressed", Look.on_accent())
	b.add_color_override("font_color_hover_pressed", Look.on_accent())
	b.add_color_override("font_color_disabled", Look.TEXT_3)
	b.connect("toggled" if toggle else "pressed", self, method, args)
	return b

func _style_input(c:Control):
	var f = _font(14)
	if c is LineEdit:
		c.add_font_override("font", f)
		c.add_stylebox_override("normal", Look.box(Look.SURFACE, Look.LINE_HI, 1, 0))
		c.add_stylebox_override("focus", Look.box(Look.SURFACE_HI, Look.accent(), 1, 0))
		c.add_stylebox_override("read_only", Look.box(Look.BG, Look.LINE, 1, 0))
		c.add_color_override("font_color", Look.TEXT)
		c.add_color_override("font_color_uneditable", Look.TEXT_3)
	elif c is OptionButton:
		c.add_font_override("font", f)
		c.focus_mode = Control.FOCUS_NONE
		c.add_stylebox_override("normal", Look.box(Look.SURFACE, Look.LINE_HI, 1, 0))
		c.add_stylebox_override("hover", Look.box(Look.SURFACE_HI, Look.accent(), 1, 0))
		c.add_stylebox_override("pressed", Look.box(Look.SURFACE_HI, Look.accent(), 1, 0))
		c.add_color_override("font_color", Look.TEXT)
		c.add_color_override("font_color_hover", Look.TEXT)
		c.add_color_override("font_color_pressed", Look.TEXT)
		var pop = c.get_popup()
		pop.add_font_override("font", f)
		pop.add_stylebox_override("panel", Look.box(Look.SURFACE_HI, Look.LINE_HI, 1, 0))
		pop.add_stylebox_override("hover", Look.box(Look.accent(), Look.accent(), 1, 0))
		pop.add_color_override("font_color_hover", Look.on_accent())
	elif c is SpinBox:
		_style_input(c.get_line_edit())
	elif c is ItemList:
		c.add_font_override("font", f)
		c.add_stylebox_override("bg", Look.box(Look.SURFACE, Look.LINE, 1, 0))
		c.add_stylebox_override("selected", Look.box(Look.accent(), Look.accent(), 1, 0))
		c.add_stylebox_override("selected_focus", Look.box(Look.accent(), Look.accent(), 1, 0))
		c.add_color_override("font_color", Look.TEXT_2)
		c.add_color_override("font_color_selected", Look.on_accent())

func _panel_style(bg:Color) -> StyleBoxFlat:
	return Look.box(bg, Look.LINE, 1, 0)

# editing playback goes through its own bus (into the game's Music bus) so slow speeds can keep the
# song's pitch with a pitch shifter that is only enabled when speed != 1: no delay at normal speed
func _edit_bus() -> String:
	var bus = AudioServer.get_bus_index("RREdit")
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus, "RREdit")
		AudioServer.add_bus_effect(bus, AudioEffectPitchShift.new())
		AudioServer.set_bus_effect_enabled(bus, 0, false)
	bus = AudioServer.get_bus_index("RREdit")
	AudioServer.set_bus_send(bus, "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master")
	return "RREdit"

func _apply_speed():
	ap.pitch_scale = speed
	var bus = AudioServer.get_bus_index("RREdit")
	if bus >= 0 and AudioServer.get_bus_effect_count(bus) > 0:
		var fx = AudioServer.get_bus_effect(bus, 0)
		if fx is AudioEffectPitchShift: fx.pitch_scale = 1.0 / speed # (the tape-style pitch change of pitch_scale cancelled out)
		AudioServer.set_bus_effect_enabled(bus, 0, speed != 1.0)

func _build_audio():
	ap = AudioStreamPlayer.new()
	ap.bus = _edit_bus()
	add_child(ap)
	var hs = Rhythia.get_stream_with_default("user://hit", Rhythia.def_hit_snd)
	for i in 4:
		var p = AudioStreamPlayer.new()
		p.stream = hs
		p.volume_db = -8
		p.bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
		add_child(p)
		hit_players.append(p)
	click_player = AudioStreamPlayer.new()
	click_player.stream = Rhythia.get_stream_with_default("user://miss", Rhythia.def_miss_snd)
	click_player.volume_db = -14
	click_player.bus = hit_players[0].bus
	add_child(click_player)

# ------------------------------------------------------------------ top bar
func _build_top():
	var bar = Panel.new()
	bar.add_stylebox_override("panel", _panel_style(Look.SURFACE))
	bar.anchor_right = 1
	bar.margin_bottom = 52
	root.add_child(bar)
	var h = HBoxContainer.new()
	h.anchor_right = 1
	h.anchor_bottom = 1
	h.margin_left = 14
	h.margin_right = -14
	h.margin_top = 10
	h.margin_bottom = -10
	h.add_constant_override("separation", 8)
	bar.add_child(h)
	var t = _lbl("// EDITOR", 20, Look.TEXT)
	t.rect_min_size = Vector2(130, 0)
	t.valign = Label.VALIGN_CENTER
	h.add_child(t)
	state_lbl = _lbl("", 14, Look.TEXT_2)
	state_lbl.rect_min_size = Vector2(110, 0) # (the bar fits 1280 px: EXIT was cut off)
	state_lbl.valign = Label.VALIGN_CENTER
	h.add_child(state_lbl)
	star_lbl = _lbl("★ ...", 14, Look.TEXT)
	star_lbl.rect_min_size = Vector2(200, 0)
	star_lbl.valign = Label.VALIGN_CENTER
	star_lbl.mouse_filter = Control.MOUSE_FILTER_PASS # (its tooltip)
	h.add_child(star_lbl)
	for b in [["NEW", "_ask_new"], ["OPEN", "_ask_open"], ["SAVE", "_save_pressed"], ["EXPORT", "_export"]]:
		h.add_child(_btn(b[0], b[1], [], false, 78))
	h.add_child(_btn("TEST (F5)", "_test", [false], false, 100))
	h.add_child(_btn("TEST FROM HERE", "_test", [true], false, 150))
	top_msg = _lbl("", 14, Look.TEXT_2)
	top_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_msg.valign = Label.VALIGN_CENTER
	top_msg.clip_text = true
	h.add_child(top_msg)
	h.add_child(_btn("EXIT (ESC)", "_exit", [], false, 110))

func msg(s:String, bad:bool = false):
	top_msg.text = s
	top_msg.add_color_override("font_color", Look.CRIT.lightened(0.2) if bad else Look.TEXT_2)

# ------------------------------------------------------------------ left panel
func _build_left():
	var p = Panel.new()
	p.add_stylebox_override("panel", _panel_style(Look.SURFACE))
	p.anchor_bottom = 1
	p.margin_top = 52
	p.margin_right = 340
	p.margin_bottom = -270
	root.add_child(p)
	var v = VBoxContainer.new()
	v.anchor_right = 1
	v.anchor_bottom = 1
	v.margin_left = 10
	v.margin_right = -10
	v.margin_top = 10
	v.margin_bottom = -10
	v.add_constant_override("separation", 8)
	p.add_child(v)
	var tabs = HBoxContainer.new()
	tabs.add_constant_override("separation", 4)
	v.add_child(tabs)
	var grp = ButtonGroup.new()
	for t in [["props", "PROPS"], ["timing", "TIMING"], ["notes", "NOTES"], ["auto", "AUTO"], ["checks", "CHECKS"]]:
		var b = _btn(t[1], "_page_tab", [t[0]], true, 60)
		b.group = grp
		tabs.add_child(b)
		page_btns[t[0]] = b
	for id in ["props", "timing", "notes", "auto", "checks"]:
		var sc = ScrollContainer.new()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.scroll_horizontal_enabled = false
		v.add_child(sc)
		var pv = VBoxContainer.new()
		pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pv.rect_min_size.x = 300
		pv.add_constant_override("separation", 7)
		sc.add_child(pv)
		pages[id] = [sc, pv]
	_build_props(pages.props[1])
	_build_timing(pages.timing[1])
	_build_notes(pages.notes[1])
	_build_auto(pages.auto[1])
	_build_checks(pages.checks[1])
	_page("props")
	page_btns.props.pressed = true

func _page_tab(pressed:bool, id:String):
	if pressed and !_paging: _page(id)

var _paging:bool = false
func _page(id:String):
	for k in pages: pages[k][0].visible = k == id
	if id == "notes": _refresh_note_list()
	if id == "checks": _run_checks()
	if page_btns.has(id) and !page_btns[id].pressed: # (opened from code: the tab follows)
		_paging = true
		page_btns[id].pressed = true
		_paging = false

func _field_row(parent:Control, label:String, ctl:Control):
	parent.add_child(_lbl(label.to_upper(), 12, Look.TEXT_3))
	_style_input(ctl)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(ctl)

func _build_props(p:Control):
	f_id = LineEdit.new()
	f_id.connect("text_changed", self, "_prop_changed", ["id"])
	_field_row(p, "Map id (file name)", f_id)
	f_name = LineEdit.new()
	f_name.connect("text_changed", self, "_prop_changed", ["name"])
	_field_row(p, "Song title", f_name)
	f_creator = LineEdit.new()
	f_creator.connect("text_changed", self, "_prop_changed", ["creator"])
	_field_row(p, "Mapper", f_creator)
	f_diff = OptionButton.new()
	for i in DIFFS.size(): f_diff.add_item(DIFFS[i], i)
	f_diff.connect("item_selected", self, "_diff_changed")
	_field_row(p, "Difficulty", f_diff)
	p.add_child(_lbl("AUDIO", 12, Look.TEXT_3))
	audio_lbl = _lbl("", 13, Look.TEXT_2)
	audio_lbl.autowrap = true
	audio_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	audio_lbl.rect_min_size.x = 290
	p.add_child(audio_lbl)
	p.add_child(_btn("CHANGE AUDIO...", "_pick_audio", [false]))
	var note = _lbl("Only fields the .sspm format stores are listed. BPM / offset are editor aids (TIMING tab), they are not saved in the map.", 12, Look.TEXT_3)
	note.autowrap = true
	note.rect_min_size.x = 290
	p.add_child(note)

func _prop_changed(txt:String, key:String):
	if _lock_ui or !m: return
	if key == "id":
		txt = txt.to_lower()
		if txt != f_id.text:
			var c = f_id.caret_position
			f_id.text = txt
			f_id.caret_position = c
	m.meta[key] = txt
	m.dirty = true
	m.rev += 1

func _diff_changed(i:int):
	if _lock_ui or !m: return
	m.meta.difficulty = i - 1
	m.dirty = true
	m.rev += 1

func _build_timing(p:Control):
	sp_bpm = SpinBox.new()
	sp_bpm.min_value = 20
	sp_bpm.max_value = 400
	sp_bpm.step = 0.001
	sp_bpm.connect("value_changed", self, "_timing_changed")
	_field_row(p, "BPM (editor grid only)", sp_bpm)
	sp_off = SpinBox.new()
	sp_off.min_value = -5000
	sp_off.max_value = 60000
	sp_off.step = 1
	sp_off.suffix = "ms"
	sp_off.connect("value_changed", self, "_timing_changed")
	_field_row(p, "Offset (first beat)", sp_off)
	ob_div = OptionButton.new()
	for i in SNAPS.size(): ob_div.add_item("1/%d beat" % SNAPS[i] if SNAPS[i] > 1 else "1 beat", SNAPS[i])
	ob_div.connect("item_selected", self, "_div_changed")
	_field_row(p, "Grid resolution", ob_div)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 4)
	for pr in [[4, "1/4"], [8, "1/8"], [3, "1/3"], [6, "1/6"], [12, "1/12"]]:
		row.add_child(_btn(pr[1], "_set_div", [pr[0]], false, 52))
	p.add_child(_lbl("GRID PRESETS", 12, Look.TEXT_3))
	p.add_child(row)
	var ck = CheckBox.new()
	ck.text = "Snap time to grid"
	ck.pressed = true
	ck.focus_mode = Control.FOCUS_NONE
	ck.add_font_override("font", _font(14))
	ck.connect("toggled", self, "_set_time_snap")
	p.add_child(ck)
	p.add_child(_lbl("NOTE POSITION SNAP", 12, Look.TEXT_3))
	var pr = HBoxContainer.new()
	pr.add_constant_override("separation", 4)
	var g = ButtonGroup.new()
	for s in [["cell", "CELLS"], ["half", "HALF"], ["free", "FREE"]]:
		var b = _btn(s[1], "_set_pos_snap", [s[0]], true, 90)
		b.group = g
		b.pressed = s[0] == "cell"
		pr.add_child(b)
		pos_btns[s[0]] = b
	p.add_child(pr)
	var ck2 = CheckBox.new()
	ck2.text = "Advance one grid step after placing"
	ck2.focus_mode = Control.FOCUS_NONE
	ck2.add_font_override("font", _font(14))
	ck2.connect("toggled", self, "_set_advance")
	p.add_child(ck2)
	var ck3 = CheckBox.new()
	ck3.text = "Hit sound on notes while playing"
	ck3.pressed = true
	ck3.focus_mode = Control.FOCUS_NONE
	ck3.add_font_override("font", _font(14))
	ck3.connect("toggled", self, "_set_hit_sound")
	p.add_child(ck3)
	var ck4 = CheckBox.new()
	ck4.text = "Metronome (click on every beat)"
	ck4.focus_mode = Control.FOCUS_NONE
	ck4.add_font_override("font", _font(14))
	ck4.connect("toggled", self, "_set_metronome")
	p.add_child(ck4)
	p.add_child(_lbl("TOOLS", 12, Look.TEXT_3))
	var r1 = HBoxContainer.new()
	r1.add_constant_override("separation", 4)
	r1.add_child(_btn("TAP BPM", "_tap", [], false, 96))
	r1.add_child(_btn("OFFSET = HERE", "_offset_here", [], false, 150))
	p.add_child(r1)
	p.add_child(_btn("SNAP SELECTION TO GRID", "_snap_selection"))
	p.add_child(_lbl("TIMING POINTS (BPM CHANGES, CTRL+SHIFT+B)", 12, Look.TEXT_3))
	var tr = HBoxContainer.new()
	tr.add_constant_override("separation", 4)
	tr.add_child(_btn("ADD HERE", "_point_add", [], false, 110))
	tr.add_child(_btn("REMOVE", "_point_remove", [], false, 90))
	p.add_child(tr)
	pt_list = ItemList.new()
	pt_list.rect_min_size = Vector2(0, 70)
	pt_list.connect("item_selected", self, "_point_pick")
	_style_input(pt_list)
	p.add_child(pt_list)
	sp_pt = SpinBox.new()
	sp_pt.min_value = 20
	sp_pt.max_value = 400
	sp_pt.step = 0.001
	sp_pt.editable = false
	sp_pt.connect("value_changed", self, "_point_bpm")
	_field_row(p, "BPM from the selected point", sp_pt)
	p.add_child(_lbl("BOOKMARKS", 12, Look.TEXT_3))
	var br = HBoxContainer.new()
	br.add_constant_override("separation", 4)
	br.add_child(_btn("ADD HERE (B)", "_bookmark_add", [], false, 130))
	br.add_child(_btn("REMOVE", "_bookmark_remove", [], false, 90))
	p.add_child(br)
	book_list = ItemList.new()
	book_list.rect_min_size = Vector2(0, 90)
	book_list.connect("item_selected", self, "_bookmark_go")
	_style_input(book_list)
	p.add_child(book_list)

func _build_notes(p:Control):
	p.add_child(_lbl("SELECTION", 12, Look.TEXT_3))
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 4)
	for f in [["t", "ms", 0.0, 36000000.0, 1.0], ["x", "x", -1.0, 3.0, 0.01], ["y", "y", -1.0, 3.0, 0.01]]:
		var c = VBoxContainer.new()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_child(_lbl(f[1].to_upper(), 12, Look.TEXT_3))
		var sb = SpinBox.new()
		sb.min_value = f[2]
		sb.max_value = f[3]
		sb.step = f[4]
		sb.editable = false
		sb.connect("value_changed", self, "_insp_changed", [f[0]])
		_style_input(sb)
		c.add_child(sb)
		row.add_child(c)
		insp[f[0]] = sb
	p.add_child(row)
	insp.info = _lbl("nothing selected", 13, Look.TEXT_2)
	p.add_child(insp.info)
	p.add_child(_lbl("OPERATIONS ON THE SELECTION", 12, Look.TEXT_3))
	var g1 = GridContainer.new()
	g1.columns = 2
	g1.add_constant_override("hseparation", 4)
	g1.add_constant_override("vseparation", 4)
	for b in [["MIRROR X", "_op_mirror", [true]], ["MIRROR Y", "_op_mirror", [false]], ["ROTATE 90", "_op_rotate", []],
			["DELETE", "_delete_sel", []], ["-1 ms", "_op_nudge", [-1]], ["+1 ms", "_op_nudge", [1]],
			["-10 ms", "_op_nudge", [-10]], ["+10 ms", "_op_nudge", [10]], ["-1 step", "_op_step", [-1]], ["+1 step", "_op_step", [1]],
			["REPEAT x2", "_op_repeat", [2]], ["REPEAT x4", "_op_repeat", [4]]]:
		var bt = _btn(b[0], b[1], b[2])
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g1.add_child(bt)
	p.add_child(g1)
	p.add_child(_lbl("NOTE LIST (time filter, e.g. 1:00-1:30)", 12, Look.TEXT_3))
	note_list_filter = LineEdit.new()
	note_list_filter.placeholder_text = "all"
	note_list_filter.connect("text_changed", self, "_note_filter_changed")
	_style_input(note_list_filter)
	p.add_child(note_list_filter)
	note_list = ItemList.new()
	note_list.rect_min_size = Vector2(0, 220)
	note_list.connect("item_selected", self, "_note_list_pick")
	_style_input(note_list)
	p.add_child(note_list)

func _build_checks(p:Control):
	p.add_child(_btn("RUN CHECKS", "_run_checks"))
	diag_list = ItemList.new()
	diag_list.rect_min_size = Vector2(0, 200)
	diag_list.connect("item_selected", self, "_diag_pick")
	_style_input(diag_list)
	p.add_child(diag_list)
	p.add_child(_lbl("HISTORY (newest first)", 12, Look.TEXT_3))
	var hr = HBoxContainer.new()
	hr.add_constant_override("separation", 4)
	hr.add_child(_btn("UNDO", "_undo", [], false, 80))
	hr.add_child(_btn("REDO", "_redo", [], false, 80))
	p.add_child(hr)
	hist_list = ItemList.new()
	hist_list.rect_min_size = Vector2(0, 160)
	hist_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_input(hist_list)
	p.add_child(hist_list)

# ------------------------------------------------------------------ field (3x3 grid: where notes are)
func _build_field():
	field = Control.new()
	field.anchor_right = 1
	field.anchor_bottom = 1
	field.margin_left = 340
	field.margin_top = 52
	field.margin_bottom = -270
	field.mouse_filter = Control.MOUSE_FILTER_STOP
	field.connect("draw", self, "_draw_field")
	field.connect("gui_input", self, "_field_input")
	field.connect("mouse_exited", self, "_field_exit")
	root.add_child(field)

func _field_geom() -> Rect2:
	var s = min(field.rect_size.x, field.rect_size.y) - 90.0
	s = max(s, 120.0)
	return Rect2((field.rect_size - Vector2(s, s)) / 2, Vector2(s, s))

# grid coordinate (note x / y units) of a screen point inside the field control
func _to_grid(p:Vector2) -> Vector2:
	var g = _field_geom()
	var cell = g.size.x / 3.0
	return Vector2((p.x - g.position.x) / cell - 0.5, (p.y - g.position.y) / cell - 0.5)

func _snap_pos(v:Vector2) -> Vector2:
	match pos_snap:
		"cell": return Vector2(clamp(round(v.x), 0, 2), clamp(round(v.y), 0, 2))
		"half": return Vector2(clamp(round(v.x * 2.0) / 2.0, 0, 2), clamp(round(v.y * 2.0) / 2.0, 0, 2))
	return Vector2(clamp(stepify(v.x, 0.01), -0.5, 2.5), clamp(stepify(v.y, 0.01), -0.5, 2.5))

func _place_ms() -> int:
	return m.snap_t(pos) if _snapping() else int(round(pos))

# time snap, unless Alt is held (a precise placement / drag without switching the snap off)
func _snapping() -> bool:
	return time_snap and !Input.is_key_pressed(KEY_ALT)

func _drop_focus(ev):
	if ev is InputEventMouseButton and ev.pressed:
		var fo = root.get_focus_owner()
		if fo: fo.release_focus()

func _field_input(ev):
	_drop_focus(ev)
	if !m: return
	if ev is InputEventMouseMotion:
		hover_cell = _to_grid(ev.position)
		if field_drag != null:
			var d = _snap_pos(hover_cell) - _snap_pos(field_drag.start) if pos_snap != "free" else hover_cell - field_drag.start
			if drag_delta != d:
				drag_delta = d
		field.update()
	elif ev is InputEventMouseButton:
		var gp = _to_grid(ev.position)
		if ev.button_index == BUTTON_LEFT and ev.pressed:
			var hit = _note_at(gp)
			if hit != null:
				if ev.shift or ev.control:
					if sel.has(Model.key_of(hit)): sel.erase(Model.key_of(hit))
					else: sel[Model.key_of(hit)] = hit
				elif !sel.has(Model.key_of(hit)):
					sel = {Model.key_of(hit): hit}
				field_drag = {"start": gp}
				drag_delta = Vector2.ZERO
			else:
				_place_note(_snap_pos(gp))
			_sel_changed()
		elif ev.button_index == BUTTON_LEFT and !ev.pressed:
			if field_drag != null and drag_delta != Vector2.ZERO: _move_selection(drag_delta, 0)
			field_drag = null
			drag_delta = Vector2.ZERO
			field.update()
		elif ev.button_index == BUTTON_RIGHT and ev.pressed:
			var hit2 = _note_at(gp)
			if hit2 != null:
				m.begin("delete note")
				m.run(["del", [hit2]])
				m.end()
				sel.erase(Model.key_of(hit2))
				_sel_changed()
		elif ev.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN] and ev.pressed:
			_seek(_step_from(pos, 1 if ev.button_index == BUTTON_WHEEL_UP else -1))

func _field_exit():
	hover_cell = Vector2(-9, -9)
	field.update()

# the note near a grid point among the ones the field shows now
func _note_at(gp:Vector2):
	var best = null
	var bd = 0.36
	var i = m.lower_bound(pos - 120.0)
	while i < m.notes.size() and m.notes[i][2] <= pos + APPROACH:
		var n = m.notes[i]
		var d = Vector2(n[0], n[1]).distance_to(gp)
		var near_t = abs(n[2] - pos) < 120.0 or n[2] > pos
		if near_t and d < bd:
			bd = d
			best = n
		i += 1
	return best

func _place_note(g:Vector2):
	var ms = _place_ms()
	if ms < 0: ms = 0
	var n = [g.x, g.y, ms]
	if m.has_note(n):
		msg("a note is already there")
		return
	m.begin("place note")
	m.run(["add", [n]])
	m.end()
	sel = {Model.key_of(n): n}
	if advance: _seek(m.grid_next(ms, 1))
	_sel_changed()

# where the pattern cursor is at time t (grid units): rests on a note, then glides to the next one and
# arrives exactly on its time (up to 600 ms of travel), so the mapper sees how the pattern moves
func _cursor_at(t:float):
	var i = m.lower_bound(t)
	if i >= m.notes.size():
		if m.notes.empty(): return null
		var l = m.notes[m.notes.size() - 1]
		return Vector2(l[0], l[1])
	var nx = m.notes[i]
	if i == 0: return Vector2(nx[0], nx[1])
	var pv = m.notes[i - 1]
	var span = min(nx[2] - pv[2], 600.0)
	var k = clamp((t - (nx[2] - span)) / max(span, 1.0), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return Vector2(pv[0], pv[1]).linear_interpolate(Vector2(nx[0], nx[1]), k)

func _toggle_cursor():
	show_cursor = !show_cursor
	field.update()

func _draw_cursor(c:Control, g:Rect2, cell:float):
	if !show_cursor or m.notes.empty(): return
	var prev = null
	for j in range(12, -1, -1):
		var q = _cursor_at(pos - j * 22.0)
		if q == null: return
		var p = Vector2(g.position.x + (q.x + 0.5) * cell, g.position.y + (q.y + 0.5) * cell)
		if prev != null: c.draw_line(prev, p, Color(1, 1, 1, 0.5 * (1.0 - j / 13.0)), 1.0 + 3.0 * (1.0 - j / 13.0))
		prev = p
	c.draw_circle(prev, 9.0, Color(1, 1, 1, 1.0))
	c.draw_circle(prev, 4.0, Color(0.02, 0.02, 0.024, 1.0))
	c.draw_arc(prev, 15.0, 0, TAU, 28, Color(1, 1, 1, 0.7), 2.0)

func _draw_field():
	var c = field
	var g = _field_geom()
	var cell = g.size.x / 3.0
	c.draw_rect(g, Look.SURFACE)
	for i in 4:
		c.draw_line(Vector2(g.position.x + i * cell, g.position.y), Vector2(g.position.x + i * cell, g.end.y), Look.LINE, 1.0)
		c.draw_line(Vector2(g.position.x, g.position.y + i * cell), Vector2(g.end.x, g.position.y + i * cell), Look.LINE, 1.0)
	c.draw_rect(g, Look.LINE_HI, false, 1.0)
	Look.brackets(c, g.grow(10), 22.0, Look.LINE_HI, 2.0)
	if !m:
		return
	var lf = _font(12)
	for k in 9: # (grid key of each cell)
		c.draw_string(lf, Vector2(g.position.x + (k % 3) * cell + 6, g.position.y + (k / 3) * cell + 16), GRID_LETTERS[k], Color(1, 1, 1, 0.16))
	# ghost under the mouse
	if hover_cell.x > -5:
		var sp = _snap_pos(hover_cell)
		var h = Vector2(g.position.x + (sp.x + 0.5) * cell, g.position.y + (sp.y + 0.5) * cell)
		var hs = cell * 0.5
		c.draw_rect(Rect2(h - Vector2(hs, hs) / 2, Vector2(hs, hs)), Color(1, 1, 1, 0.12))
		c.draw_rect(Rect2(h - Vector2(hs, hs) / 2, Vector2(hs, hs)), Look.LINE_HI, false, 1.0)
	var ns = cell * 0.5
	var i = m.lower_bound(pos - 220.0)
	while i < m.notes.size() and m.notes[i][2] <= pos + APPROACH:
		var n = m.notes[i]
		var dt = n[2] - pos
		var gx = n[0]
		var gy = n[1]
		var is_sel = sel.has(Model.key_of(n))
		if is_sel and field_drag != null:
			gx += drag_delta.x
			gy += drag_delta.y
		var ctr = Vector2(g.position.x + (gx + 0.5) * cell, g.position.y + (gy + 0.5) * cell)
		var a = 1.0
		var sc = 1.0
		if dt > 0:
			sc = 1.0 + (dt / APPROACH) * 1.4
			a = 1.0 - dt / APPROACH * 0.75
		else:
			a = clamp(1.0 + dt / 220.0, 0.0, 1.0)
		var col = Color(1, 1, 1, a)
		if is_sel: col = Color(1, 0.35, 0.4, a)
		var sz = ns * sc
		var r = Rect2(ctr - Vector2(sz, sz) / 2, Vector2(sz, sz))
		if dt <= 0 or dt < 40:
			var core = Rect2(ctr - Vector2(ns, ns) / 2, Vector2(ns, ns))
			c.draw_rect(core, Color(col.r, col.g, col.b, a * 0.55))
			c.draw_rect(core, col, false, 2.0)
		else:
			c.draw_rect(r, col, false, 1.5)
		i += 1
	_draw_cursor(c, g, cell) # on top of the notes
	c.draw_string(_font(13), Vector2(g.position.x, g.end.y + 34), "%d selected / %d notes   playhead %s" % [sel.size(), m.notes.size(), Model.fmt_time(int(pos))], Look.TEXT_3)

# ------------------------------------------------------------------ timeline
func _build_timeline():
	var p = Panel.new()
	p.add_stylebox_override("panel", _panel_style(Look.SURFACE))
	p.anchor_top = 1
	p.anchor_right = 1
	p.anchor_bottom = 1
	p.margin_top = -270
	root.add_child(p)
	var bar = HBoxContainer.new()
	bar.anchor_right = 1
	bar.margin_left = 12
	bar.margin_right = -12
	bar.margin_top = 8
	bar.margin_bottom = 40
	bar.add_constant_override("separation", 6)
	p.add_child(bar)
	bar.add_child(_btn("|<", "_seek_start", [], false, 40))
	bar.add_child(_btn("PLAY / PAUSE (SPACE)", "_toggle_play", [], false, 200))
	var sb = OptionButton.new()
	for s in [[0.5, "0.5x"], [0.75, "0.75x"], [1.0, "1.0x"]]: sb.add_item(s[1])
	sb.select(2)
	sb.connect("item_selected", self, "_speed_changed")
	_style_input(sb)
	sb.rect_min_size.x = 84
	bar.add_child(sb)
	bar.add_child(_btn("LOOP (L)", "_set_loop", [], true, 90))
	bar.add_child(_btn("A [", "_loop_mark", [true], false, 50))
	bar.add_child(_btn("B ]", "_loop_mark", [false], false, 50))
	bar.add_child(_btn("-", "_zoom_btn", [0.8], false, 36))
	bar.add_child(_btn("+", "_zoom_btn", [1.25], false, 36))
	bar.add_child(_btn("FIT", "_zoom_fit", [], false, 54))
	time_lbl = _lbl("", 15, Look.TEXT)
	time_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_lbl.valign = Label.VALIGN_CENTER
	time_lbl.align = Label.ALIGN_RIGHT
	bar.add_child(time_lbl)
	tl = Control.new()
	tl.anchor_right = 1
	tl.anchor_bottom = 1
	tl.margin_top = 46
	tl.margin_left = 12
	tl.margin_right = -12
	tl.margin_bottom = -8
	tl.mouse_filter = Control.MOUSE_FILTER_STOP
	tl.connect("draw", self, "_draw_tl")
	tl.connect("gui_input", self, "_tl_input")
	tl.connect("resized", self, "_tl_resized")
	p.add_child(tl)

const RULER = 22.0
const MINIMAP = 30.0

func _tl_resized():
	_tl_dirty = true
	wave_lines = null

func _span() -> float:
	return tl.rect_size.x / ppm

func _x_of(t:float) -> float:
	return (t - view0) * ppm

func _t_of(x:float) -> float:
	return view0 + x / ppm

func _lane_rect() -> Rect2:
	return Rect2(0, RULER, tl.rect_size.x, tl.rect_size.y - RULER - MINIMAP - 6)

func _total_ms() -> float:
	var last = m.notes[m.notes.size() - 1][2] if m and !m.notes.empty() else 0.0
	return max(audio_len, last + 2000.0)

func _clamp_view():
	view0 = clamp(view0, -1000.0, max(_total_ms() - _span() + 1000.0, -1000.0))

func _draw_tl():
	var c = tl
	var sz = c.rect_size
	var lane = _lane_rect()
	c.draw_rect(Rect2(0, 0, sz.x, sz.y), Look.BG)
	if !m: return
	var span = _span()
	var t0 = view0
	var t1 = view0 + span
	# loop region / waveform backdrop
	if loop_a >= 0 and loop_b > loop_a:
		c.draw_rect(Rect2(_x_of(loop_a), lane.position.y, (loop_b - loop_a) * ppm, lane.size.y), Color(1, 1, 1, 0.06))
	# ruler + beat grid
	c.draw_rect(Rect2(0, 0, sz.x, RULER), Look.SURFACE)
	var beat_px = 60000.0 / m.bpm * ppm
	for pt in m.points: beat_px = min(beat_px, 60000.0 / pt[1] * ppm) # (the densest section decides the stride)
	var bstep = 1
	while beat_px * bstep < 7.0: bstep *= 2
	var font = _font(11)
	for gl in m.grid_lines(t0, t1, beat_px / m.div >= 6.0, bstep):
		var x = _x_of(gl[0])
		if gl[1] == 2:
			c.draw_line(Vector2(x, lane.position.y), Vector2(x, lane.end.y), Color(1, 1, 1, 0.03), 1.0)
			continue
		var measure = gl[1] == 0
		c.draw_line(Vector2(x, RULER - (10 if measure else 5)), Vector2(x, RULER), Look.TEXT_2 if measure else Look.TEXT_3, 1.0)
		c.draw_line(Vector2(x, lane.position.y), Vector2(x, lane.end.y), Color(1, 1, 1, 0.13 if measure else 0.06), 1.0)
	# timing points (BPM changes): a line through the lane + the new BPM on the ruler
	for pt in m.points:
		if pt[0] < t0 or pt[0] > t1: continue
		var px = _x_of(pt[0])
		c.draw_line(Vector2(px, 0), Vector2(px, lane.end.y), Color(0.3, 0.9, 1.0, 0.7), 2.0)
		c.draw_string(font, Vector2(px + 4, RULER - 2), "%s BPM" % _num_txt(pt[1]), Color(0.3, 0.9, 1.0))
	# time labels (every ~120 px)
	var tstep = _nice_step(120.0 / ppm)
	var tt = ceil(t0 / tstep) * tstep
	while tt <= t1:
		c.draw_string(font, Vector2(_x_of(tt) + 4, 11), Model.fmt_time(int(tt)), Look.TEXT_2)
		tt += tstep
	# waveform
	_draw_wave(c, lane)
	_draw_auto(c, lane, t0, t1)
	# note ticks
	_draw_ticks(c, lane)
	# bookmarks
	for bm in m.bookmarks:
		var bx = _x_of(bm)
		if bx >= 0 and bx <= sz.x:
			c.draw_line(Vector2(bx, 0), Vector2(bx, lane.end.y), Color(1, 1, 1, 0.5), 1.0)
			c.draw_rect(Rect2(bx, 0, 7, 7), Color(1, 1, 1, 0.9))
	# selection box
	if box_sel != null:
		var xa = _x_of(min(box_sel.a, box_sel.b))
		var xb = _x_of(max(box_sel.a, box_sel.b))
		c.draw_rect(Rect2(xa, lane.position.y, xb - xa, lane.size.y), Color(1, 1, 1, 0.1))
		c.draw_rect(Rect2(xa, lane.position.y, xb - xa, lane.size.y), Look.LINE_HI, false, 1.0)
	# playhead
	var px = _x_of(pos)
	if px >= -4 and px <= sz.x + 4:
		var col = Color(1, 1, 1, 0.95)
		c.draw_line(Vector2(px, 0), Vector2(px, lane.end.y), col, 2.0)
		c.draw_colored_polygon(PoolVector2Array([Vector2(px - 6, 0), Vector2(px + 6, 0), Vector2(px, 9)]), col)
	_draw_minimap(c, sz)

func _nice_step(ms:float) -> float:
	var steps = [100.0, 250.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 30000.0, 60000.0, 120000.0]
	for s in steps:
		if s >= ms: return s
	return 300000.0

func _lane_y(y:float, lane:Rect2) -> float:
	var row = lane.size.y / 3.0
	return lane.position.y + (clamp(y, 0.0, 2.0) + 0.5) * row

# note ticks: rebuilt only when the notes, the view, the selection or a drag change (not while the
# playhead alone moves), and drawn as a few multilines instead of one rect per note
var _tk_key:String = ""
var _tk_groups:Array = []
var _sel_rev:int = 0
func _draw_ticks(c:Control, lane:Rect2):
	var row = lane.size.y / 3.0
	for r in range(1, 3):
		c.draw_line(Vector2(0, lane.position.y + row * r), Vector2(lane.end.x, lane.position.y + row * r), Color(1, 1, 1, 0.07), 1.0)
	var key = "%d|%f|%f|%d|%d|%d|%d" % [m.rev, view0, ppm, int(tl.rect_size.x), _sel_rev, drag_dt if tl_drag != null else 0, int(lane.size.y)]
	if key != _tk_key:
		_tk_key = key
		_tk_build(lane, row)
	for g in _tk_groups:
		if g[0].size() > 1: c.draw_multiline(g[0], g[1], g[2])

func _tk_build(lane:Rect2, row:float):
	var t0 = view0 - 10.0
	var t1 = view0 + _span() + 10.0
	var i0 = m.lower_bound(t0)
	var i1 = m.lower_bound(t1)
	var count = i1 - i0
	_tk_groups = []
	if count > tl.rect_size.x * 2.5:
		# zoomed far out: density per pixel column (one bar per column, not one object per note)
		var cols = int(tl.rect_size.x)
		var dens = PoolIntArray()
		dens.resize(cols + 1)
		for i in range(i0, i1):
			var x = int(_x_of(m.notes[i][2]))
			if x >= 0 and x <= cols: dens[x] += 1
		var mx = 1
		for v in dens: mx = max(mx, v)
		var pts = PoolVector2Array()
		for x in range(cols):
			if dens[x] > 0:
				pts.append(Vector2(x, lane.end.y))
				pts.append(Vector2(x, lane.end.y - lane.size.y * min(1.0, float(dens[x]) / mx)))
		_tk_groups.append([pts, Color(1, 1, 1, 0.5), 1.0])
		return
	var tw = clamp(ppm * 14.0, 2.0, 6.0)
	var hh = min(row * 0.62, 22.0) / 2.0
	var hot = Color(1, 0.35, 0.4)
	var buckets = [[], [], [], []] # x columns dim..bright, selected (plain arrays: a PoolVector2Array inside an Array is copied on every access)
	var moving = tl_drag != null and drag_dt != 0
	for i in range(i0, i1):
		var n = m.notes[i]
		var k = 3 if (!sel.empty() and sel.has(Model.key_of(n))) else (0 if n[0] < 0.67 else (1 if n[0] < 1.33 else 2))
		var t = n[2] + (drag_dt if (k == 3 and moving) else 0)
		var x = _x_of(t)
		var y = _lane_y(n[1], lane)
		buckets[k].append(Vector2(x, y - hh))
		buckets[k].append(Vector2(x, y + hh))
	_tk_groups.append([PoolVector2Array(buckets[0]), Color(0.55, 0.55, 0.55, 0.95), tw])
	_tk_groups.append([PoolVector2Array(buckets[1]), Color(0.78, 0.78, 0.78, 0.95), tw])
	_tk_groups.append([PoolVector2Array(buckets[2]), Color(1, 1, 1, 0.95), tw])
	_tk_groups.append([PoolVector2Array(buckets[3]), hot, tw + 1.0])

func _draw_wave(c:Control, lane:Rect2):
	var mid = lane.position.y + lane.size.y / 2.0
	if wave_state == "none" or wave_state == "failed":
		var s = "no waveform" if wave_state == "none" else "waveform unavailable for this audio"
		c.draw_string(_font(12), Vector2(10, lane.end.y - 8), s, Look.TEXT_3)
		return
	var key = "%f|%f|%d|%d" % [view0, ppm, wave_n, int(tl.rect_size.x)]
	if key != wave_key or wave_lines == null:
		wave_key = key
		var pts = PoolVector2Array()
		var half = lane.size.y * 0.46
		var w = int(tl.rect_size.x)
		var x = 0
		while x < w:
			var ta = view0 + x / ppm
			var tb = view0 + (x + 2) / ppm
			var ia = int(floor(ta / BIN))
			var ib = int(floor(tb / BIN))
			if ib >= 0 and ia < wave_n:
				var v = 0.0
				for k in range(max(ia, 0), min(ib, wave_n - 1) + 1):
					v = max(v, wave[k])
				if v > 0.003:
					pts.append(Vector2(x, mid - v * half))
					pts.append(Vector2(x, mid + v * half))
			x += 2
		wave_lines = pts
	if wave_lines.size() > 1: c.draw_multiline(wave_lines, Color(1, 1, 1, 0.16), 2.0)
	if wave_state == "loading":
		c.draw_string(_font(12), Vector2(10, lane.position.y + 14), "WAVEFORM %d%%" % int(100.0 * wave_n * BIN / max(audio_len, 1.0)), Look.TEXT_3)

var _mm_key:String = ""
var _mm_pts:PoolVector2Array = PoolVector2Array()
func _draw_minimap(c:Control, sz:Vector2):
	var r = Rect2(0, sz.y - MINIMAP, sz.x, MINIMAP)
	c.draw_rect(r, Look.SURFACE)
	var total = _total_ms()
	if total <= 0: return
	var k = sz.x / total
	var key = "%d|%d|%d" % [m.rev, int(sz.x), int(total)]
	if key != _mm_key: # density per column, rebuilt only when the notes change
		_mm_key = key
		_mm_pts = PoolVector2Array()
		if !m.notes.empty():
			var cols = int(sz.x)
			var dens = PoolIntArray()
			dens.resize(cols + 1)
			for n in m.notes:
				var x = int(n[2] * k)
				if x >= 0 and x <= cols: dens[x] += 1
			var mx = 1
			for v in dens: mx = max(mx, v)
			for x in range(cols):
				if dens[x] > 0:
					_mm_pts.append(Vector2(x, r.end.y))
					_mm_pts.append(Vector2(x, r.end.y - r.size.y * min(1.0, float(dens[x]) / mx)))
	if _mm_pts.size() > 1: c.draw_multiline(_mm_pts, Color(1, 1, 1, 0.4), 1.0)
	var vr = Rect2(view0 * k, r.position.y, _span() * k, r.size.y)
	c.draw_rect(vr, Color(1, 1, 1, 0.1))
	c.draw_rect(vr, Look.LINE_HI, false, 1.0)
	c.draw_line(Vector2(pos * k, r.position.y), Vector2(pos * k, r.end.y), Color(1, 1, 1, 0.9), 2.0)

func _tl_input(ev):
	_drop_focus(ev)
	if !m: return
	var lane = _lane_rect()
	if ev is InputEventMouseButton:
		if ev.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN] and ev.pressed:
			var dir = 1.0 if ev.button_index == BUTTON_WHEEL_UP else -1.0
			if ev.control:
				var tm = _t_of(ev.position.x)
				ppm = clamp(ppm * (1.25 if dir > 0 else 0.8), 0.004, 3.0)
				view0 = tm - ev.position.x / ppm
				follow = false
			else:
				view0 -= dir * _span() * (0.25 if !ev.shift else 0.75)
				follow = false
			_clamp_view()
			_tl_dirty = true
			return
		var in_mm = ev.position.y > tl.rect_size.y - MINIMAP
		if ev.button_index == BUTTON_LEFT:
			if ev.pressed:
				if in_mm:
					var t = ev.position.x / tl.rect_size.x * _total_ms()
					view0 = t - _span() / 2.0
					_clamp_view()
					follow = false
					_seek(t)
					return
				if ev.position.y < RULER:
					_seek(_snap_time(_t_of(ev.position.x)))
					tl_drag = {"mode": "seek"}
					return
				var hit = _tick_at(ev.position, lane)
				if hit != null:
					var k = Model.key_of(hit)
					if ev.shift or ev.control:
						if sel.has(k): sel.erase(k)
						else: sel[k] = hit
					elif !sel.has(k):
						sel = {k: hit}
					tl_drag = {"mode": "move", "grab": hit[2], "x0": ev.position.x}
					drag_dt = 0
					_sel_changed()
				else:
					tl_drag = {"mode": "box", "a": _t_of(ev.position.x), "x0": ev.position.x, "add": ev.shift or ev.control}
					box_sel = {"a": tl_drag.a, "b": tl_drag.a}
			else:
				if tl_drag != null:
					match tl_drag.mode:
						"box":
							if abs(ev.position.x - tl_drag.x0) < 4:
								if !tl_drag.add: sel = {}
								_seek(_snap_time(_t_of(ev.position.x)))
							else:
								_box_select(min(box_sel.a, box_sel.b), max(box_sel.a, box_sel.b), tl_drag.add)
							box_sel = null
						"move":
							if drag_dt != 0: _move_selection(Vector2.ZERO, drag_dt)
							drag_dt = 0
					tl_drag = null
					_sel_changed()
				tl.update()
		elif ev.button_index == BUTTON_RIGHT and ev.pressed:
			var h2 = _tick_at(ev.position, lane)
			if h2 != null:
				m.begin("delete note")
				m.run(["del", [h2]])
				m.end()
				sel.erase(Model.key_of(h2))
				_sel_changed()
		elif ev.button_index == BUTTON_MIDDLE:
			tl_drag = {"mode": "pan", "x0": ev.position.x, "v0": view0} if ev.pressed else null
	elif ev is InputEventMouseMotion and tl_drag != null:
		match tl_drag.mode:
			"seek": _seek(_snap_time(_t_of(ev.position.x)))
			"box":
				box_sel.b = _t_of(ev.position.x)
				tl.update()
			"move":
				var want = _t_of(ev.position.x) - _t_of(tl_drag.x0)
				drag_dt = _snap_time(tl_drag.grab + want) - int(tl_drag.grab) if _snapping() else int(round(want))
				tl.update()
			"pan":
				view0 = tl_drag.v0 - (ev.position.x - tl_drag.x0) / ppm
				follow = false
				_clamp_view()
				_tl_dirty = true

func _snap_time(t:float) -> int:
	if _snapping(): return m.snap_t(max(t, 0.0))
	return int(round(max(t, 0.0)))

func _tick_at(p:Vector2, lane:Rect2):
	var t = _t_of(p.x)
	var tol = 5.0 / ppm
	var i = m.lower_bound(t - tol)
	var best = null
	var bd = 1e9
	while i < m.notes.size() and m.notes[i][2] <= t + tol:
		var n = m.notes[i]
		var dy = abs(_lane_y(n[1], lane) - p.y)
		var d = abs(n[2] - t) * ppm + dy * 0.25
		if dy < lane.size.y / 3.0 and d < bd:
			bd = d
			best = n
		i += 1
	return best

func _box_select(a:float, b:float, add:bool):
	if !add: sel = {}
	var i = m.lower_bound(a)
	while i < m.notes.size() and m.notes[i][2] <= b:
		sel[Model.key_of(m.notes[i])] = m.notes[i]
		i += 1

# ------------------------------------------------------------------ editing operations (all through the model)
func _sel_notes() -> Array:
	var out = []
	for k in sel:
		if m.keys.has(k): out.append(sel[k])
	out.sort_custom(m, "_cmp")
	return out

func _sel_changed():
	_sel_rev += 1
	var ns = _sel_notes()
	var keep = {}
	for n in ns: keep[Model.key_of(n)] = n
	sel = keep
	_refresh_insp()
	_field_dirty = true
	field.update()
	tl.update()

func _move_selection(dg:Vector2, dms:int, name:String = "move notes"):
	var ns = _sel_notes()
	if ns.empty(): return
	var pairs = []
	for n in ns:
		var nn = [n[0] + dg.x, n[1] + dg.y, max(int(n[2]) + dms, 0)]
		nn[0] = clamp(nn[0], Model.GRID_MIN, Model.GRID_MAX)
		nn[1] = clamp(nn[1], Model.GRID_MIN, Model.GRID_MAX)
		pairs.append([n, nn])
	m.begin(name)
	# apply in an order that never lands on a note that has not moved yet
	if dms > 0 or (dms == 0 and dg.x + dg.y > 0): pairs.invert()
	for pr in pairs: m.run(["mov", [pr]])
	m.end()
	var ns2 = {}
	for pr in pairs:
		if m.has_note(pr[1]): ns2[Model.key_of(pr[1])] = pr[1]
		elif m.has_note(pr[0]): ns2[Model.key_of(pr[0])] = pr[0]
	sel = ns2
	_sel_changed()

func _delete_sel():
	var ns = _sel_notes()
	if ns.empty(): return
	m.begin("delete %d note(s)" % ns.size())
	m.run(["del", ns])
	m.end()
	sel = {}
	_sel_changed()

func _op_mirror(horizontal:bool):
	_transform_sel("mirror " + ("X" if horizontal else "Y"), horizontal, false)

func _op_rotate():
	_transform_sel("rotate 90", false, true)

func _transform_sel(name:String, mir_x:bool, rot:bool):
	var ns = _sel_notes()
	if ns.empty(): return
	var news = []
	for n in ns:
		var x = n[0]
		var y = n[1]
		if rot:
			var t = x
			x = 2.0 - y
			y = t
		elif mir_x: x = 2.0 - x
		else: y = 2.0 - y
		news.append([x, y, n[2]])
	m.begin(name)
	m.run(["del", ns])
	m.run(["add", news])
	m.end()
	sel = {}
	for n in news: sel[Model.key_of(n)] = n
	_sel_changed()

func _op_nudge(ms:int):
	_move_selection(Vector2.ZERO, ms, "nudge %d ms" % ms)

func _op_step(dir:int):
	if sel.empty(): return
	var ns = _sel_notes()
	var first = ns[0][2]
	var target = int(round(m.grid_next(first, dir)))
	if target == first: target = first + dir
	_move_selection(Vector2.ZERO, int(target - first), "shift %d step" % dir)

func _snap_selection():
	var ns = _sel_notes()
	if ns.empty():
		msg("select notes first")
		return
	var pairs = []
	for n in ns:
		var s = m.snap_t(n[2])
		if s != int(n[2]): pairs.append([n, [n[0], n[1], max(s, 0)]])
	if pairs.empty():
		msg("already on the grid")
		return
	m.begin("snap to grid")
	for pr in pairs: m.run(["mov", [pr]])
	m.end()
	sel = {}
	for pr in pairs:
		if m.has_note(pr[1]): sel[Model.key_of(pr[1])] = pr[1]
	_sel_changed()

func _op_repeat(times:int):
	var ns = _sel_notes()
	if ns.empty(): return
	var span = ns[ns.size() - 1][2] - ns[0][2]
	var step = m.step_at(ns[0][2])
	var len_ms = max(ceil((span + 1) / step) * step, step)
	var added = []
	m.begin("repeat x%d" % times)
	for k in range(1, times):
		var group = []
		for n in ns: group.append([n[0], n[1], int(round(n[2] + k * len_ms))])
		m.run(["add", group])
		added += group
	m.end()
	sel = {}
	for n in ns: sel[Model.key_of(n)] = n
	for n in added: if m.has_note(n): sel[Model.key_of(n)] = n
	_sel_changed()

func _copy():
	var ns = _sel_notes()
	if ns.empty(): return
	clip = []
	var t0 = ns[0][2]
	for n in ns: clip.append([n[0], n[1], n[2] - t0])
	msg("copied %d note(s)" % clip.size())

func _paste():
	if clip.empty(): return
	var base = _place_ms()
	var group = []
	for n in clip: group.append([n[0], n[1], base + int(n[2])])
	m.begin("paste %d note(s)" % group.size())
	m.run(["add", group])
	m.end()
	sel = {}
	for n in group: if m.has_note(n): sel[Model.key_of(n)] = n
	_sel_changed()

func _cut():
	_copy()
	_delete_sel()

func _duplicate():
	var ns = _sel_notes()
	if ns.empty(): return
	var step = m.step_at(ns[0][2])
	var span = ns[ns.size() - 1][2] - ns[0][2]
	var dm = max(ceil((span + 1) / step) * step, step)
	var group = []
	for n in ns: group.append([n[0], n[1], int(round(n[2] + dm))])
	m.begin("duplicate")
	m.run(["add", group])
	m.end()
	sel = {}
	for n in group: if m.has_note(n): sel[Model.key_of(n)] = n
	_sel_changed()
	_seek(group[0][2])

func _select_all():
	sel = {}
	for n in m.notes: sel[Model.key_of(n)] = n
	_sel_changed()

func _undo():
	if !m: return
	var n = m.undo()
	if n != "":
		msg("undo: " + n)
		_select_touched()
	_sel_changed()

func _redo():
	if !m: return
	var n = m.redo()
	if n != "":
		msg("redo: " + n)
		_select_touched()
	_sel_changed()

# undo / redo select what the step put back (nothing put back: the selection stays)
func _select_touched():
	if m.touched.empty(): return
	sel = {}
	for x in m.touched:
		var k = Model.key_of(x)
		if m.keys.has(k): sel[k] = x

func _jump_note(dir:int):
	if m.notes.empty(): return
	var i = m.lower_bound(pos + (1.0 if dir > 0 else -1.0))
	if dir > 0:
		while i < m.notes.size() and m.notes[i][2] <= pos + 0.5: i += 1
		if i >= m.notes.size(): return
	else:
		i -= 1
		while i >= 0 and m.notes[i][2] >= pos - 0.5: i -= 1
		if i < 0: return
	_seek(m.notes[i][2])
	sel = {Model.key_of(m.notes[i]): m.notes[i]}
	_sel_changed()

# inspector
func _refresh_insp():
	_lock_ui = true
	var ns = _sel_notes()
	for k in ["t", "x", "y"]: insp[k].editable = ns.size() == 1
	if ns.size() == 1:
		insp.t.value = ns[0][2]
		insp.x.value = ns[0][0]
		insp.y.value = ns[0][1]
		insp.info.text = "1 note at %s" % Model.fmt_time(int(ns[0][2]))
	else:
		insp.info.text = "nothing selected" if ns.empty() else "%d notes  %s - %s" % [ns.size(), Model.fmt_time(int(ns[0][2])), Model.fmt_time(int(ns[ns.size() - 1][2]))]
	_lock_ui = false

func _insp_changed(v:float, which:String):
	if _lock_ui: return
	var ns = _sel_notes()
	if ns.size() != 1: return
	var o = ns[0]
	var nn = [o[0], o[1], o[2]]
	match which:
		"t": nn[2] = int(v)
		"x": nn[0] = v
		"y": nn[1] = v
	if m.has_note(nn):
		msg("a note is already there", true)
		_refresh_insp()
		return
	m.begin("edit note")
	m.run(["mov", [[o, nn]]])
	m.end()
	sel = {Model.key_of(nn): nn}
	_sel_changed()

func _refresh_note_list():
	if !m: return
	note_list.clear()
	var a = 0.0
	var b = 1e12
	var f = note_list_filter.text.strip_edges()
	if f != "":
		var parts = f.split("-")
		if parts.size() == 2:
			var ta = Model.parse_time(parts[0])
			var tb = Model.parse_time(parts[1])
			if ta >= 0 and tb >= 0:
				a = ta
				b = tb
	var i = m.lower_bound(a)
	var shown = 0
	while i < m.notes.size() and m.notes[i][2] <= b and shown < 400:
		var n = m.notes[i]
		note_list.add_item("%s   x%.2f y%.2f" % [Model.fmt_time(int(n[2])), n[0], n[1]])
		note_list.set_item_metadata(shown, n)
		shown += 1
		i += 1

func _note_filter_changed(_t):
	_refresh_note_list()

func _note_list_pick(i:int):
	var n = note_list.get_item_metadata(i)
	if n == null: return
	_seek(n[2])
	sel = {Model.key_of(n): n}
	_sel_changed()
	_center_view()

# ------------------------------------------------------------------ timing / tools
func _timing_changed(_v):
	if _lock_ui or !m: return
	m.bpm = clamp(sp_bpm.value, 20.0, 400.0)
	m.offset = int(sp_off.value)
	m.dirty = true # (editor aids are part of the session)
	m.rev += 1
	wave_lines = null

func _div_changed(i:int):
	if !m or _lock_ui: return
	m.div = ob_div.get_item_id(i)
	m.rev += 1

func _set_div(d:int):
	m.div = d
	_sync_timing_ui()
	m.rev += 1

func _set_time_snap(on:bool):
	time_snap = on

func _set_pos_snap(on:bool, which:String):
	if on: pos_snap = which

func _set_advance(on:bool):
	advance = on

func _set_hit_sound(on:bool):
	hit_sound = on

func _set_metronome(on:bool):
	metronome = on

func _tap():
	var now = OS.get_ticks_msec()
	if !tap_times.empty() and now - tap_times[tap_times.size() - 1] > 2500: tap_times = []
	tap_times.append(now)
	if tap_times.size() >= 3:
		var total = tap_times[tap_times.size() - 1] - tap_times[0]
		var bpm = 60000.0 * (tap_times.size() - 1) / total
		sp_bpm.value = stepify(bpm, 0.1)
		msg("tapped %.1f BPM from %d taps" % [bpm, tap_times.size()])
	else:
		msg("keep tapping (%d)" % tap_times.size())

func _offset_here():
	sp_off.value = int(round(pos))
	msg("offset set to the playhead")

func _bookmark_add():
	var t = int(round(pos))
	if t in m.bookmarks: return
	m.bookmarks.append(t)
	m.bookmarks.sort()
	m.dirty = true
	m.rev += 1
	_refresh_bookmarks()

func _bookmark_remove():
	var sel_i = book_list.get_selected_items()
	if sel_i.empty():
		# nearest to the playhead
		var best = -1
		var bd = 1e12
		for i in m.bookmarks.size():
			if abs(m.bookmarks[i] - pos) < bd:
				bd = abs(m.bookmarks[i] - pos)
				best = i
		if best >= 0: m.bookmarks.remove(best)
	else:
		m.bookmarks.remove(sel_i[0])
	m.dirty = true
	m.rev += 1
	_refresh_bookmarks()

func _bookmark_go(i:int):
	_seek(m.bookmarks[i])
	_center_view()

func _refresh_bookmarks():
	book_list.clear()
	for b in m.bookmarks: book_list.add_item(Model.fmt_time(int(b)))
	_refresh_points()
	tl.update()

# timing points: a new section (its own BPM, grid and measures) from the snapped playhead on
func _point_add():
	if !m: return
	var t = m.snap_t(pos) if time_snap else int(round(pos))
	if !m.add_point(t, m.bpm_at(t)):
		msg("a timing point goes after the offset (first beat) and not on another one", true)
		return
	m.dirty = true
	_refresh_points()
	for i in m.points.size():
		if int(m.points[i][0]) == t:
			pt_list.select(i)
			_point_pick(i)
	msg("timing point at %s: set its BPM below" % Model.fmt_time(t))

func _point_remove():
	var si = pt_list.get_selected_items()
	if !m or m.points.empty(): return
	var k = si[0] if !si.empty() else -1
	if k < 0: # (the one at or before the playhead)
		for i in m.points.size():
			if m.points[i][0] <= pos + 0.5: k = i
	if k < 0: return
	m.points.remove(k)
	m.rev += 1
	m.dirty = true
	_refresh_points()
	tl.update()

func _point_pick(i:int):
	if !m or i < 0 or i >= m.points.size(): return
	_lock_ui = true
	sp_pt.editable = true
	sp_pt.value = m.points[i][1]
	_lock_ui = false
	_seek(m.points[i][0])
	_center_view()

func _point_bpm(v:float):
	var si = pt_list.get_selected_items()
	if _lock_ui or !m or si.empty() or si[0] >= m.points.size(): return
	m.points[si[0]][1] = clamp(v, 20.0, 400.0)
	m.rev += 1
	m.dirty = true
	pt_list.set_item_text(si[0], _point_txt(m.points[si[0]]))
	tl.update()

func _refresh_points():
	if !pt_list: return
	pt_list.clear()
	for pt in m.points: pt_list.add_item(_point_txt(pt))
	sp_pt.editable = false

func _point_txt(pt:Array) -> String:
	return "%s   %s BPM" % [Model.fmt_time(int(pt[0])), _num_txt(pt[1])]

static func _num_txt(v:float) -> String:
	var t = "%.3f" % v
	while t.ends_with("0"): t = t.substr(0, t.length() - 1)
	return t.trim_suffix(".")

func _sync_timing_ui():
	_lock_ui = true
	sp_bpm.value = m.bpm
	sp_off.value = m.offset
	for i in ob_div.get_item_count():
		if ob_div.get_item_id(i) == m.div: ob_div.select(i)
	_lock_ui = false

# ------------------------------------------------------------------ playback
func _seek(ms:float):
	pos = clamp(ms, 0.0, max(audio_len, 1.0) if audio_len > 0 else 36000000.0)
	if playing and stream: ap.seek(pos / 1000.0)
	_prev_pos = pos
	tl.update()
	field.update()

func _seek_start():
	_seek(0.0)
	_center_view()

func _center_view():
	view0 = pos - _span() * 0.35
	_clamp_view()
	tl.update()

func _toggle_play():
	if !m or !stream:
		msg("no audio loaded", true)
		return
	if playing:
		ap.stop()
		playing = false
	else:
		if pos >= audio_len - 20.0: pos = 0.0
		ap.stream = stream
		_apply_speed()
		ap.play(pos / 1000.0)
		playing = true
		_prev_pos = pos
	tl.update()

func _speed_changed(i:int):
	speed = [0.5, 0.75, 1.0][i]
	_apply_speed()

func _set_loop(on:bool):
	loop_on = on
	if on and !(loop_a >= 0 and loop_b > loop_a):
		var ns = _sel_notes()
		if ns.size() >= 2:
			loop_a = ns[0][2]
			loop_b = ns[ns.size() - 1][2] + 200
		else:
			loop_a = pos
			loop_b = pos + 4000.0
	tl.update()

func _loop_mark(is_a:bool):
	if is_a: loop_a = pos
	else: loop_b = pos
	if loop_a >= 0 and loop_b > loop_a: loop_on = true
	tl.update()

func _zoom_btn(f:float):
	var tm = pos if (pos > view0 and pos < view0 + _span()) else view0 + _span() / 2.0
	var xr = (tm - view0) * ppm
	ppm = clamp(ppm * f, 0.004, 3.0)
	view0 = tm - xr / ppm
	_clamp_view()
	tl.update()

func _zoom_fit():
	ppm = clamp(tl.rect_size.x / max(_total_ms(), 1000.0), 0.004, 3.0)
	view0 = 0.0
	tl.update()

func _process(delta):
	if !m:
		return
	if playing:
		if !ap.playing:
			playing = false
			if loop_on and loop_b > loop_a: _seek(loop_a)
		else:
			# playhead = the audio clock, smoothed: the wall clock moves it every frame, the audio position
			# (capped time since the last mix: a stalled mixer must not shoot the playhead ahead) pulls it
			# back by 15 % a frame; a real jump (> 0.4 s) snaps
			var raw = ap.get_playback_position() + clamp(AudioServer.get_time_since_last_mix(), 0.0, 0.05) - AudioServer.get_output_latency()
			var est = pos + delta * 1000.0 * speed
			var d = raw * 1000.0 - est
			pos = raw * 1000.0 if abs(d) > 400.0 else max(pos, est + d * 0.15) # (never steps back: a lagging clock just holds the playhead)
		if loop_on and loop_b > loop_a and pos >= loop_b:
			_seek(loop_a)
			ap.play(pos / 1000.0)
			playing = true
		_play_sounds(_prev_pos, pos)
		_prev_pos = pos
		if follow:
			var target = pos - _span() * 0.3
			if pos < view0 or pos > view0 + _span() * 0.9: view0 = target
			_clamp_view()
		tl.update()
		field.update()
	elif _last_rev != m.rev:
		pass
	if _last_rev != m.rev:
		_last_rev = m.rev
		_refresh_state()
		tl.update()
		field.update()
	if wave_state == "loading": _wave_step()
	_star_tick(delta)
	_hush_t += delta
	if _hush_t > 0.5:
		_hush_t = 0.0
		_hush() # (a preview that restarts on its own is paused again)
	_auto_t += delta
	if _auto_t > 15.0:
		_auto_t = 0.0
		if m.dirty and _auto_rev != m.rev: _autosave()
	time_lbl.text = "%s / %s     beat %.2f%s     %d notes" % [Model.fmt_time(int(pos)), Model.fmt_time(int(audio_len)), m.beat_at(pos), (" @ %s BPM" % _num_txt(m.bpm_at(pos))) if !m.points.empty() else "", m.notes.size()]

func _play_sounds(a:float, b:float):
	if b <= a: return
	if hit_sound:
		var i = m.lower_bound(a + 0.001)
		var fired = false
		while i < m.notes.size() and m.notes[i][2] <= b:
			if !fired:
				var p = hit_players[hit_i]
				hit_i = (hit_i + 1) % hit_players.size()
				p.pitch_scale = 1.0
				p.play()
				fired = true
			i += 1
	if metronome:
		var gl = m.grid_lines(a + 0.001, b, false, 1, 1)
		if !gl.empty():
			click_player.pitch_scale = 1.5 if gl[0][1] == 0 else 1.0
			click_player.play()

func _refresh_state():
	var s = "UNSAVED" if m.dirty else "SAVED"
	if _saving: s = "SAVING..."
	state_lbl.text = ("● " if m.dirty else "○ ") + s
	state_lbl.add_color_override("font_color", Look.TEXT if m.dirty else Look.TEXT_3)
	hist_list.clear()
	for h in m.history(): hist_list.add_item("%s  (%d)" % [h[0], h[1]])

# ------------------------------------------------------------------ waveform (muted capture)
func _wave_begin(force:bool = false):
	_wave_cleanup()
	wave = PoolRealArray()
	wave_n = 0
	wave_lines = null
	env_lo = PoolRealArray()
	env_hi = PoolRealArray()
	env_all = PoolRealArray()
	if !stream or audio_len <= 0:
		wave_state = "none"
		return
	var cache = _wave_cache_path()
	var f = File.new()
	if !force and cache != "" and f.file_exists(cache) and f.open(cache, File.READ) == OK:
		var n = f.get_32()
		var len_ms = f.get_32()
		if n > 0 and abs(len_ms - int(audio_len)) < 50 and n == int(ceil(audio_len / BIN)) + 2:
			var buf = f.get_buffer(n)
			f.close()
			wave = PoolRealArray()
			wave.resize(n)
			for i in min(n, buf.size()): wave[i] = buf[i] / 255.0
			wave_n = n
			wave_state = "ready"
			_env_load()
			return
		f.close()
	var cs = _load_stream(m.meta.audio) # (its own stream object: not shared with the editing playback)
	if cs is AudioStreamOGGVorbis or cs is AudioStreamMP3: cs.loop = false
	wave_cap = Cap.new()
	add_child(wave_cap)
	wave_cap.start(cs if cs != Globals.error_sound and cs != null else stream, audio_len, BIN)
	wave = wave_cap.wave
	wave_state = "loading" if wave_cap.state == "loading" else "failed"
	wave_frame = 0

func _wave_step():
	if !is_instance_valid(wave_cap): return
	var done = wave_cap.state != "loading"
	wave_frame += 1
	if wave_frame % 8 == 0 or done:
		wave = wave_cap.wave # (a copy every few frames is enough for the drawing)
		wave_n = wave_cap.wave_n
		wave_lines = null
		tl.update()
	if !done: return
	if wave_cap.state == "ready":
		env_lo = wave_cap.lo
		env_hi = wave_cap.hi
		env_all = wave_cap.al
		wave_n = wave.size()
		wave_state = "ready"
		_wave_save()
	else:
		wave_state = "failed"
	_wave_cleanup()
	if auto_pending: call_deferred("_auto_run")

var wave_frame:int = 0
func _wave_cleanup():
	if is_instance_valid(wave_cap):
		wave_cap.stop()
		wave_cap.queue_free()
	wave_cap = null # (the two capture buses stay for the session: removing them under a player crashed the game)

func _wave_cache_path() -> String:
	if !m or m.meta.audio == "": return ""
	return m.meta.audio.get_base_dir() + "/wave.bin"

# analysis envelopes cache (env2.bin next to wave.bin: "RRE2", bin ms x 100, count, then a byte per
# bin for each of the low / high / whole bands; env.bin of earlier builds held per-frame values)
func _env_path() -> String:
	var p = _wave_cache_path()
	return p.get_base_dir() + "/env2.bin" if p != "" else ""

func _env_load():
	var f = File.new()
	var p = _env_path()
	if p == "" or !f.file_exists(p) or f.open(p, File.READ) != OK: return
	var n = 0
	if f.get_buffer(4).get_string_from_ascii() == "RRE2" and f.get_32() == int(Cap.ABIN * 100):
		n = f.get_32()
	if n > 0 and abs(n - (int(ceil(audio_len / Cap.ABIN)) + 2)) <= 2:
		var arrs = []
		for k in 3:
			var b = f.get_buffer(n)
			if b.size() != n: break
			var a = PoolRealArray()
			a.resize(n)
			for i in n: a[i] = b[i] / 255.0
			arrs.append(a)
		if arrs.size() == 3:
			env_lo = arrs[0]
			env_hi = arrs[1]
			env_all = arrs[2]
	f.close()

func _env_save():
	var p = _env_path()
	if p == "" or env_lo.size() == 0: return
	var f = File.new()
	if f.open(p, File.WRITE) != OK: return
	f.store_buffer("RRE2".to_ascii())
	f.store_32(int(Cap.ABIN * 100))
	f.store_32(env_lo.size())
	for arr in [env_lo, env_hi, env_all]:
		var buf = PoolByteArray()
		buf.resize(arr.size())
		for i in arr.size(): buf[i] = int(clamp(arr[i] * 255.0, 0.0, 255.0))
		f.store_buffer(buf)
	f.close()

func _wave_save():
	var p = _wave_cache_path()
	if p == "" or wave_state != "ready": return
	_env_save()
	var f = File.new()
	if f.open(p + ".tmp", File.WRITE) != OK: return
	f.store_32(wave.size())
	f.store_32(int(audio_len))
	var buf = PoolByteArray() # one byte per bin (calling encode_float / decode_float on a PoolByteArray crashes this engine build)
	buf.resize(wave.size())
	for i in wave.size(): buf[i] = int(clamp(wave[i] * 255.0, 0.0, 255.0))
	f.store_buffer(buf)
	f.close()
	var d = Directory.new()
	if d.file_exists(p): d.remove(p)
	d.rename(p + ".tmp", p)

# ------------------------------------------------------------------ session / maps
func _sanitize_id(s:String) -> String:
	var out = ""
	for c in s.to_lower():
		if c in "0123456789abcdefghijklmnopqrstuvwxyz_-": out += c
		elif c in " .": out += "_"
	while "__" in out: out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_")

func _unique_id(base:String) -> String:
	if base == "": base = "new_map"
	var id = base
	var n = 2
	while Rhythia.registry_song.idx_id.has(id) or File.new().file_exists("user://maps/%s.sspm" % id):
		id = "%s_%d" % [base, n]
		n += 1
	return id

func _work_dir(id:String) -> String:
	var d = "%s/%s" % [DIR, id]
	var dd = Directory.new()
	if !dd.dir_exists(d): dd.make_dir_recursive(d)
	return d

func _audio_ext(buf:PoolByteArray) -> String:
	if buf.size() > 4:
		if buf[0] == 79 and buf[1] == 103 and buf[2] == 103 and buf[3] == 83: return "ogg"
		if buf[0] == 82 and buf[1] == 73 and buf[2] == 70 and buf[3] == 70: return "wav"
	return "mp3"

func _adopt(model, at:float = 0.0, from_song = null):
	m = model
	if from_song != null: src_song = from_song
	sel = {}
	ack_markers = false
	start_panel.visible = false
	_load_audio()
	_lock_ui = true
	f_id.text = m.meta.id
	f_name.text = m.meta.name
	f_creator.text = m.meta.creator
	f_diff.select(int(m.meta.difficulty) + 1)
	f_id.editable = !saved_once
	_lock_ui = false
	_sync_timing_ui()
	_refresh_bookmarks()
	_refresh_insp()
	pos = at
	_prev_pos = at
	view0 = -200.0
	ppm = 0.15
	_center_view()
	_last_rev = -1
	_auto_rev = m.rev
	msg("")

# the game's AudioLoader.load_file maps user:// through Globals.p, which on Android points at a
# different folder than the engine's user:// (where the editor keeps its files): read the bytes here
func _load_stream(path:String):
	var f = File.new()
	if f.open(path, File.READ) != OK: return null
	var b = f.get_buffer(f.get_len())
	f.close()
	if b.size() == 0: return null
	return Globals.audioLoader.load_buffer(b, false)

func _load_audio():
	stream = null
	audio_ok = false
	audio_len = 0.0
	if playing: ap.stop()
	playing = false
	var path = m.meta.audio
	if path != "" and File.new().file_exists(path):
		var s = _load_stream(path)
		if s != Globals.error_sound and s != null:
			stream = s
			if s is AudioStreamOGGVorbis or s is AudioStreamMP3: s.loop = false
			audio_len = s.get_length() * 1000.0 if s.has_method("get_length") else 0.0
			audio_ok = audio_len > 0.0
	audio_lbl.text = "%s  (%s)" % [path.get_file(), Model.fmt_time(int(audio_len))] if audio_ok else ("MISSING OR UNREADABLE: " + path if path != "" else "no audio chosen")
	_wave_begin()
	_tl_dirty = true

func _session_dict() -> Dictionary:
	var d = m.to_dict()
	d["saved_once"] = saved_once
	d["pos"] = pos
	d["src_id"] = src_song.id if src_song and "id" in src_song else ""
	d["time"] = OS.get_unix_time()
	return d

func _autosave():
	if !m: return
	_auto_rev = m.rev
	_write_json(SESSION, _session_dict())
	_sidecar_write()

# per-map editor settings (grid / bookmarks are not part of the .sspm): DIR/<id>/meta.json
func _sidecar_write():
	if !m or str(m.meta.id) == "": return
	_write_json("%s/meta.json" % _work_dir(str(m.meta.id)), {"bpm": m.bpm, "offset": m.offset, "div": m.div, "bookmarks": m.bookmarks, "points": m.points})

func _sidecar_read(model):
	var f = File.new()
	var path = "%s/%s/meta.json" % [DIR, model.meta.id]
	if !f.file_exists(path) or f.open(path, File.READ) != OK: return
	var r = JSON.parse(f.get_as_text())
	f.close()
	if r.error != OK or typeof(r.result) != TYPE_DICTIONARY: return
	var d = r.result
	model.bpm = clamp(float(d.get("bpm", 120.0)), 20.0, 400.0)
	model.offset = int(d.get("offset", 0))
	model.div = int(clamp(int(d.get("div", 4)), 1, 16))
	if typeof(d.get("bookmarks")) == TYPE_ARRAY: model.bookmarks = d.bookmarks
	model.set_points(d.get("points", []))

func _write_json(path:String, d:Dictionary) -> bool:
	var f = File.new()
	if f.open(path + ".tmp", File.WRITE) != OK: return false
	f.store_string(to_json(d))
	f.close()
	var dd = Directory.new()
	if dd.file_exists(path): dd.remove(path)
	return dd.rename(path + ".tmp", path) == OK

func _read_session():
	var f = File.new()
	if !f.file_exists(SESSION) or f.open(SESSION, File.READ) != OK: return null
	var r = JSON.parse(f.get_as_text())
	f.close()
	if r.error != OK or typeof(r.result) != TYPE_DICTIONARY: return null
	return r.result

# ------------------------------------------------------------------ start screen (new / open / recover)
func _build_start():
	start_panel = Control.new()
	start_panel.anchor_right = 1
	start_panel.anchor_bottom = 1
	start_panel.margin_top = 52
	root.add_child(start_panel)
	var bg = ColorRect.new()
	bg.color = Look.BG
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	start_panel.add_child(bg)
	var card = Panel.new()
	card.add_stylebox_override("panel", _panel_style(Look.SURFACE))
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.margin_left = -460
	card.margin_right = 460
	card.margin_top = -300
	card.margin_bottom = 300
	start_panel.add_child(card)
	var v = VBoxContainer.new()
	v.anchor_right = 1
	v.anchor_bottom = 1
	v.margin_left = 24
	v.margin_right = -24
	v.margin_top = 20
	v.margin_bottom = -20
	v.add_constant_override("separation", 10)
	card.add_child(v)
	v.add_child(_lbl("// MAP EDITOR", 26, Look.TEXT))
	var intro = _lbl("Edit real Rhythia maps: .sspm files in your library. Saving writes a playable .sspm; TEST runs the actual game.", 14, Look.TEXT_2)
	intro.autowrap = true
	intro.rect_min_size.x = 840
	v.add_child(intro)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	row.add_child(_btn("NEW MAP FROM AUDIO...", "_pick_audio", [true], false, 230))
	var rec = _btn("RECOVER LAST SESSION", "_recover", [], false, 230)
	rec.name = "Recover"
	row.add_child(rec)
	v.add_child(row)
	v.add_child(_lbl("OPEN FROM LIBRARY", 12, Look.TEXT_3))
	lib_filter = LineEdit.new()
	lib_filter.placeholder_text = "search title / mapper / id"
	lib_filter.connect("text_changed", self, "_lib_filter_changed")
	_style_input(lib_filter)
	v.add_child(lib_filter)
	lib_list = ItemList.new()
	lib_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lib_list.connect("item_activated", self, "_lib_open")
	_style_input(lib_list)
	v.add_child(lib_list)
	v.add_child(_btn("OPEN SELECTED", "_lib_open_sel", [], false, 160))
	var note = _lbl("Maps that are built in, online or text files open as a copy (new id *_edit): originals are never overwritten.", 12, Look.TEXT_3)
	note.autowrap = true
	note.rect_min_size.x = 840
	v.add_child(note)
	call_deferred("_lib_fill")

func _lib_fill():
	lib_songs = []
	var q = lib_filter.text.to_lower()
	lib_list.clear()
	for s in Rhythia.registry_song.get_items():
		if !(s is Object) or !("name" in s): continue
		var hay = ("%s %s %s" % [s.name, s.creator, s.id]).to_lower()
		if q != "" and !(q in hay): continue
		lib_songs.append(s)
		lib_list.add_item("%s   -   %s   [%s]" % [s.name, s.creator, s.id])
		if lib_songs.size() >= 300: break
	var has = _read_session() != null
	var rb = start_panel.find_node("Recover", true, false)
	if rb:
		rb.disabled = !has
		if has:
			var sd = _read_session()
			rb.text = "RECOVER: %s (%d notes)" % [str(sd.get("meta", {}).get("name", "?")).left(16), (sd.get("notes", []) as Array).size()]

func _lib_filter_changed(_t):
	_lib_fill()

func _lib_open_sel():
	var s = lib_list.get_selected_items()
	if !s.empty(): _lib_open(s[0])

func _lib_open(i:int):
	if i < 0 or i >= lib_songs.size(): return
	_guard_discard("_do_open_song", [lib_songs[i]])

func open_song(song):
	# called from outside (map page button)
	if m == null: _do_open_song(song)
	else: _guard_discard("_do_open_song", [song])

func _do_open_song(s):
	var d = _open_song_model(s)
	if d is String:
		msg(d, true)
		return
	_adopt(d[0], 0.0, s)
	saved_once = d[1]
	f_id.editable = !saved_once
	msg("opened " + str(s.name))

# -> [Model, saved_once] or an error string
func _open_song_model(s):
	var notes = s.read_notes()
	if notes == null or (notes.size() == 0 and s.is_broken and s.warning != ""):
		return "could not read the notes: " + str(s.warning)
	var nm = Model.new()
	nm.set_notes(notes)
	var in_place = s.songType == Globals.MAP_SSPM2 and str(s.filePath).begins_with("user://maps/") and !s.is_builtin and !s.is_online
	var id = s.id if in_place else _unique_id(_sanitize_id(s.id) + "_edit")
	nm.meta.id = id
	nm.meta.name = s.name
	nm.meta.creator = s.creator
	nm.meta.difficulty = s.difficulty
	if s.songType == Globals.MAP_SSPM2:
		s.read_markers()
		nm.extra_markers = max(s.marker_types.size() - 1, 0) if s.marker_types.size() > 1 else 0
	var buf = s.get_music_buffer()
	if buf == null or buf.size() == 0: return "the map has no readable audio"
	var dir = _work_dir(id)
	var path = "%s/audio.%s" % [dir, _audio_ext(buf)]
	var f = File.new()
	if f.open(path, File.WRITE) != OK: return "could not write the working audio copy"
	f.store_buffer(buf)
	f.close()
	nm.meta.audio = path
	_sidecar_read(nm)
	return [nm, in_place]

func _recover():
	var sd = _read_session()
	if sd == null:
		msg("no session to recover", true)
		return
	var nm = Model.from_dict(sd)
	saved_once = bool(sd.get("saved_once", false))
	if sd.get("src_id", "") != "":
		var s = Rhythia.registry_song.get_item(sd.src_id)
		if s is Object: src_song = s
	_adopt(nm, float(sd.get("pos", 0.0)))
	f_id.editable = !saved_once
	msg("recovered the autosaved session")

func _pick_audio(new_map:bool):
	_fs_raise("_audio_new" if new_map else "_audio_change")
	Globals.file_sel.open_file(self, "_fs_done", PoolStringArray(["*.mp3, *.ogg, *.wav ; Audio files"]), false, OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS))

# the game's file picker (Globals.file_sel) sits on the root under the editor's layer: on phones
# (Godot's own dialog, no system one) it opened invisible behind the editor while still taking the
# input. While it's open the editor layer is hidden, and shown again when the picker answers (it
# always does: a cancel answers with nothing). Moving the picker onto a higher layer instead
# crashed phones (its nodes re-entered the tree without a viewport).
var fs_then:String = ""

func _fs_raise(then:String):
	fs_then = then
	if is_instance_valid(Globals.file_sel) and !Globals.file_sel.use_native: visible = false

func _fs_done(v):
	visible = true
	if fs_then != "": call(fs_then, v)

func _audio_new(files:PoolStringArray):
	if files.size() == 0: return
	_guard_discard("_new_from_audio", [files[0]])

func _new_from_audio(file:String):
	var base = _sanitize_id(file.get_file().get_basename())
	var id = _unique_id(base)
	var path = _copy_audio(file, id)
	if path == "":
		msg("could not copy the audio file", true)
		return
	var nm = Model.new()
	nm.meta.id = id
	nm.meta.name = file.get_file().get_basename()
	nm.meta.creator = ""
	nm.meta.audio = path
	nm.dirty = true
	src_song = null
	saved_once = false
	_adopt(nm)
	msg("new map from " + file.get_file())

func _audio_change(files:PoolStringArray):
	if files.size() == 0 or !m: return
	var path = _copy_audio(files[0], m.meta.id)
	if path == "":
		msg("could not copy the audio file", true)
		return
	m.meta.audio = path
	m.dirty = true
	m.rev += 1
	_load_audio()
	msg("audio changed to " + files[0].get_file())

func _copy_audio(src:String, id:String) -> String:
	var f = File.new()
	if f.open(src, File.READ) != OK: return ""
	var buf = f.get_buffer(f.get_len())
	f.close()
	if buf.size() < 100: return ""
	var s = Globals.audioLoader.load_buffer(buf)
	if s == Globals.error_sound or s == null: return ""
	var path = "%s/audio.%s" % [_work_dir(id), _audio_ext(buf)]
	var o = File.new()
	if o.open(path, File.WRITE) != OK: return ""
	o.store_buffer(buf)
	o.close()
	return path

# ------------------------------------------------------------------ discard guard
func _guard_discard(method:String, args:Array):
	if m and m.dirty:
		confirm.dialog_text = "The current map has unsaved changes.\nContinue and discard them?"
		confirm_cb = [method, args]
		confirm.popup_centered(Vector2(460, 140))
	else:
		callv(method, args)

func _confirmed():
	if confirm_cb.size() == 2:
		var cb = confirm_cb
		confirm_cb = []
		callv(cb[0], cb[1])

func _ask_new():
	_guard_discard("_to_start", [])

func _ask_open():
	_guard_discard("_to_start", [])

func _to_start():
	if m:
		_autosave()
	m = null
	if playing: ap.stop()
	playing = false
	_wave_cleanup()
	wave_state = "none"
	start_panel.visible = true
	_lib_fill()

# ------------------------------------------------------------------ checks
func _run_checks():
	if !m: return
	diags = m.validate(audio_len, audio_ok)
	diag_list.clear()
	if diags.empty():
		diag_list.add_item("OK - no problems found")
	for d in diags:
		var tag = {"error": "[ERROR]", "warn": "[WARN]", "info": "[INFO]"}[d.sev]
		diag_list.add_item("%s %s%s" % [tag, d.msg, ("   @ " + Model.fmt_time(int(d.ms))) if d.ms >= 0 else ""])
		diag_list.set_item_metadata(diag_list.get_item_count() - 1, d.ms)

func _diag_pick(i:int):
	var ms = diag_list.get_item_metadata(i)
	if ms != null and ms >= 0:
		_seek(ms)
		_center_view()

func _errors() -> Array:
	var out = []
	for d in m.validate(audio_len, audio_ok):
		if d.sev == "error": out.append(d)
	return out

# ------------------------------------------------------------------ saving / export / test
func _make_song(id:String, in_memory:bool):
	var s = Song.new(id, str(m.meta.name), str(m.meta.creator))
	s.song = str(m.meta.name)
	s.difficulty = int(m.meta.difficulty)
	if src_song and src_song is Object:
		s.rating = src_song.rating
		s.custom_data = src_song.custom_data.duplicate(true)
		if src_song.has_cover and src_song.cover:
			s.has_cover = true
			s.cover = src_song.cover
	var txt = Model.to_txt(id, m.notes)
	s.setup_from_data(txt, m.meta.audio)
	s.last_ms = m.notes[m.notes.size() - 1][2] if !m.notes.empty() else 0
	return s

func _save_pressed():
	var r = save_map()
	if r != "": msg(r, true)
	else: msg("saved %s.sspm" % m.meta.id)

# returns "" on success, else the reason; the old file is restored on any failure
func save_map() -> String:
	if !m: return "nothing to save"
	var errs = _errors()
	if !errs.empty(): return "cannot save: " + errs[0].msg
	if m.extra_markers > 0 and !ack_markers:
		ack_markers = true
		return "this map has extra markers the editor drops - press SAVE again to save without them"
	_saving = true
	_refresh_state()
	var id = str(m.meta.id)
	var path = Globals.p("user://maps/%s.sspm") % id
	var d = Directory.new()
	if !d.dir_exists(Globals.p("user://maps")): d.make_dir_recursive(Globals.p("user://maps"))
	var s = _make_song(id, false) # (before the old file goes: the cover is read from it)
	var backup = ""
	if File.new().file_exists(path):
		var bdir = DIR + "/backup"
		if !d.dir_exists(bdir): d.make_dir_recursive(bdir)
		backup = "%s/%s_%d.sspm" % [bdir, id, OS.get_unix_time()]
		if d.copy(path, backup) != OK:
			_saving = false
			return "could not back up the existing file - nothing was changed"
		d.remove(path)
	var res = s.convert_to_sspm()
	var ok = res == "Converted!"
	var why = str(res)
	if ok:
		var chk = Song.new()
		var lr = chk.load_from_sspm(path)
		if lr is String:
			ok = false
			why = "written file does not load: " + lr
		else:
			var cn = chk.read_notes()
			if cn.size() != m.notes.size():
				ok = false
				why = "written file has %d notes, expected %d" % [cn.size(), m.notes.size()]
	if !ok:
		if File.new().file_exists(path): d.remove(path)
		if backup != "": d.copy(backup, path) # put the old file back
		_saving = false
		_refresh_state()
		return "save failed (%s)%s" % [why, " - the previous file was restored" if backup != "" else ""]
	_saving = false
	saved_once = true
	f_id.editable = false
	m.dirty = false
	m.rev += 1
	Rhythia.registry_song.check_and_remove_id(id)
	Rhythia.registry_song.add_sspm_map(path)
	var list = load("res://mods/replay/Classic.gd").map_list(menu)
	if list and list.has_method("prepare_songs"):
		list.prepare_songs()
		list.reload_to_current_page()
	_autosave()
	return ""

func _export():
	if !m: return
	var r = save_map()
	if r != "":
		msg(r, true)
		return
	_fs_raise("_export_to")
	Globals.file_sel.open_folder(self, "_fs_done", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))

func _export_to(path):
	if typeof(path) != TYPE_STRING:
		if path.size() == 0: return
		path = path[0]
	if path == "": return
	var id = str(m.meta.id)
	var d = Directory.new()
	var dst = "%s/%s.sspm" % [path, id]
	var n = 1
	while File.new().file_exists(dst): # never overwrite an existing file
		dst = "%s/%s_%d.sspm" % [path, id, n]
		n += 1
	var err = d.copy(Globals.p("user://maps/%s.sspm") % id, dst)
	if err != OK:
		msg("export failed (error %d)" % err, true)
		return
	var chk = Song.new()
	var lr = chk.load_from_sspm(dst)
	if lr is String or chk.read_notes().size() != m.notes.size():
		msg("export written but did not verify: " + str(lr), true)
		return
	var txt = dst.get_basename() + ".txt"
	var f = File.new()
	if !f.file_exists(txt) and f.open(txt, File.WRITE) == OK:
		f.store_string(Model.to_txt(id, m.notes))
		f.close()
	var extra = " (+ .txt)"
	if ResourceLoader.exists("res://mods/fixes/Phxm.gd"): # the rewrite's format next to it
		var px = load("res://mods/fixes/Phxm.gd").export(chk, dst.get_basename() + ".phxm")
		extra = " (+ .txt, .phxm)" if px is Dictionary else " (+ .txt; .phxm failed: %s)" % px
	msg("exported and verified: " + dst.get_file() + extra)

func _test(from_here:bool):
	if !m: return
	if !audio_ok or m.notes.empty():
		msg("need audio and at least one note to test", true)
		return
	var errs = _errors()
	if !errs.empty():
		msg("cannot test: " + errs[0].msg, true)
		return
	if playing: ap.stop()
	playing = false
	_autosave()
	var s = _make_song(TEST_ID, true)
	s.is_broken = false
	s.warning = ""
	Engine.set_meta("rr_editor_model", m)
	Engine.set_meta("rr_editor_pos", pos)
	Engine.set_meta("rr_editor_testing", true)
	Engine.set_meta("rr_editor_prev", Rhythia.selected_song.id if Rhythia.selected_song else "")
	Engine.set_meta("rr_editor_saved_once", saved_once)
	if src_song and "id" in src_song: Engine.set_meta("rr_editor_src", src_song.id)
	Rhythia.start_offset = max(pos - 1500.0, 0.0) if from_here else 0.0
	Rhythia.select_song(s)
	Rhythia.replaying = false
	if "black_fade_target" in menu: menu.black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	_wave_cleanup()
	get_tree().change_scene("res://scenes/loaders/songload.tscn")

# ------------------------------------------------------------------ closing
func _exit():
	if _closing: return
	_closing = true
	if m:
		if m.dirty: _autosave()
		Engine.set_meta("rr_editor_model", m)
		Engine.set_meta("rr_editor_pos", pos)
		Engine.set_meta("rr_editor_saved_once", saved_once)
		if src_song and "id" in src_song: Engine.set_meta("rr_editor_src", src_song.id)
	if playing: ap.stop()
	var t = UIAnim.play(root, Vector2.ZERO, Vector2(0, 18), 1.0, 0.0, 0.2)
	t.connect("finished", self, "queue_free")

# ------------------------------------------------------------------ keys
func _input(ev):
	if _closing: return
	if !(ev is InputEventKey) or !ev.pressed or ev.echo: return
	var fo = root.get_focus_owner()
	var typing = fo is LineEdit and !(fo.get_parent() is SpinBox) # (a number box never needs a space / letter shortcut)
	if confirm.visible: return
	if ev.scancode == KEY_ESCAPE:
		if typing:
			fo.release_focus()
		elif start_panel.visible and m:
			start_panel.visible = false
		else:
			_exit()
		get_tree().set_input_as_handled()
		return
	if typing: return
	var handled = true
	if ev.shift and m and ev.scancode >= KEY_1 and ev.scancode <= KEY_9: # pattern slots (AUTO tab)
		if ev.control: _slot_store(ev.scancode - KEY_0)
		else: _slot_recall(ev.scancode - KEY_0)
		get_tree().set_input_as_handled()
		return
	if ev.shift and !ev.control and m: # (Quantum Editor bindings: flips, curve)
		var sh = true
		match ev.scancode:
			KEY_H: _op_mirror(true)
			KEY_V: _op_mirror(false)
			KEY_D: _bezier()
			KEY_C: _toggle_cursor()
			_: sh = false
		if sh:
			get_tree().set_input_as_handled()
			return
	if ev.control:
		match ev.scancode:
			KEY_S: if m: _save_pressed()
			KEY_Z:
				if ev.shift: _redo()
				else: _undo()
			KEY_Y: _redo()
			KEY_C: _copy()
			KEY_X: _cut()
			KEY_V: _paste()
			KEY_D: _duplicate()
			KEY_A: _select_all()
			KEY_T: _page("timing")
			KEY_B:
				if ev.shift: _point_add()
				else:
					_page("timing")
					book_list.grab_focus()
			KEY_Q: _toggle_quantum()
			KEY_LEFT: if m: _seek(m.grid_next(pos, -1, 0.25)) # (one measure)
			KEY_RIGHT: if m: _seek(m.grid_next(pos, 1, 0.25))
			_: handled = false
	else:
		if !m:
			return
		var gk = GRID_KEYS.find(ev.scancode)
		if gk < 0: gk = PAD_KEYS.find(ev.scancode)
		if gk >= 0 and !ev.shift: # a note on that cell at the (snapped) playhead
			_place_note(Vector2(gk % 3, gk / 3))
			get_tree().set_input_as_handled()
			return
		match ev.scancode:
			KEY_SPACE: _toggle_play()
			KEY_LEFT: _seek(_step_from(pos, -1))
			KEY_RIGHT: _seek(_step_from(pos, 1))
			KEY_HOME: _seek(0.0)
			KEY_END: _seek(audio_len)
			KEY_DELETE, KEY_BACKSPACE: _delete_sel()
			KEY_COMMA: _jump_note(-1)
			KEY_PERIOD: _jump_note(1)
			KEY_B: _bookmark_add()
			KEY_L: _set_loop(!loop_on)
			KEY_BRACKETLEFT: _loop_mark(true)
			KEY_BRACKETRIGHT: _loop_mark(false)
			KEY_F5: _test(ev.shift)
			KEY_UP: _op_nudge(1) if ev.alt else _move_selection(Vector2(0, -1 if pos_snap == "cell" else -0.5), 0, "move up")
			KEY_DOWN: _op_nudge(-1) if ev.alt else _move_selection(Vector2(0, 1 if pos_snap == "cell" else 0.5), 0, "move down")
			_: handled = false
	if handled: get_tree().set_input_as_handled()

# grid keys (the Quantum Editor's layout): Q W E / A S D / Z X C, or the numpad, = the 3x3 cells
const GRID_KEYS = [KEY_Q, KEY_W, KEY_E, KEY_A, KEY_S, KEY_D, KEY_Z, KEY_X, KEY_C]
const PAD_KEYS = [KEY_KP_7, KEY_KP_8, KEY_KP_9, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_1, KEY_KP_2, KEY_KP_3]
const GRID_LETTERS = ["Q", "W", "E", "A", "S", "D", "Z", "X", "C"]

# Ctrl+Q: free note positions (the Quantum Editor's "quantum") <-> grid cells
func _toggle_quantum():
	var to = "cell" if pos_snap == "free" else "free"
	pos_snap = to
	if pos_btns.has(to): pos_btns[to].pressed = true
	msg("note positions: free (quantum)" if to == "free" else "note positions: grid cells")

func _step_from(t:float, dir:int) -> float:
	if !time_snap: return t + dir * 10.0
	return m.grid_next(t, dir)

# ------------------------------------------------------------------ AUTO tab: audio analysis, patterns, transforms
# Audio analysis (EditorAuto.gd): BPM / offset estimates + onset markers from the muted capture;
# nothing changes until a candidate is applied, and "preview grid" draws it over the timeline first.
# Patterns (EditorPatterns.gd): generated at the playhead on the current grid step, inserted as one
# undo step and selected. Pattern slots: Ctrl+Shift+1..9 stores the selection, Shift+1..9 puts it
# at the playhead. Alt held while placing / dragging = no time snap.
const Auto = preload("res://mods/replay/EditorAuto.gd")
const Pat = preload("res://mods/replay/EditorPatterns.gd")
var auto_pending:bool = false
var auto_thread:Thread = null
var auto_res:Dictionary = {}
var auto_lbl:Label
var auto_cands:VBoxContainer
var auto_preview = null          # [bpm, offset] drawn over the timeline, or null
var show_onsets:bool = true
var pat_ui:Dictionary = {}
var slots:Dictionary = {}        # 1..9 -> notes relative to the first one

func _build_auto(p:Control):
	p.add_child(_lbl("AUDIO ANALYSIS (BPM / OFFSET ESTIMATE)", 12, Look.TEXT_3))
	var r = HBoxContainer.new()
	r.add_constant_override("separation", 4)
	r.add_child(_btn("ANALYSE AUDIO", "_auto_start", [], false, 150))
	var ck = CheckBox.new()
	ck.text = "beat markers"
	ck.pressed = true
	ck.focus_mode = Control.FOCUS_NONE
	ck.add_font_override("font", _font(13))
	ck.connect("toggled", self, "_auto_onsets")
	r.add_child(ck)
	p.add_child(r)
	auto_lbl = _lbl("Estimates the tempo and the first beat from the song. Check it by ear: it can come out at half / double speed.", 12, Look.TEXT_2)
	auto_lbl.autowrap = true
	auto_lbl.rect_min_size.x = 290
	p.add_child(auto_lbl)
	auto_cands = VBoxContainer.new()
	auto_cands.add_constant_override("separation", 4)
	p.add_child(auto_cands)
	# patterns
	p.add_child(_lbl("PATTERN AT THE PLAYHEAD (ONE GRID STEP APART)", 12, Look.TEXT_3))
	var kind = OptionButton.new()
	for k in ["stream", "jumps", "circle", "spiral"]: kind.add_item(k)
	_field_row(p, "Pattern", kind)
	pat_ui.kind = kind
	var path = OptionButton.new()
	for k in Pat.PATHS: path.add_item(k)
	path.select(Pat.PATHS.find("snake"))
	_field_row(p, "Stream path", path)
	pat_ui.path = path
	for f in [["count", "Notes", 2, 256, 1, 8], ["every", "Grid steps between notes", 1, 16, 1, 1], ["dist", "Jumps: min distance (cells)", 0.5, 2.9, 0.1, 1.5],
			["seed", "Jumps: variation", 1, 9999, 1, 1], ["r0", "Circle / spiral: radius from", 0.1, 1.5, 0.05, 1.0],
			["r1", "Spiral: radius to", 0.0, 1.5, 0.05, 0.3], ["turns", "Circle / spiral: turns", 0.25, 8, 0.25, 1.0]]:
		var sp = SpinBox.new()
		sp.min_value = f[2]
		sp.max_value = f[3]
		sp.step = f[4]
		sp.value = f[5]
		_field_row(p, f[1], sp)
		pat_ui[f[0]] = sp
	var cw = CheckBox.new()
	cw.text = "clockwise"
	cw.pressed = true
	cw.focus_mode = Control.FOCUS_NONE
	cw.add_font_override("font", _font(13))
	p.add_child(cw)
	pat_ui.cw = cw
	p.add_child(_btn("GENERATE AT PLAYHEAD", "_pat_generate"))
	# transforms
	p.add_child(_lbl("TRANSFORM THE SELECTION", 12, Look.TEXT_3))
	var piv = CheckBox.new()
	piv.text = "about the selection's centre (else the grid's)"
	piv.focus_mode = Control.FOCUS_NONE
	piv.add_font_override("font", _font(13))
	p.add_child(piv)
	pat_ui.pivot = piv
	var ang = SpinBox.new()
	ang.min_value = -360
	ang.max_value = 360
	ang.step = 1
	ang.value = 45
	ang.suffix = "°"
	_field_row(p, "Rotate by", ang)
	pat_ui.angle = ang
	var scl = SpinBox.new()
	scl.min_value = 0.1
	scl.max_value = 4
	scl.step = 0.05
	scl.value = 0.5
	_field_row(p, "Scale by", scl)
	pat_ui.scale = scl
	var g = GridContainer.new()
	g.columns = 2
	g.add_constant_override("hseparation", 4)
	g.add_constant_override("vseparation", 4)
	for b in [["ROTATE", "_pat_tf", ["rotate"]], ["SCALE", "_pat_tf", ["scale"]], ["REVERSE TIME", "_pat_tf", ["reverse"]],
			["MIRROR SECTION X", "_pat_mirror_section", ["x"]], ["MIRROR SECTION Y", "_pat_mirror_section", ["y"]],
			["REPEAT x4 ROTATING", "_pat_repeat", ["rotate"]], ["CURVE THROUGH SELECTION", "_bezier", []]]:
		var bt = _btn(b[0], b[1], b[2])
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(bt)
	p.add_child(g)
	var help = _lbl("Slots: Ctrl+Shift+1..9 store the selection, Shift+1..9 put it at the playhead. Curve (Shift+D): the selected notes are its control points, notes on every grid step from the first to the last. Hold Alt to place / drag without time snap.", 12, Look.TEXT_3)
	help.autowrap = true
	help.rect_min_size.x = 290
	p.add_child(help)

func _auto_onsets(on:bool):
	show_onsets = on
	tl.update()

func _auto_start():
	if !m or !stream:
		msg("open a map with audio first", true)
		return
	if auto_thread and auto_thread.is_active(): return
	auto_pending = true
	if wave_state == "ready" and env_lo.size() > 0:
		_auto_run()
		return
	auto_lbl.text = "Listening to the song (muted, 4x speed)..."
	_wave_begin(true) # (no cached band envelopes for this audio: capture again)

func _auto_run():
	auto_pending = false
	if env_lo.size() == 0:
		auto_lbl.text = "No band energies were captured for this audio."
		return
	auto_lbl.text = "Analysing..."
	auto_thread = Thread.new()
	auto_thread.start(self, "_auto_work", [env_lo, env_hi, env_all])

func _auto_work(a:Array):
	call_deferred("_auto_done", Auto.analyse(a[0], a[1], a[2], Cap.ABIN))

func _auto_done(res:Dictionary):
	if auto_thread and auto_thread.is_active(): auto_thread.wait_to_finish()
	auto_res = res
	for c in auto_cands.get_children(): c.queue_free()
	if res.bpm <= 0:
		auto_lbl.text = "Couldn't find a steady beat (%d onsets). Set the BPM by ear (TAP BPM on the TIMING tab)." % res.onsets.size()
		tl.update()
		return
	auto_lbl.text = "%d onsets found. Estimates (best first; confidence = how much more the beats line up than at a random phase):" % res.onsets.size()
	for c in res.candidates:
		var h = HBoxContainer.new()
		h.add_constant_override("separation", 4)
		var l = _lbl("%.2f BPM  offset %d ms  (%.1fx)" % [c[0], c[1], c[2]], 13, Look.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(_btn("PREVIEW", "_auto_preview", [c], false, 76))
		h.add_child(_btn("USE", "_auto_apply", [c], false, 50))
		auto_cands.add_child(h)
	tl.update()

func _auto_preview(c:Array):
	auto_preview = null if auto_preview == c else c
	msg(("preview grid: %.2f BPM from %d ms (accent lines; USE to keep it)" % [c[0], c[1]]) if auto_preview else "preview off")
	tl.update()

func _auto_apply(c:Array):
	auto_preview = null
	sp_bpm.value = c[0]
	sp_off.value = c[1]
	_timing_changed(0)
	msg("BPM %.2f, offset %d ms (editor grid; notes not moved - SNAP SELECTION TO GRID does that)" % [c[0], c[1]])
	tl.update()

# onset markers + the previewed grid over the timeline
func _draw_auto(c:Control, lane:Rect2, t0:float, t1:float):
	if show_onsets and auto_res.has("onsets"):
		var ons = auto_res.onsets
		var i = _bsearch(ons, t0)
		while i < ons.size() and ons[i] <= t1:
			var x = _x_of(ons[i])
			c.draw_line(Vector2(x, lane.position.y), Vector2(x, lane.position.y + 10), Color(1, 0.8, 0.3, 0.8), 2.0)
			i += 1
	if auto_preview:
		var bpm = auto_preview[0]
		var off = auto_preview[1]
		var per = 60000.0 / bpm
		var k = floor((t0 - off) / per)
		var n = 0
		while n < 4000:
			var t = off + k * per
			if t > t1: break
			var x = _x_of(t)
			c.draw_line(Vector2(x, lane.position.y), Vector2(x, lane.end.y), Color(0.3, 0.9, 1.0, 0.45 if posmod(int(k), 4) == 0 else 0.22), 1.0)
			k += 1
			n += 1

func _bsearch(arr:Array, t:float) -> int:
	var lo = 0
	var hi = arr.size()
	while lo < hi:
		var mid = (lo + hi) / 2
		if arr[mid] < t: lo = mid + 1
		else: hi = mid
	return lo

func _insert_notes(name:String, ns:Array):
	if ns.empty(): return
	m.begin(name)
	var n = m.run(["add", ns])
	m.end()
	sel = {}
	for x in ns:
		var key = Model.key_of([float(x[0]), float(x[1]), int(round(x[2]))])
		if m.keys.has(key): sel[key] = [float(x[0]), float(x[1]), int(round(x[2]))]
	_sel_changed()
	var oob = Pat.out_of_bounds(ns)
	msg("%s: %d notes%s%s" % [name, n, (" (%d were already there)" % (ns.size() - n)) if n < ns.size() else "", ("  - %d outside the playable area" % oob) if oob > 0 else ""], oob > 0)

func _pat_generate():
	if !m: return
	var t0 = m.snap_t(pos) if time_snap else pos
	var step = m.step_at(t0) * pat_ui.every.value
	var n = int(pat_ui.count.value)
	var ns = []
	match pat_ui.kind.get_item_text(pat_ui.kind.selected):
		"stream": ns = Pat.stream(t0, step, n, Pat.PATHS[pat_ui.path.selected])
		"jumps": ns = Pat.jumps(t0, step, n, pat_ui.dist.value, int(pat_ui.seed.value))
		"circle": ns = Pat.spiral(t0, step, n, pat_ui.r0.value, pat_ui.r0.value, pat_ui.turns.value, pat_ui.cw.pressed)
		"spiral": ns = Pat.spiral(t0, step, n, pat_ui.r0.value, pat_ui.r1.value, pat_ui.turns.value, pat_ui.cw.pressed)
	_insert_notes(pat_ui.kind.get_item_text(pat_ui.kind.selected), ns)

func _pivot(ns:Array) -> Vector2:
	return Pat.centroid(ns) if pat_ui.pivot.pressed else Pat.CENTER

func _replace_sel(name:String, news:Array):
	var ns = _sel_notes()
	if ns.empty():
		msg("select notes first")
		return
	m.begin(name)
	m.run(["del", ns])
	m.run(["add", news])
	m.end()
	sel = {}
	for x in news: sel[Model.key_of(x)] = x
	_sel_changed()
	var oob = Pat.out_of_bounds(news)
	msg(name + (("  - %d notes now outside the playable area" % oob) if oob > 0 else ""), oob > 0)

func _pat_tf(op:String):
	var ns = _sel_notes()
	if ns.empty():
		msg("select notes first")
		return
	var amt = pat_ui.angle.value if op == "rotate" else (pat_ui.scale.value if op == "scale" else 0.0)
	_replace_sel("%s%s" % [op, (" %s" % str(amt)) if op != "reverse" else ""], Pat.transform(ns, op, amt, _pivot(ns)))

func _pat_mirror_section(axis:String):
	var ns = _sel_notes()
	if ns.empty():
		msg("select notes first")
		return
	_insert_notes("mirror section " + axis, Pat.mirror_section(ns, axis, m.step_at(ns[0][2])))

func _pat_repeat(op:String):
	var ns = _sel_notes()
	if ns.empty():
		msg("select notes first")
		return
	var t_min = ns[0][2]
	var t_max = ns[0][2]
	for x in ns:
		t_min = min(t_min, x[2])
		t_max = max(t_max, x[2])
	var period = t_max - t_min + m.step_at(t_min)
	_insert_notes("repeat x4 rotating", Pat.repeat(ns, 3, period, op, 90.0))

# Bezier curve: the selection (2+ notes, by time) are the control points; the curve gets a note on
# every grid step from the first note's time to the last's and replaces them (one undo step)
func _bezier():
	var ns = _sel_notes()
	if ns.size() < 2:
		msg("select 2 or more notes: the curve starts on the first, ends on the last and bends toward the others")
		return
	var t0 = float(ns[0][2])
	var t1 = float(ns[ns.size() - 1][2])
	if t1 - t0 < 1.0:
		msg("the selected notes need different times", true)
		return
	var times = []
	var t = t0
	while t < t1 - 0.5 and times.size() < 4000:
		times.append(int(round(t)))
		t = m.grid_next(t, 1) if time_snap else t + m.step_at(t)
	times.append(int(t1))
	_replace_sel("curve (%d notes)" % times.size(), Pat.bezier(ns, times))

func _slot_store(k:int):
	var ns = _sel_notes()
	if ns.empty():
		msg("select notes to store in slot %d" % k)
		return
	slots[k] = Pat.to_slot(ns)
	msg("slot %d: %d notes stored (Shift+%d puts them at the playhead)" % [k, ns.size(), k])

func _slot_recall(k:int):
	if !slots.has(k):
		msg("slot %d is empty (Ctrl+Shift+%d stores the selection)" % [k, k])
		return
	_insert_notes("slot %d" % k, Pat.from_slot(slots[k], m.snap_t(pos) if time_snap else pos))
