extends Node
# Menu frame time with the mouse still and with it moving (a player's hand is never still): the map
# list and map pages, mouse parked vs circling over the screen. The motion goes in as input events
# (Input's mouse position, hover), so the real cursor isn't touched. RR_RES / RR_FULL as ScreenProbe.
# Output: @@OUT@@/move.txt
const OUT = "@@OUT@@/move.txt"
var last_us = 0
var cap = null
var moving = false
var t = 0.0

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

func _process(d):
	var now = OS.get_ticks_usec()
	if cap != null and last_us > 0: cap.append((now - last_us) / 1000.0)
	last_us = now
	if moving:
		t += d
		var sz = get_viewport().get_visible_rect().size
		var ev = InputEventMouseMotion.new()
		ev.position = sz / 2 + Vector2(cos(t * 1.7) * sz.x * 0.3, sin(t * 2.3) * sz.y * 0.3)
		ev.global_position = ev.position
		ev.relative = Vector2(1, 1)
		Input.parse_input_event(ev)

func measure(label:String, move:bool):
	moving = move
	yield(wait(1.5), "completed")
	cap = []
	yield(wait(3.0), "completed")
	var a = cap
	cap = null
	moving = false
	var s = 0.0
	for v in a: s += v
	a.sort()
	out("%-28s mean %6.3f ms (%5.0f fps)  p99 %6.2f" % [label + (" (mouse moving)" if move else " (still)"), s / max(a.size(), 1), 1000.0 / max(s / max(a.size(), 1), 0.001), a[int(a.size() * 0.99)]])

func run():
	Directory.new().remove(OUT)
	yield(wait(25.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("")
	yield(wait(1.0), "completed")
	yield(measure("map list", false), "completed")
	yield(measure("map list", true), "completed")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@":
			Rhythia.select_song(s)
	yield(measure("map page", false), "completed")
	yield(measure("map page", true), "completed")
	out("== done")
	OS.kill(OS.get_process_id())
