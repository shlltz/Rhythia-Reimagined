extends Node
# Whole-UI audit: screenshots of every main screen at the window size set below (@@NAME@@: L = 1280x720,
# H = 1920x1080), and a log of anything that fails to open. Map @@MAP1@@. Output @@OUT@@/u_*.png + audit.txt
const OUT = "@@OUT@@/audit.txt"
var menu:Node

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1920, 1080) if "@@NAME@@".begins_with("H") else Vector2(1280, 720)
	call_deferred("run")

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func shot(n):
	if "@@NAME@@" == "Y":
		yield(get_tree(), "idle_frame")
		return
	if OS.window_minimized: return
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/u_" + n + ".png")

func key(sc:int):
	var e = InputEventKey.new()
	e.scancode = sc; e.pressed = true
	Input.parse_input_event(e)
	yield(get_tree(), "idle_frame") # (the game polls is_key_pressed: the key has to stay down a frame)
	yield(get_tree(), "idle_frame")
	var r = InputEventKey.new()
	r.scancode = sc; r.pressed = false
	Input.parse_input_event(r)

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	menu = get_tree().root.get_node("Menu")
	out("shot title")
	yield(shot("title"), "completed")
	menu.get_node("TitleMenu")._close("")
	yield(wait(1.2), "completed")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	Rhythia.select_song(song)
	yield(wait(1.8), "completed")
	if "@@NAME@@".ends_with("2"):
		yield(part_b(song), "completed")
		return
	out("shot maps")
	yield(shot("maps"), "completed")
	var si = menu.get_node_or_null("Main/Maps/Results/Results")
	if si and si.has_method("_toggle_mods"):
		si._toggle_mods(true)
		yield(wait(0.8), "completed")
		out("shot mods")
		yield(shot("mods"), "completed")
		si._toggle_mods(false)
		yield(wait(0.5), "completed")
	# settings: every tab
	load("res://mods/replay/Classic.gd").show_page(menu, "settings")
	yield(wait(1.0), "completed")
	var tabs = menu.get_node_or_null("Main/Settings/S/F/TabContainer")
	out("settings tabs: %s" % (str(tabs.get_tab_count()) if tabs else "MISSING"))
	if tabs:
		for i in tabs.get_tab_count():
			tabs.current_tab = i
			yield(wait(0.7), "completed")
			yield(shot("settings_%d" % i), "completed")
			out("  tab %d: %s" % [i, tabs.get_tab_title(i)])
	load("res://mods/replay/Classic.gd").show_page(menu, "maps")
	yield(wait(0.8), "completed")
	# customize
	menu.open_customize()
	yield(wait(1.0), "completed")
	var p = menu.get_node_or_null("ReimaginedPanel")
	out("shot cz_first")
	yield(shot("cz_first"), "completed")
	if p and p.has_method("show_tab"):
		for t in ([] if "@@NAME@@" == "X" else ["hud", "interface", "skin", "logs", "storage"]):
			p.show_tab(t, false)
			out("tab " + t)
			yield(wait(0.6), "completed")
			yield(shot("cz_" + t), "completed")
		out("skin editor next")
		if false:
			p._open_skin_editor()
			out("opened skin editor")
			for i in 5:
				yield(get_tree(), "idle_frame")
				out("  frame %d" % i)
			yield(wait(1.2), "completed")
			out("shot skin_editor")
			yield(shot("skin_editor"), "completed")
			var se = menu.get_node_or_null("SkinPanel")
			if se: se.queue_free()
	if p: p.queue_free()
	out("done")
	OS.kill(OS.get_process_id())

# (screenshots read the screen back; after several of them creating a Viewport blocked - test only,
# so the screens with their own viewports are shot in a second run)
func part_b(song):
	menu.open_customize()
	yield(wait(1.0), "completed")
	var p = menu.get_node_or_null("ReimaginedPanel")
	p._open_skin_editor()
	yield(wait(1.5), "completed")
	out("shot skin_editor")
	yield(shot("skin_editor"), "completed")
	var se = menu.get_node_or_null("SkinPanel")
	if se: se.queue_free()
	p.queue_free()
	yield(wait(0.5), "completed")
	menu.open_replays()
	yield(wait(1.2), "completed")
	out("shot replays")
	yield(shot("replays"), "completed")
	var rb = menu.get_node_or_null("ReplayBrowser")
	if rb: rb.queue_free()
	yield(wait(0.4), "completed")
	menu.open_editor(song)
	yield(wait(2.0), "completed")
	out("shot editor")
	yield(shot("editor"), "completed")
	var ed = menu.get_node_or_null("Editor")
	if ed: ed.queue_free()
	yield(wait(0.5), "completed")
	# gameplay: HUD, pause, results
	Rhythia.set("mod_nofail", true)
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var g = null
	var t = 0.0
	while !g and t < 20:
		yield(wait(0.25), "completed"); t += 0.25
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"): g = sc.get_node("Game")
	yield(wait(4.0), "completed")
	out("shot hud")
	yield(shot("hud"), "completed")
	yield(key(KEY_ESCAPE), "completed")
	yield(wait(1.0), "completed")
	out("shot pause")
	yield(shot("pause"), "completed")
	out("done")
	OS.kill(OS.get_process_id())
