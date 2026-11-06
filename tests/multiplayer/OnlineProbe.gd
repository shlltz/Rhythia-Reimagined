extends Node
# Online maps load in the background (fixes/Online.gd): startup time, then how many online maps the
# registry and the map list hold when the menu comes up and 12 s later. Output: @@OUT@@/online.txt
const OUT = "@@OUT@@/online.txt"

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func counts() -> String:
	var reg = 0
	for s in Rhythia.registry_song.get_items():
		if s.is_online: reg += 1
	var list = get_tree().root.get_node_or_null("Menu/Main/Maps/MapRegistry/S/VBoxContainer")
	var shown = 0
	var total = 0
	if list:
		total = list.disp.size()
		for s in list.disp:
			if s.is_online: shown += 1
	return "registry online %d, list %d maps (%d online), online filter %s" % [reg, total, shown, str(list.show_online_maps) if list else "-"]

func _ready():
	call_deferred("run")

func run():
	Directory.new().remove(OUT)
	var l = get_tree().root.get_node_or_null("Menu/Main/Maps/MapRegistry/S/VBoxContainer")
	if l and OS.get_environment("RR_ONLINE_ON") == "1": l.show_online_maps = true # (RR_ONLINE_ON=1: the online filter on, as the maps arrive)
	out("menu up at %d ms: %s" % [OS.get_ticks_msec(), counts()])
	yield(get_tree().create_timer(2.0), "timeout")
	out("+2 s: %s" % counts())
	yield(get_tree().create_timer(10.0), "timeout")
	out("+12 s: %s" % counts())
	OS.kill(OS.get_process_id())
