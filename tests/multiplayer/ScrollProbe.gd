extends Node
# Map list scrolling: mouse wheel steps sent over the map list (RR_SCROLL_HZ steps a second, default
# 20; down then up), frame times while scrolling vs still: mean, p99, worst, frames over 16.7 ms.
# Also the time inside pg_down / pg_up (the card swap) per step. RR_RES / RR_FULL as ScreenProbe.
# Output: @@OUT@@/scroll.txt
const OUT = "@@OUT@@/scroll.txt"
var last_us = 0
var cap = null
var proc = []

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = OS.get_environment("RR_FULL") == "1"
	var res = OS.get_environment("RR_RES").split("x")
	if !OS.window_fullscreen: OS.window_size = Vector2(int(res[0]), int(res[1])) if res.size() == 2 else Vector2(1280, 720)
	OS.vsync_enabled = false
	Engine.target_fps = 0
	call_deferred("run")

func _process(_d):
	var now = OS.get_ticks_usec()
	if cap != null and last_us > 0:
		cap.append((now - last_us) / 1000.0)
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	last_us = now

func wheel(list:Control, down:bool):
	var ev = InputEventMouseButton.new()
	ev.button_index = BUTTON_WHEEL_DOWN if down else BUTTON_WHEEL_UP
	ev.pressed = true
	ev.position = list.get_global_rect().position + list.get_global_rect().size / 2
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	var up = ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)

func stats(label:String, a:Array):
	var p = proc
	var s = 0.0
	var slow = 0
	for v in a:
		s += v
		if v > 16.7: slow += 1
	var b = a.duplicate()
	b.sort()
	var ps = 0.0
	for v in p: ps += v
	out("%-22s mean %6.2f ms (%5.0f fps)  p99 %6.2f  worst %6.2f  over 16.7 ms: %d / %d  process step mean %.2f ms" % [label,
		s / max(a.size(), 1), 1000.0 / max(s / max(a.size(), 1), 0.001), b[int(b.size() * 0.99)] if b.size() else 0.0,
		b[-1] if b.size() else 0.0, slow, a.size(), ps / max(p.size(), 1)])

func run():
	Directory.new().remove(OUT)
	yield(wait(25.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("")
	yield(wait(2.0), "completed")
	var list = menu.find_node("VBoxContainer", true, false)
	var ml = menu.get_node_or_null("Main/Maps/MapRegistry/S/VBoxContainer")
	if ml: list = ml
	out("== maps in list: %d, cards: %d" % [list.disp.size(), list.btns.size()])
	cap = []; proc = []
	yield(wait(2.0), "completed")
	stats("still", cap)
	var hz = float(OS.get_environment("RR_SCROLL_HZ")) if OS.get_environment("RR_SCROLL_HZ") != "" else 20.0
	for dir in [true, false]:
		cap = []; proc = []
		var t0 = OS.get_ticks_msec()
		while OS.get_ticks_msec() - t0 < 3000:
			wheel(list, dir)
			yield(wait(1.0 / hz), "completed")
		var a = cap
		cap = null
		out("  cur_map %d, list y %.1f" % [list.cur_map, list.rect_position.y])
		if OS.get_environment("RR_SCROLL_SHOT") == "1":
			wheel(list, dir)
			for k in 3: yield(get_tree(), "idle_frame")
			yield(VisualServer, "frame_post_draw")
			get_viewport().get_texture().get_data().save_png("@@OUT@@/scroll_%s.png" % ("down" if dir else "up"))
		stats("scroll " + ("down" if dir else "up") + " %d/s" % hz, a)
		cap = []; proc = []
		yield(wait(1.0), "completed")
		stats("  settling after", cap)
	out("== done")
	OS.kill(OS.get_process_id())
