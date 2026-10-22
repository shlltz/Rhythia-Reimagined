extends Node
# map page layout at the instance's window size: rects of Main/Maps down to depth 4. Output @@OUT@@/layout.txt
const OUT = "@@OUT@@/layout.txt"
func _ready():
	call_deferred("run")
func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()
func dump(n, d):
	if !(n is Control) or !n.visible: return
	var p = ""
	for i in d: p += "  "
	var r = n.get_global_rect()
	out("%s%s (%s) g=(%d,%d %dx%d) min=%s scale=%s" % [p, n.name, n.get_class(), r.position.x, r.position.y, r.size.x, r.size.y, str(n.rect_min_size), str(n.rect_scale)])
	if d < 4:
		for c in n.get_children(): dump(c, d + 1)
func run():
	Directory.new().remove(OUT)
	yield(get_tree().create_timer(6.0), "timeout")
	var menu = get_tree().root.get_node("Menu")
	menu.get_node("TitleMenu")._close("")
	yield(get_tree().create_timer(1.2), "timeout")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	yield(get_tree().create_timer(1.5), "timeout")
	out("viewport %s" % str(get_viewport().get_visible_rect().size))
	dump(menu.get_node("Main/Maps"), 0)
	var v = menu.get_node_or_null("AudioVisualizer")
	if v: out("visualizer g=%s z=%d" % [str(v.get_global_rect()), v.z_index])
	OS.kill(OS.get_process_id())
