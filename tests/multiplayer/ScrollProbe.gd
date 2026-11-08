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

func shot(path:String):
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png(path)

func move_mouse(p:Vector2):
	var ev = InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)

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
			shot("@@OUT@@/scroll_%s.png" % ("down" if dir else "up"))
		stats("scroll " + ("down" if dir else "up") + " %d/s" % hz, a)
		cap = []; proc = []
		yield(wait(1.0), "completed")
		stats("  settling after", cap)
	# hover: the mouse sweeps up and down over the cards (card hover highlights), then rests on one
	var vs = get_viewport().get_visible_rect().size
	var cx = list.rect_global_position.x + list.rect_size.x * 0.6
	cap = []; proc = []
	var t1 = OS.get_ticks_msec()
	while OS.get_ticks_msec() - t1 < 3000:
		var u = (OS.get_ticks_msec() - t1) / 1500.0
		move_mouse(Vector2(cx, vs.y * (0.1 + 0.8 * abs(fmod(u, 2.0) - 1.0))))
		yield(get_tree(), "idle_frame")
	stats("hover sweep", cap)
	cap = null
	# select the second card on screen, rest the mouse on the first (selected + hovered looks)
	var shown = []
	for b in list.btns:
		if is_instance_valid(b) and "song" in b and b.song != null:
			var r = b.get_global_rect()
			if r.position.y > 0 and r.end.y < vs.y: shown.append(b)
	if shown.size() >= 2:
		Rhythia.select_song(shown[1].song)
		yield(wait(0.3), "completed")
		move_mouse(shown[0].get_global_rect().position + shown[0].rect_size * Vector2(0.7, 0.5))
	yield(wait(0.6), "completed")
	var hov = [] # (cards with a hover look: CardLook.gd)
	for b in list.btns:
		if !is_instance_valid(b): continue
		for c in b.get_children():
			if "hover" in c and c.hover > 0.01: hov.append("%s %.2f" % [b.get_node("Name").text, c.hover])
	out("  hovered cards: %s (the real mouse over the window can get in the way)" % str(hov))
	if OS.get_environment("RR_SCROLL_SHOT") == "1":
		yield(VisualServer, "frame_post_draw")
		shot("@@OUT@@/scroll_hover.png")
	out("== done")
	OS.kill(OS.get_process_id())
