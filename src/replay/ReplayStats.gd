extends Reference
# Replay Studio analysis (Rhythia-reimagined). parse() reads a .sspre without touching the game
# (Replay.gd's reader applies the replay's mods and changes scenes on errors); analyse() rebuilds
# from what the replay recorded - the cursor path and pause / skip signals on the replay's clock
# (real ms from the start, "rms") and a hit / miss result per note:
#   - song time at every 5 ms of replay time, stepped exactly like NoteManager.replay_seek (3 s
#     lead-in, speed, pauses with the 750 ms rewind on unpause, skips),
#   - the judgement order and from it combo, score (Game.gd's points: 50 x speed factor x combo
#     level, the level dropping on a miss and resetting on a pause) and accuracy,
#   - per hit note, reconstructed from the cursor path: where the cursor was against the note centre
#     at the note's time ("aim", interpolated between samples like the replay viewer does) and how
#     long after the note's time a sample first sits inside the hitbox ("delay"; unknown when none
#     does). The game records the cursor every 1 / rec_interval s (not every frame), so both are
#     only as fine as that: "sample_ms" says how fine,
#   - cursor speed over song time and a cursor heatmap (time-weighted, pauses left out).
# Nothing here is invented: values the replay can't give are left out, not estimated.
# Pure: no nodes, safe on a worker thread (the Array-of-Arrays sort_custom matches the game's own).

const SIG = PoolByteArray([0x53, 0x73, 0x2A, 0x52])
const DT = 5.0
const HEAT = 48                 # heatmap cells per side over the cursor area -0.5 .. 2.5
const SPEED_BIN = 250.0         # ms of song time per cursor speed value
const LOCAL = 25                # judgements in the local accuracy window

# {ok, error, sv, id, song_id, state_str, settings, end_ms, cur_t / cur_x / cur_y (PoolRealArray,
# cursor in grid units, y down), trig [[rms, kind]], results {note id: hit}}
static func parse(path:String) -> Dictionary:
	var out = {"ok": false, "error": "", "path": path}
	var f = File.new()
	if f.open(path, File.READ) != OK:
		out.error = "can't open the file"
		return out
	if f.get_len() < 16 or f.get_buffer(4) != SIG:
		f.close()
		out.error = "not a replay file"
		return out
	out.sv = f.get_16()
	if out.sv < 2 or out.sv > 4:
		f.close()
		out.error = "replay version %d is not supported (2 .. 4)" % out.sv
		return out
	f.get_64()
	if out.sv >= 4: f.get_line() # (device id: not kept)
	out.id = f.get_line()
	out.song_id = out.id.substr(0, out.id.find_last("."))
	out.state_str = f.get_line()
	out.settings = {}
	if out.sv >= 3:
		for k in ["approach_rate", "spawn_distance", "fade_length", "parallax", "ui_parallax", "grid_parallax", "fov"]: out.settings[k] = f.get_float()
		out.settings.cam_unlock = f.get_8() == 1
		out.settings.edge_drift = f.get_float()
	f.get_8()
	out.end_ms = float(f.get_32())
	f.get_32()
	var ct = PoolRealArray()
	var cx = PoolRealArray()
	var cy = PoolRealArray()
	var trig = []
	var res = {}
	var timed = [Globals.RS_PAUSE, Globals.RS_START_UNPAUSE, Globals.RS_CANCEL_UNPAUSE, Globals.RS_SKIP, Globals.RS_FINISH_UNPAUSE, Globals.RS_GIVEUP]
	while true:
		if f.eof_reached() or f.get_position() >= f.get_len():
			f.close()
			out.error = "the file ends early (no end marker)"
			return out
		var kind = f.get_8()
		if kind == Globals.RS_END: break
		if kind == Globals.RS_CURSOR:
			ct.append(float(f.get_32()))
			cx.append(f.get_float())
			cy.append(f.get_float())
		elif kind in timed:
			trig.append([float(f.get_32()), kind])
		elif kind == Globals.RS_HIT:
			res[f.get_32()] = true
		elif kind == Globals.RS_MISS:
			res[f.get_32()] = false
		else:
			f.close()
			out.error = "unknown record type %d" % kind
			return out
	f.close()
	out.cur_t = ct
	out.cur_x = cx
	out.cur_y = cy
	out.trig = trig
	out.results = res
	out.ok = true
	return out

# opts: {speed, hitbox, hit_window, start_offset, mirror_x, mirror_y, hardrock}; notes = the map's
# [x, y, ms] (Song.read_notes)
static func analyse(rp:Dictionary, song_notes:Array, opts:Dictionary) -> Dictionary:
	var speed = float(opts.get("speed", 1.0))
	var hbox = float(opts.get("hitbox", 1.14))
	var hitw = float(opts.get("hit_window", 55.0))
	var so = float(opts.get("start_offset", 0.0))
	# the notes as NoteManager.spawn_notes numbers them (same sort, same filter, same mods)
	var arr = song_notes.duplicate(true)
	arr.sort_custom(load("res://mods/replay/ReplayStats.gd"), "_by_time")
	var ns = []
	for d in arr:
		if d[2] < so: continue
		var p = Vector2(d[0], d[1])
		if opts.get("hardrock", false): p = (p - Vector2(1, 1)) * 1.35 + Vector2(1, 1)
		if opts.get("mirror_x", false): p.x = 2.0 - p.x
		if opts.get("mirror_y", false): p.y = 2.0 - p.y
		ns.append([p, float(d[2])])
	var res = rp.results
	var trig = rp.trig
	var length = rp.end_ms
	if rp.cur_t.size() > 0: length = max(length, rp.cur_t[rp.cur_t.size() - 1])
	if trig.size() > 0: length = max(length, trig[trig.size() - 1][0])
	# ---- replay clock -> song time + judgements (NoteManager.replay_seek, without the drawing)
	var sms_at = PoolRealArray()
	var sms = so - 3000.0 * speed
	var srms = 0.0
	var ps = 0.0
	var pms = 0.0
	var unp = false
	var cur = 0
	var pending = []
	var ti = 0
	var judged = []     # [note id, rms, song ms, hit]
	var pauses = []     # song ms of each pause
	var level_resets = [] # judgement count at each pause (the combo level restarts there)
	var gave_up = false
	sms_at.append(sms)
	while srms < length:
		var sp = false
		var sk = false
		var su = false
		var sc = false
		var se = false
		for s in pending:
			match s[1]:
				Globals.RS_PAUSE: sp = true
				Globals.RS_GIVEUP: gave_up = true
				Globals.RS_SKIP: sk = true
				Globals.RS_START_UNPAUSE:
					su = true
					unp = true
				Globals.RS_CANCEL_UNPAUSE:
					sc = true
					unp = false
				Globals.RS_FINISH_UNPAUSE: se = true
		if gave_up: break
		if sk:
			var nx = sms
			for k in range(cur, ns.size()):
				if ns[k][1] > sms:
					nx = ns[k][1]
					break
			sms = nx - 1000.0 - 1000.0 * speed
		if sc:
			ps = -1.0
			sms = pms
		elif sp:
			ps = -1.0
			pms = sms
			pauses.append(sms)
			level_resets.append(judged.size())
		elif su:
			ps = 1.0
			sms = pms - 750.0 * speed
		if unp and ps >= 0:
			ps = max(ps - DT / 750.0, 0.0)
			if se: ps = 0.0
		var step = min(DT, length - srms)
		srms += step
		if ps == 0 or (ps > 0 and unp): sms += step * speed
		sms_at.append(sms)
		pending = []
		while ti < trig.size() and trig[ti][0] <= srms:
			pending.append(trig[ti])
			ti += 1
		var i = cur
		while i < ns.size():
			var nms = ns[i][1]
			if nms > sms: break
			if ns[i].size() == 2: # (not judged yet)
				if !res.has(i):
					if sms > nms + hitw + 100: ns[i].append("none") # (never reached: the run ended first)
				elif res[i]:
					ns[i].append("hit")
					judged.append([i, srms, sms, true])
				elif sms > nms + hitw or ps == -1:
					ns[i].append("miss")
					judged.append([i, srms, sms, false])
			if i == cur and ns[i].size() > 2 and sms > nms + hitw + 100: cur = i + 1
			i += 1
	# results recorded but not judged before the replay ended (the miss that failed the run lands on
	# its last frame, before the window closes on this clock): judged at the end, in note order
	for i in range(cur, ns.size()):
		if ns[i].size() == 2 and res.has(i):
			ns[i].append("hit" if res[i] else "miss")
			judged.append([i, srms, sms, res[i]])
	# ---- score / combo / accuracy in judgement order
	var spd = clamp((speed - 1.0) * 1.5 + 1.0, 0.0, 1.9)
	var hbo = clamp(_linstep(1.14, 0.0, hbox - 1.14), 0.0, 1.0)
	var hwi = clamp(_linstep(55.0, 0.0, hbox - 55.0), 0.0, 1.0) # (sic: Game.gd compares the hitbox here too)
	var base = int(floor(50.0 * spd * min(hbo, hwi) + 0.5))
	var score = 0
	var combo = 0
	var max_combo = 0
	var lvl = 1
	var prog = 0
	var hits = 0
	var misses = 0
	var rows = []       # per judgement: [song ms, hit, combo, score, accuracy, local accuracy]
	var window = []
	var reset_i = 0
	for j in judged.size():
		while reset_i < level_resets.size() and level_resets[reset_i] <= j:
			lvl = 1
			prog = 0
			reset_i += 1
		var hit = judged[j][3]
		if hit:
			hits += 1
			combo += 1
			max_combo = max(max_combo, combo)
			score += base * lvl
			if lvl != 8:
				prog += 1
				if prog == 10:
					prog = 0
					lvl += 1
					if lvl == 8: prog = 10
		else:
			misses += 1
			combo = 0
			prog = 0
			if lvl != 1: lvl -= 1
		window.append(1 if hit else 0)
		if window.size() > LOCAL: window.pop_front()
		var wsum = 0
		for w in window: wsum += w
		rows.append([ns[judged[j][0]][1], hit, combo, score, float(hits) / (hits + misses), float(wsum) / window.size()])
	# ---- cursor: aim + delay per hit note, speed, heatmap
	var ct = rp.cur_t
	var cxs = rp.cur_x
	var cys = rp.cur_y
	var lo_c = -0.5 + (0.13125 - 0.6 if opts.get("hardrock", false) else 0.13125) # (Cursor.gd: what the hit test sees)
	var hi_c = 2.5 - (0.13125 - 0.6 if opts.get("hardrock", false) else 0.13125)
	var hbs = hbox / 2.0
	if hbs == 0.57: hbs = 0.56875
	var aims = PoolVector2Array()
	var delays = PoolRealArray()
	var unknown_delay = 0
	var per_note = []   # [song ms, hit, aim dx, aim dy, delay (-1 = unknown), delay resolution, note x, note y] per judged note
	for jd in judged:
		var n = ns[jd[0]]
		if !jd[3]:
			per_note.append([n[1], false, 0.0, 0.0, -1.0, 0.0, n[0].x, n[0].y])
			continue
		var rx = jd[1] - max(0.0, jd[2] - n[1]) / max(speed, 0.01) # (replay time the song crossed the note's time)
		var c = _cursor_at(ct, cxs, cys, rx)
		c = Vector2(clamp(c.x, lo_c, hi_c), clamp(c.y, lo_c, hi_c))
		var aim = c - n[0]
		aims.append(aim)
		var dl = -1.0
		var dres = 0.0
		var k = _first_at(ct, rx - 0.5)
		while k < ct.size():
			var s_ms = _sms(sms_at, ct[k])
			if s_ms > n[1] + hitw + 40.0: break # (the game says it was hit: the first sample after that frame still counts)
			var q = Vector2(clamp(cxs[k], lo_c, hi_c), clamp(cys[k], lo_c, hi_c))
			if s_ms >= n[1] - 0.5 and abs(q.x - n[0].x) <= hbs and abs(q.y - n[0].y) <= hbs:
				dl = clamp(s_ms - n[1], 0.0, hitw)
				dres = (ct[k] - ct[k - 1]) * speed if k > 0 else 0.0 # (it got there somewhere since the sample before)
				break
			k += 1
		if dl >= 0: delays.append(dl)
		else: unknown_delay += 1
		per_note.append([n[1], true, aim.x, aim.y, dl, dres, n[0].x, n[0].y])
	var nb = int(ceil(max(1.0, sms_at[sms_at.size() - 1] - (so - 3000.0 * speed)) / SPEED_BIN)) + 1
	var t_from = so - 3000.0 * speed
	var dist = PoolRealArray()
	var tim = PoolRealArray()
	dist.resize(nb)
	tim.resize(nb)
	for b in nb:
		dist[b] = 0.0
		tim[b] = 0.0
	var heat = PoolRealArray()
	heat.resize(HEAT * HEAT)
	for h in heat.size(): heat[h] = 0.0
	var travelled = 0.0
	var moving_s = 0.0
	for k in range(1, ct.size()):
		var dt = ct[k] - ct[k - 1]
		if dt <= 0 or dt > 250.0: continue
		var s0 = _sms(sms_at, ct[k - 1])
		var s1 = _sms(sms_at, ct[k])
		if s1 <= s0: continue # (paused / rewound: not playing)
		var d = Vector2(cxs[k] - cxs[k - 1], cys[k] - cys[k - 1]).length()
		var b = int(clamp((s1 - t_from) / SPEED_BIN, 0, nb - 1))
		dist[b] += d
		tim[b] += dt
		travelled += d
		moving_s += dt / 1000.0
		var hx = int(clamp((cxs[k - 1] + 0.5) / 3.0 * HEAT, 0, HEAT - 1))
		var hy = int(clamp((cys[k - 1] + 0.5) / 3.0 * HEAT, 0, HEAT - 1))
		heat[hy * HEAT + hx] += dt
	var spd_curve = PoolRealArray() # grid units per second of real time, per SPEED_BIN of song time
	spd_curve.resize(nb)
	for b in nb: spd_curve[b] = dist[b] / (tim[b] / 1000.0) if tim[b] > 0 else 0.0
	# ---- summary
	var mean_aim = Vector2.ZERO
	var mean_err = 0.0
	for a in aims:
		mean_aim += a
		mean_err += a.length()
	if aims.size() > 0:
		mean_aim /= aims.size()
		mean_err /= aims.size()
	var gaps = []
	for k in range(1, min(ct.size(), 2000)): gaps.append(ct[k] - ct[k - 1])
	gaps.sort()
	var dsort = Array(delays)
	dsort.sort()
	var reached = 0
	for n in ns: if n.size() > 2 and n[2] != "none": reached += 1
	return {
		"notes": ns.size(), "judged": judged.size(), "hits": hits, "misses": misses, "score": score,
		"max_combo": max_combo, "accuracy": float(hits) / max(1, hits + misses), "pauses": pauses,
		"gave_up": gave_up, "length_rms": length, "song_from": t_from, "song_to": sms_at[sms_at.size() - 1],
		"rows": rows, "per_note": per_note, "aim_mean": mean_aim, "aim_err": mean_err,
		"delay_median": dsort[dsort.size() / 2] if dsort.size() > 0 else -1.0, "delay_known": delays.size(),
		"delay_unknown": unknown_delay, "speed_curve": spd_curve, "speed_bin": SPEED_BIN,
		"hitbox_half": hbs, "heat": heat, "heat_n": HEAT, "sample_ms": gaps[gaps.size() / 2] if gaps.size() > 0 else 0.0, "travelled": travelled, "avg_speed": travelled / max(moving_s, 0.001),
		"sms_at": sms_at, "dt": DT}

static func _by_time(a, b) -> bool:
	return a[2] < b[2]

static func _linstep(a:float, b:float, x:float) -> float:
	if a == b: return float(x >= a)
	return clamp(abs((x - a) / (b - a)), 0.0, 1.0)

# song time at a replay time
static func _sms(sms_at:PoolRealArray, rms:float) -> float:
	var f = rms / DT
	var i = int(floor(f))
	if i < 0: return sms_at[0]
	if i + 1 >= sms_at.size(): return sms_at[sms_at.size() - 1]
	return lerp(sms_at[i], sms_at[i + 1], f - i)

# replay time when the song first reaches `ms` (for "watch from here"); -1 if it never does
static func rms_of(st:Dictionary, ms:float) -> float:
	var a = st.sms_at
	for i in range(1, a.size()):
		if a[i] >= ms and a[i - 1] < ms: return (i - 1 + (ms - a[i - 1]) / max(a[i] - a[i - 1], 0.0001)) * st.dt
	return -1.0

# first cursor sample at or after rms
static func _first_at(ct:PoolRealArray, rms:float) -> int:
	var lo = 0
	var hi = ct.size()
	while lo < hi:
		var mid = (lo + hi) / 2
		if ct[mid] < rms: lo = mid + 1
		else: hi = mid
	return lo

# cursor position at rms, interpolated like Replay.get_cursor_position (smoothstep between samples)
static func _cursor_at(ct:PoolRealArray, cx:PoolRealArray, cy:PoolRealArray, rms:float) -> Vector2:
	var n = ct.size()
	if n == 0: return Vector2(1, 1)
	var k = _first_at(ct, rms)
	if k >= n: return Vector2(cx[n - 1], cy[n - 1])
	if k == 0: return Vector2(cx[0], cy[0])
	var v = clamp(smoothstep(ct[k - 1], ct[k], rms), 0.0, 1.0)
	return Vector2(lerp(cx[k - 1], cx[k], v), lerp(cy[k - 1], cy[k], v))

# replay options from its state string (Rhythia.parse_pb_str) + the settings that aren't recorded
static func opts_of(rp:Dictionary) -> Dictionary:
	var st = Rhythia.parse_pb_str(rp.state_str)
	var lvl = st.get("mod_speed_level", Globals.SPEED_NORMAL)
	var speed = float(st.get("custom_speed", 1.0)) if lvl == Globals.SPEED_CUSTOM else float(Globals.speed_multi[lvl])
	var hw = float(st.get("hitwindow_ms", 55.0))
	if Rhythia.speed_hitwindow: hw *= speed
	if st.get("mod_hardrock", false): hw *= 0.8
	return {"speed": speed, "hitbox": float(st.get("note_hitbox_size", 1.14)), "hit_window": hw,
		"start_offset": float(st.get("start_offset", 0.0)), "mirror_x": st.get("mod_mirror_x", false),
		"mirror_y": st.get("mod_mirror_y", false), "hardrock": st.get("mod_hardrock", false), "state": st}
