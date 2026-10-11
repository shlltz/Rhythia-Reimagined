extends CanvasLayer
# Run effect (personal build, Customize > Interface > Atmosphere "Run effects"): a short red flash
# along the screen edges when a combo of 20 or more breaks. Edges only, 0.22 s, no screen read, one
# rect that is hidden the rest of the time - the playfield stays clear. Added by NoteManager.

const MIN_COMBO = 20
const LEN = 0.22
const SHADER = """shader_type canvas_item;
uniform float k = 0.0;
void fragment() {
	vec2 q = abs(SCREEN_UV * 2.0 - 1.0);
	float e = smoothstep(0.62, 1.05, max(q.x, q.y));
	COLOR = vec4(1.0, 0.14, 0.21, e * 0.5 * k);
}"""
var rect:ColorRect
var game:Node
var t:float = 0.0

func _ready():
	layer = 68
	game = get_parent().get_parent()
	if !game.has_signal("miss"):
		queue_free()
		return
	rect = ColorRect.new()
	rect.anchor_right = 1
	rect.anchor_bottom = 1
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = ShaderMaterial.new()
	rect.material.shader = Shader.new()
	rect.material.shader.code = SHADER
	rect.visible = false
	add_child(rect)
	game.connect("miss", self, "_miss")
	set_process(false)

func _miss(_col):
	if game.combo < MIN_COMBO: return # (signal comes before the combo is reset)
	t = LEN
	rect.visible = true
	set_process(true)

func _process(delta):
	t -= delta
	var k = clamp(t / LEN, 0.0, 1.0)
	rect.material.set_shader_param("k", k * k)
	if t <= 0.0:
		rect.visible = false
		set_process(false)
