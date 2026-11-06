extends CanvasLayer
# Startup intro (personal build), after osu!lazer's: while the game loads, a thin line pulses on black;
# once the menu is up and running smoothly, your RHYTHIA wordmark (logo.webp, monochrome) writes itself -
# a white pen runs along its outlines left to right, the letters fill in behind it with a bright edge,
# the camera easing in - REIMAGINED lands under it with a thump, then the camera rushes through the
# wordmark, the square Rhythia logo zooms down into place drawing itself on (exactly where the title
# screen's logo sits) and a white flash hands over to the title menu, the music starting with it.
# No voice. Injected into init.tscn; moves itself to the root so it survives the init -> menu scene
# change. Click / any key skips to the flash.
# Smooth: the animation only starts once loading is over (the startup frames are long), its clock
# never jumps more than 1/30 s, the outline trace and the thump are made before it starts, and the
# pen's ~900 segments are built once (the drawing is shader uniforms).

const PATH = "res://mods/intro/Intro.gd"
const WORDMARK = "res://mods/intro/logo.webp"
const ICON = "res://assets/images/branding/icon.png"
const MENUS = ["res://scenes/menu/menu2.tscn", "res://scenes/menu/oldmenu2.tscn"]
const Ring = preload("res://mods/replay/Ring.gd")
const SUB = "REIMAGINED"

const STROKES = 900              # outline segments
const SAMPLE_W = 340             # the wordmark's alpha is traced at this width
const LOGO_W = 0.6               # of the screen's width (at most LOGO_HMAX of its height)
const LOGO_HMAX = 0.34
const LOGO_Y = 0.45              # centre, of the screen's height
const SLANT = 0.12               # the pen runs left to right, a little ahead at the top
const ICON_PX = 520.0            # = TitleMenu.LOGO: the square logo lands at the title logo's size

# timeline (s, from the start of the animation)
const PEN_AT = 0.1
const PEN_TIME = 0.9
const FILL_AT = 0.35
const FILL_TIME = 0.9
const TEXT_AT = 1.15
const TEXT_TIME = 0.4
const IMPACT_AT = 1.55
const RUSH_AT = 2.05             # the camera rushes through the wordmark
const RUSH_TIME = 0.45
const ICON_AT = 2.2              # the square logo zooms down into place, drawing itself on
const ICON_TIME = 0.55
const FLASH_AT = 2.85            # white flash: the title menu takes over
const FLASH_TIME = 0.8
const SETTLE_FRAMES = 12         # smooth frames in a row (< 30 ms) before it starts
const MAX_LOAD_WAIT = 15.0       # start anyway after this long

# pen: vertex colour r = where along the sweep the segment is (0..1), a = the soft edge
const PEN_SHADER = """shader_type canvas_item;
uniform float progress = 0.0;
uniform float fade = 1.0;
void fragment() {
	float behind = progress * 1.001 - COLOR.r;
	float head = exp(-max(behind, 0.0) * 25.0);
	float g = 0.72 + 0.28 * head;
	COLOR = vec4(vec3(g), COLOR.a * step(0.0, behind) * fade);
}"""

# a logo in monochrome (luminance lifted: fills read white, dark outlines stay dark), revealed by a
# sweep with a soft edge and a white glow riding it. mode 0: left to right (slanted), 1: clockwise
# around the centre from the top
const FILL_SHADER = """shader_type canvas_item;
uniform float progress = 0.0;
uniform float slant = 0.12;
uniform float lift = 1.45;
uniform float mode = 0.0;
const float TAU = 6.28318530718;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = clamp(dot(c.rgb, vec3(0.299, 0.587, 0.114)) * lift, 0.0, 1.0);
	c.rgb = vec3(l);
	vec2 d = UV - 0.5;
	float a = mode < 0.5 ? (UV.x + slant * (1.0 - UV.y)) / (1.0 + slant) : fract(atan(d.x, -d.y) / TAU + 1.0);
	float p = progress * 1.03;
	float shown = 1.0 - smoothstep(p - 0.025, p, a);
	float edge = exp(-abs(p - a) * 40.0) * step(a, p) * (1.0 - smoothstep(0.97, 1.03, progress));
	c.rgb = min(c.rgb + vec3(0.85 * edge), vec3(1.0));
	COLOR = vec4(c.rgb, c.a * shown) * COLOR;
}"""

var bg:ColorRect
var loader:Control               # the loading line
var stage:Control                # the wordmark part: logo, pen, subtitle (zooms as one)
var logo:TextureRect
var pen:Control
var text:Control
var icon:TextureRect
var flash:ColorRect
var font:Font
var thump:AudioStreamPlayer
var tex:Texture
var aspect:float = 3.0
var segs:Array = []              # [a, b, k] in 0..1 of the wordmark
var clock:float = -1.0           # animation time; < 0 = still loading
var wait_t:float = 0.0
var smooth:int = 0
var impacted:bool = false
var flashed:bool = false
var music_bus:int = -1
var music_was_muted:bool = false

func _ready():
	if get_parent() != get_tree().root:
		# launched from init.tscn: run as a root node instead (once: init loads twice on a first
		# launch, the stock cutscene's replacement goes back to it - fixes/NoCutscene.gd)
		if !Engine.has_meta("rr_intro_started"):
			Engine.set_meta("rr_intro_started", true)
			var me = load(PATH).new()
			me.name = "Intro"
			get_tree().root.call_deferred("add_child", me)
		queue_free()
		return
	layer = 128
	pause_mode = Node.PAUSE_MODE_PROCESS
	bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	_full(bg, self)
	loader = Control.new()
	_full(loader, self)
	loader.connect("draw", self, "_draw_loader")
	stage = Control.new()
	_full(stage, self)
	tex = _wordmark()
	if tex: aspect = tex.get_width() / max(1.0, float(tex.get_height()))
	logo = TextureRect.new()
	logo.texture = tex
	logo.expand = true
	logo.stretch_mode = TextureRect.STRETCH_SCALE
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.material = _mat(FILL_SHADER)
	logo.material.set_shader_param("slant", SLANT)
	stage.add_child(logo)
	pen = Control.new()
	_full(pen, stage)
	pen.material = _mat(PEN_SHADER)
	pen.connect("draw", self, "_draw_pen")
	text = Control.new()
	_full(text, stage)
	text.connect("draw", self, "_draw_text")
	if ResourceLoader.exists("res://uitheme.tres"): text.theme = load("res://uitheme.tres")
	font = text.get_font("font", "Label")
	if font is DynamicFont: font = font.duplicate()
	icon = TextureRect.new()
	icon.texture = load(ICON)
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.material = _mat(FILL_SHADER)
	icon.material.set_shader_param("mode", 1.0)
	icon.material.set_shader_param("lift", 1.9) # (= the title logo's grey material)
	icon.visible = false
	add_child(icon)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	_full(flash, self)
	stage.visible = false
	_trace()
	thump = AudioStreamPlayer.new()
	thump.stream = _thump()
	thump.bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
	thump.volume_db = -4.0
	add_child(thump)
	# keep the menu music quiet until the flash
	music_bus = AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		music_was_muted = AudioServer.is_bus_mute(music_bus)
		AudioServer.set_bus_mute(music_bus, true)
	layout()
	get_tree().root.connect("size_changed", self, "layout")

func _full(c:Control, parent:Node):
	c.anchor_right = 1
	c.anchor_bottom = 1
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)

func _mat(code:String) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = code
	return m

# the wordmark (raw .webp in the pck, decoded here); the stock icon if it's missing
func _wordmark():
	var f = File.new()
	if f.open(WORDMARK, File.READ) == OK:
		var img = Image.new()
		var err = img.load_webp_from_buffer(f.get_buffer(f.get_len()))
		f.close()
		if err == OK:
			var t = ImageTexture.new()
			t.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
			return t
	return load(ICON)

# where the pen passes a point (0..1 of the wordmark): left to right, a little ahead at the top
static func _sweep(p:Vector2) -> float:
	return (p.x + SLANT * (1.0 - p.y)) / (1.0 + SLANT)

# the wordmark's outlines: opaque pixels with a clear neighbour, picked evenly, each joined to another
# outline pixel 3-6 px away into a short segment (a grid of 8 px cells finds that neighbour)
func _trace():
	if !tex: return
	var img = tex.get_data()
	if !(img is Image): return
	img = img.duplicate()
	if img.is_compressed(): img.decompress()
	var w = SAMPLE_W
	var h = int(max(8, round(SAMPLE_W / aspect)))
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	img.lock()
	var edge = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if img.get_pixel(x, y).a < 0.5: continue
			if img.get_pixel(x - 1, y).a < 0.5 or img.get_pixel(x + 1, y).a < 0.5 or img.get_pixel(x, y - 1).a < 0.5 or img.get_pixel(x, y + 1).a < 0.5:
				edge.append(Vector2(x, y))
	img.unlock()
	if edge.size() < 4: return
	var cells = {}
	for p in edge:
		var k = int(p.x / 8) * 1000 + int(p.y / 8)
		if !cells.has(k): cells[k] = []
		cells[k].append(p)
	var size = Vector2(w, h)
	var step = max(1, edge.size() / STROKES)
	for i in range(0, edge.size(), step):
		var a:Vector2 = edge[i]
		var b = a
		var best = 1e9
		var cx = int(a.x / 8)
		var cy = int(a.y / 8)
		for gx in range(cx - 1, cx + 2):
			for gy in range(cy - 1, cy + 2):
				for q in cells.get(gx * 1000 + gy, []):
					var d = a.distance_squared_to(q)
					if d > 9 and d < 36 and d < best:
						best = d
						b = q
		if b == a: continue
		segs.append([a / size, b / size, _sweep((a + b) / 2 / size)])

func logo_rect() -> Rect2:
	var vs = get_viewport().get_visible_rect().size
	var w = min(vs.x * LOGO_W, vs.y * LOGO_HMAX * aspect)
	var h = w / aspect
	return Rect2(Vector2((vs.x - w) / 2, vs.y * LOGO_Y - h / 2), Vector2(w, h))

func layout():
	var vs = get_viewport().get_visible_rect().size
	var r = logo_rect()
	logo.rect_position = r.position
	logo.rect_size = r.size
	stage.rect_pivot_offset = r.position + r.size / 2
	icon.rect_size = Vector2(ICON_PX, ICON_PX)
	icon.rect_position = (vs - icon.rect_size) / 2
	icon.rect_pivot_offset = icon.rect_size / 2
	if font is DynamicFont: font.size = int(max(12, round(r.size.y * 0.16)))
	pen.update()
	text.update()
	loader.update()

func _process(delta):
	if clock < 0:
		_wait(delta)
		return
	clock += min(delta, 1.0 / 30.0) # (a late frame slows it a little instead of jumping ahead)
	if !impacted and clock >= IMPACT_AT:
		impacted = true
		thump.play()
	if !flashed and clock >= FLASH_AT: _flash()
	if clock >= FLASH_AT + FLASH_TIME:
		finish()
		return
	_apply()
	if clock < RUSH_AT + 0.1: text.update()

# loading: a thin line pulses until the menu is up and frames come smoothly
func _wait(delta):
	wait_t += delta
	loader.update()
	var sc = get_tree().current_scene
	var up = sc != null and sc.filename in MENUS
	smooth = smooth + 1 if up and delta < 0.03 else 0
	if smooth >= SETTLE_FRAMES or wait_t >= MAX_LOAD_WAIT:
		clock = 0.0
		loader.visible = false
		stage.visible = true
		layout()
		_apply()

func _draw_loader():
	var vs = loader.rect_size
	var k = 0.5 + 0.5 * sin(wait_t * 4.0)
	var half = 18.0 + 22.0 * k
	loader.draw_rect(Rect2(vs.x / 2 - half, vs.y / 2 - 1, half * 2, 2), Color(1, 1, 1, 0.25 + 0.35 * k))

static func _c01(v:float) -> float:
	return clamp(v, 0.0, 1.0)

static func _cubic_out(p:float) -> float:
	return 1.0 - pow(1.0 - clamp(p, 0.0, 1.0), 3)

static func _sine_io(p:float) -> float:
	return 0.5 - 0.5 * cos(PI * clamp(p, 0.0, 1.0))

static func _hit(now:float, at:float, decay:float) -> float:
	return exp(-(now - at) * decay) if now >= at else 0.0

func _apply():
	var t = clock
	pen.material.set_shader_param("progress", _sine_io((t - PEN_AT) / PEN_TIME))
	pen.material.set_shader_param("fade", 1.0 - _c01((t - FILL_AT - FILL_TIME) / 0.3))
	logo.material.set_shader_param("progress", _sine_io((t - FILL_AT) / FILL_TIME))
	# camera: eases in while it writes, punches on the impact, then rushes through the wordmark
	var s = 0.86 + 0.14 * _cubic_out(t / (IMPACT_AT + 0.2)) + 0.05 * _hit(t, IMPACT_AT, 7.0)
	var rush = _c01((t - RUSH_AT) / RUSH_TIME)
	s *= 1.0 + 3.0 * rush * rush * rush
	stage.rect_scale = Vector2(s, s)
	stage.modulate.a = 1.0 - rush * rush
	# the square logo: zooms down from big into its place on the title screen, drawing on clockwise
	var ik = _c01((t - ICON_AT) / ICON_TIME)
	icon.visible = ik > 0.0 and !flashed
	if icon.visible:
		var e = _cubic_out(ik)
		var si = 1.0 + 1.4 * (1.0 - e) + 0.04 * _hit(t, ICON_AT + ICON_TIME, 9.0)
		icon.rect_scale = Vector2(si, si)
		icon.modulate.a = _c01(ik * 3.0)
		icon.material.set_shader_param("progress", _sine_io(ik / 0.8))
	# flash: full white the moment the title menu takes over, then fading
	if flashed: flash.color.a = pow(1.0 - _c01((t - FLASH_AT) / FLASH_TIME), 2)

# white flash: the black and the intro's logo go, the title menu (same logo, same place) is under it
func _flash():
	flashed = true
	clock = max(clock, FLASH_AT)
	bg.visible = false
	stage.visible = false
	loader.visible = false
	icon.visible = false
	flash.color.a = 1.0
	if music_bus >= 0: AudioServer.set_bus_mute(music_bus, music_was_muted)
	thump.volume_db = -9.0
	thump.play()

# the pen's segments, built once (colour r = sweep position; the shader reveals them)
func _draw_pen():
	if segs.empty(): return
	var r = logo_rect()
	var w = max(1.5, r.size.x / SAMPLE_W * 1.1)
	var arr = []
	for sg in segs:
		arr.append([r.position + sg[0] * r.size, r.position + sg[1] * r.size, w, Color(sg[2], 0, 0, 1)])
	Ring.bars(pen, arr)

# REIMAGINED tracking in under the wordmark along a rule that draws out from the middle
func _draw_text():
	if clock < 0: return
	var r = logo_rect()
	var t = clock
	var cx = r.position.x + r.size.x / 2
	var y = r.end.y + r.size.y * 0.24
	var k = _cubic_out((t - TEXT_AT) / TEXT_TIME)
	if font and k > 0:
		var spacing = font.get_height() * (0.55 + 0.9 * (1.0 - k))
		var adv = []
		var total = 0.0
		for ch in SUB:
			var cw = font.get_string_size(ch).x
			adv.append(cw)
			total += cw + spacing
		total -= spacing
		var x = cx - total / 2
		for i in SUB.length():
			text.draw_string(font, Vector2(x, y + font.get_ascent() * 0.5), SUB[i], Color(1, 1, 1, 0.92 * k))
			x += adv[i] + spacing
	var rule = _cubic_out((t - TEXT_AT + 0.1) / 0.35)
	if rule > 0:
		var ry = y + font.get_height() * 0.75 if font else y + 20
		var half = r.size.x * 0.32 * rule
		var a = 0.85 * (1.0 - 0.5 * _c01((t - IMPACT_AT) / 0.4))
		Ring.bars(text, [[Vector2(cx - half, ry), Vector2(cx + half, ry), 2.0, Color(1, 1, 1, a)]])

func _input(ev):
	if flashed or clock < 0.3: return
	if (ev is InputEventKey or ev is InputEventMouseButton) and ev.pressed:
		clock = FLASH_AT
		_flash()

func finish():
	if music_bus >= 0 and !flashed: AudioServer.set_bus_mute(music_bus, music_was_muted)
	queue_free()

# never leave the music bus muted, however the intro goes away
func _exit_tree():
	if music_bus >= 0 and !flashed: AudioServer.set_bus_mute(music_bus, music_was_muted)

# a short low thump, made on the fly (16-bit mono)
static func _thump() -> AudioStreamSample:
	var rate = 44100
	var n = int(rate * 0.7)
	var data = PoolByteArray()
	data.resize(n * 2)
	var rng = RandomNumberGenerator.new()
	rng.seed = 42
	var phase = 0.0
	var lp = 0.0
	for i in n:
		var t = float(i) / rate
		phase += TAU * (46.0 + 70.0 * exp(-t * 9.0)) / rate
		var body = sin(phase) * exp(-t * 6.5)
		lp += ((rng.randf() * 2.0 - 1.0) - lp) * 0.12
		var v = int(clamp((body * 0.85 + lp * exp(-t * 45.0) * 0.45) * min(1.0, t * 400.0), -1.0, 1.0) * 30000.0)
		if v < 0: v += 65536
		data[i * 2] = v & 0xff
		data[i * 2 + 1] = (v >> 8) & 0xff
	var s = AudioStreamSample.new()
	s.format = AudioStreamSample.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s
