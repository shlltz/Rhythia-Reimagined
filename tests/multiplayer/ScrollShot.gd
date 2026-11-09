extends Node
# Map list carousel look: screenshots still, mid-scroll (3 wheel notches) and settled, and the
# list's scroll position over the scroll (smooth = no jumps). Output @@OUT@@/s0.png s1.png s2.png, shot.txt
var list = null
var trail = []
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_size = Vector2(1920, 1080)
	call_deferred("run")
func shot(p):
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png(p)
func wheel(down:bool):
	var ev = InputEventMouseButton.new()
	ev.button_index = BUTTON_WHEEL_DOWN if down else BUTTON_WHEEL_UP
	ev.pressed = true
	ev.position = list.get_parent().get_global_rect().position + list.get_parent().get_global_rect().size / 2
	ev.global_position = ev.position
	Input.parse_input_event(ev)
func _process(_d):
	if list and trail.size() < 400: trail.append(list.rr_pos)
func run():
	yield(get_tree().create_timer(24.0), "timeout")
	var menu = get_tree().root.get_node("Menu")
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	yield(get_tree().create_timer(2.0), "timeout")
	list = menu.get_node("Main/Maps/MapRegistry/S/VBoxContainer")
	shot("@@OUT@@/s0.png")
	trail.clear()
	for i in 3:
		wheel(true)
		yield(get_tree().create_timer(0.04), "timeout")
	yield(get_tree().create_timer(0.08), "timeout")
	shot("@@OUT@@/s1.png")
	yield(get_tree().create_timer(1.0), "timeout")
	shot("@@OUT@@/s2.png")
	# a drag: press on a card, pull up 300 px over 0.25 s, let go (a fling)
	var c = list.btns[list.btns.size() / 2].get_node("Select")
	var p0 = c.get_global_rect().position + c.get_global_rect().size / 2
	var before = list.rr_pos
	var ev = InputEventMouseButton.new()
	ev.button_index = BUTTON_LEFT; ev.pressed = true; ev.position = p0; ev.global_position = p0
	Input.parse_input_event(ev)
	for i in 25:
		yield(get_tree().create_timer(0.01), "timeout")
		var m = InputEventMouseMotion.new()
		m.position = p0 - Vector2(0, 12 * (i + 1)); m.global_position = m.position
		m.button_mask = BUTTON_MASK_LEFT
		Input.parse_input_event(m)
	var mid = list.rr_pos
	var up = ev.duplicate(); up.pressed = false; up.position = p0 - Vector2(0, 300); up.global_position = up.position
	Input.parse_input_event(up)
	yield(get_tree().create_timer(1.5), "timeout")
	var sel_ok = Rhythia.selected_song
	var f = File.new()
	f.open("@@OUT@@/shot.txt", File.WRITE)
	var big = 0.0
	for i in range(1, trail.size()): big = max(big, abs(trail[i] - trail[i - 1]))
	f.store_line("frames %d, from %.2f to %.2f, biggest step a frame %.3f cards" % [trail.size(), trail[0] if trail.size() else 0.0, trail[-1] if trail.size() else 0.0, big])
	f.store_line("drag: %.2f -> %.2f at release -> %.2f settled (selected %s)" % [before, mid, list.rr_pos, sel_ok.name if sel_ok else "-"])
	f.close()
	OS.kill(OS.get_process_id())
