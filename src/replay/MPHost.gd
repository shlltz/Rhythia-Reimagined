extends Node
# Multiplayer host transport: a TCP server inside the hosting player's game (no separate program).
# Accepts connections, splits the byte stream into lines, rate-limits and size-limits them, maps
# connections to player ids for MPLobby (which holds all the rules), writes MPLobby's replies
# without ever blocking the frame, and announces the lobby on the LAN (UDP broadcast).
# Lives under the hosting player's MPClient (root, survives scene changes, runs while paused).

signal stopped(reason)

const P = preload("res://mods/replay/MPProto.gd")
const Lobby = preload("res://mods/replay/MPLobby.gd")
const MSG_RATE = 40.0           # messages per second a connection may send (burst BURST)
const BURST = 80.0
const MAX_OUT = 1048576         # unsent bytes before a connection counts as stuck

var lobby
var server:TCP_Server
var port:int = P.PORT
var conns:Array = []
var beacon:PacketPeerUDP
var running:bool = false
var _beacon_t:int = -100000

func _ready():
	name = "MPHost"
	pause_mode = PAUSE_MODE_PROCESS

# -> "" when listening, else what went wrong
func start(cfg:Dictionary) -> String:
	port = int(cfg.get("port", P.PORT))
	lobby = Lobby.new(cfg)
	server = TCP_Server.new()
	var err = server.listen(port, "*")
	if err != OK:
		return "Couldn't open port %d (error %d): another program (or another lobby) may be using it." % [port, err]
	var ips = P.lan_ips()
	for ip in ips: lobby.addresses.append("%s:%d" % [ip, port])
	lobby.code = P.room_code(ips[0], port) if ips.size() > 0 else ""
	beacon = PacketPeerUDP.new()
	beacon.set_broadcast_enabled(true)
	beacon.set_dest_address("255.255.255.255", P.LAN_PORT)
	running = true
	print("[mp] hosting on port %d: %s" % [port, str(lobby.addresses)])
	return ""

func stop(reason:String = "the host closed the lobby"):
	if !running: return
	running = false
	for c in conns:
		var n = c.peer.get_available_bytes()
		if n > 0: c.peer.get_partial_data(min(n, 65536)) # (unread data would reset the connection and drop the message)
		if c.pid > 0: c.peer.put_data(P.encode({t = "closing", reason = reason}))
		c.peer.disconnect_from_host()
	conns = []
	if server: server.stop()
	if beacon: beacon.close()
	print("[mp] lobby closed: " + reason)
	emit_signal("stopped", reason)

func _exit_tree():
	stop("the host left")

func _process(_d):
	if !running: return
	var now = P.now_ms()
	while server.is_connection_available():
		var peer = server.take_connection()
		if conns.size() >= P.MAX_PLAYERS * 3:
			peer.disconnect_from_host()
			continue
		peer.set_no_delay(true)
		conns.append({peer = peer, inbuf = PoolByteArray(), out = PoolByteArray(), pid = 0, opened = now,
			last_rx = now, tokens = BURST, tok_t = now, bad = 0, closing = 0})
	for c in conns.duplicate(): _read(c, now)
	lobby.tick(now)
	_dispatch(now)
	for c in conns.duplicate(): _write(c, now)
	if lobby.closed:
		stop("the host left")
		return
	if now - _beacon_t > 1500:
		_beacon_t = now
		var b = {rr_mp = P.VERSION, name = lobby.lobby_name, port = port, n = lobby.active_count(), max = lobby.max_players,
			state = lobby.state, map = lobby.map.get("name", ""), pw = lobby.password != "", code = lobby.code}
		beacon.put_packet(to_json(b).to_utf8()) # (errors ignored: some networks drop broadcasts)

func _read(c:Dictionary, now:int):
	if c.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_lost(c)
		return
	var n = c.peer.get_available_bytes()
	if c.closing > 0: # closing: drain and drop what still comes in (closing with unread data resets the
		if n > 0: c.peer.get_partial_data(min(n, 65536)) # connection and the peer could lose our last message)
		return
	if n > 0:
		var r = c.peer.get_partial_data(min(n, 65536))
		if r[0] != OK:
			_lost(c)
			return
		var b = c.inbuf
		b.append_array(r[1])
		c.inbuf = b
		c.last_rx = now
	var buf:PoolByteArray = c.inbuf
	var start = 0
	var size = buf.size()
	for i in size:
		if buf[i] != 10: continue
		if i - start > P.MAX_LINE:
			_close(c, "message too long")
			return
		if i > start: _line(c, buf.subarray(start, i - 1).get_string_from_utf8(), now)
		start = i + 1
		if !conns.has(c) or c.closing > 0: return
	if start > 0: c.inbuf = buf.subarray(start, size - 1) if start < size else PoolByteArray()
	if c.inbuf.size() > P.MAX_BUFFER:
		_close(c, "too much data")
		return
	if c.pid == 0 and now - c.opened > 10000:
		_close(c, "no hello")
	elif now - c.last_rx > P.TIMEOUT * 1000:
		_lost(c)

func _line(c:Dictionary, line:String, now:int):
	c.tokens = min(BURST, c.tokens + (now - c.tok_t) / 1000.0 * MSG_RATE)
	c.tok_t = now
	if c.tokens < 1.0:
		c.bad += 1 # over the rate limit: dropped
		if c.bad > 200: _close(c, "too many messages")
		return
	c.tokens -= 1.0
	var msg = P.parse_line(line)
	if msg == null:
		c.bad += 1
		_queue(c, {t = "error", what = "protocol", msg = "unreadable message"})
		if c.bad > 30: _close(c, "unreadable messages")
		return
	if c.pid == 0:
		_dispatch(now) # (anything queued for the others goes out before this player counts as online)
		var r = lobby.hello(msg)
		_dispatch_except(now, c)
		if !r.ok:
			_queue(c, {t = "reject", reason = r.reason})
			c.closing = now + 500
			return
		for o in conns: # the same player on a new connection (reconnect): the old one goes
			if o != c and o.pid == r.pid:
				o.pid = 0
				o.closing = now
		c.pid = r.pid
		print("[mp] host: player %d joined (%s)" % [r.pid, "reconnect" if r.get("replaced") or lobby.players[r.pid].get("lost_at", 0) > 0 else "new"])
		_queue(c, lobby.welcome(r.pid))
		return
	lobby.handle(c.pid, msg)

func _dispatch(now:int):
	for item in lobby.out:
		var bytes = P.encode(item[1])
		if item[0] == -1:
			for c in conns:
				if c.pid > 0 and c.closing == 0: _append(c, bytes)
		else:
			var c = _conn_of(item[0])
			if c: _append(c, bytes)
	lobby.out = []
	for pid in lobby.drop:
		var c = _conn_of(pid)
		if c:
			c.pid = 0
			c.closing = now + 400
	lobby.drop = []

# the "joined" notice etc. that hello() just queued: to everyone but the new player (it gets the
# same in its welcome's chat history)
func _dispatch_except(now:int, skip:Dictionary):
	var keep = skip.pid
	skip.pid = -1
	_dispatch(now)
	skip.pid = keep

func _append(c:Dictionary, bytes:PoolByteArray):
	var o = c.out
	o.append_array(bytes)
	c.out = o

func _queue(c:Dictionary, msg:Dictionary):
	_append(c, P.encode(msg))

func _write(c:Dictionary, now:int):
	if !conns.has(c): return
	if c.out.size() > 0:
		var r = c.peer.put_partial_data(c.out)
		if r[0] != OK:
			_lost(c)
			return
		var sent = int(r[1])
		var o:PoolByteArray = c.out
		c.out = o.subarray(sent, o.size() - 1) if sent < o.size() else PoolByteArray()
		if c.out.size() > MAX_OUT:
			_lost(c)
			return
	if c.closing > 0 and ((c.out.size() == 0 and now >= c.closing) or now > c.closing + 3000): # (a short grace so the last message lands)
		c.peer.disconnect_from_host()
		conns.erase(c)

func _conn_of(pid:int):
	for c in conns:
		if c.pid == pid: return c
	return null

func _close(c:Dictionary, why:String):
	print("[mp] host: closing connection of player %d: %s" % [c.pid, why])
	_queue(c, {t = "reject", reason = why})
	_write(c, P.now_ms())
	var pid = c.pid
	c.peer.disconnect_from_host()
	conns.erase(c)
	if pid > 0: lobby.disconnected(pid)

func _lost(c:Dictionary):
	if c.pid > 0: print("[mp] host: lost player %d (status %d, %d ms since data)" % [c.pid, c.peer.get_status(), P.now_ms() - c.last_rx])
	c.peer.disconnect_from_host()
	conns.erase(c)
	if c.pid > 0 and _conn_of(c.pid) == null: lobby.disconnected(c.pid)
