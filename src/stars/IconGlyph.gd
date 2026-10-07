extends Control
# Draws a small icon over a map-page button whose own text is hidden: "heart" (Favorite: filled
# when favourited), "play" (preview music: play / stop) or "menu" (map actions: three dots).
# State comes from the game's own button text ("Favorited!", "Stop Playing"), so the stock
# scripts keep working untouched.

var kind:String = "menu"
var on:bool = false

func _init(k:String = "menu"):
	kind = k

func _ready():
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_IGNORE

func _process(_d):
	var b = get_parent()
	var v = false
	if b is Button:
		if kind == "heart": v = b.text.findn("favorited") != -1
		elif kind == "play": v = b.text.findn("stop") != -1
	if v != on:
		on = v
		update()

func _draw():
	var c = rect_size / 2
	var b = get_parent()
	var col = Color(1, 1, 1, 0.4 if (b is BaseButton and b.disabled) else 0.9)
	var I = load("res://mods/replay/Icons.gd") if ResourceLoader.exists("res://mods/replay/Icons.gd") else null
	if I and I.available(): # Flaticon icons
		var r = Rect2(c - Vector2(11, 11), Vector2(22, 22))
		match kind:
			"heart": I.draw(self, "heart", r, Color("#ff5c8a") if on else col)
			"play": I.draw(self, "stop" if on else "play", r, Color("#8ad8ff") if on else col)
			_: I.draw(self, "menu-dots", r, col)
		return
	match kind:
		"heart":
			var pts = PoolVector2Array()
			for i in 40:
				var t = i * TAU / 40
				pts.append(c + Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) * 0.62)
			if on: draw_colored_polygon(pts, Color("#ff5c8a"))
			else:
				pts.append(pts[0])
				draw_polyline(pts, col, 2.0, true)
		"play":
			if on: draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), Color("#8ad8ff"))
			else: draw_colored_polygon(PoolVector2Array([c + Vector2(-6, -9), c + Vector2(10, 0), c + Vector2(-6, 9)]), col)
		_:
			for dx in [-8, 0, 8]: draw_circle(c + Vector2(dx, 0), 2.4, col)
