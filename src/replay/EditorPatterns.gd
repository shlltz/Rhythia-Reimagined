extends Reference
# Map editor pattern tools (Rhythia-reimagined). Pure functions: settings in, notes ([x, y, ms] as
# Song.notes holds them, x / y on the 3x3 grid 0..2, floats allowed) out - the editor inserts them
# as one undo step and selects them, so they stay normal editable notes. Deterministic: the same
# settings give the same notes (jumps use a generator seeded from the settings, never the clock).
# Clean-room; the ideas (streams, jumps, spirals, mirrored sections, pattern slots) are common
# rhythm-game mapping tools, also found in the Sound Space Quantum Editor.

const CENTER = Vector2(1, 1)
const PATHS = ["row", "column", "snake", "zigzag", "circle", "corners", "cross"]

# n notes, `step_ms` apart from t0, walking a path of cells. Paths:
#   row / column: left-right (top-down) lines, wrapping;  snake: rows back and forth;
#   zigzag: top / bottom alternating left to right;  circle: the 8 outer cells clockwise;
#   corners: the 4 corners clockwise;  cross: centre and its 4 neighbours
static func stream(t0:float, step_ms:float, n:int, path:String = "snake", start:int = 0) -> Array:
	var cells = path_cells(path)
	var out = []
	for i in n:
		var c = cells[(start + i) % cells.size()]
		out.append([float(c.x), float(c.y), int(round(t0 + i * step_ms))])
	return out

static func path_cells(path:String) -> Array:
	match path:
		"row": return [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(0, 1), Vector2(1, 1), Vector2(2, 1), Vector2(0, 2), Vector2(1, 2), Vector2(2, 2)]
		"column": return [Vector2(0, 0), Vector2(0, 1), Vector2(0, 2), Vector2(1, 0), Vector2(1, 1), Vector2(1, 2), Vector2(2, 0), Vector2(2, 1), Vector2(2, 2)]
		"zigzag": return [Vector2(0, 0), Vector2(1, 2), Vector2(2, 0), Vector2(1, 2)]
		"circle": return [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(2, 1), Vector2(2, 2), Vector2(1, 2), Vector2(0, 2), Vector2(0, 1)]
		"corners": return [Vector2(0, 0), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2)]
		"cross": return [Vector2(1, 1), Vector2(1, 0), Vector2(2, 1), Vector2(1, 2), Vector2(0, 1)]
	return [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(2, 1), Vector2(1, 1), Vector2(0, 1), Vector2(0, 2), Vector2(1, 2), Vector2(2, 2)] # snake

# n jumps: each note at least `min_dist` cells (grid units) from the one before, on the 9 cells
static func jumps(t0:float, step_ms:float, n:int, min_dist:float = 1.5, seed_:int = 1) -> Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash([int(t0), int(step_ms * 100), n, int(min_dist * 100), seed_])
	var out = []
	var prev = Vector2(-10, -10)
	for i in n:
		var pick = null
		var opts = []
		for y in 3:
			for x in 3:
				if Vector2(x, y).distance_to(prev) >= min_dist: opts.append(Vector2(x, y))
		if opts.empty(): # (min_dist too large for the grid: the farthest cells)
			var far = 0.0
			for y in 3:
				for x in 3: far = max(far, Vector2(x, y).distance_to(prev))
			for y in 3:
				for x in 3:
					if Vector2(x, y).distance_to(prev) >= far - 0.001: opts.append(Vector2(x, y))
		pick = opts[rng.randi() % opts.size()]
		out.append([pick.x, pick.y, int(round(t0 + i * step_ms))])
		prev = pick
	return out

# n notes on a circle (or a spiral when r1 != r0) around `center`, `turns` times round
static func spiral(t0:float, step_ms:float, n:int, r0:float = 1.0, r1:float = 1.0, turns:float = 1.0, clockwise:bool = true, center:Vector2 = CENTER, start_deg:float = -90.0) -> Array:
	var out = []
	for i in n:
		var k = float(i) / max(1, n - 1) if n > 1 else 0.0
		var a = deg2rad(start_deg) + (1.0 if clockwise else -1.0) * TAU * turns * (float(i) / max(1, n))
		var r = lerp(r0, r1, k)
		var p = center + Vector2(cos(a), sin(a)) * r
		out.append([stepify(p.x, 0.001), stepify(p.y, 0.001), int(round(t0 + i * step_ms))])
	return out

# ------------------------------------------------------------------ transforms (selection)
# ops: "mirror_x", "mirror_y", "rotate" (deg, about pivot), "scale" (factor about pivot),
# "reverse" (time order flipped inside the selection's span), "shift" (ms)
static func transform(ns:Array, op:String, amount:float = 0.0, pivot:Vector2 = CENTER) -> Array:
	var out = []
	if ns.empty(): return out
	var t_min = ns[0][2]
	var t_max = ns[0][2]
	for n in ns:
		t_min = min(t_min, n[2])
		t_max = max(t_max, n[2])
	for n in ns:
		var p = Vector2(n[0], n[1])
		var t = n[2]
		match op:
			"mirror_x": p.x = 2.0 * pivot.x - p.x
			"mirror_y": p.y = 2.0 * pivot.y - p.y
			"rotate": p = pivot + (p - pivot).rotated(deg2rad(amount))
			"scale": p = pivot + (p - pivot) * amount
			"reverse": t = t_min + t_max - t
			"shift": t = t + amount
		out.append([_tidy(p.x), _tidy(p.y), int(round(t))])
	return out

static func _tidy(v:float) -> float:
	var r = round(v)
	return r if abs(v - r) < 0.0005 else stepify(v, 0.001)

# the selection played again after itself `times` times, each copy transformed once more
# (copy k = op applied k times), starting `period_ms` after the previous copy
static func repeat(ns:Array, times:int, period_ms:float, op:String = "none", amount:float = 0.0) -> Array:
	var out = []
	var cur = ns.duplicate(true)
	for k in times:
		cur = transform(cur, "shift", period_ms)
		if op != "none": cur = transform(cur, op, amount)
		out += cur
	return out

# a mirrored copy of the selection right after it ("mirror section"): call-and-response patterns
static func mirror_section(ns:Array, axis:String, gap_ms:float) -> Array:
	if ns.empty(): return []
	var t_min = ns[0][2]
	var t_max = ns[0][2]
	for n in ns:
		t_min = min(t_min, n[2])
		t_max = max(t_max, n[2])
	return transform(transform(ns, "shift", t_max - t_min + gap_ms), "mirror_x" if axis == "x" else "mirror_y")

# a Bezier curve through control notes (by time): one note per time in `times`, the curve parameter
# going linearly in time from the first control note to the last (de Casteljau)
static func bezier(ctrl:Array, times:Array) -> Array:
	var out = []
	if ctrl.size() < 2 or times.empty(): return out
	var t0 = float(ctrl[0][2])
	var t1 = float(ctrl[ctrl.size() - 1][2])
	for t in times:
		var u = clamp((t - t0) / max(t1 - t0, 1.0), 0.0, 1.0)
		var pts = []
		for c in ctrl: pts.append(Vector2(c[0], c[1]))
		while pts.size() > 1:
			var nx = []
			for i in pts.size() - 1: nx.append(pts[i].linear_interpolate(pts[i + 1], u))
			pts = nx
		out.append([_tidy(pts[0].x), _tidy(pts[0].y), int(round(t))])
	return out

# selection centroid (pivot for rotate / scale "about the selection")
static func centroid(ns:Array) -> Vector2:
	if ns.empty(): return CENTER
	var c = Vector2.ZERO
	for n in ns: c += Vector2(n[0], n[1])
	return c / ns.size()

# notes outside the playable area (the cursor reaches roughly -0.5 .. 2.5)
static func out_of_bounds(ns:Array) -> int:
	var k = 0
	for n in ns:
		if n[0] < -0.5 or n[0] > 2.5 or n[1] < -0.5 or n[1] > 2.5: k += 1
	return k

# pattern slots (1-9): a selection stored relative to its first note, recalled at any time
static func to_slot(ns:Array) -> Array:
	if ns.empty(): return []
	var t0 = ns[0][2]
	for n in ns: t0 = min(t0, n[2])
	var out = []
	for n in ns: out.append([n[0], n[1], n[2] - t0])
	return out

static func from_slot(slot:Array, at_ms:float) -> Array:
	var out = []
	for n in slot: out.append([float(n[0]), float(n[1]), int(round(at_ms + n[2]))])
	return out
