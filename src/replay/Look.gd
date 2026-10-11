extends Reference
# Rhythia-reimagined design tokens: one palette, shape and motion set for every mod screen.
# The personal build (ssp_mod.py "theme") adds res://mods/look/mono.flag: monochrome surfaces with
# white as the accent, sharp corners and a few ULTRAKILL-style details (inverted hover, corner
# brackets, terminal labels, scanlines), red kept for rare critical moments. Without the flag
# (share builds) the accent look stays as it was.

const ACC = Color("#8a6cff")          # mods' accent (the share build swaps it for the logo pink)
const MONO_ACC = Color(0.93, 0.93, 0.93)

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
const OK = Color("#5cdb7a")           # pass / success (the pass glow keeps its own green)
const CRIT = Color("#ff2436")         # fail, critical, extreme difficulty - used sparingly
# motion (seconds): hover / press, small moves, page changes
const T_FAST = 0.12
const T_MED = 0.24
const T_SLOW = 0.4

static func mono() -> bool:
	if !Engine.has_meta("rr_mono"):
		var p = "res://mods/look/mono.flag"
		Engine.set_meta("rr_mono", ResourceLoader.exists(p) or File.new().file_exists(p))
	return Engine.get_meta("rr_mono")

static func accent() -> Color:
	return MONO_ACC if mono() else ACC

# text drawn on a solid accent fill
static func on_accent() -> Color:
	return Color(0.03, 0.03, 0.035) if mono() else Color(1, 1, 1)

# accent at an alpha (translucent fills / outlines); mono fills are a bit fainter (white is loud)
static func accent_a(a:float) -> Color:
	var c = accent()
	return Color(c.r, c.g, c.b, a * (0.7 if mono() else 1.0))

# corner radius: sharp in the personal build, the given radius elsewhere
static func radius(r:int) -> int:
	return min(r, 2) if mono() else r

# flat box with the shared shape rules
static func box(bg:Color, border:Color = Color(0, 0, 0, 0), bw:int = 0, r:int = 6) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	var rr = radius(r)
	if rr > 0:
		sb.set_corner_radius_all(rr)
		sb.corner_detail = 6
		sb.anti_aliasing = true
	return sb

# terminal-style tag: "PLAY" -> "// PLAY" (personal build), plain text otherwise
static func tag(s:String) -> String:
	return ("// " + s.to_upper()) if mono() else s

# ULTRAKILL-style corner brackets around a rect (len = arm length)
static func brackets(ci:CanvasItem, r:Rect2, arm:float, col:Color, w:float = 2.0):
	var a = r.position
	var b = r.end
	for c in [[a, Vector2(1, 1)], [Vector2(b.x, a.y), Vector2(-1, 1)], [b, Vector2(-1, -1)], [Vector2(a.x, b.y), Vector2(1, -1)]]:
		var p:Vector2 = c[0]
		var d:Vector2 = c[1]
		ci.draw_line(p, p + Vector2(arm * d.x, 0), col, w)
		ci.draw_line(p, p + Vector2(0, arm * d.y), col, w)

# full-rect scanline overlay (no screen read: just thin dark lines and a slow faint roll band);
# add it last, it ignores the mouse. Callers hide it with lighter effects on.
const SCAN_SHADER = """shader_type canvas_item;
uniform float strength = 0.07;
void fragment() {
	float line = step(0.5, fract(FRAGCOORD.y * 0.5));
	float roll = 1.0 - smoothstep(0.0, 0.06, abs(fract(SCREEN_UV.y + TIME * 0.035) - 0.5));
	COLOR = vec4(vec3(roll), line * strength + roll * 0.018);
}"""
static func scanlines(strength:float = 0.07) -> ColorRect:
	var r = ColorRect.new()
	r.name = "Scanlines"
	r.anchor_right = 1
	r.anchor_bottom = 1
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.material = ShaderMaterial.new()
	r.material.shader = Shader.new()
	r.material.shader.code = SCAN_SHADER
	r.material.set_shader_param("strength", strength)
	return r

# greyscale (lifted to near-white) material for colour art in the monochrome build, e.g. the logo
const GREY_SHADER = """shader_type canvas_item;
uniform float lift = 1.9;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = clamp(dot(c.rgb, vec3(0.299, 0.587, 0.114)) * lift, 0.0, 1.0);
	COLOR = vec4(vec3(l), c.a) * COLOR;
}"""
static func grey_material(lift:float = 1.9) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = GREY_SHADER
	m.set_shader_param("lift", lift)
	return m
