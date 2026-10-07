extends CanvasLayer
# Pass effects: once every note is done on a pass, a green glow
# fades in around all four screen edges; when the map ends on a pass, the last frame zooms in
# and fades to black before the results screen (instead of the plain black fade).
# Added to Game by Game._ready when this file exists; Game.end() calls zoom_in().

const GREEN = Color(0.3, 1.0, 0.45)
const WIDTH = 0.12       # glow depth, share of the screen height
const ZOOM_TIME = 0.6

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

# freeze the last frame, zoom into it while fading to black; Game.end() yields on this
func zoom_in():
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	var tex = ImageTexture.new()
	tex.create_from_image(img, 0)
	var shot = TextureRect.new()
	shot.texture = tex
	shot.expand = true
	shot.anchor_right = 1
	shot.anchor_bottom = 1
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var black = ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.anchor_right = 1
	black.anchor_bottom = 1
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shot)
	add_child(black)
	yield(get_tree(), "idle_frame") # sizes settle
	shot.rect_pivot_offset = shot.rect_size / 2
	var k = 0.0
	while k < 1.0:
		yield(get_tree(), "idle_frame")
		k = min(1.0, k + get_process_delta_time() / ZOOM_TIME)
		var e = k * k * (3.0 - 2.0 * k)
		var z = 1.0 + 0.6 * e
		shot.rect_scale = Vector2(z, z)
		black.color.a = clamp((k - 0.35) / 0.65, 0.0, 1.0)
