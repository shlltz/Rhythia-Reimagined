extends CanvasLayer
# Startup intro (personal build; port of the Rewrite : Unleashed one): on a black screen, white speed
# lines streak in from both sides and settle onto the outline of the Rhythia logo, drawing it; the logo
# fills in under them as they fade, a line draws out beneath it and RHYTHIA REIMAGINED tracks in along
# it and lands with a small impact (a thump made on the fly, a faint flash). Then it pushes in and
# fades to the menu. No voice. Injected into init.tscn; moves itself to the root so it survives the
# init -> menu scene change. Click / any key skips to the settled picture.

const PATH = "res://mods/intro/Intro.gd"
const LOGO = "res://assets/images/branding/icon.png"
const MENU = "res://scenes/menu/menu2.tscn"
const Ring = preload("res://mods/replay/Ring.gd")
const TITLE = "RHYTHIA REIMAGINED"

const STROKES = 700              # outline segments
const SAMPLE = 200               # the logo's alpha is traced at this size
const LOGO_H = 0.36              # of the screen's height
const LOGO_Y = 0.42              # centre, of the screen's height

# timeline (s)
const LINES_IN = 0.15
const LINES_SPREAD = 0.55
const LINE_TRAVEL = 0.5
const FILL_AT = 0.95
const FILL_TIME = 0.45
const RULE_AT = 1.25
const RULE_TIME = 0.35
const TEXT_AT = 1.35
const TEXT_TIME = 0.5
const IMPACT_AT = 1.85
const DONE_AT = 2.2
const OUTRO = 0.45
const MAX_WAIT = 6.0             # never cover the screen longer than this past DONE_AT

var bg:ColorRect
var canvas:Control               # lines, rule, title and flash are drawn here
var logo:TextureRect
var font:Font
var player:AudioStreamPlayer
var strokes:Array = []           # [a, b, delay, side, reach, shade] (a, b in 0..1 of the logo)
var clock:float = -1.0
var flash:float = 0.0
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
	_full(bg)
	var tex = _logo_texture()
	logo = TextureRect.new()
	logo.texture = tex
	logo.expand = true
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.modulate.a = 0.0
	if tex and tex.resource_path == LOGO: logo.material = _grey() # (the stock pink logo turns white)
	add_child(logo)
	canvas = Control.new()
	_full(canvas)
	canvas.connect("draw", self, "_draw_canvas")
	if ResourceLoader.exists("res://uitheme.tres"): canvas.theme = load("res://uitheme.tres")
	font = canvas.get_font("font", "Label")
	if font is DynamicFont: font = font.duplicate()
	_trace(tex)

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
	layout()
	get_tree().root.connect("size_changed", self, "layout")

func _full(c:Control):
	c.anchor_right = 1
	c.anchor_bottom = 1
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)

# the logo from the Rhythia-reimagined skin folder if there is one, else the stock icon
func _logo_texture():
	if ResourceLoader.exists("res://mods/replay/Reimagined.gd"):
		var t = load("res://mods/replay/Reimagined.gd").skin_tex("logo")
		if t: return t
	return load(LOGO)

func _grey():
	if ResourceLoader.exists("res://mods/replay/Look.gd"): return load("res://mods/replay/Look.gd").grey_material()
	return null

# the logo's outline: opaque pixels with a clear neighbour, picked evenly, each joined to another
# outline pixel 3-6 px away into a short segment (a grid of 8 px cells finds that neighbour)
func _trace(tex:Texture):
	if !tex: return
	var img = tex.get_data()
	if !(img is Image): return
	img = img.duplicate()
	if img.is_compressed(): img.decompress()
	img.resize(SAMPLE, SAMPLE, Image.INTERPOLATE_BILINEAR)
	img.lock()
	var edge = []
	for y in range(1, SAMPLE - 1):
		for x in range(1, SAMPLE - 1):
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
	var rng = RandomNumberGenerator.new()
	rng.seed = 1110
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
		var u = a.x / SAMPLE
		# a sweep outwards from the middle, a little scattered
		var delay = LINES_IN + abs(u - 0.5) * 2.0 * LINES_SPREAD * 0.7 + rng.randf() * LINES_SPREAD * 0.3
		strokes.append([a / SAMPLE, b / SAMPLE, delay, -1.0 if u < 0.5 else 1.0, rng.randf_range(0.35, 0.8), rng.randf_range(0.7, 1.0)])

func logo_rect() -> Rect2:
	var vs = get_viewport().get_visible_rect().size
	var d = vs.y * LOGO_H
	return Rect2(Vector2((vs.x - d) / 2, vs.y * LOGO_Y - d / 2), Vector2(d, d))

func layout():
	var r = logo_rect()
	logo.rect_position = r.position
	logo.rect_size = r.size
	logo.rect_pivot_offset = r.size / 2
	if font is DynamicFont: font.size = int(max(12, round(r.size.x * 0.085)))
	canvas.update()

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
		# so the lines aren't lost in the switch (and init has applied the volume settings)
		if wait_t == 0.0: wait_fs = wants_fullscreen()
		wait_t += delta
		if wait_fs and !OS.window_fullscreen and wait_t < 4.0: return
		settle += 1
		if settle < 3: return
		clock = 0.0
		layout()
		return
	clock += delta
	if flash > 0: flash = max(0.0, flash - delta * 6.0)
	if !impacted and clock >= IMPACT_AT:
		impacted = true
		flash = 1.0
		if player.stream: player.play()
	if outro_t < 0:
		var sc = get_tree().current_scene
		var menu_up = sc and sc.filename in [MENU, "res://scenes/menu/oldmenu2.tscn"]
		if clock >= DONE_AT and (menu_up or clock >= DONE_AT + MAX_WAIT): begin_outro()
	_apply()
	if outro_t >= 0:
		outro_t += delta
		var o = clamp(outro_t / OUTRO, 0.0, 1.0)
		o = o * o
		var s = logo.rect_scale.x * (1.0 + 0.06 * o)
		logo.rect_scale = Vector2(s, s)
		logo.modulate.a *= 1.0 - o
		canvas.modulate.a = 1.0 - o
		bg.color.a = 1.0 - clamp((outro_t - 0.1) / OUTRO, 0.0, 1.0)
		if outro_t >= OUTRO + 0.1:
			finish()
			return
	if clock < DONE_AT + 0.5 or flash > 0 or outro_t >= 0: canvas.update()

static func _c01(v:float) -> float:
	return clamp(v, 0.0, 1.0)

static func _expo_out(p:float) -> float:
	return 1.0 if p >= 1.0 else 1.0 - pow(2.0, -10.0 * p)

static func _cubic_out(p:float) -> float:
	return 1.0 - pow(1.0 - p, 3)

func _apply():
	var fill = _cubic_out(_c01((clock - FILL_AT) / FILL_TIME))
	logo.modulate.a = fill
	var s = 1.04 - 0.04 * fill
	logo.rect_scale = Vector2(s, s)

func _draw_canvas():
	if clock < 0: return
	var r = logo_rect()
	var t = clock
	var w = max(1.5, r.size.x / 200.0 * 1.2)
	var fade = 1.0 - _c01((t - FILL_AT - 0.15) / 0.5) # (the lines give way to the fill)
	if fade > 0 and !strokes.empty():
		var sw = canvas.rect_size.x
		var segs = []
		for st in strokes:
			var p = _expo_out(_c01((t - st[2]) / LINE_TRAVEL))
			if p <= 0.0: continue
			var a = r.position + st[0] * r.size
			var b = r.position + st[1] * r.size
			# a long streak from the side, shortening onto its segment
			var off = (1.0 - p) * sw * st[4] * st[3]
			var tail = (1.0 - p) * sw * 0.18 * st[3]
			var g = st[5]
			segs.append([a + Vector2(off + tail, 0), b + Vector2(off, 0), w, Color(g, g, g, min(1.0, p * 3.0) * fade)])
		Ring.bars(canvas, segs)
	# the title, tracking in (letters close up as it fades in), and the line under it
	var y = r.end.y + r.size.y * 0.16
	var cx = r.position.x + r.size.x / 2
	var text = _c01((t - TEXT_AT) / TEXT_TIME)
	if font and text > 0:
		var k = _cubic_out(text)
		var fs = font.get_height()
		var spacing = fs * (0.32 + 0.6 * (1.0 - k))
		var adv = []
		var total = 0.0
		for ch in TITLE:
			var cw = font.get_string_size(ch).x
			adv.append(cw)
			total += cw + spacing
		total -= spacing
		var land = _c01((t - IMPACT_AT) / 0.22)
		var pop = 1.0 + 0.04 * (1.0 - land) if t >= IMPACT_AT else 1.0
		var x = cx - total * pop / 2
		var col = Color(1, 1, 1, 0.92 * k)
		for i in TITLE.length():
			canvas.draw_string(font, Vector2(x, y + font.get_ascent() * 0.5), TITLE[i], col)
			x += (adv[i] + spacing) * pop
	var rule = _expo_out(_c01((t - RULE_AT) / RULE_TIME))
	if rule > 0:
		var ry = y + r.size.y * 0.09
		var half = r.size.x * 0.75 * rule
		var a = 0.9 * (1.0 - 0.55 * _c01((t - IMPACT_AT) / 0.4))
		Ring.bars(canvas, [[Vector2(cx - half, ry), Vector2(cx + half, ry), max(2.0, w), Color(1, 1, 1, a)]])
	if flash > 0: canvas.draw_rect(Rect2(Vector2.ZERO, canvas.rect_size), Color(1, 1, 1, flash * 0.06))

func _skip():
	if clock < 0: return
	if clock < DONE_AT:
		clock = DONE_AT + 0.5
		impacted = true
		flash = 0.0
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
