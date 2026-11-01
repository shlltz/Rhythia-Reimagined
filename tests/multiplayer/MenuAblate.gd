extends Node
# What a menu screen's frame time is made of: selects @@MAP1@@ (its map page shows), then hides one
# visible canvas item at a time (children of the menu scene and of the root's CanvasLayers, down to
# RR_MENU_DEPTH levels, default 2; RR_MENU_ROOT=path: only under that node) for a short window, with a
# control window before each.
# Reports the frame time saved per item, biggest first. RR_MENU_PROC=1 also switches the item's
# processing off (script cost). Output: @@OUT@@/menuablate.txt
const OUT = "@@OUT@@/menuablate.txt"
const WIN = 1.2
var last_us = 0
var frames = []
var capturing = false

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
	call_deferred("run")

func _process(_d):
	OS.vsync_enabled = false
	Engine.target_fps = 0
	var u = OS.get_ticks_usec()
	if capturing and last_us > 0: frames.append((u - last_us) / 1000.0)
	last_us = u

func measure() -> float:
	frames = []; last_us = 0
	capturing = true
	yield(wait(WIN), "completed")
	capturing = false
	if frames.size() == 0: return 0.0
	var f = frames.duplicate(); f.sort()
	return f[f.size() / 2] # (median: robust against single hitches)

func song(file):
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == file: return s
	return null

func collect(n:Node, depth:int, into:Array):
	for c in n.get_children():
		if c == self: continue
		if (c is CanvasItem and c.visible) or c is CanvasLayer:
			if c is CanvasItem: into.append(c)
			if depth > 1: collect(c, depth - 1, into)

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var t = 0.0
	while t < 30:
		yield(wait(0.25), "completed"); t += 0.25
		var sc = get_tree().current_scene
		if !sc or sc.name != "Menu": continue
		var tm = sc.get_node_or_null("TitleMenu")
		if tm and tm.visible:
			tm._close("")
			yield(wait(1.0), "completed")
		break
	var s = song("@@MAP1@@")
	if s: Rhythia.select_song(s)
	yield(wait(4.0), "completed")
	var depth = int(OS.get_environment("RR_MENU_DEPTH")) if OS.get_environment("RR_MENU_DEPTH") != "" else 2
	var proc = OS.get_environment("RR_MENU_PROC") == "1"
	var items = []
	var root_path = OS.get_environment("RR_MENU_ROOT") # (only under this node, e.g. Menu/Main/Maps)
	if root_path != "":
		var r = get_tree().root.get_node_or_null(root_path)
		if r: collect(r, depth, items)
	else:
		collect(get_tree().current_scene, depth, items)
		for c in get_tree().root.get_children():
			if c is CanvasLayer and c != get_tree().current_scene: collect(c, depth, items)
	var base = yield(measure(), "completed")
	out("== menu ablate @@NAME@@: %d items, median frame %.3f ms (%s)" % [items.size(), base, s.name if s else "no map"])
	var rows = []
	for c in items:
		if !is_instance_valid(c) or !c.visible: continue
		var ctl = yield(measure(), "completed")
		c.visible = false
		var was_p = c.is_processing()
		if proc: c.set_process(false)
		yield(wait(0.15), "completed")
		var off = yield(measure(), "completed")
		if is_instance_valid(c):
			c.visible = true
			if proc: c.set_process(was_p)
		yield(wait(0.15), "completed")
		rows.append([ctl - off, str(c.get_path()).replace("/root/", ""), ctl])
	rows.sort_custom(self, "_desc")
	for r in rows: out("%7.3f ms  (ctl %.3f)  %s" % [r[0], r[2], r[1]])
	out("== done")
	OS.kill(OS.get_process_id())

func _desc(a, b): return a[0] > b[0]
