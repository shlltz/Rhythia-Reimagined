extends Reference
# Rhythia-reimagined design tokens shared by the mod screens.

const ACC = Color("#8a6cff")          # mods' accent (the share build swaps it for the logo pink)

# surfaces (near-black -> charcoal) and lines
const BG = Color(0.02, 0.02, 0.024)
const SURFACE = Color(0.05, 0.05, 0.056)
const SURFACE_HI = Color(0.085, 0.085, 0.092)
const LINE = Color(1, 1, 1, 0.1)
const LINE_HI = Color(1, 1, 1, 0.32)
# text: primary / secondary / muted
const TEXT = Color(1, 1, 1)
const TEXT_2 = Color(1, 1, 1, 0.62)
const TEXT_3 = Color(1, 1, 1, 0.38)
# states
const OK = Color("#5cdb7a")
const CRIT = Color("#ff2436")

# motion (seconds): hover / press, small moves, page changes
const T_FAST = 0.12
const T_MED = 0.24
const T_SLOW = 0.4

static func accent() -> Color:
	return ACC

# text drawn on a solid accent fill
static func on_accent() -> Color:
	return Color(1, 1, 1)

# flat box with the shared shape rules
static func box(bg:Color, border:Color = Color(0, 0, 0, 0), bw:int = 0, r:int = 6) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	if r > 0:
		sb.set_corner_radius_all(r)
		sb.corner_detail = 6
		sb.anti_aliasing = true
	return sb

# corner brackets around a rect (arm = arm length)
static func brackets(ci:CanvasItem, r:Rect2, arm:float, col:Color, w:float = 2.0):
	var a = r.position
	var b = r.end
	for c in [[a, Vector2(1, 1)], [Vector2(b.x, a.y), Vector2(-1, 1)], [b, Vector2(-1, -1)], [Vector2(a.x, b.y), Vector2(1, -1)]]:
		var p:Vector2 = c[0]
		var d:Vector2 = c[1]
		ci.draw_line(p, p + Vector2(arm * d.x, 0), col, w)
		ci.draw_line(p, p + Vector2(0, arm * d.y), col, w)
