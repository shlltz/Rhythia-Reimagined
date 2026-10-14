extends CanvasLayer
# Colorset maker: a "+" cell after the last colorset in Settings > Notes > Note Colors opens this.
# Builds / edits a colorset file (user://colorsets/<name>.txt: one #rrggbb per line, "m" = mirror),
# registers it in the game right away and can select it ("Save & Use").

const GRID = "S/F/TabContainer/Notes/Notes/Group/H/ColorSet2/ColorSet"
const MAX_COLORS = 32

var colors:Array = [Color("#ff64b1")]
var sel:int = 0
var mirror:bool = false
var loaded_id:String = ""     # "" = a new colorset; else the custom colorset being edited
var loaded_path:String = ""
var load_ids:Array = []

var menu:Node
var name_edit:LineEdit
var load_btn:OptionButton
var mirror_chk:CheckBox
var swatches:GridContainer
var picker:ColorPicker
var status:Label
var panel:Panel
var sync_lock:bool = false

# ---------------------------------------------------------------- the + cell on the Note Colors page
# (called deferred from SettingsStyle: the grid's own cells are added a frame after its _ready)
static func install(settings:Node, menu_node:Node):
	var grid = settings.get_node_or_null(GRID)
	if !grid or grid.has_node("RRPlus") or !grid.has_node("Color"):
		return
	var tpl = grid.get_node("Color")
	var cell = tpl.duplicate()
	cell.name = "RRPlus"
	cell.visible = true
	var cols = cell.get_node("Colors")
	for c in cols.get_children(): c.queue_free()
	cell.get_node("Mirror").visible = false
	cell.get_node("Name").text = "New colorset"
	var plus = Label.new()
	plus.text = "+"
	plus.anchor_right = 1
	plus.anchor_bottom = 1
	plus.align = Label.ALIGN_CENTER
	plus.valign = Label.VALIGN_CENTER
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f = grid.get_node("Color/Name").get_font("font")
	if f is DynamicFont:
		var big = f.duplicate()
		big.size = 54
		plus.add_font_override("font", big)
	plus.modulate = Color(1, 1, 1, 0.85)
	cell.add_child(plus)
	var s = cell.get_node("Select")
	s.hint_tooltip = "Make a colorset"
	s.disabled = false
	cell.self_modulate = Color(0.5, 0.5, 0.5)
	for c in s.get_signal_connection_list("pressed"): s.disconnect("pressed", c.target, c.method)
	var ss = menu_node.get_node_or_null("SettingsStyle")
	if !ss: return
	s.connect("pressed", ss, "_open_colorset_maker", [grid])
	grid.add_child(cell)

static func open(menu_node:Node, grid:Node = null, edit_id:String = ""):
	var root = menu_node.get_tree().root
	if root.has_node("ColorsetMaker"): return
	var m = load("res://mods/replay/ColorsetMaker.gd").new()
	m.name = "ColorsetMaker"
	m.menu = menu_node
	m.set_meta("grid", grid)
	root.add_child(m)

# rebuild the colorset grid so a new / changed colorset shows up (the game builds it once)
static func refresh_grid(grid:Node):
	if !is_instance_valid(grid): return
	if Rhythia.is_connected("selected_colorset_changed", grid, "upd"): Rhythia.disconnect("selected_colorset_changed", grid, "upd")
	if grid.is_connected("resized", grid, "col"): grid.disconnect("resized", grid, "col")
	for c in grid.get_children():
		if c.name != "Color": c.queue_free()
	grid.btns = {}
	grid._ready()

# ---------------------------------------------------------------- the dialog
func _ready():
	layer = 130
	pause_mode = PAUSE_MODE_PROCESS
	var vp = get_viewport().get_visible_rect().size
	var root = Control.new()
	root.anchor_right = 1
	root.anchor_bottom = 1
	var theme_path = "res://uitheme.tres"
	if ResourceLoader.exists(theme_path): root.theme = load(theme_path)
	add_child(root)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	root.add_child(dim)
	panel = Panel.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.055, 0.065, 0.99)
	sb.border_color = Color(1, 1, 1, 0.16)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	panel.add_stylebox_override("panel", sb)
	var w = clamp(vp.x * 0.94, 300.0, 560.0)
	var h = clamp(vp.y * 0.94, 300.0, 900.0)
	panel.rect_min_size = Vector2(w, h)
	panel.rect_size = Vector2(w, h)
	panel.rect_position = (vp - Vector2(w, h)) / 2
	root.add_child(panel)

	var title = Label.new()
	title.text = "Colorset Maker"
	title.align = Label.ALIGN_CENTER
	title.rect_position = Vector2(0, 14)
	title.rect_size = Vector2(w, 30)
	title.add_color_override("font_color", Color(1, 1, 1))
	panel.add_child(title)

	var foot = HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGN_CENTER
	foot.add_constant_override("separation", 10)
	foot.rect_position = Vector2(12, h - 62)
	foot.rect_size = Vector2(w - 24, 48)
	panel.add_child(foot)
	foot.add_child(_btn("Save", "_save", [false], 120))
	foot.add_child(_btn("Save & Use", "_save", [true], 150))
	foot.add_child(_btn("Close", "_close", [], 110))

	status = Label.new()
	status.align = Label.ALIGN_CENTER
	status.autowrap = true
	status.rect_position = Vector2(12, h - 96)
	status.rect_size = Vector2(w - 24, 30)
	status.modulate = Color(1, 1, 1, 0.65)
	panel.add_child(status)

	var scroll = ScrollContainer.new()
	scroll.rect_position = Vector2(12, 52)
	scroll.rect_size = Vector2(w - 24, h - 52 - 104)
	scroll.scroll_horizontal_enabled = false
	panel.add_child(scroll)
	var v = VBoxContainer.new()
	v.rect_min_size.x = w - 24 - 14
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_constant_override("separation", 10)
	scroll.add_child(v)

	var lr = HBoxContainer.new()
	lr.add_constant_override("separation", 10)
	v.add_child(lr)
	lr.add_child(_lbl("Load", 56))
	load_btn = OptionButton.new()
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.rect_min_size.y = 40
	lr.add_child(load_btn)
	load_btn.connect("item_selected", self, "_load_pick")

	var nr = HBoxContainer.new()
	nr.add_constant_override("separation", 10)
	v.add_child(nr)
	nr.add_child(_lbl("Name", 56))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Colorset name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.rect_min_size.y = 40
	name_edit.max_length = 40
	nr.add_child(name_edit)

	mirror_chk = CheckBox.new()
	mirror_chk.text = "Mirror (colors go back the other way after the last)"
	mirror_chk.connect("toggled", self, "_mirror_toggled")
	v.add_child(mirror_chk)

	var cl = _lbl("Colors (notes cycle through them in this order)", 0)
	cl.autowrap = true
	v.add_child(cl)
	swatches = GridContainer.new()
	swatches.columns = int(clamp(floor((w - 24 - 14) / 52.0), 4, 10))
	swatches.add_constant_override("hseparation", 6)
	swatches.add_constant_override("vseparation", 6)
	v.add_child(swatches)

	var br = HBoxContainer.new()
	br.add_constant_override("separation", 8)
	v.add_child(br)
	br.add_child(_btn("Add Color", "_add", [], 0))
	br.add_child(_btn("Remove", "_remove", [], 0))
	br.add_child(_btn("<", "_move", [-1], 48))
	br.add_child(_btn(">", "_move", [1], 48))

	picker = ColorPicker.new()
	picker.edit_alpha = false
	picker.presets_enabled = false
	picker.presets_visible = false
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.connect("color_changed", self, "_picked")
	v.add_child(picker)

	_fill_load_list()
	_build_swatches()
	picker.color = colors[sel]
	_msg("")

func _lbl(t:String, minw:float) -> Label:
	var l = Label.new()
	l.text = t
	if minw > 0: l.rect_min_size.x = minw
	l.valign = Label.VALIGN_CENTER
	return l

func _btn(t:String, f:String, args:Array, minw:float) -> Button:
	var b = Button.new()
	b.text = t
	b.rect_min_size = Vector2(minw, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.connect("pressed", self, f, args)
	return b

func _msg(t:String, bad:bool = false):
	status.text = t
	status.modulate = Color(1, 0.45, 0.5) if bad else Color(1, 1, 1, 0.65)

# ---------------------------------------------------------------- load list
func _fill_load_list():
	load_btn.clear()
	load_ids = [""]
	load_btn.add_item("New colorset")
	var customs = []
	var builtin = []
	for cs in Rhythia.registry_colorset.items:
		if str(cs.id).begins_with("custom_"): customs.append(cs)
		elif cs.real_colors.size() > 0: builtin.append(cs)
	for cs in customs:
		load_ids.append(cs.id)
		load_btn.add_item(cs.name)
	for cs in builtin:
		load_ids.append(cs.id)
		load_btn.add_item("(built-in) " + cs.name)
	var i = load_ids.find(loaded_id)
	load_btn.select(i if i >= 0 else 0)

func _load_pick(i:int):
	var id = load_ids[i]
	if id == "":
		colors = [Color("#ff64b1")]
		mirror = false
		loaded_id = ""
		loaded_path = ""
		name_edit.text = ""
	else:
		var cs = Rhythia.registry_colorset.get_item(id)
		if !cs: return
		colors = cs.real_colors.duplicate()
		if colors.empty(): colors = [Color("#ffffff")]
		mirror = bool(cs.mirror)
		if id.begins_with("custom_"):
			loaded_id = id
			loaded_path = _path_of(cs.name)
			name_edit.text = cs.name
		else: # built-in: a template for a new colorset
			loaded_id = ""
			loaded_path = ""
			name_edit.text = cs.name + " copy"
	mirror_chk.pressed = mirror
	sel = 0
	_build_swatches()
	picker.color = colors[0]
	_msg("")

# ---------------------------------------------------------------- colors
func _build_swatches():
	for c in swatches.get_children():
		swatches.remove_child(c) # (queue_free alone leaves them as children until the frame ends)
		c.queue_free()
	for i in colors.size():
		var b = Button.new()
		b.rect_min_size = Vector2(46, 46)
		b.focus_mode = Control.FOCUS_NONE
		var on = i == sel
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb = StyleBoxFlat.new()
			sb.bg_color = colors[i]
			sb.set_corner_radius_all(4)
			sb.set_border_width_all(3 if on else 1)
			sb.border_color = Color(1, 1, 1, 1.0) if on else Color(1, 1, 1, 0.25)
			b.add_stylebox_override(st, sb)
		b.connect("pressed", self, "_select", [i])
		swatches.add_child(b)

func _select(i:int):
	sel = i
	_build_swatches()
	picker.color = colors[i]

func _picked(c:Color):
	colors[sel] = Color(c.r, c.g, c.b, 1.0)
	var b = swatches.get_child(sel)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb = b.get_stylebox(st)
		if sb is StyleBoxFlat: sb.bg_color = colors[sel]

func _add():
	if colors.size() >= MAX_COLORS:
		_msg("At most %d colors" % MAX_COLORS, true)
		return
	colors.insert(sel + 1, colors[sel])
	sel += 1
	_build_swatches()
	picker.color = colors[sel]

func _remove():
	if colors.size() <= 1:
		_msg("A colorset needs at least one color", true)
		return
	colors.remove(sel)
	sel = int(clamp(sel, 0, colors.size() - 1))
	_build_swatches()
	picker.color = colors[sel]

func _move(d:int):
	var j = sel + d
	if j < 0 or j >= colors.size(): return
	var t = colors[sel]
	colors[sel] = colors[j]
	colors[j] = t
	sel = j
	_build_swatches()

func _mirror_toggled(on:bool):
	mirror = on

# ---------------------------------------------------------------- save
func _path_of(nm:String) -> String:
	return Rhythia.user_colorset_dir + "/" + nm + ".txt"

static func clean_name(s:String) -> String:
	var out = ""
	for ch in s.strip_edges():
		if !(ch in "\\/:*?\"<>|"): out += ch
	return out.strip_edges()

func _save(use:bool):
	var nm = clean_name(name_edit.text)
	if nm == "":
		_msg("Give the colorset a name", true)
		return
	var path = _path_of(nm)
	var f = File.new()
	if f.file_exists(path) and path != loaded_path:
		_msg("A colorset called \"%s\" already exists: pick another name or load it to edit it" % nm, true)
		return
	var d = Directory.new()
	if !d.dir_exists(Rhythia.user_colorset_dir): d.make_dir_recursive(Rhythia.user_colorset_dir)
	if f.open(path, File.WRITE) != OK:
		_msg("Could not write " + path, true)
		return
	for c in colors: f.store_line("#" + c.to_html(false))
	if mirror: f.store_line("m")
	f.close()
	var id = "custom_" + path.get_file().to_lower().md5_text()
	Rhythia.load_color_txt(path, id)
	var cs = Rhythia.registry_colorset.get_item(id)
	loaded_id = id
	loaded_path = path
	_fill_load_list()
	if use and cs: Rhythia.select_colorset(cs)
	var grid = get_meta("grid") if has_meta("grid") else null
	if is_instance_valid(grid):
		load("res://mods/replay/ColorsetMaker.gd").refresh_grid(grid)
		call_deferred("_plus_again", grid)
	Globals.notify(Globals.NOTIFY_SUCCEED, "Saved \"%s\"%s" % [nm, " and selected it" if use else ""], "Colorset Maker", 3)
	_msg("Saved to " + path.get_file())

func _plus_again(grid:Node):
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	if is_instance_valid(grid) and is_instance_valid(menu):
		var st = menu.get_node_or_null("Main/Settings")
		if st: load("res://mods/replay/ColorsetMaker.gd").install(st, menu)

func _close():
	queue_free()

func _input(ev):
	if ev is InputEventKey and ev.pressed and !ev.echo and ev.scancode == KEY_ESCAPE:
		get_tree().set_input_as_handled()
		_close()
