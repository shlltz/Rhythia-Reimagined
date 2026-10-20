extends Node
# host that dies mid-match (process killed)
const OUT = "@@OUT@@/drv.txt"
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")
func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line("[%7.1f] %s" % [OS.get_ticks_msec() / 1000.0, s]); f.close()
func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")
func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	menu.get_node("TitleMenu")._close("multiplayer")
	yield(wait(1.5), "completed")
	var m = menu.get_node("Multiplayer")
	var C = m.client
	m.name_edit.text = "HostA"; m._save_name_btn()
	m._go_create(); m.c_port.text = "47381"; m.c_name.text = "Drop test"; m._create()
	var t = 0.0
	while t < 60 and C.players.size() < 2:
		yield(wait(0.25), "completed"); t += 0.25
	var roach = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": roach = s
	C.pick_map(roach)
	t = 0.0
	while t < 30:
		var r = false
		for p in C.players:
			if str(p.name) == "GuestB" and p.get("ready", false): r = true
		if r: break
		yield(wait(0.25), "completed"); t += 0.25
	C.start_match()
	t = 0.0
	while t < 40 and C.phase != "playing":
		yield(wait(0.1), "completed"); t += 0.1
	out("host playing: %s" % C.phase)
	yield(wait(5.0), "completed")
	out("host dies now")
	OS.kill(OS.get_process_id())
