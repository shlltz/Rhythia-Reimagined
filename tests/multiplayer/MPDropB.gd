extends Node
# guest whose host dies mid-match
const OUT = "@@OUT@@/drv.txt"
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
	f.seek_end(); f.store_line("[%7.1f] %s" % [OS.get_ticks_msec() / 1000.0, s]); f.close()
func ok(n, c, d = ""):
	if c: passed += 1
	else: failed += 1
	out(("PASS  " if c else "FAIL  ") + n + ("  " + str(d) if str(d) != "" else ""))
func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")
func shot(n):
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/" + n + ".png")
func run():
	Directory.new().remove(OUT)
	yield(wait(7.0), "completed")
	Rhythia.set("mod_nofail", false)
	var menu = get_tree().root.get_node("Menu")
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	yield(wait(1.0), "completed")
	menu.open_multiplayer()
	yield(wait(1.0), "completed")
	var m = menu.get_node("Multiplayer")
	var C = m.client
	m.name_edit.text = "GuestB"; m._save_name_btn()
	m._go_join()
	m.j_addr.text = "127.0.0.1:47381"
	m._join()
	var t = 0.0
	while t < 30 and C.my_have != "ok":
		yield(wait(0.25), "completed"); t += 0.25
	m._ready_toggle(true)
	t = 0.0
	while t < 60 and C.phase != "playing":
		yield(wait(0.1), "completed"); t += 0.1
	ok("guest playing", C.phase == "playing")
	t = 0.0
	while t < 20 and C.status == "online":
		yield(wait(0.25), "completed"); t += 0.25
	ok("guest notices the host is gone", C.status != "online", "%s after %.1f s" % [C.status, t])
	yield(wait(1.0), "completed")
	shot("B_hostgone_game")
	ok("guest's game keeps running", is_instance_valid(C.game) and !C.game.ending and Rhythia.mod_nofail)
	t = 0.0
	while t < 90 and !get_tree().root.has_node("Menu/Multiplayer"):
		yield(wait(0.5), "completed"); t += 0.5
	ok("back in the menu after the map", get_tree().root.has_node("Menu/Multiplayer"), "%.0f s" % t)
	yield(wait(1.0), "completed")
	var mm = get_tree().root.get_node_or_null("Menu/Multiplayer")
	ok("multiplayer screen shows home (no lobby)", mm != null and mm.screen == "home", mm.screen if mm else "")
	ok("guest's own settings back", !Rhythia.mod_nofail and C.snapshot.empty() and !File.new().file_exists("user://rr_mp_restore.json"))
	ok("client idle, match cleared", C.status == "idle" and C.phase == "none", [C.status, C.phase])
	shot("B_hostgone_menu")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
