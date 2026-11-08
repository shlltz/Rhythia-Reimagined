extends Control
# Fail screen (personal build; the look of ULTRAKILL's death screen, own lines). The run plays on under
# it (nothing is judged - NoteManager; the cursor still moves): the camera tilts over and sinks, the
# view goes red (red-mono, then into a deep red; scanlines) with glitch bursts that come faster as it
# goes (slices shifted, RGB split - over the text too), the music goes muffled, and a fast diagnostic log types out in VCR mono - warnings
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
const ROLL = 16.0      # degrees the camera rolls over by the end
const PITCH = 42.0     # degrees it tips back (looking up: falling backwards to the ground)
const SINK = 1.0       # how far it drops (accelerating)
const SLOW_END = 0.08  # the run's speed (map + song, pitch down like tape) by the end of the log
const CURSOR_GONE = 0.7 # (the cursor has faded out by this part of the log)
const RADIO_DB = [-24.0, -9.0] # the radio static from the start to the end of the log
const TINT_SHADER = """shader_type canvas_item;
uniform float k = 0.0;
void fragment() {
	vec3 col = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	float l = dot(col, vec3(0.3, 0.59, 0.11));
	vec3 red = vec3(min(1.0, l * 1.7 + 0.06), l * 0.12, l * 0.1);
	col = mix(col, red, smoothstep(0.0, 0.35, k));
	col = mix(col, vec3(0.4, 0.0, 0.02), smoothstep(0.3, 1.0, k) * 0.92);
	col *= 0.9 + 0.1 * sin(FRAGCOORD.y * 1.6);
	COLOR = vec4(col, 1.0);
}"""
const GLITCH_SHADER = """shader_type canvas_item;
uniform float amount = 0.0;
uniform float seed = 0.0;
float h(float x) { return fract(sin(x * 12.9898 + seed * 78.233) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	float band = floor(uv.y * (14.0 + 30.0 * h(1.0)));
	float on = step(1.0 - amount * 0.7, h(band));
	uv.x += on * (h(band + 7.0) - 0.5) * 0.16 * amount;
	float ca = 0.012 * amount * (0.5 + on);
	vec3 col;
	col.r = texture(SCREEN_TEXTURE, uv + vec2(ca, 0.0)).r;
	col.g = texture(SCREEN_TEXTURE, uv).g;
	col.b = texture(SCREEN_TEXTURE, uv - vec2(ca, 0.0)).b;
	col += on * step(0.93, h(band + 3.0)) * 0.25 * amount; // a bright torn line now and then
	COLOR = vec4(col, 1.0);
}"""
const MUFFLE_BUS = "RRDeathMuffle"

var lines = []
var labels = []
var cur:int = -1
var line_t:float = 0.0
var end_t:float = -1.0
var t:float = 0.0
var total:float = 1.0
# the last line floods the screen (ULTRAKILL): FLOOD copies, each faster than the one before, the
# log scrolling up once it reaches the bottom so they keep dropping down
const FLOOD = 48
var flood_from:int = 1 << 30
var row_y0:float = 0.0
var row_h:float = 1.0
var row_end:float = 1.0

# s line i takes (typing + gap)
func _dur(i:int) -> float:
	var d = lines[i][0].length() / CPS + GAP
	if i >= flood_from: d /= min(pow(1.17, i - flood_from), 7.0)
	return d
var done:bool = false
var stopped:bool = false
var players = []
var pidx:int = 0
var rng = RandomNumberGenerator.new()
var tint:ColorRect
var glitch:ColorRect
var glitch_copy:BackBufferCopy
var burst:float = 0.0    # s left of the current glitch burst
var burst_amt:float = 0.0
var cam = null          # the run's camera (tilted while the log runs)
var applied:bool = false # (fall put on it this frame, taken off again first thing next frame)
var base_tf:Transform    # (the camera as the run left it)
var nm = null           # the run's NoteManager (slowed down)
var radio:AudioStreamPlayer = null
var cur_mat:SpatialMaterial = null # the run's cursor (fading out), its trail and glow
var cur_a:float = 1.0
var trail = null
var trail_a:float = 1.0
var glow = null
var cur_2d:CanvasItem = null
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
	tint = _shader_rect(TINT_SHADER)
	add_child(tint)
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
	]
	flood_from = lines.size()
	for j in FLOOD: lines.append(["I CAN STILL HEAR THE MUSIC.", E])
	total = HOLD
	for i in lines.size(): total += _dur(i)
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
		row_y0 = vs.y * 0.07
		row_h = size * 1.1
		row_end = vs.y * 0.94
		l.rect_position = Vector2(vs.x * 0.04, row_y0 + i * row_h)
		l.visible = false
		l.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(l)
		labels.append(l)
	glitch_copy = BackBufferCopy.new() # (the glitch reads the screen with the text on it)
	glitch_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(glitch_copy)
	glitch_copy.visible = false
	glitch = _shader_rect(GLITCH_SHADER)
	glitch.visible = false
	add_child(glitch)
	var bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
	for i in 10:
		var p = AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		players.append(p)
	var sc = get_tree().current_scene
	cam = sc.get_node_or_null("Camera") if sc else null
	nm = sc.get_node_or_null("Game/Spawn") if sc else null
	if nm and !("rr_slow" in nm): nm = null
	_muffle_start(sc)
	_cursor_start(sc)
	_radio_take() # (done long ago on the loading card)
	if Engine.has_meta("rr_radio_sfx"): # the radio static under the log
		radio = AudioStreamPlayer.new()
		radio.stream = Engine.get_meta("rr_radio_sfx")
		radio.bus = bus
		radio.volume_db = RADIO_DB[0]
		add_child(radio)
		radio.play(rng.randf() * 1.0)

static func _shader_rect(code:String) -> ColorRect:
	var r = ColorRect.new()
	r.anchor_right = 1
	r.anchor_bottom = 1
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.material = ShaderMaterial.new()
	r.material.shader = shader(code)
	return r

# one Shader per code for the session (compiled once on the loading card, shared by every use)
static func shader(code:String) -> Shader:
	var cache = Engine.get_meta("rr_shader_cache") if Engine.has_meta("rr_shader_cache") else {}
	if !cache.has(code.hash()):
		var sh = Shader.new()
		sh.code = code
		cache[code.hash()] = sh
		Engine.set_meta("rr_shader_cache", cache)
	return cache[code.hash()]

# on the loading card: the log's font drawn once at its size and its shaders compiled (no hitch on the fail)
static func warm(parent:Node):
	_radio_take()
	if !Engine.has_meta("rr_radio_sfx") and !Engine.has_meta("rr_radio_job"): # the radio static, made on a worker (tens of ms of maths)
		if OS.can_use_threads():
			var job = load("res://mods/replay/DeathLog.gd").new() # (not in the tree: just the thread's target)
			var th = Thread.new()
			if th.start(job, "_radio_job") == OK: Engine.set_meta("rr_radio_job", [th, job])
			else: job.free()
		else: Engine.set_meta("rr_radio_sfx", _radio_sound())

	for code in [TINT_SHADER, GLITCH_SHADER]:
		var r = _shader_rect(code)
		r.anchor_right = 0
		r.anchor_bottom = 0
		r.rect_size = Vector2(2, 2)
		r.modulate.a = 0.01
		parent.add_child(r)
		parent.get_tree().create_timer(0.3).connect("timeout", r, "queue_free")
	var vs = parent.get_viewport().get_visible_rect().size
	var f = DynamicFont.new()
	if ResourceLoader.exists(FONT): f.font_data = load(FONT)
	f.size = int(clamp(vs.y * 0.0235, 12, 40))
	var l = Label.new()
	l.text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:.!-/()%' "
	l.add_font_override("font", f)
	l.add_constant_override("shadow_as_outline", 1)
	l.add_color_override("font_color_shadow", Color(1, 0.5, 0.2, 0.35))
	l.modulate.a = 0.01
	parent.add_child(l)
	parent.get_tree().create_timer(0.3).connect("timeout", l, "queue_free")
	var f2 = DynamicFont.new() # (the red card's FAIL, ScreenSwap)
	if ResourceLoader.exists(FONT): f2.font_data = load(FONT)
	f2.size = fail_size(vs)
	var l2 = Label.new()
	l2.text = "FAIL"
	l2.add_font_override("font", f2)
	l2.modulate.a = 0.01
	parent.add_child(l2)
	parent.get_tree().create_timer(0.3).connect("timeout", l2, "queue_free")

static func fail_size(vs:Vector2) -> int:
	return int(clamp(vs.y * 0.17, 40, 260))


func _radio_job(_u):
	return _radio_sound()

static func _radio_take():
	if !Engine.has_meta("rr_radio_job"): return
	var j = Engine.get_meta("rr_radio_job")
	Engine.remove_meta("rr_radio_job")
	var s = j[0].wait_to_finish()
	j[1].free()
	if s is AudioStreamSample: Engine.set_meta("rr_radio_sfx", s)

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

# the cursor fades away while the log types (its own material copied first: the run's stays as it is)
func _cursor_start(sc):
	if !sc: return
	var mesh = sc.get_node_or_null("Game/Spawn/Cursor/Mesh")
	if mesh and mesh.get("material/0") is SpatialMaterial:
		cur_mat = mesh.get("material/0").duplicate()
		cur_mat.flags_transparent = true
		cur_a = cur_mat.albedo_color.a
		mesh.set("material/0", cur_mat)
	trail = sc.get_node_or_null("Game/CursorTrail")
	if trail and "rr_alpha" in trail: trail_a = trail.rr_alpha
	else: trail = null
	var cur = sc.get_node_or_null("Game/Spawn/Cursor")
	if cur:
		for c in cur.get_children():
			if c is MeshInstance and "mat" in c and c.get("mat") is SpatialMaterial: glow = c
	cur_2d = sc.get_node_or_null("Game/Spawn/Cursor/VisualPos")

func _cursor_fade(f:float):
	var e = f * f * (3.0 - 2.0 * f)
	if cur_mat: cur_mat.albedo_color.a = cur_a * (1.0 - e)
	if is_instance_valid(trail): trail.rr_alpha = trail_a * (1.0 - e)
	if is_instance_valid(glow) and glow.mat: glow.mat.albedo_color.a *= (1.0 - e) # (after its own update: this runs last)
	if is_instance_valid(cur_2d): cur_2d.modulate.a = 1.0 - e

# ScreenSwap calls this first thing every frame: the camera back as the run left it
func untilt():
	if applied and is_instance_valid(cam): cam.transform = base_tf
	applied = false

# falling backwards: the view tips up and rolls a little while it drops, faster and faster
func _tilt(k:float):
	if !is_instance_valid(cam): return
	var e = k * k * (3.0 - 2.0 * k)
	base_tf = cam.transform
	var tf = base_tf
	tf.basis = tf.basis * Basis(Vector3(1, 0, 0), deg2rad(PITCH) * e) * Basis(Vector3(0, 0, 1), deg2rad(ROLL) * e)
	tf.origin.y -= SINK * k * k
	cam.transform = tf
	applied = true

func _exit_tree():
	untilt()
	if is_instance_valid(music) and music_bus != "": music.bus = music_bus
	var bus = AudioServer.get_bus_index(MUFFLE_BUS)
	if bus >= 0: AudioServer.remove_bus(bus)

# the run stops (ScreenSwap: red card, eyelids): the log freezes as it is, its sounds stop
func stop():
	stopped = true
	for p in players: p.stop()
	if radio: radio.stop()
	glitch.visible = false
	glitch_copy.visible = false

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
		tint.material.set_shader_param("k", k)
		_glitch(dt, k)
		_muffle(min(t / 0.5, 1.0))
		if music: music.volume_db = music_db - 12.0 * k
		var slow = lerp(1.0, SLOW_END, 1.0 - pow(1.0 - k, 2)) # the run winds down hard, the song with it (pitch down, like tape)
		_cursor_fade(clamp(k / CURSOR_GONE, 0.0, 1.0))
		if nm:
			nm.rr_slow = slow
			if music: music.pitch_scale = max(0.05, float(nm.speed_multi) * slow)
		if radio: radio.volume_db = lerp(RADIO_DB[0], RADIO_DB[1], k) + (6.0 if burst > 0.0 else 0.0) # (louder with every glitch)
		if end_t >= 0.0:
			end_t += dt
			labels[-1].visible = fmod(end_t, 0.14) < 0.09 or end_t > 0.28 # (the last line blinks twice)
			if end_t >= HOLD: done = true
		else:
			line_t += dt
			var n = 0
			while (cur < 0 or line_t >= _dur(cur)) and end_t < 0.0 and n < 8: # (fast flood lines: several a frame)
				line_t = line_t - _dur(cur) if cur >= 0 else 0.0
				_next()
				n += 1
			if end_t < 0.0 and cur >= 0:
				var full = lines[cur][0].length() / CPS + GAP # (flood lines type faster by the same factor)
				labels[cur].visible_characters = int(min(line_t * CPS * full / _dur(cur), lines[cur][0].length()))
		for l in labels: # a faint CRT flicker
			if l.visible: l.modulate.a = 0.9 + 0.1 * rng.randf()
	_tilt(min(t / total, 1.0))

# glitch bursts: more often as the log goes on
func _glitch(dt:float, k:float):
	if burst > 0.0:
		burst -= dt
		glitch.material.set_shader_param("seed", rng.randf() * 100.0)
		glitch.material.set_shader_param("amount", burst_amt)
		if burst <= 0.0:
			glitch.visible = false
			glitch_copy.visible = false # (no screen copy between bursts)
	elif rng.randf() < dt * (2.5 + 9.0 * k):
		burst = rng.randf_range(0.04, 0.12)
		burst_amt = rng.randf_range(0.35, 1.0) * (0.6 + 0.4 * k)
		glitch.visible = true
		glitch_copy.visible = true

func _next():
	if cur >= 0: labels[cur].visible_characters = -1
	cur += 1
	if cur >= labels.size():
		cur = labels.size() - 1
		end_t = 0.0
		return
	labels[cur].visible = true
	labels[cur].visible_characters = 0
	var over = row_y0 + (cur + 1) * row_h - row_end # (past the bottom: everything moves up a row)
	if over > 0.0:
		for i in labels.size(): labels[i].rect_position.y = row_y0 + i * row_h - over
	var j = cur - flood_from
	if j < 6 or j % 2 == 0: _line_sound(lines[cur][1] != RED)

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

# radio static (a loop): hiss in a radio band, fluttering, with dropouts and crackles; made once on
# the loading card (22 kHz is plenty for static)
static func _radio_sound() -> AudioStreamSample:
	var rate = 22050
	var n = int(rate * 1.6)
	var data = PoolByteArray()
	data.resize(n * 2)
	var rng = RandomNumberGenerator.new()
	rng.seed = 1993
	var lp1 = 0.0
	var lp2 = 0.0
	var gate = 1.0
	var gate_n = 0
	var crack = 0.0
	var ph = 0.0
	for i in n:
		var w = rng.randf() * 2.0 - 1.0
		lp1 += (w - lp1) * 0.55       # (top of the band)
		lp2 += (lp1 - lp2) * 0.09     # (bottom of the band)
		var hiss = lp1 - lp2
		gate_n -= 1
		if gate_n <= 0: # dropouts / level jumps every 15..90 ms
			gate_n = int(rate * rng.randf_range(0.015, 0.09))
			gate = 0.08 if rng.randf() < 0.18 else rng.randf_range(0.45, 1.0)
		ph += TAU * rng.randf_range(9.0, 23.0) / rate
		var flutter = 0.75 + 0.25 * sin(ph)
		if rng.randf() < 0.0012: crack = rng.randf_range(0.5, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		crack *= 0.93
		var edge = min(1.0, min(i, n - 1 - i) / (rate * 0.01)) # (no click at the loop point)
		var v = int(clamp((hiss * 1.6 * gate * flutter + crack) * edge, -1.0, 1.0) * 24000.0)
		if v < 0: v += 65536
		data[i * 2] = v & 0xff
		data[i * 2 + 1] = (v >> 8) & 0xff
	var s = AudioStreamSample.new()
	s.format = AudioStreamSample.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamSample.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = n
	return s
