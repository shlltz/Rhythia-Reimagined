extends SceneTree
# Pure unit tests (no game files, no game autoloads; run.py copies the scripts in under
# res://mods/replay/ with the build stamps): editor timing sections + undo selection, pattern tools,
# audio tempo / offset from synthetic envelopes, the GIF writer (decoded back by a decoder in this
# file), the updater's version rules and manifest signature checks, online lobby addresses / codes /
# invite links (MPRelay). Exit code 1 on any failure.

var passed = 0
var failed = 0

func ok(n:String, c:bool, d = ""):
	if c: passed += 1
	else: failed += 1
	print(("PASS  " if c else "FAIL  ") + n + ("  " + str(d) if str(d) != "" else ""))

func _init():
	_model()
	_patterns()
	_auto()
	_gif()
	_updater()
	_relay()
	print("== totals: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

# ------------------------------------------------------------------ editor model
func _model():
	var M = load("res://mods/replay/EditorModel.gd")
	var m = M.new()
	m.bpm = 120.0
	m.offset = 100
	m.div = 4
	ok("model: single-BPM snap", m.snap_t(1234) == M.snap(1234, 120.0, 100, 4))
	ok("model: timing point before the offset refused", !m.add_point(50, 180.0))
	m.add_point(10100, 180.0)
	m.add_point(20100, 90.0)
	ok("model: snap on each section's grid", m.snap_t(1180) == 1225 and m.snap_t(10300) == 10267 and m.snap_t(10080) == 10100)
	ok("model: grid steps across a change", abs(m.grid_next(10050, 1) - 10100) < 0.01 and abs(m.grid_next(10100, -1) - 9975) < 0.01)
	ok("model: beats add up", abs(m.beat_at(11100) - 23.0) < 0.001)
	ok("model: points in the session file", to_json(M.from_dict(m.to_dict()).points) == to_json(m.points))
	m.begin("add")
	m.run(["add", [[0.0, 0.0, 500], [1.0, 1.0, 600]]])
	m.end()
	m.undo()
	m.redo()
	ok("model: redo reports what it put back", m.touched.size() == 2)
	m.begin("move")
	m.run(["mov", [[[0.0, 0.0, 500], [2.0, 2.0, 500]]]])
	m.end()
	m.undo()
	ok("model: undoing a move gives the old position", m.touched.size() == 1 and m.touched[0][0] == 0.0)

# ------------------------------------------------------------------ patterns
func _patterns():
	var P = load("res://mods/replay/EditorPatterns.gd")
	var st = P.stream(1000, 100, 9, "snake")
	ok("patterns: snake stream", st.size() == 9 and st[1][2] == 1100 and st[3][0] == 2.0 and st[3][1] == 1.0)
	ok("patterns: jumps deterministic", to_json(P.jumps(0, 100, 32, 1.5, 3)) == to_json(P.jumps(0, 100, 32, 1.5, 3)))
	ok("patterns: rotate 90", to_json(P.transform([[0.0, 0.0, 5], [2.0, 1.0, 9]], "rotate", 90)) == to_json([[2.0, 0.0, 5], [1.0, 2.0, 9]]))
	ok("patterns: mirror section", to_json(P.mirror_section([[0.0, 0.0, 100], [1.0, 0.0, 200]], "x", 50)) == to_json([[2.0, 0.0, 250], [1.0, 0.0, 350]]))
	ok("patterns: slots", to_json(P.from_slot(P.to_slot([[1.0, 1.0, 500], [0.0, 2.0, 600]]), 2000)) == to_json([[1.0, 1.0, 2000], [0.0, 2.0, 2100]]))
	var bz = P.bezier([[0.0, 0.0, 0], [2.0, 0.0, 300], [2.0, 2.0, 600]], [0, 300, 600])
	ok("patterns: bezier through 3 control notes", to_json(bz) == to_json([[0.0, 0.0, 0], [1.5, 0.5, 300], [2.0, 2.0, 600]]), bz)

# ------------------------------------------------------------------ audio analysis
func _synth(bpm:float, off:float, secs:float, noise:float = 0.05) -> Array:
	var n = int(secs * 100)
	var lo = PoolRealArray(); lo.resize(n)
	var hi = PoolRealArray(); hi.resize(n)
	var pk = PoolRealArray(); pk.resize(n)
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var per = 60000.0 / bpm
	for i in n:
		var t = i * 10.0
		lo[i] = clamp(_win(t, off, per, 60.0) * 0.9 + rng.randf() * noise, 0, 1)
		hi[i] = clamp(_win(t, off + per / 2.0, per, 40.0) * 0.5 + rng.randf() * noise, 0, 1)
		pk[i] = clamp(max(lo[i], hi[i]) * 0.8 + 0.1, 0, 1)
	return [lo, hi, pk]

func _win(t:float, off:float, per:float, tau:float) -> float:
	var ph = fposmod(t - off, per)
	return 1.0 if ph == 0.0 or per - ph < 10.0 else exp(-ph / tau)

func _auto():
	var A = load("res://mods/replay/EditorAuto.gd")
	for case in [[150.0, 200.0], [174.0, 90.0], [128.5, 333.0]]:
		var e = _synth(case[0], case[1], 40.0)
		var r = A.analyse(e[0], e[1], e[2], 10.0)
		var per = 60000.0 / r.bpm if r.bpm > 0 else 1.0
		var err = abs(fposmod(r.offset - case[1] + per / 2.0, per) - per / 2.0)
		var octave = false
		for k in [0.5, 1.0, 2.0]:
			if abs(r.bpm - case[0] * k) <= 0.6 * k: octave = true
		ok("auto: %.1f BPM tempo (or octave)" % case[0], octave, r.bpm)
		ok("auto: %.1f BPM offset within 8 ms" % case[0], r.bpm > 0 and (err <= 8.0 or (abs(r.bpm - case[0]) > 1 and err <= per / 2.0)), "%d vs %d" % [r.offset, case[1]])
	var rnd = _synth(120.0, 0.0, 30.0, 0.0)
	var rr = RandomNumberGenerator.new()
	rr.seed = 5
	for i in rnd[0].size():
		rnd[0][i] = rr.randf() * 0.6
		rnd[1][i] = rr.randf() * 0.6
		rnd[2][i] = max(rnd[0][i], rnd[1][i])
	ok("auto: noise claims no tempo", A.analyse(rnd[0], rnd[1], rnd[2], 10.0).bpm == 0.0)

# ------------------------------------------------------------------ GIF writer (+ a decoder here)
func _gif():
	var G = load("res://mods/replay/GifWriter.gd")
	var w = 96
	var h = 54
	var g = G.new()
	g.begin(w, h, 5)
	var frames = []
	var rng = RandomNumberGenerator.new()
	rng.seed = 3
	for k in 3:
		var b = PoolByteArray()
		b.resize(w * h * 3)
		for i in w * h:
			var noisy = (i % w) >= w / 2
			b[i * 3] = rng.randi() % 256 if noisy else (i % w) * 5 % 256
			b[i * 3 + 1] = rng.randi() % 256 if noisy else (i / w) * 4 % 256
			b[i * 3 + 2] = rng.randi() % 256 if noisy else (k * 80) % 256
		frames.append(b)
		g.add_frame(b)
	var dec = _gif_indices(g.finish())
	ok("gif: 3 frames decode", dec.size() == 3, dec.size())
	var bad = 0
	for k in min(3, dec.size()):
		for i in w * h:
			if dec[k].size() <= i or dec[k][i] != g.index_of(frames[k][i * 3], frames[k][i * 3 + 1], frames[k][i * 3 + 2]): bad += 1
	ok("gif: every pixel decodes to its palette index (LZW table cleared on the way)", bad == 0, "%d wrong" % bad)

# palette indices of each frame of a GIF from GifWriter (global palette, full frames)
func _gif_indices(d:PoolByteArray) -> Array:
	var out = []
	if d.subarray(0, 5).get_string_from_ascii() != "GIF89a": return out
	var p = 13 + 768
	while p < d.size():
		var b = d[p]
		if b == 0x3B: break
		if b == 0x21:
			p += 2
			while d[p] != 0: p += d[p] + 1
			p += 1
		elif b == 0x2C:
			var fw = d[p + 5] | (d[p + 6] << 8)
			var fh = d[p + 7] | (d[p + 8] << 8)
			p += 10
			var mcs = d[p]
			p += 1
			var data = PoolByteArray()
			while d[p] != 0:
				data.append_array(d.subarray(p + 1, p + d[p]))
				p += d[p] + 1
			p += 1
			out.append(_lzw_decode(data, mcs, fw * fh))
		else:
			break
	return out

func _lzw_decode(data:PoolByteArray, mcs:int, n:int) -> PoolByteArray:
	var clear = 1 << mcs
	var eoi = clear + 1
	var size = mcs + 1
	var table = []
	for i in clear: table.append(PoolByteArray([i]))
	table.append(PoolByteArray())
	table.append(PoolByteArray())
	var res = PoolByteArray()
	var prev = null
	var bit = 0
	var total = data.size() * 8
	while bit + size <= total and res.size() < n:
		var code = 0
		for k in size:
			if data[(bit + k) >> 3] & (1 << ((bit + k) & 7)): code |= 1 << k
		bit += size
		if code == clear:
			table.resize(clear + 2)
			size = mcs + 1
			prev = null
			continue
		if code == eoi: break
		var entry
		if code < table.size(): entry = table[code]
		elif prev != null: entry = prev + PoolByteArray([prev[0]])
		else: break
		res.append_array(entry)
		if prev != null and table.size() < 4096:
			table.append(prev + PoolByteArray([entry[0]]))
			if table.size() == (1 << size) and size < 12: size += 1
		prev = entry
	return res

# ------------------------------------------------------------------ updater
func _updater():
	var U = load("res://mods/replay/Updater.gd")
	ok("updater: version order", U.newer("0.13.0", "0.12.2") and U.newer("1.0.0", "0.99.9") and !U.newer("0.12.2", "0.12.2"))
	ok("updater: version format", U.valid_version("0.13.0") and !U.valid_version("0.13") and !U.valid_version("v0.13.0"))
	var pub = CryptoKey.new()
	var f = File.new()
	f.open("res://mods/replay/update_key.pub", File.READ)
	ok("updater: the committed public key loads", pub.load_from_string(f.get_as_text(), true) == OK)
	f.close()
	var key = Crypto.new().generate_rsa(2048)
	Engine.set_meta("rr_update_test", {"pubkey": key.save_to_string(true), "base": "http://127.0.0.1:1"})
	var m = to_json({"format": 1, "version": "9.9.9", "notes": "", "pck": {"name": "x.pck", "url": "http://127.0.0.1:1/x.pck", "size": 10, "sha256": "0000000000000000000000000000000000000000000000000000000000000000"}}).to_utf8()
	var sig = Crypto.new().sign(HashingContext.HASH_SHA256, _sha(m), key)
	ok("updater: a signed manifest passes", U.verify_manifest(m, sig).has("manifest"), U.verify_manifest(m, sig))
	var m2 = m.get_string_from_utf8().replace("9.9.9", "9.9.8").to_utf8()
	ok("updater: a changed manifest fails", U.verify_manifest(m2, sig).has("error"))
	var other = Crypto.new().generate_rsa(2048)
	ok("updater: another key fails", U.verify_manifest(m, Crypto.new().sign(HashingContext.HASH_SHA256, _sha(m), other)).has("error"))
	var m3 = m.get_string_from_utf8().replace("http://127.0.0.1:1/x.pck", "https://example.com/x.pck").to_utf8()
	ok("updater: a foreign URL fails even when signed", U.verify_manifest(m3, Crypto.new().sign(HashingContext.HASH_SHA256, _sha(m3), key)).has("error"))
	Engine.remove_meta("rr_update_test")

func _sha(b:PoolByteArray) -> PoolByteArray:
	var h = HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish()

# ------------------------------------------------------------------ online lobbies (relay addresses, codes, invites)
func _relay():
	var R = load("res://mods/replay/MPRelay.gd")
	ok("relay: bare domain -> wss", R.base_url("relay.example.org") == "wss://relay.example.org")
	ok("relay: https + path -> wss, trailing slash gone", R.base_url("https://r.example.org/rr/") == "wss://r.example.org/rr")
	ok("relay: localhost / 127.x stay plain ws (testing)", R.base_url("127.0.0.1:8080") == "ws://127.0.0.1:8080" and R.base_url("localhost:9") == "ws://localhost:9")
	ok("relay: junk refused", R.base_url("") == "" and R.base_url("a b") == "" and R.base_url("<script>") == "" and R.base_url("ftp:x y") == "")
	ok("relay: codes normalised", R.norm_code("abcd efgh") == "ABCD-EFGH" and R.norm_code("ABCD-EFGH") == "ABCD-EFGH")
	ok("relay: not codes", R.norm_code("ABCD-EFG") == "" and R.norm_code("ABCD-EFG0") == "" and R.norm_code("ABCDE-FGHJK") == "")
	var inv = R.invite("wss://r.example.org/rr", "ABCD-EFGH")
	ok("relay: invite link", inv == "https://r.example.org/rr/j/ABCD-EFGH", inv)
	var back = R.parse_invite(inv)
	ok("relay: invite round trip", back.get("base") == "wss://r.example.org/rr" and back.get("code") == "ABCD-EFGH", back)
	ok("relay: local invite stays ws", R.parse_invite("http://127.0.0.1:47390/j/abcd-efgh").get("base") == "ws://127.0.0.1:47390")
	ok("relay: bare code has no relay", R.parse_invite(" abcdefgh ").get("base") == "" and R.parse_invite("hello").empty())
	ok("relay: a LAN address is not an invite", R.parse_invite("192.168.1.20:47320").empty())
	ok("relay: refusals that can't be retried", "full" in R.FINAL and "expired" in R.FINAL and !("host_away" in R.FINAL))
	ok("relay: messages explain", "full" in R.describe("full", "").to_lower() and "rr-mp-0" in R.describe("game_version", "the host plays rr-mp-1, you have rr-mp-0"))
