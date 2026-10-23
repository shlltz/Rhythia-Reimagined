extends Node
# Which canvas items cost the 2D draw calls (exact numbers, no timing noise): on the title menu and on
# a 10+ star map page, every visible CanvasItem is hidden for a few frames and the drop in 2D draw
# calls / items is recorded (a parent's drop includes its children). Top 18 per screen.
# Output: @@OUT@@/draw.txt
const OUT = "@@OUT@@/draw.txt"

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

func calls() -> float:
	var s = 0.0
	for i in 4:
		yield(get_tree(), "idle_frame")
		if i > 0: s += Performance.get_monitor(Performance.RENDER_2D_DRAW_CALLS_IN_FRAME)
	return s / 3.0

func probe(label:String):
	var base = yield(calls(), "completed")
	out("== %s: %.0f 2D draw calls" % [label, base])
	var items = []
	var stack = [get_tree().root]
	while !stack.empty():
		var n = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is CanvasItem and n.visible and n.is_visible_in_tree(): items.append(n)
	var rows = []
	for n in items:
		if !is_instance_valid(n) or !n.is_visible_in_tree(): continue
		n.visible = false
		var c = yield(calls(), "completed")
		if is_instance_valid(n): n.visible = true
		var sc = n.get_script()
		rows.append([base - c, str(n.get_path()).replace("/root/", ""), sc.resource_path.get_file() if sc else n.get_class()])
	rows.sort_custom(self, "_desc")
	for r in rows.slice(0, min(17, rows.size() - 1)): out("%6.0f  %s  (%s)" % r)

func _desc(a, b): return a[0] > b[0]

func run():
	Directory.new().remove(OUT)
	yield(wait(25.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	for c in menu.get_children(): # (the first-start username panel: not part of the screens measured)
		if c.get_script() and c.get_script().resource_path.ends_with("NamePanel.gd"): c.queue_free()
	yield(wait(1.0), "completed")
	yield(probe("title menu"), "completed")
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("")
	yield(wait(2.0), "completed")
	var cp = get_tree().root.get_node_or_null("ConfirmationPrompt")
	if cp: out("ConfirmationPrompt visible %s modulate.a %.2f text %s" % [cp.visible, cp.modulate.a, str(cp.find_node("L", true, false).text if cp.find_node("L", true, false) else "").left(120)])
	yield(probe("map list"), "completed")
	var sc = get_tree().root.get_node_or_null("StarCache")
	var pick = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and sc and float(sc.get_stars(s)) >= 10.5:
			pick = s
			break
	if pick:
		Rhythia.select_song(pick)
		yield(wait(3.0), "completed")
		yield(probe("map page 10+ stars"), "completed")
	out("== done")
	OS.kill(OS.get_process_id())
