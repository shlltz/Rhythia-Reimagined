extends Reference
# Multiplayer protocol (Rhythia-reimagined): constants, message framing, text sanitising, value
# checks, room codes. No state here - MPLobby (host rules), MPHost (host sockets) and MPClient
# (every player) share these helpers.
#
# Wire format: one JSON object per line (UTF-8, "\n" ends a message), always {"t": type, ...}.
# TCP keeps the order and delivery; lines over MAX_LINE are refused. A relay can later forward
# these same lines unchanged (the protocol never depends on the peer's address).

const VERSION = "rr-mp-1"
const PORT = 47320               # TCP: lobby, chat, match control, scores
const LAN_PORT = 47321           # UDP: LAN lobby announcements (broadcast)
const MAX_LINE = 8192            # bytes in one message
const MAX_BUFFER = 65536         # unread bytes kept per connection before it is dropped
const MAX_PLAYERS = 16
const NAME_MAX = 20
const CHAT_MAX = 200
const LOBBY_NAME_MAX = 32
const PW_MAX = 32
const HEARTBEAT = 2.0            # s between pings (both ways)
const TIMEOUT = 12.0             # s without any data = connection lost
const RECONNECT_KEEP = 45.0      # s a lost player's slot (and score) is kept for a reconnect
const LOAD_TIMEOUT = 30.0        # s the host waits for everyone to load a match
const START_LEAD = 1500          # ms between "everyone loaded" and the shared start
const CHAT_RATE = 5              # messages ...
const CHAT_WINDOW = 5.0          # ... per this many seconds
const CHAT_HISTORY = 60

# the match rules: No Fail is always on (enforced by MPClient); these are the mods the host may add.
# Sudden Death is left out (it fails the run, No Fail does not), Extra Energy does nothing with No Fail.
const HOST_MODS = [["mod_hardrock", "Hard Rock"], ["mod_ghost", "Ghost"], ["mod_flashlight", "Flashlight"],
	["mod_nearsighted", "Nearsighted"], ["mod_mirror_x", "Mirror X"], ["mod_mirror_y", "Mirror Y"],
	["mod_chaos", "Chaos"], ["mod_earthquake", "Earthquake"], ["mod_no_regen", "No Regen"]]
const ALL_MODS = ["mod_nofail", "mod_sudden_death", "mod_extra_energy", "mod_no_regen", "mod_mirror_x",
	"mod_mirror_y", "mod_ghost", "mod_nearsighted", "mod_chaos", "mod_earthquake", "mod_flashlight", "mod_hardrock"]
const SPEED_MIN = 0.5
const SPEED_MAX = 2.0

static func encode(msg:Dictionary) -> PoolByteArray:
	return (to_json(msg) + "\n").to_utf8()

# a message, or null when the line is not a valid message
static func parse_line(line:String):
	if line.length() > MAX_LINE or line.strip_edges() == "": return null
	var r = JSON.parse(line)
	if r.error != OK or typeof(r.result) != TYPE_DICTIONARY: return null
	if typeof(r.result.get("t")) != TYPE_STRING: return null
	return r.result

# printable text: control characters out, runs of white space folded, trimmed, cut to max_len
static func clean_text(v, max_len:int) -> String:
	if typeof(v) != TYPE_STRING: return ""
	var out = ""
	var sp = false
	for ch in v:
		var c = ord(ch)
		if c == 9 or c == 10 or c == 13 or c == 0x2028 or c == 0x2029:
			c = 32 # line breaks / tabs -> a space
			ch = " "
		elif c < 32 or (c >= 127 and c < 160) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF:
			continue # other control characters, and the bidi overrides that can flip how a line reads
		if c == 32:
			if sp: continue
			sp = true
		else: sp = false
		out += ch
		if out.length() > max_len + 1: break
	return out.strip_edges().substr(0, max_len).strip_edges()

static func clean_name(v) -> String:
	var n = clean_text(v, NAME_MAX)
	return n if n != "" else "player"

static func gen_name() -> String:
	randomize()
	return "player%04d" % (randi() % 10000)

# a number in [lo, hi] from a message field, else null
static func num(d:Dictionary, k:String, lo:float, hi:float):
	var v = d.get(k)
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_REAL: return null
	if is_nan(float(v)) or is_inf(float(v)): return null
	if float(v) < lo or float(v) > hi: return null
	return v

static func boolean(d:Dictionary, k:String):
	var v = d.get(k)
	return v if typeof(v) == TYPE_BOOL else null

static func now_ms() -> int:
	return OS.get_ticks_msec()

# ---------------------------------------------------------------- addresses and room codes
# A room code is the host's IPv4 address + port written in 10 letters/digits (no I, O, 0, 1).
# It is a short way to type an address, not a lookup: it works where that address is reachable.
const CODE_ABC = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

static func room_code(ip:String, port:int) -> String:
	var parts = ip.split(".")
	if parts.size() != 4: return ""
	var v = 0
	for p in parts: v = v * 256 + (int(p) & 255)
	v = v * 65536 + (port & 65535)
	var s = ""
	for i in 10:
		s = CODE_ABC[v & 31] + s
		v = v >> 5
	return s.substr(0, 5) + "-" + s.substr(5)

# [ip, port] from "1.2.3.4", "1.2.3.4:5000", "hostname:5000" or a room code; [] if unusable
static func parse_address(text:String) -> Array:
	var t = text.strip_edges()
	if t == "": return []
	var code = t.to_upper().replace("-", "").replace(" ", "")
	if code.length() == 10 and !(":" in t) and !("." in t):
		var v = 0
		for ch in code:
			var k = CODE_ABC.find(ch)
			if k < 0: return []
			v = v * 32 + k
		var port = v & 65535
		v = v >> 16
		var ip = "%d.%d.%d.%d" % [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]
		return [ip, port] if port > 0 else []
	var host = t
	var port = PORT
	var i = t.find_last(":")
	if i > 0 and t.count(":") == 1:
		host = t.substr(0, i)
		var ps = t.substr(i + 1)
		if !ps.is_valid_integer(): return []
		port = int(ps)
	if port <= 0 or port > 65535 or host == "": return []
	for ch in host:
		if !(ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"): return []
	return [host, port]

static func is_private_ipv4(ip:String) -> bool:
	var p = ip.split(".")
	if p.size() != 4: return false
	var a = int(p[0]); var b = int(p[1])
	return a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31)

# this machine's LAN addresses (private IPv4 first)
static func lan_ips() -> Array:
	var pri = []
	var other = []
	for ip in IP.get_local_addresses():
		if ip.count(".") != 3 or ip.begins_with("127.") or ip.begins_with("169.254."): continue
		if is_private_ipv4(ip): pri.append(ip)
		else: other.append(ip)
	return pri + other

# ---------------------------------------------------------------- maps
# what identifies a map across players: its id plus a hash of the note data and the audio size.
# Both sides compute it the same way from their own copy.
static func map_info(song) -> Dictionary:
	var notes = song.read_notes()
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var chunk = ""
	for n in notes:
		chunk += "%.3f,%.3f,%d;" % [float(n[0]), float(n[1]), int(n[2])]
		if chunk.length() > 16384:
			ctx.update(chunk.to_utf8())
			chunk = ""
	ctx.update((chunk + "|%d" % notes.size()).to_utf8())
	var audio = 0
	var buf = song.get_music_buffer() if song.has_method("get_music_buffer") else null
	if buf is PoolByteArray: audio = buf.size()
	ctx.update(("|a%d" % audio).to_utf8())
	var h = ctx.finish().hex_encode()
	return {id = str(song.id), name = str(song.name), creator = str(song.creator), diff = int(song.difficulty),
		notes = notes.size(), len = float(song.last_ms), hash = h, audio = audio}

# a map entry from the host, checked and cut to size; null if it is not usable
static func clean_map(d) -> Dictionary:
	if typeof(d) != TYPE_DICTIONARY: return {}
	var id = d.get("id")
	var h = d.get("hash")
	if typeof(id) != TYPE_STRING or id == "" or id.length() > 200: return {}
	if typeof(h) != TYPE_STRING or h.length() != 32 or !h.is_valid_hex_number(): return {}
	var notes = num(d, "notes", 0, 1e7)
	var ln = num(d, "len", 0, 3.6e7)
	if notes == null or ln == null: return {}
	var diff = num(d, "diff", -10, 100)
	var audio = num(d, "audio", 0, 2e9)
	return {id = id, hash = h.to_lower(), name = clean_text(d.get("name", ""), 120), creator = clean_text(d.get("creator", ""), 60),
		diff = int(diff) if diff != null else -1, notes = int(notes), len = float(ln), audio = int(audio) if audio != null else 0}

static func map_key(m:Dictionary) -> String:
	return "" if m.empty() else str(m.id) + ":" + str(m.hash)

# rules from the host, checked (unknown mods dropped, numbers clamped to sane ranges)
static func clean_rules(d) -> Dictionary:
	var r = {speed = 1.0, mods = [], hw = 55.0, hb = 1.14, shw = false}
	if typeof(d) != TYPE_DICTIONARY: return r
	var shw = boolean(d, "shw")
	if shw != null: r.shw = shw
	var sp = num(d, "speed", SPEED_MIN, SPEED_MAX)
	if sp != null: r.speed = stepify(float(sp), 0.01)
	var hw = num(d, "hw", 10, 500)
	if hw != null: r.hw = float(hw)
	var hb = num(d, "hb", 0.2, 5.0)
	if hb != null: r.hb = float(hb)
	var allowed = []
	for m in HOST_MODS: allowed.append(m[0])
	if typeof(d.get("mods")) == TYPE_ARRAY:
		for m in d.mods:
			if typeof(m) == TYPE_STRING and m in allowed and !(m in r.mods): r.mods.append(m)
	return r

static func rules_text(r:Dictionary) -> String:
	var t = ["No Fail (always on)"]
	if abs(float(r.get("speed", 1.0)) - 1.0) > 0.001: t.append("%.2fx" % float(r.speed))
	for m in HOST_MODS:
		if m[0] in r.get("mods", []): t.append(m[1])
	t.append("hit window %d ms%s" % [int(r.get("hw", 55)), " (scales with speed)" if r.get("shw", false) else ""])
	t.append("hitbox %.2f" % float(r.get("hb", 1.14)))
	return PoolStringArray(t).join("  /  ")

static func fmt_len(ms:float) -> String:
	var s = int(ms / 1000.0)
	return "%d:%02d" % [s / 60, s % 60]
