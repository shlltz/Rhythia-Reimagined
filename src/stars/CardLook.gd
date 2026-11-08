extends Control
# Map list card look (personal build), drawn over the card's cover: a difficulty accent bar on the
# left edge, a hairline frame, and a tint for cards without a cover. Hover: a light sheen from the
# left, the accent widens, the frame and the cover brighten, the card slides out a little - eased
# in ~0.12 s.
# Cheap: one draw call set per card, redrawn only while the hover eases (no per-frame work at rest,
# no shader uniforms per card; the cover material is shared - v3MapList._rr_card_look).

var col:Color = Color(1, 1, 1)   # the map's difficulty colour (set before it's added)
var card:Control
var cover:CanvasItem
var hover:float = 0.0
var target:float = 0.0
const SLIDE = 14.0

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	anchor_right = 1
	anchor_bottom = 1
	card = get_parent()
	cover = card.get_node_or_null("Cover")
	if cover and !cover.visible: cover = null
	var sel = card.get_node_or_null("Select")
	if sel:
		sel.connect("mouse_entered", self, "_hover", [true])
		sel.connect("mouse_exited", self, "_hover", [false])
	set_process(false)
	_apply()

func _hover(on:bool):
	target = 1.0 if on else 0.0
	set_process(true)

func _process(delta):
	hover += (target - hover) * (1.0 - exp(-delta * 22.0))
	if abs(target - hover) < 0.01:
		hover = target
		set_process(false)
	_apply()
	update()
	# the card slides out a little to the left (the list places it: v3MapList._rr_place)
	card.set_meta("rr_hx", SLIDE * hover)
	var list = card.get_parent()
	if list and list.has_method("_rr_place"): list._rr_place()

func _apply():
	if cover: cover.modulate.a = 0.62 + 0.38 * hover

func _draw():
	var s = rect_size
	var h = hover
	var clear = Color(col.r, col.g, col.b, 0.0)
	if !cover: # no cover: a faint tint of the difficulty colour from the right
		_band(s.x * 0.35, s.x, s.y, clear, Color(col.r, col.g, col.b, 0.16 + 0.08 * h))
	if h > 0.01: # hover sheen from the left edge, a light frame
		_band(0.0, s.x * 0.8, s.y, Color(1, 1, 1, 0.18 * h), Color(1, 1, 1, 0.0))
		draw_rect(Rect2(Vector2(1, 1), s - Vector2(2, 2)), Color(1, 1, 1, 0.7 * h), false, 2.0)
	else:
		draw_rect(Rect2(0, s.y - 1, s.x, 1), Color(1, 1, 1, 0.06)) # (a hairline between cards)
	draw_rect(Rect2(0, 0, 4.0 + 4.0 * h, s.y), Color(col.r, col.g, col.b, 0.9 + 0.1 * h))

# a horizontal gradient band (left colour a -> right colour b)
func _band(x0:float, x1:float, hgt:float, a:Color, b:Color):
	draw_polygon(PoolVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, hgt), Vector2(x0, hgt)]), PoolColorArray([a, b, b, a]))
