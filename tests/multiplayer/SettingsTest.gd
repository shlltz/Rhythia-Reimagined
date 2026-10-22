extends Node
# Settings page: row layout, descriptions, reset arrows, autosave, tab reset (through the game's
# confirm dialog), search with folded sections. Drives the real controls the way a click does.
# Output @@OUT@@/settings_test.txt + st_*.png
const OUT = "@@OUT@@/settings_test.txt"
var passed = 0
var failed = 0
var rows:Node
var tabs:TabContainer

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1920, 1080) if "@@NAME@@" != "L" else Vector2(1280, 720)
	call_deferred("run")

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
	if OS.window_minimized: return
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/st_" + n + ".png")

func saved_json() -> Dictionary:
	var f = File.new()
	if f.open(Globals.p("user://settings.json"), File.READ) != OK: return {}
	var d = parse_json(f.get_as_text()); f.close()
	return d if d is Dictionary else {}

func entry(path:String):
	for e in rows.rows:
		if str(tabs.get_path_to(e.row)) == path: return e
	return null

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	yield(wait(1.0), "completed")
	load("res://mods/replay/Classic.gd").show_page(menu, "settings")
	yield(wait(1.2), "completed")
	var st = menu.get_node("SettingsStyle")
	rows = st.get_node_or_null("RRRows")
	tabs = st.tabs
	ok("rows helper installed", rows != null)
	if !rows:
		OS.kill(OS.get_process_id())
		return
	var with_reset = 0
	var descs = 0
	for e in rows.rows:
		if e.reset: with_reset += 1
	for t in tabs.get_children():
		for sec in t.get_children():
			var h = sec.get_node_or_null("Group/H")
			if h:
				for r in h.get_children(): if r.has_meta("rr_desc"): descs += 1
	ok("most rows know their default", with_reset >= 70, "%d of %d rows" % [with_reset, rows.rows.size()])
	ok("rows have descriptions", descs >= 60, descs)
	var dirty = []
	for e in rows.rows:
		if e.reset and e.reset.visible: dirty.append(e.key)
	out("rows already off their default at start: %s" % str(dirty))
	yield(shot("gameplay"), "completed")

	# spin box (FOV): change -> arrow, saved; reset -> default in Rhythia
	var fov = entry("Gameplay/Camera/Group/H/FOV")
	ok("FOV row found with a default of 70", fov != null and fov.def == 70.0, fov.def if fov else "")
	fov.ctl.value = 95
	yield(wait(1.6), "completed")
	ok("FOV applied to the game", Rhythia.fov == 95, Rhythia.fov)
	ok("FOV reset arrow shows", fov.reset.visible)
	ok("change saved to settings.json", saved_json().get("fov") == 95.0, saved_json().get("fov"))
	ok("header says saved", rows.saved.text == "changes saved" and rows.saved.modulate.a > 0.1, rows.saved.text)
	fov.reset.emit_signal("pressed")
	yield(wait(1.6), "completed")
	ok("FOV reset to 70 in the game", Rhythia.fov == 70 and fov.ctl.value == 70, Rhythia.fov)
	ok("FOV arrow gone after reset", !fov.reset.visible)
	ok("reset saved too", saved_json().get("fov") == 70.0, saved_json().get("fov"))

	# switch (target checkbox): click path, reset
	var grid = entry("UI/UI/Group/H/Grid")
	var gdef = grid.def
	grid.ctl.pressed = not gdef
	grid.ctl._pressed() # (what a click runs)
	yield(wait(0.6), "completed")
	ok("switch applied", Rhythia.enable_grid == (not gdef))
	ok("switch drawn instead of a tick box", grid.row.get_child_count() > 0 and grid.row.get_icon("checked") is ImageTexture and grid.row.get_icon("checked").get_width() == 1)
	grid.reset.emit_signal("pressed")
	yield(wait(0.6), "completed")
	ok("switch reset to its default", Rhythia.enable_grid == gdef)

	# colour picker
	var col = entry("World & Cursor/Cursor/Group/H/cursor_color")
	col.ctl.color = Color(1, 0, 0)
	col.ctl.emit_signal("popup_closed")
	yield(wait(0.6), "completed")
	ok("colour applied", Rhythia.cursor_color.to_html() == Color(1, 0, 0).to_html())
	col.reset.emit_signal("pressed")
	yield(wait(0.6), "completed")
	ok("colour reset", Rhythia.cursor_color.to_html() == Color(1, 1, 1).to_html(), Rhythia.cursor_color)

	# volume (percent + dB pair)
	var vol = entry("Video & Audio/Audio/Group/H/HitSound2")
	ok("volume row has a default", vol != null and vol.def == 30.0)
	vol.ctl.value = 80
	yield(wait(0.4), "completed")
	var db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("HitSound"))
	ok("volume applied", abs(db2linear(db) - 0.8) < 0.01, db)
	vol.reset.emit_signal("pressed")
	yield(wait(0.4), "completed")
	db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("HitSound"))
	ok("volume reset to 30%", abs(db2linear(db) - 0.3) < 0.01, db2linear(db))

	# mod's own row (Swept Hitbox, reimagined.json)
	var sw = entry("Gameplay/Modifiers/Group/H/SweptHitbox")
	var R = load("res://mods/replay/Reimagined.gd")
	sw.ctl.pressed = false
	yield(wait(0.4), "completed")
	ok("swept hitbox off", R.val("swept_hitbox") == false)
	sw.reset.emit_signal("pressed")
	yield(wait(0.4), "completed")
	ok("swept hitbox back on", R.val("swept_hitbox") == true)

	# tab reset: two changes, confirm through the game's dialog
	tabs.current_tab = 0
	yield(wait(0.5), "completed")
	fov.ctl.value = 100
	var hw = entry("Gameplay/Modifiers/Group/H/HitWindow")
	hw.ctl.value = 70
	yield(wait(0.8), "completed")
	ok("tab reset button counts 2", rows.tab_reset.text.find("(2)") > 0 and !rows.tab_reset.disabled, rows.tab_reset.text)
	rows.tab_reset.emit_signal("pressed")
	yield(wait(0.8), "completed")
	yield(shot("confirm"), "completed")
	var cp = Globals.confirm_prompt
	ok("confirm dialog asks first", cp != null and cp.visible)
	ok("nothing reset before confirming", Rhythia.fov == 100)
	cp.emit_signal("option_selected", 1)
	yield(wait(1.5), "completed")
	ok("tab reset applied after confirming", Rhythia.fov == 70 and Rhythia.hitwindow_ms == 55, "%s %s" % [Rhythia.fov, Rhythia.hitwindow_ms])
	ok("tab reset button disabled when nothing differs", rows.tab_reset.disabled, rows.tab_reset.text)

	# every tab opens and keeps drawing (the Notes tab once froze in a layout loop)
	var frames = Engine.get_frames_drawn()
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		yield(wait(0.5), "completed")
	ok("every tab opens", Engine.get_frames_drawn() - frames > 20, Engine.get_frames_drawn() - frames)
	tabs.current_tab = 1
	yield(wait(0.5), "completed")
	yield(shot("notes"), "completed")

	# folded section + search
	var colors = tabs.get_node("UI/UIColor/Group")
	tabs.current_tab = 3
	yield(wait(0.5), "completed")
	ok("HUD colours start folded", !colors.visible)
	yield(shot("ui_folded"), "completed")
	st.search.text = "panel"
	st._search("panel")
	yield(wait(0.5), "completed")
	var desc_ok = true
	for r in tabs.get_node("UI/UIColor/Group/H").get_children():
		if r.has_meta("rr_desc") and r.visible != r.get_meta("rr_desc").visible: desc_ok = false
	ok("search opens folded sections", colors.visible)
	ok("descriptions follow their row in search", desc_ok)
	yield(shot("search"), "completed")
	st.search.text = ""
	st._search("")
	yield(wait(0.4), "completed")
	ok("folds back after search", !colors.visible)
	tabs.current_tab = 4
	yield(wait(0.6), "completed")
	yield(shot("video"), "completed")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
