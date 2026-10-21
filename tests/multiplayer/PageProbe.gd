extends Node
# dev probe: classic song page node tree (Main/Results/Results) + screenshots of both song pages
const OUT = "@@OUT@@/page.txt"
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")
func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()
func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")
func shot(n):
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/pg_" + n + ".png")
func dump(n, d):
	var s = "  ".repeat(d) if false else ""
	for i in d: s += "  "
	var x = s + n.name + " [" + n.get_class() + "]"
	if n.get_script(): x += " {" + str(n.get_script().resource_path).get_file() + "}"
	if n is Control: x += " pos" + str(n.rect_position) + " size" + str(n.rect_size) + (" HIDDEN" if !n.visible else "")
	if n.get("text") is String and n.text != "": x += " '" + n.text.replace("\n", "|").left(40) + "'"
	out(x)
	for c in n.get_children(): dump(c, d + 1)
func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	Rhythia.select_song(song)
	yield(wait(1.5), "completed")
	shot("new")
	Rhythia.enable_oldmenu = true
	get_tree().change_scene("res://scenes/menu/oldmenu2.tscn")
	yield(wait(3.0), "completed")
	menu = get_tree().current_scene
	load("res://mods/replay/Classic.gd").show_page(menu, "maps")
	Rhythia.select_song(song)
	load("res://mods/replay/Classic.gd").map_list(menu).switch_to_play_screen()
	yield(wait(1.5), "completed")
	shot("classic")
	var si = menu.get_node("Main/Results/Results")
	for n in ["EndInfo", "ButtonDisp", "Info", "Info/D", "Info/M/V"]:
		var c = si.get_node(n)
		out("%s pos %s size %s min %s anchors %s %s scale %s" % [n, c.rect_position, c.rect_size, c.get_combined_minimum_size(), c.anchor_top, c.anchor_bottom, c.rect_scale])
	dump(menu.get_node("Main/Results"), 0)
	OS.kill(OS.get_process_id())
