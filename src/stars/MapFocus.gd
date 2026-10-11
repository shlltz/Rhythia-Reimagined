extends Control
# Selected-map focus on a map list card (personal build, Look.mono): white edge strip, thin outline
# and corner brackets; a short white flash when the card becomes the selection. Redraws only when
# the selection changes (and during the flash), never every frame.

var card:Control
var on:bool = false
var flash:float = 0.0

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	anchor_right = 1
	anchor_bottom = 1
	card = get_parent()
	set_process(false)
	Rhythia.connect("selected_song_changed", self, "_changed")
	_changed()

func _exit_tree():
	if Rhythia.is_connected("selected_song_changed", self, "_changed"): Rhythia.disconnect("selected_song_changed", self, "_changed")

func _changed(_s = null):
	var now = is_instance_valid(card) and "song" in card and card.song != null and card.song == Rhythia.selected_song
	if now and !on:
		flash = 1.0
		set_process(true)
	on = now
	update()

func _process(delta):
	flash = max(0.0, flash - delta / 0.18)
	update()
	if flash <= 0.0: set_process(false)

func _draw():
	if !on: return
	var r = Rect2(Vector2(), rect_size)
	if flash > 0.0: draw_rect(r, Color(1, 1, 1, 0.22 * flash))
	draw_rect(Rect2(0, 0, 4, r.size.y), Color(1, 1, 1, 0.95))
	draw_rect(r.grow(-1), Color(1, 1, 1, 0.55), false, 1.0)
	load("res://mods/replay/Look.gd").brackets(self, r.grow(-5), 12.0, Color(1, 1, 1, 0.9), 2.0)
