extends CanvasLayer
# Pass effects: once every note is done on a pass, a green glow
# fades in around all four screen edges; when the map ends on a pass, the last frame zooms out
# and fades to black before the results screen (instead of the plain black fade).
# Added to Game by Game._ready when this file exists; Game.end() calls zoom_in().

const GREEN = Color(0.3, 1.0, 0.45)
const WIDTH = 0.12       # glow depth, share of the screen height
const ZOOM_TIME = 0.9

var game:Node
var glow:float = 0.0
var t:float = 0.0
var draw:Control

func _ready():
	game = get_parent()
	layer = 50
	pause_mode = PAUSE_MODE_PROCESS # Game pauses the tree when the map ends
	draw = Control.new()
	draw.anchor_right = 1
	draw.anchor_bottom = 1
	draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw.connect("draw", self, "_draw_glow")
	add_child(draw)

func _process(delta):
	if zooming: return
	t += delta
	var on = game.get("passed") and !Rhythia.queue_active
	glow = move_toward(glow, 1.0 if on else 0.0, delta / 0.8)
	if glow > 0: draw.update()

func _draw_glow():
	if glow <= 0: return
	var s = draw.rect_size
	var d = s.y * WIDTH * (0.9 + 0.1 * sin(t * 3.0))
	var edge = Color(GREEN.r, GREEN.g, GREEN.b, 0.45 * glow * (0.85 + 0.15 * sin(t * 3.0)))
	var clear = Color(GREEN.r, GREEN.g, GREEN.b, 0.0)
	# each side a quad fading inward; corners overlap a little (brighter corners, like a vignette)
	var quads = [
		[Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x - d, d), Vector2(d, d)],
		[Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - d, s.y - d), Vector2(s.x - d, d)],
		[Vector2(s.x, s.y), Vector2(0, s.y), Vector2(d, s.y - d), Vector2(s.x - d, s.y - d)],
		[Vector2(0, s.y), Vector2(0, 0), Vector2(d, d), Vector2(d, s.y - d)]]
	for q in quads:
		draw.draw_polygon(PoolVector2Array(q), PoolColorArray([edge, edge, clear, clear]))

# freeze the last frame, pull back from it while fading to black; Game.end() yields on this.
# The tree is paused by then, so the picture on screen doesn't change: it is drawn again each
# frame through a screen-reading shader (zoom + fade) instead of being read back from the GPU
# (perf: get_data() on the screen stalled for 35-50 ms the moment a map was passed).
const ZOOM_SHADER = """shader_type canvas_item;
uniform float zoom = 1.0; // 1 = full size; smaller pulls the picture back toward the centre
uniform float fade = 0.0; // 0..1 to black
void fragment() {
	vec2 uv = (SCREEN_UV - vec2(0.5)) / zoom + vec2(0.5);
	vec3 c = vec3(0.0);
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) c = textureLod(SCREEN_TEXTURE, uv, 0.0).rgb;
	COLOR = vec4(mix(c, vec3(0.0), fade), 1.0);
}"""
var zooming:bool = false

# One material for the whole session, its shader compiled while a map loads (warm): this engine
# build compiles a shader on the frame it is first drawn (~0.1 s), which would land on the pass.
static func zoom_material() -> ShaderMaterial:
	if Engine.has_meta("rr_pass_zoom"): return Engine.get_meta("rr_pass_zoom")
	var m = ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = ZOOM_SHADER
	Engine.set_meta("rr_pass_zoom", m)
	return m

# draws the zoom shader once, in a 2 px square that shows the screen unchanged (songload calls this
# while the loading card is up; once per session)
static func warm(parent:Node):
	if Engine.has_meta("rr_pass_zoom_warm"): return
	Engine.set_meta("rr_pass_zoom_warm", true)
	var r = ColorRect.new()
	r.rect_size = Vector2(2, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.material = zoom_material()
	r.material.set_shader_param("zoom", 1.0)
	r.material.set_shader_param("fade", 0.0)
	parent.add_child(r)
	parent.get_tree().create_timer(0.5).connect("timeout", r, "queue_free")

func zoom_in():
	zooming = true # (the edge glow holds still: it is part of the frozen picture)
	var shot = ColorRect.new()
	shot.anchor_right = 1
	shot.anchor_bottom = 1
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot.material = zoom_material()
	shot.material.set_shader_param("zoom", 1.0)
	shot.material.set_shader_param("fade", 0.0)
	add_child(shot)
	yield(get_tree(), "idle_frame") # sizes settle
	var k = 0.0
	while k < 1.0:
		yield(get_tree(), "idle_frame")
		k = min(1.0, k + get_process_delta_time() / ZOOM_TIME)
		var e = 1.0 - pow(1.0 - k, 3) # (eases out: a smooth pull back from the grid)
		var f = clamp((k - 0.3) / 0.7, 0.0, 1.0)
		shot.material.set_shader_param("zoom", 1.0 - 0.18 * e)
		shot.material.set_shader_param("fade", f * f * (3.0 - 2.0 * f))
