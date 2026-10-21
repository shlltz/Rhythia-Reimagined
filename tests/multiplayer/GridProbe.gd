extends Node
# classic map grid: time to build a page of tiles (v2MapList.load_pg) and the frame times while
# paging, cold (covers never decoded) and warm. Output @@OUT@@/grid.txt + g_*.png
const OUT = "@@OUT@@/grid.txt"
var frames = []
var capturing = false
var last_us = 0

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func _process(_d):
	OS.vsync_enabled = false
	Engine.target_fps = 0
	var u = OS.get_ticks_usec()
	if capturing and last_us > 0: frames.append((u - last_us) / 1000.0)
	last_us = u

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func shot(n):
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/g_" + n + ".png")

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	get_tree().change_scene("res://scenes/menu/oldmenu2.tscn")
	yield(wait(3.0), "completed")
	menu = get_tree().current_scene
	load("res://mods/replay/Classic.gd").show_page(menu, "maps")
	yield(wait(1.0), "completed")
	var g = menu.get_node("Main/MapRegistry/S/G")
	var on = menu.get_node("Main/MapRegistry/T/Online")
	on.pressed = false # local maps only (they have covers; online ones aren't downloaded)
	g.update_search_showonline(false)
	yield(wait(1.0), "completed")
	var withc = 0
	for b in g.btns:
		if b.song.has_cover: withc += 1
	out("tiles %d, with covers %d" % [g.btns.size(), withc])
	for pass_i in 3:
		var t0 = OS.get_ticks_usec()
		g.load_pg()
		out("load_pg %s: %.1f ms" % [["cold", "warm", "warm"][pass_i], (OS.get_ticks_usec() - t0) / 1000.0])
		yield(wait(1.5), "completed")
	frames = []
	last_us = 0
	capturing = true
	for k in 6:
		g.load_pg()
		yield(wait(0.4), "completed")
	capturing = false
	var f = frames.duplicate()
	f.sort()
	var n = f.size()
	out("paging frames %d  p50 %.2f  p99 %.2f  max %.2f" % [n, f[n / 2], f[int(n * 0.99)], f[n - 1]])
	yield(wait(1.0), "completed")
	var shown = 0
	for b in g.btns:
		var c = b.get_node_or_null("Cover")
		if c and c.visible and c.texture: shown += 1
	out("tiles showing a cover: %d" % shown)
	shot("grid")
	# a map with a cover: the classic page gets its full cover + preview from the worker, hype on it
	var pick = null
	for tb in g.btns:
		if tb.song.has_cover and !tb.song.loaded_cover(): pick = tb.song
	if pick:
		var t1 = OS.get_ticks_usec()
		Rhythia.select_song(pick)
		out("select_song (sync part): %.2f ms" % ((OS.get_ticks_usec() - t1) / 1000.0))
		g.switch_to_play_screen()
		yield(wait(1.5), "completed")
		var si = menu.get_node("Main/Results/Results")
		var tex = null
		for dp in si.get_node("ButtonDisp").get_children():
			if dp is Panel and dp.visible and dp.has_node("Cover"): tex = dp.get_node("Cover").texture
		out("page cover = full cover: %s" % str(tex != null and tex == pick.loaded_cover()))
		var pl = si.get_node_or_null("Info/M/V/Buttons/Control/PreviewMusic/Song")
		out("preview playing: %s (prefetched stream used: %s)" % [str(pl != null and pl.playing), str(pl != null and pl.stream == pick.rr_stream)])
		out("hype on the classic page: %s, cover scaled %s, spectrum bars: %s" % [str(si.has_node("Hype")), str(si.get_node("ButtonDisp").rect_scale), str(si.has_node("Hype") and si.get_node("Hype").viz != null)])
		shot("page")
	else: out("no map with an unloaded cover to pick")
	out("== done")
	OS.kill(OS.get_process_id())
