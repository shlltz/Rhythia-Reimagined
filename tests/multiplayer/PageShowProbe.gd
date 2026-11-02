extends Node
# What makes a menu page's first frame slow when it is shown (sidebar switch): the page (RR_PAGE,
# default Settings) is shown and hidden again 5 times and the first frame after showing is timed
# (median); then the same with each part of the page hidden in turn (RR_PAGE_DEPTH levels, default 3).
# Biggest saving first. RR_RES / RR_FULL as ScreenProbe. Output: @@OUT@@/pageshow.txt
const OUT = "@@OUT@@/pageshow.txt"
var last_us = 0
var frames = []

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
	if last_us > 0: frames.append((now - last_us) / 1000.0)
	last_us = now

# first frame after the page shows (median of n)
var other:Control = null # RR_PAGE_SWAP=1: the map list hides as the page shows (a real sidebar switch)
func show_cost(page:Control, n:int = 5):
	var a = []
	for i in n:
		page.visible = false
		if other: other.visible = true
		for k in 6: yield(get_tree(), "idle_frame")
		frames = []
		if other: other.visible = false
		page.visible = true
		for k in 3: yield(get_tree(), "idle_frame")
		a.append(frames[1] if frames.size() > 1 else 0.0) # (frames[0] = the frame the switch happened in)
	a.sort()
	return a[a.size() / 2]

func run():
	Directory.new().remove(OUT)
	yield(wait(25.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("")
	yield(wait(1.5), "completed")
	var pname = OS.get_environment("RR_PAGE") if OS.get_environment("RR_PAGE") != "" else "Settings"
	var page = menu.get_node("Main/" + pname)
	var maps = menu.get_node("Main/Maps")
	maps.visible = false
	if OS.get_environment("RR_PAGE_SWAP") == "1": other = maps
	var base = yield(show_cost(page, 9), "completed")
	out("== %s: first frame shown %.2f ms (median of 9)" % [pname, base])
	var depth = int(OS.get_environment("RR_PAGE_DEPTH")) if OS.get_environment("RR_PAGE_DEPTH") != "" else 3
	var items = []
	var stack = [[page, 0]]
	while !stack.empty():
		var e = stack.pop_back()
		for c in e[0].get_children():
			if c is CanvasItem and c.visible:
				items.append(c)
				if e[1] + 1 < depth: stack.append([c, e[1] + 1])
	var res = []
	for c in items:
		c.visible = false
		var v = yield(show_cost(page), "completed")
		c.visible = true
		res.append([base - v, str(page.get_path_to(c)), c.get_class()])
	res.sort_custom(self, "_by0")
	for r in res.slice(0, min(24, res.size()) - 1):
		out("  %7.2f ms  %s  (%s)" % r)
	out("== done")
	OS.kill(OS.get_process_id())

func _by0(a, b): return a[0] > b[0]
