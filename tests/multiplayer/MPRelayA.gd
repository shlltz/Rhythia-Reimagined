extends Node
# Online lobby through a real relay (relay/rr_relay.py on 127.0.0.1:47390, run by relay_e2e.py), instance A = host.
# Relay missing / down, HOST ONLINE, room code + invite, guests B (invite link) and C (bare code) come in
# through the relay, chat, a match with live scores and results, the host's relay link drops and comes back
# with the same code, kick, room end. Output @@OUT@@/relay_a.txt
const OUT = "@@OUT@@/relay_a.txt"
const ROOM = "@@S@@/t/relay_room.txt"
const B_OK = "@@S@@/t/relay_b_ok.txt"
const RELAY = "ws://127.0.0.1:47390"
const Relay = preload("res://mods/replay/MPRelay.gd")
var passed = 0
var failed = 0

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

func pl(C, nm):
	for p in C.players:
		if str(p.name) == nm: return p
	return {}

func has_chat(C, text):
	for e in C.chat:
		if e.text == text: return true
	return false

func relayed_players(h) -> int:
	var n = 0
	for c in h.conns:
		if c.relayed and c.pid > 0: n += 1
	return n

func write(path, text):
	var f = File.new()
	f.open(path, File.WRITE); f.store_string(text); f.close()

func run():
	var d = Directory.new()
	for p in [OUT, ROOM, B_OK]: d.remove(p)
	yield(wait(6.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	menu.get_node("TitleMenu")._close("multiplayer")
	yield(wait(1.5), "completed")
	var m = menu.get_node("Multiplayer")
	var C = m.client
	m.name_edit.text = "HostA"
	m._save_name_btn()
	m._go_create()
	m.c_port.text = "47381"
	m.c_name.text = "Relay test"
	# no relay address: refused with an explanation, nothing started
	m.c_relay.text = ""
	m._create(true)
	ok("HOST ONLINE without a relay address: explained, nothing started", !C.connected_or_trying() and "relay server address" in m.c_status.text, m.c_status.text)
	# relay down at startup: the host is told, the tunnel keeps retrying (backoff)
	m.c_relay.text = "ws://127.0.0.1:47399"
	m._create(true)
	var t = 0.0
	while t < 12 and !(C.host_node and C.host_node.tunnel and C.host_node.tunnel.state == "reconnecting"):
		yield(wait(0.2), "completed"); t += 0.2
	var tu = C.host_node.tunnel if C.host_node else null
	yield(wait(1.2), "completed")
	m._refresh_status()
	ok("relay down: host told, retrying", tu != null and tu.state == "reconnecting" and "reach the relay" in tu.error_text, m.status_lbl.text)
	ok("relay down: the LAN lobby still runs", C.online() and C.hosting())
	yield(shot("RA_relay_down"), "completed")
	C.leave()
	yield(wait(0.6), "completed")
	# the real relay
	m._go_create()
	m.c_relay.text = RELAY
	m._create(true)
	tu = C.host_node.tunnel
	t = 0.0
	while t < 12 and tu.state != "ready":
		yield(wait(0.1), "completed"); t += 0.1
	ok("room created on the relay", tu.state == "ready" and Relay.norm_code(tu.code) == tu.code, "%s in %.1f s" % [tu.code, t])
	t = 0.0
	while t < 5 and str(C.lobby.get("code", "")) != tu.code:
		yield(wait(0.1), "completed"); t += 0.1
	var inv = str(C.lobby.get("invite", ""))
	ok("lobby shows the online code + invite link", str(C.lobby.get("code")) == tu.code and inv == Relay.invite(RELAY, tu.code), inv)
	ok("no private addresses in the online lobby's data", typeof(C.lobby.get("addr")) == TYPE_ARRAY and C.lobby.addr.empty())
	ok("host credential is separate from the code", tu.token.length() >= 40 and !(tu.code.replace("-", "") in tu.token))
	m._copy_code()
	ok("COPY INVITE copies the link", OS.clipboard == inv and m.l_code_btn.text == "COPY INVITE")
	write(ROOM, inv)
	yield(shot("RA_lobby"), "completed")
	t = 0.0
	while t < 90 and !(relayed_players(C.host_node) == 2 and C.players.size() == 3):
		yield(wait(0.25), "completed"); t += 0.25
	ok("B and C joined through the relay", relayed_players(C.host_node) == 2 and C.players.size() == 3, "%.1f s" % t)
	C.send_chat("hello from A")
	t = 0.0
	while t < 20 and !(has_chat(C, "hello from B") and has_chat(C, "hello from C")):
		yield(wait(0.25), "completed"); t += 0.25
	ok("chat from both guests", has_chat(C, "hello from B") and has_chat(C, "hello from C"))
	var roach = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": roach = s
	C.pick_map(roach)
	t = 0.0
	while t < 30 and !(pl(C, "GuestB").get("ready", false) and pl(C, "GuestC").get("ready", false)):
		yield(wait(0.25), "completed"); t += 0.25
	ok("both guests have the map (verified) and are ready", str(pl(C, "GuestB").get("have")) == "ok" and pl(C, "GuestC").get("ready", false))
	Engine.set_meta("rr_mp_test_autoplay", true)
	C.start_match()
	t = 0.0
	while t < 40 and C.phase != "playing":
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	ok("match started for everyone", C.phase == "playing")
	ok("No Fail on in the match", Rhythia.mod_nofail)
	yield(wait(8.0), "completed")
	var bb = {}
	for e in C.board:
		if str(e.name) == "GuestB": bb = e
	ok("live scores from a relayed guest", !bb.empty() and float(bb.get("prog", 0)) > 0.05, bb)
	t = 0.0
	while t < 90 and !(C.results_match == C.match_id and C.results.size() == 3):
		yield(wait(0.5), "completed"); t += 0.5
	ok("results with all 3 players", C.results.size() == 3, C.results)
	yield(wait(3.0), "completed")
	m = get_tree().root.get_node("Menu/Multiplayer") # (the menu is built again after the match)
	# B cuts its own connection (network blip) and comes back by itself
	t = 0.0
	while t < 60 and !File.new().file_exists(B_OK):
		yield(wait(0.25), "completed"); t += 0.25
	ok("B's reconnect done (B's report)", File.new().file_exists(B_OK))
	# the host's relay link drops: guests wait, the tunnel comes back with the same code, everyone rejoins
	var code0 = tu.code
	var w = tu.ws
	tu._on_lost("lost")
	w.disconnect_from_host()
	w = null
	m._refresh_status()
	ok("host shows the relay reconnecting", "RECONNECTING" in m.status_lbl.text, m.status_lbl.text)
	t = 0.0
	while t < 20 and tu.state != "ready":
		yield(wait(0.2), "completed"); t += 0.2
	ok("tunnel back with the same room code", tu.state == "ready" and tu.code == code0, "%.1f s" % t)
	t = 0.0
	while t < 40 and !(relayed_players(C.host_node) == 2 and str(pl(C, "GuestB").get("conn", "")) == "ok" and str(pl(C, "GuestC").get("conn", "")) == "ok"):
		yield(wait(0.25), "completed"); t += 0.25
	ok("both guests back in through the relay", relayed_players(C.host_node) == 2, "%.1f s" % t)
	yield(wait(4.0), "completed") # (B tries a wrong-version join meanwhile)
	# kick C
	C.kick(int(pl(C, "GuestC").get("pid", 0)))
	t = 0.0
	while t < 10 and !pl(C, "GuestC").empty():
		yield(wait(0.25), "completed"); t += 0.25
	ok("kicked C is gone", pl(C, "GuestC").empty() and relayed_players(C.host_node) == 1)
	yield(wait(3.0), "completed")
	m._refresh_status()
	out("host status: " + m.status_lbl.text)
	out("== totals: %d passed, %d failed" % [passed, failed])
	C.leave() # (ends the room: the relay revokes the code)
	yield(wait(20.0), "completed")
	OS.kill(OS.get_process_id())
