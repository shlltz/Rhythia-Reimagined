extends Node
# Map switching cost per map, in the map list: time inside Rhythia.select_song() (the signal handlers
# that run at once) and the slowest of the next 6 frames, for up to 120 local maps, with each map's
# file size and note count. Then the worst 15. RR_SWITCH_SPLIT=1 also times the parts of one switch
# (song page, preview audio, covers) by doing them one at a time.
# Output: @@OUT@@/switch.txt
const OUT = "@@OUT@@/switch.txt"
var last_us = 0
var cap = null

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	OS.vsync_enabled = false
	Engine.target_fps = 0
	call_deferred("run")

func _process(_d):
	var now = OS.get_ticks_usec()
	if cap != null and last_us > 0: cap.append((now - last_us) / 1000.0)
	last_us = now

func _desc(a, b): return a[0] > b[0]

func run():
	Directory.new().remove(OUT)
	yield(wait(30.0), "completed")
	var tm = get_tree().current_scene.get_node_or_null("TitleMenu")
	if tm and tm.visible: tm._close("")
	yield(wait(3.0), "completed")
	var local = []
	for s in Rhythia.registry_song.get_items():
		if !s.is_online: local.append(s)
	var rows = []
	var tot_sync = 0.0
	for i in min(120, local.size()):
		var s = local[(i * 7) % local.size()]
		cap = []
		var t0 = OS.get_ticks_usec()
		Rhythia.select_song(s)
		var sync = (OS.get_ticks_usec() - t0) / 1000.0
		tot_sync += sync
		for k in 6: yield(get_tree(), "idle_frame")
		var worst = 0.0
		for v in cap: worst = max(worst, v)
		cap = null
		var f = File.new()
		var size = 0
		if f.open(s.filePath, File.READ) == OK:
			size = f.get_len()
			f.close()
		rows.append([max(sync, worst), sync, worst, size / 1048576.0, s.filePath.get_file()])
		yield(wait(0.15), "completed")
	rows.sort_custom(self, "_desc")
	out("== %d switches, mean time inside select_song %.2f ms" % [rows.size(), tot_sync / max(rows.size(), 1)])
	var big = 0
	for r in rows: if r[0] > 16.7: big += 1
	out("switches with a frame or call over 16.7 ms: %d" % big)
	for r in rows.slice(0, 14): out("%7.2f ms  (in select_song %.2f, worst frame after %.2f)  %5.1f MB  %s" % r)
	out("== done")
	OS.kill(OS.get_process_id())
