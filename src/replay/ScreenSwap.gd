extends CanvasLayer
# Screen changes without black (personal build): the last frame of the screen you leave is frozen on
# a layer over the root, the scene changes under it, and the frozen frame holds until the new screen
# draws smoothly (its first frames hitch while it builds), then moves away:
#   "back"    - shrinks and fades (Esc on the loading card)
#   "forward" - grows past the camera and fades (run -> results)
# Through menuload (the black loader between a run and the menu) its fades are skipped, so the menu
# comes up as soon as it is loaded. Frees itself when done.

const TIME = {"back": 0.42, "forward": 0.55}
const MAX_HOLD = 6.0  # (still loading: the frozen frame waits for the next screen)
const MAX_SETTLE = 0.6 # s it waits for smooth frames once the next screen is up (a slow machine never gets them)

var shot:TextureRect
var style:String = "back"
var from:String = ""
var t:float = 0.0
var held:float = 0.0
var steady:int = 0
var settle:float = 0.0

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
		tree.root.add_child(n)
	tree.change_scene(scene)

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

func _process(delta):
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
	shot.rect_scale = Vector2(s, s)
	shot.modulate.a = 1.0 - k * k * (3.0 - 2.0 * k)
	if k >= 1.0:
		queue_free()
