extends Node
# Dumps the in-game HUD viewports' controls (name, type, rect, text, font size) mid-run. Output @@OUT@@/hud.txt
const OUT = "@@OUT@@/hud.txt"
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")
func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()
func dump(n:Node, d:int):
	var s = "  ".repeat(d) if false else ""
	for i in d: s += "  "
	var extra = ""
	if n is Control:
		extra = " pos=%s size=%s vis=%s" % [str(n.rect_position), str(n.rect_size), str(n.visible)]
		if n is Label:
			var f = n.get_font("font")
			extra += " text='%s' fsize=%s align=%d autowrap=%s clip=%s" % [n.text, str(f.size if f is DynamicFont else "?"), n.align, str(n.autowrap), str(n.clip_text)]
	elif n is Viewport:
		extra = " vsize=%s" % str(n.size)
	elif n is Spatial:
		extra = " origin=%s scale=%s" % [str(n.transform.origin), str(n.scale)]
	out(s + n.name + " (" + n.get_class() + ")" + extra)
	for c in n.get_children(): dump(c, d + 1)
func run():
	Directory.new().remove(OUT)
	yield(get_tree().create_timer(6.0, true), "timeout")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	Rhythia.select_song(song)
	Rhythia.set("mod_nofail", true)
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var g = null
	while !g:
		yield(get_tree().create_timer(0.25, true), "timeout")
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"): g = sc.get_node("Game")
	yield(get_tree().create_timer(5.0, true), "timeout")
	dump(g.get_node("HUD"), 0)
	OS.kill(OS.get_process_id())
