extends Node
# Multiplayer client (every player, the host too: the host's game runs MPHost and joins it over
# 127.0.0.1 like everyone else). One node on the root ("RRMultiplayer"), kept across scene changes
# and running while the tree is paused. Holds the connection and a copy of the lobby state; the
# lobby screen (MPMenu) and the in-game overlay (MPOverlay) only read it and call its actions.
#
# Match flow: match_load -> the session's rules are applied (No Fail forced on, the host's mods /
# speed / hit window / hitbox; the player's own values are saved to RESTORE first) -> the map loads
# -> Game.gd calls game_ready() and holds its lead-in until go_open() (the host's shared start time,
# converted with the clock offset from the pings) -> scores every 250 ms -> game_end() -> back in
# the menu the player's own settings come back (restore_rules) and the lobby shows the results.

signal changed(what)            # status | lobby | players | chat | board | results | match | lan
signal notice(text, bad)

const P = preload("res://mods/replay/MPProto.gd")
const RESTORE = "user://rr_mp_restore.json"
const NAME = "RRMultiplayer"

var status:String = "idle"      # idle | resolving | connecting | handshake | online | reconnecting
var status_text:String = ""
var peer:StreamPeerTCP
var inbuf:PoolByteArray = PoolByteArray()
var outbuf:PoolByteArray = PoolByteArray()
var addr_host:String = ""
var addr_ip:String = ""
var addr_port:int = 0
var password:String = ""
var my_name:String = ""
var token:String = ""
var pid:int = 0
var host_node = null            # MPHost while this game hosts the lobby
var owner_key:String = ""
var lobby:Dictionary = {}
var players:Array = []
var chat:Array = []             # {pid, name, text, ts, sys, mine, failed}
var board:Array = []
var results:Array = []
var results_match:int = 0
var have_key:String = ""
var my_have:String = "?"
var rtt:int = -1
var offset:float = 0.0          # server clock - local clock (ms)
var _sync:Array = []            # recent [rtt, offset] samples
var _last_rx:int = 0
var _ping_t:int = 0
var _connect_t:int = 0
var _resolve_id:int = -1
var _reconnect_until:int = 0
var _retry_t:int = 0
var _was_online:bool = false
var _reconnecting:bool = false
var chat_seq:int = 0
var leaving:bool = false
var test_no_scene:bool = false  # tests: match_load doesn't change scenes or settings

# match
var phase:String = "none"       # none | loading | ready | waiting | playing | done
var match_id:int = 0
var match_map:Dictionary = {}
var match_rules:Dictionary = {}
var go_local:int = -1
var go_late:int = 0
var aborted:bool = false
var game = null
var _score_t:int = 0
var score_seq:int = 0
var _last_sent:Dictionary = {}
var snapshot:Dictionary = {}
var lan:Dictionary = {}         # "ip:port" -> beacon info + seen time
var lan_udp:PacketPeerUDP = null
var lan_error:String = ""

static func get_client(tree:SceneTree):
	var n = tree.root.get_node_or_null(NAME)
	if n: return n
	n = load("res://mods/replay/MPClient.gd").new()
	n.name = NAME
	tree.root.add_child(n)
	return n

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	my_name = P.clean_name(_cfg("mp_name", ""))
	if _cfg("mp_name", "") == "": my_name = P.gen_name()

func _cfg(k:String, def):
	var R = load("res://mods/replay/Reimagined.gd")
	var c = R.cfg()
	return c.get(k, def)

func _cfg_set(k:String, v):
	var R = load("res://mods/replay/Reimagined.gd")
	R.cfg()[k] = v
	R.save()

func set_my_name(n:String):
	my_name = P.clean_name(n)
	_cfg_set("mp_name", my_name)

func online() -> bool:
	return status == "online"

func connected_or_trying() -> bool:
	return status != "idle"

func is_host() -> bool:
	return pid != 0 and int(lobby.get("host", -1)) == pid

func hosting() -> bool:
	return host_node != null and is_instance_valid(host_node) and host_node.running

func me() -> Dictionary:
	for p in players:
		if int(p.pid) == pid: return p
	return {}

func server_now() -> int:
	return int(P.now_ms() + offset)

# ---------------------------------------------------------------- connecting
# -> "" or the error
func host_lobby(cfg:Dictionary) -> String:
	if connected_or_trying(): leave()
	randomize()
	owner_key = "%08x%08x" % [randi(), randi()]
	cfg["owner_key"] = owner_key
	cfg["rules"] = {speed = 1.0, mods = [], hw = float(Rhythia.get("hitwindow_ms")), hb = float(Rhythia.get("note_hitbox_size")), shw = bool(Rhythia.get("speed_hitwindow"))}
	var h = load("res://mods/replay/MPHost.gd").new()
	add_child(h)
	var err = h.start(cfg)
	if err != "":
		h.queue_free()
		return err
	host_node = h
	h.connect("stopped", self, "_host_stopped")
	password = str(cfg.get("pw", ""))
	_open("127.0.0.1", int(cfg.get("port", P.PORT)))
	return ""

func join(host:String, port:int, pw:String):
	if connected_or_trying(): leave()
	owner_key = ""
	password = pw
	token = ""
	_open(host, port)
	var R = load("res://mods/replay/Reimagined.gd")
	var rec = Array(_cfg("mp_recent", []))
	var a = "%s:%d" % [host, port]
	rec.erase(a)
	rec.push_front(a)
	while rec.size() > 6: rec.pop_back()
	_cfg_set("mp_recent", rec)

func _open(host:String, port:int):
	addr_host = host
	addr_port = port
	leaving = false
	_was_online = false
	_reconnecting = false
	pid = 0
	token = ""
	lobby = {}
	players = []
	chat = []
	board = []
	results = []
	_sync = []
	offset = 0
	rtt = -1
	if host.is_valid_ip_address():
		addr_ip = host
		_connect_now()
	else:
		_resolve_id = IP.resolve_hostname_queue_item(host, IP.TYPE_IPV4)
		_set_status("resolving", "looking up " + host)
		_connect_t = P.now_ms()

func _connect_now():
	peer = StreamPeerTCP.new()
	inbuf = PoolByteArray()
	outbuf = PoolByteArray()
	var err = peer.connect_to_host(addr_ip, addr_port) # (doesn't wait: get_status() reports progress)
	_connect_t = P.now_ms()
	if err != OK:
		_conn_failed("couldn't start the connection (error %d)" % err)
		return
	_set_status("connecting", "connecting to %s:%d" % [addr_ip, addr_port])

func leave():
	if status == "idle" and !hosting():
		restore_rules()
		return
	leaving = true
	if peer and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data(P.encode({t = "bye"}))
	_close_peer()
	if hosting(): host_node.stop("the host closed the lobby")
	if host_node and is_instance_valid(host_node): host_node.queue_free()
	host_node = null
	_reset_match()
	restore_rules()
	pid = 0
	token = ""
	lobby = {}
	players = []
	_set_status("idle", "")

func _close_peer():
	if peer:
		peer.disconnect_from_host()
	peer = null
	inbuf = PoolByteArray()
	outbuf = PoolByteArray()

# a connect attempt failed or a live connection dropped: retry for 30 s with the same token (the
# host keeps the slot and score), unless the player left on purpose
func _conn_failed(why:String):
	print("[mp] %s: connection problem: %s" % [name, why])
	_close_peer()
	var now = P.now_ms()
	if !leaving and (_was_online or _reconnecting):
		var first = !_reconnecting
		if first:
			_reconnecting = true
			_reconnect_until = now + 30000
			emit_signal("notice", "Connection to the lobby lost - reconnecting...", true)
		if now < _reconnect_until:
			_retry_t = now + (400 if first else 2000)
			_set_status("reconnecting", "connection lost - retrying (%s)" % why)
			return
		_reconnecting = false
		_was_online = false
		_reset_match_if_waiting()
		_set_status("idle", "connection lost")
		emit_signal("notice", "Lost the connection to the lobby.", true)
		return
	_set_status("idle", why)
	emit_signal("notice", why, true)

func _host_stopped(reason:String):
	if host_node: host_node.queue_free()
	host_node = null

func _set_status(s:String, text:String):
	status = s
	status_text = text
	emit_signal("changed", "status")

func send(msg:Dictionary) -> bool:
	if !peer or (status != "online" and !(status == "handshake" and msg.t == "hello")): return false
	var o = outbuf
	o.append_array(P.encode(msg))
	outbuf = o
	return true

# ---------------------------------------------------------------- frame
func _process(_d):
	var now = P.now_ms()
	match status:
		"resolving":
			var st = IP.get_resolve_item_status(_resolve_id)
			if st == IP.RESOLVER_STATUS_DONE:
				addr_ip = IP.get_resolve_item_address(_resolve_id)
				IP.erase_resolve_item(_resolve_id)
				if addr_ip == "": _conn_failed("unknown host " + addr_host)
				else: _connect_now()
			elif st == IP.RESOLVER_STATUS_ERROR or st == IP.RESOLVER_STATUS_NONE or now - _connect_t > 8000:
				IP.erase_resolve_item(_resolve_id)
				_conn_failed("couldn't find " + addr_host)
		"connecting":
			var st = peer.get_status()
			if st == StreamPeerTCP.STATUS_CONNECTED:
				peer.set_no_delay(true)
				_set_status("handshake", "joining")
				_last_rx = now
				send({t = "hello", v = P.VERSION, name = my_name, pw = password, token = token, owner = owner_key})
			elif st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE or now - _connect_t > 7000:
				_conn_failed("couldn't reach %s:%d (wrong address, the host isn't reachable from here, or a firewall blocks it)" % [addr_ip, addr_port])
		"handshake", "online":
			_read(now)
			if status == "online" and now - _ping_t > P.HEARTBEAT * 1000:
				_ping_t = now
				send({t = "ping", c = now})
			_write()
			if peer and now - _last_rx > P.TIMEOUT * 1000:
				_conn_failed("no answer from the host for %d s" % int(P.TIMEOUT))
		"reconnecting":
			if now >= _retry_t: _connect_now()
	_match_frame(now)
	_lan_frame(now)

func _read(now:int):
	if !peer: return
	var st = peer.get_status()
	var n = peer.get_available_bytes() if st == StreamPeerTCP.STATUS_CONNECTED else 0
	if n > 0:
		var r = peer.get_partial_data(min(n, 65536))
		if r[0] != OK:
			_conn_failed("read error %d" % r[0])
			return
		var b = inbuf
		b.append_array(r[1])
		inbuf = b
		_last_rx = now
	var buf:PoolByteArray = inbuf
	var start = 0
	var size = buf.size()
	for i in size:
		if buf[i] != 10: continue
		if i > start:
			var msg = P.parse_line(buf.subarray(start, i - 1).get_string_from_utf8())
			if msg != null: _handle(msg, now)
		start = i + 1
		if !peer: return
	if start > 0: inbuf = buf.subarray(start, size - 1) if start < size else PoolByteArray()
	if inbuf.size() > P.MAX_BUFFER: _conn_failed("too much data from the host")
	elif st != StreamPeerTCP.STATUS_CONNECTED and peer: _conn_failed("the host closed the connection")

func _write():
	if !peer or outbuf.size() == 0: return
	var r = peer.put_partial_data(outbuf)
	if r[0] != OK:
		_conn_failed("write error %d" % r[0])
		return
	var sent = int(r[1])
	outbuf = outbuf.subarray(sent, outbuf.size() - 1) if sent < outbuf.size() else PoolByteArray()

# ---------------------------------------------------------------- messages from the host
func _handle(m:Dictionary, now:int):
	match m.t:
		"welcome":
			pid = int(m.get("pid", 0))
			token = str(m.get("token", ""))
			lobby = m.get("lobby", {}) if typeof(m.get("lobby")) == TYPE_DICTIONARY else {}
			players = m.get("players", []) if typeof(m.get("players")) == TYPE_ARRAY else []
			var resumed = _was_online
			if !resumed:
				chat = []
				if typeof(m.get("chat")) == TYPE_ARRAY:
					for e in m.chat:
						if typeof(e) == TYPE_DICTIONARY: chat.append(_chat_entry(e))
				results = m.get("results", []) if typeof(m.get("results")) == TYPE_ARRAY else []
			var s = P.num(m, "s", 0, 1e15)
			if s != null: offset = float(s) - now
			_was_online = true
			_reconnecting = false
			_set_status("online", "in lobby")
			_ping_t = 0
			send({t = "ping", c = now})
			_check_map()
			emit_signal("changed", "lobby")
			emit_signal("changed", "players")
			emit_signal("changed", "chat")
			if resumed: emit_signal("notice", "Reconnected.", false)
		"reject":
			var why = str(m.get("reason", "refused"))
			_reconnecting = false
			leaving = true
			_close_peer()
			_was_online = false
			if hosting(): host_node.stop("the host couldn't join its own lobby")
			_set_status("idle", why)
			emit_signal("notice", "The lobby refused to let you in: " + why, true)
		"lobby":
			if typeof(m.get("lobby")) != TYPE_DICTIONARY: return
			lobby = m.lobby
			_rules_pending = {}
			_check_map()
			emit_signal("changed", "lobby")
		"players":
			if typeof(m.get("list")) != TYPE_ARRAY: return
			players = m.list
			emit_signal("changed", "players")
		"chat":
			var e = _chat_entry(m)
			if e.mine:
				for i in range(chat.size() - 1, -1, -1):
					if chat[i].get("pending") and chat[i].get("seq") == e.seq:
						chat.remove(i)
						break
			chat.append(e)
			while chat.size() > P.CHAT_HISTORY + 20: chat.pop_front()
			emit_signal("changed", "chat")
		"error":
			var what = str(m.get("what", ""))
			var text = P.clean_text(m.get("msg", ""), 200)
			if what == "chat" and m.has("seq"):
				for e in chat:
					if e.get("pending") and int(e.get("seq", -1)) == int(m.seq):
						e["pending"] = false
						e["failed"] = text
				emit_signal("changed", "chat")
			emit_signal("notice", text, true)
		"ping": send({t = "pong", s = m.get("s", 0)})
		"pong":
			var c = P.num(m, "c", 0, 1e15)
			var s = P.num(m, "s", 0, 1e15)
			if c == null or s == null or now < int(c): return
			rtt = now - int(c)
			_sync.append([rtt, float(s) + rtt / 2.0 - now])
			while _sync.size() > 8: _sync.pop_front()
			var best = _sync[0]
			for x in _sync:
				if x[0] < best[0]: best = x
			offset = best[1]
		"match_load": _on_match_load(m)
		"match_go":
			if int(P.num(m, "m", 0, 1e9) if P.num(m, "m", 0, 1e9) != null else -1) != match_id or phase == "none": return
			var at = P.num(m, "at", 0, 1e15)
			if at == null: return
			go_local = int(float(at) - offset)
			if phase in ["loading", "ready"]: phase = "waiting" if phase == "ready" else phase
			emit_signal("changed", "match")
		"board":
			if typeof(m.get("list")) != TYPE_ARRAY: return
			board = m.list
			emit_signal("changed", "board")
		"match_end":
			if typeof(m.get("results")) != TYPE_ARRAY: return
			results = m.results
			results_match = int(P.num(m, "m", 0, 1e9) if P.num(m, "m", 0, 1e9) != null else 0)
			if results_match == match_id and phase in ["loading", "ready", "waiting", "playing"]:
				aborted = true # the match ended before this game did (host stopped it / time ran out)
				if phase == "playing" and is_instance_valid(game) and !game.ending: game.end(Globals.END_GIVEUP)
			emit_signal("changed", "results")
		"kicked":
			leaving = true
			_close_peer()
			_was_online = false
			_set_status("idle", "removed by the host")
			emit_signal("notice", "The host removed you from the lobby.", true)
		"closing":
			leaving = true
			_close_peer()
			_was_online = false
			_set_status("idle", str(m.get("reason", "the lobby closed")))
			emit_signal("notice", "The lobby closed: " + P.clean_text(m.get("reason", ""), 100), true)

func _chat_entry(m:Dictionary) -> Dictionary:
	return {pid = int(m.get("pid", 0)), name = P.clean_name(m.get("name", "")) if !m.get("sys", false) else "",
		text = P.clean_text(m.get("text", ""), P.CHAT_MAX), ts = int(m.get("ts", 0)) if typeof(m.get("ts")) in [TYPE_INT, TYPE_REAL] else 0,
		sys = bool(m.get("sys", false)), mine = int(m.get("pid", 0)) == pid and pid != 0, seq = int(m.get("seq", -1)) if typeof(m.get("seq")) in [TYPE_INT, TYPE_REAL] else -1}

# ---------------------------------------------------------------- actions (the host checks every one)
func send_chat(text:String) -> String:
	var t = P.clean_text(text, P.CHAT_MAX)
	if t == "": return "empty"
	if status != "online": return "not connected"
	chat_seq += 1
	if !send({t = "chat", seq = chat_seq, text = t}): return "not connected"
	chat.append({pid = pid, name = my_name, text = t, ts = OS.get_unix_time(), sys = false, mine = true, seq = chat_seq, pending = true})
	emit_signal("changed", "chat")
	return ""

func set_ready(on:bool):
	send({t = "ready", on = on})

func pick_map(song) -> String:
	if !is_host(): return "only the host picks the map"
	var info = P.map_info(song)
	send({t = "set_map", map = info})
	return ""

var _rules_pending:Dictionary = {}
func set_rules(r:Dictionary):
	_rules_pending = P.clean_rules(r)
	send({t = "set_rules", rules = r})

# the rules as the host last set them (a change still on its way counts)
func rules_now() -> Dictionary:
	return _rules_pending.duplicate(true) if !_rules_pending.empty() else P.clean_rules(lobby.get("rules", {}))

func set_lobby_cfg(d:Dictionary):
	var m = d.duplicate()
	m["t"] = "set_lobby"
	send(m)

func start_match():
	# the host's own hit window / hitbox are the match timing
	var r = lobby.get("rules", {}).duplicate(true) if typeof(lobby.get("rules")) == TYPE_DICTIONARY else {}
	r["hw"] = float(Rhythia.get("hitwindow_ms")) if snapshot.empty() else float(snapshot.get("hitwindow_ms", 55))
	r["hb"] = float(Rhythia.get("note_hitbox_size")) if snapshot.empty() else float(snapshot.get("note_hitbox_size", 1.14))
	r["shw"] = bool(Rhythia.get("speed_hitwindow")) if snapshot.empty() else bool(snapshot.get("speed_hitwindow", false))
	var cur = lobby.get("rules", {})
	if typeof(cur) != TYPE_DICTIONARY or abs(float(cur.get("hw", 0)) - r.hw) > 0.01 or abs(float(cur.get("hb", 0)) - r.hb) > 0.0001 or bool(cur.get("shw", false)) != r.shw:
		send({t = "set_rules", rules = r}) # (resets ready flags: only when the timing actually changed)
	send({t = "start"})

func abort_match():
	send({t = "abort"})

func kick(p:int):
	send({t = "kick", pid = p})

func give_host(p:int):
	send({t = "give_host", pid = p})

# does this game have the host's map (same notes + audio)? -> tells the host
func _check_map():
	var m = lobby.get("map", {})
	var key = P.map_key(m) if typeof(m) == TYPE_DICTIONARY else ""
	if key == have_key: return
	have_key = key
	if key == "":
		my_have = "?"
		return
	my_have = local_have(m)
	send({t = "have", key = key, st = my_have})
	emit_signal("changed", "lobby")

static func find_song(id:String):
	var s = Rhythia.registry_song.get_item(id)
	if !(s is Object) or s.is_online or s.is_broken: return null
	return s

func local_have(m:Dictionary) -> String:
	if Engine.has_meta("rr_mp_test_hide") and str(m.id) in Engine.get_meta("rr_mp_test_hide"): return "missing"
	var s = find_song(str(m.id))
	if !s: return "missing"
	var info = P.map_info(s)
	return "ok" if info.hash == str(m.hash) else "mismatch"

# ---------------------------------------------------------------- the match
func in_match() -> bool:
	return phase in ["loading", "ready", "waiting", "playing"]

func _on_match_load(m:Dictionary):
	var mid = P.num(m, "m", 0, 1e9)
	var mp = P.clean_map(m.get("map"))
	if mid == null or mp.empty(): return
	match_id = int(mid)
	match_map = mp
	match_rules = P.clean_rules(m.get("rules"))
	aborted = false
	go_local = -1
	go_late = 0
	score_seq = 0
	_last_sent = {}
	board = []
	var song = find_song(mp.id)
	if !song or local_have(mp) != "ok":
		send({t = "done", m = match_id, seq = 1, end = "quit", score = 0, hits = 0, misses = 0, combo = 0, mc = 0, prog = 0})
		emit_signal("notice", "You don't have this map, so you sit this match out.", true)
		return
	phase = "loading"
	emit_signal("changed", "match")
	if test_no_scene: return
	apply_rules(match_rules)
	Engine.set_meta("rr_mp_match", true)
	Rhythia.select_song(song)
	if Engine.has_meta("rr_mp_test_autoplay"): # (automated tests only: the game's autoplayer plays)
		_test_autoplay = true
		Rhythia.replay = Replay.new()
		Rhythia.replaying = true
		Rhythia.replay_path = "" # (songload reads it: no file = the autoplayer)
	get_tree().call_deferred("change_scene", "res://scenes/loaders/songload.tscn")

# session rules on, the player's own values saved first (also to RESTORE, so a crash mid-match
# can't leave them changed: menu2 calls recover() on the next start)
func apply_rules(r:Dictionary):
	if snapshot.empty():
		for k in P.ALL_MODS: snapshot[k] = bool(Rhythia.get(k))
		for k in ["mod_speed_level", "custom_speed", "hitwindow_ms", "note_hitbox_size", "speed_hitwindow", "start_offset", "record_replays"]:
			snapshot[k] = Rhythia.get(k)
		var f = File.new()
		if f.open(RESTORE, File.WRITE) == OK:
			f.store_string(to_json(snapshot))
			f.close()
	for k in P.ALL_MODS: Rhythia.set(k, k in r.get("mods", []))
	Rhythia.set("mod_nofail", true)
	var sp = float(r.get("speed", 1.0))
	if abs(sp - 1.0) < 0.001:
		Rhythia.set("mod_speed_level", Globals.SPEED_NORMAL)
	else:
		Rhythia.set("custom_speed", sp)
		Globals.speed_multi[Globals.SPEED_CUSTOM] = sp
		Rhythia.set("mod_speed_level", Globals.SPEED_CUSTOM)
	Rhythia.set("hitwindow_ms", float(r.get("hw", 55)))
	Rhythia.set("note_hitbox_size", float(r.get("hb", 1.14)))
	Rhythia.set("speed_hitwindow", bool(r.get("shw", false)))
	Rhythia.set("start_offset", 0)
	Rhythia.set("record_replays", false) # (no replay files or personal bests from session runs)
	Rhythia.replaying = false
	Rhythia.queue_active = false

func restore_rules():
	if snapshot.empty(): return
	_apply_snapshot(snapshot)
	snapshot = {}
	Directory.new().remove(RESTORE)

static func _apply_snapshot(s:Dictionary):
	for k in s.keys():
		if k == "custom_speed":
			Rhythia.set(k, float(s[k]))
			Globals.speed_multi[Globals.SPEED_CUSTOM] = float(s[k])
		elif k == "mod_speed_level": continue
		else: Rhythia.set(k, s[k])
	if s.has("mod_speed_level"): Rhythia.set("mod_speed_level", int(s.mod_speed_level))

# the game crashed or was closed during a match: put the player's own settings back
static func recover():
	var f = File.new()
	if !f.file_exists(RESTORE): return
	if f.open(RESTORE, File.READ) != OK: return
	var r = JSON.parse(f.get_as_text())
	f.close()
	Directory.new().remove(RESTORE)
	if r.error == OK and typeof(r.result) == TYPE_DICTIONARY:
		_apply_snapshot(r.result)
		if Rhythia.has_method("save_settings"): Rhythia.save_settings()
		print("[mp] restored the settings a multiplayer match had changed")

# Game.gd, when the map is loaded: tell the host, then wait for the shared start
func game_ready(g):
	game = g
	if aborted or !in_match():
		return
	send({t = "loaded", m = match_id})
	phase = "waiting" if go_local >= 0 else "ready"
	if ResourceLoader.exists("res://mods/replay/MPOverlay.gd"):
		var o = load("res://mods/replay/MPOverlay.gd").new()
		o.client = self
		g.get_parent().add_child(o)
	emit_signal("changed", "match")

func go_open() -> bool:
	if aborted or status == "idle": return true # (lost the lobby before the start: just play)
	return phase == "playing"

func go_late_ms() -> int:
	return int(clamp(go_late, 0, 600000))

func match_aborted() -> bool:
	return aborted

func game_end(g, end_type:int):
	if !in_match(): return
	_send_score(g, true, end_type == Globals.END_PASS)
	phase = "done"
	game = null
	Engine.remove_meta("rr_mp_match")
	Engine.set_meta("rr_mp_return", true)
	emit_signal("changed", "match")

# menu2, back from a match: own settings back, lobby screen up
var _test_autoplay:bool = false
func back_in_menu():
	restore_rules()
	if _test_autoplay:
		_test_autoplay = false
		Rhythia.replaying = false
	if phase == "done" or !in_match(): _reset_match()
	send({t = "back"})

func _reset_match():
	phase = "none"
	game = null
	go_local = -1
	Engine.remove_meta("rr_mp_match")

func _reset_match_if_waiting():
	if phase in ["loading", "ready", "waiting"]: aborted = true

func _match_frame(now:int):
	if !in_match(): return
	if !test_no_scene and !Rhythia.mod_nofail:
		Rhythia.set("mod_nofail", true) # No Fail stays on for the whole match, whatever toggles it
		print("[mp] No Fail re-enforced")
	if phase == "waiting" and go_local >= 0 and now >= go_local:
		phase = "playing"
		go_late = now - go_local
		emit_signal("changed", "match")
	if phase == "playing" and is_instance_valid(game) and now - _score_t >= 250:
		_score_t = now
		_send_score(game, false, false)

func _send_score(g, final:bool, passed:bool):
	if !is_instance_valid(g): return
	var sp = g.get_node_or_null("Spawn")
	var prog = 0.0
	if sp and float(g.last_ms) > 0: prog = clamp(float(sp.ms) / float(g.last_ms), 0.0, 1.0)
	var s = {score = int(g.score), combo = int(g.combo), mc = int(g.max_combo), hits = int(g.hits),
		misses = int(g.misses), prog = stepify(prog, 0.001)}
	if !final and s.hash() == _last_sent.hash(): return
	_last_sent = s.duplicate()
	score_seq += 1
	var msg = s.duplicate()
	msg["t"] = "done" if final else "score"
	msg["m"] = match_id
	msg["seq"] = score_seq
	if final: msg["end"] = "pass" if passed else "quit"
	send(msg)

# ---------------------------------------------------------------- LAN lobbies
func lan_listen(on:bool):
	if on and !lan_udp:
		lan_udp = PacketPeerUDP.new()
		var err = lan_udp.listen(P.LAN_PORT, "*")
		if err != OK:
			lan_udp = null
			lan_error = "LAN discovery isn't available here (UDP port %d is busy - another game on this computer may be using it)." % P.LAN_PORT
		else: lan_error = ""
		emit_signal("changed", "lan")
	elif !on and lan_udp:
		lan_udp.close()
		lan_udp = null

func _lan_frame(now:int):
	if !lan_udp: return
	var got = false
	while lan_udp.get_available_packet_count() > 0:
		var pkt = lan_udp.get_packet()
		var ip = lan_udp.get_packet_ip()
		if pkt.size() > 2048: continue
		var r = JSON.parse(pkt.get_string_from_utf8())
		if r.error != OK or typeof(r.result) != TYPE_DICTIONARY or r.result.get("rr_mp") != P.VERSION: continue
		var d = r.result
		var port = P.num(d, "port", 1, 65535)
		if port == null: continue
		var key = "%s:%d" % [ip, int(port)]
		lan[key] = {ip = ip, port = int(port), name = P.clean_text(d.get("name", ""), P.LOBBY_NAME_MAX),
			n = int(P.num(d, "n", 0, 99) if P.num(d, "n", 0, 99) != null else 0), max = int(P.num(d, "max", 0, 99) if P.num(d, "max", 0, 99) != null else 0),
			state = P.clean_text(d.get("state", ""), 12), map = P.clean_text(d.get("map", ""), 80), pw = bool(d.get("pw", false)),
			code = P.clean_text(d.get("code", ""), 12), seen = now}
		got = true
	for k in lan.keys():
		if now - lan[k].seen > 5000:
			lan.erase(k)
			got = true
	if got: emit_signal("changed", "lan")

func _exit_tree():
	leave()
	lan_listen(false)
