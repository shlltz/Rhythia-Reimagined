extends Reference
# Smooth circles for the mod's round UI (results grade ring, volume rings, music button).
# Godot 3's draw_circle has no anti-aliasing and draw_arc's "antialiased" lines get uneven and
# stair-stepped when thick. These build the shape as one triangle mesh with a 1px soft edge, so
# rings and discs look clean at any size and the sweep ends move smoothly (no segment popping).

const FEATHER = 1.0

# ring (or part of one) from angle a0 to a1, w pixels thick; cap = rounded ends
static func arc(ci:CanvasItem, c:Vector2, r:float, w:float, a0:float, a1:float, col:Color, cap:bool = false):
	if col.a <= 0.0 or abs(a1 - a0) < 0.0001: return
	var clear = Color(col.r, col.g, col.b, 0)
	var h = w / 2.0
	_band(ci, c, a0, a1, [r - h - FEATHER, r - h + FEATHER * 0.5, r + h - FEATHER * 0.5, r + h + FEATHER], [clear, col, col, clear])
	if cap and abs(a1 - a0) < TAU - 0.001:
		disc(ci, c + Vector2(cos(a0), sin(a0)) * r, h, col)
		disc(ci, c + Vector2(cos(a1), sin(a1)) * r, h, col)

# straight bars (the spectrum rings): every [from, to, width, colour] in one triangle array with a
# 1px soft edge along both sides. One draw call for all of them: an antialiased draw_line is not
# batched by Godot 3 and cost about five each (the title's 90 bars were ~450 of its 550 draw calls).
static func bars(ci:CanvasItem, segs:Array):
	var n = segs.size()
	if n == 0: return
	var pts = PoolVector2Array()
	pts.resize(n * 8)
	var cs = PoolColorArray()
	cs.resize(n * 8)
	var j = 0
	for s in segs:
		var a:Vector2 = s[0]
		var b:Vector2 = s[1]
		var col:Color = s[3]
		var d = b - a
		var l = d.length()
		d = d / l if l > 0.0001 else Vector2(1, 0)
		var nr = Vector2(-d.y, d.x)
		var h = s[2] * 0.5
		var o0 = nr * (h + FEATHER * 0.5)
		var o1 = nr * max(h - FEATHER * 0.5, 0.0)
		var clear = Color(col.r, col.g, col.b, 0.0)
		pts[j] = a - o0
		pts[j + 1] = a - o1
		pts[j + 2] = a + o1
		pts[j + 3] = a + o0
		pts[j + 4] = b - o0
		pts[j + 5] = b - o1
		pts[j + 6] = b + o1
		pts[j + 7] = b + o0
		cs[j] = clear
		cs[j + 1] = col
		cs[j + 2] = col
		cs[j + 3] = clear
		cs[j + 4] = clear
		cs[j + 5] = col
		cs[j + 6] = col
		cs[j + 7] = clear
		j += 8
	VisualServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _bar_indices(n), pts, cs)

# per bar: 4 vertices across at each end, 3 quads across (cached per bar count)
static func _bar_indices(n:int) -> PoolIntArray:
	var cache:Dictionary = Engine.get_meta("rr_bar_idx") if Engine.has_meta("rr_bar_idx") else {}
	if cache.has(n): return cache[n]
	var idx = PoolIntArray()
	for i in n:
		var b = i * 8
		for k in 3:
			idx.append(b + k); idx.append(b + 4 + k); idx.append(b + k + 1)
			idx.append(b + 4 + k); idx.append(b + 5 + k); idx.append(b + k + 1)
	if cache.size() > 64: cache.clear()
	cache[n] = idx
	Engine.set_meta("rr_bar_idx", cache)
	return idx

# filled circle with a soft edge
static func disc(ci:CanvasItem, c:Vector2, r:float, col:Color):
	if col.a <= 0.0 or r <= 0.0: return
	_band(ci, c, 0.0, TAU, [0.0, max(r - FEATHER * 0.5, 0.0), r + FEATHER * 0.5], [col, col, Color(col.r, col.g, col.b, 0)])

# rings at the given radii (inner to outer), one colour per radius, as a single triangle array.
# Vertices are stored ring by ring (all of radius 0, then all of radius 1, ...): each ring is the
# cached unit directions moved by one native Transform2D.xform, colours are filled by doubling and
# the triangle indices (same triangles, same order as building it point by point) are cached per
# segment count - a 400-segment disc used to cost ~7000 GDScript appends a draw (the title glow
# draws six of them every frame).
static func _band(ci:CanvasItem, c:Vector2, a0:float, a1:float, radii:Array, cols:Array):
	var sweep = a1 - a0
	var n = int(clamp(abs(sweep) * radii[radii.size() - 1] / 2.5, 16, 400)) # ~2.5px per segment
	var m = radii.size()
	var dirs = _dirs(a0, sweep, n)
	var pts = PoolVector2Array()
	var cs = PoolColorArray()
	for k in m:
		var r = max(radii[k], 0.0)
		pts.append_array(Transform2D(Vector2(r, 0), Vector2(0, r), c).xform(dirs)) # = c + d * r, per point
		cs.append_array(_fill(cols[k], n + 1))
	VisualServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _indices(n, m), pts, cs)

# unit directions at the n + 1 segment edges (full circles cached per n; arcs sweep, so not those)
static func _dirs(a0:float, sweep:float, n:int) -> PoolVector2Array:
	var full = a0 == 0.0 and sweep == TAU
	var cache:Dictionary = Engine.get_meta("rr_ring_dirs") if Engine.has_meta("rr_ring_dirs") else {}
	if full and cache.has(n): return cache[n]
	var d = PoolVector2Array()
	for i in n + 1:
		var a = a0 + sweep * float(i) / n
		d.append(Vector2(cos(a), sin(a)))
	if full:
		if cache.size() > 64: cache.clear()
		cache[n] = d
		Engine.set_meta("rr_ring_dirs", cache)
	return d

# triangles of an (n segments x m radii) band, vertex index = ring * (n + 1) + segment edge
static func _indices(n:int, m:int) -> PoolIntArray:
	var key = n * 8 + m
	var cache:Dictionary = Engine.get_meta("rr_ring_idx") if Engine.has_meta("rr_ring_idx") else {}
	if cache.has(key): return cache[key]
	var idx = PoolIntArray()
	var e = n + 1
	for i in range(1, n + 1):
		for k in m - 1:
			var a = k * e + i - 1        # (edge i - 1, ring k)
			var b = (k + 1) * e + i - 1  # (edge i - 1, ring k + 1)
			idx.append(a); idx.append(b); idx.append(a + 1)
			idx.append(b); idx.append(b + 1); idx.append(a + 1)
	if cache.size() > 64: cache.clear()
	cache[key] = idx
	Engine.set_meta("rr_ring_idx", cache)
	return idx

# count copies of one colour, built by doubling (native appends, not one per vertex)
static func _fill(col:Color, count:int) -> PoolColorArray:
	var a = PoolColorArray([col])
	while a.size() < count: a.append_array(a)
	a.resize(count)
	return a

# frame-rate independent smoothing toward a target (rate = how fast, per second)
static func approach(v:float, target:float, rate:float, delta:float) -> float:
	return lerp(v, target, 1.0 - exp(-rate * delta))
