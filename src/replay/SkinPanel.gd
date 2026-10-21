extends CanvasLayer
# Skin editor (Rhythia-reimagined; Customize > Skin > "Skin editor"): skin profiles (Skins.gd) on
# the left, the selected skin's settings in five groups in the middle, a live preview on the right.
# The preview is built from the game's own pieces - the note materials, grid and cursor meshes out of
# scenes/song.tscn, the real note shape / colour set / effect scenes / sounds - and moves notes at the
# player's approach rate, so what it shows is what a run shows. Edits change a working copy;
# Save writes the profile, Use makes it the skin in play (Skins.apply).

const S = preload("res://mods/replay/Skins.gd")
const Look = preload("res://mods/replay/Look.gd")
const UIAnim = preload("res://mods/replay/UIAnim.gd")
const RP = preload("res://mods/replay/ReimaginedPanel.gd")
const W = 1180.0
const H = 700.0
const GROUPS = [["notes", "Notes"], ["cursor", "Cursor"], ["effects", "Effects"], ["sounds", "Sounds"], ["hud", "HUD"]]

var root:Control
var card:Panel
var fonts:Dictionary = {}
var skin_list:ItemList
var status:Label
var cur_name:String = ""
var work:Dictionary = {}          # settings being edited
var work_colors = null            # [html] own colour set, or null
var work_mirror:bool = false
var dirty:bool = false
var group_box:VBoxContainer
var group_btns:Array = []
var cur_group:String = "notes"
var file_dialog:FileDialog
var pending_slot:String = ""
var pending_mode:String = ""      # file slot | import | export
var closing:bool = false
var name_edit:LineEdit

func _ready():
	layer = 31
	root = Control.new()
	root.anchor_right = 1
	root.anchor_bottom = 1
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists("res://uitheme.tres"): root.theme = load("res://uitheme.tres")
	add_child(root)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	root.add_child(dim)
	card = Panel.new()
	card.add_stylebox_override("panel", Look.box(Color(0.05, 0.05, 0.07, 0.98), Color(1, 1, 1, 0.12), 1, 10))
	card.anchor_left = 0.5; card.anchor_right = 0.5; card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.margin_left = -W / 2; card.margin_right = W / 2; card.margin_top = -H / 2; card.margin_bottom = H / 2
	root.add_child(card)
	var t = _label("Skin editor", 30, Color(1, 1, 1))
	t.rect_position = Vector2(26, 16)
	card.add_child(t)
	status = _label("", 13, Color(1, 1, 1, 0.55))
	status.rect_position = Vector2(28, 58)
	status.rect_size = Vector2(W - 120, 20)
	status.clip_text = true
	card.add_child(status)
	var x = _btn("X", self, "close", [], 38)
	x.flat = true
	x.rect_position = Vector2(W - 58, 18)
	card.add_child(x)
	_build_left()
	_build_middle()
	_build_preview()
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.connect("file_selected", self, "_file_picked")
	root.add_child(file_dialog)
	_refresh_list()
	var a = S.active()
	var want = Engine.get_meta("rr_skin_reopen") if Engine.has_meta("rr_skin_reopen") else ""
	Engine.remove_meta("rr_skin_reopen")
	_select(want if want != "" else (a if a != "" else (S.list()[0] if !S.list().empty() else "")))
	if Engine.has_meta("rr_skin_applied"): # (back from the reload that applied a skin)
		var ap = Engine.get_meta("rr_skin_applied")
		Engine.remove_meta("rr_skin_applied")
		_say(("\"%s\" is in use - it shows from the next map." % ap[0]) + (("  Not applied: " + PoolStringArray(ap[1]).join("; ")) if !ap[1].empty() else ""), !ap[1].empty())
	load("res://mods/replay/Device.gd").touch_fit(card) # (finger-sized buttons on touch screens)
	UIAnim.play(card, Vector2(0, 26), Vector2.ZERO, 0.0, 1.0, 0.3)

func _input(ev):
	if ev is InputEventKey and ev.pressed and !ev.echo and ev.scancode == KEY_ESCAPE:
		if file_dialog.visible: return
		get_tree().set_input_as_handled()
		close()

func close():
	if closing: return
	closing = true
	var tw = UIAnim.play(root, Vector2.ZERO, Vector2.ZERO, 1.0, 0.0, 0.2)
	tw.connect("finished", self, "queue_free")

# ------------------------------------------------------------------ helpers
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

func _btn(text:String, target:Object, method:String, args:Array = [], w:float = 0) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(w, 32)
	b.connect("pressed", target, method, args)
	return b

func _say(t:String, bad:bool = false):
	status.text = t
	status.add_color_override("font_color", Color(1, 0.55, 0.55) if bad else Color(1, 1, 1, 0.6))

func _ask(text:String, title:String, options:Array, method:String, args:Array = []):
	var opts = []
	for o in options: opts.append({text = o})
	Globals.confirm_prompt.open(text, title, opts)
	var pick = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	callv(method, [pick] + args)

# ------------------------------------------------------------------ left: profiles
func _build_left():
	var v = VBoxContainer.new()
	v.rect_position = Vector2(20, 92)
	v.rect_size = Vector2(250, H - 110)
	v.add_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(_label("Skins", 16, Color(1, 1, 1, 0.8)))
	skin_list = ItemList.new()
	skin_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skin_list.connect("item_selected", self, "_picked")
	v.add_child(skin_list)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "name"
	v.add_child(name_edit)
	var g = GridContainer.new()
	g.columns = 2
	g.add_constant_override("hseparation", 6)
	g.add_constant_override("vseparation", 6)
	v.add_child(g)
	for b in [["New from current", "_new"], ["Duplicate", "_dup"], ["Rename", "_rename"], ["Delete", "_delete_ask"], ["Import .rrskin", "_import"], ["Export .rrskin", "_export"]]:
		var bt = _btn(b[0], self, b[1], [], 122)
		g.add_child(bt)
	var use = _btn("Use this skin", self, "_use", [], 250)
	v.add_child(use)
	v.add_child(_btn("Stop using skins", self, "_unuse", [], 250))

func _refresh_list():
	skin_list.clear()
	var a = S.active()
	for n in S.list():
		skin_list.add_item(("● " if n == a else "") + n)
		skin_list.set_item_metadata(skin_list.get_item_count() - 1, n)
	if skin_list.get_item_count() == 0:
		_say("No skins yet: \"New from current\" saves the look you have now as one.")

func _picked(i:int):
	var n = skin_list.get_item_metadata(i)
	if dirty and n != cur_name:
		_ask("\"%s\" has unsaved changes. Leave them?" % cur_name, "Unsaved skin", ["Keep editing", "Leave them"], "_picked_go", [n])
		return
	_select(n)

func _picked_go(pick:int, n:String):
	if pick == 1: _select(n)
	else: _sel_row(cur_name)

func _sel_row(n:String):
	for i in skin_list.get_item_count():
		if skin_list.get_item_metadata(i) == n: skin_list.select(i)

func _select(n:String):
	cur_name = n
	_sel_row(n)
	name_edit.text = n
	var d = S.read(n) if n != "" else {}
	work = d.get("settings", {}).duplicate(true)
	work_colors = d.get("colors")
	work_mirror = d.get("mirror", false)
	dirty = false
	_show_group(cur_group)
	_rebuild_preview()
	if n != "": _say("%s%s" % [n, "  (in use)" if n == S.active() else ""])

func _new():
	var n = S.unique_name(name_edit.text if name_edit.text.strip_edges() != "" and !S.list().has(name_edit.text.strip_edges()) else "My skin")
	if S.capture(n):
		_refresh_list()
		_select(n)
		_say("\"%s\" made from the look you have now (settings + your user-folder images and sounds)." % n)

func _dup():
	if cur_name == "": return
	var n = S.duplicate_skin(cur_name, cur_name + " copy")
	_refresh_list()
	if n != "": _select(n)

func _rename():
	if cur_name == "": return
	var n = S.rename(cur_name, name_edit.text)
	if n == "":
		_say("Can't rename: the name is empty or taken.", true)
		return
	_refresh_list()
	_select(n)

func _delete_ask():
	if cur_name == "": return
	_ask("Delete the skin \"%s\"? Its folder goes to the recycle bin." % cur_name, "Delete skin", ["Cancel", "Delete"], "_delete_go")

func _delete_go(pick:int):
	if pick != 1: return
	if S.delete(cur_name):
		_say("Deleted \"%s\"." % cur_name)
		cur_name = ""
		_refresh_list()
		_select(S.list()[0] if !S.list().empty() else "")

# applied while the menu reloads (Skins.use_and_reload: the settings page would undo it otherwise);
# the editor opens again on the same skin afterwards (menu2.gd)
func _use():
	if cur_name == "" or closing: return
	if dirty: _save()
	Engine.set_meta("rr_skin_reopen", cur_name)
	closing = true
	S.use_and_reload(get_tree(), cur_name)

func _unuse():
	S.clear_active()
	_refresh_list()
	_sel_row(cur_name)
	_say("No skin in use: the game's own files from your user folder again (settings stay as they are).")

func _import():
	pending_mode = "import"
	file_dialog.mode = FileDialog.MODE_OPEN_FILE
	file_dialog.filters = PoolStringArray(["*.rrskin ; Rhythia|Reimagined skins"])
	file_dialog.popup_centered_ratio(0.7)

func _export():
	if cur_name == "": return
	pending_mode = "export"
	file_dialog.mode = FileDialog.MODE_SAVE_FILE
	file_dialog.filters = PoolStringArray(["*.rrskin ; Rhythia|Reimagined skins"])
	file_dialog.current_file = cur_name + ".rrskin"
	file_dialog.popup_centered_ratio(0.7)

func _file_picked(p:String):
	if pending_mode == "import":
		var r = S.import_pkg(p)
		if r is String:
			_say("Import failed: " + r, true)
			return
		_refresh_list()
		_select(r[0])
		_say("Imported \"%s\"." % r[0] + (("  " + PoolStringArray(r[1]).join("; ")) if !r[1].empty() else ""), !r[1].empty())
	elif pending_mode == "export":
		if dirty: _save()
		if !p.ends_with(".rrskin"): p += ".rrskin"
		var e = S.export_pkg(cur_name, p)
		_say("Exported to " + p if e == "" else "Export failed: " + e, e != "")
	elif pending_mode == "file":
		var e = S.set_file(cur_name, pending_slot, p)
		if e != "":
			_say("%s: %s" % [pending_slot, e], true)
			return
		_say("%s set." % pending_slot)
		_show_group(cur_group)
		_rebuild_preview()

# ------------------------------------------------------------------ middle: settings
func _build_middle():
	var bar = HBoxContainer.new()
	bar.rect_position = Vector2(290, 92)
	bar.add_constant_override("separation", 4)
	card.add_child(bar)
	for g in GROUPS:
		var b = _btn(g[1], self, "_show_group", [g[0]], 74)
		b.toggle_mode = true
		bar.add_child(b)
		group_btns.append(b)
	var sc = ScrollContainer.new()
	sc.rect_position = Vector2(290, 134)
	sc.rect_size = Vector2(430, H - 200)
	sc.scroll_horizontal_enabled = false
	card.add_child(sc)
	group_box = VBoxContainer.new()
	group_box.rect_min_size = Vector2(412, 0)
	group_box.add_constant_override("separation", 8)
	sc.add_child(group_box)
	var foot = HBoxContainer.new()
	foot.rect_position = Vector2(290, H - 56)
	foot.add_constant_override("separation", 8)
	card.add_child(foot)
	foot.add_child(_btn("Save", self, "_save", [], 100))
	foot.add_child(_btn("Revert", self, "_revert", [], 100))
	foot.add_child(_btn("Reset this group", self, "_reset_group", [], 190))

func _val(k:String):
	return work[k] if work.has(k) else S.DEFAULTS.get(k)

func _set(k:String, v):
	work[k] = v.to_html(true) if v is Color else v
	dirty = true
	_preview_dirty = true

func _show_group(g:String):
	cur_group = g
	for i in GROUPS.size(): group_btns[i].pressed = GROUPS[i][0] == g
	for c in group_box.get_children(): c.queue_free()
	if cur_name == "":
		group_box.add_child(_label("Make or pick a skin on the left.", 14, Color(1, 1, 1, 0.6)))
		return
	match g:
		"notes":
			_pick_row("Shape", "selected_mesh", "registry_mesh")
			_file_row("Own shape (.obj)", "mesh")
			_pick_row("Colours", "selected_colorset", "registry_colorset")
			_colors_row()
			_num_row("Size", "note_size", 0.2, 2.5, 0.01)
			_num_row("Opacity", "note_opacity", 0.0, 1.0, 0.01)
			_num_row("Spin X (°/s)", "note_spin_x", -720, 720, 1)
			_num_row("Spin Y (°/s)", "note_spin_y", -720, 720, 1)
			_num_row("Spin Z (°/s)", "note_spin_z", -720, 720, 1)
			_file_row("Note image", "note")
		"cursor":
			_file_row("Cursor image", "cursor")
			_num_row("Size", "cursor_scale", 0.1, 4.0, 0.01)
			_opt_row("Colour", "cursor_color_type", [[Globals.CURSOR_CUSTOM_COLOR, "own colour"], [Globals.CURSOR_NOTE_COLOR, "note colour"], [Globals.CURSOR_RAINBOW, "rainbow"]])
			_color_row("Own colour", "cursor_color")
			_num_row("Spin (°/s)", "cursor_spin", -720, 720, 1)
			_opt_row("Trail", "trail_style", [["game", "the game's"], ["osu", "osu! dots"], ["off", "none"]])
			_check_row("Game trail on", "cursor_trail")
			_num_row("Game trail length (s)", "trail_time", 0.02, 1.0, 0.01)
			_num_row("Game trail detail", "trail_detail", 1, 60, 1)
			_num_row("osu! trail opacity", "trail_alpha", 0.0, 1.0, 0.01)
			_num_row("osu! trail length", "trail_length", 0.2, 3.0, 0.05)
			_num_row("osu! trail size", "trail_size", 0.2, 3.0, 0.05)
			_file_row("Trail image", "trail")
			_file_row("Touch marker (phones)", "touch")
		"effects":
			_pick_row("Hit effect", "selected_hit_effect", "registry_effect")
			_pick_row("Miss effect", "selected_miss_effect", "registry_effect")
			_check_row("Show hit effects", "show_hit_effect")
			_check_row("Show miss effects", "show_miss_effect")
			_check_row("Hit effect at the cursor", "hit_effect_at_cursor")
			_color_row("Miss flash", "miss_flash_color")
		"sounds":
			_file_row("Hit sound", "hit")
			_check_row("Play hit sounds", "play_hit_snd")
			_file_row("Miss sound", "miss")
			_check_row("Play miss sounds", "play_miss_snd")
			var h = HBoxContainer.new()
			h.add_child(_btn("Play hit", self, "_play", ["hit"], 120))
			h.add_child(_btn("Play miss", self, "_play", ["miss"], 120))
			group_box.add_child(h)
		"hud":
			_file_row("HUD font (.ttf / .otf)", "hud_font")
			_color_row("Miss text", "miss_text_color")
			_color_row("Score text", "score_text_color")
			var sample = _label("SCORE 1,234,567   COMBO 420   98.76%", 20, Color(_val("score_text_color")))
			var hf = S.hud_font(20, cur_name)
			if hf: sample.add_font_override("font", hf)
			group_box.add_child(sample)

func _row(text:String, ctl:Control):
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 10)
	var l = _label(text, 14, Color(1, 1, 1, 0.8))
	l.rect_min_size = Vector2(150, 0)
	l.valign = Label.VALIGN_CENTER
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	group_box.add_child(h)
	return h

func _num_row(text:String, k:String, lo:float, hi:float, step:float):
	var sp = SpinBox.new()
	sp.min_value = lo
	sp.max_value = hi
	sp.step = step
	sp.value = float(_val(k))
	sp.connect("value_changed", self, "_num_changed", [k, step >= 1 and k in ["trail_detail"]])
	_row(text, sp)

func _num_changed(v:float, k:String, as_int:bool):
	_set(k, int(v) if as_int else v)

func _check_row(text:String, k:String):
	var c = CheckBox.new()
	c.pressed = bool(_val(k))
	c.focus_mode = Control.FOCUS_NONE
	c.connect("toggled", self, "_set_b", [k])
	_row(text, c)

func _set_b(v:bool, k:String):
	_set(k, v)

func _color_row(text:String, k:String):
	var cp = ColorPickerButton.new()
	cp.color = Color(_val(k))
	cp.rect_min_size = Vector2(0, 30)
	cp.connect("color_changed", self, "_set_c", [k])
	_row(text, cp)

func _set_c(c:Color, k:String):
	_set(k, c)

func _opt_row(text:String, k:String, opts:Array):
	var o = OptionButton.new()
	for i in opts.size():
		o.add_item(str(opts[i][1]), i)
		o.set_item_metadata(i, opts[i][0])
		if str(opts[i][0]) == str(_val(k)): o.select(i)
	o.connect("item_selected", self, "_opt_changed", [o, k])
	_row(text, o)

func _opt_changed(i:int, o:OptionButton, k:String):
	_set(k, o.get_item_metadata(i))

func _pick_row(text:String, k:String, reg:String):
	var o = OptionButton.new()
	var items = Rhythia.get(reg).get_items() if Rhythia.get(reg) else []
	var i = 0
	for it in items:
		o.add_item(str(it.name), i)
		o.set_item_metadata(i, it.id)
		if it.id == str(_val(k)): o.select(i)
		i += 1
	o.connect("item_selected", self, "_opt_changed", [o, k])
	_row(text, o)

func _colors_row():
	var le = LineEdit.new()
	le.placeholder_text = "own colours: #ff3d64, #00ffed ... (empty = the set above)"
	le.text = PoolStringArray(work_colors).join(", ") if work_colors is Array else ""
	le.connect("text_entered", self, "_colors_set")
	le.connect("focus_exited", self, "_colors_le", [le])
	_row("Own colours", le)
	var m = CheckBox.new()
	m.text = "mirror (back and forth)"
	m.pressed = work_mirror
	m.connect("toggled", self, "_mirror_set")
	_row("", m)

func _colors_le(le:LineEdit):
	_colors_set(le.text)

func _colors_set(t:String):
	var cs = []
	for p in t.replace(";", ",").split(",", false):
		var c = p.strip_edges()
		if c.is_valid_html_color(): cs.append(Color(c).to_html(false))
	work_colors = cs if !cs.empty() else null
	dirty = true
	_preview_dirty = true

func _mirror_set(v:bool):
	work_mirror = v
	dirty = true
	_preview_dirty = true

func _file_row(text:String, slot:String):
	var h = HBoxContainer.new()
	var f = S.file_of(cur_name, slot)
	var l = _label(f.get_file() if f != "" else "(the game's own)", 13, Color(1, 1, 1, 0.75 if f != "" else 0.4))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	h.add_child(l)
	h.add_child(_btn("Choose...", self, "_choose", [slot], 90))
	if f != "": h.add_child(_btn("Clear", self, "_clear_file", [slot], 60))
	_row(text, h)

func _choose(slot:String):
	pending_mode = "file"
	pending_slot = slot
	file_dialog.mode = FileDialog.MODE_OPEN_FILE
	file_dialog.filters = PoolStringArray(["*." + PoolStringArray(S.FILES[slot][2]).join(", *.") + " ; " + slot])
	file_dialog.popup_centered_ratio(0.7)

func _clear_file(slot:String):
	S.clear_file(cur_name, slot)
	_show_group(cur_group)
	_rebuild_preview()

func _save():
	if cur_name == "": return
	var d = {"settings": work, "name": cur_name}
	if work_colors is Array:
		d.colors = work_colors
		d.mirror = work_mirror
	if S.write(cur_name, d):
		dirty = false
		_say("Saved \"%s\"." % cur_name + ("  Press \"Use this skin\" to play with it." if S.active() != cur_name else ""))
		if S.active() == cur_name: S.apply(cur_name)
	else: _say("Couldn't save the skin.", true)

func _revert():
	_select(cur_name)

func _reset_group():
	if cur_name == "": return
	for k in S.defaults_for(cur_group): work[k] = S.defaults_for(cur_group)[k]
	if cur_group == "notes": work_colors = null
	for slot in S.FILES:
		if S.FILES[slot][0] == cur_group: S.clear_file(cur_name, slot)
	dirty = true
	_preview_dirty = true
	_show_group(cur_group)
	_rebuild_preview()
	_say("%s back to the game's defaults (Save to keep it)." % cur_group.capitalize())

func _play(slot:String):
	var f = S.file_of(cur_name, slot)
	var st = Globals.audioLoader.load_file(f) if f != "" else null
	if !(st is AudioStream): st = Rhythia.hit_snd if slot == "hit" else Rhythia.miss_snd
	if st is AudioStreamOGGVorbis or st is AudioStreamMP3: st.loop = false
	sfx.stream = st
	sfx.play()

# ------------------------------------------------------------------ right: live preview
var vp:Viewport
var world:Spatial
var spawn:Spatial
var notes_mm:MultiMeshInstance
var cursor:Spatial
var cursor_mat:SpatialMaterial
var solid_mat:Material
var trans_mat:Material
var sfx:AudioStreamPlayer
var _preview_dirty:bool = false
var t:float = 0.0
var lanes:Array = []
var hit_fx = null
var miss_fx = null
var parts:Dictionary = {}

func _build_preview():
	var holder = ViewportContainer.new()
	holder.rect_position = Vector2(740, 92)
	holder.rect_size = Vector2(420, 420)
	holder.stretch = true
	card.add_child(holder)
	vp = Viewport.new()
	vp.size = Vector2(420, 420)
	vp.own_world = true
	vp.msaa = Viewport.MSAA_4X
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	holder.add_child(vp)
	world = Spatial.new()
	vp.add_child(world)
	var env = WorldEnvironment.new()
	var e = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.03)
	env.environment = e
	world.add_child(env)
	var cam = Camera.new()
	cam.transform.origin = Vector3(0, 0, 3.5) # (the game's camera)
	cam.fov = Rhythia.get("fov")
	cam.far = 500
	cam.current = true
	world.add_child(cam)
	sfx = AudioStreamPlayer.new()
	add_child(sfx)
	_game_parts()
	var note = _label("live preview: the game's notes, grid and cursor at your approach rate", 12, Color(1, 1, 1, 0.4))
	note.rect_position = Vector2(742, 518)
	note.rect_size = Vector2(420, 34)
	note.autowrap = true
	card.add_child(note)
	for i in 9: lanes.append([i % 3, int(i / 3)])
	lanes.shuffle()
	set_process(true)

# the note materials, grid and cursor out of scenes/song.tscn (its scene state: nothing instanced)
func _game_parts():
	var ps = load("res://scenes/song.tscn")
	if !(ps is PackedScene): return
	var st = ps.get_state()
	for i in st.get_node_count():
		var path = str(st.get_node_path(i))
		for j in st.get_node_property_count(i):
			var pn = st.get_node_property_name(i, j)
			var key = path + ":" + pn
			if key.ends_with("Spawn:note_solid_mat") and path.ends_with("Game/Spawn"): parts.solid = st.get_node_property_value(i, j)
			elif key.ends_with("Spawn:note_transparent_mat") and path.ends_with("Game/Spawn"): parts.trans = st.get_node_property_value(i, j)
			elif path.ends_with("Game/Spawn/Outer") or path.ends_with("Game/Spawn/Inner") or path.ends_with("Game/Spawn/Cursor/Mesh"):
				parts[path.get_file() + ":" + pn] = st.get_node_property_value(i, j)

func _rebuild_preview():
	_preview_dirty = false
	if spawn: spawn.queue_free()
	spawn = Spatial.new()
	spawn.transform.origin = Vector3(-1, 1, 0) # (the game's Spawn)
	world.add_child(spawn)
	for g in ["Outer", "Inner"]:
		if !parts.has(g + ":mesh"): continue
		var mi = MeshInstance.new()
		mi.mesh = parts[g + ":mesh"]
		mi.transform = parts.get(g + ":transform", Transform())
		var m = parts.get(g + ":material/0")
		var R = load("res://mods/replay/Reimagined.gd")
		var tex = R.skin_tex("border" if g == "Outer" else "grid")
		if m and tex:
			m = m.duplicate()
			m.albedo_texture = tex
		mi.set("material/0", m)
		spawn.add_child(mi)
	# notes: the chosen shape with the game's materials, coloured per instance like the game does
	var mesh = _note_mesh()
	notes_mm = MultiMeshInstance.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.color_format = MultiMesh.COLOR_FLOAT
	mm.mesh = mesh
	mm.instance_count = 9
	notes_mm.multimesh = mm
	spawn.add_child(notes_mm)
	# cursor
	cursor = Spatial.new()
	cursor.transform.origin = Vector3(1, -1, 0)
	spawn.add_child(cursor)
	if parts.has("Mesh:mesh"):
		var cm = MeshInstance.new()
		cm.mesh = parts["Mesh:mesh"]
		cm.transform = parts.get("Mesh:transform", Transform())
		cursor_mat = parts.get("Mesh:material/0").duplicate() if parts.get("Mesh:material/0") else SpatialMaterial.new()
		var img = _skin_image("cursor")
		if !img: img = Globals.imageLoader.load_if_exists("user://cursor")
		if img: cursor_mat.albedo_texture = img
		cm.set("material/0", cursor_mat)
		var s = float(_val("cursor_scale"))
		cm.scale = Vector3(s, s, s)
		cm.name = "Mesh"
		cursor.add_child(cm)
	_effects()

func _skin_image(slot:String):
	var f = S.file_of(cur_name, slot)
	if f == "": return null
	var img = Image.new()
	if img.load(f) != OK: return null
	var tx = ImageTexture.new()
	tx.create_from_image(img)
	return tx

func _note_mesh() -> Mesh:
	var path = ""
	var own = S.file_of(cur_name, "mesh")
	if own != "": path = own
	else:
		var it = Rhythia.registry_mesh.get_item(str(_val("selected_mesh")))
		path = it.path if it else "res://assets/blocks/rounded.obj"
	var mesh = ObjParse.load_obj(path) if !path.begins_with("res://") else load(path)
	if !(mesh is Mesh): mesh = load("res://assets/blocks/rounded.obj")
	mesh = mesh.duplicate()
	solid_mat = parts.solid.duplicate() if parts.has("solid") else SpatialMaterial.new()
	trans_mat = parts.trans.duplicate() if parts.has("trans") else solid_mat
	var img = _skin_image("note")
	if !img: img = Globals.imageLoader.load_if_exists("user://note")
	if img and solid_mat is ShaderMaterial:
		for m in [solid_mat, trans_mat]:
			m.set_shader_param("image", img)
			m.set_shader_param("use_image", true)
	mesh.surface_set_material(0, solid_mat)
	if mesh.get_surface_count() > 1: mesh.surface_set_material(1, trans_mat)
	if mesh.get_surface_count() > 2: mesh.surface_set_material(2, solid_mat)
	return mesh

func _effects():
	hit_fx = null
	miss_fx = null
	for e in [["selected_hit_effect", false], ["selected_miss_effect", true]]:
		var it = Rhythia.registry_effect.get_item(str(_val(e[0])))
		if !it: continue
		var sc = load(it.path)
		if !(sc is PackedScene): continue
		var fx = sc.instance()
		if fx.has_method("setup"): fx.setup(it.id, e[1])
		fx.visible = false
		spawn.add_child(fx)
		if e[1]: miss_fx = [fx, it.id]
		else: hit_fx = [fx, it.id]

func _colors() -> Array:
	if work_colors is Array:
		var cs = []
		for c in work_colors: cs.append(Color(c))
		if work_mirror and cs.size() > 2:
			for i in range(cs.size() - 2, 0, -1): cs.append(cs[i])
		return cs
	var set = Rhythia.registry_colorset.get_item(str(_val("selected_colorset")))
	return set.colors if set else [Color(1, 1, 1)]

var fired:Dictionary = {} # note slot -> the cycle it last fired its hit / miss effect in
func _process(delta):
	if !notes_mm or closing: return
	if _preview_dirty: _rebuild_preview()
	t += delta
	var ar = max(5.0, float(Rhythia.get("approach_rate")))
	var dist = max(5.0, float(Rhythia.get("spawn_distance")))
	var span = dist / ar                      # seconds a note is on screen
	var gap = 0.33                            # between notes
	var cols = _colors()
	var sz = 0.45 * float(_val("note_size")) * (Rhythia.note_hitbox_size / 1.14)
	var op = float(_val("note_opacity"))
	var spin = Vector3(float(_val("note_spin_x")), float(_val("note_spin_y")), float(_val("note_spin_z")))
	var mm = notes_mm.multimesh
	for i in 9:
		var born = floor((t - i * gap) / (9 * gap)) * 9 * gap + i * gap
		var age = t - born
		var lane = lanes[i]
		var z = -(span - age) * ar
		var tr = Transform().scaled(Vector3(sz, sz, sz))
		tr = tr.rotated(Vector3(1, 0, 0), deg2rad(spin.x * t)).rotated(Vector3(0, 1, 0), deg2rad(spin.y * t)).rotated(Vector3(0, 0, 1), deg2rad(spin.z * t))
		tr.origin = Vector3(lane[0], -lane[1], z)
		mm.set_instance_transform(i, tr)
		var c = cols[(int(born / gap)) % cols.size()]
		var a = op * clamp((dist - (-z)) / (dist * 0.25), 0.0, 1.0) if z < 0 else 0.0
		mm.set_instance_color(i, Color(c.r, c.g, c.b, a))
		if z >= 0 and fired.get(i, -1.0) != born: # (one effect per note reaching the grid; every 4th misses)
			fired[i] = born
			_fx(lane, c, i % 4 == 3)
	# cursor: glides between the lanes, the chosen colour / spin
	if cursor:
		var p = Vector2(1 + sin(t * 1.7) * 0.9, -1 + cos(t * 1.3) * 0.9)
		cursor.transform.origin = Vector3(p.x, p.y, 0.002)
		var m = cursor.get_node_or_null("Mesh")
		if m: m.rotation_degrees.y = -float(_val("cursor_spin")) * t
		if cursor_mat:
			var ct = int(_val("cursor_color_type"))
			if ct == Globals.CURSOR_RAINBOW: cursor_mat.albedo_color = Color.from_hsv(fmod(t * 0.1, 1.0), 0.65, 1)
			elif ct == Globals.CURSOR_NOTE_COLOR: cursor_mat.albedo_color = cols[-1]
			elif cursor_mat.albedo_texture == null: cursor_mat.albedo_color = Color(_val("cursor_color"))
			else: cursor_mat.albedo_color = Color(1, 1, 1)

func _fx(lane:Array, col:Color, miss:bool):
	var e = miss_fx if miss else hit_fx
	if e == null or !(bool(_val("show_miss_effect")) if miss else bool(_val("show_hit_effect"))): return
	var fx = e[0].duplicate()
	if !fx.has_method("spawn"):
		fx.free()
		return
	var pos = Vector3(lane[0] - 1, 1 - lane[1], 0.002)
	if !miss and bool(_val("hit_effect_at_cursor")) and cursor: pos = cursor.global_transform.origin
	fx.spawn(world, pos, col, e[1], miss)
