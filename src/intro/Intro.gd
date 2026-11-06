extends CanvasLayer
# Startup intro (personal build): your RHYTHIA wordmark (logo.webp), in monochrome, writes itself up
# like osu!lazer's logo animation - a thin white pen runs along its outlines from left to right, the
# letters fill in right behind it with a bright leading edge, the pen lines fade into the finished logo.
# The camera eases in the whole time (osu!-style zoom), punches on the impact (a thump made in code, a
# faint flash) when REIMAGINED lands under the logo, and at the end flies forward through the logo
# into the menu. No voice. Injected into init.tscn; moves itself to the root so it survives the
# init -> menu scene change. Click / any key skips to the fly-through.
# Cheap: the pen's ~700 segments are built once into one triangle array; the drawing is two shader
# uniforms per frame (pen and fill progress), not geometry rebuilt every frame.

const PATH = "res://mods/intro/Intro.gd"
const WORDMARK = "res://mods/intro/logo.webp"
const ICON = "res://assets/images/branding/icon.png"
const MENU = "res://scenes/menu/menu2.tscn"
const Ring = preload("res://mods/replay/Ring.gd")
const SUB = "REIMAGINED"

const STROKES = 900              # outline segments
const SAMPLE_W = 340             # the logo's alpha is traced at this width
const LOGO_W = 0.6               # of the screen's width (at most LOGO_HMAX of its height)
const LOGO_HMAX = 0.34
const LOGO_Y = 0.45              # centre, of the screen's height
const SLANT = 0.12               # the pen runs left to right, a little ahead at the top

# timeline (s)
const PEN_AT = 0.15
const PEN_TIME = 1.0
const FILL_AT = 0.45
const FILL_TIME = 1.0
const TEXT_AT = 1.35
const TEXT_TIME = 0.45
const IMPACT_AT = 1.8
const DONE_AT = 2.3
const OUTRO = 0.55
const MAX_WAIT = 6.0             # never cover the screen longer than this past DONE_AT

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

# the logo: monochrome (luminance lifted, so the fill reads white and the dark outline stays dark),
# revealed by the same sweep with a soft edge and a white glow riding it
const FILL_SHADER = """shader_type canvas_item;
uniform float progress = 0.0;
uniform float slant = 0.12;
uniform float lift = 1.45;
uniform float grey = 1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = clamp(dot(c.rgb, vec3(0.299, 0.587, 0.114)) * lift, 0.0, 1.0);
	c.rgb = mix(c.rgb, vec3(l), grey);
	float a = (UV.x + slant * (1.0 - UV.y)) / (1.0 + slant);
	float p = progress * 1.03;
	float shown = 1.0 - smoothstep(p - 0.025, p, a);
	float edge = exp(-abs(p - a) * 40.0) * step(a, p) * (1.0 - smoothstep(0.97, 1.03, progress));
	c.rgb = min(c.rgb + vec3(0.85 * edge), vec3(1.0));
	COLOR = vec4(c.rgb, c.a * shown) * COLOR;
}"""

var bg:ColorRect
var stage:Control                # everything that zooms: logo, pen, subtitle
var logo:TextureRect
var pen:Control
var text:Control                 # subtitle + rule (redrawn while they animate)
var flash_rect:ColorRect
var font:Font
var player:AudioStreamPlayer
var tex:Texture
var aspect:float = 3.0
var segs:Array = []              # [a, b, k] in 0..1 of the logo
var clock:float = -1.0
var impacted:bool = false
var outro_t:float = -1.0
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
	stage = Control.new()
	_full(stage, self)
	tex = _logo_texture()
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
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	_full(flash_rect, self)
	_trace()

	player = AudioStreamPlayer.new()
	player.stream = _thump()
	player.bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
	player.volume_db = -4.0
	add_child(player)
	# keep the menu music quiet until the logo leaves
	music_bus = AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		music_was_muted = AudioServer.is_bus_mute(music_bus)
		AudioServer.set_bus_mute(music_bus, true)
	_apply()
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
func _logo_texture():
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

# where the pen passes a point (0..1 of the logo): left to right, a little ahead at the top
static func _sweep(p:Vector2) -> float:
	return (p.x + SLANT * (1.0 - p.y)) / (1.0 + SLANT)

# the logo's outlines: opaque pixels with a clear neighbour, picked evenly, each joined to another
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
	var r = logo_rect()
	logo.rect_position = r.position
	logo.rect_size = r.size
	stage.rect_pivot_offset = r.position + r.size / 2
	if font is DynamicFont: font.size = int(max(12, round(r.size.y * 0.16)))
	pen.update()
	text.update()

func wants_fullscreen() -> bool:
	var f = File.new()
	if f.open(Globals.p("user://settings.json"), File.READ) != OK: return false
	var r = JSON.parse(f.get_as_text())
	f.close()
	return r.error == OK and r.result is Dictionary and r.result.get("window_fullscreen", false) == true

var wait_fs:bool = false
var wait_t:float = 0.0
var settle:int = 0

func _process(delta):
	if clock < 0:
		# the game opens windowed and switches to fullscreen ~1-2 s later: start after that,
		# so the drawing isn't lost in the switch (and init has applied the volume settings)
		if wait_t == 0.0: wait_fs = wants_fullscreen()
		wait_t += delta
		if wait_fs and !OS.window_fullscreen and wait_t < 4.0: return
		settle += 1
		if settle < 3: return
		clock = 0.0
		layout()
		return
	clock += delta
	if !impacted and clock >= IMPACT_AT:
		impacted = true
		if player.stream: player.play()
	if outro_t < 0:
		var sc = get_tree().current_scene
		var menu_up = sc and sc.filename in [MENU, "res://scenes/menu/oldmenu2.tscn"]
		if clock >= DONE_AT and (menu_up or clock >= DONE_AT + MAX_WAIT): begin_outro()
	else:
		outro_t += delta
		if outro_t >= OUTRO + 0.1:
			finish()
			return
	_apply()
	if clock < DONE_AT + 0.3: text.update()

static func _c01(v:float) -> float:
	return clamp(v, 0.0, 1.0)

static func _cubic_out(p:float) -> float:
	return 1.0 - pow(1.0 - clamp(p, 0.0, 1.0), 3)

# pen and fill: quick in the middle, easing at both ends (a hand writing it)
static func _sine_io(p:float) -> float:
	return 0.5 - 0.5 * cos(PI * clamp(p, 0.0, 1.0))

static func _hit(now:float, at:float, decay:float) -> float:
	return exp(-(now - at) * decay) if now >= at else 0.0

func _apply():
	var t = max(clock, 0.0)
	pen.material.set_shader_param("progress", _sine_io((t - PEN_AT) / PEN_TIME))
	pen.material.set_shader_param("fade", 1.0 - _c01((t - FILL_AT - FILL_TIME) / 0.35))
	logo.material.set_shader_param("progress", _sine_io((t - FILL_AT) / FILL_TIME))
	# camera: eases in from further back the whole time, punches on the impact, breathes while
	# waiting; the outro flies forward through the logo while everything fades to the menu
	var s = 0.86 + 0.14 * _cubic_out(t / (IMPACT_AT + 0.2)) + 0.012 * max(0.0, t - IMPACT_AT - 0.2)
	s += 0.05 * _hit(t, IMPACT_AT, 7.0)
	var a = 1.0
	if outro_t >= 0:
		var o = _c01(outro_t / OUTRO)
		s *= 1.0 + 1.6 * o * o * o
		a = 1.0 - o * o
		bg.color.a = 1.0 - _c01((outro_t - 0.15) / OUTRO)
	stage.rect_scale = Vector2(s, s)
	stage.modulate.a = a
	flash_rect.color.a = 0.07 * _hit(t, IMPACT_AT, 6.0)

# the pen's segments, built once (colour r = sweep position; the shader reveals them)
func _draw_pen():
	if segs.empty(): return
	var r = logo_rect()
	var w = max(1.5, r.size.x / SAMPLE_W * 1.1)
	var arr = []
	for sg in segs:
		arr.append([r.position + sg[0] * r.size, r.position + sg[1] * r.size, w, Color(sg[2], 0, 0, 1)])
	Ring.bars(pen, arr)

# REIMAGINED tracking in under the logo along a rule that draws out from the middle
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

func _skip():
	if clock < 0: return
	if clock < DONE_AT:
		clock = DONE_AT
		impacted = true
		text.update()
	begin_outro()

func begin_outro():
	if outro_t < 0:
		outro_t = 0.0
		if music_bus >= 0: AudioServer.set_bus_mute(music_bus, music_was_muted)

func _input(ev):
	if outro_t >= 0 or clock < 0.3: return
	if (ev is InputEventKey or ev is InputEventMouseButton) and ev.pressed:
		_skip()

func finish():
	if music_bus >= 0 and outro_t < 0: AudioServer.set_bus_mute(music_bus, music_was_muted)
	queue_free()

# never leave the music bus muted, however the intro goes away
func _exit_tree():
	if music_bus >= 0 and outro_t < 0: AudioServer.set_bus_mute(music_bus, music_was_muted)

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
