extends Control
# Fail screen (personal build; the look of ULTRAKILL's death screen, own lines): black, a fast
# diagnostic log types out in VCR mono - warnings orange, errors red - one blip per line, with the
# run's own numbers. ScreenSwap ("fail") shows it on a live fail and loads the results after it; a key
# or click skips to the end, R restarts the map.

const FONT = "res://assets/font/UbuntuMono/Regular.ttf" # (= VCR OSD Mono in this build)
const CPS = 1100.0     # characters typed per second
const GAP = 0.035      # s between lines
const HOLD = 0.4       # s on the last line
const ORANGE = Color(1.0, 0.56, 0.12)
const RED = Color(1.0, 0.13, 0.1)
const PALE = Color(1.0, 0.93, 0.78)

var lines = []
var labels = []
var cur:int = -1
var line_t:float = 0.0
var end_t:float = -1.0
var t:float = 0.0
var done:bool = false
var players = []
var pidx:int = 0
var rng = RandomNumberGenerator.new()
var black:ColorRect

func _init():
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_IGNORE

static func _mmss(ms:float) -> String:
	return "%d:%02d" % [int(ms / 60000), int(ms / 1000) % 60]

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	rng.randomize()
	black = ColorRect.new()
	black.color = Color(0, 0, 0)
	black.anchor_right = 1
	black.anchor_bottom = 1
	black.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(black)
	var pos = max(float(Rhythia.song_end_position), 0.0) # (a fail in the lead-in: 0:00)
	var length = max(float(Rhythia.song_end_length), 1.0)
	var miss = int(Rhythia.song_end_misses)
	var W = ORANGE
	var E = RED
	lines = [
		["WARNING: ENERGY RESERVES DEPLETED.", W],
		["RUNNING DIAGNOSTIC", W],
		["ERROR: CURSOR TRACKING MODULE NOT RESPONDING", E],
		["ERROR: HIT REGISTER DESYNCHRONIZED", E],
		["WARNING: COMBO CHAIN SEVERED", W],
		["ATTEMPTING RESYNC", W],
		["ERROR: TIMING CORE OUTSIDE HIT WINDOW", E],
		["INSUFFICIENT ENERGY.", E],
		["INSUFFICIENT ENERGY.", E],
		["INITIATING RECOVERY PROTOCOL", PALE],
		["ATTEMPTING CONNECTION WITH AUDIO SYNC", W],
		["ERROR: %d NOTE%s UNACCOUNTED FOR" % [miss, "" if miss == 1 else "S"], E],
		["ERROR: NOTE STREAM OVERFLOW", E],
		["WARNING: UNABLE TO SUSTAIN RHYTHM", W],
		["ERROR: VISUAL GRID MALFUNCTION", E],
		["ERROR: APPROACH VECTOR LOST", E],
		["INSUFFICIENT ENERGY.", E],
		["WARNING: RUN HALTED AT %s / %s (%d%%)" % [_mmss(pos), _mmss(length), int(100.0 * pos / length)], W],
		["! SIGNAL FAILURE !", E],
		["! SIGNAL FAILURE !", E],
		["! SIGNAL FAILURE !", E],
		["-!- RUN TERMINATED -!-", E],
		["ERROR: NO INPUT RESPONDING. UNABLE TO FINISH MAP", E],
		["! SIGNAL FAILURE !", E],
		["INSUFFICIENT ENERGY.", E],
		["WARNING: UNABLE TO HOLD THE BEAT", W],
		["-!- RUN TERMINATED -!-", E],
		["-!- RUN TERMINATED -!-", E],
		["I CAN STILL HEAR THE MUSIC.", E],
		["I CAN STILL HEAR THE MUSIC.", E],
		["I CAN STILL HEAR THE MUSIC.", E],
		["I CAN STILL HEAR THE MUSIC.", E],
	]
	var h = get_viewport_rect().size.y
	var size = int(clamp(h * 0.0235, 12, 40))
	var f = DynamicFont.new()
	if ResourceLoader.exists(FONT): f.font_data = load(FONT)
	f.size = size
	for i in lines.size():
		var l = Label.new()
		l.text = lines[i][0]
		l.add_font_override("font", f)
		var c:Color = lines[i][1]
		l.add_color_override("font_color", c)
		l.add_color_override("font_color_shadow", Color(c.r, c.g * 0.6, c.b * 0.4, 0.35)) # (a soft glow)
		l.add_constant_override("shadow_as_outline", 1)
		l.rect_position = Vector2(get_viewport_rect().size.x * 0.04, h * 0.07 + i * size * 1.1)
		l.visible_characters = 0
		l.visible = false
		l.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(l)
		labels.append(l)
	var bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
	for i in 4:
		var p = AudioStreamPlayer.new()
		p.bus = bus
		p.volume_db = -15.0
		add_child(p)
		players.append(p)
	set_process_input(true)

func _blip(err:bool):
	var s = blips()
	var p = players[pidx]
	pidx = (pidx + 1) % players.size()
	p.stream = s[1] if err else s[0]
	p.pitch_scale = rng.randf_range(0.97, 1.03)
	p.play()

func _process(delta):
	var dt = min(delta, 1.0 / 30.0)
	t += dt
	if end_t >= 0.0:
		end_t += dt
		var last = labels[-1]
		last.visible = fmod(end_t, 0.16) < 0.1 or end_t > 0.32 # (the last line blinks twice)
		if end_t >= HOLD: done = true
	else:
		line_t += dt
		if cur < 0 or line_t >= lines[cur][0].length() / CPS + GAP:
			_next()
		else:
			labels[cur].visible_characters = int(min(line_t * CPS, lines[cur][0].length()))
	for l in labels: # a faint CRT flicker
		if l.visible: l.modulate.a = 0.9 + 0.1 * rng.randf()

func _next():
	if cur >= 0: labels[cur].visible_characters = -1
	cur += 1
	line_t = 0.0
	if cur >= labels.size():
		cur = labels.size() - 1
		end_t = 0.0
		return
	labels[cur].visible = true
	labels[cur].visible_characters = 0
	_blip(lines[cur][1] == RED)

# R: restart the map (ScreenSwap.retry: eyelids close); any other key / click: the whole log at once
var restarting:bool = false
func _input(ev):
	if restarting or !((ev is InputEventKey or ev is InputEventMouseButton) and ev.pressed) or (ev is InputEventKey and ev.echo): return
	if ev is InputEventKey and ev.scancode == KEY_R and get_parent().has_method("retry"):
		get_tree().set_input_as_handled()
		restarting = true
		get_parent().retry()
		return
	if end_t >= 0.0 or t < 0.25: return # (not a click still in flight from the run)
	get_tree().set_input_as_handled()
	for i in labels.size():
		labels[i].visible = true
		labels[i].visible_characters = -1
	cur = labels.size() - 1
	end_t = HOLD - 0.15

# two short square blips (line / error line), made once on the loading card
static func blips() -> Array:
	if Engine.has_meta("rr_death_blips"): return Engine.get_meta("rr_death_blips")
	var out = [_blip_sample(1320.0), _blip_sample(700.0)]
	Engine.set_meta("rr_death_blips", out)
	return out

static func _blip_sample(hz:float) -> AudioStreamSample:
	var rate = 44100
	var n = int(rate * 0.035)
	var data = PoolByteArray()
	data.resize(n * 2)
	for i in n:
		var tt = float(i) / rate
		var sq = 1.0 if fmod(tt * hz, 1.0) < 0.5 else -1.0
		var env = min(1.0, tt * 2000.0) * (1.0 - float(i) / n)
		var v = int(sq * env * 0.3 * 32000.0)
		if v < 0: v += 65536
		data[i * 2] = v & 0xff
		data[i * 2 + 1] = (v >> 8) & 0xff
	var s = AudioStreamSample.new()
	s.format = AudioStreamSample.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s
