extends Node
# Multiplayer core tests (one game instance): protocol helpers, lobby rules (no sockets), then a
# real host + 2 clients over 127.0.0.1 inside this process. Output: @@OUT@@/core_test.txt
const OUT = "@@OUT@@/core_test.txt"
const P = preload("res://mods/replay/MPProto.gd")
const Lobby = preload("res://mods/replay/MPLobby.gd")
var passed = 0
var failed = 0

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(960, 540)
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

func msgs(l, pid, t):
	var r = []
	for o in l.out:
		if (o[0] == pid or o[0] == -1) and o[1].t == t: r.append(o[1])
	return r

func run():
	Directory.new().remove(OUT)
	yield(wait(5.0), "completed")
	out("== protocol")
	ok("clean_name strips control chars", P.clean_name("a\u0001b\nc\td") == "ab c d", P.clean_name("a\u0001b\nc\td"))
	ok("clean_name length limit", P.clean_name(_rep("x", 50)).length() == P.NAME_MAX)
	ok("clean_name empty -> player", P.clean_name("   ") == "player")
	ok("clean_name bidi override removed", !("‮" in P.clean_name("ab‮cd")))
	ok("clean_text folds spaces", P.clean_text("a    b", 50) == "a b")
	ok("clean_text non-string", P.clean_text(5, 10) == "")
	ok("parse_line valid", P.parse_line('{"t":"ping","c":1}') != null)
	ok("parse_line rejects non-object", P.parse_line('[1,2]') == null)
	ok("parse_line rejects missing t", P.parse_line('{"x":1}') == null)
	ok("parse_line rejects junk", P.parse_line('{{{') == null)
	ok("parse_line rejects huge", P.parse_line('{"t":"chat","text":"' + _rep("a", 9000) + '"}') == null)
	var code = P.room_code("192.168.1.38", 47320)
	ok("room code format", code.length() == 11 and code[5] == "-", code)
	var back = P.parse_address(code)
	ok("room code round trip", back.size() == 2 and back[0] == "192.168.1.38" and back[1] == 47320, str(back))
	ok("room code lower case + no dash", P.parse_address(code.to_lower().replace("-", "")) == back)
	ok("address ip only", P.parse_address("10.0.0.5") == ["10.0.0.5", P.PORT])
	ok("address ip:port", P.parse_address("10.0.0.5:5000") == ["10.0.0.5", 5000])
	ok("address hostname", P.parse_address("my-pc.lan:47320") == ["my-pc.lan", 47320])
	ok("address bad port", P.parse_address("1.2.3.4:99999").empty() and P.parse_address("1.2.3.4:x").empty())
	ok("address junk", P.parse_address("a b c").empty() and P.parse_address("").empty())
	var good_map = {id = "abc", hash = "0123456789abcdef0123456789abcdef", name = "N", creator = "C", diff = 2, notes = 100, len = 30000.0}
	ok("clean_map ok", !P.clean_map(good_map).empty())
	var bad = good_map.duplicate(); bad.hash = "zz"
	ok("clean_map bad hash", P.clean_map(bad).empty())
	bad = good_map.duplicate(); bad.notes = -5
	ok("clean_map bad notes", P.clean_map(bad).empty())
	var r = P.clean_rules({speed = 9.0, mods = ["mod_hardrock", "mod_sudden_death", 5, "mod_hardrock"], hw = 70, hb = 1.2})
	ok("clean_rules drops bad speed / mods", r.speed == 1.0 and r.mods == ["mod_hardrock"] and r.hw == 70.0, str(r))

	out("== lobby rules (no sockets)")
	var L = Lobby.new({name = "Test", max = 3, pw = "", owner_key = "K"})
	var bad_v = L.hello({t = "hello", v = "rr-mp-0", name = "x"})
	ok("version check", !bad_v.ok and "version" in bad_v.reason, bad_v)
	var a = L.hello({t = "hello", v = P.VERSION, name = "Alice", owner = "K"})
	var b = L.hello({t = "hello", v = P.VERSION, name = "Alice"})
	ok("join gives unique ids", a.ok and b.ok and a.pid != b.pid, [a, b])
	ok("owner is host", L.host_pid == a.pid and L.owner_pid == a.pid)
	ok("duplicate names allowed", L.players[a.pid].name == L.players[b.pid].name)
	var c = L.hello({t = "hello", v = P.VERSION, name = "Cat"})
	var d = L.hello({t = "hello", v = P.VERSION, name = "Dan"})
	ok("max players enforced", c.ok and !d.ok and "full" in d.reason, d)
	L.out = []
	L.handle(b.pid, {t = "chat", seq = 1, text = "hi \u0007there"})
	var ch = msgs(L, -1, "chat")
	ok("chat relayed to everyone, sanitised", ch.size() == 1 and ch[0].text == "hi there" and ch[0].pid == b.pid, ch)
	L.out = []
	L.handle(b.pid, {t = "chat", seq = 1, text = "again"})
	ok("duplicate chat seq ignored", msgs(L, -1, "chat").empty())
	for i in range(2, 8): L.handle(b.pid, {t = "chat", seq = i, text = "spam %d" % i})
	ok("chat rate limit", msgs(L, -1, "chat").size() == P.CHAT_RATE - 1 and msgs(L, b.pid, "error").size() >= 1, msgs(L, -1, "chat").size())
	L.out = []
	L.handle(b.pid, {t = "ready", on = true})
	ok("ready refused without a map", !L.players[b.pid].ready and msgs(L, b.pid, "error").size() == 1)
	L.out = []
	L.handle(b.pid, {t = "set_map", map = good_map})
	ok("set_map refused for non-host", L.map.empty() and msgs(L, b.pid, "error").size() == 1)
	L.handle(b.pid, {t = "start"})
	ok("start refused for non-host", L.state == "lobby")
	L.handle(b.pid, {t = "kick", pid = a.pid})
	ok("kick refused for non-host", L.players.has(a.pid))
	L.handle(a.pid, {t = "set_map", map = good_map})
	ok("host sets map", L.map.get("id") == "abc")
	var key = P.map_key(L.map)
	L.handle(a.pid, {t = "have", key = key, st = "ok"})
	L.handle(b.pid, {t = "have", key = key, st = "ok"})
	L.handle(c.pid, {t = "have", key = key, st = "missing"})
	L.out = []
	L.handle(a.pid, {t = "start"})
	ok("start blocked: a player is missing the map", L.state == "lobby" and "missing" in str(msgs(L, a.pid, "error")), msgs(L, a.pid, "error"))
	L.handle(c.pid, {t = "ready", on = true})
	ok("ready refused when missing the map", !L.players[c.pid].ready)
	L.handle(c.pid, {t = "have", key = "old:key", st = "ok"})
	ok("have for an old map ignored", L.players[c.pid].have == "missing")
	L.handle(c.pid, {t = "have", key = key, st = "ok"})
	L.out = []
	L.handle(a.pid, {t = "start"})
	ok("start blocked: not ready", L.state == "lobby" and "not ready" in str(msgs(L, a.pid, "error")))
	L.handle(b.pid, {t = "ready", on = true})
	L.handle(c.pid, {t = "ready", on = true})
	L.handle(a.pid, {t = "set_rules", rules = {speed = 1.25, mods = ["mod_ghost"]}})
	ok("rules change unreadies", !L.players[b.pid].ready and L.rules.speed == 1.25)
	L.handle(b.pid, {t = "ready", on = true})
	L.handle(c.pid, {t = "ready", on = true})
	L.out = []
	L.handle(a.pid, {t = "start"})
	ok("start ok when all ready + have the map", L.state == "loading" and L.participants.size() == 3)
	ok("match_load sent to each participant", msgs(L, a.pid, "match_load").size() == 1 and msgs(L, c.pid, "match_load").size() == 1)
	L.handle(b.pid, {t = "set_map", map = good_map})
	L.handle(a.pid, {t = "set_map", map = good_map})
	ok("map can't change mid-match", L.state == "loading")
	L.handle(a.pid, {t = "loaded", m = L.match_id})
	L.handle(b.pid, {t = "loaded", m = L.match_id})
	ok("waits for everyone to load", L.state == "loading")
	L.out = []
	L.now += 10
	L.handle(c.pid, {t = "loaded", m = L.match_id})
	var go = msgs(L, a.pid, "match_go")
	ok("all loaded -> shared start time ahead", L.state == "playing" and go.size() == 1 and go[0].at >= L.now + P.START_LEAD, go)
	var mid = L.match_id
	L.handle(a.pid, {t = "score", m = mid, seq = 1, score = 500, hits = 10, misses = 1, combo = 5, mc = 9, prog = 0.2})
	ok("score accepted", L.players[a.pid].s.score == 500)
	L.handle(a.pid, {t = "score", m = mid, seq = 1, score = 900, hits = 12, misses = 1, combo = 7, mc = 9, prog = 0.3})
	ok("repeated seq ignored", L.players[a.pid].s.score == 500)
	L.handle(a.pid, {t = "score", m = mid, seq = 2, score = 400, hits = 12, misses = 1, combo = 7, mc = 9, prog = 0.3})
	ok("score going down rejected", L.players[a.pid].s.score == 500)
	L.handle(a.pid, {t = "score", m = mid, seq = 3, score = 999999, hits = 12, misses = 1, combo = 7, mc = 9, prog = 0.3})
	ok("impossible score rejected", L.players[a.pid].s.score == 500)
	L.handle(a.pid, {t = "score", m = mid, seq = 4, score = 900, hits = 12, misses = 1, combo = 13, mc = 13, prog = 0.3})
	ok("combo above hits rejected", L.players[a.pid].s.score == 500)
	L.handle(b.pid, {t = "score", m = mid + 1, seq = 1, score = 100, hits = 2, misses = 0, combo = 2, mc = 2, prog = 0.1})
	ok("score for another match ignored", L.players[b.pid].s.score == 0)
	L.handle(b.pid, {t = "score", m = mid, seq = 1, pid = a.pid, score = 100, hits = 2, misses = 0, combo = 2, mc = 2, prog = 0.1})
	ok("a client can only set its own score", L.players[b.pid].s.score == 100 and L.players[a.pid].s.score == 500)
	L.out = []
	L.tick(L.now + 300)
	ok("board broadcast", msgs(L, -1, "board").size() == 1)
	L.handle(a.pid, {t = "done", m = mid, seq = 9, end = "pass", score = 2000, hits = 90, misses = 10, combo = 40, mc = 60, prog = 1})
	L.handle(b.pid, {t = "done", m = mid, seq = 9, end = "quit", score = 300, hits = 5, misses = 1, combo = 0, mc = 3, prog = 0.4})
	ok("match waits for the last player", L.state == "playing")
	L.out = []
	L.handle(c.pid, {t = "done", m = mid, seq = 1, end = "pass", score = 2500, hits = 95, misses = 5, combo = 50, mc = 70, prog = 1})
	var me = msgs(L, -1, "match_end")
	ok("match_end when all finished", L.state == "lobby" and me.size() == 1)
	if me.size() == 1:
		var res = me[0].results
		ok("results ranked by score", res.size() == 3 and res[0].pid == c.pid and res[1].pid == a.pid and res[2].pid == b.pid and res[0].rank == 1, res)
		ok("results statuses", res[2].status == "quit" and res[0].status == "finished")
	ok("ready flags reset after a match", !L.players[b.pid].ready and !L.players[c.pid].ready)
	# second match in the same lobby
	L.handle(b.pid, {t = "ready", on = true})
	L.handle(c.pid, {t = "ready", on = true})
	L.handle(a.pid, {t = "start"})
	ok("second match starts", L.state == "loading" and L.match_id == mid + 1)
	for q in [a.pid, b.pid, c.pid]: L.handle(q, {t = "loaded", m = L.match_id})
	ok("second match playing", L.state == "playing")
	# disconnect + reconnect
	L.disconnected(b.pid)
	ok("disconnect marks lost", L.players[b.pid].conn == "lost")
	var tok = L.players[b.pid].token
	var re = L.hello({t = "hello", v = P.VERSION, name = "whatever", token = tok})
	ok("reconnect with token keeps the id", re.ok and re.pid == b.pid and L.players[b.pid].conn == "ok")
	L.disconnected(b.pid)
	L.handle(a.pid, {t = "done", m = L.match_id, seq = 20, end = "pass", score = 100, hits = 3, misses = 0, combo = 3, mc = 3, prog = 1})
	L.out = []
	L.handle(c.pid, {t = "done", m = L.match_id, seq = 20, end = "pass", score = 50, hits = 2, misses = 0, combo = 2, mc = 2, prog = 1})
	var me2 = msgs(L, -1, "match_end")
	ok("match ends without the disconnected player", me2.size() == 1 and L.state == "lobby")
	if me2.size() == 1:
		var st = ""
		for e in me2[0].results:
			if e.pid == b.pid: st = e.status
		ok("disconnected player marked", st == "disconnected", st)
	L.tick(L.now + int(P.RECONNECT_KEEP * 1000) + 100)
	ok("lost player removed after the keep time", !L.players.has(b.pid))
	# abort
	L.handle(c.pid, {t = "ready", on = true})
	L.handle(a.pid, {t = "start"})
	L.out = []
	L.handle(c.pid, {t = "abort"})
	ok("abort refused for non-host", L.state == "loading")
	L.handle(a.pid, {t = "abort"})
	ok("host abort ends the match", L.state == "lobby" and msgs(L, -1, "match_end").size() == 1 and msgs(L, -1, "match_end")[0].aborted)
	# host transfer + kick
	L.handle(a.pid, {t = "give_host", pid = c.pid})
	ok("give host", L.host_pid == c.pid)
	L.handle(a.pid, {t = "set_map", map = good_map})
	ok("old host lost host rights", msgs(L, a.pid, "error").size() >= 1)
	L.handle(c.pid, {t = "kick", pid = a.pid})
	ok("the owner machine can't be kicked", L.players.has(a.pid))
	L.handle(c.pid, {t = "give_host", pid = a.pid})
	var e2 = L.hello({t = "hello", v = P.VERSION, name = "Eve"})
	L.out = []
	L.handle(a.pid, {t = "kick", pid = e2.pid})
	ok("kick removes + tells the player", !L.players.has(e2.pid) and msgs(L, e2.pid, "kicked").size() == 1 and e2.pid in L.drop)
	# invalid messages
	for i in 35: L.handle(c.pid, {t = "nonsense"})
	ok("a client spamming invalid messages is dropped", !L.players.has(c.pid))
	L.handle(a.pid, {t = "bye"})
	ok("owner leaving closes the lobby", L.closed)
	var L2 = Lobby.new({name = "pw", max = 4, pw = "secret", owner_key = "K"})
	ok("password required", !L2.hello({t = "hello", v = P.VERSION, name = "x", pw = "nope"}).ok and L2.hello({t = "hello", v = P.VERSION, name = "x", pw = "secret"}).ok)

	out("== sockets: host + 2 clients over 127.0.0.1")
	var A = load("res://mods/replay/MPClient.gd").get_client(get_tree())
	A.test_no_scene = true
	A.my_name = "HostA"
	var err = A.host_lobby({name = "Core lobby", max = 4, pw = "", port = 47390})
	ok("host starts listening", err == "", err)
	var B = load("res://mods/replay/MPClient.gd").new()
	B.name = "MPTestB"
	B.test_no_scene = true
	get_tree().root.add_child(B)
	B.my_name = "Bob"
	B.join("127.0.0.1", 47390, "")
	var C = load("res://mods/replay/MPClient.gd").new()
	C.name = "MPTestC"
	C.test_no_scene = true
	get_tree().root.add_child(C)
	C.my_name = "Bob"
	C.join("127.0.0.1", 47390, "wrong-is-fine-no-pw")
	var t = 0.0
	while t < 5 and !(A.online() and B.online() and C.online()):
		yield(wait(0.1), "completed"); t += 0.1
	ok("all three online", A.online() and B.online() and C.online(), [A.status, B.status, C.status])
	yield(wait(0.5), "completed")
	ok("same player list everywhere", A.players.size() == 3 and str(_ids(A.players)) == str(_ids(B.players)) and str(_ids(B.players)) == str(_ids(C.players)), [_ids(A.players), _ids(B.players)])
	ok("A is host", A.is_host() and !B.is_host())
	ok("unique ids, duplicate names", B.pid != C.pid and B.my_name == C.my_name)
	ok("room code + address in lobby info", str(B.lobby.get("code", "")) != "" and B.lobby.get("addr", []).size() > 0, B.lobby.get("code"))
	A.send_chat("hello from A")
	B.send_chat("hi from B")
	yield(wait(0.5), "completed")
	ok("chat A -> B", _has_chat(B, "hello from A"))
	ok("chat B -> A + C", _has_chat(A, "hi from B") and _has_chat(C, "hi from B"))
	ok("own message confirmed (not pending)", _confirmed(B, "hi from B"))
	# rtt / clock
	yield(wait(2.5), "completed")
	ok("ping measured", B.rtt >= 0 and B.rtt < 200, B.rtt)
	ok("clock offset small on one machine", abs(B.offset) < 50, B.offset)
	ok("ping shown in player list", _ping_of(A, B.pid) >= 0, _ping_of(A, B.pid))
	# map + ready + start
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.note_count > 0 and s.filePath.get_file() == "@@MAP1@@": song = s
	ok("test map in the library", song != null)
	if song:
		var e = A.pick_map(song)
		yield(wait(0.6), "completed")
		ok("map synced to clients", str(B.lobby.get("map", {}).get("id", "")) == song.id, B.lobby.get("map", {}).get("id"))
		ok("clients checked the map", B.my_have == "ok" and _have_of(A, B.pid) == "ok", [B.my_have, _have_of(A, B.pid)])
		A.start_match()
		yield(wait(0.4), "completed")
		ok("start refused while players aren't ready", A.lobby.get("state") == "lobby")
		B.set_ready(true)
		C.set_ready(true)
		yield(wait(0.4), "completed")
		ok("ready synced", _ready_of(A, B.pid) and _ready_of(B, C.pid))
		A.start_match()
		yield(wait(0.5), "completed")
		ok("match loading on all", A.phase == "loading" and B.phase == "loading" and C.phase == "loading", [A.phase, B.phase, C.phase])
		for X in [A, B, C]:
			X.phase = "ready"
			X.send({t = "loaded", m = X.match_id})
		yield(wait(0.5), "completed")
		ok("shared start time received", A.go_local > 0 and B.go_local > 0 and abs(A.go_local - B.go_local) < 30, [A.go_local, B.go_local])
		for X in [A, B, C]: X.phase = "waiting"
		yield(wait(2.5), "completed")
		ok("all start at the go time", A.phase == "playing" and B.phase == "playing" and C.phase == "playing")
		B.score_seq += 1
		B.send({t = "score", m = B.match_id, seq = B.score_seq, score = 1200, hits = 20, misses = 2, combo = 10, mc = 12, prog = 0.3})
		yield(wait(0.6), "completed")
		ok("live board on other clients", _board_score(A, B.pid) == 1200 and _board_score(C, B.pid) == 1200)
		for X in [A, B, C]:
			X.score_seq += 1
			X.send({t = "done", m = X.match_id, seq = X.score_seq, end = "pass", score = 100 * X.pid + (2000 if X == B else 0), hits = 30, misses = 2, combo = 30, mc = 30, prog = 1})
			X.phase = "done"
		yield(wait(0.6), "completed")
		ok("synchronized results on every client", A.results.size() == 3 and B.results.size() == 3 and C.results.size() == 3 and str(A.results) == str(C.results))
		ok("results ranked", A.results.size() == 3 and int(A.results[0].pid) == B.pid, A.results)
	# disconnect handling
	C.peer.disconnect_from_host()
	C.peer = null
	C.status = "idle"
	yield(wait(1.0), "completed")
	ok("host notices a dropped player", _conn_of(A, C.pid) == "lost", _conn_of(A, C.pid))
	# reconnect (B drops, its client reconnects with its token)
	var bpid = B.pid
	B.peer.disconnect_from_host()
	t = 0.0
	while t < 3 and B.online():
		yield(wait(0.05), "completed"); t += 0.05
	ok("client notices the drop", !B.online(), B.status)
	t = 0.0
	while t < 8 and !(B.online() and B._was_online and _conn_of(A, bpid) == "ok" and B.pid == bpid):
		yield(wait(0.2), "completed"); t += 0.2
	ok("client reconnects to the same slot", B.online() and B.pid == bpid and _conn_of(A, bpid) == "ok", [B.status, B.pid, bpid])
	# bad data on a raw socket
	var raw = StreamPeerTCP.new()
	raw.connect_to_host("127.0.0.1", 47390)
	yield(wait(0.3), "completed")
	raw.put_data("this is not json\n{\"t\":\"hello\",\"v\":\"rr-mp-999\"}\n".to_utf8())
	yield(wait(0.5), "completed")
	var got = raw.get_partial_data(raw.get_available_bytes())[1].get_string_from_utf8() if raw.get_available_bytes() > 0 else ""
	ok("raw junk answered + old version rejected", "reject" in got and "version" in got, got.substr(0, 160))
	yield(wait(0.3), "completed")
	ok("host still fine after junk", A.online() and A.players.size() >= 2)
	# kick
	A.kick(B.pid)
	yield(wait(0.8), "completed")
	ok("kicked client is out", B.status == "idle" and !_ids(A.players).has(B.pid), [B.status, _ids(A.players)])
	yield(wait(1.5), "completed")
	ok("a kicked player can't reconnect", B.status == "idle" and !_ids(A.players).has(B.pid), [B.status, B.status_text])
	# host leaves -> lobby closes
	var D = load("res://mods/replay/MPClient.gd").new()
	D.name = "MPTestD"
	get_tree().root.add_child(D)
	D.join("127.0.0.1", 47390, "")
	yield(wait(0.8), "completed")
	A.leave()
	yield(wait(0.8), "completed")
	ok("host leaving closes the lobby for others", D.status == "idle", D.status_text)
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())

func _ids(l):
	var r = []
	for p in l: r.append(int(p.pid))
	return r

func _find(cl, pid):
	for p in cl.players:
		if int(p.pid) == pid: return p
	return {}

func _ping_of(cl, pid): return int(_find(cl, pid).get("ping", -1))
func _have_of(cl, pid): return str(_find(cl, pid).get("have", ""))
func _ready_of(cl, pid): return bool(_find(cl, pid).get("ready", false))
func _conn_of(cl, pid): return str(_find(cl, pid).get("conn", "gone"))

func _board_score(cl, pid):
	for e in cl.board:
		if int(e.pid) == pid: return int(e.score)
	return -1

func _has_chat(cl, text):
	for e in cl.chat:
		if e.text == text: return true
	return false

func _confirmed(cl, text):
	for e in cl.chat:
		if e.text == text and !e.get("pending", false): return true
	return false

func _rep(x, n):
	var r = ""
	for i in n: r += x
	return r
