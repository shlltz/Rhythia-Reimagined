extends Node
# two-instance multiplayer test, instance A = host. Output @@OUT@@/drv.txt (+ png)
const OUT = "@@OUT@@/drv.txt"
var passed = 0
var failed = 0
var notices = []

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	OS.window_position = Vector2(0, 30)
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

func _notice(t, bad): notices.append(t)

func find_song(part):
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == part: return s
	return null

func pl(C, nm):
	for p in C.players:
		if str(p.name) == nm: return p
	return {}

func has_chat(C, text):
	for e in C.chat:
		if e.text == text: return true
	return false

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	menu.get_node("TitleMenu")._close("multiplayer")
	yield(wait(1.5), "completed")
	var m = menu.get_node("Multiplayer")
	var C = m.client
	C.connect("notice", self, "_notice")
	m.name_edit.text = "HostA"
	m._save_name_btn()
	m._go_create()
	m.c_port.text = "47380"
	m.c_name.text = "Two PC test"
	m._create()
	var t = 0.0
	while t < 5 and !C.online():
		yield(wait(0.1), "completed"); t += 0.1
	ok("A hosts", C.online() and C.hosting(), C.lobby.get("code"))
	t = 0.0
	while t < 90 and pl(C, "GuestB").empty():
		yield(wait(0.25), "completed"); t += 0.25
	ok("B joined (A's view)", !pl(C, "GuestB").empty(), "%.0f s" % t)
	yield(wait(1.0), "completed")
	ok("player list: 2 players, A host", C.players.size() == 2 and C.is_host())
	C.send_chat("hello from A")
	t = 0.0
	while t < 20 and !has_chat(C, "hello from B"):
		yield(wait(0.25), "completed"); t += 0.25
	ok("chat from B received", has_chat(C, "hello from B"))
	shot("A_lobby")
	# a map B doesn't have
	var chipi = find_song("@@MAP2@@")
	var roach = find_song("@@MAP1@@")
	ok("A has both test maps", chipi != null and roach != null)
	C.pick_map(chipi)
	t = 0.0
	while t < 15 and str(pl(C, "GuestB").get("have", "")) != "missing":
		yield(wait(0.25), "completed"); t += 0.25
	ok("B reports the map missing", str(pl(C, "GuestB").get("have", "")) == "missing")
	notices = []
	C.start_match()
	yield(wait(0.8), "completed")
	ok("start refused: B is missing the map", str(C.lobby.get("state")) == "lobby" and "missing" in str(notices), notices)
	shot("A_missing")
	C.pick_map(roach)
	t = 0.0
	while t < 15 and str(pl(C, "GuestB").get("have", "")) != "ok":
		yield(wait(0.25), "completed"); t += 0.25
	ok("B has the second map", str(pl(C, "GuestB").get("have", "")) == "ok")
	t = 0.0
	while t < 20 and !pl(C, "GuestB").get("ready", false):
		yield(wait(0.25), "completed"); t += 0.25
	ok("B ready (A's view)", pl(C, "GuestB").get("ready", false))
	# match 1: A autoplays, B doesn't touch anything (misses everything: only No Fail keeps it alive)
	Engine.set_meta("rr_mp_test_autoplay", true)
	C.start_match()
	t = 0.0
	while t < 40 and C.phase != "playing":
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	out("GO_SERVER %d" % C.server_now())
	ok("match 1 started", C.phase == "playing")
	ok("No Fail on in the match", Rhythia.mod_nofail)
	yield(wait(1.0), "completed")
	ok("overlay in game", get_tree().current_scene.find_node("MPOverlay", true, false) != null)
	yield(wait(7.0), "completed")
	shot("A_game")
	var bb = {}
	for e in C.board:
		if str(e.name) == "GuestB": bb = e
	var ab = {}
	for e in C.board:
		if str(e.name) == "HostA": ab = e
	ok("live board has B's progress", !bb.empty() and float(bb.get("prog", 0)) > 0.05, bb)
	ok("A scores while autoplaying", int(ab.get("score", 0)) > 0, ab)
	t = 0.0
	while t < 90 and !(C.results_match == C.match_id and C.results.size() == 2):
		yield(wait(0.5), "completed"); t += 0.5
	ok("match 1 results (both players)", C.results.size() == 2, C.results)
	if C.results.size() == 2:
		ok("A ranked first (autoplay)", str(C.results[0].name) == "HostA" and int(C.results[0].score) > int(C.results[1].score))
		ok("B finished (No Fail kept B alive)", str(C.results[1].status) == "finished", C.results[1].status)
	yield(wait(3.0), "completed")
	var m2 = get_tree().root.get_node_or_null("Menu/Multiplayer")
	ok("back in the lobby with results", m2 != null and m2.results_on)
	ok("A's own settings back (record_replays restored)", C.snapshot.empty() and !File.new().file_exists("user://rr_mp_restore.json"))
	shot("A_results")
	# match 2 (same lobby, same map): A quits half way
	t = 0.0
	while t < 40 and !pl(C, "GuestB").get("ready", false):
		yield(wait(0.25), "completed"); t += 0.25
	ok("B ready again", pl(C, "GuestB").get("ready", false))
	var mid1 = C.match_id
	C.start_match()
	t = 0.0
	while t < 40 and C.phase != "playing":
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	out("GO2_SERVER %d" % C.server_now())
	ok("match 2 started", C.phase == "playing" and C.match_id == mid1 + 1)
	yield(wait(6.0), "completed")
	if is_instance_valid(C.game): C.game.end(Globals.END_GIVEUP)
	t = 0.0
	while t < 90 and !(C.results_match == C.match_id and C.results.size() == 2):
		yield(wait(0.5), "completed"); t += 0.5
	ok("match 2 results", C.results_match == mid1 + 1 and C.results.size() == 2, C.results)
	var qa = ""
	for e in C.results:
		if str(e.name) == "HostA": qa = str(e.status)
	ok("A quit status in results", qa == "quit", qa)
	# B now drops off without saying goodbye (process killed)
	t = 0.0
	while t < 40 and str(pl(C, "GuestB").get("conn", "ok")) == "ok":
		yield(wait(0.25), "completed"); t += 0.25
	ok("host notices B's connection loss", str(pl(C, "GuestB").get("conn", "")) == "lost", "%.1f s" % t)
	yield(wait(1.0), "completed")
	ok("lobby keeps running", C.online() and C.hosting())
	shot("A_after_drop")
	out("== totals: %d passed, %d failed" % [passed, failed])
	C.leave()
	yield(wait(0.5), "completed")
	OS.kill(OS.get_process_id())
