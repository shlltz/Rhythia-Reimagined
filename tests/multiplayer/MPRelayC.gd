extends Node
# Online lobby through a real relay, instance C = second guest, joining with the bare room code plus the
# relay address (MPRelayA.gd). Plays the match, rides out the host's relay drop, then gets kicked.
# Output @@OUT@@/relay_c.txt
const OUT = "@@OUT@@/relay_c.txt"
const ROOM = "@@S@@/t/relay_room.txt"
const RELAY = "ws://127.0.0.1:47390"
const Relay = preload("res://mods/replay/MPRelay.gd")
var passed = 0
var failed = 0
var notices = []

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

func has_chat(C, text):
	for e in C.chat:
		if e.text == text: return true
	return false

func _notice(text, _bad):
	notices.append(text)

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	menu.get_node("TitleMenu")._close("multiplayer")
	yield(wait(1.5), "completed")
	var m = menu.get_node("Multiplayer")
	var C = m.client
	C.connect("notice", self, "_notice")
	m.name_edit.text = "GuestC"
	m._save_name_btn()
	var t = 0.0
	var inv = ""
	while t < 60 and inv == "":
		yield(wait(0.25), "completed"); t += 0.25
		var f = File.new()
		if f.open(ROOM, File.READ) == OK:
			inv = f.get_as_text().strip_edges(); f.close()
	var code = Relay.parse_invite(inv).get("code", "")
	m._go_join()
	m.j_addr.text = code.to_lower().replace("-", "") # (typed by hand: lower case, no dash)
	m.j_relay.text = RELAY
	m._join()
	t = 0.0
	while t < 15 and !C.online():
		yield(wait(0.1), "completed"); t += 0.1
	ok("C in the lobby with the bare code", C.online() and C.relayed(), "%.1f s" % t)
	C.send_chat("hello from C")
	t = 0.0
	while t < 30 and C.my_have != "ok":
		yield(wait(0.25), "completed"); t += 0.25
	m._ready_toggle(true)
	t = 0.0
	while t < 60 and C.phase != "playing":
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	ok("C plays the match", C.phase == "playing")
	t = 0.0
	while t < 120 and !(C.results_match == C.match_id and C.results.size() == 3):
		yield(wait(0.5), "completed"); t += 0.5
	ok("C gets the results", C.results.size() == 3)
	# the host's relay drop, then the kick
	t = 0.0
	while t < 150 and C.status != "idle":
		yield(wait(0.25), "completed"); t += 0.25
	ok("C removed by the host", C.status == "idle" and "removed" in C.status_text, C.status_text)
	ok("C was told", "The host removed you from the lobby." in notices, notices)
	out("== totals: %d passed, %d failed" % [passed, failed])
	yield(wait(1.0), "completed")
	OS.kill(OS.get_process_id())
