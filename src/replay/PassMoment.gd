extends CanvasLayer
# The pass moment (personal build): on the last note of a live pass (all notes done, not failed, not a
# replay / autoplay / multiplayer / map queue) the run freezes for a beat with a white flash and a
# "clear" sound, then everything moving drops to slow motion (Engine.time_scale: hit effects, HUD,
# glow - the music rings out as it is, the run's clock is its own) while the camera pushes in and a
# glow blooms on the cursor. After HOLD s a white-out cuts to the results (Game.end(END_PASS); the
# frozen white frame flies past into them, ScreenSwap "forward"). Added to Game by Game._ready.

const STOP = 0.08      # s of hit-stop
const SLOW = 0.3       # time scale after it
const HOLD = 1.5       # s from the last note to the results
const WHITE = 0.14     # s of white-out at the end
const FOV_PUSH = 14.0  # degrees the camera pushes in

var game:Node
var spawn:Node
var cam:Camera = null
var cursor:Spatial = null
var base_fov:float = 70.0
var started:bool = false
var t0:int = 0
var flash:ColorRect
var halo:Control
var halo_k:float = 0.0
var done:bool = false

static func live() -> bool:
	return !Rhythia.replaying and !Rhythia.visual_mode and !Rhythia.queue_active

func _ready():
	game = get_parent()
	spawn = game.get_node_or_null("Spawn")
	layer = 97
	pause_mode = PAUSE_MODE_PROCESS
	process_priority = 1000 # (after the run's own camera code)
	halo = Control.new()
	halo.anchor_right = 1
	halo.anchor_bottom = 1
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add = CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = add
	halo.connect("draw", self, "_draw_halo")
	add_child(halo)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.anchor_right = 1
	flash.anchor_bottom = 1
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

func _process(_delta):
	if done or !spawn: return
	if !started:
		if game.ending: # (failed / gave up / ended some other way first)
			done = true
			return
		if game.get("passed") and spawn.ms > game.last_ms + float(spawn.get("hit_window")) and _mp_free():
			_start()
		return
	var el = (OS.get_ticks_usec() - t0) / 1000000.0
	if game.ending: # (the song ran out, or R held to skip: Game.end runs on its own)
		_finish()
		return
	Engine.time_scale = 0.0 if el < STOP else SLOW
	var f = 0.0
	if el < STOP: f = 0.6
	else: f = 0.6 * max(0.0, 1.0 - (el - STOP) / 0.4)
	if el > HOLD - WHITE: f = max(f, (el - (HOLD - WHITE)) / WHITE) # the white-out
	flash.color.a = clamp(f, 0.0, 1.0)
	var e = 1.0 - pow(1.0 - min(el / 1.3, 1.0), 3)
	if is_instance_valid(cam): cam.fov = base_fov - FOV_PUSH * e
	halo_k = min(1.0, el / 0.25)
	halo.update()
	if el >= HOLD:
		game.set_meta("rr_pass_moment", true) # (Game.end: no zoom-to-black, straight into the results)
		_finish()
		game.end(Globals.END_PASS)

func _mp_free() -> bool:
	var mp = get_tree().root.get_node_or_null("RRMultiplayer")
	return !(mp and mp.in_match())

func _start():
	started = true
	t0 = OS.get_ticks_usec()
	var sc = get_tree().current_scene
	cam = sc.get_node_or_null("Camera") if sc else null
	if cam: base_fov = cam.fov
	cursor = spawn.get_node_or_null("Cursor")
	_take_sound()
	if Engine.has_meta("rr_clear_sfx"):
		var p = AudioStreamPlayer.new()
		p.stream = Engine.get_meta("rr_clear_sfx")
		p.bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
		p.volume_db = -6.0
		add_child(p)
		p.play()

func _finish():
	done = true
	Engine.time_scale = 1.0

func _exit_tree():
	if started: Engine.time_scale = 1.0

# a soft white bloom on the cursor (additive rings)
func _draw_halo():
	if !is_instance_valid(cursor) or !is_instance_valid(cam) or halo_k <= 0.0: return
	var p = cam.unproject_position(cursor.global_transform.origin)
	var r = halo.rect_size.y * 0.09 * (0.6 + 0.4 * halo_k)
	for i in 8:
		var k = float(i + 1) / 8.0
		halo.draw_circle(p, r * k, Color(1.0, 0.95, 0.8, 0.07 * halo_k))

# ------------------------------------------------------------------ the clear sound
# a low impact under a bright fifth / octave bloom with a sparkle on top (made once on a worker while a
# map loads; ~1.4 s at 22 kHz)
static func warm():
	_take_sound()
	if Engine.has_meta("rr_clear_sfx") or Engine.has_meta("rr_clear_job"): return
	if OS.can_use_threads():
		var job = load("res://mods/replay/PassMoment.gd").new() # (not in the tree: just the thread's target)
		var th = Thread.new()
		if th.start(job, "_sound_job") == OK: Engine.set_meta("rr_clear_job", [th, job])
		else: job.free()
	else: Engine.set_meta("rr_clear_sfx", _clear_sound())

func _sound_job(_u):
	return _clear_sound()

static func _take_sound():
	if !Engine.has_meta("rr_clear_job"): return
	var j = Engine.get_meta("rr_clear_job")
	Engine.remove_meta("rr_clear_job")
	var s = j[0].wait_to_finish()
	j[1].free()
	if s is AudioStreamSample: Engine.set_meta("rr_clear_sfx", s)

static func _clear_sound() -> AudioStreamSample:
	var rate = 22050
	var n = int(rate * 1.4)
	var data = PoolByteArray()
	data.resize(n * 2)
	var rng = RandomNumberGenerator.new()
	rng.seed = 77
	var freqs = [261.63, 392.0, 523.25, 784.0, 1046.5] # C4 G4 C5 G5 C6: open fifths, no third (sits over any key)
	var amps = [0.22, 0.2, 0.2, 0.14, 0.1]
	var ph = [0.0, 0.0, 0.0, 0.0, 0.0]
	var thump = 0.0
	var lp = 0.0
	for i in n:
		var t = float(i) / rate
		var v = 0.0
		for k in 5:
			ph[k] += TAU * freqs[k] * (1.0 + 0.002 * sin(t * 5.0 + k)) / rate
			v += sin(ph[k]) * amps[k] * exp(-t * (1.6 + k * 0.5))
		thump += TAU * (55.0 + 90.0 * exp(-t * 18.0)) / rate
		v += sin(thump) * 0.55 * exp(-t * 9.0)
		lp += ((rng.randf() * 2.0 - 1.0) - lp) * 0.6
		v += lp * 0.12 * exp(-t * 14.0) # (a bright sparkle at the hit)
		v *= min(1.0, t * 600.0)
		var s16 = int(clamp(v, -1.0, 1.0) * 26000.0)
		if s16 < 0: s16 += 65536
		data[i * 2] = s16 & 0xff
		data[i * 2 + 1] = (s16 >> 8) & 0xff
	var s = AudioStreamSample.new()
	s.format = AudioStreamSample.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s
