extends Node
# Right-click on a map card: the card's map gets selected and the map actions menu (Delete Map ...) opens
# at the cursor. Nothing is deleted. Output: @@OUT@@/cardmenu.txt + cardmenu.png
const OUT = "@@OUT@@/cardmenu.txt"

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")

func run():
	Directory.new().remove(OUT)
	yield(wait(25.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("")
	yield(wait(2.0), "completed")
	var list = menu.get_node("Main/Maps/MapRegistry/S/VBoxContainer")
	var card = null
	for b in list.btns:
		if is_instance_valid(b) and b.get("song") and b.song != Rhythia.selected_song and b.get_global_rect().intersects(get_viewport().get_visible_rect()):
			card = b
			break
	if !card:
		out("FAIL no other card on screen")
		OS.kill(OS.get_process_id())
	var at = card.get_global_rect().position + card.get_global_rect().size / 2
	for p in [true, false]:
		var ev = InputEventMouseButton.new()
		ev.button_index = BUTTON_RIGHT
		ev.pressed = p
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)
	yield(wait(0.6), "completed")
	out(("PASS" if Rhythia.selected_song == card.song else "FAIL") + " right-click selects the card's map")
	var pm = null
	for n in get_tree().root.get_children():
		pass
	var stack = [menu]
	while !stack.empty():
		var n = stack.pop_back()
		if n is PopupMenu and n.visible: pm = n
		for c in n.get_children(): stack.append(c)
	var items = []
	if pm:
		for i in pm.get_item_count(): items.append(pm.get_item_text(i))
	out(("PASS" if pm and "delete map" in str(items).to_lower() else "FAIL") + " actions menu open at the cursor: %s %s" % [str(pm.rect_position) if pm else "-", str(items)])
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png("@@OUT@@/cardmenu.png")
	if pm: pm.hide()
	out("== done")
	OS.kill(OS.get_process_id())
