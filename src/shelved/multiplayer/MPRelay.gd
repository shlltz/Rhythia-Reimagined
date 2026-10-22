extends Reference
# Online lobbies through a relay (relay/rr_relay.py, docs/RELAY.md). The host's game keeps one
# outbound WebSocket to the relay (Tunnel) and gets a room code; each guest connects with its own
# WebSocket (Guest). Both look like a StreamPeerTCP to MPHost / MPClient, so the lobby protocol
# (MPProto JSON lines) and every host-side check stay exactly as on a LAN. The relay only routes
# bytes; it never reads or changes the game's messages.

const PROTO = "rr-relay-1"
const P = preload("res://mods/replay/MPProto.gd")
const CHUNK = 16000              # bytes per WebSocket message (the relay takes up to 64 KB)
const PING_MS = 3000             # relay ping (also keeps the relay's idle timer happy)
const OPEN_TIMEOUT = 10000
const BACKOFF_MAX = 16000
# relay refusals that retrying can't fix
const FINAL = ["not_found", "expired", "full", "version", "game_version", "closed", "throttled", "bad_url", "protocol", "busy"]

const TEXTS = {
	not_found = "No room with that code. Check the code, or the room has closed.",
	expired = "That room has closed.",
	full = "The room is full.",
	host_away = "The host's connection dropped - waiting for it to come back.",
	version = "This relay runs a different relay version.",
	game_version = "Different multiplayer versions",
	throttled = "Too many join attempts from your network - wait a minute.",
	closed = "The host closed the connection.",
	rate = "Too much data - the relay cut the connection.",
	busy = "The relay is full right now - try again later.",
	restarting = "The relay is restarting - reconnecting.",
}

# "relay.example.org" / "https://relay.example.org/rr" / "ws://127.0.0.1:8080" -> a ws(s) base URL, "" if unusable
static func base_url(text:String) -> String:
	var t = text.strip_edges()
	if t == "" or " " in t: return ""
	var scheme = ""
	for s in [["wss://", "wss://"], ["ws://", "ws://"], ["https://", "wss://"], ["http://", "ws://"]]:
		if t.to_lower().begins_with(s[0]):
			scheme = s[1]
			t = t.substr(s[0].length())
			break
	while t.ends_with("/"): t = t.substr(0, t.length() - 1)
	var host = t.split("/")[0].split(":")[0]
	if host == "" or !(host.is_valid_ip_address() or _host_ok(host)): return ""
	if scheme == "": scheme = "ws://" if host == "localhost" or host.begins_with("127.") else "wss://"
	return scheme + t

static func _host_ok(h:String) -> bool:
	for ch in h:
		if !(ch.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789.-"): return false
	return h.length() <= 253

# "ABCD-EFGH" / "abcdefgh" -> "ABCD-EFGH", "" if not an online room code
static func norm_code(text:String) -> String:
	var c = text.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if c.length() != 8: return ""
	for ch in c:
		if P.CODE_ABC.find(ch) < 0: return ""
	return c.substr(0, 4) + "-" + c.substr(4)

# what a pasted invite / code means: {base, code} (base "" = just a code), {} if neither
static func parse_invite(text:String) -> Dictionary:
	var t = text.strip_edges()
	var c = norm_code(t)
	if c != "": return {base = "", code = c}
	var k = t.find("/j/")
	if k < 0: return {}
	c = norm_code(t.substr(k + 3).split("/")[0].split("?")[0])
	var b = base_url(t.substr(0, k))
	if c == "" or b == "": return {}
	return {base = b, code = c}

# the link a host shares: opens a short page in a browser, pastes straight into JOIN
static func invite(base:String, code:String) -> String:
	return base.replace("wss://", "https://").replace("ws://", "http://") + "/j/" + code

static func describe(code:String, msg:String) -> String:
	var t = TEXTS.get(code, "")
	if code == "game_version": return ("%s: %s." % [t, msg]) if msg != "" else "%s between you and the host - update to the same version." % t
	if t == "": return msg if msg != "" else "relay error (%s)" % code
	return t

static func _setup(ws:WebSocketClient):
	ws.verify_ssl = true # (wss: the relay's certificate must be valid for its name)
	if Engine.has_meta("rr_relay_cert"): # (tests only: trust a local test certificate)
		var x = X509Certificate.new()
		if x.load(str(Engine.get_meta("rr_relay_cert"))) == OK: ws.trusted_ssl_certificate = x
	if ws.has_method("set_buffers"): ws.set_buffers(1024, 4096, 1024, 4096)

static func _sid_bytes(sid:int) -> PoolByteArray:
	return PoolByteArray([(sid >> 24) & 255, (sid >> 16) & 255, (sid >> 8) & 255, sid & 255])

static func _put(ws:WebSocketClient, bytes:PoolByteArray, text:bool) -> int:
	var p = ws.get_peer(1)
	p.set_write_mode(WebSocketPeer.WRITE_MODE_TEXT if text else WebSocketPeer.WRITE_MODE_BINARY)
	return p.put_packet(bytes)

# ---------------------------------------------------------------- guest: one connection to a room
class Guest:
	extends Reference
	var ws:WebSocketClient
	var base:String
	var code:String
	var game:String
	var state:int = StreamPeerTCP.STATUS_CONNECTING
	var error_code:String = ""
	var error_text:String = ""
	var inbuf:PoolByteArray = PoolByteArray()
	var relay_rtt:int = -1
	var sid:int = 0
	var _opened:bool = false
	var _t0:int = 0
	var _ping_t:int = 0
	const relayed = true

	func _init(base_:String, code_:String, game_:String):
		base = base_
		code = code_
		game = game_
		ws = WebSocketClient.new()
		load("res://mods/replay/MPRelay.gd")._setup(ws)
		ws.connect("connection_established", self, "_on_open")
		ws.connect("connection_error", self, "_on_error")
		ws.connect("connection_closed", self, "_on_closed")
		ws.connect("server_close_request", self, "_on_close_request")
		_t0 = OS.get_ticks_msec()
		var err = ws.connect_to_url(base + "/v1/join")
		if err != OK: _fail("bad_url", "Couldn't start a connection to the relay %s (error %d)." % [base, err])

	func _on_open(_proto):
		_opened = true
		load("res://mods/replay/MPRelay.gd")._put(ws, to_json({op = "join", code = code, proto = PROTO, game = game}).to_utf8(), true)

	func _on_error():
		_fail("unreachable", "Couldn't reach the relay %s: offline, wrong address, a firewall, or its certificate isn't trusted." % base)

	# the relay's reason comes as a message right before its close: read it before the close counts
	var _close_reason:String = ""
	func _on_close_request(_code, reason):
		_close_reason = str(reason)
		_drain(OS.get_ticks_msec())

	func _on_closed(_clean):
		_drain(OS.get_ticks_msec()) # (the reason message may still be queued)
		if state == StreamPeerTCP.STATUS_CONNECTED or state == StreamPeerTCP.STATUS_CONNECTING:
			var R = load("res://mods/replay/MPRelay.gd")
			if R.TEXTS.has(_close_reason): _fail(_close_reason, R.describe(_close_reason, ""))
			else: _fail("lost", "The connection to the relay dropped.")

	func _fail(c:String, text:String):
		if state == StreamPeerTCP.STATUS_ERROR: return
		error_code = c
		error_text = text
		state = StreamPeerTCP.STATUS_ERROR
		if ws.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED: ws.disconnect_from_host(1000, "")

	func get_status() -> int:
		if state == StreamPeerTCP.STATUS_CONNECTING or state == StreamPeerTCP.STATUS_CONNECTED: _poll()
		return state

	func _poll():
		ws.poll()
		var now = OS.get_ticks_msec()
		if _opened and ws.get_connection_status() == NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
			_drain(now)
			if state == StreamPeerTCP.STATUS_CONNECTED and now - _ping_t > PING_MS:
				_ping_t = now
				load("res://mods/replay/MPRelay.gd")._put(ws, to_json({op = "ping", t = now}).to_utf8(), true)
		if state == StreamPeerTCP.STATUS_CONNECTING and now - _t0 > OPEN_TIMEOUT:
			_fail("timeout", "Couldn't reach the relay %s: no answer in %d s." % [base, OPEN_TIMEOUT / 1000])

	func _drain(now:int):
		if !_opened or state == StreamPeerTCP.STATUS_ERROR: return
		var p = ws.get_peer(1)
		while p.get_available_packet_count() > 0:
			var pkt = p.get_packet()
			if !p.was_string_packet():
				if state == StreamPeerTCP.STATUS_CONNECTED:
					var b = inbuf
					b.append_array(pkt)
					inbuf = b
				continue
			var m = parse_json(pkt.get_string_from_utf8()) if pkt.size() < 4096 else null
			if typeof(m) != TYPE_DICTIONARY: continue
			match str(m.get("op", "")):
				"joined":
					sid = int(m.get("sid", 0))
					state = StreamPeerTCP.STATUS_CONNECTED
				"pong":
					if typeof(m.get("t")) in [TYPE_INT, TYPE_REAL]: relay_rtt = now - int(m.t)
				"error":
					var c = str(m.get("code", "error"))
					_fail(c, load("res://mods/replay/MPRelay.gd").describe(c, P.clean_text(m.get("msg", ""), 160)))
					return

	func get_available_bytes() -> int:
		return inbuf.size()

	func get_partial_data(n:int) -> Array:
		var k = int(min(n, inbuf.size()))
		var out = inbuf.subarray(0, k - 1) if k > 0 else PoolByteArray()
		inbuf = inbuf.subarray(k, inbuf.size() - 1) if k < inbuf.size() else PoolByteArray()
		return [OK, out]

	func put_partial_data(b:PoolByteArray) -> Array:
		if state != StreamPeerTCP.STATUS_CONNECTED: return [ERR_CONNECTION_ERROR, 0]
		var sent = 0
		var R = load("res://mods/replay/MPRelay.gd")
		while sent < b.size():
			var n = int(min(CHUNK, b.size() - sent))
			if R._put(ws, b.subarray(sent, sent + n - 1), false) != OK: break # (buffer full: the rest goes next frame)
			sent += n
		ws.poll() # (sends now, like a socket write)
		return [OK, sent]

	func put_data(b:PoolByteArray) -> int:
		put_partial_data(b)
		return OK

	func set_no_delay(_on:bool):
		pass

	func disconnect_from_host():
		if state == StreamPeerTCP.STATUS_CONNECTED or state == StreamPeerTCP.STATUS_CONNECTING:
			ws.poll() # (whatever was just written - "bye" - goes out before the close)
			ws.disconnect_from_host(1000, "bye")
			ws.poll()
		state = StreamPeerTCP.STATUS_NONE

# ---------------------------------------------------------------- host: one guest inside the tunnel
class Stream:
	extends Reference
	var sid:int
	var tunnel_ref
	var inbuf:PoolByteArray = PoolByteArray()
	var open:bool = true
	const relayed = true

	func _init(sid_:int, t):
		sid = sid_
		tunnel_ref = weakref(t) # (the tunnel holds its streams; a strong ref back would never be freed)

	func get_status() -> int:
		return StreamPeerTCP.STATUS_CONNECTED if open else StreamPeerTCP.STATUS_NONE

	func get_available_bytes() -> int:
		return inbuf.size()

	func get_partial_data(n:int) -> Array:
		var k = int(min(n, inbuf.size()))
		var out = inbuf.subarray(0, k - 1) if k > 0 else PoolByteArray()
		inbuf = inbuf.subarray(k, inbuf.size() - 1) if k < inbuf.size() else PoolByteArray()
		return [OK, out]

	func put_partial_data(b:PoolByteArray) -> Array:
		var t = tunnel_ref.get_ref()
		if !open or !t: return [ERR_CONNECTION_ERROR, 0]
		return [OK, t.send(sid, b)]

	func put_data(b:PoolByteArray) -> int:
		put_partial_data(b)
		return OK

	func set_no_delay(_on:bool):
		pass

	func disconnect_from_host():
		if !open: return
		open = false
		var t = tunnel_ref.get_ref()
		if t: t.close_stream(sid)

# ---------------------------------------------------------------- host: the tunnel to the relay
class Tunnel:
	extends Reference
	var ws:WebSocketClient = null
	var base:String
	var game:String
	var max_guests:int
	var state:String = "connecting"   # connecting | creating | ready | reconnecting | failed | closed
	var code:String = ""
	var token:String = ""             # host credential from the relay (resume); never shown
	var grace:int = 25
	var error_code:String = ""
	var error_text:String = ""
	var streams:Dictionary = {}       # sid -> Stream
	var pending:Array = []            # new Streams for MPHost to take
	var relay_rtt:int = -1
	var attempts:int = 0
	var changes:int = 0               # bumps on every state / code change (MPHost watches it)
	var _retry_at:int = 0
	var _t0:int = 0
	var _ping_t:int = 0
	var _lost_at:int = 0
	var _opened:bool = false
	var _dead = null                  # the socket that just failed: kept until the next frame (it may still be emitting)

	func _init(base_:String, game_:String, max_:int):
		base = base_
		game = game_
		max_guests = max_
		_connect()

	func _connect():
		ws = WebSocketClient.new()
		load("res://mods/replay/MPRelay.gd")._setup(ws)
		ws.connect("connection_established", self, "_on_open")
		ws.connect("connection_error", self, "_on_lost", ["unreachable"])
		ws.connect("connection_closed", self, "_on_closed")
		ws.connect("server_close_request", self, "_on_close_request")
		_opened = false
		_t0 = OS.get_ticks_msec()
		_state("connecting" if attempts == 0 else "reconnecting")
		if ws.connect_to_url(base + "/v1/host") != OK: _on_lost("bad_url")

	func _state(s:String):
		state = s
		changes += 1

	func _on_open(_proto):
		_opened = true
		_state("creating")
		var hello = {op = "create", proto = PROTO, game = game, max = max_guests}
		if token != "": hello["resume"] = token
		load("res://mods/replay/MPRelay.gd")._put(ws, to_json(hello).to_utf8(), true)

	var _close_reason:String = ""
	func _on_close_request(_code, reason):
		_close_reason = str(reason)

	func _on_closed(_clean):
		if error_code == "" and TEXTS.has(_close_reason):
			error_code = _close_reason
			error_text = load("res://mods/replay/MPRelay.gd").describe(_close_reason, "")
		_on_lost("lost")

	func _on_lost(why:String):
		if state == "closed" or state == "failed" or ws == null: return
		var was_ready = state == "ready"
		_dead = ws
		ws = null
		for s in streams.values(): s.open = false # (MPHost sees them drop; the players reconnect)
		streams = {}
		if error_code in FINAL or why == "bad_url":
			if why == "bad_url": error_text = "Couldn't start a connection to the relay %s." % base
			_state("failed")
			return
		if was_ready: _lost_at = OS.get_ticks_msec()
		if why == "unreachable" and error_text == "": error_text = "Couldn't reach the relay %s." % base
		elif why == "lost" and error_text == "": error_text = "The connection to the relay dropped."
		attempts += 1
		_retry_at = OS.get_ticks_msec() + int(min(BACKOFF_MAX, 1000 * pow(2, attempts - 1)))
		_state("reconnecting")

	func poll(now:int):
		_dead = null
		if state == "reconnecting" and ws == null:
			if now >= _retry_at:
				if token != "" and _lost_at > 0 and now - _lost_at > grace * 1000: token = "" # (the old room is gone: a new code)
				error_code = ""
				_connect()
			return
		if ws == null: return
		ws.poll()
		if ws == null: return
		if (state == "connecting" or state == "reconnecting" or state == "creating") and now - _t0 > OPEN_TIMEOUT:
			error_text = "Couldn't reach the relay %s: no answer." % base
			var w = ws
			_on_lost("timeout")
			w.disconnect_from_host()
			return
		if !_opened or ws.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_CONNECTED: return
		var p = ws.get_peer(1)
		while ws and p.get_available_packet_count() > 0:
			var pkt = p.get_packet()
			if !p.was_string_packet():
				if pkt.size() < 4: continue
				var sid = (pkt[0] << 24) | (pkt[1] << 16) | (pkt[2] << 8) | pkt[3]
				var s = streams.get(sid)
				if s == null: continue
				var b = s.inbuf
				b.append_array(pkt.subarray(4, pkt.size() - 1))
				s.inbuf = b
				if s.inbuf.size() > P.MAX_BUFFER * 2: s.disconnect_from_host() # (MPHost drops it too)
				continue
			var m = parse_json(pkt.get_string_from_utf8()) if pkt.size() < 4096 else null
			if typeof(m) != TYPE_DICTIONARY: continue
			match str(m.get("op", "")):
				"room":
					var c = load("res://mods/replay/MPRelay.gd").norm_code(str(m.get("code", "")))
					if c == "": continue
					code = c
					token = str(m.get("token", ""))
					grace = int(m.get("grace", 25))
					attempts = 0
					_lost_at = 0
					error_text = ""
					_state("ready")
				"open":
					var sid = int(m.get("sid", 0))
					if sid > 0 and !streams.has(sid):
						var s = Stream.new(sid, self)
						streams[sid] = s
						pending.append(s)
				"close":
					var s = streams.get(int(m.get("sid", 0)))
					if s:
						s.open = false
						streams.erase(s.sid)
				"pong":
					if typeof(m.get("t")) in [TYPE_INT, TYPE_REAL]: relay_rtt = now - int(m.t)
				"error":
					error_code = str(m.get("code", "error"))
					error_text = load("res://mods/replay/MPRelay.gd").describe(error_code, P.clean_text(m.get("msg", ""), 160))
		if ws and state == "ready" and now - _ping_t > PING_MS:
			_ping_t = now
			load("res://mods/replay/MPRelay.gd")._put(ws, to_json({op = "ping", t = now}).to_utf8(), true)

	func is_connection_available() -> bool:
		return !pending.empty()

	func take_connection():
		return pending.pop_front()

	func send(sid:int, b:PoolByteArray) -> int:
		if ws == null or state != "ready": return 0
		var R = load("res://mods/replay/MPRelay.gd")
		var head = R._sid_bytes(sid)
		var sent = 0
		while sent < b.size():
			var n = int(min(CHUNK, b.size() - sent))
			var pkt = head + b.subarray(sent, sent + n - 1)
			if R._put(ws, pkt, false) != OK: break
			sent += n
		return sent

	func flush():
		if ws: ws.poll()

	func close_stream(sid:int):
		if streams.has(sid):
			streams[sid].open = false
			streams.erase(sid)
			if ws and state == "ready":
				load("res://mods/replay/MPRelay.gd")._put(ws, to_json({op = "close", sid = sid}).to_utf8(), true)

	# the host ends the room: the relay revokes the code at once
	func end():
		if state == "closed": return
		if ws and state == "ready":
			ws.poll()
			load("res://mods/replay/MPRelay.gd")._put(ws, to_json({op = "end"}).to_utf8(), true)
			ws.poll()
			ws.disconnect_from_host(1000, "end")
			ws.poll()
		ws = null
		for s in streams.values(): s.open = false
		streams = {}
		_state("closed")
