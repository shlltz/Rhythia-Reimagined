extends Control
# Map list card look (personal build), drawn over the card's cover: a difficulty accent bar on the
# left edge, a hairline frame, and a tint for cards without a cover. Hover: a light sheen from the
# left, the accent widens, the frame and the cover brighten (drawing only: cards passing under a
# resting mouse while scrolling cost no layout). The selected card stands out: it grows out to the
# left and stays out, its cover at full brightness with a brighter sheen (the frame / brackets / edge
# strip: MapFocus.gd). Both ease in ~0.12 s.
# Cheap: redrawn only while hover / selection ease (no per-frame work at rest, no shader uniforms
# per card; the cover material is shared - v3MapList._rr_card_look). The list leaves SEL_SLIDE of
# room on the left so the grown card isn't clipped (v3MapList._rr_room).

const SEL_SLIDE = 26.0

var col:Color = Color(1, 1, 1)   # the map's difficulty colour (set before it's added)
var card:Control
var cover:CanvasItem
var hover:float = 0.0
var target:float = 0.0
var sel:float = 0.0
var sel_target:float = 0.0

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	anchor_right = 1
	anchor_bottom = 1
	card = get_parent()
	cover = card.get_node_or_null("Cover")
	if cover and !cover.visible: cover = null
	var b = card.get_node_or_null("Select")
	if b:
		b.connect("mouse_entered", self, "_hover", [true])
		b.connect("mouse_exited", self, "_hover", [false])
	Rhythia.connect("selected_song_changed", self, "_selected")
	set_process(false)
	sel_target = 1.0 if _is_sel() else 0.0
	sel = sel_target # (a card made for the selected map starts out already)
	_apply()

func _exit_tree():
	if Rhythia.is_connected("selected_song_changed", self, "_selected"): Rhythia.disconnect("selected_song_changed", self, "_selected")

func _is_sel() -> bool:
	return is_instance_valid(card) and "song" in card and card.song != null and card.song == Rhythia.selected_song

func _hover(on:bool):
	target = 1.0 if on else 0.0
	set_process(true)

func _selected(_s = null):
	var t = 1.0 if _is_sel() else 0.0
	if t != sel_target:
		sel_target = t
		set_process(true)

func _process(delta):
	var a = 1.0 - exp(-delta * 22.0)
	hover += (target - hover) * a
	var moving_sel = sel != sel_target
	sel += (sel_target - sel) * a
	if abs(target - hover) < 0.01 and abs(sel_target - sel) < 0.01:
		hover = target
		sel = sel_target
		set_process(false)
	_apply()
	update()
	if moving_sel:
		var list = card.get_parent()
		if list and list.has_method("_rr_place"): list._rr_place()

func _apply():
	if cover: cover.modulate.a = min(1.0, 0.55 + 0.35 * hover + 0.45 * sel)
	# the selected card grows out to the left (the list places it: v3MapList._rr_place)
	card.set_meta("rr_hx", SEL_SLIDE * sel)

func _draw():
	var s = rect_size
	var h = hover
	var clear = Color(col.r, col.g, col.b, 0.0)
	if !cover: # no cover: a faint tint of the difficulty colour from the right
		_band(s.x * 0.35, s.x, s.y, clear, Color(col.r, col.g, col.b, 0.16 + 0.08 * h + 0.1 * sel))
	var lit = max(h, sel)
	if lit > 0.01: # sheen from the left edge
		_band(0.0, s.x * 0.8, s.y, Color(1, 1, 1, 0.16 * h + 0.2 * sel), Color(1, 1, 1, 0.0))
	if h > 0.01 and sel < 0.99: # hover frame (the selected card has MapFocus's)
		draw_rect(Rect2(Vector2(1, 1), s - Vector2(2, 2)), Color(1, 1, 1, 0.7 * h * (1.0 - sel)), false, 2.0)
	if lit < 0.99:
		draw_rect(Rect2(0, s.y - 1, s.x, 1), Color(1, 1, 1, 0.06 * (1.0 - lit))) # (a hairline between cards)
	draw_rect(Rect2(0, 0, 4.0 + 4.0 * h, s.y), Color(col.r, col.g, col.b, (0.9 + 0.1 * h) * (1.0 - sel)))

# a horizontal gradient band (left colour a -> right colour b)
func _band(x0:float, x1:float, hgt:float, a:Color, b:Color):
	draw_polygon(PoolVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, hgt), Vector2(x0, hgt)]), PoolColorArray([a, b, b, a]))
