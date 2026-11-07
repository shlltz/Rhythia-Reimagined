extends DanceMover
# Autoplay cursor that moves like a hand (personal build; replaces the stock BouncyDanceMover in
# Replay.gd). Per note an aim point a little off the centre (cuts corners toward the next note, a small
# fixed per-note error). Between two notes:
#  - streams (gap shorter than the time a hand needs, Fitts' law): one continuous flowing curve, the
#    cursor passes through notes with a Catmull-Rom velocity;
#  - jumps with time to spare: the cursor overshoots the note it just hit a little and settles, waits,
#    then makes a minimum-jerk reach (bell-shaped speed) to the next note with a slight sideways bow;
#  - long breaks: the hand relaxes toward the middle and wanders more.
# A low-amplitude hand tremor on top. Everything is a function of song time, so seeking is exact.
# Times inside are "hand" ms (song ms / speed multiplier), positions are note grid units (0..2).

const SETTLE = 55.0          # ms the overshoot takes to settle
const OVERSHOOT = 0.13    # max overshoot (grid units)
const CENTRE = Vector2(1, 1)

var speed:float = 1.0
var P:PoolVector2Array = PoolVector2Array()  # aim points
var T:PoolRealArray = PoolRealArray()        # hand ms
var V:PoolVector2Array = PoolVector2Array()  # velocity through each point (units / hand ms)
var S:PoolRealArray = PoolRealArray()        # when the reach toward point i+1 starts
var BOW:PoolRealArray = PoolRealArray()
var seg:int = 0

func _init(song:Song):
	speed = max(0.05, Globals.speed_multi[Rhythia.mod_speed_level])
	var notes = []
	for n in song.read_notes():
		var p = Vector2(n[0], n[1])
		if Rhythia.mod_mirror_x: p.x = 2 - p.x
		if Rhythia.mod_mirror_y: p.y = 2 - p.y
		var t = float(n[2]) / speed
		if notes.size() > 0 and t - notes[-1][1] < 10.0 / speed: # (chords / near-stacks: aim between)
			notes[-1][0] = (notes[-1][0] + p) * 0.5
		else: notes.append([p, t])
	if notes.size() == 0:
		notes.append([CENTRE, 0.0])
	var rng = RandomNumberGenerator.new()
	rng.seed = 1337 + notes.size()
	var n = notes.size()
	# virtual first point (resting near the middle) and last (relax back to it)
	P.append(lerp(CENTRE, notes[0][0], 0.35)); T.append(notes[0][1] - 1400.0)
	for i in n:
		var p:Vector2 = notes[i][0]
		var a = p
		if i > 0 and i < n - 1: # cut the corner toward the neighbours
			var cut:Vector2 = (notes[i - 1][0] + notes[i + 1][0]) * 0.5 - p
			a += cut.clamped(1.0) * 0.12
		a += Vector2(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.06, 0.06))
		P.append(a); T.append(notes[i][1])
	P.append(lerp(CENTRE, notes[n - 1][0], 0.3)); T.append(notes[n - 1][1] + 1600.0)
	var m = P.size()
	S.resize(m); V.resize(m); BOW.resize(m)
	var flow = []
	flow.resize(m)
	for i in m:
		BOW[i] = rng.randf_range(-0.07, 0.07)
		if i == m - 1:
			S[i] = T[i]; flow[i] = false
			continue
		var g = T[i + 1] - T[i]
		var mt = _move_time(P[i].distance_to(P[i + 1]), g)
		if i == m - 2: mt = max(mt, 600.0) # (relaxing at the end: slow)
		flow[i] = g <= mt * 1.15
		S[i] = T[i] if flow[i] else T[i + 1] - mt
	for i in m:
		var v = Vector2.ZERO
		if i > 0 and i < m - 1:
			var tng = (P[i + 1] - P[i - 1]) / max(T[i + 1] - T[i - 1], 1.0)
			if flow[i]:
				v = tng * (0.9 if flow[i - 1] else 0.6)
			else: # stopping here: carry on a little past it and settle
				var mv = max(T[i] - S[i - 1], 1.0)
				v = (P[i] - P[i - 1]) / mv * 0.35
				if v.length() * SETTLE > OVERSHOOT: v = v.normalized() * OVERSHOOT / SETTLE
		V[i] = v

# Fitts-style reach time (hand ms) for a distance; slower when there's lots of time
func _move_time(d:float, gap:float) -> float:
	var mt = 70.0 + 95.0 * log(d + 1.0) / log(2.0)
	return max(mt, min(gap * 0.55, mt * 1.8))

# resting after point i (overshoot settling, relaxing toward the middle on long breaks)
func _rest(i:int, h:float) -> Vector2:
	var dt = max(0.0, h - T[i])
	var p = P[i] + V[i] * SETTLE * (1.0 - exp(-dt / SETTLE))
	var relax = _relax(i, h)
	if relax > 0.0: p = lerp(p, lerp(p, CENTRE, 0.35), relax)
	return p

func _relax(i:int, h:float) -> float:
	if i + 1 >= T.size(): return 0.0
	var gap = T[i + 1] - T[i]
	if gap < 2200.0: return 0.0
	var dt = h - T[i]
	return smoothstep(700.0, 1800.0, dt) * (1.0 - smoothstep(S[i] - 900.0, S[i], h))

func _tremor(h:float, k:float) -> Vector2:
	var x = 0.010 * sin(h * 0.0041 + 1.3) + 0.006 * sin(h * 0.0097 + 0.4) + 0.0022 * sin(h * 0.053)
	var y = 0.009 * sin(h * 0.0037 + 2.1) + 0.006 * sin(h * 0.0089 + 5.0) + 0.0022 * sin(h * 0.047 + 1.0)
	return Vector2(x, y) * k

func _update(ms:float) -> Vector2:
	var h = ms / speed
	var m = T.size()
	if h <= T[0]: return _out(P[0] + _tremor(h, 1.0))
	if h >= T[m - 1]: return _out(P[m - 1] + _tremor(h, 1.6))
	# segment i: T[i] <= h < T[i+1]
	if seg >= m - 1 or h < T[seg]:
		var lo = 0
		var hi = m - 1
		while hi - lo > 1:
			var mid = (lo + hi) / 2
			if T[mid] <= h: lo = mid
			else: hi = mid
		seg = lo
	while seg < m - 2 and h >= T[seg + 1]: seg += 1
	var i = seg
	var shake = 1.0 + 1.5 * _relax(i, h)
	if h < S[i]: return _out(_rest(i, h) + _tremor(h, shake))
	# reaching from where the rest left the cursor to the next point (quintic Hermite, no acceleration
	# at the ends = minimum jerk when both velocities are zero)
	var p0 = _rest(i, S[i])
	var v0 = Vector2.ZERO
	if S[i] > T[i]: v0 = (_rest(i, S[i]) - _rest(i, S[i] - 1.0))
	else: v0 = V[i]
	var dur = T[i + 1] - S[i]
	if dur < 1.0: return _out(P[i + 1])
	var s = clamp((h - S[i]) / dur, 0.0, 1.0)
	var s2 = s * s
	var s3 = s2 * s
	var s4 = s3 * s
	var s5 = s4 * s
	var h0 = 1.0 - 10.0 * s3 + 15.0 * s4 - 6.0 * s5
	var h1 = s - 6.0 * s3 + 8.0 * s4 - 3.0 * s5
	var h4 = -4.0 * s3 + 7.0 * s4 - 3.0 * s5
	var h5 = 10.0 * s3 - 15.0 * s4 + 6.0 * s5
	var p = p0 * h0 + v0 * dur * h1 + V[i + 1] * dur * h4 + P[i + 1] * h5
	var d = P[i + 1] - p0
	if d.length() > 0.3: # a slight sideways bow, zero (and flat) at both ends
		p += Vector2(-d.y, d.x) * BOW[i] * 16.0 * s2 * (1.0 - s) * (1.0 - s)
	return _out(p + _tremor(h, shake * (1.0 - 1.6 * s * (1.0 - s))))

func _out(p:Vector2) -> Vector2:
	return Vector2(clamp(p.x, -0.5, 2.5), clamp(p.y, -0.5, 2.5))
