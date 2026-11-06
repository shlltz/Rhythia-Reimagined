extends CanvasLayer
# Screen changes without black (personal build): the last frame of the screen you leave is frozen on
# a layer over the root, the scene changes under it, and the frozen frame holds until the new screen
# draws smoothly (its first frames hitch while it builds), then moves away:
#   "back"    - shrinks and fades (Esc on the loading card)
#   "forward" - grows past the camera and fades (run -> results)
#   "fail"    - snaps out at once: the frame lunges forward under a zoom blur and dims (SNAP s, before
#               the scene even changes), holds blurred while the results load, then fades
# Through menuload (the black loader between a run and the menu) its fades are skipped, so the menu
# comes up as soon as it is loaded. Frees itself when done.

const TIME = {"back": 0.42, "forward": 0.55, "fail": 0.25}
const SNAP = 0.2
const BLUR_SHADER = """shader_type canvas_item;
uniform float amount = 0.0;
uniform float dim = 1.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	vec3 col = vec3(0.0);
	float j = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453); // (jitter: a smooth streak, not 12 copies)
	for (int i = 0; i < 12; i++) {
		col += texture(TEXTURE, vec2(0.5) + d * (1.0 - amount * (float(i) + j) / 12.0)).rgb;
	}
	col /= 12.0;
	float g = dot(col, vec3(0.3, 0.59, 0.11));
	COLOR = vec4(mix(vec3(g), col, 0.35 + 0.65 * dim) * dim, 1.0);
}"""
const MAX_HOLD = 6.0  # (still loading: the frozen frame waits for the next screen)
const MAX_SETTLE = 0.6 # s it waits for smooth frames once the next screen is up (a slow machine never gets them)

var shot:TextureRect
var style:String = "back"
var from:String = ""
var t:float = 0.0
var held:float = 0.0
var steady:int = 0
var settle:float = 0.0
var pending:String = ""  # (fail: the scene changes once the snap is done)
var snap_t:float = 0.0

static func go(tree:SceneTree, scene:String, style_:String = "back"):
	var old = tree.root.get_node_or_null("RRScreenSwap")
	if old: old.free()
	var img = tree.root.get_texture().get_data()
	if img is Image and img.get_width() > 1:
		img.flip_y()
		var tex = ImageTexture.new()
		tex.create_from_image(img, 0)
		var n = load("res://mods/replay/ScreenSwap.gd").new()
		n.name = "RRScreenSwap"
		n.style = style_
		n.from = tree.current_scene.filename if tree.current_scene else ""
		n.set_meta("tex", tex)
		if style_ == "fail":
			n.pending = scene
			tree.root.add_child(n)
			return
		tree.root.add_child(n)
	tree.change_scene(scene)

# the fail blur compiled ahead (on the loading card): its first use would hitch the snap
static func warm(parent:Node):
	var r = TextureRect.new()
	r.texture = load("res://icon.png") if ResourceLoader.exists("res://icon.png") else null
	r.rect_size = Vector2(2, 2)
	r.expand = true
	r.modulate.a = 0.01
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh = Shader.new()
	sh.code = BLUR_SHADER
	r.material = ShaderMaterial.new()
	r.material.shader = sh
	parent.add_child(r)
	parent.get_tree().create_timer(0.3).connect("timeout", r, "queue_free")

func _ready():
	layer = 99
	pause_mode = PAUSE_MODE_PROCESS
	process_priority = -100 # (before the loader's own _process: its fade is skipped the same frame)
	shot = TextureRect.new()
	shot.texture = get_meta("tex")
	shot.expand = true
	shot.anchor_right = 1
	shot.anchor_bottom = 1
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shot)
	if style == "fail":
		var sh = Shader.new()
		sh.code = BLUR_SHADER
		shot.material = ShaderMaterial.new()
		shot.material.shader = sh

func _process(delta):
	if pending != "": # the snap: fast, accelerating, then the scene changes under the blurred frame
		snap_t += min(delta, 1.0 / 30.0)
		var q = min(snap_t / SNAP, 1.0)
		var qe = q * q
		shot.rect_pivot_offset = shot.rect_size / 2
		shot.rect_scale = Vector2.ONE * (1.0 + 0.3 * qe)
		shot.material.set_shader_param("amount", 0.28 * qe)
		shot.material.set_shader_param("dim", 1.0 - 0.6 * qe)
		if q >= 1.0:
			get_tree().change_scene(pending)
			pending = ""
		return
	var sc = get_tree().current_scene
	var fn = sc.filename if sc else ""
	if steady < 3 and held < MAX_HOLD:
		held += delta
		if !sc or fn == from: return
		if "/loaders/" in fn:
			if "menuload" in fn and "black_fade" in sc: # no black in or out: switch the moment the menu is loaded
				sc.black_fade = 1.0
				sc.black_fade_target = true
			return
		if "black_fade" in sc and sc.get("black_fade") > 0.0 and !sc.get("black_fade_target"): # (the menu's own fade in from black)
			sc.black_fade = 0.0
			var bf = sc.get_node_or_null("BlackFade")
			if bf: bf.visible = false
		settle += delta
		steady = steady + 1 if delta < 0.05 else 0
		if settle > MAX_SETTLE: steady = 3
		return
	t += min(delta, 1.0 / 30.0)
	var k = min(t / TIME.get(style, 0.45), 1.0)
	var e = 1.0 - pow(1.0 - k, 3)
	shot.rect_pivot_offset = shot.rect_size / 2
	var s = (1.0 - 0.08 * e) if style == "back" else (1.0 + 0.12 * e)
	if style == "fail": s = 1.3 + 0.15 * e
	shot.rect_scale = Vector2(s, s)
	shot.modulate.a = 1.0 - k * k * (3.0 - 2.0 * k)
	if k >= 1.0:
		queue_free()
