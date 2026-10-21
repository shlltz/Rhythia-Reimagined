extends Node
# classic map selection (oldmenu2.tscn, the old-menu setting): the mods' screens and hooks work there
# too. Needs @@MAP1@@ in the library. Output: @@OUT@@/classic.txt + c_*.png
const OUT = "@@OUT@@/classic.txt"
const CLASSIC = "res://scenes/menu/oldmenu2.tscn"
var passed = 0
var failed = 0

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
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
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/c_" + n + ".png")

func esc():
	var e = InputEventKey.new()
	e.scancode = KEY_ESCAPE
	e.pressed = true
	get_tree().input_event(e)
	e = e.duplicate()
	e.pressed = false
	get_tree().input_event(e)

func vis(menu, p):
	var n = menu.get_node_or_null(p)
	return n != null and n.is_visible_in_tree()

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	Rhythia.enable_oldmenu = true
	get_tree().change_scene(CLASSIC)
	yield(wait(3.0), "completed")
	menu = get_tree().current_scene
	ok("classic menu loaded", menu.filename == CLASSIC, menu.filename)
	ok("classic hooks added, finished runs come back here", menu.has_node("RRClassic") and Rhythia.menu_target == CLASSIC)
	ok("sidebar mod buttons", menu.has_node("Sidebar/L/Replays") and menu.has_node("Sidebar/L/Multiplayer") and menu.has_node("Sidebar/L/Customize"))
	# title screen -> Play / Settings land on the right classic pages
	menu.show_title()
	yield(wait(1.5), "completed")
	var tm = menu.get_node_or_null("TitleMenu")
	ok("title screen", tm != null and tm.visible)
	shot("title")
	tm._close("settings")
	yield(wait(1.2), "completed")
	ok("title Settings -> settings page", vis(menu, "Main/Settings"))
	esc()
	yield(wait(1.2), "completed")
	ok("Esc on settings -> title", tm.visible)
	tm._close("play")
	yield(wait(1.5), "completed")
	ok("title Play -> map grid", vis(menu, "Main/MapRegistry"))
	yield(wait(1.0), "completed")
	var g = menu.get_node("Main/MapRegistry/S/G")
	var se = menu.get_node("Main/MapRegistry/T/Search") # the test library's one downloaded map (online ones have no rating)
	se.text = "dancing roach"
	se.emit_signal("text_changed", se.text)
	var n = 0
	var t = 0.0
	while t < 5 and (n == 0 or n != g.btns.size()): # (the grid rebuilds its tiles on a resize)
		yield(wait(0.25), "completed"); t += 0.25
		n = 0
		for b in g.btns:
			if is_instance_valid(b) and b.has_node("RRStars"): n += 1
	ok("star ratings on the grid tiles", n > 0 and n == g.btns.size(), "%d / %d" % [n, g.btns.size()])
	shot("grid")
	ok("map list helper finds the grid", load("res://mods/replay/Classic.gd").map_list(menu) == g)
	# song page
	Rhythia.select_song(song)
	g.switch_to_play_screen()
	yield(wait(1.5), "completed")
	ok("map picked -> song page", vis(menu, "Main/Results"))
	var hooks = menu.get_node("RRClassic")
	ok("star rating on the song page", hooks.star_badge != null and hooks.star_badge.is_visible_in_tree() and hooks.star_badge.song == song)
	ok("slowest speed button", menu.has_node("Main/Results/Results/ModsHolder/Mods/SpeedMod/C/MMMM"))
	var a = menu.get_node("Main/Results/Results/Info/M/V/Buttons/Control/Actions")
	var pm = a.get_popup()
	pm.emit_signal("about_to_show")
	ok("map actions: editor + collections", pm.get_item_index(7701) != -1 and pm.get_item_index(7700) != -1)
	shot("info")
	pm.emit_signal("id_pressed", 7700)
	yield(wait(0.5), "completed")
	ok("collection list opens", hooks.coll_popup.visible)
	hooks.coll_popup.hide()
	esc()
	yield(wait(1.0), "completed")
	ok("Esc on the song page -> grid", vis(menu, "Main/MapRegistry") and !vis(menu, "Main/Results"))
	esc()
	yield(wait(1.0), "completed")
	ok("Esc on the grid -> title", tm.visible)
	tm._close("")
	yield(wait(1.0), "completed")
	# multiplayer: the host picks the lobby map on the classic pages
	menu.open_multiplayer()
	yield(wait(1.0), "completed")
	var m = menu.get_node("Multiplayer")
	m._go_create()
	m.c_port.text = "47396"
	m._create()
	t = 0.0
	while t < 5 and !m.client.online():
		yield(wait(0.1), "completed"); t += 0.1
	ok("lobby hosted", m.client.online())
	m._pick_begin()
	yield(wait(0.6), "completed")
	Classic_show_maps(menu)
	Rhythia.select_song(song)
	g.switch_to_play_screen()
	yield(wait(1.2), "completed")
	var pb = hooks.mp_pick_btn
	ok("PICK FOR LOBBY replaces Start", pb != null and pb.is_visible_in_tree() and !hooks.run_btn.visible)
	shot("pick")
	pb.emit_signal("pressed")
	yield(wait(1.0), "completed")
	ok("map picked for the lobby", str(m.client.lobby.get("map", {}).get("id", "")) == song.id and !pb.visible and hooks.run_btn.visible)
	m._back()
	m._back()
	yield(wait(0.6), "completed")
	if menu.has_node("Multiplayer"): menu.get_node("Multiplayer").queue_free()
	yield(wait(0.3), "completed")
	# a run from the classic menu comes back to it, with the results screen
	Rhythia.select_song(song)
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	t = 0.0
	var game = null
	while t < 30 and !game:
		yield(wait(0.25), "completed"); t += 0.25
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"): game = sc.get_node("Game")
	ok("game started", game != null)
	yield(wait(2.0), "completed")
	if game: game.end(Globals.END_GIVEUP)
	t = 0.0
	while t < 20 and !get_tree().root.has_node("Menu/ResultsScreen"):
		yield(wait(0.25), "completed"); t += 0.25
	menu = get_tree().current_scene
	ok("back on the classic menu with the results screen", menu.filename == CLASSIC and menu.has_node("ResultsScreen"), menu.filename)
	yield(wait(1.0), "completed")
	shot("results")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())

func Classic_show_maps(menu):
	load("res://mods/replay/Classic.gd").show_page(menu, "maps")
