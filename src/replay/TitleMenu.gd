extends CanvasLayer
# osu!-style main menu in front of map selection: a big logo that beats with the menu music,
# a ring of spectrum bars around it, light rain in the background and (after clicking
# the logo) cards sliding out from behind it: Play / Settings / Exit. Shown on startup and when
# Esc is pressed on map selection (menu2.gd). Sounds come from the osuskin mod if installed.

const UIAnim = preload("res://mods/replay/UIAnim.gd")
const OsuSfx = preload("res://mods/replay/OsuSfx.gd")
const LOGO = 520.0
const SHIFT = 300.0            # how far the logo moves left when the cards open
const CARD_W = 440.0
const CARD_H = 78.0
const CARD_GAP = 12.0
const SLIDE_IN = 0.55          # seconds per card (expo out)
const SLIDE_OUT = 0.22
const STAGGER = 0.07
const ITEMS = [
	["Play", "choose a map", Color("#8a6cff"), "menu-play-click.mp3", "play"],
	["Settings", "game, audio, visuals", Color("#5cc98a"), "menu-options-click.mp3", "settings"],
	["Browse", "download new maps", Color("#4db8ff"), "", "browse"], # game's own click (menu2 Press); browser mod only
	["Exit", "see you next time", Color("#ff6b6b"), "menu-exit-click.mp3", "exit"],
]

# 3 layers of falling streaks: each screen column (slanted) holds one drop with its own speed / phase
const RAIN_SHADER = """
shader_type canvas_item;
uniform float strength = 0.22;
uniform vec2 offset = vec2(0.0);
float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }
void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 uv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + offset; // y = 0 at the top (SCREEN_UV starts at the bottom)
	float a = 0.0;
	for (int l = 0; l < 3; l++) {
		float fl = float(l);
		float cols = 70.0 + fl * 55.0;                 // farther layers: more, thinner, slower drops
		float x = (uv.x * aspect + uv.y * 0.18) * cols / aspect;
		float c = floor(x);
		float r = hash(c + fl * 71.3);
		if (r < 0.45) continue;                        // most columns are dry
		float speed = (0.55 + r * 0.6) * (1.0 - fl * 0.25);
		float head = fract(TIME * speed + hash(c * 3.1 + fl)) * 1.4 - 0.2;
		float len = 0.05 + 0.07 * r;
		float d = head - uv.y;
		float body = step(0.0, d) * (1.0 - smoothstep(0.0, len, d));
		float w = 1.0 - smoothstep(0.0, 0.07 + fl * 0.03, abs(fract(x) - 0.5));
		a += body * w * (1.0 - fl * 0.3);
	}
	COLOR = vec4(0.8, 0.88, 1.0, clamp(a, 0.0, 1.0) * strength);
}
"""

# snow: 3 layers of hashed flakes in a grid that drifts down and sways
const SNOW_SHADER = """
shader_type canvas_item;
uniform float strength = 0.55;
uniform vec2 offset = vec2(0.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 uv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + offset; // y = 0 at the top
	float a = 0.0;
	for (int l = 0; l < 3; l++) {
		float fl = float(l);
		float n = 9.0 + fl * 7.0;
		vec2 p = vec2(uv.x * aspect, uv.y) * n;
		p.y -= TIME * (0.32 - fl * 0.07) * n * 0.25;
		p.x += sin(TIME * 0.6 + floor(p.y) * 1.7 + fl) * 0.3;
		vec2 c = floor(p);
		vec2 f = fract(p);
		float r = hash(c + fl * 17.0);
		if (r < 0.55) continue;
		vec2 pos = vec2(hash(c + 3.1), hash(c + 7.7)) * 0.6 + 0.2;
		float size = (0.05 + 0.06 * r) * (1.0 - fl * 0.25);
		a += (1.0 - smoothstep(size * 0.4, size, length(f - pos))) * (1.0 - fl * 0.3);
	}
	COLOR = vec4(1.0, 1.0, 1.0, clamp(a, 0.0, 1.0) * strength);
}
"""

var menu:Node
var sfx:Node
var root:Control
var topo:ColorRect
var logo:TextureRect
var ring:Control
var cards:Array = []
var items:Array = []           # ITEMS minus Browse when the browser mod is missing
var tilt:float = 0.0           # the icon is drawn tilted; turning by this makes it upright
var open_amt:float = 0.0       # logo shift / turn, 0..1 (smoothed)
var expanded:bool = false
var anim_t:float = 10.0        # seconds since the cards were told to open / close
var beat:float = 0.0
# beat detection (kicks in the menu music): punch jumps to 1 on a kick and decays fast;
# it drives the logo hit, the ring, a small screen bump, the glow and a wave down the cards
var punch:float = 0.0
var since_beat:float = 10.0
var bass_avg:float = 0.0
var bass_prev:float = 0.0
var beat_cd:float = 0.0
var glow:Control
const R = preload("res://mods/replay/Ring.gd")
var closing:bool = false
var parallax:Vector2 = Vector2.ZERO
var covered:Array = []
var hint:Label
var fonts:Dictionary = {}

func _ready():
	layer = 15
	menu = get_parent()
	sfx = OsuSfx.inst(get_tree())
	root = Control.new()
	root.anchor_right = 1
	root.anchor_bottom = 1
	root.mouse_filter = Control.MOUSE_FILTER_STOP # nothing behind gets clicks
	if ResourceLoader.exists("res://uitheme.tres"): root.theme = load("res://uitheme.tres")
	add_child(root)
	var dim = ColorRect.new()
	dim.color = Color(0.015, 0.015, 0.02, 0.94)
	dim.anchor_right = 1; dim.anchor_bottom = 1
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	# background effect (Customize > Interface): rain / snow / wavey (topographic)
	topo = ColorRect.new()
	topo.anchor_right = 1; topo.anchor_bottom = 1
	topo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	topo.material = ShaderMaterial.new()
	topo.material.shader = Shader.new()
	root.add_child(topo)
	apply_bg()

	for it in ITEMS:
		if it[4] != "browse" or ResourceLoader.exists("res://mods/browser/MapBrowser.gd"): items.append(it)
	for i in items.size():
		var c = Card.new()
		c.title = items[i][0]
		c.sub = items[i][1]
		c.col = items[i][2]
		c.font_big = _font(28)
		c.font_small = _font(15)
		c.rect_size = Vector2(CARD_W, CARD_H)
		c.connect("mouse_entered", sfx, "play", ["click-short.ogg", -10.0])
		c.connect("pressed", self, "_choose", [i])
		root.add_child(c)
		cards.append(c)

	glow = Control.new() # soft light behind the logo that flashes on the beat
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.connect("draw", self, "_draw_glow")
	root.add_child(glow)
	root.move_child(glow, topo.get_index() + 1)
	ring = Control.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.connect("draw", self, "_draw_ring")
	root.add_child(ring)
	root.move_child(ring, glow.get_index() + 1) # ring + glow behind the cards
	logo = TextureRect.new()
	logo.texture = load("res://assets/images/branding/icon.png")
	logo.expand = true
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.rect_size = Vector2(LOGO, LOGO)
	logo.rect_pivot_offset = Vector2(LOGO, LOGO) / 2
	logo.connect("gui_input", self, "_logo_input")
	tilt = _measure_tilt(logo.texture)
	root.add_child(logo)
	_logo_fx()
	hint = Label.new()
	hint.text = "click the logo"
	hint.align = Label.ALIGN_CENTER
	hint.anchor_left = 0; hint.anchor_right = 1; hint.anchor_top = 1; hint.anchor_bottom = 1
	hint.margin_top = -90; hint.margin_bottom = -60
	hint.modulate = Color(1, 1, 1, 0.45)
	root.add_child(hint)
	var brand = Label.new() # Rhythia-reimagined
	brand.text = "rhythia  reimagined  v@@VERSION@@"
	brand.add_font_override("font", _font(15))
	brand.align = Label.ALIGN_RIGHT
	brand.anchor_left = 1; brand.anchor_right = 1; brand.anchor_top = 1; brand.anchor_bottom = 1
	brand.margin_left = -400; brand.margin_right = -28; brand.margin_top = -46; brand.margin_bottom = -22
	brand.modulate = Color(1, 1, 1, 0.3)
	root.add_child(brand)
	apply_skin()
	show_menu()

func _font(size:int):
	if fonts.has(size): return fonts[size]
	var base = root.get_font("font", "Label")
	var f = base
	if base is DynamicFont:
		f = base.duplicate()
		f.size = size
	fonts[size] = f
	return f

# rotation (degrees, clockwise) that makes the icon's square axis-aligned: smallest bounding box
# of its opaque pixels, sampled on a 48x48 grid
static func _measure_tilt(tex:Texture) -> float:
	if !tex: return 0.0
	var img:Image = tex.get_data()
	if !img: return 0.0
	img = img.duplicate()
	if img.is_compressed(): img.decompress()
	img.resize(48, 48, Image.INTERPOLATE_BILINEAR)
	img.lock()
	var pts = []
	for y in 48:
		for x in 48:
			if img.get_pixel(x, y).a > 0.5: pts.append(Vector2(x - 24, y - 24))
	img.unlock()
	if pts.size() < 10: return 0.0
	var best = -1.0
	var best_deg = 0.0
	for k in range(-45, 45):
		var a = deg2rad(k)
		var lo = Vector2(1e9, 1e9)
		var hi = Vector2(-1e9, -1e9)
		for p in pts:
			var q = p.rotated(a)
			lo = Vector2(min(lo.x, q.x), min(lo.y, q.y))
			hi = Vector2(max(hi.x, q.x), max(hi.y, q.y))
		var area = (hi.x - lo.x) * (hi.y - lo.y)
		if best < 0 or area < best:
			best = area
			best_deg = k
	return best_deg

# ------------------------------------------------------------------ open / close
func show_menu():
	closing = false
	expanded = false
	open_amt = 0.0
	anim_t = 10.0
	visible = true
	_cover(true)
	sfx.play("click-short-confirm.ogg", -10.0) # soft: back on the title screen
	UIAnim.play(root, Vector2.ZERO, Vector2.ZERO, 0.0, 1.0, 0.35)
	set_process(true)
	set_process_input(true)

func _close(then:String = ""):
	if closing: return
	closing = true
	set_process_input(false)
	var t = UIAnim.play(root, Vector2.ZERO, Vector2.ZERO, 1.0, 0.0, 0.28)
	t.connect("finished", self, "_after_close", [then])

func _after_close(then:String):
	visible = false
	set_process(false)
	_cover(false)
	if then == "": # into map selection: the map cards slide in
		var ml = menu.get_node_or_null("Main/Maps/MapRegistry/S/VBoxContainer")
		if ml and ml.has_method("rr_slide_in"): ml.rr_slide_in()
	match then:
		"settings": _sidebar(1)
		"browse":
			_sidebar(0)
			menu.open_map_browser()
		_: _sidebar(0)

func apply_bg():
	var style = load("res://mods/replay/Reimagined.gd").val("title_bg")
	var m = topo.material
	match style:
		"snow": m.shader.code = SNOW_SHADER
		"waves":
			m.shader.code = load("res://mods/replay/menu2.gd").TOPO_SHADER
			m.set_shader_param("strength", 0.16)
			m.set_shader_param("speed", 0.035)
		_: m.shader.code = RAIN_SHADER

# custom logo from the Rhythia-reimagined skin folder
func apply_skin():
	var R = load("res://mods/replay/Reimagined.gd")
	var t = R.skin_tex("logo")
	logo.texture = t if t else load("res://assets/images/branding/icon.png")
	tilt = _measure_tilt(logo.texture)

func _sidebar(page:int):
	var sb = menu.get_node_or_null("Sidebar")
	if sb and sb.has_method("press"): sb.press(page, true)

# hide the menu pages underneath (their search box grabs typing, the map list the wheel)
func _cover(on:bool):
	var bar = menu.get_node_or_null("Sidebar") # no sidebar on the title screen
	var topo = menu.get_node_or_null("TopoBackground") # hidden behind our own: one full-screen shader, not two
	if topo: topo.visible = !on
	if bar:
		if on: bar.visible = false
		elif !bar.visible:
			bar.visible = true
			UIAnim.play(bar, Vector2(-bar.rect_size.x, 0), Vector2.ZERO, 0.0, 1.0, 0.35)
	if on:
		var main = menu.get_node_or_null("Main")
		if main:
			for p in main.get_children():
				if p is Control and p.visible:
					p.visible = false
					covered.append(p)
	else:
		for p in covered:
			if is_instance_valid(p): p.visible = true
		covered = []

func _exit_tree():
	_cover(false)

# ------------------------------------------------------------------ input
func _logo_input(ev):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		if expanded: _choose(0)
		else: _expand(true)

func _expand(on:bool):
	if expanded == on: return
	expanded = on
	anim_t = 0.0
	sfx.play("click-short-confirm.ogg" if on else "click-short.ogg", -8.0) # soft logo click

func _choose(i:int):
	if closing or !expanded: return
	var it = items[i]
	if it[3] != "": sfx.play(it[3], -4.0)
	if it[4] == "exit":
		closing = true
		UIAnim.play(root, Vector2.ZERO, Vector2.ZERO, 1.0, 0.0, 0.5)
		yield(get_tree().create_timer(0.55), "timeout")
		get_tree().quit()
		return
	_close(it[4])

func _input(ev):
	if !(ev is InputEventKey) or !ev.pressed or ev.echo: return
	match ev.scancode:
		KEY_ESCAPE:
			if expanded: _expand(false)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_P:
			if expanded: _choose(0)
			else: _expand(true)
		_: return
	get_tree().set_input_as_handled()

# ------------------------------------------------------------------ animation
static func _expo_out(x:float) -> float:
	return 1.0 if x >= 1.0 else 1.0 - pow(2.0, -10.0 * x)

func _card_k(i:int) -> float:
	var n = cards.size()
	if expanded: return _expo_out(clamp((anim_t - i * STAGGER) / SLIDE_IN, 0.0, 1.0))
	return 1.0 - _expo_out(clamp((anim_t - (n - 1 - i) * STAGGER * 0.5) / SLIDE_OUT, 0.0, 1.0))

func _process(delta):
	var size = root.rect_size
	if size.x <= 0: return
	anim_t += delta
	open_amt = lerp(open_amt, 1.0 if expanded else 0.0, 1.0 - exp(-delta * 9.0))
	hint.modulate.a = 0.45 * (1.0 - open_amt)
	# music energy from the menu's visualizer (low end = kick)
	var e = 0.0
	var vis = menu.get_node_or_null("AudioVisualizer")
	if vis and vis.mags.size() > 8 and vis.ceiling > 0:
		for i in 6: e += vis.mags[i]
		e = clamp(e / 6.0 / vis.ceiling, 0.0, 1.0)
	beat = max(e, beat - delta * 2.5)
	var raw = 0.0
	if vis and vis.mags.size() > 8 and vis.ceiling > 0:
		for i in 4: raw += vis.mags[i]
		raw = raw / 4.0 / vis.ceiling
	var rising = raw - bass_prev
	bass_prev = raw
	bass_avg = lerp(bass_avg, raw, 1.0 - exp(-delta * 3.0))
	beat_cd -= delta
	since_beat += delta
	if raw > bass_avg * 1.12 and rising > 0.0 and raw > 0.15 and beat_cd <= 0.0:
		punch = 1.0
		beat_cd = 0.14
		since_beat = 0.0
	punch *= exp(-delta * 8.0)
	root.rect_pivot_offset = size / 2 # the whole screen bumps a little on the kick
	var bump = 1.0 + 0.012 * punch
	root.rect_scale = Vector2(bump, bump)
	glow.rect_position = Vector2.ZERO
	glow.update()
	var m = (get_viewport().get_mouse_position() / size - Vector2(0.5, 0.5)) * 2.0
	parallax = parallax.linear_interpolate(m, 1.0 - exp(-delta * 4.0))
	topo.material.set_shader_param("offset", parallax * 0.012)
	var centre = size / 2 + Vector2(-SHIFT * open_amt, 0) - parallax * 6.0
	var s = (1.0 + beat * 0.04 + punch * 0.07) * (1.0 - 0.12 * open_amt)
	if logo.get_global_rect().has_point(get_viewport().get_mouse_position()): s *= 1.03
	logo.rect_position = centre - logo.rect_pivot_offset
	logo.rect_scale = Vector2(s, s)
	logo.rect_rotation = tilt * (1.0 - pow(1.0 - open_amt, 3))
	var n = cards.size()
	for i in n:
		var c = cards[i]
		var k = _card_k(i)
		var y = centre.y + (i - (n - 1) / 2.0) * (CARD_H + CARD_GAP)
		var x = lerp(centre.x - CARD_W * 0.35, centre.x + LOGO * 0.40, k)
		c.rect_position = Vector2(x, y - CARD_H / 2)
		c.modulate.a = clamp(k * 1.4, 0.0, 1.0)
		c.visible = k > 0.005
		c.mouse_filter = Control.MOUSE_FILTER_STOP if k > 0.9 else Control.MOUSE_FILTER_IGNORE
		var d = since_beat - i * 0.035 # the hit runs down the cards like a wave
		var pulse = exp(-d * 9.0) if d >= 0.0 else 0.0
		if abs(pulse - c.beat) > 0.002:
			c.beat = pulse
			c.update()
	ring.rect_position = centre
	ring.update()
	_logo_fx_step(delta)

func _draw_ring():
	var vis = menu.get_node_or_null("AudioVisualizer")
	if !vis or vis.mags.size() < 8 or vis.ceiling <= 0: return
	var r = LOGO / 2 * logo.rect_scale.x * 0.92
	var n = 90
	var col = Color(1, 1, 1, 0.22 + 0.3 * punch)
	for i in n:
		var k = int(float(i % (n / 2)) / (n / 2) * min(vis.mags.size(), 64))
		var v = clamp(vis.mags[k] / vis.ceiling, 0.0, 1.0)
		var a = -PI / 2 + i * TAU / n
		var d = Vector2(cos(a), sin(a))
		var c = col # bars facing the (see-through) cards fade out while they're open
		c.a *= 1.0 - open_amt * clamp((d.x - 0.15) * 2.5, 0.0, 1.0)
		if c.a > 0.005: ring.draw_line(d * r, d * (r + 6 + v * 70 * (1.0 + 0.35 * punch)), c, 4.0, true)

func _draw_glow():
	if punch < 0.01 and beat < 0.01: return
	var c = logo.rect_position + logo.rect_pivot_offset
	var r = LOGO / 2 * logo.rect_scale.x
	var a = 0.04 * beat + 0.1 * punch
	for k in 6: # stacked soft discs = a cheap radial glow
		R.disc(glow, c, r * (1.0 + 0.22 * k), Color(1, 1, 1, a * (1.0 - k / 6.0) * 0.5))

# ------------------------------------------------------------------ logo fx
# Rhythia-reimagined touch: the logo always has a slight red / blue split and glitches in short
# bursts every few seconds (and a little on strong kicks). Overlay after a BackBufferCopy, so it
# reads the logo (and ring) exactly as drawn under it.
const LOGO_FX_SHADER = """shader_type canvas_item;
uniform float power = 0.0;  // glitch burst 0..1
uniform float split = 1.5;  // constant colour split, px
uniform vec2 size = vec2(400.0, 400.0);
float hash(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	float tick = floor(TIME * 20.0);
	float band = floor(UV.y * 12.0 + hash(tick) * 3.0);
	float on = step(1.0 - power * 0.5, hash(band * 7.13 + tick));
	float shift = (hash(band * 1.7 + tick * 3.1) - 0.5) * 0.1 * on * power;
	vec2 uv = SCREEN_UV + vec2(shift * size.x * SCREEN_PIXEL_SIZE.x, 0.0);
	vec2 sp = vec2((split + (2.0 + 5.0 * on) * power) * SCREEN_PIXEL_SIZE.x, 0.0);
	vec4 c = textureLod(SCREEN_TEXTURE, uv, 0.0);
	c.r = textureLod(SCREEN_TEXTURE, uv + sp, 0.0).r;
	c.b = textureLod(SCREEN_TEXTURE, uv - sp, 0.0).b;
	float scan = 1.0 - power * 0.15 * step(0.5, fract(UV.y * size.y * 0.25));
	COLOR = vec4(c.rgb * scan, 1.0);
}"""
var logo_fx:ColorRect
var logo_glitch:float = 0.0
var logo_glitch_next:float = 2.0
var logo_glitch_left:float = 0.0

func _logo_fx():
	var bb = BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	bb.name = "FxCopy"
	logo.add_child(bb)
	logo_fx = ColorRect.new()
	logo_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_fx.anchor_right = 1
	logo_fx.anchor_bottom = 1
	logo_fx.material = ShaderMaterial.new()
	logo_fx.material.shader = Shader.new()
	logo_fx.material.shader.code = LOGO_FX_SHADER
	logo.add_child(logo_fx)

func _logo_fx_step(delta:float):
	if !logo_fx: return
	var RI = load("res://mods/replay/Reimagined.gd")
	RI.fps_watch(delta)
	var on = !RI.lite() and bool(RI.val("glitch_fx"))
	logo_fx.visible = on
	logo.get_node("FxCopy").visible = on
	if !on: return
	logo_glitch_next -= delta
	if logo_glitch_next <= 0.0:
		logo_glitch_next = rand_range(1.8, 4.5)
		logo_glitch_left = rand_range(0.08, 0.2)
	if punch > 0.95 and logo_glitch_left <= 0.0 and randf() < 0.25: logo_glitch_left = 0.07
	logo_glitch_left -= delta
	logo_glitch = rand_range(0.45, 0.8) if logo_glitch_left > 0.0 else max(0.0, logo_glitch - delta * 8.0)
	logo_fx.material.set_shader_param("power", logo_glitch)
	logo_fx.material.set_shader_param("split", 1.2 + 1.5 * punch)
	logo_fx.material.set_shader_param("size", logo.rect_size * logo.rect_scale)

# ------------------------------------------------------------------ card
# outlined card on a see-through black fill: accent bar (grows on hover), title + subtitle,
# chevron; slides a little on hover, the outline lights up in the card colour on hover and
# flashes on the beat
class Card extends Control:
	signal pressed
	var beat:float = 0.0
	var title:String = ""
	var sub:String = ""
	var col:Color = Color(1, 1, 1)
	var font_big:Font
	var font_small:Font
	var hover:float = 0.0
	var press:float = 0.0
	var inside:bool = false

	func _ready():
		connect("mouse_entered", self, "_set_inside", [true])
		connect("mouse_exited", self, "_set_inside", [false])

	func _set_inside(v:bool):
		inside = v

	var held:bool = false # pressed on this card (the release only counts then)

	func _gui_input(ev):
		if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
			if ev.pressed:
				press = 1.0
				held = true
			elif held:
				held = false
				# where the button came up, not the hover flag: mouse_entered can lag behind
				# (the cards move every frame), and clicks were lost (Rhythia-reimagined)
				if Rect2(Vector2(), rect_size).has_point(ev.position): emit_signal("pressed")

	func _process(delta):
		var h = lerp(hover, 1.0 if inside else 0.0, 1.0 - exp(-delta * 14.0))
		var p = max(0.0, press - delta * 5.0)
		if abs(h - hover) > 0.0005 or p != press:
			hover = h
			press = p
			update()

	func _draw():
		var w = rect_size.x
		var h = rect_size.y
		var x0 = hover * 12.0 - press * 4.0 + beat * 5.0
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(col.r * 0.08, col.g * 0.08, col.b * 0.08, 0.32 + 0.1 * hover)
		var edge = Color(1, 1, 1, 0.3).linear_interpolate(col, hover)
		edge.a = min(1.0, edge.a + 0.4 * beat)
		sb.border_color = edge
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(12)
		sb.corner_detail = 8
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(x0, 0, w, h))
		var bh = h * (0.36 + 0.16 * hover)
		var bar = StyleBoxFlat.new()
		bar.bg_color = col
		bar.set_corner_radius_all(2)
		bar.anti_aliasing = true
		draw_style_box(bar, Rect2(x0 + 14, (h - bh) / 2, 4 + 2 * hover, bh))
		var tx = x0 + 34 + 6 * hover
		if font_big: draw_string(font_big, Vector2(tx, h * 0.5 + 2), title, Color(1, 1, 1))
		if font_small: draw_string(font_small, Vector2(tx, h * 0.5 + 24), sub, Color(1, 1, 1, 0.45 + 0.2 * hover))
		var cx = x0 + w - 34 + 6 * hover
		var cy = h * 0.5
		var cc = Color(1, 1, 1, 0.25 + 0.6 * hover)
		draw_line(Vector2(cx - 6, cy - 9), Vector2(cx + 3, cy), cc, 2.5)
		draw_line(Vector2(cx + 3, cy), Vector2(cx - 6, cy + 9), cc, 2.5)
