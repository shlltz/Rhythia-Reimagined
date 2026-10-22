extends Node
# Online lobby through a real relay, instance B = guest joining with the invite link (MPRelayA.gd).
# The relay adds 40-55 ms to everything it sends (relay_e2e.py), so the pings shown must include it.
# Also: B's own connection drops and comes back, the host's relay link drops, a wrong-version join, and
# joins to a closed room / an unknown code (refused, no retry loop). Output @@OUT@@/relay_b.txt
const OUT = "@@OUT@@/relay_b.txt"
const ROOM = "@@S@@/t/relay_room.txt"
const B_OK = "@@S@@/t/relay_b_ok.txt"
const RELAY = "ws://127.0.0.1:47390"
const DELAY = 40
const Relay = preload("res://mods/replay/MPRelay.gd")
var passed = 0
var failed = 0
var saw_reconnecting = 0
var CL = null

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
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
	if OS.window_minimized: return
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/" + n + ".png")

func has_chat(C, text):
	for e in C.chat:
		if e.text == text: return true
	return false

func _status(_w):
	if CL.status == "reconnecting": saw_reconnecting += 1

func read(path):
	var f = File.new()
	if f.open(path, File.READ) != OK: return ""
	var s = f.get_as_text(); f.close()
	return s.strip_edges()

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	menu.get_node("TitleMenu")._close("multiplayer")
	yield(wait(1.5), "completed")
	var m = menu.get_node("Multiplayer")
	var C = m.client
	CL = C
	C.connect("changed", self, "_status")
	m.name_edit.text = "GuestB"
	m._save_name_btn()
	var t = 0.0
	var inv = ""
	while t < 60 and inv == "":
		yield(wait(0.25), "completed"); t += 0.25
		inv = read(ROOM)
	ok("invite from A", inv != "", inv)
	m._go_join()
	m.j_relay.text = "" # (the invite carries the relay)
	m.j_addr.text = inv
	m._join()
	ok("join shows what it does", "Joining room" in m.j_status.text, m.j_status.text)
	t = 0.0
	while t < 15 and !C.online():
		yield(wait(0.1), "completed"); t += 0.1
	ok("B in A's lobby through the relay", C.online() and C.relayed() and m.screen == "lobby", "%.1f s" % t)
	ok("no private addresses in what B sees", typeof(C.lobby.get("addr")) == TYPE_ARRAY and C.lobby.addr.empty() and !("192.168." in to_json(C.lobby)))
	yield(wait(7.0), "completed")
	m._refresh_status()
	out("B status: " + m.status_lbl.text)
	ok("ping measured end to end, includes the relay's delay", C.rtt >= 2 * DELAY and C.rtt < 1500, C.rtt)
	ok("relay ping measured", C.relay_rtt() >= DELAY and C.relay_rtt() <= C.rtt + 60, C.relay_rtt())
	ok("jitter measured", C.jitter() >= 0, C.jitter())
	ok("status says RELAYED with the real ping", "RELAYED" in m.status_lbl.text and ("%d MS" % C.rtt) in m.status_lbl.text, m.status_lbl.text)
	yield(shot("RB_lobby"), "completed")
	C.send_chat("hello from B")
	t = 0.0
	while t < 20 and !has_chat(C, "hello from A"):
		yield(wait(0.25), "completed"); t += 0.25
	ok("chat from A received", has_chat(C, "hello from A"))
	t = 0.0
	while t < 30 and C.my_have != "ok":
		yield(wait(0.25), "completed"); t += 0.25
	ok("map verified against the host's", C.my_have == "ok")
	yield(wait(0.4), "completed")
	m._ready_toggle(true)
	Rhythia.set("mod_nofail", false)
	t = 0.0
	while t < 60 and C.phase != "playing":
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	ok("match started through the relay", C.phase == "playing")
	yield(wait(2.0), "completed")
	Rhythia.set("mod_nofail", false) # (something turns it off mid-match: the client puts it back)
	yield(wait(0.5), "completed")
	ok("No Fail enforced in the match", Rhythia.mod_nofail)
	t = 0.0
	while t < 120 and !(C.results_match == C.match_id and C.results.size() == 3):
		yield(wait(0.5), "completed"); t += 0.5
	ok("results with all 3 players", C.results.size() == 3)
	yield(wait(2.0), "completed")
	ok("own settings back after the match", !Rhythia.mod_nofail)
	m = get_tree().root.get_node("Menu/Multiplayer") # (the menu is built again after the match)
	# a network blip on B's side: the connection dies, B reconnects through the relay as the same player
	var pid0 = C.pid
	saw_reconnecting = 0
	C.peer._fail("lost", "test: network cut")
	t = 0.0
	while t < 25 and !(C.online() and saw_reconnecting > 0):
		yield(wait(0.1), "completed"); t += 0.1
	ok("B reconnected by itself, same player", C.online() and saw_reconnecting > 0 and C.pid == pid0, "%.1f s" % t)
	var f = File.new()
	f.open(B_OK, File.WRITE); f.store_string("ok"); f.close()
	# A's relay link drops next: B sees it and is back once A's tunnel returns
	saw_reconnecting = 0
	t = 0.0
	while t < 30 and saw_reconnecting == 0:
		yield(wait(0.1), "completed"); t += 0.1
	ok("B noticed the host's relay drop", saw_reconnecting > 0)
	t = 0.0
	while t < 40 and !C.online():
		yield(wait(0.1), "completed"); t += 0.1
	ok("B back after the host's tunnel returned", C.online() and C.pid == pid0, "%.1f s" % t)
	# a different multiplayer version is refused by the relay with a reason
	var code = Relay.parse_invite(inv).code
	var g = Relay.Guest.new(RELAY, code, "rr-mp-0")
	t = 0.0
	while t < 10 and g.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		yield(wait(0.1), "completed"); t += 0.1
	ok("wrong multiplayer version refused, explained", g.error_code == "game_version" and "versions" in g.error_text, g.error_text)
	g = null
	# the host ends the lobby: B is told, then the code is dead
	t = 0.0
	while t < 90 and C.status != "idle":
		yield(wait(0.25), "completed"); t += 0.25
	ok("lobby end reaches B", C.status == "idle", C.status_text)
	yield(wait(1.0), "completed")
	C.join_online(RELAY, code, "")
	t = 0.0
	while t < 10 and C.status != "idle":
		yield(wait(0.1), "completed"); t += 0.1
	ok("closed room: refused at once, no retry loop", C.status == "idle" and "closed" in C.status_text, C.status_text)
	m._go_join()
	m.j_addr.text = "ZZZZ-ZZZZ"
	m.j_relay.text = RELAY
	m._join()
	t = 0.0
	while t < 10 and C.status != "idle":
		yield(wait(0.1), "completed"); t += 0.1
	yield(wait(0.3), "completed")
	ok("unknown code: explained", C.status == "idle" and "No room" in m.j_status.text, m.j_status.text)
	yield(shot("RB_unknown"), "completed")
	m.j_relay.text = ""
	m.j_addr.text = "ABCD-EFGH"
	m._join()
	ok("bare code without a relay: asks for the invite link", "invite link" in m.j_status.text and C.status == "idle", m.j_status.text)
	out("== totals: %d passed, %d failed" % [passed, failed])
	yield(wait(1.0), "completed")
	OS.kill(OS.get_process_id())
