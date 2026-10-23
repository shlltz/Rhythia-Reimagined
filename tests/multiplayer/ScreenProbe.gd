extends Node
# Render cost per screen (uncapped fps): frame time, 2D canvas items and 2D draw calls, 3D draw calls,
# vertices, video memory - title menu, map list, map pages (a plain map, a 7-10 star map with the
# side glow, a 10+ star map with the hype effects), settings, editor, gameplay. A weak GPU pays
# for draw calls, full-screen passes and overdraw, which a fast CPU hides.
# Output: @@OUT@@/screens.txt
const OUT = "@@OUT@@/screens.txt"
var last_us = 0
var cap = null
var mon = null

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

const MON = ["RENDER_2D_ITEMS_IN_FRAME", "RENDER_2D_DRAW_CALLS_IN_FRAME", "RENDER_DRAW_CALLS_IN_FRAME", "RENDER_VERTICES_IN_FRAME"]
func _process(_d):
	var now = OS.get_ticks_usec()
	if cap != null and last_us > 0:
		cap.append((now - last_us) / 1000.0)
		for i in MON.size(): mon[i] += Performance.get_monitor(Performance.get(MON[i]))
	last_us = now

func measure(label:String):
	yield(wait(2.0), "completed")
	cap = []
	mon = [0.0, 0.0, 0.0, 0.0]
	yield(wait(3.0), "completed")
	var a = cap
	cap = null
	if OS.get_environment("RR_SHOTS") == "1":
		var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/sc_" + label.replace(" ", "_").replace("+", "p") + ".png")
	var n = max(a.size(), 1)
	var s = 0.0
	for v in a: s += v
	a.sort()
	out("%-22s mean %6.3f ms  p99 %6.2f  | 2D items %5.0f  2D calls %5.0f  3D calls %4.0f  verts %7.0f  | vram %.0f MB" % [label, s / n, a[int(a.size() * 0.99)], mon[0] / n, mon[1] / n, mon[2] / n, mon[3] / n, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])

func stars_of(s) -> float:
	var sc = get_tree().root.get_node_or_null("StarCache")
	if sc and sc.has_method("get_stars"): return float(sc.get_stars(s))
	return -1.0

func run():
	Directory.new().remove(OUT)
	yield(wait(25.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	yield(measure("title menu"), "completed")
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("")
	var plain = null
	var glow = null
	var hype = null
	for s in Rhythia.registry_song.get_items():
		if s.is_online: continue
		var st = stars_of(s)
		if s.filePath.get_file() == "@@MAP1@@": plain = s
		if st >= 7.5 and st < 9.5 and glow == null: glow = s
		if st >= 10.5 and hype == null: hype = s
	yield(measure("map list"), "completed")
	for p in [["map page (plain)", plain], ["map page 7-10 stars", glow], ["map page 10+ stars", hype]]:
		if p[1] == null:
			out("%-22s (no such map here)" % p[0])
			continue
		Rhythia.select_song(p[1])
		yield(measure(p[0]), "completed")
	Rhythia.select_song(plain)
	yield(wait(0.5), "completed")
	menu.open_editor(plain)
	yield(wait(2.5), "completed")
	yield(measure("editor"), "completed")
	var e = menu.get_node_or_null("Editor")
	if e:
		e.m.dirty = false
		e._exit()
	yield(wait(1.0), "completed")
	Rhythia.select_song(plain)
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = ""
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	yield(wait(6.0), "completed")
	yield(measure("gameplay"), "completed")
	out("== done")
	OS.kill(OS.get_process_id())
