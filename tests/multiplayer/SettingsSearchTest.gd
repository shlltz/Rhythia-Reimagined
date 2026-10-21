extends Node
# settings search box (SettingsStyle.gd): filters rows across tabs, counts per tab, jumps to the
# tab with matches, Esc clears, typing anywhere focuses it. Output: @@OUT@@/search.txt + s_*.png
const OUT = "@@OUT@@/search.txt"
var passed = 0
var failed = 0

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func ok(n, c, d = ""):
	if c: passed += 1
	else: failed += 1
	out(("PASS  " if c else "FAIL  ") + n + ("  " + str(d) if str(d) != "" else ""))

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func shot(n):
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/s_" + n + ".png")

func key(sc, uni = 0):
	var e = InputEventKey.new()
	e.scancode = sc
	e.unicode = uni
	e.pressed = true
	get_tree().input_event(e)
	e = e.duplicate()
	e.pressed = false
	get_tree().input_event(e)

func row_visible(tabs, path):
	var n = tabs.get_node_or_null(path)
	return n != null and n.visible

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var menu = get_tree().current_scene
	if "@@NAME@@" == "classic":
		if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
		get_tree().change_scene("res://scenes/menu/oldmenu2.tscn")
		yield(wait(3.0), "completed")
		menu = get_tree().current_scene
	menu.show_title()
	yield(wait(1.0), "completed")
	menu.get_node("TitleMenu")._close("settings")
	yield(wait(1.5), "completed")
	var ss = menu.get_node("SettingsStyle")
	var tabs = menu.get_node("Main/Settings/S/F/TabContainer")
	ok("settings page open with a search box", menu.get_node("Main/Settings").is_visible_in_tree() and ss.search != null and ss.search.is_visible_in_tree())
	shot("empty")
	# typing anywhere goes into the box
	ss.search.release_focus()
	key(KEY_F, "f".ord_at(0))
	key(KEY_O, "o".ord_at(0))
	key(KEY_V, "v".ord_at(0))
	yield(wait(0.3), "completed")
	ok("typing on the page fills the search box", ss.search.text == "fov" and ss.search.has_focus(), ss.search.text)
	ok("matching rows shown", row_visible(tabs, "Gameplay/Camera/Group/H/FOV") and row_visible(tabs, "Gameplay/Camera/Group/H/HitFOV"))
	ok("other rows hidden", !row_visible(tabs, "Gameplay/Camera/Group/H/Sensitivity") and !row_visible(tabs, "Gameplay/Modifiers"))
	ok("tab counts + result line", "(" in ss.buttons[0].title and "matching" in ss.search_info.text, ss.search_info.text)
	shot("fov")
	# a term only in another tab: the page jumps there
	ss.search.text = "note scale"
	ss._search(ss.search.text)
	yield(wait(0.3), "completed")
	ok("jumps to the tab with matches", tabs.get_current_tab_control().name == "Notes" and row_visible(tabs, "Notes/Notes/Group/H/NoteScale"), tabs.get_current_tab_control().name)
	ok("tabs without matches dimmed", ss.buttons[0].modulate.a < 0.5)
	shot("notes")
	ss.search.text = "zzqx"
	ss._search(ss.search.text)
	ok("no match message", ss.search_info.text == "no settings match")
	# Esc clears and restores everything
	key(KEY_ESCAPE)
	yield(wait(0.3), "completed")
	ok("Esc clears the search", ss.search.text == "" and menu.get_node("Main/Settings").is_visible_in_tree())
	ok("all rows back", row_visible(tabs, "Gameplay/Camera/Group/H/Sensitivity") and row_visible(tabs, "Gameplay/Modifiers") and row_visible(tabs, "Notes/Notes/Group/H/NoteScale"))
	ok("tab titles back", !("(" in ss.buttons[0].title) and ss.buttons[0].modulate.a == 1.0)
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
