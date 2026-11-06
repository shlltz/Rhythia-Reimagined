extends CanvasLayer
# Loading screen -> run without a black screen: songload freezes its last frame (map card over the
# blurred cover) into this layer on the root, then switches to the run. The frozen frame fades out
# and drifts towards the viewer while the game camera eases in from a wider view, so the playfield
# grows into place under it. Frees itself when done.

const TIME = 0.85
const SNAP_IN = 0.3 # snap mode (map start): the fail snap in reverse - the run comes in zoomed, blurred
                    # and dim and settles sharp (ease-out), with a soft thump + whoosh (made on the loading card)
const SNAP_SHADER = """shader_type canvas_item;
uniform float amount = 0.0;
uniform float zoom = 1.0;
uniform float dim = 1.0;
void fragment() {
	vec2 d = (SCREEN_UV - vec2(0.5)) / zoom;
	float j = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 col = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		col += texture(SCREEN_TEXTURE, vec2(0.5) + d * (1.0 - amount * (float(i) + j) / 12.0)).rgb;
	}
	col /= 12.0;
	float g = dot(col, vec3(0.3, 0.59, 0.11));
	COLOR = vec4(mix(vec3(g), col, 0.35 + 0.65 * dim) * dim, 1.0);
}"""
const PUSH = 14.0 # degrees of extra field of view at the start

var shot:TextureRect
var t:float = 0.0
var time:float = TIME
var snap:bool = false
var settle:float = 0.0
var blur:ColorRect = null
var sfx:AudioStreamPlayer = null
var cam:Camera = null
var base_fov:float = 70.0
var steady:int = 0 # smooth frames since the run's scene came up (its first frames hitch while it builds)

static func start(tree:SceneTree, time:float = TIME, snap_:bool = false):
	var old = tree.root.get_node_or_null("RRRunIntro")
	if old: old.free() # (a retry while the last one still fades)
	var img = tree.root.get_texture().get_data()
	if !(img is Image) or img.get_width() < 2: return
	img.flip_y()
	var tex = ImageTexture.new()
	tex.create_from_image(img, 0)
	var n = load("res://mods/replay/RunIntro.gd").new()
	n.name = "RRRunIntro"
	n.set_meta("tex", tex)
	n.time = time
	n.snap = snap_
	tree.root.add_child(n)

func _ready():
	layer = 100
	pause_mode = PAUSE_MODE_PROCESS
	shot = TextureRect.new()
	shot.texture = get_meta("tex")
	shot.expand = true
	shot.anchor_right = 1
	shot.anchor_bottom = 1
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if snap:
		blur = _blur_rect()
		blur.visible = false
		add_child(blur) # (under the card: it reads the run only)
	add_child(shot)

static func _blur_rect() -> ColorRect:
	var r = ColorRect.new()
	r.anchor_right = 1
	r.anchor_bottom = 1
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh = Shader.new()
	sh.code = SNAP_SHADER
	r.material = ShaderMaterial.new()
	r.material.shader = sh
	return r

# on the loading card: the snap's shader compiled and its sound made (neither may hitch the start)
static func warm(parent:Node):
	var r = _blur_rect()
	r.anchor_right = 0
	r.anchor_bottom = 0
	r.rect_size = Vector2(2, 2)
	r.modulate.a = 0.01
	parent.add_child(r)
	parent.get_tree().create_timer(0.3).connect("timeout", r, "queue_free")
	if !Engine.has_meta("rr_enter_sfx"): Engine.set_meta("rr_enter_sfx", _enter_sound())

# a soft low thump with a short whoosh that darkens as it settles (like the picture sharpening)
static func _enter_sound() -> AudioStreamSample:
	var rate = 44100
	var n = int(rate * 0.42)
	var data = PoolByteArray()
	data.resize(n * 2)
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var phase = 0.0
	var lp = 0.0
	for i in n:
		var t = float(i) / rate
		phase += TAU * (50.0 + 60.0 * exp(-t * 14.0)) / rate
		var body = sin(phase) * exp(-t * 9.0)
		lp += ((rng.randf() * 2.0 - 1.0) - lp) * (0.02 + 0.3 * exp(-t * 12.0)) # (the filter closes)
		var air = lp * exp(-t * 7.0) * 0.5
		var v = int(clamp((body * 0.8 + air) * min(1.0, t * 300.0), -1.0, 1.0) * 26000.0)
		if v < 0: v += 65536
		data[i * 2] = v & 0xff
		data[i * 2 + 1] = (v >> 8) & 0xff
	var s = AudioStreamSample.new()
	s.format = AudioStreamSample.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s

func _process(delta):
	var sc0 = get_tree().current_scene
	if steady < 2: # hold the frozen frame until the run draws smoothly, then fade (no jump after the hitch)
		var up = sc0 and sc0.has_node("Game")
		if up: settle += delta
		steady = steady + 1 if up and delta < 0.05 else 0
		if settle > 0.6: steady = 2 # (a slow machine never gets smooth frames: go anyway)
		return
	t += min(delta, 1.0 / 30.0)
	if snap:
		_snap()
		return
	var k = min(t / time, 1.0)
	var e = 1.0 - pow(1.0 - k, 3)
	shot.rect_pivot_offset = shot.rect_size / 2
	var s = 1.0 + 0.07 * e
	shot.rect_scale = Vector2(s, s)
	shot.modulate.a = 1.0 - k * k * (3.0 - 2.0 * k)
	if !cam:
		var sc = get_tree().current_scene
		var c = sc.get_node_or_null("Camera") if sc else null
		if c is Camera:
			cam = c
			base_fov = float(Rhythia.get("fov"))
	if cam and is_instance_valid(cam): cam.fov = base_fov + PUSH * (1.0 - e)
	if k >= 1.0:
		if cam and is_instance_valid(cam): cam.fov = base_fov
		queue_free()

func _snap():
	var sc = get_tree().current_scene
	var game = sc.get_node_or_null("Game") if sc else null
	if game and "black_fade" in game: # the run's own fade in from black would darken the snap: off
		if game.black_fade_target and t < 1.0:
			t = 0.0 # (its warm-up frames aren't done: wait for them)
			return
		game.black_fade = 0.0
	if !blur.visible and t < SNAP_IN:
		blur.visible = true
		if Engine.has_meta("rr_enter_sfx"):
			sfx = AudioStreamPlayer.new()
			sfx.stream = Engine.get_meta("rr_enter_sfx")
			sfx.bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
			sfx.volume_db = -11.0
			add_child(sfx)
			sfx.play()
	shot.modulate.a = max(0.0, 1.0 - t / 0.08) # (the card is gone in a blink)
	var k = min(t / SNAP_IN, 1.0)
	var e = 1.0 - pow(1.0 - k, 3)
	blur.material.set_shader_param("amount", 0.28 * (1.0 - e))
	blur.material.set_shader_param("zoom", 1.3 - 0.3 * e)
	blur.material.set_shader_param("dim", 0.4 + 0.6 * e)
	if k >= 1.0:
		blur.visible = false
		shot.visible = false
		if !sfx or !sfx.playing: queue_free()
