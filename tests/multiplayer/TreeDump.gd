extends Node
# Dumps the menu's node tree under RR_DUMP_ROOT (default Menu/Main/Maps) with class, script, global
# rect, visibility, to RR_DUMP_DEPTH (default 6), on a selected map's page. Output @@OUT@@/tree.txt
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_size = Vector2(1920, 1080)
	call_deferred("run")
func run():
	yield(get_tree().create_timer(24.0), "timeout")
	var menu = get_tree().root.get_node("Menu")
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	yield(get_tree().create_timer(2.0), "timeout")
	if OS.get_environment("RR_FAKE_PB") == "1": # (sample values in the best-attempt panel, to see its layout)
		var ei = menu.find_node("EndInfo", true, false)
		if ei:
			ei.visible = true
			var vals = {"Result": "Best Attempt", "LetterGrade": "A", "LetterGrade2": "A", "Misses": "69", "Pauses": "-", "Accuracy": "2,669/2,738\n97.480%", "MaxCombo": "443", "Progress": "3:14\n60.93%"}
			for k in vals:
				var l = ei.get_node_or_null(k)
				if l: l.text = vals[k]
			for k in ["Pauses", "Misses"]: ei.get_node(k).visible = true
			for k in ["NoPauses", "FullCombo"]: ei.get_node(k).visible = false
		yield(get_tree().create_timer(0.3), "timeout")
	var root_p = OS.get_environment("RR_DUMP_ROOT") if OS.get_environment("RR_DUMP_ROOT") != "" else "Menu/Main/Maps"
	var depth = int(OS.get_environment("RR_DUMP_DEPTH")) if OS.get_environment("RR_DUMP_DEPTH") != "" else 6
	var f = File.new()
	f.open("@@OUT@@/tree.txt", File.WRITE)
	_dump(f, get_tree().root.get_node(root_p), 0, depth)
	f.close()
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png("@@OUT@@/page.png")
	var fb = get_tree().root.get_node_or_null("Menu/Main/Maps/MapRegistry/T/RRFilters")
	if fb: # (the filter panel open)
		fb.pressed = true
		fb.emit_signal("toggled", true)
		yield(get_tree().create_timer(0.5), "timeout")
		img = get_viewport().get_texture().get_data()
		img.flip_y()
		img.save_png("@@OUT@@/page_filters.png")
	OS.kill(OS.get_process_id())
func _dump(f, n, d, maxd):
	var sc = n.get_script()
	var r = ""
	if n is Control: r = "%s %s%s" % [str(n.get_global_rect().position.round()), str(n.rect_size.round()), "" if n.visible else " HIDDEN"]
	elif n is CanvasLayer: r = "layer %d" % n.layer
	f.store_line("%s%s [%s%s] %s" % ["  ".repeat(d), n.name, n.get_class(), (" " + sc.resource_path.get_file()) if sc and sc.resource_path != "" else "", r])
	if d >= maxd: return
	if n.name == "VBoxContainer" and n.get_child_count() > 6: # (the map list's cards: just one)
		_dump(f, n.get_child(0), d + 1, maxd)
		f.store_line("%s... %d cards" % ["  ".repeat(d + 1), n.get_child_count()])
		return
	for c in n.get_children(): _dump(f, c, d + 1, maxd)
