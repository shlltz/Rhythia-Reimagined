extends Node
# v2.8 features: files dropped onto the game (colorset, note mesh, settings files, font), the HUD
# font, trail gradient + cursor glow in a run, and the settings generator (a live run is tracked,
# advise() from stored runs, Apply / Undo stick even with the settings page's own boxes).
# Map: @@MAP1@@. Output @@OUT@@/features.txt + feat_*.png
const OUT = "@@OUT@@/features.txt"
const D = "@@OUT@@/drop/"
var passed = 0
var failed = 0
var R

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func ok(what:String, cond:bool, info = ""):
	if cond: passed += 1
	else: failed += 1
	out("%s  %s  %s" % ["PASS" if cond else "FAIL", what, str(info)])

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func shot(name):
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png("@@OUT@@/" + name)

func write(path:String, text:String):
	var f = File.new()
	f.open(path, File.WRITE)
	f.store_string(text)
	f.close()

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func drop(files:Array):
	get_tree().emit_signal("files_dropped", PoolStringArray(files), 0)

func answer(i:int): # the confirm prompt a drop opened
	yield(wait(0.3), "completed")
	Globals.confirm_prompt.emit_signal("option_selected", i)

func song():
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": return s
	return null

func start_run(live:bool):
	Rhythia.select_song(song())
	if live:
		Rhythia.replaying = false
		Rhythia.mod_nofail = true
	else:
		Rhythia.replay = Replay.new()
		Rhythia.replaying = true
		Rhythia.replay_path = ""
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var t0 = OS.get_ticks_msec()
	while OS.get_ticks_msec() - t0 < 60000:
		yield(get_tree(), "idle_frame")
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game") and sc.get_node("Game").has_node("Spawn") and sc.get_node("Game/Spawn").active: return sc.get_node("Game")
	return null

func to_menu(g):
	if is_instance_valid(g): g.end(Globals.END_GIVEUP)
	var t = 0.0
	while t < 20 and !(get_tree().current_scene and get_tree().current_scene.name == "Menu"):
		yield(wait(0.25), "completed"); t += 0.25
	yield(wait(1.5), "completed")
	var rs = get_tree().current_scene.get_node_or_null("ResultsScreen")
	if rs: rs.queue_free()

func run():
	Directory.new().remove(OUT)
	Directory.new().make_dir_recursive(D)
	yield(wait(6.0), "completed")
	var t = 0.0
	while t < 30:
		yield(wait(0.25), "completed"); t += 0.25
		var sc = get_tree().current_scene
		if !sc or sc.name != "Menu": continue
		var tm = sc.get_node_or_null("TitleMenu")
		if tm and tm.visible:
			tm._close("")
			yield(wait(1.0), "completed")
		break
	R = load("res://mods/replay/Reimagined.gd")
	ok("drop handler on the root", get_tree().root.has_node("DropFiles"))
	# ---- colorset
	write(D + "Test Sunset.txt", "#ff0000\n#00ff88\n0000ff\nm\n")
	write(D + "notacolorset.txt", "some map data, 1|1|200\n")
	drop([D + "Test Sunset.txt", D + "notacolorset.txt"])
	yield(wait(0.5), "completed")
	var id = "custom_" + "test sunset.txt".md5_text()
	var cs = Rhythia.registry_colorset.get_item(id)
	ok("colorset .txt added", cs != null and !(cs is bool), id)
	ok("colorset selected", cs and !(cs is bool) and Rhythia.selected_colorset == cs)
	ok("other .txt ignored", !File.new().file_exists(Rhythia.user_colorset_dir.plus_file("notacolorset.txt")))
	# ---- note mesh
	write(D + "tri.obj", "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n")
	drop([D + "tri.obj"])
	yield(wait(0.3), "completed")
	var m = Rhythia.registry_mesh.get_item("ugc_tri.obj")
	ok("note mesh .obj added", m != null and !(m is bool))
	ok("mesh copied to the meshes folder", File.new().file_exists(Rhythia.user_mesh_dir.plus_file("tri.obj")))
	# ---- font
	var src = File.new()
	src.open("res://assets/font/main.ttf", File.READ)
	var bytes = src.get_buffer(src.get_len())
	src.close()
	var f = File.new()
	f.open(D + "MyFont.ttf", File.WRITE)
	f.store_buffer(bytes)
	f.close()
	write(D + "broken.ttf", "not a font")
	drop([D + "broken.ttf"])
	yield(wait(0.3), "completed")
	ok("a broken font is refused", R.val("hud_font") != "own")
	drop([D + "MyFont.ttf"])
	yield(wait(0.3), "completed")
	ok("font dropped -> HUD font = own", R.val("hud_font") == "own" and load("res://mods/replay/HudFont.gd").own_path() != "", R.val("hud_font"))
	# ---- customize settings file
	write(D + "custom.json", to_json({"trail_style": "osu", "trail_color2": "ff3d64", "cursor_glow": 0.6, "player_name": "NotMe"}))
	drop([D + "custom.json"])
	yield(answer(0), "completed")
	yield(wait(2.5), "completed") # (the menu reloads)
	ok("customize file loaded", R.val("trail_style") == "osu" and R.val("trail_color2") == "ff3d64" and is_equal_approx(float(R.val("cursor_glow")), 0.6), [R.val("trail_style"), R.val("trail_color2"), R.val("cursor_glow")])
	ok("player name not taken from a file", R.val("player_name") != "NotMe")
	ok("backup of the old customize settings", File.new().file_exists(Globals.p(R.FILE) + ".bak"))
	# ---- game settings file
	var keep_fs = OS.window_fullscreen
	write(D + "settings.json", to_json({"approach_rate": 41.5, "spawn_distance": 13.5, "window_fullscreen": true}))
	drop([D + "settings.json"])
	yield(answer(0), "completed")
	yield(wait(3.0), "completed")
	ok("game settings loaded", is_equal_approx(Rhythia.approach_rate, 41.5) and is_equal_approx(Rhythia.get("spawn_distance"), 13.5), [Rhythia.approach_rate, Rhythia.get("spawn_distance")])
	ok("display settings left alone", OS.window_fullscreen == keep_fs)
	ok("settings backup written", File.new().file_exists(Globals.p("user://settings-backup.json")))
	yield(wait(1.0), "completed")
	ok("approach rate survives the settings page (a second later)", is_equal_approx(Rhythia.approach_rate, 41.5), Rhythia.approach_rate)
	# ---- a run with the pixel font, gradient, glow (autoplay)
	R.cfg()["hud_font"] = "pixel"
	var g = yield(start_run(false), "completed")
	ok("run started", g != null)
	if g:
		yield(wait(3.0), "completed")
		var hud = g.get_node("HUD")
		var lab = hud.scorelabel
		var fnt = lab.get_font("font")
		ok("HUD label uses the pixel font", fnt is DynamicFont and fnt.font_data and fnt.font_data.resource_path.ends_with("main.ttf"), fnt.font_data.resource_path if fnt is DynamicFont and fnt.font_data else "")
		var glow = g.get_node("Spawn/Cursor").get_node_or_null("CursorGlow")
		ok("cursor glow under the cursor", glow != null)
		if glow: ok("glow strength", abs(glow.mat.albedo_color.a - 0.48) < 0.01, glow.mat.albedo_color)
		var ot = g.get_parent().find_node("OsuTrail", true, false)
		ok("osu trail fades to the end colour", ot != null and ot.tail != null and ot.tail.to_html(false) == "ff3d64")
		yield(shot("feat_run.png"), "completed")
		yield(to_menu(g), "completed")
	# ---- settings generator: a live run is tracked
	var PT = load("res://mods/replay/PlayTrack.gd")
	PT.forget()
	R.cfg()["track_plays"] = true
	g = yield(start_run(true), "completed")
	if g:
		var t2 = 0.0
		while is_instance_valid(g) and int(g.misses) + int(g.hits) < 40 and t2 < 40:
			yield(wait(0.5), "completed"); t2 += 0.5
		ok("tracker on a live run", g.get_node("Spawn").rr_track != null)
		var tr = g.get_node("Spawn").rr_track
		if tr: ok("misses split into short / past / beside", tr.under + tr.over + tr.wide == tr.misses and tr.misses > 0, [tr.misses, tr.under, tr.over, tr.wide])
		yield(to_menu(g), "completed")
	var runs = PT.load_all()
	ok("the run was stored with its settings", runs.size() == 1 and runs[0].settings.has("sensitivity"), runs.size())
	# advise from synthetic runs: overshooting + late hits
	var all = []
	for i in 4:
		all.append({t = i, map = "x", notes = 400, hits = 360, misses = 40, late = 160, late_ms = 18.0, under = 5, over = 30, wide = 5,
			speed = 1.0, passed = true, settings = {sensitivity = Rhythia.sensitivity, approach_rate = Rhythia.approach_rate, spawn_distance = Rhythia.get("spawn_distance")}})
	var tips = PT.advise(all)
	var ids = []
	for x in tips: ids.append(x.id)
	ok("advice: lower sensitivity (overshooting) and more reading time (late hits)", "sens_down" in ids and "reading" in ids, ids)
	ok("no advice from too few runs", PT.advise(all.slice(0, 1)).empty())
	# Apply / Undo through Customize
	var f2 = File.new()
	f2.open(Globals.p(PT.FILE), File.WRITE)
	f2.store_string(to_json(all))
	f2.close()
	var menu = get_tree().current_scene
	if menu.has_method("open_customize"): menu.open_customize()
	yield(wait(1.0), "completed")
	var panel = null
	for c in menu.get_children():
		if c.get_script() and c.get_script().resource_path.ends_with("ReimaginedPanel.gd"): panel = c
	for c in get_tree().root.get_children():
		if !panel and c.get_script() and c.get_script().resource_path.ends_with("ReimaginedPanel.gd"): panel = c
	ok("Customize open", panel != null)
	if panel:
		panel.show_tab("gen", false)
		yield(wait(0.5), "completed")
		ok("generator tab lists the suggestions", panel.gen_w.list.get_child_count() >= 2, panel.gen_w.list.get_child_count())
		yield(shot("feat_gen.png"), "completed")
		var before = float(Rhythia.sensitivity)
		var tip = null
		for x in PT.advise(all):
			if x.id == "sens_down": tip = x
		panel._gen_apply(tip)
		yield(wait(1.0), "completed")
		ok("Apply changed sensitivity and it stays (settings page box updated)", is_equal_approx(float(Rhythia.sensitivity), float(tip.set.sensitivity)) and !is_equal_approx(before, float(Rhythia.sensitivity)), [before, Rhythia.sensitivity])
		panel._gen_undo("sens_down")
		yield(wait(1.0), "completed")
		ok("Undo puts it back", is_equal_approx(float(Rhythia.sensitivity), before), Rhythia.sensitivity)
		panel.show_tab("trail", false)
		yield(wait(0.6), "completed")
		yield(shot("feat_trail.png"), "completed")
		panel.show_tab("hud", false)
		yield(wait(0.6), "completed")
		yield(shot("feat_hud.png"), "completed")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
