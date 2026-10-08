extends Button
# S---- speed button (Rhythia-reimagined), left of the stock <<< button: the reverse of S++++
# (x1.45), so x1/1.45 = 0.69. The game has no level for it, so it runs on the stock Custom speed
# (68.97 %): scores, replays and the speed star rating all work as they do for any custom speed.
# Looks like the stock buttons: the S++++ icons flipped, lit in violet when on.

const MULTI = 1.0 / 1.45
const ICONS = "res://assets/images/modifiers/128/speed_pppp%s.png"
const LIT_HUE = 0.75 # violet (S++++ is red, <<< blue)

var c:Control # SpeedMod/C
var active:bool = false
var st_off:StyleBoxTexture
var st_on:StyleBoxTexture

static func is_slowest() -> bool:
	return Rhythia.mod_speed_level == Globals.SPEED_CUSTOM and abs(Globals.speed_multi[Globals.SPEED_CUSTOM] - MULTI) < 0.002

func _ready():
	name = "MMMM"
	focus_mode = FOCUS_NONE
	rect_min_size = Vector2(32, 32)
	hint_tooltip = "S---- (x0.69)"
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	st_off = _style("_dark", false)
	st_on = _style("_colored", true)
	var hov = _style("", false)
	add_stylebox_override("hover", hov)
	add_stylebox_override("pressed", st_on)
	add_stylebox_override("focus", StyleBoxEmpty.new())
	_paint()
	connect("pressed", self, "_pick")

# a stock S++++ icon, mirrored (and turned violet for the lit one)
func _style(kind:String, recolor:bool) -> StyleBox:
	var t = load(ICONS % kind)
	if !t: return StyleBoxEmpty.new()
	var img:Image = t.get_data()
	if img.is_compressed(): img.decompress()
	img.flip_x()
	if recolor:
		img.lock()
		for y in img.get_height():
			for x in img.get_width():
				var p = img.get_pixel(x, y)
				if p.a > 0.0 and p.s > 0.15: img.set_pixel(x, y, Color.from_hsv(LIT_HUE, p.s, p.v, p.a))
		img.unlock()
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	var sb = StyleBoxTexture.new()
	sb.texture = tex
	sb.region_rect = Rect2(Vector2(), img.get_size())
	return sb

func _pick():
	var cs = c.get_node_or_null("CustomSpeed")
	var cb = c.get_node_or_null("Custom")
	if !cs or !cb: return
	cs.value = stepify(MULTI * 100.0, 0.01)
	if cb.pressed: cb.emit_signal("toggled", true) # already on custom: apply the new value
	else: cb.pressed = true

func _paint():
	add_stylebox_override("normal", st_on if active else st_off)

func _process(_d):
	var a = is_slowest()
	if a != active:
		active = a
		_paint()
