extends CanvasLayer
# The pass moment (personal build): on the last note of a live pass (all notes done, not failed, not a
# replay / autoplay / multiplayer / map queue) the run freezes for a beat with a white flash and a
# "clear" sound that echoes out (ping-pong, ~4 s), a ripple goes out from the cursor (screen
# distortion + a bright ring), the screen cracks from the cursor and breaks, a beam of light, and
# everything but the cursor and the effects fades to near black, and big bright
# glass shards fall from the sky (after DMC5's Vergil return: tumbling panes that glint as they turn,
# now and then a huge chunk close past the camera, glitter) - they keep falling until the map itself
# ends (the song runs out), then a white-out cuts to the results (Game.end(END_PASS); ScreenSwap
# "forward"). Everything moving drops to slow motion for the first moments (Engine.time_scale - the
# music plays on as it is, the run's clock is its own), then eases back. Added to Game by Game._ready.

const STOP = 0.08      # s of hit-stop
const SLOW = 0.3       # time scale after it
const SLOW_UNTIL = 1.5 # s: slow motion, then back to normal speed by SLOW_BACK
const SLOW_BACK = 2.6
const HOLD_MIN = 1.5   # s at least from the last note to the results (when the song is already over)
const HOLD_MAX = 180.0 # (a song that never reports its end)
const WHITE = 0.14     # s of white-out at the end
const FOV_PUSH = 14.0  # degrees the camera pushes in
const RIPPLES = [0.0, 0.16, 0.34] # s: three rings out from the cursor
const RIPPLE_TIME = 1.1

const RIPPLE_SHADER = """shader_type canvas_item;
uniform vec2 center = vec2(0.5);   // (in this rect's UV: top-down)
uniform float aspect = 1.7778;
uniform vec3 radius = vec3(-1.0);  // per ring, in screen heights
uniform vec3 amp = vec3(0.0);
void fragment() {
	vec2 d = UV - center;
	d.x *= aspect;
	float dist = max(length(d), 0.0001);
	vec2 dir = d / dist;
	dir.x /= aspect;
	float fy = sign(dFdy(SCREEN_UV.y)) * sign(dFdy(UV.y)); // (SCREEN_UV may run bottom-up)
	vec3 x = (vec3(dist) - radius) / 0.05;
	vec3 w = exp(-x * x) * amp;
	float off = dot(sin(x * 2.4), w);
	float glow = w.x + w.y + w.z;
	vec2 o = dir * off * 0.035;
	vec3 c = textureLod(SCREEN_TEXTURE, SCREEN_UV - vec2(o.x, o.y * fy), 0.0).rgb;
	c += vec3(0.75, 0.88, 1.0) * glow * 0.35;
	COLOR = vec4(c, 1.0);
}
"""

var game:Node
var spawn:Node
var cam:Camera = null
var cursor:Spatial = null
var base_fov:float = 70.0
var started:bool = false
var t0:int = 0
var flash:ColorRect
var halo:Control
var glass:Control
var dim:ColorRect       # everything but the cursor and the effects fades out under it
var cur_layer:Control   # the cursor drawn again over the dimming (its texture, size and a short trail)
var cur_mesh:MeshInstance = null
var cur_tex:Texture = null
var cur_col:Color = Color(1, 1, 1)
var cur_trail = []      # recent cursor points on screen
const DIM = 0.93        # how dark the rest gets
const DIM_FROM = 0.15   # s: fading from ...
const DIM_TO = 1.4      # ... to
var ripple:ColorRect
var ripple_copy:BackBufferCopy
var warm_frames:int = 2
var halo_k:float = 0.0
var done:bool = false
var end_at:float = -1.0 # (el when the white-out started)
var rng = RandomNumberGenerator.new()
var hit_p:Vector2 = Vector2.ZERO # the cursor on screen at the last note
var shards = []    # [pos, vel, rot, spin, tilt, tilt_speed, depth, points]
var sparks = []    # [pos, vel, phase]
var cracks = []    # PoolVector2Array polylines
var rain_t:float = 0.0
var chunk_t:float = 0.8
var last_el:float = 0.0

static func live() -> bool:
	return !Rhythia.replaying and !Rhythia.visual_mode and !Rhythia.queue_active

func _ready():
	game = get_parent()
	spawn = game.get_node_or_null("Spawn")
	layer = 97
	pause_mode = PAUSE_MODE_PROCESS
	process_priority = 1000 # (after the run's own camera code)
	rng.randomize()
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	ripple_copy = BackBufferCopy.new()
	ripple_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(ripple_copy)
	ripple = ColorRect.new()
	ripple.anchor_right = 1
	ripple.anchor_bottom = 1
	ripple.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh = Shader.new()
	sh.code = RIPPLE_SHADER
	ripple.material = ShaderMaterial.new()
	ripple.material.shader = sh
	add_child(ripple) # (drawn for the first frames so the shader is compiled under the run's start)
	cur_layer = _layer("_draw_cursor", false)
	glass = _layer("_draw_glass", false)
	halo = _layer("_draw_halo", true)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.anchor_right = 1
	flash.anchor_bottom = 1
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

func _layer(draw_fn:String, additive:bool) -> Control:
	var c = Control.new()
	c.anchor_right = 1
	c.anchor_bottom = 1
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if additive:
		var add = CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		c.material = add
	c.connect("draw", self, draw_fn)
	add_child(c)
	return c

func _process(delta):
	if warm_frames > 0:
		warm_frames -= 1
		if warm_frames == 0 and !started: _ripple_on(false)
	if done or !spawn: return
	if !started:
		if game.ending: # (failed / gave up / ended some other way first)
			done = true
			return
		if game.get("passed") and spawn.ms > game.last_ms + float(spawn.get("hit_window")) and _mp_free():
			_start()
		return
	var el = (OS.get_ticks_usec() - t0) / 1000000.0
	var real_dt = el - last_el
	last_el = el
	if game.ending: # (R held to skip: Game.end runs on its own)
		_finish()
		return
	if el < STOP: Engine.time_scale = 0.0
	elif el < SLOW_UNTIL: Engine.time_scale = SLOW
	else: Engine.time_scale = lerp(SLOW, 1.0, smoothstep(SLOW_UNTIL, SLOW_BACK, el))
	var dt = real_dt * Engine.time_scale # (the shards fall in the slow motion too; frozen in the hit-stop)
	var f = 0.0
	if el < STOP: f = 0.6
	else: f = 0.6 * max(0.0, 1.0 - (el - STOP) / 0.4)
	# the map is over (the song ran out): white-out, then the results
	var music = spawn.get_node_or_null("Music")
	if end_at < 0.0 and el >= HOLD_MIN and (!(music and music.playing) or el >= HOLD_MAX): end_at = el
	if end_at >= 0.0: f = max(f, (el - end_at) / WHITE)
	var wash = 0.0 if end_at >= 0.0 else 0.14 * (1.0 - smoothstep(0.3, 2.2, el)) # (cold light after the flash)
	var fa = clamp(max(f, wash), 0.0, 1.0)
	var blue = clamp(1.0 - f / max(fa, 0.001), 0.0, 1.0)
	flash.color = Color(1.0 - 0.25 * blue, 1.0 - 0.12 * blue, 1.0, fa)
	# the camera pushes in, then eases half way back while the shards fall
	var e = 1.0 - pow(1.0 - min(el / 1.3, 1.0), 3)
	e -= 0.5 * smoothstep(SLOW_UNTIL, SLOW_BACK + 1.0, el)
	if is_instance_valid(cam): cam.fov = base_fov - FOV_PUSH * e
	halo_k = min(1.0, el / 0.25) * (1.0 - smoothstep(1.2, 2.4, el))
	_ripples(el)
	_glass_step(el, dt)
	dim.color.a = DIM * smoothstep(DIM_FROM, DIM_TO, el)
	_cursor_step()
	cur_layer.update()
	halo.update()
	glass.update()
	if end_at >= 0.0 and el - end_at >= WHITE:
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
	cur_mesh = spawn.get_node_or_null("Cursor/Mesh")
	if cur_mesh and cur_mesh.get("material/0") is SpatialMaterial:
		var mt = cur_mesh.get("material/0")
		cur_tex = mt.albedo_texture
		cur_col = mt.albedo_color
		cur_col.a = 1.0
	var vs = glass.rect_size
	hit_p = vs / 2.0
	if is_instance_valid(cursor) and is_instance_valid(cam): hit_p = cam.unproject_position(cursor.global_transform.origin)
	_crack(vs)
	_shatter(vs)
	for i in 90: sparks.append([Vector2(rng.randf() * vs.x, rng.randf() * vs.y), Vector2(rng.randf_range(-12, 12), rng.randf_range(20, 70)), rng.randf() * TAU])
	_ripple_on(true)
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

# ------------------------------------------------------------------ ripple
func _ripple_on(on:bool):
	ripple.visible = on
	ripple_copy.visible = on

func _ripples(el:float):
	var vs = ripple.rect_size
	var m = ripple.material
	m.set_shader_param("center", Vector2(hit_p.x / max(vs.x, 1.0), hit_p.y / max(vs.y, 1.0)))
	m.set_shader_param("aspect", vs.x / max(vs.y, 1.0))
	var r = Vector3(-1, -1, -1)
	var a = Vector3(0, 0, 0)
	var live = false
	for i in 3:
		var k = (el - RIPPLES[i]) / RIPPLE_TIME
		if k <= 0.0 or k >= 1.0: continue
		live = true
		r[i] = 1.6 * (1.0 - pow(1.0 - k, 2.2))
		a[i] = (1.0 - k) * (1.0 if i == 0 else 0.6)
	m.set_shader_param("radius", r)
	m.set_shader_param("amp", a)
	if !live and el > RIPPLES[-1] + RIPPLE_TIME: _ripple_on(false)

# ------------------------------------------------------------------ the cursor over the dimming
func _cursor_step():
	if !is_instance_valid(cursor) or !is_instance_valid(cam): return
	cur_trail.append(cam.unproject_position(cursor.global_transform.origin))
	if cur_trail.size() > 14: cur_trail.remove(0)

func _draw_cursor():
	var k = smoothstep(DIM_FROM, DIM_TO * 0.7, last_el) # (only needed once the rest is dark)
	if k <= 0.0 or cur_trail.empty() or !is_instance_valid(cam): return
	var p = cur_trail[-1]
	var r = cur_layer.rect_size.y * 0.02
	if is_instance_valid(cur_mesh) and cur_mesh.mesh: # (its real size on screen)
		var half = cur_mesh.mesh.get_aabb().size.x * 0.5 * cur_mesh.global_transform.basis.get_scale().x
		r = cam.unproject_position(cursor.global_transform.origin + cam.global_transform.basis.x * half).distance_to(p)
	for i in range(1, cur_trail.size()): # a short trail
		var f = float(i) / cur_trail.size()
		if cur_trail[i - 1].distance_squared_to(cur_trail[i]) < 0.25: continue # (a wide zero-length line fails to draw)
		cur_layer.draw_line(cur_trail[i - 1], cur_trail[i], Color(cur_col.r, cur_col.g, cur_col.b, 0.5 * f * k), max(1.0, r * 0.9 * f))
	var c = Color(cur_col.r, cur_col.g, cur_col.b, k)
	if cur_tex: cur_layer.draw_texture_rect(cur_tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, c)
	else: cur_layer.draw_circle(p, r, c)

# ------------------------------------------------------------------ glass
# cracks out from the cursor: jagged rays to past the screen edge, some branching
func _crack(vs:Vector2):
	var reach = vs.length()
	for i in 11:
		var ang = TAU * (i + rng.randf_range(-0.3, 0.3)) / 11.0
		var p = hit_p
		var line = PoolVector2Array([p])
		var dist = 0.0
		while dist < reach:
			var step = rng.randf_range(0.03, 0.09) * vs.y
			ang += rng.randf_range(-0.35, 0.35)
			p += Vector2(cos(ang), sin(ang)) * step
			dist += step
			line.append(p)
			if rng.randf() < 0.12: # (a branch off this ray)
				var b = PoolVector2Array([p])
				var q = p
				var ba = ang + rng.randf_range(0.5, 1.1) * (1 if rng.randf() < 0.5 else -1)
				for j in rng.randi_range(2, 5):
					ba += rng.randf_range(-0.3, 0.3)
					q += Vector2(cos(ba), sin(ba)) * rng.randf_range(0.03, 0.07) * vs.y
					b.append(q)
				cracks.append(b)
		cracks.append(line)
	# rings round the hit (the spider-web)
	for ring in [0.06, 0.13, 0.22]:
		var r = ring * vs.y
		var a0 = rng.randf() * TAU
		var arc = PoolVector2Array()
		for j in 15:
			if rng.randf() < 0.18 and arc.size() > 1:
				cracks.append(arc)
				arc = PoolVector2Array()
			var a = a0 + TAU * j / 14.0
			arc.append(hit_p + Vector2(cos(a), sin(a)) * r * rng.randf_range(0.85, 1.15))
		if arc.size() > 1: cracks.append(arc)

# the screen breaks: pieces burst out from the hit, then fall
func _shatter(vs:Vector2):
	for i in 34:
		var a = rng.randf() * TAU
		var d = rng.randf_range(0.02, 0.5) * vs.y
		var s = _shard(hit_p + Vector2(cos(a), sin(a)) * d, rng.randf_range(1.1, 2.2), vs)
		s[1] = Vector2(cos(a), sin(a)) * rng.randf_range(120, 520) * s[6] * vs.y / 1080.0 + Vector2(0, -rng.randf_range(0, 200))
		shards.append(s)

func _shard(p:Vector2, depth:float, vs:Vector2, big:bool = false) -> Array:
	var size = (rng.randf_range(1.6, 5.0) if !big else rng.randf_range(15.0, 22.0)) * 0.018 * vs.y * depth
	var n = rng.randi_range(3, 5)
	var angs = []
	for i in n: angs.append(rng.randf() * TAU)
	angs.sort()
	var stretch = rng.randf_range(1.0, 2.6) # (slivers)
	var raw = PoolVector2Array()
	for a in angs: raw.append(Vector2(cos(a) * stretch, sin(a)) * size * rng.randf_range(0.45, 1.0))
	raw.append(Vector2(-stretch, 0.3) * size * 0.8) # (never a sliver of nothing)
	raw.append(Vector2(stretch, -0.3) * size * 0.8)
	var pts = Geometry.convex_hull_2d(raw) # (convex: always draws; the hull comes back closed)
	pts.remove(pts.size() - 1)
	return [p, Vector2(rng.randf_range(-30, 30), rng.randf_range(60, 200)) * depth * vs.y / 1080.0,
		rng.randf() * TAU, rng.randf_range(-1.6, 1.6) / (3.0 if big else 1.0),
		rng.randf() * TAU, rng.randf_range(1.0, 4.0) / (3.0 if big else 1.0), depth, pts]

func _glass_step(el:float, dt:float):
	var vs = glass.rect_size
	var raining = end_at < 0.0
	if raining and el > STOP:
		rain_t += dt * (8.0 + 9.0 * min(el / 3.0, 1.0)) # (shards a second, building up)
		while rain_t >= 1.0:
			rain_t -= 1.0
			var dep = rng.randf_range(0.35, 1.5)
			shards.append(_shard(Vector2(rng.randf() * vs.x, -0.1 * vs.y), dep, vs))
		chunk_t -= dt
		if chunk_t <= 0.0: # a huge chunk close past the camera
			chunk_t = rng.randf_range(1.4, 2.6)
			shards.append(_shard(Vector2(rng.randf_range(0.1, 0.9) * vs.x, -0.45 * vs.y), rng.randf_range(1.6, 2.1), vs, true))
	var g = 700.0 * vs.y / 1080.0
	var keep = []
	for s in shards:
		s[1].y = min(s[1].y + g * s[6] * dt, 900.0 * s[6] * vs.y / 1080.0)
		s[1].x *= 1.0 - 0.6 * dt
		s[0] += s[1] * dt
		s[2] += s[3] * dt
		s[4] += s[5] * dt
		if s[0].y < vs.y * 1.6: keep.append(s)
	shards = keep
	if shards.size() > 260: shards = shards.slice(shards.size() - 260, shards.size() - 1)
	for p in sparks:
		p[0] += p[1] * dt
		p[2] += dt * 5.0
		if p[0].y > vs.y + 4: p[0] = Vector2(rng.randf() * vs.x, -4)

func _draw_glass():
	var el = last_el
	# the cracks: dark lines with a light edge, gone as the pieces fall
	var ca = 1.0 if el < STOP + 0.12 else max(0.0, 1.0 - (el - STOP - 0.12) / 0.9)
	if ca > 0.0:
		for c in cracks:
			glass.draw_polyline(c, Color(0.06, 0.07, 0.2, 0.75 * ca), 3.0)
			glass.draw_polyline(c, Color(0.85, 0.9, 1.0, 0.7 * ca), 1.0)
	# far shards first (smaller, dimmer)
	shards.sort_custom(self, "_by_depth")
	for s in shards:
		var cs = cos(s[4]) # (tumbling: the pane turns edge-on and back)
		var glint = pow(abs(cs), 10.0)
		var tf = Transform2D(s[2], s[0])
		var pts = PoolVector2Array()
		for q in s[7]: pts.append(tf.xform(Vector2(q.x * (0.15 + 0.85 * abs(cs)), q.y)))
		var a = clamp(0.7 + 0.3 * s[6], 0.6, 1.0)
		var cols = PoolColorArray()
		for q in pts: # (sky in the glass: lighter towards the top of each pane)
			var up = clamp((q.y - s[0].y) / 80.0, -1.0, 1.0)
			cols.append(Color(0.8 - 0.12 * up + 0.2 * glint, 0.88 - 0.08 * up + 0.12 * glint, 1.0, (0.42 + 0.45 * glint) * a))
		VisualServer.canvas_item_add_triangle_array(glass.get_canvas_item(), _fan(pts.size()), pts, cols) # (convex: a fan, no triangulation to fail)
		pts.append(pts[0])
		glass.draw_polyline(pts, Color(0.1, 0.12, 0.32, 0.55 * a), 2.0)
		glass.draw_polyline(pts, Color(0.95, 0.98, 1.0, (0.6 + 0.4 * glint) * a), 2.0)
	for p in sparks: # glitter
		var tw = 0.5 + 0.5 * sin(p[2])
		if tw > 0.35: glass.draw_rect(Rect2(p[0], Vector2(2, 2)), Color(1, 1, 1, 0.75 * tw * min(1.0, el / 0.3)))

func _by_depth(a, b): return a[6] < b[6]

var fans = {}
func _fan(n:int) -> PoolIntArray:
	if !fans.has(n):
		var ix = PoolIntArray()
		for i in range(1, n - 1): ix.append_array([0, i, i + 1])
		fans[n] = ix
	return fans[n]

# a soft white bloom on the cursor (additive rings) and a beam of light through it
func _draw_halo():
	if halo_k > 0.0:
		var r = halo.rect_size.y * 0.09 * (0.6 + 0.4 * halo_k)
		for i in 8:
			var k = float(i + 1) / 8.0
			halo.draw_circle(hit_p, r * k, Color(1.0, 0.95, 0.8, 0.07 * halo_k))
	var el = last_el
	var bk = (min(1.0, el / 0.06) if el < 0.06 else max(0.0, 1.0 - (el - 0.06) / 1.4))
	if bk > 0.0:
		var h = halo.rect_size.y
		var w = halo.rect_size.x * 0.07 * (0.3 + 0.7 * bk)
		for i in 7:
			var k = float(i + 1) / 7.0
			halo.draw_rect(Rect2(hit_p.x - w * k, 0, w * 2.0 * k, h), Color(0.8, 0.85, 1.0, 0.09 * bk))

# ------------------------------------------------------------------ the clear sound
# a low impact under a bright fifth / octave bloom with a sparkle on top, then a ping-pong echo
# (left / right, each repeat darker) that rings out for ~3 s (made once on a worker while a map
# loads; ~4.4 s stereo at 22 kHz)
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
	var m = int(rate * 4.4)
	var x = PoolRealArray()
	x.resize(m)
	var rng = RandomNumberGenerator.new()
	rng.seed = 77
	var freqs = [261.63, 392.0, 523.25, 784.0, 1046.5] # C4 G4 C5 G5 C6: open fifths, no third (sits over any key)
	var amps = [0.22, 0.2, 0.2, 0.14, 0.1]
	var ph = [0.0, 0.0, 0.0, 0.0, 0.0]
	var thump = 0.0
	var lp = 0.0
	for i in m:
		if i >= n:
			x[i] = 0.0
			continue
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
		v *= 1.0 - smoothstep(1.2, 1.4, t)
		x[i] = v
	# ping-pong delay: the first repeat on the right, then left, ...; each one through a low-pass
	var d = int(rate * 0.3)
	var fb = 0.62
	var wet = 0.8
	var L = PoolRealArray()
	var R = PoolRealArray()
	L.resize(m)
	R.resize(m)
	var lpl = 0.0
	var lpr = 0.0
	var data = PoolByteArray()
	data.resize(m * 4)
	for i in m:
		var fromR = R[i - d] if i >= d else 0.0
		var fromL = L[i - d] if i >= d else 0.0
		lpl += (fromR - lpl) * 0.5
		lpr += (fromL - lpr) * 0.5
		L[i] = x[i] + fb * lpl
		R[i] = fb * lpr
		var tail = 1.0 - smoothstep(4.1, 4.4, float(i) / rate)
		var outs = [x[i] + wet * (L[i] - x[i]) * tail, x[i] + wet * R[i] * tail]
		for c in 2:
			var s16 = int(clamp(outs[c], -1.0, 1.0) * 26000.0)
			if s16 < 0: s16 += 65536
			data[i * 4 + c * 2] = s16 & 0xff
			data[i * 4 + c * 2 + 1] = (s16 >> 8) & 0xff
	var s = AudioStreamSample.new()
	s.format = AudioStreamSample.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = true
	s.data = data
	return s
