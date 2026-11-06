extends Node
# Smooth wheel scrolling on the settings page: 3 notches down, then the scroll position frame by frame
# (it should ease in many small steps, not jump), and frame times while it moves.
# Output: @@OUT@@/smooth.txt
const OUT = "@@OUT@@/smooth.txt"

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.vsync_enabled = false
	Engine.target_fps = 0
	call_deferred("run")

func run():
	Directory.new().remove(OUT)
	yield(wait(25.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("settings")
	yield(wait(2.0), "completed")
	var sc = menu.get_node_or_null("Main/Settings/S")
	out("settings visible %s, smooth attached %s, max %.0f" % [sc.is_visible_in_tree(), sc.has_node("SmoothScroll"), sc.get_v_scrollbar().max_value - sc.get_v_scrollbar().page])
	out("before: %d" % sc.scroll_vertical)
	sc.scroll_vertical = 0
	yield(wait(0.5), "completed")
	out("reset: %d" % sc.scroll_vertical)
	var c = sc.get_global_rect().position + sc.get_global_rect().size / 2
	for i in 3:
		var ev = InputEventMouseButton.new()
		ev.button_index = BUTTON_WHEEL_DOWN
		ev.pressed = true
		ev.factor = 1.0
		ev.position = c
		ev.global_position = c
		Input.parse_input_event(ev)
	var vals = []
	var worst = 0.0
	var t0 = OS.get_ticks_usec()
	var last = t0
	while OS.get_ticks_usec() - t0 < 600000:
		yield(get_tree(), "idle_frame")
		var now = OS.get_ticks_usec()
		worst = max(worst, (now - last) / 1000.0)
		last = now
		if vals.empty() or vals[-1] != sc.scroll_vertical: vals.append(sc.scroll_vertical)
	out("distinct positions while easing: %d, first %s, last %s, worst frame %.2f ms" % [vals.size(), str(vals.slice(0, min(6, vals.size()) - 1)), str(vals[-1]), worst])
	out("== done")
	OS.kill(OS.get_process_id())
