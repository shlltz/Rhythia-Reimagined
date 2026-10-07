extends Control

# Start + the favourite / preview / actions row; kept as refs because the re-layout moves them
# under the mods bar (RS/H2/Mods/RunBox)
onready var run_btn = get_node("RS/H1/Info/Run")
onready var ctrl_box = get_node("RS/H1/Info/Control")

func comma_sep(number):
	var string = str(number)
	var mod = string.length() % 3
	var res = ""
	
	for i in range(0, string.length()):
		if i != 0 && i % 3 == mod:
			res += ","
		res += string[i]
	
	return res

func get_time_ms(ms:float):
	var s = max(floor(ms / 1000),0)
	var m = floor(s / 60)
	var rs = fmod(s,60)
	return "%d:%02d" % [m,rs]

onready var diff_label = $RS/HMid/Difficulty # moved under the mapper by _relayout
onready var difficulty_btns:Array = [
	$RS/H1/ButtonDisp/NODIF,
	$RS/H1/ButtonDisp/EASY,
	$RS/H1/ButtonDisp/MEDIUM,
	$RS/H1/ButtonDisp/HARD,
	$RS/H1/ButtonDisp/LOGIC,
	$RS/H1/ButtonDisp/TASUKETE
]

func update(_s=null):
	if !Rhythia.selected_song: return
	$RS.visible = true
	var map:Song = Rhythia.selected_song
#	$Deleted.visible = (map.id == "!DELETED")
	$RS.visible = (map.id != "!DELETED")
	$RS/H2/EndInfo.visible = true
	ctrl_box.get_node("Actions").visible = true
#	$Actions.visible = true
	_i("/Id/Id").text = map.id
	_i("/Name/Name").text = map.name
	_i("/SongName/SongName").text = map.song
#	_i("/SongName").visible = map.name != map.song
	_i("/Mapper/Mapper").text = "by " + map.creator
	diff_label.text = map.custom_data.get("difficulty_name",
		Globals.difficulty_names.get(map.difficulty,"INVALID DIFFICULTY ID")
	)
	diff_label.modulate = Globals.difficulty_colors.get(map.difficulty,Color("#ffffff"))
	_i("/Data/Data").text = "%s - %s notes" % [get_time_ms(map.last_ms),comma_sep(map.note_count)]
	_update_stars(map)
	
	diff_label.visible = true
	
	_i("/Mapper").visible = !Rhythia.single_map_mode_txt
	_i("/Id").visible = !Rhythia.single_map_mode_txt and info_path == "RS/H1/Info" # hidden in the re-layout
	_i("/SMM").visible = Rhythia.single_map_mode

	#print(map.creator)

	var txt = ""
	if Rhythia.note_hitbox_size == 1.140: txt += tr("Default hitboxes, ")
	else: txt += tr("Hitboxes: %s, ") % Rhythia.note_hitbox_size
	if Rhythia.hitwindow_ms == 55: txt += tr("default hitwindow")
	else: txt += tr("hitwindow: %s ms") % Rhythia.hitwindow_ms
	$RS/HMid/Hitboxes.text = txt

	if map.creator == "DyamoDash":
		_i("/Mapper/Mapper").text = "by " + map.creator + " ♡"
		$RS/HMid/Hitboxes.text = txt + "\nHave you seen the Dyamo easter egg?\nHold D Y A when starting the game!"

	
	for i in range(difficulty_btns.size()):
		var n:Panel = difficulty_btns[i]
		n.visible = (map.difficulty == i-1)
		n.get_node("F").visible = Rhythia.is_favorite(map.id)
		if map.has_cover:
			n.get_node("Name").visible = false
			n.get_node("Cover").visible = true
			n.get_node("Cover").texture = map.cover
		else:
			n.get_node("Cover").visible = false
			n.get_node("Name").visible = true
			n.get_node("Name").text = map.name
	
	if map.warning != "":
		_i("/Warning").visible = true
		_i("/Warning").text = map.warning
		if map.is_broken:
			_i("/Warning").set("custom_colors/font_color",Color(1,0,0))
#			$Info/Run/Run.disabled = true
#			$Info/Buttons/Control/Favorite.disabled = true
#			$Info/Control/PreviewMusic.disabled = true
		else:
			_i("/Warning/Warning").set("custom_colors/font_color",Color(1,1,0))
#			$Info/Run/Run.disabled = false
#			$Info/Control/Favorite.disabled = false
#			$Info/Control/PreviewMusic.disabled = false
	else: _i("/Warning").visible = false
	run_btn.disabled = false
	ctrl_box.get_node("Actions").disabled = false
	ctrl_box.get_node("PreviewMusic").disabled = false
	
	$Actions/Convert.disabled = (
		$Actions/Convert.debounce or
		Rhythia.selected_song.is_broken or
		Rhythia.selected_song.is_builtin or
		Rhythia.selected_song.converted or
		Rhythia.selected_song.songType == Globals.MAP_SSPM2 or
		Rhythia.selected_song.is_online
	)
	
	$Actions/Convert.visible = (
		!Rhythia.selected_song.is_builtin and
		!Rhythia.selected_song.is_online and
		Rhythia.selected_song.songType != Globals.MAP_SSPM2
	)
	
	$Actions/Difficulty.visible = (
		!Rhythia.selected_song.is_builtin and
		!Rhythia.selected_song.is_online and (
			Rhythia.selected_song.songType == Globals.MAP_SSPM or
			Rhythia.selected_song.songType == Globals.MAP_SSPM2
		)
	)
	
	if Rhythia.selected_song.songType == Globals.MAP_SSPM:
		$Actions/Convert.text = "Upgrade map to SSPM v2"
	else:
		$Actions/Convert.text = "Convert map to .sspm"
	
	# give the containers time to update
	if is_inside_tree():
		yield(get_tree(),"idle_frame")
		yield(get_tree(),"idle_frame")
#		if _i("").rect_size.y > 245:
#			$Actions.rect_position.y = _i("").rect_size.y + 35
#			$RS/H2/EndInfo.rect_position.y = _i("").rect_size.y + 35
#		else:
#			$Actions.rect_position.y = 280
#			$RS/H2/EndInfo.rect_position.y = 280

func return_to_song_select():
	get_viewport().get_node("Menu/Sidebar").press(0,false)

# ---------------------------------------------------------------- layout (recent plays mod)
# left: recent plays; right column: cover, map name + mapper, smaller Start, favourite/preview.
# Nodes are moved after the whole menu is ready (other scripts look Run up by path in _ready).
var info_path:String = "RS/H1/Info"
func _i(p:String = ""): return get_node(info_path + p)

func _relayout():
	var h1 = get_node_or_null("RS/H1")
	if !h1 or h1.has_node("Right") or !h1.has_node("Info"): return
	var info = h1.get_node("Info")
	var cover = h1.get_node("ButtonDisp")
	var recent = load("res://mods/stars/RecentPlays.gd").new()
	recent.name = "Recent"
	recent.size_flags_horizontal = SIZE_EXPAND_FILL
	recent.size_flags_stretch_ratio = 1.6
	h1.add_child(recent)
	h1.move_child(recent, 0)
	var right = VBoxContainer.new()
	right.name = "Right"
	right.size_flags_horizontal = SIZE_FILL
	right.rect_min_size.x = 380
	right.add_constant_override("separation", 6)
	h1.add_child(right)
	var spacer = Control.new() # Recent + Spacer share the free width: equal = centred, Recent only = right
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	h1.add_child(spacer)
	recent.spacer = spacer
	h1.remove_child(cover)
	right.add_child(cover)
	h1.remove_child(info)
	right.add_child(info)
	info_path = "RS/H1/Right/Info"
	info.size_flags_vertical = 0
	var order = ["Name", "SongName", "Mapper", "Data", "Run", "Control", "Warning", "SMM", "Id"]
	for i in order.size():
		if info.has_node(order[i]): info.move_child(info.get_node(order[i]), i)
	for c in info.get_children():
		if c is HSeparator: c.visible = false
	for row in ["Name", "Mapper", "Data"]: # value only, centred
		var r = info.get_node_or_null(row)
		if !r: continue
		r.alignment = BoxContainer.ALIGN_CENTER
		for c in r.get_children():
			if c.name in ["Label", "Title"]: c.visible = false
	info.get_node("Id").visible = false
	info.get_node("SongName").visible = false # same text as the name; left a blank line
	info.get_node("Data").rect_min_size.y = 30 # room for the star/BPM badge
	if diff_label: # custom difficulty name: from the left of the page to under the mapper
		diff_label.get_parent().remove_child(diff_label)
		var drow = HBoxContainer.new()
		drow.name = "Diff"
		drow.alignment = BoxContainer.ALIGN_CENTER
		info.add_child(drow)
		info.move_child(drow, info.get_node("Mapper").get_index() + 1)
		drow.add_child(diff_label)
		diff_label.size_flags_horizontal = SIZE_EXPAND_FILL # (autowrap label: needs the column width)
		diff_label.rect_min_size = Vector2.ZERO
		diff_label.align = Label.ALIGN_CENTER
		diff_label.valign = Label.VALIGN_CENTER
	var hb = get_node_or_null("RS/HMid/Hitboxes")
	if hb:
		hb.align = Label.ALIGN_CENTER
		hb.size_flags_horizontal = SIZE_EXPAND_FILL
	cover.rect_min_size = Vector2(0, 240) # grows into the free height (square)
	cover.size_flags_vertical = SIZE_EXPAND_FILL
	cover.connect("resized", self, "_fit_column")
	for c in get_node("RS/H2").get_children(): # separators were eating clicks on Mirror Y / Invert Mouse / preview
		if c is Separator: c.mouse_filter = MOUSE_FILTER_IGNORE
	# only H1 (cover column) grows: the bottom half keeps what it needs + room for the visualizer
	for n in [["H2", 360], ["HSeparator5", 150], ["HSeparator", 0], ["HSeparator2", 16]]:
		var c = get_node_or_null("RS/" + n[0])
		if !c: continue
		c.size_flags_vertical = SIZE_FILL
		c.rect_min_size.y = max(c.rect_min_size.y, n[1])
	info.add_constant_override("separation", 4)
	for row in ["Name", "Mapper"]: # no fixed heights: name and mapper sit tight under the cover
		var r = info.get_node(row)
		r.rect_min_size = Vector2.ZERO
		for c in r.get_children():
			c.rect_min_size = Vector2.ZERO
			if c is Label: c.align = Label.ALIGN_CENTER
	# favourite / preview / actions -> small centred icon buttons (IconGlyph draws the icon,
	# the game's own text stays as state but is invisible)
	var ctrl = ctrl_box
	ctrl.alignment = BoxContainer.ALIGN_CENTER
	ctrl.add_constant_override("separation", 8)
	for n in [["Actions", "menu"], ["Favorite", "heart"], ["PreviewMusic", "play"]]:
		var bt = ctrl.get_node_or_null(n[0])
		if !bt: continue
		bt.size_flags_horizontal = 0
		bt.rect_min_size = Vector2(52, 40)
		bt.clip_text = true
		bt.icon = null
		for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_disabled", "font_color_focus"]:
			bt.add_color_override(k, Color(0, 0, 0, 0))
		bt.hint_tooltip = {"menu": "Map actions", "heart": "Favorite", "play": "Play / stop the song"}[n[1]]
		bt.add_child(load("res://mods/stars/IconGlyph.gd").new(n[1]))
	right.alignment = BoxContainer.ALIGN_CENTER # cover + name / mapper / stars, centred in the column
	run_btn.rect_min_size = Vector2(0, 48)
	run_btn.size_flags_vertical = 0
	_relayout_mods()
	_move_run_box()
	if Color("#8a6cff").r > 0.9: _share_buttons() # share build (the accent is swapped for the logo pink there)
	add_to_group("rr_mappage")
	_rr_apply()
	_rr_collection_menu()
	update()
	call_deferred("_fit_column")

# Start + the icon row as wide as the cover, so the column lines up
func _fit_column():
	var box = get_node_or_null("RS/H2/Mods/RunBox")
	var side = box.rect_size.x if box else 380.0
	run_btn.size_flags_horizontal = SIZE_FILL
	var btns = []
	for n in ["Actions", "Favorite", "PreviewMusic"]:
		var b = ctrl_box.get_node_or_null(n)
		if b and b.visible: btns.append(b)
	for b in btns: b.rect_min_size.x = floor((side - 8 * (btns.size() - 1)) / max(1, btns.size()))

# share build: Start / icon buttons in calm dark fills with an accent outline (the stock styles
# were a navy Start with green text and a bright cyan pressed heart)
func _share_buttons():
	var acc = Color("#8a6cff")
	for b in [run_btn] + ctrl_box.get_children():
		if !(b is BaseButton): continue
		var big = b == run_btn
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			var sb = StyleBoxFlat.new()
			sb.set_corner_radius_all(6)
			sb.bg_color = Color(0.2, 0.17, 0.21, 0.95)
			sb.border_color = Color(1, 1, 1, 0.22)
			sb.set_border_width_all(1)
			if big: # Start: the logo pink
				sb.bg_color = Color(acc.r * 0.62, acc.g * 0.62, acc.b * 0.62, 0.97)
				sb.border_color = Color(acc.r, acc.g, acc.b, 1.0).lightened(0.25)
				sb.set_border_width_all(2)
			if st == "hover":
				sb.bg_color = sb.bg_color.lightened(0.15)
				sb.border_color = Color(acc.r, acc.g, acc.b, 1.0).lightened(0.35)
			elif st == "pressed": sb.bg_color = sb.bg_color.darkened(0.2)
			elif st == "disabled": sb.bg_color.a = 0.5
			b.add_stylebox_override(st, sb)
	for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_focus"]:
		run_btn.add_color_override(k, Color(1, 1, 1, 0.95))

# Start + the icon row go under the "[+] MODS" bar, as wide as it (the cover column keeps the
# map's look: cover, name, mapper, stars)
func _move_run_box():
	var mods = get_node_or_null("RS/H2/Mods")
	if !mods or mods.has_node("RunBox") or !mods_toggle: return
	var box = VBoxContainer.new()
	box.name = "RunBox"
	box.add_constant_override("separation", 8)
	mods.add_child(box)
	for n in [run_btn, ctrl_box]:
		n.get_parent().remove_child(n)
		box.add_child(n)
	box.rect_position = mods_toggle.rect_position + Vector2(0, mods_toggle.rect_size.y + 16)
	box.rect_size = Vector2(mods_toggle.rect_size.x, 0)
	mods.rect_min_size.y = max(mods.rect_min_size.y, box.rect_position.y + 48 + 8 + 40 + 8)

# Rhythia-reimagined: interface toggles (also called live from the Customize panel)
func _rr_apply():
	var rr = "res://mods/replay/Reimagined.gd"
	var off = ResourceLoader.exists(rr) and load(rr).val("hide_hitbox_text")
	var hm = get_node_or_null("RS/HMid")
	if hm: hm.visible = !off

# "Add to collection" in the map's ... menu -> a checklist of collections + "New collection..."
var coll_popup:PopupMenu
var coll_new:PopupPanel
func _rr_collection_menu():
	if !ResourceLoader.exists("res://mods/replay/Reimagined.gd"): return
	var a = ctrl_box.get_node_or_null("Actions")
	if !(a is MenuButton): return
	a.get_popup().connect("about_to_show", self, "_rr_actions_shown", [a.get_popup()])
	a.get_popup().connect("id_pressed", self, "_rr_actions_pressed")
	coll_popup = PopupMenu.new()
	coll_popup.hide_on_checkable_item_selection = false
	coll_popup.connect("id_pressed", self, "_rr_coll_pressed")
	add_child(coll_popup)
	coll_new = PopupPanel.new()
	var le = LineEdit.new()
	le.placeholder_text = "new collection name, Enter"
	le.rect_min_size = Vector2(300, 36)
	le.connect("text_entered", self, "_rr_coll_create")
	coll_new.add_child(le)
	add_child(coll_new)

func _rr_actions_shown(pm:PopupMenu):
	if pm.get_item_index(7700) == -1:
		pm.add_separator()
		pm.add_item("Add to collection...", 7700)

func _rr_actions_pressed(id:int):
	if id != 7700 or !Rhythia.selected_song: return
	var R = load("res://mods/replay/Reimagined.gd")
	coll_popup.clear()
	var names = R.collections().keys()
	names.sort()
	for i in names.size():
		coll_popup.add_check_item(names[i], i)
		coll_popup.set_item_checked(i, R.coll_has(names[i], Rhythia.selected_song.id))
		coll_popup.set_item_metadata(i, names[i])
	if names.size() > 0: coll_popup.add_separator()
	coll_popup.add_item("New collection...", 9999)
	coll_popup.rect_position = get_viewport().get_mouse_position()
	coll_popup.popup()

func _rr_coll_pressed(id:int):
	var R = load("res://mods/replay/Reimagined.gd")
	if id == 9999:
		coll_new.rect_position = get_viewport().get_mouse_position()
		coll_new.popup()
		coll_new.get_child(0).text = ""
		coll_new.get_child(0).grab_focus()
		return
	var idx = coll_popup.get_item_index(id)
	R.coll_toggle(coll_popup.get_item_metadata(idx), Rhythia.selected_song.id)
	coll_popup.set_item_checked(idx, !coll_popup.is_item_checked(idx))

func _rr_coll_create(t:String):
	var R = load("res://mods/replay/Reimagined.gd")
	if R.coll_create(t) and Rhythia.selected_song: R.coll_toggle(t.strip_edges(), Rhythia.selected_song.id)
	coll_new.hide()

# ---------------------------------------------------------------- modifiers panel
# Speed / Start From stay; the mod checkboxes + health model fold away behind a "MODS" bar that
# shows what is on. Open, they are grouped. Nodes only move inside Mods (MapSearch looks Speed /
# Start From up by absolute path).
const MOD_GROUPS = [["EASIER", ["NoFail", "EasyMode"]],
	["HARDER", ["SuddenDeath", "HardMode", "HardRock", "Flashlight", "Ghost", "Chaos", "Earthquake", "Nearsight"]],
	["SPECIAL", ["MirrorX", "MirrorY", "VisualMode", "InvertMouse"]]]
var mods_nodes:Array = []      # shown only while open
var mods_boxes:Array = []
var mods_toggle:Button

func _relayout_mods():
	var mods = get_node_or_null("RS/H2/Mods")
	if !mods or mods.has_node("ModsToggle") or !mods.has_node("NoFail") or !mods.has_node("SuddenDeath"): return
	var col_a = mods.get_node("NoFail").rect_position.x
	var col_b = mods.get_node("SuddenDeath").rect_position.x
	var top = 0.0
	for n in ["SpeedMod", "StartOffset"]:
		var c = mods.get_node_or_null(n)
		if c: top = max(top, c.rect_position.y + c.rect_size.y)
	mods_toggle = Button.new()
	mods_toggle.name = "ModsToggle"
	mods_toggle.focus_mode = FOCUS_NONE
	mods_toggle.align = Button.ALIGN_LEFT
	mods_toggle.clip_text = true
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.border_width_left = 3
	sb.content_margin_left = 12
	var sh = sb.duplicate()
	sh.bg_color = Color(1, 1, 1, 0.1)
	for st in ["normal", "pressed", "focus"]: mods_toggle.add_stylebox_override(st, sb)
	mods_toggle.add_stylebox_override("hover", sh)
	mods.add_child(mods_toggle)
	# bar lines up with the speed buttons row (left edge of the buttons .. right edge of the % box)
	var row = Rect2(col_a - 150, top, col_b - col_a + 170, 0)
	var sc = mods.get_node_or_null("SpeedMod/C")
	if sc: row = Rect2(sc.get_parent().rect_position + sc.rect_position, sc.rect_size)
	mods_toggle.rect_position = Vector2(row.position.x, top + 16)
	mods_toggle.rect_size = Vector2(row.size.x, 34)
	mods_toggle.connect("pressed", self, "_toggle_mods")
	for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_focus"]: # readable on any theme
		mods_toggle.add_color_override(k, Color(1, 1, 1, 0.92))
	# open: a floating card ABOVE the bar (osu! mod select style) - opening downwards ran into the
	# bottom visualizer. Laid out from y = 0, then lifted above the bar.
	var y = 14.0
	var placed = []   # [node, Vector2 position relative to the card]
	for g in MOD_GROUPS:
		var head = Label.new()
		head.text = g[0]
		head.add_color_override("font_color", Color("#8a6cff").lightened(0.25)) # group titles in the accent colour
		mods.add_child(head)
		placed.append([head, Vector2(-150, y)])
		y += 24
		var i = 0
		for n in g[1]:
			var box = mods.get_node_or_null(n)
			if !box or !box.visible: continue # (some are hidden by the game)
			placed.append([box, Vector2(0 if i % 2 == 0 else col_b - col_a, y + int(i / 2) * 30)])
			mods_boxes.append(box)
			if box is BaseButton: box.connect("toggled", self, "_mods_summary")
			var lbl = box.get_node_or_null("Label")
			if lbl: # brighter names with a dark outline-ish shadow (readable over the cover / glow)
				lbl.add_color_override("font_color", Color(1, 1, 1, 0.95))
				lbl.add_color_override("font_color_shadow", Color(0, 0, 0, 0.8))
				lbl.add_constant_override("shadow_offset_x", 1)
				lbl.add_constant_override("shadow_offset_y", 1)
				lbl.clip_text = false
				lbl.margin_left -= 16 # (right-aligned) room so "Extra Energy" isn't cut
			i += 1
		y += int((i + 1) / 2) * 30 + 8
	var hp = mods.get_node_or_null("HpModel")
	if hp:
		placed.append([hp, Vector2(hp.rect_position.x - col_a, y + 4)])
		y += 44
	var card = Panel.new()
	card.name = "ModsCard"
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.05, 0.05, 0.065, 1.0)
	cs.set_corner_radius_all(8)
	cs.border_color = Color(1, 1, 1, 0.12)
	cs.set_border_width_all(1)
	card.add_stylebox_override("panel", cs)
	card.mouse_filter = MOUSE_FILTER_STOP # clicks on the card don't reach Speed / Start From underneath
	mods.add_child(card)
	var first = mods.get_child_count()
	for e in placed: first = min(first, e[0].get_index())
	mods.move_child(card, first) # above Speed/Start From for clicks, below the checkboxes
	var origin = Vector2(mods_toggle.rect_position.x + 165, mods_toggle.rect_position.y - 10 - y)
	card.rect_position = origin + Vector2(-165, 0)
	card.rect_size = Vector2(max(col_b - col_a + 205, mods_toggle.rect_size.x), y)
	mods_nodes.append(card)
	for e in placed:
		e[0].rect_position = origin + e[1]
		mods_nodes.append(e[0])
	for n in mods_nodes: # draw over the bottom visualizer / fade
		VisualServer.canvas_item_set_z_index(n.get_canvas_item(), 6)
	_toggle_mods(Engine.get_meta("mods_open") if Engine.has_meta("mods_open") else false)

# clicking anywhere outside the open card (and its bar / dropdowns) closes it
func _input(ev):
	if !(ev is InputEventMouseButton) or !ev.pressed or mods_nodes.empty() or !mods_nodes[0].visible: return
	var p = ev.global_position
	if mods_nodes[0].get_global_rect().has_point(p) or mods_toggle.get_global_rect().has_point(p): return
	var hp = get_node_or_null("RS/H2/Mods/HpModel")
	if hp and hp.get_popup().visible: return
	_toggle_mods(false)

var mods_tween:Tween = null
var mods_amt:float = 0.0
func _toggle_mods(open = null):
	if open == null: open = !(mods_nodes.size() > 0 and mods_nodes[0].visible)
	Engine.set_meta("mods_open", open)
	_mods_summary()
	if mods_nodes.empty(): return
	if !mods_tween:
		mods_tween = Tween.new()
		add_child(mods_tween)
	mods_tween.stop_all()
	if open:
		for n in mods_nodes: n.visible = true
	# wipe up from the MODS bar when opening, back down when closing
	mods_tween.interpolate_method(self, "_mods_wipe", mods_amt, 1.0 if open else 0.0, 0.24 if open else 0.15,
			Tween.TRANS_CUBIC, Tween.EASE_OUT if open else Tween.EASE_IN)
	mods_tween.start()

func _mods_wipe(k:float):
	mods_amt = k
	var card = mods_nodes[0]
	var bottom = card.rect_position.y + card.rect_size.y
	var top = bottom - card.rect_size.y * k
	card.rect_pivot_offset = Vector2(0, card.rect_size.y)
	card.rect_scale = Vector2(1, max(k, 0.001))
	for i in range(1, mods_nodes.size()): # rows appear as the card's top edge passes them
		var n = mods_nodes[i]
		n.modulate.a = clamp((n.rect_position.y + 20 - top) / 20.0, 0.0, 1.0)
	if k <= 0.0 and !Engine.get_meta("mods_open"): # closed (not the first step of an opening)
		for n in mods_nodes: n.visible = false

func _mods_summary(_x = null):
	if !mods_toggle: return
	var on = []
	for b in mods_boxes:
		if b.pressed: on.append(b.get_node("Label").text if b.has_node("Label") else b.name)
	var open = Engine.has_meta("mods_open") and Engine.get_meta("mods_open")
	mods_toggle.text = ("[-] MODS   " if open else "[+] MODS   ") + (PoolStringArray(on).join(", ") if on.size() > 0 else "none")

func _ready():
	call_deferred("_relayout")
	if ResourceLoader.exists("res://mods/hype/Hype.gd"): # map page effects (hype mod)
		var hy = load("res://mods/hype/Hype.gd").new()
		hy.name = "Hype"
		add_child(hy)
	Rhythia.connect("selected_song_changed",self,"update")
	Rhythia.connect("mods_changed",self,"update")
	Rhythia.connect("speed_mod_changed",self,"update")
	Rhythia.connect("favorite_songs_changed",self,"update")
#	$ButtonDisp/Select.connect("pressed",self,"return_to_song_select")
	if Rhythia.selected_song: update()
	else:
		$RS.visible = false
		$RS/H2/EndInfo.visible = false
		run_btn.disabled = true
		ctrl_box.get_node("Actions").disabled = true
		ctrl_box.get_node("PreviewMusic").disabled = true

# star rating (Steam Rhythia formula) next to length/notes; shows the speed-mod rating when one is on
const StarBadge = preload("res://mods/stars/StarBadge.gd")
var star_badge:Control = null
func _update_stars(map):
	if !star_badge:
		star_badge = Control.new()
		star_badge.set_script(StarBadge)
		star_badge.align_left = true
		star_badge.pill = false
		star_badge.rect_min_size = Vector2(150, 22)
		_i("/Data").add_child(star_badge)
	var speed = 1.0
	if Rhythia.mod_speed_level != Globals.SPEED_NORMAL:
		speed = Globals.speed_multi[Rhythia.mod_speed_level]
	star_badge.set_song(map, _i("/Data/Data").get_font("font"), speed)
