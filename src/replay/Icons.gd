extends Reference
# Icons from Flaticon UIcons (solid rounded, "Uicons by Flaticon", free with credit - see
# icons/Flaticon-license.txt). The icon font is packed raw and drawn at any size; Glyph is a
# Control that draws one icon centred in its rect.

const FONT_FILE = "res://mods/replay/icons/uicons-solid-rounded.woff"
const CODES = {
	"play": 0xfa7f, "pause": 0xf9fc, "stop": 0xfcd2, "settings": 0xfbac, "film": 0xf66d,
	"cloud-download": 0xf45c, "settings-sliders": 0xfbab, "heart": 0xf794, "square-plus": 0xfc99,
	"language": 0xf85b, "power": 0xfaa8, "search": 0xfb98, "menu-dots": 0xf918, "users": 0xfe7e,
	"music-note": 0xf987, "info": 0xf7ff, "star": 0xfcc1, "folder": 0xf6ac, "time-past": 0xfd82,
	"rewind": 0xfb31, "forward": 0xf6b9, "step-backward": 0xfcc9, "step-forward": 0xfcca, "minus": 0xf93e,
	"plus": 0xfa8c, "cross": 0xf4ed, "eye-crossed": 0xf5e9, "eye": 0xf5eb,
}
# sidebar button name (lower case) -> icon
const SIDEBAR = {
	"results": "play", "play": "play", "settings": "settings", "replays": "film", "browse": "cloud-download",
	"customize": "settings-sliders", "favorites": "heart", "favourites": "heart", "content": "square-plus",
	"contentmgr": "square-plus", "import": "square-plus", "language": "language", "lang": "language",
	"quit": "power", "exit": "power", "credits": "users",
}

static func available() -> bool:
	return File.new().file_exists(FONT_FILE)

static func font(px:int) -> DynamicFont:
	var k = "rr_icons_%d" % px
	if Engine.has_meta(k): return Engine.get_meta(k)
	var d = DynamicFontData.new()
	d.font_path = FONT_FILE
	var f = DynamicFont.new()
	f.font_data = d
	f.size = px
	Engine.set_meta(k, f)
	return f

static func has(n:String) -> bool:
	return CODES.has(n)

# icon `n` centred in `r`, sized to fit
static func draw(ci:CanvasItem, n:String, r:Rect2, col:Color = Color(1, 1, 1)):
	if !CODES.has(n) or !available(): return
	var px = int(max(4.0, min(r.size.x, r.size.y)))
	var f = font(px)
	var ch = char(CODES[n])
	var sz = f.get_string_size(ch)
	var pos = r.position + Vector2((r.size.x - sz.x) / 2, (r.size.y - f.get_height()) / 2 + f.get_ascent())
	ci.draw_string(f, pos.round(), ch, col)

class Glyph extends Control:
	var icon:String = ""
	var color:Color = Color(1, 1, 1)
	var fill:float = 1.0 # share of the rect the icon fills
	var lib = null

	func _init(n:String = "", f:float = 1.0):
		icon = n
		fill = f
		mouse_filter = MOUSE_FILTER_IGNORE

	func set_icon(n:String):
		icon = n
		update()

	func _draw():
		if !lib: lib = load("res://mods/replay/Icons.gd")
		var s = rect_size * fill
		lib.draw(self, icon, Rect2((rect_size - s) / 2, s), color)
