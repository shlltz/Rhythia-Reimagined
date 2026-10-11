extends CanvasLayer
# Atmosphere overlay (personal build): scanlines, film grain and an optional CRT vignette over the
# menus and result screens in one full-screen shader (no screen read). Strengths come from
# Reimagined settings (fx_*); Look.fx_on() off or lighter effects on = hidden. Menu scene only:
# a run is never covered.
const SHADER = """shader_type canvas_item;
uniform float scan = 0.7;
uniform float grain = 0.3;
uniform float crt = 0.0;
uniform float anim = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float dark = step(0.5, fract(FRAGCOORD.y * 0.5)) * 0.1 * scan;
	vec2 q = SCREEN_UV * 2.0 - 1.0;
	dark = 1.0 - (1.0 - dark) * (1.0 - smoothstep(0.6, 1.3, length(q * vec2(0.85, 1.0))) * 0.6 * crt);
	float g = hash(FRAGCOORD.xy + floor(TIME * 18.0 * anim) * 17.0) - 0.5;
	float ga = abs(g) * 0.2 * grain;
	float a = ga + dark * (1.0 - ga);
	COLOR = vec4(vec3(step(0.0, g)) * ga / max(a, 0.0001), a);
}"""
var rect:ColorRect

func _ready():
	layer = 90
	rect = ColorRect.new()
	rect.anchor_right = 1
	rect.anchor_bottom = 1
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = ShaderMaterial.new()
	rect.material.shader = Shader.new()
	rect.material.shader.code = SHADER
	add_child(rect)
	add_to_group("rr_atmo")
	refresh()

func refresh():
	var Look = load("res://mods/replay/Look.gd")
	var R = load("res://mods/replay/Reimagined.gd")
	var on = Look.fx_on()
	var m = rect.material
	m.set_shader_param("scan", float(R.val("fx_scan")))
	m.set_shader_param("grain", float(R.val("fx_grain")))
	m.set_shader_param("crt", 1.0 if R.val("fx_crt") else 0.0)
	m.set_shader_param("anim", 0.0 if R.lite() else 1.0) # (lighter effects: frozen grain)
	rect.visible = on and (float(R.val("fx_scan")) > 0.0 or float(R.val("fx_grain")) > 0.0 or bool(R.val("fx_crt")))
