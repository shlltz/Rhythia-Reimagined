extends Node
# Classic map selection (Settings: old menu = scenes/menu/oldmenu2.tscn): same menu2.gd root, but a
# full-screen map grid (Main/MapRegistry, v2MapList) and the stock song page (Main/Results, legacymenu
# SongInfoScreen) instead of the list + modded page. Static helpers give every mod the right node for
# either layout; an instance (added by menu2.gd on the classic menu) brings the modded page's extras
# to the classic one: star ratings (page + grid tiles), PICK FOR LOBBY, the map editor / collection
# actions, the slowest speed button and the touch speed pad, the hype cover visualizer, and covers
# loaded off the main thread (grid thumbnails, the page's full cover) - the look stays stock.

const CLASSIC = "res://scenes/menu/oldmenu2.tscn"
const INFO = "Main/Results/Results"
const GRID = "Main/MapRegistry/S/G"

static func is_classic(menu:Node) -> bool:
	return menu != null and menu.filename == CLASSIC

# the map list script (v3MapList on the new menu, v2MapList on the classic one): prepare_songs,
# build_list, reload_to_current_page, switch_to_play_screen, btns
static func map_list(menu:Node) -> Node:
	if !menu: return null
	var l = menu.get_node_or_null("Main/Maps/MapRegistry/S/VBoxContainer")
	return l if l else menu.get_node_or_null(GRID)

# sidebar page index ("maps" / "settings"); the classic bar has Results, MapSelect, Settings, ...
static func page(menu:Node, what:String) -> int:
	var c = is_classic(menu)
	match what:
		"settings": return 2 if c else 1
	return 1 if c else 0

static func show_page(menu:Node, what:String):
	var sb = menu.get_node_or_null("Sidebar") if menu else null
	if sb and sb.has_method("press"): sb.press(page(menu, what), true)

# whatever shows PICK FOR LOBBY while the multiplayer host picks a map
static func pick_target(menu:Node) -> Node:
	if !menu: return null
	var si = menu.get_node_or_null("Main/Maps/Results/Results")
	if si and si.has_method("rr_mp_pick_mode"): return si
	return menu.get_node_or_null("RRClassic")

# map selection pages (Esc goes to the title screen from these)
static func map_pages_visible(menu:Node) -> bool:
	for p in ["Main/Maps", "Main/MapRegistry", "Main/Results"]:
		var n = menu.get_node_or_null(p)
		if n and n.is_visible_in_tree(): return true
	return false

# ---------------------------------------------------------------- instance (classic menu only)
const StarBadge = "res://mods/stars/StarBadge.gd"
var menu:Node
var si:Control
var run_btn:Button
var star_badge:Control
var mp_pick_btn:Button
var coll_popup:PopupMenu
var coll_new:PopupPanel
var tile_font:Font
var _t:float = 0.0
var bg:Node = null            # BgLoad (fixes mod): covers / preview audio on a worker thread
var preview_btn:Node = null
var page_routed:bool = false
var preview_routed:bool = false
var pending_page = null
var pending_preview = null

func _ready():
	name = "RRClassic"
	menu = get_parent()
	Rhythia.menu_target = CLASSIC # (stock: a finished run went back to the new menu)
	si = menu.get_node_or_null(INFO)
	if !si: return
	run_btn = si.get_node_or_null("Info/M/V/Run/Run")
	var mods = si.get_node_or_null("ModsHolder/Mods")
	if mods and ResourceLoader.exists("res://mods/stars/SpeedPad.gd"):
		_add_slowest_speed(mods)
		_touch_speed(mods)
	_actions_menu()
	_bg_setup()
	if ResourceLoader.exists("res://mods/hype/Hype.gd") and !si.has_node("Hype"): # cover visualizer (hype mod)
		var hy = load("res://mods/hype/Hype.gd").new()
		hy.name = "Hype"
		hy.bars = false # (pulse only here, no spectrum bars)
		si.add_child(hy)
	if ResourceLoader.exists(StarBadge):
		Rhythia.connect("selected_song_changed", self, "_update_stars")
		Rhythia.connect("mods_changed", self, "_update_stars")
		_update_stars()

func _process(delta):
	_grid_mode()
	_t += delta
	if _t < 0.25: return
	_t = 0.0
	_tile_stars()
	_tile_covers()

func _exit_tree():
	if Engine.has_meta("rr_grid_thumbs"): Engine.remove_meta("rr_grid_thumbs")

# ---- covers off the main thread
# The grid read every tile's full cover on the main thread (~170 ms per page of 20 tiles, again on
# every page / search keystroke: only 6 full covers stay loaded). While the grid shows, Song.cover
# hands it the list thumbnail instead (Song.gd checks rr_grid_thumbs) and the thumbnails are decoded
# on the worker. The stock song page and its preview button ran on the selection signal and read
# the full cover / audio there: they now run once the worker has them (a few ms later).
func _grid_mode():
	var g = menu.get_node_or_null(GRID)
	var on = bg != null and g != null and g.is_visible_in_tree()
	if on == Engine.has_meta("rr_grid_thumbs"): return
	if on: Engine.set_meta("rr_grid_thumbs", true)
	else: Engine.remove_meta("rr_grid_thumbs")

func _tile_covers():
	var g = menu.get_node_or_null(GRID)
	if !bg or !g or !g.is_visible_in_tree() or g.get("btns") == null: return
	for b in g.btns:
		if !is_instance_valid(b) or !(b.get("song") is Object) or !b.song.has_cover: continue
		var c = b.get_node_or_null("Cover")
		if !c: continue
		if b.song.thumb:
			if !c.texture: c.texture = b.song.thumb
		else: bg.request_thumb(b.song)

func _thumb_done(_map):
	_tile_covers()

func _bg_setup():
	var p = "res://mods/fixes/BgLoad.gd"
	if !ResourceLoader.exists(p) or !load(p).available(): return
	bg = load(p).new()
	add_child(bg)
	bg.connect("loaded", self, "_bg_done")
	bg.connect("thumb_loaded", self, "_thumb_done")
	if Rhythia.is_connected("selected_song_changed", si, "update"):
		Rhythia.disconnect("selected_song_changed", si, "update")
		page_routed = true
	preview_btn = si.get_node_or_null("Info/M/V/Buttons/Control/PreviewMusic")
	if preview_btn and Rhythia.is_connected("selected_song_changed", preview_btn, "upd"):
		Rhythia.disconnect("selected_song_changed", preview_btn, "upd")
		preview_routed = true
	if page_routed or preview_routed: Rhythia.connect("selected_song_changed", self, "_on_song")

func _on_song(s = null):
	var map = s if s is Object else Rhythia.selected_song
	if !(map is Object): return
	var need = false
	if page_routed:
		if !map.has_cover or map.loaded_cover(): si.update(map)
		else:
			pending_page = map
			need = true
	if preview_routed:
		if map.rr_stream or !(map.sspm_song_stored or !map.musicFile.begins_with("res://")): preview_btn.upd(map)
		else:
			pending_preview = map
			need = true
	if need: bg.request(map)

func _bg_done(map):
	if map != Rhythia.selected_song: return # (picked something else meanwhile)
	if pending_page == map:
		pending_page = null
		si.update(map) # (if the worker couldn't decode it, the stock page reads it as before)
	if pending_preview == map:
		pending_preview = null
		preview_btn.upd(map)

# ---- star ratings
func _update_stars(_x = null):
	var map = Rhythia.selected_song
	var data = si.get_node_or_null("Info/D/Data")
	var col = si.get_node_or_null("Info/M/V")
	if !(map is Object) or !data or !col: return
	if !star_badge: # own row under Favorite / Preview (the length line has the name right under it)
		star_badge = Control.new()
		star_badge.set_script(load(StarBadge))
		star_badge.name = "RRStars"
		star_badge.align_left = true
		star_badge.pill = false
		star_badge.rect_min_size = Vector2(150, 24)
		col.add_child(star_badge)
	var speed = 1.0
	if Rhythia.mod_speed_level != Globals.SPEED_NORMAL: speed = Globals.speed_multi[Rhythia.mod_speed_level]
	star_badge.set_song(map, data.get_font("font"), speed)

# a small star pill on each tile of the map grid (the grid rebuilds its tiles per page)
func _tile_stars():
	var g = menu.get_node_or_null(GRID)
	if !g or !g.is_visible_in_tree() or !ResourceLoader.exists(StarBadge) or g.get("btns") == null: return
	for b in g.btns:
		if !is_instance_valid(b) or b.has_node("RRStars") or !(b.get("song") is Object) or b.song.is_online: continue # (online = not downloaded: no notes to rate)
		if !tile_font:
			var f = b.get_node("Name").get_font("font") if b.has_node("Name") else null
			if f is DynamicFont:
				f = f.duplicate()
				f.size = 12
			tile_font = f
		var s = Control.new()
		s.set_script(load(StarBadge))
		s.name = "RRStars"
		s.align_left = true
		s.rect_position = Vector2(2, b.rect_size.y - 24) # bottom left, beside the cloud icon
		s.rect_size = Vector2(b.rect_size.x - 4, 18)
		b.add_child(s)
		s.set_song(b.song, tile_font)

# ---- speed row: S---- button + touch number pad (same as the modded page)
func _add_slowest_speed(mods:Control):
	var c = mods.get_node_or_null("SpeedMod/C")
	if !c or c.has_node("MMMM") or !c.has_node("CustomSpeed") or !c.has_node("Custom"): return
	if !ResourceLoader.exists("res://mods/stars/SpeedSlowest.gd") or !ResourceLoader.exists("res://mods/replay/Ring.gd"): return
	var b = Button.new()
	b.set_script(load("res://mods/stars/SpeedSlowest.gd"))
	b.c = c
	c.add_child(b)
	c.move_child(b, 0)

func _touch_speed(mods:Control):
	var c = mods.get_node_or_null("SpeedMod/C")
	if !c or !c.has_node("CustomSpeed") or !OS.has_touchscreen_ui_hint(): return
	var le = c.get_node("CustomSpeed").get_line_edit()
	le.editable = false
	le.virtual_keyboard_enabled = false
	le.focus_mode = Control.FOCUS_NONE
	le.connect("gui_input", self, "_speed_tap", [le, c])

func _speed_tap(ev, le:LineEdit, c:Control):
	if !(ev is InputEventMouseButton) or ev.button_index != BUTTON_LEFT or ev.pressed: return
	if !Rect2(Vector2(), le.rect_size).has_point(ev.position): return
	if get_tree().root.has_node("SpeedPad"): return
	var pad = load("res://mods/stars/SpeedPad.gd").new()
	pad.name = "SpeedPad"
	pad.c = c
	get_tree().root.add_child(pad)

# ---- multiplayer: Start turns into PICK FOR LOBBY while the host picks (MPMenu)
func rr_mp_pick_mode(on:bool):
	if !run_btn: return
	if on and !mp_pick_btn:
		mp_pick_btn = run_btn.duplicate(0) # same look (theme / overrides), no signals or script
		mp_pick_btn.set_script(null)
		mp_pick_btn.name = "RRMPPick"
		mp_pick_btn.text = "PICK FOR LOBBY"
		mp_pick_btn.disabled = false
		mp_pick_btn.connect("pressed", self, "_mp_pick")
		run_btn.get_parent().add_child(mp_pick_btn)
	if mp_pick_btn: mp_pick_btn.visible = on
	run_btn.visible = !on

func _mp_pick():
	var m = menu.get_node_or_null("Multiplayer")
	if m and Rhythia.selected_song: m.pick_done(Rhythia.selected_song)

# ---- map actions (...) menu: map editor + collections
const ID_EDIT = 7701
const ID_COLL = 7700
func _actions_menu():
	var a = si.get_node_or_null("Info/M/V/Buttons/Control/Actions")
	if !(a is MenuButton) or !ResourceLoader.exists("res://mods/replay/Reimagined.gd"): return
	a.get_popup().connect("about_to_show", self, "_actions_shown", [a.get_popup()])
	a.get_popup().connect("id_pressed", self, "_actions_pressed")
	coll_popup = PopupMenu.new()
	coll_popup.hide_on_checkable_item_selection = false
	coll_popup.connect("id_pressed", self, "_coll_pressed")
	add_child(coll_popup)
	coll_new = PopupPanel.new()
	var le = LineEdit.new()
	le.placeholder_text = "new collection name, Enter"
	le.rect_min_size = Vector2(300, 36)
	le.connect("text_entered", self, "_coll_create")
	coll_new.add_child(le)
	add_child(coll_new)

func _actions_shown(pm:PopupMenu):
	if pm.get_item_index(ID_COLL) != -1: return
	pm.add_separator()
	if ResourceLoader.exists("res://mods/replay/Editor.gd"): pm.add_item("Open in map editor", ID_EDIT)
	pm.add_item("Add to collection...", ID_COLL)

func _actions_pressed(id:int):
	if !Rhythia.selected_song: return
	if id == ID_EDIT and menu.has_method("open_editor"):
		menu.open_editor(Rhythia.selected_song)
		return
	if id != ID_COLL: return
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
	_popup_on_screen(coll_popup)

func _popup_on_screen(p:Popup):
	p.rect_size = Vector2.ZERO
	p.rect_size = p.get_combined_minimum_size()
	var vp = get_viewport().get_visible_rect().size
	var at = get_viewport().get_mouse_position()
	at.x = clamp(at.x, 8, vp.x - p.rect_size.x - 8)
	at.y = clamp(at.y, 8, vp.y - p.rect_size.y - 8)
	p.popup(Rect2(at, p.rect_size))

func _coll_pressed(id:int):
	var R = load("res://mods/replay/Reimagined.gd")
	if id == 9999:
		_popup_on_screen(coll_new)
		coll_new.get_child(0).text = ""
		coll_new.get_child(0).grab_focus()
		return
	var idx = coll_popup.get_item_index(id)
	R.coll_toggle(coll_popup.get_item_metadata(idx), Rhythia.selected_song.id)
	coll_popup.set_item_checked(idx, !coll_popup.is_item_checked(idx))

func _coll_create(t:String):
	var R = load("res://mods/replay/Reimagined.gd")
	if R.coll_create(t) and Rhythia.selected_song: R.coll_toggle(t.strip_edges(), Rhythia.selected_song.id)
	coll_new.hide()
