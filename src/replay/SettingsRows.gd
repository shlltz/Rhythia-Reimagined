extends Node
# Settings rows (Rhythia-reimagined): every setting gets the same layout - its name on the left, its
# control on the right, a short description under it (from the game's own tooltip), a reset arrow
# while it differs from its default, and switches instead of tick boxes. Long colour lists start
# folded. Changes are saved a moment after they're made (the stock page only saved when it closed,
# so a crash lost them) and the header says so.
# Nothing moves to another parent: the game finds every setting by path. A row only gets a reset
# arrow when its default is known and its control can be set back the way the game itself sets it.

const Look = preload("res://mods/replay/Look.gd")
const ROW_W = 980.0 # widest a row gets: wider screens keep the controls close to their names
const FOLDED = ["UI/UIColor", "Replays & Misc/Experimental"] # long / rarely used sections start folded
# stock spin boxes without a `target`: script -> [Rhythia setting, display factor]
const SPINS = {"HitWindow": ["hitwindow_ms", 1], "NoteHitboxSize": ["note_hitbox_size", 1], "Sensitivity": ["sensitivity", 1],
	"LockMouseResize": ["absolute_scale", 1], "Parallax": ["parallax", 1], "UIParallax": ["ui_parallax", 1],
	"GridParallax": ["grid_parallax", 1], "EdgeBuffer": ["edge_drift", 1], "HitFOVAmplifier": ["hit_fov_amplifier", 1],
	"HitFOVDecay": ["hit_fov_decay", 1], "NoteScale": ["note_size", 1], "NoteOpacity": ["note_opacity", 100],
	"ApproachRate": ["approach_rate", 1], "SpawnDist": ["spawn_distance", 1], "FadeLength": ["fade_length", 100],
	"Glow": ["glow", 1], "Bloom": ["bloom", 1], "CursorScale": ["cursor_scale", 1], "CursorSpin": ["cursor_spin", 1],
	"TrailDetail": ["trail_detail", 1], "TrailTime": ["trail_time", 1], "MusicOffset": ["music_offset", 1],
	"CustomSpeed": ["custom_speed", 100], "fov": ["fov", 1]}
const OPTIONS = {"ReplayMode": "record_mode", "ReplayLimit": "record_limit"}
const VOLUMES = {"Master": 50.0, "Music": 50.0, "HitSound": 30.0, "MissSound": 60.0, "FailSound": 60.0, "PBSound": 60.0} # stock Rhythia.gd
const NO_RESET = ["enable_oldmenu"] # its own switch quits the game to apply
# clearer words for the stock tooltips that only joke
const DESCS = {"FOV": "Field of view of the gameplay camera, in degrees.",
	"NoteSpawnEffect": "A flash where each note appears. Off = no distraction.",
	"CursorTrail": "The game's own cursor trail (Customize > Cursor trail has an osu!-style one).",
	"ShowHealth": "Show the energy bar.",
	"Replays": "Record a replay of every run (sidebar > Replays, or drag a replay file into the game).",
	"Fullscreen": "Fill the whole screen.",
	"SweptHitbox": "Also counts notes your cursor passes through between two frames (fast flicks). Same hitbox size and hit window. Off = classic. Applies on the next map."}

var style:Node # SettingsStyle
var tabs:TabContainer
var fresh:Dictionary = {} # Rhythia defaults, read from a new instance of its script
var rows:Array = [] # {row, ctl, kind, key, def, reset, tab}
var folds:Array = [] # {sec, btn, open}
var saved:Label
var dirty_t:float = -1.0
var saved_t:float = 0.0
var poll:float = 0.0
var last:Dictionary = {}
var blank:ImageTexture
var tab_reset:Button
var confirm_until:int = 0

func setup(s:Node, card:Control):
	style = s
	tabs = s.tabs
	name = "RRRows"
	s.add_child(self)
	var d = Rhythia.get_script().new() # (not in the tree: only its declared values, no _ready)
	for p in d.get_script().get_script_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE: fresh[p.name] = d.get(p.name)
	d.free()
	if !fresh.get("hlm_converted", true): # (stock: the first load scales these once, so a new player starts with them x1.4)
		for k in ["parallax", "ui_parallax", "grid_parallax"]:
			if fresh.has(k): fresh[k] = fresh[k] * (0.35 / 0.25)
	var img = Image.new()
	img.create(1, 1, false, Image.FORMAT_RGBA8)
	blank = ImageTexture.new()
	blank.create_from_image(img, 0)
	for t in tabs.get_children():
		if !(t is Control): continue
		for sec in t.get_children():
			var h = sec.get_node_or_null("Group/H") if sec is Control else null
			if !h: continue
			h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for r in h.get_children(): _row(r, t)
			if (t.name + "/" + sec.name) in FOLDED: _fold(sec)
	_header(card)
	_top_buttons()
	for r in rows: last[r.row] = _value(r)
	_refresh_all()

# ---------------------------------------------------------------- one row
func _row(r:Node, tab:Control):
	if !(r is Control) or r is Separator: return
	var ctl:Control = null
	var kind = ""
	if r is CheckBox:
		ctl = r; kind = "check"
	elif r is HBoxContainer:
		for c in r.get_children():
			if c is SpinBox:
				ctl = c
				kind = "volume" if r.get("target_bus") else "spin"
			elif c is ColorPickerButton:
				ctl = c
				kind = "color"
			elif c is OptionButton:
				ctl = c
				kind = "option"
			elif c is MenuButton:
				ctl = c
				kind = "menu"
			if ctl: break
	if !ctl: return
	var e = {row = r, ctl = ctl, kind = kind, key = "", def = null, reset = null, tab = tab}
	_find_default(e)
	if r is HBoxContainer: _layout(r)
	else: _switch(r)
	_describe(r, ctl, e)
	if e.def != null and !(e.key in NO_RESET): e.reset = _reset_button(e)
	rows.append(e)

# name first (taking the free width), then the control(s); the stock description / divider hide
func _layout(r:HBoxContainer):
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l = r.get_node_or_null("Label")
	if l:
		r.move_child(l, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.rect_min_size.x = 0
		l.valign = Label.VALIGN_CENTER
	for n in ["Desc", "VSeparator"]:
		var c = r.get_node_or_null(n)
		if c: c.visible = false
	for c in r.get_children():
		if c is SpinBox: c.rect_min_size.x = max(c.rect_min_size.x, 150)
		elif c is OptionButton or c is MenuButton: c.rect_min_size.x = max(c.rect_min_size.x, 230)
		elif c is ColorPickerButton: c.rect_min_size = Vector2(110, max(c.rect_min_size.y, 30))
	if r.get("target_bus") and r.has_node("percent"): _slider(r, r.get_node("percent"))

# volume rows: a slider next to the % box (the box and the dB box stay; all three move together)
func _slider(r:HBoxContainer, pc:SpinBox):
	var s = HSlider.new()
	s.name = "RRSlider"
	s.min_value = pc.min_value
	s.max_value = min(pc.max_value, 100.0)
	s.step = 1
	s.value = pc.value
	s.rect_min_size = Vector2(220, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	r.add_child(s)
	r.move_child(s, pc.get_index())
	s.connect("value_changed", self, "_slide", [pc])
	pc.connect("value_changed", self, "_slid", [s])
	var db = r.get_node_or_null("db")
	if db is SpinBox: db.rect_min_size.x = 120

func _slide(v:float, pc:SpinBox):
	if pc.value != v: pc.value = v

func _slid(v:float, s:HSlider):
	if s.value != v: s.set_block_signals(true); s.value = v; s.set_block_signals(false)

# tick box -> switch drawn at the right end of the row (the box itself still takes the click)
func _switch(c:CheckBox):
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["checked", "unchecked", "radio_checked", "radio_unchecked", "checked_disabled", "unchecked_disabled", "radio_checked_disabled", "radio_unchecked_disabled"]: c.add_icon_override(k, blank)
	c.add_constant_override("hseparation", 0)
	c.add_constant_override("check_vadjust", 0)
	for k in ["normal", "pressed", "hover", "hover_pressed", "focus", "disabled"]:
		var sb = c.get_stylebox(k)
		if sb:
			sb = sb.duplicate()
			sb.content_margin_left = 0
			c.add_stylebox_override(k, sb)
	var s = Switch.new()
	s.box = c
	s.accent = Color(1, 1, 1) if style.mono else Look.accent()
	s.square = style.mono
	s.anchor_left = 1; s.anchor_right = 1; s.anchor_top = 0.5; s.anchor_bottom = 0.5
	s.margin_left = -52; s.margin_right = -8; s.margin_top = -11; s.margin_bottom = 11
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(s)
	c.connect("toggled", s, "_toggled")
	c.connect("mouse_entered", s, "update")
	c.connect("mouse_exited", s, "update")
	c.connect("focus_entered", s, "update")
	c.connect("focus_exited", s, "update")

func _describe(r:Control, ctl:Control, e:Dictionary):
	var tip = r.hint_tooltip if r.hint_tooltip != "" else ctl.hint_tooltip
	var text = DESCS.get(r.name, "")
	if text == "": text = _clean(tr(tip), e)
	var name_l = r.get_node_or_null("Label") if r is HBoxContainer else r
	if name_l and text.to_lower().replace(".", "").strip_edges() == tr(name_l.text).to_lower().strip_edges(): text = "" # (only repeats the name)
	r.hint_tooltip = ""
	ctl.hint_tooltip = ""
	if text.length() < 4: return
	var d = Label.new()
	d.name = r.name + "_rrdesc"
	d.set_meta("rr_desc", r)
	d.text = text
	d.autowrap = true
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.add_font_override("font", style._font(15))
	d.add_color_override("font_color", Color(1, 1, 1, 0.42))
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h = r.get_parent()
	h.add_child(d)
	h.move_child(d, r.get_index() + 1)
	d.visible = r.visible
	r.connect("visibility_changed", self, "_follow", [r, d])

func _follow(r:Control, d:Control):
	d.visible = r.visible

# "[def. 1.14] the size of ..." -> "The size of ..." (the default is shown by the reset arrow)
static func _clean(t:String, e:Dictionary) -> String:
	t = t.strip_edges()
	if t.begins_with("["):
		var close = t.find("]")
		if close > 0:
			var inner = t.substr(1, close - 1)
			t = t.substr(close + 1).strip_edges()
			if !(inner.begins_with("def") or inner.begins_with("default")): t = "(" + inner + ") " + t
	t = t.replace("##DEFAULT##", "")
	if t.length() > 0: t = t[0].to_upper() + t.substr(1)
	if t.length() > 0 and !(t[t.length() - 1] in [".", "!", "?", ")"]): t += "."
	return t

# ---------------------------------------------------------------- defaults
func _find_default(e:Dictionary):
	var c = e.ctl
	var tg = c.get("target")
	if c.has_meta("rr_default"):
		e.def = c.get_meta("rr_default"); e.key = "rr"
	elif e.kind == "volume":
		var bus = str(e.row.get("target_bus"))
		if VOLUMES.has(bus): e.def = VOLUMES[bus]; e.key = "bus:" + bus
	elif tg is String and tg != "" and fresh.has(tg):
		e.key = tg
		e.def = fresh[tg]
		if e.kind == "spin" and !_same(c.value, Rhythia.get(tg)): e.def = null # (shown in other units: no reset)
	elif e.kind == "check" and c.get_script() and _script(c) == "VSync":
		e.def = false; e.key = "vsync"
	elif e.kind == "spin" and SPINS.has(_script(c)):
		var m = SPINS[_script(c)]
		if fresh.has(m[0]) and _same(c.value, float(Rhythia.get(m[0])) * m[1]): # units checked against the live value
			e.key = m[0]; e.def = float(fresh[m[0]]) * m[1]
	elif e.kind == "option" and OPTIONS.has(_script(c)):
		var k = OPTIONS[_script(c)]
		if fresh.has(k): e.key = k; e.def = fresh[k]

static func _script(c:Node) -> String:
	var s = c.get_script()
	return s.resource_path.get_file().get_basename() if s else ""

static func _same(a, b) -> bool:
	if a is Color and b is Color: return a.to_html() == b.to_html()
	if (a is float or a is int) and (b is float or b is int): return abs(float(a) - float(b)) < 0.0005
	return a == b

func _value(e:Dictionary):
	match e.kind:
		"check": return e.ctl.pressed
		"spin", "volume": return e.ctl.value
		"color": return e.ctl.color
		"menu": return Rhythia.get(e.key) if e.key != "" else e.ctl.text
		"option": return e.ctl.get_item_id(e.ctl.selected)
	return null

func is_default(e:Dictionary) -> bool:
	return e.def == null or _same(_value(e), e.def)

# back to the default, through the control the way a click would do it
func reset(e:Dictionary):
	if e.def == null: return
	var c = e.ctl
	match e.kind:
		"check":
			c.pressed = bool(e.def)
			if c.has_method("_pressed"): c._pressed()
		"spin", "volume":
			c.value = float(e.def)
		"color":
			c.color = e.def
			c.emit_signal("popup_closed")
		"menu":
			if c.has_method("on_pressed"): c.on_pressed(int(e.def))
		"option":
			c.select(c.get_item_index(int(e.def)))
			c.emit_signal("item_selected", c.selected)
	_changed()

func _reset_button(e:Dictionary) -> Button:
	var b = ResetArrow.new()
	b.hint_tooltip = "Reset to default (" + _show(e.def, e) + ")"
	b.focus_mode = Control.FOCUS_ALL
	b.rect_min_size = Vector2(34, 30)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.connect("pressed", self, "_reset_one", [e])
	if e.row is HBoxContainer:
		e.row.add_child(b)
		e.row.move_child(b, 1)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		b.anchor_left = 1; b.anchor_right = 1; b.anchor_top = 0.5; b.anchor_bottom = 0.5
		b.margin_left = -96; b.margin_right = -62; b.margin_top = -15; b.margin_bottom = 15
		e.row.add_child(b)
	return b

func _reset_one(e:Dictionary):
	reset(e)
	_refresh(e)
	if style.menu.has_node("Press"): style.menu.get_node("Press").play()

static func _show(v, e:Dictionary) -> String:
	if v is bool: return "on" if v else "off"
	if v is Color: return "#" + v.to_html(v.a < 1)
	if e.kind == "volume": return "%d%%" % int(v)
	if e.kind == "option" and e.ctl is OptionButton:
		var i = e.ctl.get_item_index(int(v))
		return e.ctl.get_item_text(i) if i >= 0 else str(v)
	if e.kind == "menu" and e.ctl.get("options") is Array and int(v) < e.ctl.options.size(): return str(e.ctl.options[int(v)])
	if v is float: return str(stepify(v, 0.01))
	return str(v)

func _refresh(e:Dictionary):
	if e.reset: e.reset.visible = !is_default(e)

func _refresh_all():
	for e in rows: _refresh(e)
	_tab_reset_text()

# rows fill the page up to ROW_W, so a control stays near its name on wide screens
func fit(width:float):
	var row_w = min(width - 40.0 - 100.0, ROW_W) # (Group margins: 40 left, the rest right)
	for t in tabs.get_children():
		if !(t is Control): continue
		for sec in t.get_children():
			var g = sec.get_node_or_null("Group") if sec is Control else null
			if g is MarginContainer: g.add_constant_override("margin_right", int(max(60.0, width - 40.0 - ROW_W)))
	# the colour-set grid set its columns from its own width on every resize: with wrapping
	# descriptions that toggled the scroll bar, which changed the width again - the page froze.
	# Its columns now follow the page width instead (changes only with the window).
	var cs = tabs.get_node_or_null("Notes/Notes/Group/H/ColorSet2")
	if cs:
		for g in _colorset_grids(cs):
			g.set_meta("rr_cols", int(max(1, floor((row_w - 40.0) / 100.0))))
			fix_colorset_grid(g)

static func fix_colorset_grid(g:Node):
	if !g.has_meta("rr_cols"): return
	if g.is_connected("resized", g, "col"): g.disconnect("resized", g, "col")
	g.columns = g.get_meta("rr_cols")

func _colorset_grids(n:Node) -> Array:
	var out = []
	for c in n.get_children():
		if c is GridContainer and c.has_method("col"): out.append(c)
		out += _colorset_grids(c)
	return out

# ---------------------------------------------------------------- folding
func _fold(sec:Control):
	var title = sec.get_node_or_null("SectionTitle")
	var group = sec.get_node_or_null("Group")
	if !title or !group: return
	var b = Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_font_override("font", style._font(16))
	b.add_color_override("font_color", Color(1, 1, 1, 0.55))
	b.add_color_override("font_color_hover", Color(1, 1, 1, 0.95))
	b.align = Button.ALIGN_LEFT
	sec.add_child(b)
	sec.move_child(b, group.get_index())
	var f = {sec = sec, btn = b, group = group, open = false}
	b.connect("pressed", self, "_toggle_fold", [f])
	folds.append(f)
	_apply_fold(f)

func _toggle_fold(f:Dictionary):
	f.open = !f.open
	_apply_fold(f)

func _apply_fold(f:Dictionary):
	var n = 0
	for r in f.group.get_node("H").get_children():
		if r is Control and !(r is Separator) and !r.has_meta("rr_desc"): n += 1
	f.btn.text = ("[-] hide" if f.open else "[+] show %d advanced settings" % n)
	f.group.visible = f.open

# search: everything opens while a search is typed, and folds back after
func searching(on:bool):
	for f in folds:
		f.group.visible = on or f.open
		f.btn.visible = !on

# ---------------------------------------------------------------- header: saved note, reset tab
func _header(card:Control):
	saved = style._label("", 15, Color(0.55, 1, 0.65) if !style.mono else Color(1, 1, 1, 0.8))
	saved.anchor_left = 1; saved.anchor_right = 1
	saved.margin_left = -420; saved.margin_right = -28; saved.margin_top = 84; saved.margin_bottom = 104
	saved.align = Label.ALIGN_RIGHT
	card.add_child(saved)
	tab_reset = Button.new()
	tab_reset.name = "RRTabReset"
	tab_reset.focus_mode = Control.FOCUS_ALL
	tab_reset.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tab_reset.add_font_override("font", style._font(15))
	tab_reset.anchor_left = 1; tab_reset.anchor_right = 1
	tab_reset.margin_left = -330; tab_reset.margin_right = -28; tab_reset.margin_top = 40; tab_reset.margin_bottom = 74
	_style_button(tab_reset)
	tab_reset.connect("pressed", self, "_ask_reset_tab")
	card.add_child(tab_reset)
	tabs.connect("tab_changed", self, "_tab_reset_text_i")

func _tab_changes() -> Array:
	var out = []
	var t = tabs.get_current_tab_control()
	for e in rows:
		if e.tab == t and e.reset and e.row.visible and !is_default(e): out.append(e)
	return out

func _tab_reset_text_i(_i):
	_tab_reset_text()

func _tab_reset_text():
	if !tab_reset: return
	var n = _tab_changes().size()
	tab_reset.text = ("Reset %s (%d)" % [tabs.get_tab_title(tabs.current_tab), n]) if n > 0 else "All defaults"
	tab_reset.disabled = n == 0

func _ask_reset_tab():
	var list = _tab_changes()
	if list.empty(): return
	var names = []
	for e in list:
		var l = e.row.get_node_or_null("Label") if e.row is HBoxContainer else e.row
		names.append(tr(l.text) if l else e.row.name)
	var cp = Globals.get("confirm_prompt")
	if !cp or !is_instance_valid(cp): # (no game dialog: the button asks itself - a second click within 4 s)
		if confirm_until > OS.get_ticks_msec():
			confirm_until = 0
			for e in list: reset(e)
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			_refresh_all()
		else:
			confirm_until = OS.get_ticks_msec() + 4000
			tab_reset.text = "Click again to reset %d" % list.size()
		return
	cp.open("Reset %d setting%s in %s to their defaults?\n%s" % [list.size(), "" if list.size() == 1 else "s",
		tabs.get_tab_title(tabs.current_tab), PoolStringArray(names.slice(0, 7)).join(", ") + (" ..." if names.size() > 8 else "")],
		"Reset settings", [{text = "Cancel"}, {text = "Reset"}])
	var sel = yield(cp, "option_selected")
	cp.close()
	if sel != 1: return
	for e in list: reset(e)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame") # (colour pickers apply a frame later)
	_refresh_all()

func _style_button(b:Button):
	var acc = Color(1, 1, 1) if style.mono else Look.accent()
	var n = StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.04)
	n.border_color = Color(1, 1, 1, 0.25)
	n.set_border_width_all(1)
	n.content_margin_left = 14; n.content_margin_right = 14; n.content_margin_top = 5; n.content_margin_bottom = 5
	if !style.mono: n.set_corner_radius_all(8)
	var h = n.duplicate()
	h.bg_color = Color(acc.r, acc.g, acc.b, 0.16)
	h.border_color = acc
	var p = h.duplicate()
	p.bg_color = Color(acc.r, acc.g, acc.b, 0.3)
	var f = h.duplicate()
	f.draw_center = false
	var d = n.duplicate()
	d.bg_color = Color(1, 1, 1, 0.0)
	d.border_color = Color(1, 1, 1, 0.08)
	b.add_stylebox_override("normal", n)
	b.add_stylebox_override("hover", h)
	b.add_stylebox_override("pressed", p)
	b.add_stylebox_override("focus", f)
	b.add_stylebox_override("disabled", d)
	b.add_color_override("font_color", Color(1, 1, 1, 0.85))
	b.add_color_override("font_color_hover", Color(1, 1, 1))
	b.add_color_override("font_color_pressed", Color(1, 1, 1))
	b.add_color_override("font_color_disabled", Color(1, 1, 1, 0.3))

# the page's own buttons (profiles, folders, reload): padded, same states as ours
func _top_buttons():
	var h = style.scroll.get_node_or_null("F/TopButtons/TopButtonsHBox")
	if !h: return
	h.add_constant_override("separation", 10)
	for b in h.get_children():
		if b is Button: _style_button(b)

# ---------------------------------------------------------------- watching + saving
func _changed():
	dirty_t = 0.6

func _process(delta):
	if !style.settings.is_visible_in_tree():
		if dirty_t >= 0: _save()
		return
	poll -= delta
	if poll <= 0:
		poll = 0.25
		var cur = tabs.get_current_tab_control()
		var any = false
		for e in rows:
			if e.tab != cur: continue
			var v = _value(e)
			if !_same(v, last.get(e.row)):
				last[e.row] = v
				any = true
				_refresh(e)
		if any:
			_changed()
			_tab_reset_text()
	if confirm_until > 0 and confirm_until < OS.get_ticks_msec():
		confirm_until = 0
		_tab_reset_text()
	if dirty_t >= 0:
		dirty_t -= delta
		if dirty_t < 0: _save()
	if saved_t > 0:
		saved_t -= delta
		saved.modulate.a = clamp(saved_t / 0.5, 0, 1)

func _save():
	dirty_t = -1.0
	if !Rhythia.has_method("save_settings"): return
	Rhythia.save_settings()
	var f = File.new()
	var ok = f.file_exists(Globals.p("user://settings.json"))
	saved.text = "changes saved" if ok else "could not save settings"
	saved_t = 2.5

func _exit_tree():
	if dirty_t >= 0: _save()

# ---------------------------------------------------------------- drawn parts
class Switch extends Control:
	var box:CheckBox
	var accent:Color
	var square:bool = false
	var k:float = -1.0
	func _toggled(_on):
		set_process(true)
	func _ready():
		k = 1.0 if box.pressed else 0.0
		set_process(false)
	func _process(delta):
		var goal = 1.0 if box.pressed else 0.0
		k = move_toward(k, goal, delta * 8.0)
		update()
		if k == goal: set_process(false)
	func _draw():
		if k < 0: k = 1.0 if box.pressed else 0.0
		var r = Rect2(Vector2(), rect_size)
		var a = 0.35 if box.disabled else 1.0
		var on = Color(accent.r, accent.g, accent.b, a)
		var track = Color(1, 1, 1, 0.12 * a).linear_interpolate(Color(on.r, on.g, on.b, 0.9 * a), k)
		var hover = box.get_draw_mode() == BaseButton.DRAW_HOVER or box.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED
		var sb = StyleBoxFlat.new()
		sb.bg_color = track
		sb.border_color = Color(1, 1, 1, (0.55 if hover else 0.3) * a).linear_interpolate(on, k)
		sb.set_border_width_all(1)
		if !square: sb.set_corner_radius_all(int(r.size.y / 2))
		draw_style_box(sb, r)
		var d = r.size.y - 6
		var x = lerp(3.0, r.size.x - 3.0 - d, k)
		var knob = Color(1, 1, 1, a) if k < 0.5 or !square else Color(0, 0, 0, a)
		if square: draw_rect(Rect2(x, 3, d, d), knob)
		else: draw_circle(Vector2(x + d / 2, r.size.y / 2), d / 2, knob)
		if box.has_focus(): # (keyboard: where Space / Enter will toggle)
			var ring = StyleBoxFlat.new()
			ring.draw_center = false
			ring.border_color = Color(accent.r, accent.g, accent.b, 0.9)
			ring.set_border_width_all(2)
			if !square: ring.set_corner_radius_all(int(r.size.y / 2) + 4)
			draw_style_box(ring, r.grow(4))

class ResetArrow extends Button:
	func _ready():
		flat = true
		text = ""
	func _draw():
		var c = rect_size / 2
		var col = Color(1, 1, 1, 0.95 if is_hovered() else 0.55)
		var rad = 7.0
		draw_arc(c, rad, -PI * 0.25, PI * 1.45, 18, col, 2.0, true)
		var tip = c + Vector2(cos(-PI * 0.25), sin(-PI * 0.25)) * rad
		draw_colored_polygon(PoolVector2Array([tip + Vector2(-4.5, -3.5), tip + Vector2(3.5, -4.0), tip + Vector2(1.0, 3.5)]), col)
		if has_focus(): draw_rect(Rect2(Vector2(1, 1), rect_size - Vector2(2, 2)), Color(1, 1, 1, 0.4), false, 1.0)
