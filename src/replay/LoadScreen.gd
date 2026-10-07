extends Control
# osu!lazer-style map loading screen, added by the songload.gd override:
# blurred + dimmed cover in the background, a centred card with cover, title,
# mapper, difficulty, star rating and active mods, plus a spinner and status line.

const C_CARD = Color(0.067, 0.067, 0.078, 0.92)
const C_LINE = Color("#26262c")
const C_TEXT = Color("#ececf0")
const C_MUTED = Color("#8d8d97")
const UI_FONT = "res://assets/font/Lato/Lato-Regular.ttf"
const PLACEHOLDER = "res://assets/images/ui/placeholder_dark.jpg"
const STAR_BADGE = "res://mods/stars/StarBadge.gd"
const CARD_SIZE = Vector2(780, 220)
const CARD_RAISE = 20.0 # card sits a little above centre, spinner + status below it
const INTRO_TIME = 0.45
const BLUR_SHADER = """
shader_type canvas_item;
uniform float radius = 0.012;
void fragment() {
	vec4 c = vec4(0.0);
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			c += texture(TEXTURE, UV + vec2(float(x), float(y)) * radius / 3.0);
		}
	}
	COLOR = c / 49.0;
}
"""
const MOD_NAMES = [
	["mod_nofail", "No Fail"], ["mod_sudden_death", "Sudden Death"], ["mod_extra_energy", "Extra Energy"],
	["mod_no_regen", "No Regen"], ["mod_mirror_x", "Mirror X"], ["mod_mirror_y", "Mirror Y"],
	["mod_ghost", "Ghost"], ["mod_nearsighted", "Nearsighted"], ["mod_chaos", "Chaos"],
	["mod_earthquake", "Earthquake"], ["mod_flashlight", "Flashlight"], ["mod_hardrock", "Hard Rock"],
]

var bg:TextureRect
var card:Panel
var cover:TextureRect
var overline:Label
var title:Label
var mapper:Label
var difficulty:Label
var stars:Control = null
var mods:Label
var status:Label
var spinner:Control
var t:float = 0.0
var spin:float = 0.0

func _init():
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_IGNORE
	_build()

func font(size:int) -> Font:
	var data = load(UI_FONT) if ResourceLoader.exists(UI_FONT) else null
	if !(data is DynamicFontData): return get_font("font")
	var f = DynamicFont.new()
	f.font_data = data
	f.size = size
	return f

func new_label(size:int, col:Color, parent:Control) -> Label:
	var l = Label.new()
	l.add_font_override("font", font(size))
	l.add_color_override("font_color", col)
	l.clip_text = true
	l.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func place(c:Control, x:float, y:float, w:float, h:float):
	c.rect_position = Vector2(x, y)
	c.rect_size = Vector2(w, h)

# centre-anchored control, offsets relative to the screen centre
func centred(c:Control, l:float, t_:float, r:float, b:float):
	c.anchor_left = 0.5; c.anchor_right = 0.5; c.anchor_top = 0.5; c.anchor_bottom = 0.5
	c.margin_left = l; c.margin_top = t_; c.margin_right = r; c.margin_bottom = b

func _build():
	bg = TextureRect.new()
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.expand = true
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.self_modulate = Color(0.32, 0.32, 0.34)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = BLUR_SHADER
	mat.shader = sh
	bg.material = mat
	add_child(bg)
	var dim = ColorRect.new()
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	dim.color = Color(0, 0, 0, 0.35)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)

	card = Panel.new()
	var box = StyleBoxFlat.new()
	box.bg_color = C_CARD
	box.border_color = C_LINE
	box.set_border_width_all(1)
	box.shadow_color = Color(0, 0, 0, 0.6)
	box.shadow_size = 30
	card.add_stylebox_override("panel", box)
	centred(card, -CARD_SIZE.x / 2, -CARD_SIZE.y / 2 - CARD_RAISE, CARD_SIZE.x / 2, CARD_SIZE.y / 2 - CARD_RAISE)
	card.rect_pivot_offset = CARD_SIZE / 2
	card.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(card)

	cover = TextureRect.new()
	cover.expand = true
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.mouse_filter = MOUSE_FILTER_IGNORE
	place(cover, 1, 1, CARD_SIZE.y - 2, CARD_SIZE.y - 2)
	card.add_child(cover)

	var x = CARD_SIZE.y + 28
	var w = CARD_SIZE.x - x - 28
	overline = new_label(12, C_MUTED, card); place(overline, x, 22, w, 16)
	title = new_label(28, C_TEXT, card); place(title, x, 42, w, 38)
	mapper = new_label(15, C_MUTED, card); place(mapper, x, 84, w, 22)
	difficulty = new_label(17, C_TEXT, card); place(difficulty, x, 128, w, 24)
	mods = new_label(13, C_MUTED, card); place(mods, x, 176, w, 20)

	var below = CARD_SIZE.y / 2 - CARD_RAISE + 34
	spinner = Control.new()
	spinner.mouse_filter = MOUSE_FILTER_IGNORE
	spinner.connect("draw", self, "_draw_spinner")
	centred(spinner, -CARD_SIZE.x / 2, below, -CARD_SIZE.x / 2 + 20, below + 20)
	add_child(spinner)
	status = new_label(14, C_MUTED, self)
	status.valign = Label.VALIGN_CENTER
	centred(status, -CARD_SIZE.x / 2 + 32, below, CARD_SIZE.x / 2, below + 20)
	set_status("Loading")
	modulate.a = 0.0

# fill the card from a Song; called again after a replay finished loading
func show_song(song, is_replay:bool = false):
	if song == null: return
	var placeholder = load(PLACEHOLDER) if ResourceLoader.exists(PLACEHOLDER) else null
	cover.texture = song.cover if song.has_cover else placeholder
	bg.texture = song.cover if song.has_cover else null
	overline.text = "LOADING REPLAY" if is_replay else "NOW LOADING"
	title.text = song.name
	mapper.text = "mapped by " + str(song.creator)
	difficulty.text = str(song.custom_data.get("difficulty_name", Globals.difficulty_names.get(song.difficulty, "")))
	difficulty.add_color_override("font_color", Globals.difficulty_colors.get(song.difficulty, C_TEXT))
	var speed = 1.0
	if Rhythia.mod_speed_level != Globals.SPEED_NORMAL:
		speed = Globals.speed_multi[Rhythia.mod_speed_level]
	_show_stars(song, speed)
	var parts = []
	if !is_equal_approx(speed, 1.0): parts.append("%sx speed" % str(stepify(speed, 0.01)))
	for m in MOD_NAMES:
		if Rhythia.get(m[0]): parts.append(m[1])
	mods.text = PoolStringArray(parts).join("  /  ") if parts.size() > 0 else "No mods"

# star rating from the stars mod, when it is installed
func _show_stars(song, speed:float):
	if !ResourceLoader.exists(STAR_BADGE): return
	if stars == null:
		stars = Control.new()
		stars.set_script(load(STAR_BADGE))
		stars.align_left = true
		card.add_child(stars)
	var dw = difficulty.get_font("font").get_string_size(difficulty.text).x
	place(stars, difficulty.rect_position.x + dw + 16, difficulty.rect_position.y, 200, 24)
	stars.set_song(song, font(15), speed)

func set_status(text:String):
	status.text = text

func _process(delta):
	t += min(delta, 1.0 / 30.0) # capped so a load hitch doesn't skip the intro
	var e = 1.0 - pow(1.0 - min(t / INTRO_TIME, 1.0), 3)
	modulate.a = e
	var s = 0.94 + 0.06 * e
	card.rect_scale = Vector2(s, s)
	spin = fmod(spin + delta * 6.0, TAU)
	spinner.update()

func _draw_spinner():
	var c = spinner.rect_size / 2
	var r = min(c.x, c.y) - 2
	spinner.draw_arc(c, r, 0, TAU, 32, Color(1, 1, 1, 0.12), 2.0, true)
	spinner.draw_arc(c, r, spin, spin + PI * 0.6, 16, C_TEXT, 2.0, true)
