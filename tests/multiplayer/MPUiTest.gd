extends Node
# multiplayer UI smoke test (one instance): every screen opens, screenshots, host a lobby, pick a
# map through the map page, chat. Output: @@OUT@@/ui_test.txt + ui_*.png
const OUT = "@@OUT@@/ui_test.txt"
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
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/ui_" + n + ".png")

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	ok("scripts compile", load("res://mods/replay/MPMenu.gd").can_instance() and load("res://mods/replay/MPOverlay.gd").can_instance())
	var tm = menu.get_node_or_null("TitleMenu")
	var has_card = false
	if tm:
		for it in tm.items: if it[4] == "multiplayer": has_card = true
	ok("title card", has_card)
	ok("sidebar button", menu.has_node("Sidebar/L/Multiplayer"))
	shot("title")
	tm._close("multiplayer")
	yield(wait(1.5), "completed")
	var m = menu.get_node_or_null("Multiplayer")
	ok("multiplayer opens from the title card", m != null)
	if !m:
		OS.kill(OS.get_process_id())
		return
	ok("home screen", m.screen == "home")
	shot("home")
	m.name_edit.text = "  Tester\u0007Name  "
	m._save_name_btn()
	ok("name saved + sanitised", m.client.my_name == "TesterName", m.client.my_name)
	ok("name persisted", str(load("res://mods/replay/Reimagined.gd").cfg().get("mp_name")) == "TesterName")
	m._go_join()
	yield(wait(2.5), "completed")
	ok("join screen", m.screen == "join")
	shot("join")
	m.j_addr.text = "not an address!"
	m._join()
	ok("bad address refused with a message", m.j_status.text.begins_with("Paste an invite link"))
	m.j_addr.text = "127.0.0.1:47399"
	m._join()
	var t = 0.0
	while t < 9 and m.client.status != "idle":
		yield(wait(0.25), "completed"); t += 0.25
	ok("unreachable host -> clear error", m.client.status == "idle" and "couldn't reach" in m.j_status.text, m.j_status.text)
	shot("join_error")
	m._back()
	m._go_create()
	yield(wait(0.5), "completed")
	ok("create screen", m.screen == "create")
	m.c_port.text = "80"
	m._create()
	ok("bad port refused", "1024" in m.c_status.text)
	m.c_port.text = "47395"
	m.c_name.text = "UI test lobby"
	shot("create")
	m._create()
	t = 0.0
	while t < 5 and !m.client.online():
		yield(wait(0.1), "completed"); t += 0.1
	ok("hosting -> lobby screen", m.client.online() and m.screen == "lobby" and m.client.hosting())
	yield(wait(0.6), "completed")
	ok("lobby shows its name + room code", m.l_name.text == "UI test lobby" and "ROOM CODE" in m.l_sub.text, m.l_sub.text)
	ok("one player listed", m.l_players.get_child_count() == 1)
	ok("start blocked without a map", m.l_start_btn.disabled and "map" in m.l_why.text.to_lower())
	m.l_chat_in.text = "hello lobby"
	m._chat_send("hello lobby")
	yield(wait(0.5), "completed")
	ok("chat line shown", m.l_chat.get_child_count() >= 2)
	shot("lobby_empty")
	# pick a map through the real map page
	m._pick_begin()
	yield(wait(0.6), "completed")
	ok("picking hides the lobby, shows the bar", !m.root.visible and m.pick_bar.visible)
	var si = menu.get_node("Main/Maps/Results/Results")
	ok("map page has PICK FOR LOBBY", si.mp_pick_btn != null and si.mp_pick_btn.visible and !si.run_btn.visible)
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	Rhythia.select_song(song)
	yield(wait(0.8), "completed")
	shot("pick")
	si._rr_mp_pick()
	yield(wait(1.0), "completed")
	ok("map picked -> back in the lobby", m.root.visible and !m.pick_bar.visible and str(m.client.lobby.get("map", {}).get("id", "")) == song.id)
	ok("Start button restored on the map page", si.run_btn.visible and !si.mp_pick_btn.visible)
	ok("host has the map", m.client.my_have == "ok")
	ok("start possible alone", !m.l_start_btn.disabled, m.l_why.text)
	m._speed(0.05)
	m._mod_toggle(true, "mod_ghost")
	yield(wait(0.6), "completed")
	ok("rules change shown", "1.05x" in m.l_rules.text and "Ghost" in m.l_rules.text, m.l_rules.text)
	shot("lobby_map")
	m._set_results(true)
	yield(wait(0.3), "completed")
	shot("results_empty")
	m._set_results(false)
	# leave (needs two presses)
	m._back()
	ok("leave asks to confirm", m.client.online())
	m._back()
	yield(wait(0.5), "completed")
	ok("left: home screen, not hosting", m.screen == "home" and !m.client.hosting() and m.client.status == "idle")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
