extends CanvasLayer
# Loading screen -> run without a black screen: songload freezes its last frame (map card over the
# blurred cover) into this layer on the root, then switches to the run. The frozen frame fades out
# and drifts towards the viewer while the game camera eases in from a wider view, so the playfield
# grows into place under it. Frees itself when done.

const TIME = 0.85
const PUSH = 14.0 # degrees of extra field of view at the start

var shot:TextureRect
var t:float = 0.0
var cam:Camera = null
var base_fov:float = 70.0
var steady:int = 0 # smooth frames since the run's scene came up (its first frames hitch while it builds)

static func start(tree:SceneTree):
	var img = tree.root.get_texture().get_data()
	if !(img is Image) or img.get_width() < 2: return
	img.flip_y()
	var tex = ImageTexture.new()
	tex.create_from_image(img, 0)
	var n = load("res://mods/replay/RunIntro.gd").new()
	n.name = "RRRunIntro"
	n.set_meta("tex", tex)
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
	add_child(shot)

func _process(delta):
	var sc0 = get_tree().current_scene
	if steady < 2: # hold the frozen frame until the run draws smoothly, then fade (no jump after the hitch)
		steady = steady + 1 if sc0 and sc0.has_node("Game") and delta < 0.05 else 0
		return
	t += min(delta, 1.0 / 30.0)
	var k = min(t / TIME, 1.0)
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
