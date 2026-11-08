extends DanceMover
# Autoplay cursor = the Rhythia rewrite's (Rhythia/Client scripts/game/AutoplayHandler.cs, AGPL-3.0;
# personal build only), ported to GDScript (replaces the stock BouncyDanceMover in Replay.gd).
# Notes at the same ms are averaged, near-simultaneous ones in reach merged; each point is pulled toward
# the middle on slow moves and pushed out on fast reversals; stacks are compressed; then each point may
# shift (up to a quarter hitbox) onto the spline through its neighbours if every note still gets hit.
# The cursor follows a time-weighted Catmull-Rom spline (alpha 0.4, tension -1) through the points.
# Rewrite coordinates are centred (-1..1); legacy notes are 0..2, so everything is shifted by 1.

const HITBOX = 0.57            # rewrite 0.5 + HIT_BOX_SIZE 0.07
const BOUNDS = 1.36875         # rewrite GRID_SIZE / 2 - CURSOR_SIZE / 2
const MAX_SHIFT = 0.25

var data:Array = []            # processed points: Vector3(x, y, ms), centred
var last:int = 0

func _init(song:Song):
	var notes = []
	for n in song.read_notes():
		var x = float(n[0])
		var y = float(n[1])
		if Rhythia.mod_mirror_x: x = 2 - x
		if Rhythia.mod_mirror_y: y = 2 - y
		notes.append(Vector3(x - 1.0, y - 1.0, float(n[2])))
	if notes.empty(): return
	notes = _merge(notes)
	var pre = _initial(notes)
	_shift(notes, pre, _compress(pre))

func _update(ms:float) -> Vector2:
	if data.empty(): return Vector2(1, 1)
	if ms < data[last].z: last = max(0, _lower(data, ms) - 1)
	while last + 1 < data.size() and data[last + 1].z <= ms: last += 1
	var p = _spline(data[max(last - 1, 0)], data[last], data[min(last + 1, data.size() - 1)], data[min(last + 2, data.size() - 1)], ms)
	return _clampb(p) + Vector2(1, 1)

static func _pos(v:Vector3) -> Vector2:
	return Vector2(v.x, v.y)

static func _clampb(p:Vector2) -> Vector2:
	return Vector2(clamp(p.x, -BOUNDS, BOUNDS), clamp(p.y, -BOUNDS, BOUNDS))

static func _hit(note:Vector3, c:Vector2, size:float) -> bool:
	return max(abs(note.x - c.x), abs(note.y - c.y)) < size

static func _sigmoid(v:float) -> float:
	return 1.0 / (1.0 + exp(-v))

static func _lower(a:Array, t:float) -> int:
	var lo = 0
	var hi = a.size()
	while lo < hi:
		var mid = (lo + hi) / 2
		if a[mid].z < t: lo = mid + 1
		else: hi = mid
	return lo

static func _merge(notes:Array) -> Array:
	for i in range(1, notes.size()):
		if notes[i].z < notes[i - 1].z:
			notes.sort_custom(load("res://mods/replay/RewriteAuto.gd"), "_by_ms")
			break
	var out = []
	var i = 0
	while i < notes.size():
		var first = notes[i]
		i += 1
		var p = _pos(first)
		var c = 1
		while i < notes.size() and notes[i].z == first.z:
			p += _pos(notes[i]); c += 1; i += 1
		p /= c
		out.append(Vector3(p.x, p.y, first.z))
	return out

static func _by_ms(a, b) -> bool:
	return a.z < b.z

static func _initial(notes:Array) -> Array:
	var pre = []
	var i = 0
	while i < notes.size():
		var note = notes[i]
		i += 1
		var collected = [note]
		while i < notes.size():
			var nx = notes[i]
			if abs(nx.z - note.z) <= 5 and _hit(note, _pos(nx), HITBOX * 0.9):
				collected.append(nx); i += 1
			else: break
		var avg = Vector2.ZERO
		for c in collected: avg += _pos(c)
		avg /= collected.size()
		if pre.size() > 0:
			var prev = pre[-1]
			var prevp = _pos(prev)
			var te = abs(prev.z - note.z) / 1000.0
			if te > 0:
				var speed = prevp.distance_to(avg) / (te * 100.0)
				avg *= 0.8 + (_sigmoid(speed * 5.0) - 0.5) * 2.0 * 0.2
			if i > 2 and pre.size() >= 2:
				var d1 = (prevp - _pos(pre[-2])).normalized()
				var d2 = (avg - prevp).normalized()
				avg *= 1.0 + max(-d1.dot(d2) - 0.5, 0.0) * (1.0 / (te * 20.0 + 1.0))
		var nn = Vector3(avg.x, avg.y, note.z)
		var pn = notes[max(i - 2, 0)]
		if collected.size() == 1 and note.x == pn.x and note.y == pn.y and pre.size() > 0:
			nn = Vector3(pre[-1].x, pre[-1].y, note.z)
		pre.append(nn)
	return pre

static func _compress(notes:Array) -> Array:
	var out = []
	for i in notes.size():
		var n = notes[i]
		if i > 0 and i + 1 < notes.size() and _pos(notes[i - 1]) == _pos(n) and _pos(notes[i + 1]) == _pos(n):
			continue
		out.append(n)
	return out

func _shift(orig:Array, pre:Array, sec:Array):
	var lim = HITBOX * MAX_SHIFT
	var m = sec.size()
	for i in range(0, m - 1):
		var n0 = sec[max(i - 2, 0)]
		var n1 = sec[max(i - 1, 0)]
		var n2 = sec[i]
		var n3 = sec[i + 1]
		var n4 = sec[min(i + 2, m - 1)]
		if _pos(n1) == _pos(n2) or _pos(n2) == _pos(n3):
			data.append(n2)
			continue
		var p = _spline(n0, n1, n3, n4, n2.z)
		var sh = _clamp_shift(p - _pos(n2), lim)
		var shifted = Vector3(n2.x + sh.x, n2.y + sh.y, n2.z)
		var val = data.slice(max(0, data.size() - 3), data.size() - 1) if data.size() > 0 else []
		val.append(shifted)
		for q in range(i + 1, min(i + 4, m)): val.append(sec[q])
		var ok = true
		var lo = val[min(2, val.size() - 1)].z
		var hi = val[max(0, val.size() - 3)].z
		var k = _lower(orig, lo)
		while k < orig.size():
			var note = orig[k]
			if note.z > hi: break
			if !(_hit(note, _from(val, note.z + 1), HITBOX * 0.9) or _hit(note, _from(val, note.z + 5), HITBOX * 0.9)):
				ok = false
				break
			k += 1
		data.append(shifted if ok else n2)
	data.append(pre[-1])

static func _from(a:Array, t:float) -> Vector2:
	if a.empty(): return Vector2.ZERO
	var j = 0
	while j + 1 < a.size() and a[j + 1].z <= t: j += 1
	return _clampb(_spline(a[max(j - 1, 0)], a[j], a[min(j + 1, a.size() - 1)], a[min(j + 2, a.size() - 1)], t))

static func _spline(n0:Vector3, n1:Vector3, n2:Vector3, n3:Vector3, t:float) -> Vector2:
	var dur = n2.z - n1.z
	if dur <= 0: return _pos(n1)
	if _pos(n1) == _pos(n2): return _pos(n1)
	var u = clamp((t - n1.z) / dur, 0.0, 1.0)
	return Vector2(_cr(n0.x, n1.x, n2.x, n3.x, u, n0.z, n1.z, n2.z, n3.z), _cr(n0.y, n1.y, n2.y, n3.y, u, n0.z, n1.z, n2.z, n3.z))

static func _cr(p0:float, p1:float, p2:float, p3:float, u:float, t0:float, t1:float, t2:float, t3:float) -> float:
	var alpha = 0.4
	var tension = -1.0
	var t01 = pow(max(abs(t0 - t1), 1.0), alpha)
	var t12 = pow(max(abs(t1 - t2), 1.0), alpha)
	var t23 = pow(max(abs(t2 - t3), 1.0), alpha)
	var m1 = (1.0 - tension) * (p2 - p1 + t12 * ((p1 - p0) / t01 - (p2 - p0) / (t01 + t12)))
	var m2 = (1.0 - tension) * (p2 - p1 + t12 * ((p3 - p2) / t23 - (p3 - p1) / (t12 + t23)))
	if is_nan(m1) or is_inf(m1): m1 = 0.0
	if is_nan(m2) or is_inf(m2): m2 = 0.0
	var u2 = u * u
	return (2.0 * (p1 - p2) + m1 + m2) * u2 * u + (-3.0 * (p1 - p2) - m1 - m1 - m2) * u2 + m1 * u + p1

static func _clamp_shift(s:Vector2, l:float) -> Vector2:
	if s.x == 0 or s.y == 0:
		return Vector2(clamp(s.x, -l, l), clamp(s.y, -l, l))
	s *= clamp(s.x, -l, l) / s.x
	s *= clamp(s.y, -l, l) / s.y
	return s
