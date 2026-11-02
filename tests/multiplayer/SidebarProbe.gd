extends Node
# Sidebar page switches: presses every sidebar button (twice: first open, then again), and records the
# frames of the next 0.6 s (the page's slide-in): the slowest frame, the mean, frames over 16.7 ms,
# and how long the press itself took. Back to Maps between pages. RR_RES / RR_FULL as ScreenProbe.
# Output: @@OUT@@/sidebar.txt
const OUT = "@@OUT@@/sidebar.txt"
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
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0) # (last frame's idle-step time: scripts + layout)
	last_us = now

func press(b:BaseButton, label:String):
	yield(wait(0.8), "completed")
	cap = []
	proc = []
	var t0 = OS.get_ticks_usec()
	b.emit_signal("pressed")
	var call_ms = (OS.get_ticks_usec() - t0) / 1000.0
	yield(wait(0.6), "completed")
	var a = cap
	cap = null
	var s = 0.0
	var slow = 0
	var worst = 0.0
	var wi = -1
	for i in a.size():
		var v = a[i]
		if v > worst: wi = i
		s += v
		worst = max(worst, v)
		if v > 16.7: slow += 1
	out("%-26s press %6.1f ms | worst frame %6.1f ms (frame %d, process step next frame %.1f ms)  mean %5.2f  frames %4d  over 16.7 ms: %d" % [label, call_ms, worst, wi, proc[wi + 1] if wi + 1 < proc.size() else -1.0, s / max(a.size(), 1), a.size(), slow])

func run():
	Directory.new().remove(OUT)
	yield(wait(25.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("")
	yield(wait(1.5), "completed")
	var l = menu.get_node("Sidebar/L")
	var maps = null
	var btns = []
	for c in l.get_children():
		if c is BaseButton and c.visible:
			btns.append(c)
			if c.name in ["Results", "Maps"]: maps = c
	out("== sidebar: " + str(btns.size()) + " buttons, maps = " + (maps.name if maps else "?"))
	var only = OS.get_environment("RR_SB_ONLY").split(",", false) # (button names; default: the pages inside the menu)
	if only.empty(): only = ["Settings", "ContentMgr", "Credits", "Language"]
	for round_i in 3:
		for b in btns:
			if b == maps or !(b.name in only): continue
			yield(press(b, "%s %s" % [b.name, ["(1st)", "(2nd)", "(3rd)"][round_i]]), "completed")
			# close whatever opened over the menu, back to the map list
			for c in menu.get_children():
				if c.has_method("_close") and c.name != "TitleMenu" and c.visible: c.call("_close") if c.get_method_list().size() > 0 else null
			if maps: yield(press(maps, "  back to " + maps.name), "completed")
	out("== done")
	OS.kill(OS.get_process_id())
