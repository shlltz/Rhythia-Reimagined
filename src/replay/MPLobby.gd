extends Reference
# Multiplayer lobby rules - the authoritative session state. Runs only on the host, inside MPHost,
# and knows nothing about sockets: MPHost turns connections into player ids, hands every message to
# hello() / handle() / disconnected(), calls tick() each frame and sends what lands in `out`.
# Every host-only action is checked here (pid == host_pid), not just hidden in the UI.

const P = preload("res://mods/replay/MPProto.gd")

var lobby_name:String = "Lobby"
var max_players:int = 8
var password:String = ""
var owner_key:String = ""      # the creating player's hello carries it: that player is the first host
var host_pid:int = 0
var owner_pid:int = 0          # the player whose game runs this server (lobby ends when they leave)
var next_pid:int = 1
var players:Dictionary = {}    # pid -> player (see _new_player)
var order:Array = []           # pids in join order
var state:String = "lobby"     # lobby | loading | playing
var map:Dictionary = {}
var rules:Dictionary = {speed = 1.0, mods = [], hw = 55.0, hb = 1.14}
var match_id:int = 0
var participants:Array = []
var match_names:Dictionary = {} # pid -> name, for results of players who left during the match
var go_at:int = 0
var load_deadline:int = 0
var match_deadline:int = 0
var chat_log:Array = []
var last_results:Array = []
var code:String = ""           # set by the transport: room code and reachable addresses
var addresses:Array = []
var closed:bool = false        # the owner left: the transport shuts the server down
var kicked_tokens:Array = []   # a removed player's client can't come back in by reconnecting
var now:int = 0
var out:Array = []             # [target, msg]  target = pid, or -1 for everyone online
var drop:Array = []            # pids whose connection the transport closes after sending
var lobby_dirty:bool = false
var players_dirty:bool = false
var board_dirty:bool = false
var _players_sent:int = -100000
var _board_sent:int = -100000
var _ping_t:int = -100000

func _init(cfg:Dictionary = {}):
	lobby_name = P.clean_text(cfg.get("name", "Lobby"), P.LOBBY_NAME_MAX)
	if lobby_name == "": lobby_name = "Lobby"
	var mx = P.num(cfg, "max", 2, P.MAX_PLAYERS)
	max_players = int(mx) if mx != null else 8
	password = P.clean_text(cfg.get("pw", ""), P.PW_MAX)
	owner_key = str(cfg.get("owner_key", ""))
	rules = P.clean_rules(cfg.get("rules", {}))
	now = P.now_ms()

# ---------------------------------------------------------------- joining
# -> {ok, pid, replaced} or {ok = false, reason}
func hello(msg:Dictionary) -> Dictionary:
	if typeof(msg) != TYPE_DICTIONARY or msg.get("t") != "hello": return {ok = false, reason = "expected hello"}
	if msg.get("v") != P.VERSION:
		return {ok = false, reason = "version mismatch: the host runs %s, you run %s - update Rhythia|Reimagined" % [P.VERSION, str(msg.get("v", "?"))]}
	var tok = msg.get("token", "")
	if typeof(tok) == TYPE_STRING and tok != "" and tok in kicked_tokens:
		return {ok = false, reason = "the host removed you from this lobby"}
	if typeof(tok) == TYPE_STRING and tok != "":
		for pid in order:
			var p = players[pid]
			if p.token == tok: # reconnect: same slot, same score
				var replaced = p.conn == "ok"
				p.conn = "ok"
				p.last_seen = now
				players_dirty = true
				if !replaced: _sys("%s reconnected" % p.name)
				return {ok = true, pid = pid, replaced = replaced}
	if password != "" and str(msg.get("pw", "")) != password:
		return {ok = false, reason = "wrong password"}
	if active_count() >= max_players:
		return {ok = false, reason = "the lobby is full (%d players)" % max_players}
	var pid = next_pid
	next_pid += 1
	var p = _new_player(pid, P.clean_name(msg.get("name", "")))
	players[pid] = p
	order.append(pid)
	if owner_pid == 0 and owner_key != "" and str(msg.get("owner", "")) == owner_key: owner_pid = pid
	if host_pid == 0 or (pid == owner_pid and !players.has(host_pid)): host_pid = pid
	_sys("%s joined" % p.name)
	players_dirty = true
	lobby_dirty = true
	return {ok = true, pid = pid, replaced = false}

func _new_player(pid:int, nm:String) -> Dictionary:
	randomize()
	return {pid = pid, name = nm, token = "%08x%08x%08x" % [randi(), randi(), OS.get_ticks_usec() & 0x7fffffff],
		conn = "ok", lost_at = 0, last_seen = now, ready = false, have = "?", ping = -1, status = "idle",
		chat_times = [], chat_seq = -1, score_seq = -1, loaded = false, finished = false, s = _zero()}

func _zero() -> Dictionary:
	return {score = 0, combo = 0, mc = 0, hits = 0, misses = 0, prog = 0.0}

func welcome(pid:int) -> Dictionary:
	var p = players[pid]
	var w = {t = "welcome", v = P.VERSION, pid = pid, token = p.token, s = now, lobby = lobby_dict(),
		players = players_list(), chat = chat_log, results = last_results}
	if state != "lobby" and pid in participants:
		w["match"] = {m = match_id, map = map, rules = rules, at = go_at if state == "playing" else -1}
	return w

func active_count() -> int:
	var n = 0
	for pid in order:
		if players[pid].conn == "ok": n += 1
	return n

# ---------------------------------------------------------------- messages
func handle(pid:int, msg:Dictionary):
	if !players.has(pid): return
	var p = players[pid]
	p.last_seen = now
	match msg.t:
		"ping": _send(pid, {t = "pong", c = msg.get("c", 0), s = now})
		"pong":
			var s = P.num(msg, "s", 0, 1e15)
			if s != null and now >= int(s):
				var rt = now - int(s)
				if p.ping < 0 or abs(rt - p.ping) > 4: players_dirty = true
				p.ping = rt
		"chat": _chat(p, msg)
		"ready":
			var on = P.boolean(msg, "on")
			if on == null: return _bad(pid, "ready needs on")
			if state != "lobby": return _err(pid, "ready", "a match is running")
			if on and map.empty(): return _err(pid, "ready", "the host hasn't picked a map yet")
			if on and p.have != "ok": return _err(pid, "ready", "you need this map to ready up")
			if p.ready != on:
				p.ready = on
				players_dirty = true
		"have":
			if str(msg.get("key", "")) != P.map_key(map): return # (an answer for an older map)
			var st = msg.get("st")
			if !(st in ["ok", "missing", "mismatch"]): return _bad(pid, "have needs st")
			if p.have != st:
				p.have = st
				if st != "ok": p.ready = false
				players_dirty = true
		"set_map":
			if !_host(pid, "map") or !_in_lobby(pid, "map"): return
			var m = P.clean_map(msg.get("map"))
			if m.empty(): return _err(pid, "map", "that map entry isn't valid")
			map = m
			for q in players.values():
				q.have = "?"
				q.ready = false
			lobby_dirty = true
			players_dirty = true
			_sys("map: %s" % (m.name if m.name != "" else m.id))
		"set_rules":
			if !_host(pid, "rules") or !_in_lobby(pid, "rules"): return
			var r = P.clean_rules(msg.get("rules"))
			if r.hash() != rules.hash():
				rules = r
				for q in players.values(): q.ready = false
				lobby_dirty = true
				players_dirty = true
		"set_lobby":
			if !_host(pid, "lobby"): return
			var nm = P.clean_text(msg.get("name", lobby_name), P.LOBBY_NAME_MAX)
			if nm != "": lobby_name = nm
			if msg.has("max"):
				var mx = P.num(msg, "max", 2, P.MAX_PLAYERS)
				if mx == null or int(mx) < active_count(): return _err(pid, "lobby", "the player limit can't be below the players in the lobby")
				max_players = int(mx)
			if msg.has("pw"): password = P.clean_text(msg.get("pw"), P.PW_MAX)
			lobby_dirty = true
		"start":
			if !_host(pid, "start") or !_in_lobby(pid, "start"): return
			_start_match(pid)
		"abort":
			if !_host(pid, "abort"): return
			if state == "lobby": return _err(pid, "abort", "no match is running")
			_sys("the host stopped the match")
			_end_match(true)
		"loaded":
			if !_this_match(msg) or !(pid in participants) or state == "lobby": return
			if !p.loaded:
				p.loaded = true
				p.status = "loaded" if state == "loading" else "playing"
				players_dirty = true
			if state == "playing": _send(pid, {t = "match_go", m = match_id, at = go_at}) # late: starts at once
			elif _all_loaded(): _go()
		"score": _score(p, msg, false)
		"done": _score(p, msg, true)
		"kick":
			if !_host(pid, "kick"): return
			var tgt = int(P.num(msg, "pid", 1, 1e9) if P.num(msg, "pid", 1, 1e9) != null else 0)
			if tgt == pid or !players.has(tgt): return _err(pid, "kick", "no such player")
			if tgt == owner_pid: return _err(pid, "kick", "the lobby's own host machine can't be removed")
			_send(tgt, {t = "kicked"})
			kicked_tokens.append(players[tgt].token)
			drop.append(tgt)
			_remove(tgt, "was removed by the host")
		"give_host":
			if !_host(pid, "host"): return
			var tgt2 = int(P.num(msg, "pid", 1, 1e9) if P.num(msg, "pid", 1, 1e9) != null else 0)
			if !players.has(tgt2) or players[tgt2].conn != "ok": return _err(pid, "host", "no such player")
			host_pid = tgt2
			_sys("%s is now the host" % players[tgt2].name)
			lobby_dirty = true
			players_dirty = true
		"back": pass
		"bye":
			drop.append(pid)
			_remove(pid, "left")
		_: _bad(pid, "unknown message " + str(msg.t).substr(0, 20))

func _host(pid:int, what:String) -> bool:
	if pid == host_pid: return true
	_err(pid, what, "only the host can do that")
	return false

func _in_lobby(pid:int, what:String) -> bool:
	if state == "lobby": return true
	_err(pid, what, "not while a match is running")
	return false

func _this_match(msg:Dictionary) -> bool:
	var m = P.num(msg, "m", 0, 1e9)
	return m != null and int(m) == match_id

func _err(pid:int, what:String, text:String):
	_send(pid, {t = "error", what = what, msg = text})

var _bad_count:Dictionary = {}
func _bad(pid:int, why:String):
	_bad_count[pid] = _bad_count.get(pid, 0) + 1
	_err(pid, "protocol", why)
	if _bad_count[pid] > 30: # a broken or hostile client: close it
		drop.append(pid)
		_remove(pid, "was disconnected (invalid messages)")

# ---------------------------------------------------------------- chat
func _chat(p:Dictionary, msg:Dictionary):
	var seq = P.num(msg, "seq", 0, 1e12)
	if seq == null: return _bad(p.pid, "chat needs seq")
	if int(seq) <= p.chat_seq: return # a repeat of a message already relayed
	var text = P.clean_text(msg.get("text"), P.CHAT_MAX)
	if text == "": return _err(p.pid, "chat", "empty message")
	var keep = []
	for t in p.chat_times:
		if now - t < P.CHAT_WINDOW * 1000: keep.append(t)
	p.chat_times = keep
	if keep.size() >= P.CHAT_RATE:
		_send(p.pid, {t = "error", what = "chat", seq = int(seq), msg = "slow down: %d messages per %d s" % [P.CHAT_RATE, int(P.CHAT_WINDOW)]})
		return
	p.chat_seq = int(seq)
	p.chat_times.append(now)
	_post({t = "chat", pid = p.pid, name = p.name, text = text, ts = OS.get_unix_time(), seq = int(seq)})

func _sys(text:String):
	_post({t = "chat", pid = 0, name = "", text = text, ts = OS.get_unix_time(), sys = true})

func _post(e:Dictionary):
	chat_log.append(e)
	while chat_log.size() > P.CHAT_HISTORY: chat_log.pop_front()
	_send(-1, e)

# ---------------------------------------------------------------- matches
func _start_match(pid:int):
	if map.empty(): return _err(pid, "start", "pick a map first")
	var no_map = []
	var not_ready = []
	for q in order:
		var p = players[q]
		if p.conn != "ok": continue
		if p.have != "ok": no_map.append(p.name + (" (checking)" if p.have == "?" else (" (different version)" if p.have == "mismatch" else "")))
		elif q != host_pid and !p.ready: not_ready.append(p.name)
	if !no_map.empty(): return _err(pid, "start", "missing the map: " + PoolStringArray(no_map).join(", "))
	if !not_ready.empty(): return _err(pid, "start", "not ready yet: " + PoolStringArray(not_ready).join(", "))
	match_id += 1
	participants = []
	match_names = {}
	for q in order:
		var p = players[q]
		if p.conn != "ok": continue
		participants.append(q)
		match_names[q] = p.name
		p.status = "loading"
		p.loaded = false
		p.finished = false
		p.s = _zero()
		p.score_seq = -1
	state = "loading"
	load_deadline = now + int(P.LOAD_TIMEOUT * 1000)
	go_at = 0
	for q in participants: _send(q, {t = "match_load", m = match_id, map = map, rules = rules})
	_sys("match %d: %s" % [match_id, map.name if map.name != "" else map.id])
	lobby_dirty = true
	players_dirty = true
	board_dirty = true

func _all_loaded() -> bool:
	for q in participants:
		if players.has(q) and players[q].conn == "ok" and !players[q].loaded: return false
	return true

# everyone has loaded (or the wait ran out): one shared start time, a little ahead so the message
# reaches everyone first; each game holds its lead-in until then (MPClient.go_open)
func _go():
	var lag = 0
	for q in participants:
		if players.has(q): lag = max(lag, players[q].ping)
	go_at = now + P.START_LEAD + int(clamp(lag, 0, 1000))
	state = "playing"
	var length = float(map.get("len", 0)) / max(float(rules.speed), 0.1)
	match_deadline = go_at + int(length) + 90000
	for q in participants:
		if !players.has(q): continue
		var p = players[q]
		if p.loaded:
			p.status = "playing"
			_send(q, {t = "match_go", m = match_id, at = go_at})
	lobby_dirty = true
	players_dirty = true

const MAX_POINTS = 800 # most points one hit can give (50 x speed bonus 1.9 x combo level 8)
func _score(p:Dictionary, msg:Dictionary, final:bool):
	if !_this_match(msg) or !(p.pid in participants) or p.finished: return
	var seq = P.num(msg, "seq", 0, 1e12)
	if seq == null or int(seq) <= p.score_seq: return # repeat / out of order
	var n = int(map.get("notes", 0)) + 2
	var sc = P.num(msg, "score", 0, 2e9)
	var hits = P.num(msg, "hits", 0, n)
	var misses = P.num(msg, "misses", 0, n)
	var combo = P.num(msg, "combo", 0, n)
	var mc = P.num(msg, "mc", 0, n)
	var prog = P.num(msg, "prog", 0, 1)
	if sc == null or hits == null or misses == null or combo == null or mc == null or prog == null:
		return _bad(p.pid, "score values out of range")
	var s = p.s
	if int(hits) + int(misses) > n or int(combo) > int(hits) or int(mc) > int(hits) or int(mc) < int(combo) \
			or int(sc) > int(hits) * MAX_POINTS or int(sc) < s.score or int(hits) < s.hits or int(misses) < s.misses:
		return _bad(p.pid, "score update rejected")
	p.score_seq = int(seq)
	p.s = {score = int(sc), combo = int(combo), mc = int(mc), hits = int(hits), misses = int(misses), prog = float(prog)}
	if final:
		p.finished = true
		p.status = "finished" if msg.get("end") == "pass" else "quit"
		players_dirty = true
	board_dirty = true
	if final: _check_end()

func _check_end():
	if state == "lobby": return
	for q in participants:
		if !players.has(q): continue
		var p = players[q]
		if !p.finished and p.conn == "ok": return
	_end_match(false)

func _end_match(aborted:bool):
	var res = []
	for q in participants:
		var p = players.get(q)
		var s = p.s if p else _zero()
		var st = "left"
		if p:
			if p.finished: st = p.status
			elif aborted: st = "stopped"
			elif p.conn != "ok": st = "disconnected"
			elif !p.loaded: st = "did not load"
			else: st = "did not finish"
		var tot = s.hits + s.misses
		res.append({pid = q, name = p.name if p else match_names.get(q, "?"), score = s.score, mc = s.mc,
			hits = s.hits, misses = s.misses, acc = (100.0 * s.hits / tot) if tot > 0 else 0.0, status = st})
	res.sort_custom(self, "_by_score")
	for i in res.size(): res[i]["rank"] = i + 1
	last_results = res
	var mid = match_id
	state = "lobby"
	participants = []
	for p in players.values():
		p.ready = false
		p.status = "idle"
		p.loaded = false
	_send(-1, {t = "match_end", m = mid, results = res, aborted = aborted})
	lobby_dirty = true
	players_dirty = true

func _by_score(a, b) -> bool:
	if a.score != b.score: return a.score > b.score
	if a.acc != b.acc: return a.acc > b.acc
	return a.pid < b.pid

# ---------------------------------------------------------------- leaving / connection loss
func disconnected(pid:int):
	if !players.has(pid): return
	var p = players[pid]
	if p.conn == "lost": return
	p.conn = "lost"
	p.lost_at = now
	p.ready = false
	_sys("%s lost connection" % p.name)
	players_dirty = true
	if pid == host_pid and players.has(owner_pid) and players[owner_pid].conn == "ok" and owner_pid != pid:
		host_pid = owner_pid
		_sys("%s is now the host" % players[owner_pid].name)
		lobby_dirty = true
	_check_end()

func _remove(pid:int, why:String):
	if !players.has(pid): return
	var nm = players[pid].name
	players.erase(pid)
	order.erase(pid)
	_sys("%s %s" % [nm, why])
	if pid == owner_pid:
		closed = true
	if pid == host_pid:
		host_pid = 0
		if players.has(owner_pid): host_pid = owner_pid
		else:
			for q in order:
				if players[q].conn == "ok":
					host_pid = q
					break
		if host_pid != 0: _sys("%s is now the host" % players[host_pid].name)
	players_dirty = true
	lobby_dirty = true
	_check_end()

# ---------------------------------------------------------------- time
func tick(now_ms:int):
	now = now_ms
	for pid in order.duplicate():
		var p = players[pid]
		if p.conn == "lost" and now - p.lost_at > P.RECONNECT_KEEP * 1000:
			_remove(pid, "timed out")
	if now - _ping_t >= P.HEARTBEAT * 1000:
		_ping_t = now
		for pid in order:
			if players[pid].conn == "ok": _send(pid, {t = "ping", s = now})
	if state == "loading" and now >= load_deadline: _go()
	if state == "playing" and now >= match_deadline: _end_match(false)
	if lobby_dirty:
		lobby_dirty = false
		_send(-1, {t = "lobby", lobby = lobby_dict()})
	if players_dirty and now - _players_sent >= 100:
		players_dirty = false
		_players_sent = now
		_send(-1, {t = "players", list = players_list()})
	if board_dirty and state != "lobby" and now - _board_sent >= 250:
		board_dirty = false
		_board_sent = now
		_send(-1, {t = "board", m = match_id, list = board()})

func _send(target:int, msg:Dictionary):
	out.append([target, msg])

# ---------------------------------------------------------------- views sent to players
func lobby_dict() -> Dictionary:
	return {name = lobby_name, max = max_players, pw = password != "", host = host_pid, owner = owner_pid,
		state = state, map = map, rules = rules, m = match_id, code = code, addr = addresses, n = active_count()}

func players_list() -> Array:
	var l = []
	for pid in order:
		var p = players[pid]
		l.append({pid = pid, name = p.name, host = pid == host_pid, ready = p.ready, conn = p.conn, ping = p.ping,
			have = p.have, status = p.status, s = p.s, in_match = pid in participants})
	return l

func board() -> Array:
	var l = []
	for q in participants:
		var p = players.get(q)
		if !p: continue
		var tot = p.s.hits + p.s.misses
		l.append({pid = q, name = p.name, score = p.s.score, combo = p.s.combo, mc = p.s.mc, misses = p.s.misses,
			acc = (100.0 * p.s.hits / tot) if tot > 0 else 100.0, prog = p.s.prog, status = p.status, conn = p.conn})
	l.sort_custom(self, "_by_score")
	return l
