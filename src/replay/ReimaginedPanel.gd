extends CanvasLayer
# Rhythia-reimagined "Customize" panel (title card "Customize", sidebar button, F1 in the menu):
# cursor trail (style / colour / opacity / length / size, live preview), HUD layout editor
# (drag / scroll / right-click the side panels, like Lunar Client's HUD editor), skin images
# (border, grid, trail dot, logo, sidebar icons), collections and interface toggles.
# Settings save instantly (Reimagined.gd); in-game things apply on the next map.

const R = preload("res://mods/replay/Reimagined.gd")
const UIAnim = preload("res://mods/replay/UIAnim.gd")
const OsuSfx = preload("res://mods/replay/OsuSfx.gd")
const OsuTrail = preload("res://mods/replay/OsuTrail.gd")
const ACCENT = Color("#8a6cff")
const W = 1060.0
const H = 680.0
const TABS = [["trail", "Cursor trail", "style, colour, opacity"], ["hud", "HUD layout", "move & scale panels"],
	["skin", "Skin", "border, icons, logo"], ["collections", "Collections", "map packs"],
	["interface", "Interface", "map list & clutter"], ["storage", "Storage", "user folder location"],
	["logs", "Logs", "for bug reports"]]
const UserDir = preload("res://mods/replay/UserDir.gd")

var menu:Node
var sfx:Node
var root:Control
var card:Panel
var content:Control
var tab_buttons:Array = []
var pages:Dictionary = {}
var cur:String = ""
var fonts:Dictionary = {}
var file_dialog:FileDialog
var pending_slot:String = ""
var closing:bool = false
var trail_widgets:Dictionary = {}

func _ready():
	layer = 30
	menu = get_parent()
	sfx = OsuSfx.inst(get_tree())
	root = Control.new()
	root.anchor_right = 1
	root.anchor_bottom = 1
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists("res://uitheme.tres"): root.theme = load("res://uitheme.tres")
	add_child(root)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	dim.connect("gui_input", self, "_dim_input")
	root.add_child(dim)

	card = Panel.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.98)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 24
	card.add_stylebox_override("panel", sb)
	card.anchor_left = 0.5; card.anchor_right = 0.5; card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.margin_left = -W / 2; card.margin_right = W / 2; card.margin_top = -H / 2; card.margin_bottom = H / 2
	root.add_child(card)

	var title = _label("RHYTHIA", 34, Color(1, 1, 1))
	title.rect_position = Vector2(28, 18)
	card.add_child(title)
	var sub = _label("reimagined", 34, ACCENT)
	sub.rect_position = Vector2(28 + _font(34).get_string_size("RHYTHIA ").x, 18)
	card.add_child(sub)
	var tag = _label("customize  -  v@@VERSION@@", 15, Color(1, 1, 1, 0.4))
	tag.rect_position = Vector2(30, 60)
	card.add_child(tag)
	var close = Button.new()
	close.text = "X"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.rect_position = Vector2(W - 58, 20)
	close.rect_size = Vector2(38, 34)
	close.connect("pressed", self, "close")
	card.add_child(close)
	var line = ColorRect.new()
	line.color = Color(1, 1, 1, 0.07)
	line.rect_position = Vector2(0, 92)
	line.rect_size = Vector2(W, 1)
	card.add_child(line)

	var tabs = VBoxContainer.new()
	tabs.rect_position = Vector2(16, 108)
	tabs.rect_size = Vector2(220, H - 130)
	tabs.add_constant_override("separation", 6)
	card.add_child(tabs)
	for t in TABS:
		var b = TabButton.new()
		b.title = t[1]
		b.sub = t[2]
		b.font_big = _font(19)
		b.font_small = _font(13)
		b.rect_min_size = Vector2(220, 54)
		b.connect("pressed", self, "show_tab", [t[0]])
		b.connect("mouse_entered", sfx, "play", ["click-short.ogg", -12.0])
		tabs.add_child(b)
		tab_buttons.append(b)
	var foot = _label("settings save instantly\nF1 opens this in the menu", 12, Color(1, 1, 1, 0.3))
	foot.rect_position = Vector2(22, H - 52)
	card.add_child(foot)

	content = Control.new()
	content.rect_position = Vector2(256, 108)
	content.rect_size = Vector2(W - 256 - 28, H - 108 - 24)
	card.add_child(content)

	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.mode = FileDialog.MODE_OPEN_FILE
	file_dialog.filters = PoolStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	file_dialog.window_title = "Choose an image"
	file_dialog.connect("file_selected", self, "_skin_picked")
	root.add_child(file_dialog)

	_build_trail()
	_build_hud()
	_build_skin()
	_build_collections()
	_build_interface()
	_build_storage()
	_build_logs()
	show_tab(Engine.get_meta("rr_tab") if Engine.has_meta("rr_tab") else "trail", false)
	# opening click = the game's own (menu2 open_customize plays Press)
	UIAnim.play(card, Vector2(0, 26), Vector2.ZERO, 0.0, 1.0, 0.3)

func _font(size:int):
	if fonts.has(size): return fonts[size]
	var base = root.get_font("font", "Label")
	var f = base
	if base is DynamicFont:
		f = base.duplicate()
		f.size = size
	fonts[size] = f
	return f

func _label(text:String, size:int, col:Color) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", _font(size))
	l.add_color_override("font_color", col)
	return l

func _dim_input(ev):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT: close()

func _input(ev):
	if ev is InputEventKey and ev.pressed and !ev.echo and ev.scancode in [KEY_ESCAPE, KEY_F1]:
		if file_dialog.visible: return
		get_tree().set_input_as_handled()
		close()

func close():
	if closing: return
	closing = true
	sfx.play("menuback.wav", -8.0)
	var t = UIAnim.play(card, Vector2.ZERO, Vector2(0, 18), 1.0, 0.0, 0.2)
	var t2 = UIAnim.play(root, Vector2.ZERO, Vector2.ZERO, 1.0, 0.0, 0.22)
	t2.connect("finished", self, "queue_free")

func show_tab(id:String, anim:bool = true):
	if id == cur: return
	cur = id
	Engine.set_meta("rr_tab", id)
	for i in TABS.size():
		tab_buttons[i].selected = TABS[i][0] == id
		tab_buttons[i].update()
	for k in pages:
		pages[k].visible = k == id
	if anim:
		sfx.play("click-short-confirm.ogg", -10.0)
		UIAnim.play(pages[id], Vector2(18, 0), Vector2.ZERO, 0.0, 1.0, 0.22)

# ------------------------------------------------------------------ building blocks
func _page(id:String) -> VBoxContainer:
	var v = VBoxContainer.new()
	v.rect_size = content.rect_size
	v.add_constant_override("separation", 10)
	v.visible = false
	content.add_child(v)
	pages[id] = v
	return v

func _heading(parent:Control, text:String, sub:String = ""):
	var l = _label(text, 22, Color(1, 1, 1))
	parent.add_child(l)
	if sub != "":
		var s = _label(sub, 14, Color(1, 1, 1, 0.45))
		s.autowrap = true
		s.rect_min_size.x = content.rect_size.x
		parent.add_child(s)

func _row(parent:Control, text:String, ctl:Control) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 14)
	var l = _label(text, 15, Color(1, 1, 1, 0.8))
	l.rect_min_size = Vector2(170, 0)
	l.valign = Label.VALIGN_CENTER
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	parent.add_child(h)
	return h

func _seg(options:Array, current:String, method:String) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 6)
	var g = ButtonGroup.new()
	for o in options:
		var b = Button.new()
		b.text = o[1]
		b.toggle_mode = true
		b.group = g
		b.pressed = o[0] == current
		b.focus_mode = Control.FOCUS_NONE
		b.rect_min_size = Vector2(110, 34)
		var on = StyleBoxFlat.new() # selected = accent fill
		on.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3)
		on.border_color = ACCENT
		on.set_border_width_all(2)
		b.add_stylebox_override("pressed", on)
		b.add_color_override("font_color_pressed", Color(1, 1, 1))
		b.connect("pressed", self, method, [o[0]])
		h.add_child(b)
	return h

func _slider(lo:float, hi:float, step:float, v:float, method:String, fmt:String) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 12)
	var s = HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	var l = _label(fmt % v, 15, Color(1, 1, 1, 0.7))
	l.rect_min_size = Vector2(64, 0)
	s.connect("value_changed", self, "_slider_moved", [l, fmt, method])
	h.add_child(s)
	h.add_child(l)
	return h

func _slider_moved(v:float, l:Label, fmt:String, method:String):
	l.text = fmt % v
	call(method, v)

func _check(parent:Control, text:String, on:bool, method:String) -> CheckBox:
	var c = CheckBox.new()
	c.text = text
	c.pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.connect("toggled", self, method)
	parent.add_child(c)
	return c

# ------------------------------------------------------------------ cursor trail
func _build_trail():
	var p = _page("trail")
	_heading(p, "Cursor trail", "The game's own trail (length / detail stay in Settings), an osu!-style trail of soft dots, or none.")
	var cf = R.cfg()
	_row(p, "Style", _seg([["game", "GAME"], ["osu", "OSU!"], ["off", "OFF"]], cf.trail_style, "_trail_style"))
	var ch = HBoxContainer.new()
	ch.add_constant_override("separation", 14)
	var same = CheckBox.new()
	same.text = "same as cursor"
	same.focus_mode = Control.FOCUS_NONE
	same.pressed = str(cf.trail_color) == ""
	same.connect("toggled", self, "_trail_same")
	ch.add_child(same)
	var cp = ColorPickerButton.new()
	cp.rect_min_size = Vector2(120, 32)
	cp.edit_alpha = false
	cp.color = R.trail_color(Color("#8ad8ff"))
	cp.disabled = same.pressed
	cp.focus_mode = Control.FOCUS_NONE
	cp.connect("color_changed", self, "_trail_color")
	ch.add_child(cp)
	trail_widgets.picker = cp
	_row(p, "Colour", ch)
	_row(p, "Opacity", _slider(0.0, 1.0, 0.05, float(cf.trail_alpha), "_trail_alpha", "%.2f"))
	trail_widgets.length = _row(p, "Length (osu!)", _slider(0.3, 3.0, 0.1, float(cf.trail_length), "_trail_length", "%.1fx"))
	trail_widgets.size = _row(p, "Size (osu!)", _slider(0.4, 2.0, 0.05, float(cf.trail_size), "_trail_size", "%.2fx"))
	var pv = TrailPreview.new()
	pv.rect_min_size = Vector2(0, 230)
	pv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(pv)
	_trail_refresh()

func _trail_refresh():
	var osu = R.val("trail_style") == "osu"
	trail_widgets.length.modulate.a = 1.0 if osu else 0.35
	trail_widgets.size.modulate.a = 1.0 if osu else 0.35

func _trail_style(v:String):
	R.set_val("trail_style", v)
	_trail_refresh()

func _trail_same(on:bool):
	trail_widgets.picker.disabled = on
	R.set_val("trail_color", "" if on else trail_widgets.picker.color.to_html(false))

func _trail_color(c:Color):
	R.set_val("trail_color", c.to_html(false))

func _trail_alpha(v:float): R.set_val("trail_alpha", v)
func _trail_length(v:float): R.set_val("trail_length", v)
func _trail_size(v:float): R.set_val("trail_size", v)

# ------------------------------------------------------------------ HUD layout
func _build_hud():
	var p = _page("hud")
	_heading(p, "HUD layout", "Drag a panel to move it, scroll to scale, right-click to hide / show, double-click to reset. Snaps to its default spot and the centre line (hold Shift to place freely). Applies on the next map.")
	var ed = HudEditor.new()
	ed.font = _font(14)
	ed.font_small = _font(12)
	ed.rect_min_size = Vector2(0, 400)
	ed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ed.connect("changed", self, "_hud_save")
	p.add_child(ed)
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 10)
	var reset = Button.new()
	reset.text = "Reset all"
	reset.focus_mode = Control.FOCUS_NONE
	reset.rect_min_size = Vector2(140, 36)
	reset.connect("pressed", self, "_hud_reset", [ed])
	h.add_child(reset)
	p.add_child(h)

func _hud_save():
	R.save()

func _hud_reset(ed:Control):
	R.cfg().hud = {}
	R.save()
	ed.sel = -1
	ed.update()
	sfx.play("menuback.wav", -10.0)

# ------------------------------------------------------------------ skin
var skin_list:VBoxContainer

func _build_skin():
	var p = _page("skin")
	_heading(p, "Skin", "Swap images without touching game files - like the custom cursor. Pick an image and it is copied into the skin folder; Reset brings the default back. Game images apply on the next map.")
	var sc = ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.scroll_horizontal_enabled = false
	p.add_child(sc)
	skin_list = VBoxContainer.new()
	skin_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skin_list.add_constant_override("separation", 8)
	sc.add_child(skin_list)
	var h = HBoxContainer.new()
	var open = Button.new()
	open.text = "Open skin folder"
	open.focus_mode = Control.FOCUS_NONE
	open.rect_min_size = Vector2(190, 36)
	open.connect("pressed", self, "_skin_open")
	h.add_child(open)
	p.add_child(h)
	_skin_rows()

func _skin_slots() -> Array:
	var out = []
	for s in R.SKIN_SLOTS: out.append([s[0], s[1], s[2], _skin_default(s[0])])
	var l = menu.get_node_or_null("Sidebar/L")
	if l:
		for b in l.get_children():
			var tex = b.get_node_or_null("Tex")
			if !(b is Button) or !b.visible or !(tex is TextureRect): continue
			var d = tex.get_meta("rr_default") if tex.has_meta("rr_default") else tex.texture
			var lbl = b.get_node_or_null("Label")
			out.append(["icon_" + b.name.to_lower(), "Sidebar: " + (lbl.text if lbl else b.name), "sidebar icon", d])
	return out

func _skin_default(slot:String):
	match slot:
		"border": return load("res://assets/images/grid_outer.png")
		"grid": return load("res://assets/images/grid_inner.png")
		"trail": return OsuTrail.dot_texture()
		"logo": return load("res://assets/images/branding/icon.png")
	return null

func _skin_rows():
	for c in skin_list.get_children(): c.queue_free()
	for s in _skin_slots():
		var custom = R.skin_tex(s[0])
		var row = PanelContainer.new()
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.035)
		sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 6; sb.content_margin_bottom = 6
		row.add_stylebox_override("panel", sb)
		var h = HBoxContainer.new()
		h.add_constant_override("separation", 14)
		row.add_child(h)
		var thumb = TextureRect.new()
		thumb.texture = custom if custom else s[3]
		thumb.expand = true
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.rect_min_size = Vector2(52, 52)
		h.add_child(thumb)
		var v = VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGN_CENTER
		v.add_child(_label(s[1], 16, Color(1, 1, 1)))
		v.add_child(_label(("custom  -  " if custom else "default  -  ") + s[2], 13, ACCENT if custom else Color(1, 1, 1, 0.4)))
		h.add_child(v)
		var pick = Button.new()
		pick.text = "Choose..."
		pick.focus_mode = Control.FOCUS_NONE
		pick.rect_min_size = Vector2(120, 36)
		pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pick.connect("pressed", self, "_skin_choose", [s[0]])
		h.add_child(pick)
		var rs = Button.new()
		rs.text = "Reset"
		rs.disabled = custom == null
		rs.focus_mode = Control.FOCUS_NONE
		rs.rect_min_size = Vector2(90, 36)
		rs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rs.connect("pressed", self, "_skin_reset", [s[0]])
		h.add_child(rs)
		skin_list.add_child(row)

func _skin_choose(slot:String):
	pending_slot = slot
	file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	file_dialog.popup_centered(Vector2(900, 560))

func _skin_picked(path:String):
	if pending_slot == "": return
	if R.skin_set(pending_slot, path): sfx.play("click-short-confirm.ogg", -8.0)
	pending_slot = ""
	_skin_applied()

func _skin_reset(slot:String):
	R.skin_clear(slot)
	sfx.play("menuback.wav", -10.0)
	_skin_applied()

func _skin_applied():
	R.apply_sidebar_icons(menu)
	var t = menu.get_node_or_null("TitleMenu")
	if t and t.has_method("apply_skin"): t.apply_skin()
	_skin_rows()

func _skin_open():
	Directory.new().make_dir_recursive(R.skin_dir())
	OS.shell_open(ProjectSettings.globalize_path(R.skin_dir()))

# ------------------------------------------------------------------ collections
var coll_list:VBoxContainer
var coll_name:LineEdit

func _build_collections():
	var p = _page("collections")
	_heading(p, "Collections", "Your own map packs. Add the selected map with the ... button on its page (Add to collection), then pick a collection under Filters in the map list.")
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 10)
	coll_name = LineEdit.new()
	coll_name.placeholder_text = "new collection name"
	coll_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coll_name.connect("text_entered", self, "_coll_create")
	h.add_child(coll_name)
	var b = Button.new()
	b.text = "Create"
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(120, 36)
	b.connect("pressed", self, "_coll_create", [""])
	h.add_child(b)
	p.add_child(h)
	var sc = ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.scroll_horizontal_enabled = false
	p.add_child(sc)
	coll_list = VBoxContainer.new()
	coll_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coll_list.add_constant_override("separation", 6)
	sc.add_child(coll_list)
	_coll_rows()

func _coll_rows():
	for c in coll_list.get_children(): c.queue_free()
	var cs = R.collections()
	var names = cs.keys()
	names.sort()
	if names.empty():
		coll_list.add_child(_label("No collections yet.", 15, Color(1, 1, 1, 0.4)))
	for n in names:
		var row = PanelContainer.new()
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.035)
		sb.border_color = ACCENT if R.val("collection") == n else Color(0, 0, 0, 0)
		sb.border_width_left = 3
		sb.content_margin_left = 12; sb.content_margin_right = 8; sb.content_margin_top = 4; sb.content_margin_bottom = 4
		row.add_stylebox_override("panel", sb)
		var h = HBoxContainer.new()
		h.add_constant_override("separation", 8)
		row.add_child(h)
		var ne = LineEdit.new()
		ne.text = n
		ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ne.add_stylebox_override("normal", StyleBoxEmpty.new())
		ne.hint_tooltip = "click to rename, Enter to save"
		ne.connect("text_entered", self, "_coll_rename", [n])
		h.add_child(ne)
		var cnt = _label("%d maps" % cs[n].size(), 14, Color(1, 1, 1, 0.45))
		cnt.rect_min_size = Vector2(90, 0)
		cnt.valign = Label.VALIGN_CENTER
		h.add_child(cnt)
		for a in [["Show", "_coll_show"], ["Delete", "_coll_delete"]]:
			var b = Button.new()
			b.text = a[0]
			b.focus_mode = Control.FOCUS_NONE
			b.rect_min_size = Vector2(90, 34)
			b.connect("pressed", self, a[1], [n, b])
			h.add_child(b)
		coll_list.add_child(row)

func _coll_create(_t = ""):
	if R.coll_create(coll_name.text):
		coll_name.text = ""
		sfx.play("click-short-confirm.ogg", -8.0)
		_coll_rows()

func _coll_rename(new:String, old:String):
	if R.coll_rename(old, new): _coll_rows()

func _coll_show(n:String, _b):
	R.set_val("collection", n)
	get_tree().call_group("rr_collections", "_rr_collections_changed")
	var t = menu.get_node_or_null("TitleMenu")
	if t and t.visible and t.has_method("_close"): t._close("")
	else:
		var sb = menu.get_node_or_null("Sidebar")
		if sb and sb.has_method("press"): sb.press(0, true)
	close()

func _coll_delete(n:String, b:Button):
	if b.text != "Sure?":
		b.text = "Sure?"
		return
	R.coll_delete(n)
	_coll_rows()

# ------------------------------------------------------------------ interface
func _build_interface():
	var p = _page("interface")
	var cf = R.cfg()
	_heading(p, "Interface", "Title screen background and less clutter on the map page and in game.")
	_check(p, "Hide \"Default hitboxes, default hitwindow\" on the map page", cf.hide_hitbox_text, "_if_hitbox")
	_check(p, "Hide the HIT WINDOW / HITBOX panel and HW / HB text in game", cf.hide_config_hud, "_if_config")
	_row(p, "Title background", _seg([["rain", "RAIN"], ["snow", "SNOW"], ["waves", "WAVEY"]], cf.title_bg, "_if_bg"))
	var gap = Control.new()
	gap.rect_min_size = Vector2(0, 12)
	p.add_child(gap)
	_check(p, "Glitch + chromatic aberration (10+ star maps, title logo)", R.val("glitch_fx"), "_if_glitch")
	_check(p, "Lighter effects for low-end PCs (auto when the game slows down)", R.val("lite_fx"), "_if_lite")
	_heading(p, "Map list", "Also under Filters next to the map list.")
	_row(p, "Sort by", _seg([["stars", "STARS"], ["name", "NAME"], ["mapper", "MAPPER"]], cf.sort, "_if_sort"))

func _if_hitbox(on:bool):
	R.set_val("hide_hitbox_text", on)
	get_tree().call_group("rr_mappage", "_rr_apply")

func _if_config(on:bool): R.set_val("hide_config_hud", on)

func _if_glitch(on:bool): R.set_val("glitch_fx", on)

func _if_lite(on:bool):
	R.set_val("lite_fx", on)
	if !on and Engine.has_meta("rr_auto_lite"): Engine.remove_meta("rr_auto_lite")

func _if_bg(v:String):
	R.set_val("title_bg", v)
	var t = menu.get_node_or_null("TitleMenu")
	if t and t.has_method("apply_bg"): t.apply_bg()

func _if_sort(v:String):
	R.set_val("sort", v)
	get_tree().call_group("rr_collections", "_rr_collections_changed")

# ------------------------------------------------------------------ storage
var dir_dialog:FileDialog
var move_confirm:ConfirmationDialog
var storage_msg:Label
var move_dest:String = ""

# Logs (mainly for phones, where the log file can't be reached): the end of the game log, with
# Copy (clipboard) to paste it in a bug report. File logging is switched on for every platform by
# the build (ssp_mod.py), so Android writes user://logs/godot.log too.
const LOG_FILE = "user://logs/godot.log"
const LOG_LINES = 400
var NL = char(10)
var log_view:TextEdit
var log_msg:Label

func _build_logs():
	var p = _page("logs")
	_heading(p, "Game log", "What the game printed this session (errors included). Copy it and paste it when you report a bug.")
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 8)
	for b in [["Copy log", "_logs_copy"], ["Refresh", "_logs_refresh"]]:
		var btn = Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.rect_min_size = Vector2(160, 36)
		btn.connect("pressed", self, b[1])
		h.add_child(btn)
	log_msg = _label("", 14, Color(0.6, 1, 0.6))
	h.add_child(log_msg)
	p.add_child(h)
	log_view = TextEdit.new()
	log_view.readonly = true
	log_view.wrap_enabled = true
	log_view.rect_min_size = Vector2(0, 380)
	log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(log_view)
	_logs_refresh()

func _log_text() -> String:
	var f = File.new()
	if f.open(Globals.p(LOG_FILE), File.READ) != OK: return "(no log file - restart the game once after updating)"
	var lines = f.get_as_text().split(NL)
	f.close()
	var from = max(0, lines.size() - LOG_LINES)
	var out = PoolStringArray()
	for i in range(from, lines.size()): out.append(lines[i])
	return "Rhythia-reimagined v@@VERSION@@ - %s %s" % [OS.get_name(), OS.get_model_name()] + NL + out.join(NL)

func _logs_refresh():
	log_view.text = _log_text()
	log_view.cursor_set_line(log_view.get_line_count())
	log_msg.text = ""

func _logs_copy():
	OS.clipboard = _log_text()
	log_msg.text = "Copied"

func _build_storage():
	var p = _page("storage")
	_heading(p, "User folder", "Your maps, replays, scores, skins and settings. Move it to another drive to free space: the game closes, a window copies everything, checks the copy, links the old place to the new folder (so everything keeps working) and starts the game again. Nothing is deleted until the copy is checked.")
	if !UserDir.supported():
		p.add_child(_label("Only available on Windows.", 15, Color(1, 1, 1, 0.5)))
		return
	var loc = _label(UserDir.location(), 15, Color(1, 1, 1))
	loc.autowrap = true
	loc.rect_min_size.x = content.rect_size.x - 190
	_row(p, "Location" + ("  (moved)" if UserDir.moved() else ""), loc)
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 8)
	for b in [["Open folder", "_storage_open", false], ["Move to...", "_storage_pick", false], ["Move back to default", "_storage_back", !UserDir.moved()]]:
		var btn = Button.new()
		btn.text = b[0]
		btn.disabled = b[2]
		btn.focus_mode = Control.FOCUS_NONE
		btn.rect_min_size = Vector2(190, 36)
		btn.connect("pressed", self, b[1])
		h.add_child(btn)
	p.add_child(h)
	storage_msg = _label("", 14, Color(1, 0.55, 0.55))
	storage_msg.autowrap = true
	storage_msg.rect_min_size.x = content.rect_size.x
	p.add_child(storage_msg)
	var note = _label("Tip: big library? Pick a folder on a drive with plenty of space, like D:\\Games. A folder named SoundSpacePlus is made inside the one you pick.", 13, Color(1, 1, 1, 0.35))
	note.autowrap = true
	note.rect_min_size.x = content.rect_size.x
	p.add_child(note)
	dir_dialog = FileDialog.new()
	dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	dir_dialog.mode = FileDialog.MODE_OPEN_DIR
	dir_dialog.window_title = "Pick where your user folder goes"
	dir_dialog.connect("dir_selected", self, "_storage_picked")
	root.add_child(dir_dialog)
	move_confirm = ConfirmationDialog.new()
	move_confirm.window_title = "Move user folder"
	move_confirm.get_ok().text = "Close game and move"
	move_confirm.connect("confirmed", self, "_storage_go")
	root.add_child(move_confirm)

func _storage_open():
	OS.shell_open(UserDir.location())

func _storage_pick():
	storage_msg.text = ""
	dir_dialog.current_dir = "C:/"
	dir_dialog.popup_centered(Vector2(900, 560))

func _storage_picked(dir:String):
	var dest = UserDir.target_for(dir)
	var why = UserDir.check(dest)
	if why != "":
		storage_msg.text = why
		sfx.play("menuback.wav", -10.0)
		return
	move_dest = dest
	move_confirm.dialog_text = "Move your user folder\n  from  %s\n  to      %s ?\n\nThe game closes now and starts again when the move is done.\nBig libraries can take a few minutes." % [UserDir.location(), dest]
	move_confirm.popup_centered()

func _storage_back():
	storage_msg.text = ""
	move_dest = ""
	move_confirm.dialog_text = "Move your user folder back\n  from  %s\n  to      %s ?\n\nThe game closes now and starts again when the move is done." % [UserDir.location(), UserDir.default_path()]
	move_confirm.popup_centered()

func _storage_go():
	var err = UserDir.start(get_tree(), move_dest)
	if err != "": storage_msg.text = err

# ------------------------------------------------------------------ widgets
class TabButton extends Control:
	signal pressed
	var title:String = ""
	var sub:String = ""
	var font_big:Font
	var font_small:Font
	var selected:bool = false setget _set_selected
	var hover:float = 0.0
	var sel:float = 0.0
	var inside:bool = false

	func _ready():
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		connect("mouse_entered", self, "_in", [true])
		connect("mouse_exited", self, "_in", [false])

	func _in(v:bool):
		inside = v
		set_process(true)

	func _set_selected(v:bool):
		selected = v
		set_process(true)

	func _gui_input(ev):
		# on release (like a Button): opening a full-screen panel mid-click crashed the game
		if ev is InputEventMouseButton and !ev.pressed and ev.button_index == BUTTON_LEFT and Rect2(Vector2.ZERO, rect_size).has_point(ev.position):
			accept_event()
			emit_signal("pressed")

	func _process(delta):
		var k = 1.0 - exp(-delta * 14.0)
		var th = 1.0 if inside else 0.0
		var ts = 1.0 if selected else 0.0
		hover = lerp(hover, th, k)
		sel = lerp(sel, ts, k)
		if abs(hover - th) < 0.003 and abs(sel - ts) < 0.003: # settled (compare to the target: a 0-delta frame used to stop it half way)
			hover = th
			sel = ts
			set_process(false)
		update()

	func _draw():
		var w = rect_size.x
		var h = rect_size.y
		var acc = Color("#8a6cff")
		draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.03 * hover + 0.05 * sel))
		draw_rect(Rect2(0, 0, 3 + 2 * sel, h), Color(acc.r, acc.g, acc.b, sel))
		var x = 18 + 4 * hover
		if font_big: draw_string(font_big, Vector2(x, h * 0.5 + 1), title, Color(1, 1, 1, 0.6 + 0.4 * max(sel, hover)))
		if font_small: draw_string(font_small, Vector2(x, h * 0.5 + 19), sub, Color(1, 1, 1, 0.3 + 0.15 * sel))

# live trail preview: a cursor running a figure eight over a mini grid
class TrailPreview extends Control:
	const R = preload("res://mods/replay/Reimagined.gd")
	var t:float = 0.0
	var dots:Array = []
	var ghosts:Array = []
	var last = null
	var tex:Texture
	var ghost_t:float = 0.0

	func _ready():
		rect_clip_content = true
		mouse_filter = MOUSE_FILTER_IGNORE

	func _cursor_col() -> Color:
		var c = Rhythia.get("cursor_color")
		return c if typeof(c) == TYPE_COLOR else Color("#8ad8ff")

	func _process(delta):
		t += delta
		var cf = R.cfg()
		var c = rect_size / 2
		var r = min(rect_size.x, rect_size.y) * 0.36
		var p = c + Vector2(sin(t * 1.9), sin(t * 3.8)) * r
		var life = 0.18 * float(cf.trail_length)
		var spacing = 4.0 * float(cf.trail_size)
		if last == null: last = p
		var d = p.distance_to(last)
		if d >= spacing:
			var n = int(d / spacing)
			var dir = (p - last) / d
			for i in range(1, n + 1): dots.append([last + dir * spacing * i, t])
			last = last + dir * spacing * n
		while dots.size() > 0 and t - dots[0][1] > life: dots.pop_front()
		ghost_t += delta
		if ghost_t > 0.016:
			ghost_t = 0.0
			ghosts.append([p, t])
		while ghosts.size() > 0 and t - ghosts[0][1] > 0.12: ghosts.pop_front()
		update()

	func _draw():
		var cf = R.cfg()
		var c = rect_size / 2
		var s = min(rect_size.x, rect_size.y) * 0.8
		var g = Rect2(c - Vector2(s, s) / 2, Vector2(s, s))
		draw_rect(Rect2(Vector2.ZERO, rect_size), Color(1, 1, 1, 0.025))
		draw_rect(g, Color(1, 1, 1, 0.35), false, 1.5)
		for k in [1, 2]:
			draw_line(Vector2(g.position.x + s * k / 3, g.position.y), Vector2(g.position.x + s * k / 3, g.end.y), Color(1, 1, 1, 0.07))
			draw_line(Vector2(g.position.x, g.position.y + s * k / 3), Vector2(g.end.x, g.position.y + s * k / 3), Color(1, 1, 1, 0.07))
		var cc = _cursor_col()
		var tc = R.trail_color(cc)
		var a = float(cf.trail_alpha)
		var cr = 13.0
		match cf.trail_style:
			"osu":
				if !tex: tex = load("res://mods/replay/OsuTrail.gd").dot_texture()
				var life = 0.18 * float(cf.trail_length)
				var rr0 = cr * 0.8 * float(cf.trail_size)
				for q in dots:
					var k = clamp(1.0 - (t - q[1]) / life, 0.0, 1.0)
					var rr = rr0 * (0.45 + 0.55 * k)
					draw_texture_rect(tex, Rect2(q[0] - Vector2(rr, rr), Vector2(rr, rr) * 2), false, Color(tc.r, tc.g, tc.b, k * k * a * 0.55))
			"game":
				for q in ghosts:
					var k = clamp(1.0 - (t - q[1]) / 0.12, 0.0, 1.0)
					draw_circle(q[0], cr * k, Color(tc.r, tc.g, tc.b, k * 0.6 * a))
		if last != null:
			var p = c + Vector2(sin(t * 1.9), sin(t * 3.8)) * min(rect_size.x, rect_size.y) * 0.36
			draw_circle(p, cr, cc)

# schematic HUD editor: the 3x3 grid and the side panels at their in-game spots (world units)
class HudEditor extends Control:
	signal changed
	const R = preload("res://mods/replay/Reimagined.gd")
	var font:Font
	var font_small:Font
	var sel:int = -1
	var hover:int = -1
	var dragging:bool = false
	var drag_from:Vector2
	var start_off:Vector2

	func _ready():
		mouse_filter = MOUSE_FILTER_STOP
		rect_clip_content = true

	func unit() -> float:
		return min(rect_size.x / 8.6, rect_size.y / 5.6)

	func rect_of(i:int) -> Rect2:
		var it = R.HUD_ITEMS[i]
		var e = R.hud_entry(it[0])
		var u = unit()
		var c = rect_size / 2 + Vector2(it[2].x + float(e[0]), -(it[2].y + float(e[1]))) * u
		var sz = it[3] * float(e[2]) * u
		return Rect2(c - sz / 2, sz)

	func _pick(p:Vector2) -> int:
		for i in range(R.HUD_ITEMS.size() - 1, -1, -1):
			if rect_of(i).grow(4).has_point(p): return i
		return -1

	func _put(i:int, e:Array):
		R.cfg().hud[R.HUD_ITEMS[i][0]] = e

	func _gui_input(ev):
		if ev is InputEventMouseMotion:
			if dragging and sel >= 0:
				var d = (ev.position - drag_from) / unit()
				var e = R.hud_entry(R.HUD_ITEMS[sel][0]).duplicate()
				var nx = start_off.x + d.x
				var ny = start_off.y - d.y
				if !Input.is_key_pressed(KEY_SHIFT):
					var home = R.HUD_ITEMS[sel][2]
					if abs(nx) < 0.08: nx = 0.0                  # default spot
					if abs(ny) < 0.08: ny = 0.0
					if abs(home.x + nx) < 0.08: nx = -home.x     # centre lines
					if abs(home.y + ny) < 0.08: ny = -home.y
				e[0] = stepify(nx, 0.001)
				e[1] = stepify(ny, 0.001)
				_put(sel, e)
				update()
			else:
				var h = _pick(ev.position)
				if h != hover:
					hover = h
					mouse_default_cursor_shape = CURSOR_MOVE if h >= 0 else CURSOR_ARROW
					update()
		elif ev is InputEventMouseButton:
			var i = _pick(ev.position)
			if ev.button_index == BUTTON_LEFT:
				if ev.pressed:
					sel = i
					if i >= 0 and ev.doubleclick:
						_put(i, [0.0, 0.0, 1.0, true])
						emit_signal("changed")
					elif i >= 0:
						var e = R.hud_entry(R.HUD_ITEMS[i][0])
						dragging = true
						drag_from = ev.position
						start_off = Vector2(float(e[0]), float(e[1]))
				elif dragging:
					dragging = false
					emit_signal("changed")
			elif ev.pressed and i >= 0:
				var e = R.hud_entry(R.HUD_ITEMS[i][0]).duplicate()
				if ev.button_index == BUTTON_RIGHT: e[3] = !e[3]
				elif ev.button_index == BUTTON_WHEEL_UP: e[2] = clamp(float(e[2]) + 0.05, 0.4, 2.0)
				elif ev.button_index == BUTTON_WHEEL_DOWN: e[2] = clamp(float(e[2]) - 0.05, 0.4, 2.0)
				else: return
				sel = i
				_put(i, e)
				emit_signal("changed")
			update()
			accept_event()

	func _draw():
		var u = unit()
		var c = rect_size / 2
		var acc = Color("#8a6cff")
		draw_rect(Rect2(Vector2.ZERO, rect_size), Color(1, 1, 1, 0.025))
		if dragging:
			draw_line(Vector2(c.x, 0), Vector2(c.x, rect_size.y), Color(acc.r, acc.g, acc.b, 0.35))
			draw_line(Vector2(0, c.y), Vector2(rect_size.x, c.y), Color(acc.r, acc.g, acc.b, 0.35))
		var g = Rect2(c - Vector2(1.5, 1.5) * u, Vector2(3, 3) * u)
		draw_rect(g, Color(1, 1, 1, 0.03))
		for k in [1, 2]:
			draw_line(Vector2(g.position.x + k * u, g.position.y), Vector2(g.position.x + k * u, g.end.y), Color(1, 1, 1, 0.08))
			draw_line(Vector2(g.position.x, g.position.y + k * u), Vector2(g.end.x, g.position.y + k * u), Color(1, 1, 1, 0.08))
		draw_rect(g, Color(1, 1, 1, 0.5), false, 2.0)
		if font_small:
			var gt = "PLAY AREA"
			draw_string(font_small, c - font_small.get_string_size(gt) / 2 + Vector2(0, 4), gt, Color(1, 1, 1, 0.18))
		for i in R.HUD_ITEMS.size():
			var it = R.HUD_ITEMS[i]
			var e = R.hud_entry(it[0])
			var r = rect_of(i)
			var on = bool(e[3])
			var hot = i == sel or i == hover
			var fill = Color(acc.r, acc.g, acc.b, 0.2 if i == sel else (0.12 if hot else 0.07))
			if !on: fill = Color(1, 1, 1, 0.02)
			draw_rect(r, fill)
			var bc = acc if i == sel else Color(1, 1, 1, 0.45 if hot else 0.22)
			if !on: bc = Color(1, 1, 1, 0.12)
			draw_rect(r, bc, false, 2.0 if i == sel else 1.0)
			if !font: continue
			var lines = it[1].split(" / ")
			lines.append("hidden" if !on else "%d%%" % round(float(e[2]) * 100))
			var lh = font.get_height() + 2
			var y0 = r.position.y + r.size.y / 2 - lh * lines.size() / 2.0 + font.get_ascent()
			for j in lines.size():
				var f = font if j < lines.size() - 1 else font_small
				var tc = Color(1, 1, 1, (0.85 if on else 0.3) if j < lines.size() - 1 else 0.4)
				var tw = f.get_string_size(lines[j]).x
				draw_string(f, Vector2(r.position.x + (r.size.x - tw) / 2, y0 + j * lh), lines[j], tc)
