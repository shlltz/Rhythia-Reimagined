extends Node
# two-instance multiplayer test, instance B = guest (finds A on the LAN). Output @@OUT@@/drv.txt
const OUT = "@@OUT@@/drv.txt"
var passed = 0
var failed = 0

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	OS.window_position = Vector2(640, 330)
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

func has_chat(C, text):
	for e in C.chat:
		if e.text == text: return true
	return false

func run():
	Directory.new().remove(OUT)
	yield(wait(7.0), "completed")
	# this player's own settings, which the match must override and then give back
	Rhythia.set("mod_nofail", false)
	Rhythia.set("mod_sudden_death", true)
	var my_hw = Rhythia.get("hitwindow_ms")
	var menu = get_tree().root.get_node("Menu")
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	yield(wait(1.0), "completed")
	menu.open_multiplayer()
	yield(wait(1.0), "completed")
	var m = menu.get_node("Multiplayer")
	var C = m.client
	m.name_edit.text = "GuestB"
	m._save_name_btn()
	m._go_join()
	var t = 0.0
	var found = null
	while t < 25 and !found:
		yield(wait(0.25), "completed"); t += 0.25
		for k in C.lan:
			if C.lan[k].name == "Two PC test": found = C.lan[k]
	ok("LAN discovery finds A's lobby", found != null, C.lan_error if !found else "%s:%d after %.1f s" % [found.ip, found.port, t])
	shot("B_join")
	if found: m._lan_join(found.ip, found.port, false)
	else:
		m.j_addr.text = "127.0.0.1:47380"
		m._join()
	t = 0.0
	while t < 10 and !C.online():
		yield(wait(0.1), "completed"); t += 0.1
	ok("B online in A's lobby", C.online() and m.screen == "lobby")
	yield(wait(1.0), "completed")
	ok("B sees 2 players, A host", C.players.size() == 2 and !C.is_host() and str(C.players[0].name) == "HostA")
	t = 0.0
	while t < 20 and !has_chat(C, "hello from A"):
		yield(wait(0.25), "completed"); t += 0.25
	ok("chat from A received", has_chat(C, "hello from A"))
	C.send_chat("hello from B")
	t = 0.0
	while t < 20 and C.my_have != "missing":
		yield(wait(0.25), "completed"); t += 0.25
	ok("B: first map missing locally", C.my_have == "missing")
	yield(wait(0.5), "completed")
	ok("B can't ready without the map", m.l_ready_btn.disabled)
	shot("B_missing")
	t = 0.0
	while t < 20 and C.my_have != "ok":
		yield(wait(0.25), "completed"); t += 0.25
	ok("B: second map ok", C.my_have == "ok")
	yield(wait(0.4), "completed")
	m._ready_toggle(true)
	shot("B_lobby")
	# match 1
	t = 0.0
	while t < 60 and C.phase != "playing":
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	out("GO_SERVER %d" % C.server_now())
	ok("B: match 1 started", C.phase == "playing")
	ok("session rules applied: No Fail on, Sudden Death off", Rhythia.mod_nofail and !Rhythia.mod_sudden_death)
	ok("match timing = host's hit window", abs(float(Rhythia.get("hitwindow_ms")) - float(C.match_rules.hw)) < 0.01)
	yield(wait(2.0), "completed")
	Rhythia.set("mod_nofail", false) # something turns No Fail off mid-match ...
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	ok("... and the session turns it back on", Rhythia.mod_nofail)
	yield(wait(5.0), "completed")
	shot("B_game")
	var g = C.game
	ok("B is missing notes but still playing (No Fail)", is_instance_valid(g) and g.misses > 3 and !g.ending, [g.misses if is_instance_valid(g) else -1])
	var ab = {}
	for e in C.board:
		if str(e.name) == "HostA": ab = e
	ok("B sees A's live score", int(ab.get("score", 0)) > 0, ab)
	t = 0.0
	while t < 90 and !(C.results_match == C.match_id and C.results.size() == 2):
		yield(wait(0.5), "completed"); t += 0.5
	ok("B: match 1 results with both players", C.results.size() == 2, C.results)
	yield(wait(3.0), "completed")
	var mm = get_tree().root.get_node_or_null("Menu/Multiplayer")
	ok("B back in the lobby with results", mm != null and mm.results_on)
	ok("B's own settings restored (No Fail off, Sudden Death on, hit window)", !Rhythia.mod_nofail and Rhythia.mod_sudden_death and abs(float(Rhythia.get("hitwindow_ms")) - float(my_hw)) < 0.01)
	ok("restore file removed", !File.new().file_exists("user://rr_mp_restore.json"))
	shot("B_results")
	mm._r_again()
	# match 2
	t = 0.0
	while t < 60 and C.phase != "playing":
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	out("GO2_SERVER %d" % C.server_now())
	ok("B: match 2 started", C.phase == "playing")
	t = 0.0
	while t < 120 and !(C.results_match == C.match_id and C.results.size() == 2):
		yield(wait(0.5), "completed"); t += 0.5
	ok("B: match 2 results", C.results_match == C.match_id and C.results.size() == 2, C.results)
	yield(wait(2.0), "completed")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id()) # (no goodbye: the host has to notice the lost connection)
