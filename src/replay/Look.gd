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

# grade letters (S / A / F...): a heavy display face (Exo 2 ExtraBold, added by the theme build) -
# null when it isn't there (share builds keep their font)
const GRADE_FONT = "res://mods/look/grade.ttf"
static func grade_font(size:int):
	if !(ResourceLoader.exists(GRADE_FONT) or File.new().file_exists(GRADE_FONT)): return null
	var d = DynamicFontData.new()
	d.font_path = GRADE_FONT
	var f = DynamicFont.new()
	f.font_data = d
	f.size = size
	f.use_filter = true
	return f

# static chromatic aberration + glitch over a control (a grade letter): red / blue pulled apart by
# `split` px and a few horizontal slices shifted - fixed (seeded), no animation. Reads the screen
# right where the control is drawn (BackBufferCopy of its rect, a bit wider for the shifts).
const STATIC_GLITCH_SHADER = """shader_type canvas_item;
uniform float split = 4.0;
uniform float seed = 1.0;
uniform vec2 size = vec2(100.0, 100.0);
float hash(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	float band = floor(UV.y * 11.0);
	float on = step(0.62, hash(band * 7.13 + seed));
	float shift = (hash(band * 1.7 + seed * 3.1) - 0.5) * 0.16 * on;
	vec2 uv = SCREEN_UV + vec2(shift * size.x * SCREEN_PIXEL_SIZE.x, 0.0);
	vec2 sp = vec2((split + 3.0 * on) * SCREEN_PIXEL_SIZE.x, 0.0);
	vec4 c = textureLod(SCREEN_TEXTURE, uv, 0.0);
	c.r = textureLod(SCREEN_TEXTURE, uv + sp, 0.0).r;
	c.b = textureLod(SCREEN_TEXTURE, uv - sp, 0.0).b;
	COLOR = vec4(c.rgb, 1.0);
}"""
static func static_glitch(target:Control, sd:float = 1.0, split:float = 4.0):
	if target.has_meta("rr_glitch"): return
	var par = target.get_parent()
	# drawn right after the target as siblings, not children: a child would take on the target's
	# colour / alpha (the grade letter's tint) and show as a tinted box
	var bb = BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT # (a rect copy came out black on the results layer)
	par.add_child(bb)
	par.move_child(bb, target.get_index() + 1)
	var o = ColorRect.new()
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.material = ShaderMaterial.new()
	o.material.shader = Shader.new()
	o.material.shader.code = STATIC_GLITCH_SHADER
	o.material.set_shader_param("seed", sd)
	o.material.set_shader_param("split", split)
	par.add_child(o)
	par.move_child(o, bb.get_index() + 1)
	target.set_meta("rr_glitch", [bb, o])
	target.connect("item_rect_changed", load("res://mods/replay/Look.gd"), "_glitch_fit", [target])
	target.connect("visibility_changed", load("res://mods/replay/Look.gd"), "_glitch_fit", [target])
	_glitch_fit(target)

static func _glitch_fit(target:Control):
	var m = target.get_meta("rr_glitch")
	var bb = m[0]
	var o = m[1]
	if !is_instance_valid(o): return
	o.rect_position = target.rect_position
	o.rect_size = target.rect_size
	o.visible = target.visible
	bb.visible = target.visible
	o.material.set_shader_param("size", target.rect_size)

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
