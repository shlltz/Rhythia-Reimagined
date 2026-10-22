extends Node
# Map screens: title menu cards (Browse / Multiplayer hidden by default), the map page's blurred
# cover backdrop, a map start through the real Start button (zoom into the cover, no black), the
# loading screen (map card, slowly turning logo, the preview muffled through a low-pass bus), the
# results card, and Retry from it, the no-cover look. Maps: @@MAP1@@ (with a cover), @@MAP2@@ (without). Output @@OUT@@/screens.txt + ms_*.png
const OUT = "@@OUT@@/screens.txt"
var passed = 0
var failed = 0

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1600, 900)
	call_deferred("run")

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line("[%7.1f] %s" % [OS.get_ticks_msec() / 1000.0, s]); f.close()

func ok(n, c, d = ""):
	if c: passed += 1
	else: failed += 1
	out(("PASS  " if c else "FAIL  ") + n + ("  " + str(d) if str(d) != "" else ""))

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func shot(n):
	if OS.window_minimized:
		out("(window minimized: no screenshot %s)" % n)
		yield(get_tree(), "idle_frame")
		return
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/" + n + ".png")

func find_script(n:Node, part:String):
	for c in n.get_children():
		if c.get_script() and part in str(c.get_script().resource_path) and c.is_visible_in_tree(): return c
		var r = find_script(c, part)
		if r: return r
	return null

func run():
	Directory.new().remove(OUT)
	yield(wait(6.5), "completed")
	var menu = get_tree().root.get_node("Menu")
	var tm = menu.get_node_or_null("TitleMenu")
	var titles = []
	if tm:
		for c in tm.cards: titles.append(c.title.to_lower())
	ok("title menu: Browse and Multiplayer hidden by default", tm != null and !("browse" in titles) and !("multiplayer" in titles) and "play" in titles and "editor" in titles, titles)
	yield(shot("ms_title"), "completed")
	tm._close("")
	yield(wait(1.5), "completed")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	ok("test map has a cover", song != null and song.has_cover)
	Rhythia.select_song(song)
	var bd = menu.get_node_or_null("MapBackdrop")
	var t = 0.0
	while t < 6 and !(bd and bd.vis >= 1.0 and bd.front.texture != null):
		yield(wait(0.1), "completed"); t += 0.1
	ok("map page: blurred cover backdrop up", bd != null and bd.vis >= 1.0 and bd.front.texture != null, "%.1f s" % t)
	ok("backdrop is the small copy (cheap blur)", bd.front.texture and bd.front.texture.get_width() <= 512, bd.front.texture.get_size() if bd.front.texture else "")
	yield(wait(1.5), "completed")
	yield(shot("ms_select"), "completed")
	var pm = menu.find_node("PreviewMusic", true, false)
	var playing = false
	if pm:
		for n in ["Song", "MenuSong"]:
			var p = pm.get_node_or_null(n)
			if p is AudioStreamPlayer and p.playing: playing = true
	out("preview playing on the map page: %s" % str(playing))
	# the real Start button
	var btn = find_script(menu, "RunMapButton")
	ok("Start button found", btn != null)
	Rhythia.set("mod_nofail", true)
	btn._pressed()
	yield(wait(0.3), "completed")
	var main = menu.get_node("Main")
	ok("launch: the menu zooms in", menu.rect_scale.x > 1.03, menu.rect_scale)
	ok("launch: the page fades while the cover stays (no black)", main.modulate.a < 0.85 and bd.modulate.a > 0.9 and menu.get_node("BlackFade").color.a < 0.01, "%.2f / %.2f" % [main.modulate.a, bd.modulate.a])
	yield(shot("ms_launch"), "completed")
	t = 0.0
	var ls = null
	while t < 5 and !ls:
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
		var sc = get_tree().current_scene
		if sc and sc.filename.ends_with("songload.tscn"): ls = find_script(sc, "LoadScreen")
	ok("loading screen", ls != null)
	if !ls:
		out("== totals: %d passed, %d failed" % [passed, failed])
		OS.kill(OS.get_process_id())
		return
	var sl = get_tree().current_scene
	ok("loading screen opens without black (seamless)", float(sl.black_fade) < 0.01, sl.black_fade)
	ok("same cover behind it", ls.bg.texture != null and ls.zoom0 > 1.1, ls.zoom0)
	var rot0 = ls.logo.rect_rotation
	yield(wait(0.7), "completed")
	ok("square logo turns slowly", ls.logo.rect_rotation > rot0 and ls.logo.rect_rotation - rot0 < 40, ls.logo.rect_rotation - rot0)
	var bus = AudioServer.get_bus_index("RRMuffle")
	if playing:
		var lp = AudioServer.get_bus_effect(bus, 0) if bus >= 0 else null
		ok("preview keeps playing, muffled (low-pass)", ls.player != null and ls.player.playing and lp != null and lp.cutoff_hz < 1500, lp.cutoff_hz if lp else "no bus")
	else:
		ok("no preview was playing: nothing to muffle", ls.player == null)
	yield(shot("ms_load"), "completed")
	var g = null
	t = 0.0
	while t < 30 and !g:
		yield(wait(0.25), "completed"); t += 0.25
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"): g = sc.get_node("Game")
	ok("the run starts", g != null)
	ok("muffle bus removed after loading", AudioServer.get_bus_index("RRMuffle") < 0)
	yield(wait(4.0), "completed")
	yield(shot("ms_game"), "completed")
	yield(wait(2.0), "completed")
	g.end(Globals.END_GIVEUP)
	t = 0.0
	while t < 20 and !get_tree().root.has_node("Menu/ResultsScreen"):
		yield(wait(0.25), "completed"); t += 0.25
	var rs = get_tree().root.get_node_or_null("Menu/ResultsScreen")
	ok("results card", rs != null)
	yield(wait(2.6), "completed")
	ok("results: cover backdrop + grade stamped", rs.bd.texture != null and rs.stamped and rs.grade_text.modulate.a > 0.9)
	var r = Rect2(rs.holder.rect_global_position, rs.holder.rect_size * rs.holder.rect_scale)
	ok("results card fits above the buttons", r.end.y < get_viewport().get_visible_rect().size.y - 90, r)
	yield(shot("ms_results"), "completed")
	rs._retry()
	t = 0.0
	ls = null
	while t < 5 and !ls:
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
		var sc = get_tree().current_scene
		if sc and sc.filename.ends_with("songload.tscn"): ls = find_script(sc, "LoadScreen")
	ok("retry from results: loading screen without black", ls != null and float(get_tree().current_scene.black_fade) < 0.01)
	yield(wait(0.6), "completed")
	yield(shot("ms_retry_load"), "completed")
	# a map without a cover: contour lines in its difficulty colour, no placeholder picture
	var bare = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and !s.has_cover and s.filePath.get_file() == "@@MAP2@@": bare = s
	if bare:
		var l2 = load("res://mods/replay/LoadScreen.gd").new()
		var layer = CanvasLayer.new()
		layer.layer = 50
		get_tree().root.add_child(layer)
		layer.add_child(l2)
		l2.show_song(bare)
		yield(wait(0.8), "completed")
		ok("no cover: contour texture, no placeholder", l2.banner.material.get_shader_param("topo") > 0.5 and l2.has_node("NoCover"))
		yield(shot("ms_nocover"), "completed")
	else:
		ok("no-cover test map (@@MAP2@@) present", false)
	out("== totals: %d passed, %d failed" % [passed, failed])
	yield(wait(0.5), "completed")
	OS.kill(OS.get_process_id())
