extends Control
# Fail screen (personal build; the look of ULTRAKILL's death screen, own lines). The run plays on under
# it (nothing is judged - NoteManager; the cursor still moves): the screen darkens, the camera tilts
# over and sinks, the music goes muffled, and a fast diagnostic log types out in VCR mono - warnings
# orange, errors red - each line with the map start's thump (louder on the orange ones), with the
# run's own numbers. ScreenSwap ("fail") owns it: when the log ends or a click / Esc skips it, the run
# stops, the red card flashes, the eyelids close, the results fade in from black; R restarts instead.

const FONT = "res://assets/font/UbuntuMono/Regular.ttf" # (= VCR OSD Mono in this build)
const CPS = 2400.0     # characters typed per second
const GAP = 0.022      # s between lines
const HOLD = 0.35      # s on the last line
const ORANGE = Color(1.0, 0.56, 0.12)
const RED = Color(1.0, 0.13, 0.1)
const PALE = Color(1.0, 0.93, 0.78)
const ROLL = 24.0      # degrees the camera tilts over by the end
const SINK = 0.35      # how far it sinks
const DIM0 = 0.3       # the dark over the run at the start (-> 1 at the end)
const MUFFLE_BUS = "RRDeathMuffle"

var lines = []
var labels = []
var cur:int = -1
var line_t:float = 0.0
var end_t:float = -1.0
var t:float = 0.0
var total:float = 1.0
var done:bool = false
var stopped:bool = false
var players = []
var pidx:int = 0
var rng = RandomNumberGenerator.new()
var black:ColorRect
var cam = null          # the run's camera (tilted while the log runs)
var applied:float = 0.0 # (tilt put on it this frame, taken off again first thing next frame)
var music:AudioStreamPlayer = null
var music_bus:String = ""
var music_db:float = 0.0

func _init():
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_IGNORE

static func _mmss(ms:float) -> String:
	return "%d:%02d" % [int(ms / 60000), int(ms / 1000) % 60]

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	process_priority = 1000 # (after the run's own camera code: the tilt goes on last)
	rng.randomize()
	black = ColorRect.new()
	black.color = Color(0, 0, 0, DIM0)
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
	total = HOLD
	for l in lines: total += l[0].length() / CPS + GAP
	var vs = get_viewport_rect().size
	var size = int(clamp(vs.y * 0.0235, 12, 40))
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
		l.rect_position = Vector2(vs.x * 0.04, vs.y * 0.07 + i * size * 1.1)
		l.visible = false
		l.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(l)
		labels.append(l)
	var bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
	for i in 10:
		var p = AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		players.append(p)
	var sc = get_tree().current_scene
	cam = sc.get_node_or_null("Camera") if sc else null
	_muffle_start(sc)

# ------------------------------------------------------------------ the run under it
func _muffle_start(sc):
	music = sc.get_node_or_null("Game/Spawn/Music") if sc else null
	if !(music is AudioStreamPlayer): music = null
	if !music: return
	var bus = AudioServer.get_bus_index(MUFFLE_BUS)
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus, MUFFLE_BUS)
		var lp = AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(bus, lp)
	music_bus = music.bus
	music_db = music.volume_db
	AudioServer.set_bus_send(bus, music_bus)
	music.bus = MUFFLE_BUS

func _muffle(k:float):
	var bus = AudioServer.get_bus_index(MUFFLE_BUS)
	if bus < 0 or AudioServer.get_bus_effect_count(bus) == 0: return
	AudioServer.get_bus_effect(bus, 0).cutoff_hz = 20000.0 * pow(500.0 / 20000.0, k)

# ScreenSwap calls this first thing every frame: the camera back as the run left it
func untilt():
	if applied != 0.0 and is_instance_valid(cam):
		cam.translate_object_local(Vector3(0, applied * SINK, 0))
		cam.rotate_object_local(Vector3(0, 0, 1), -deg2rad(ROLL) * applied)
	applied = 0.0

func _tilt(k:float):
	if !is_instance_valid(cam): return
	var e = k * k * (3.0 - 2.0 * k)
	cam.rotate_object_local(Vector3(0, 0, 1), deg2rad(ROLL) * e)
	cam.translate_object_local(Vector3(0, -e * SINK, 0))
	applied = e

func _exit_tree():
	untilt()
	if is_instance_valid(music) and music_bus != "": music.bus = music_bus
	var bus = AudioServer.get_bus_index(MUFFLE_BUS)
	if bus >= 0: AudioServer.remove_bus(bus)

# the run stops (ScreenSwap: red card, eyelids): the log freezes as it is, its sounds stop
func stop():
	stopped = true
	for p in players: p.stop()

# ------------------------------------------------------------------ the log
func _line_sound(orange:bool):
	if !Engine.has_meta("rr_enter_sfx"): return
	var p = players[pidx]
	pidx = (pidx + 1) % players.size()
	p.stream = Engine.get_meta("rr_enter_sfx")
	p.volume_db = -7.0 if orange else -16.0
	p.pitch_scale = rng.randf_range(0.94, 1.06)
	p.play()

func _process(delta):
	var dt = min(delta, 1.0 / 30.0)
	if !stopped:
		t += dt
		var k = min(t / total, 1.0)
		black.color.a = DIM0 + (1.0 - DIM0) * k * k
		_muffle(min(t / 0.5, 1.0))
		if music: music.volume_db = music_db - 12.0 * k
		if end_t >= 0.0:
			end_t += dt
			labels[-1].visible = fmod(end_t, 0.14) < 0.09 or end_t > 0.28 # (the last line blinks twice)
			if end_t >= HOLD: done = true
		else:
			line_t += dt
			if cur < 0 or line_t >= lines[cur][0].length() / CPS + GAP:
				_next()
			else:
				labels[cur].visible_characters = int(min(line_t * CPS, lines[cur][0].length()))
		for l in labels: # a faint CRT flicker
			if l.visible: l.modulate.a = 0.9 + 0.1 * rng.randf()
	_tilt(min(t / total, 1.0))

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
	_line_sound(lines[cur][1] != RED)

# R: restart (ScreenSwap.retry); a click or Esc: on to the results (ScreenSwap.finish)
var answered:bool = false
func _input(ev):
	if answered or stopped or !ev.is_pressed() or (ev is InputEventKey and ev.echo): return
	var parent = get_parent()
	if ev is InputEventKey and ev.scancode == KEY_R and parent.has_method("retry"):
		get_tree().set_input_as_handled()
		answered = true
		parent.retry()
	elif ((ev is InputEventMouseButton and ev.button_index <= BUTTON_MIDDLE) or (ev is InputEventKey and ev.scancode == KEY_ESCAPE)) and t >= 0.25 and parent.has_method("finish"):
		get_tree().set_input_as_handled() # (not before 0.25 s: a click still in flight from the run)
		answered = true
		parent.finish()
