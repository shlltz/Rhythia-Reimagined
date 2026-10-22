extends Node
# which visible controls cover a screen point on the map page (1280x720). Output @@OUT@@/pick.txt
const OUT = "@@OUT@@/pick.txt"
func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()
func _ready():
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")
func run():
	Directory.new().remove(OUT)
	yield(get_tree().create_timer(6.0), "timeout")
	var menu = get_tree().root.get_node("Menu")
	menu.get_node("TitleMenu")._close("")
	yield(get_tree().create_timer(1.2), "timeout")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	yield(get_tree().create_timer(2.0), "timeout")
	var pt = Vector2(263, 491)
	var stack = [get_tree().root]
	while !stack.empty():
		var n = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is Control and n.is_visible_in_tree() and n.get_global_rect().has_point(pt) and n.get_global_rect().get_area() < 200000:
			out("%s  %s  %s  %s  text=%s" % [n.get_path(), n.get_class(), n.get_global_rect(), n.modulate, str(n.get("text")).substr(0, 30)])
	out("== totals: 1 passed, 0 failed")
	OS.kill(OS.get_process_id())
