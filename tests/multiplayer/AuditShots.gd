extends Node
# UI audit: screenshots of the main screens at the window size mpbench gives (1280x720). Output @@OUT@@/a_*.png
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")
func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")
func shot(n):
	if OS.window_minimized: return
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/" + n + ".png")
func run():
	yield(wait(6.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	yield(shot("a_title"), "completed")
	menu.get_node("TitleMenu")._close("")
	yield(wait(1.2), "completed")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	yield(wait(1.5), "completed")
	yield(shot("a_maps"), "completed")
	menu.open_customize()
	yield(wait(1.0), "completed")
	var p = menu.get_node_or_null("ReimaginedPanel")
	yield(shot("a_customize"), "completed")
	if p and p.has_method("show_tab"):
		for t in ["hud", "interface", "skin", "collections", "device", "logs", "storage"]:
			p.show_tab(t, false)
			yield(wait(0.6), "completed")
			yield(shot("a_cz_" + t), "completed")
	if p: p.queue_free()
	yield(wait(0.5), "completed")
	menu.open_replays()
	yield(wait(1.2), "completed")
	yield(shot("a_replays"), "completed")
	var rb = menu.get_node_or_null("ReplayBrowser")
	if rb: rb.queue_free()
	yield(wait(0.4), "completed")
	menu.open_library()
	yield(wait(1.5), "completed")
	yield(shot("a_library"), "completed")
	var lp = menu.get_node_or_null("LibraryPanel")
	if lp: lp.queue_free()
	yield(wait(0.4), "completed")
	var np = load("res://mods/replay/NamePanel.gd").new()
	menu.add_child(np)
	yield(wait(0.8), "completed")
	yield(shot("a_namepanel"), "completed")
	np.queue_free()
	OS.kill(OS.get_process_id())
