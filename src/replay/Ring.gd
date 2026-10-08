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

# filled circle with a soft edge
static func disc(ci:CanvasItem, c:Vector2, r:float, col:Color):
	if col.a <= 0.0 or r <= 0.0: return
	_band(ci, c, 0.0, TAU, [0.0, max(r - FEATHER * 0.5, 0.0), r + FEATHER * 0.5], [col, col, Color(col.r, col.g, col.b, 0)])

# rings at the given radii (inner to outer), one colour per radius, as a single triangle array
static func _band(ci:CanvasItem, c:Vector2, a0:float, a1:float, radii:Array, cols:Array):
	var sweep = a1 - a0
	var n = int(clamp(abs(sweep) * radii[radii.size() - 1] / 2.5, 16, 400)) # ~2.5px per segment
	var m = radii.size()
	var pts = PoolVector2Array()
	var cs = PoolColorArray()
	var idx = PoolIntArray()
	for i in n + 1:
		var a = a0 + sweep * float(i) / n
		var d = Vector2(cos(a), sin(a))
		for k in m:
			pts.append(c + d * max(radii[k], 0.0))
			cs.append(cols[k])
		if i > 0:
			var b = (i - 1) * m
			for k in m - 1:
				idx.append(b + k); idx.append(b + k + 1); idx.append(b + m + k)
				idx.append(b + k + 1); idx.append(b + m + k + 1); idx.append(b + m + k)
	VisualServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cs)

# frame-rate independent smoothing toward a target (rate = how fast, per second)
static func approach(v:float, target:float, rate:float, delta:float) -> float:
	return lerp(v, target, 1.0 - exp(-rate * delta))
