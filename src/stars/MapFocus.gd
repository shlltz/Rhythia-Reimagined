extends Control
# Selected-map focus on a map list card (personal build, Look.mono): white edge strip, thin outline
# and corner brackets; a short white flash when the card becomes the selection. Redraws only when
# the selection changes (and during the flash), never every frame.

var card:Control
var on:bool = false
var flash:float = 0.0
var tier:int = -1 # danger class of the map (Look.danger), -1 = rating not in yet

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
	if on and "song" in card:
		var sc = load("res://mods/stars/StarCache.gd").get_instance(get_tree())
		var v = sc.get_stars(card.song) if sc else -1.0
		tier = load("res://mods/replay/Look.gd").danger(v)[2] if v >= 0.0 else -1
	update()

func _process(delta):
	flash = max(0.0, flash - delta / 0.18)
	update()
	if flash <= 0.0: set_process(false)

func _draw():
	if !on: return
	var r = Rect2(Vector2(), rect_size)
	var Look = load("res://mods/replay/Look.gd")
	var c = Look.hot() # red-ish marks follow the red setting; SEVERE / EXTREME maps get a stronger red frame
	if tier >= 3: c = Look.danger_col(tier)
	if flash > 0.0: draw_rect(r, Color(c.r, c.g, c.b, 0.22 * flash))
	draw_rect(Rect2(0, 0, 4, r.size.y), Color(c.r, c.g, c.b, 0.95))
	draw_rect(r.grow(-1), Color(c.r, c.g, c.b, 0.55), false, 1.0)
	Look.brackets(self, r.grow(-5), 12.0 + (4.0 if tier == 4 and Look.red() > 0.0 else 0.0), Color(c.r, c.g, c.b, 0.9), 2.0)
