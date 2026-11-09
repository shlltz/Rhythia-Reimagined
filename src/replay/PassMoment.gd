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
const HOLD_FILL = 0.6  # s of holding R to skip (as the run's give-up)
const HOLD_DROP = 0.4  # s the speed-up takes to ease off again once R is let go
const SKIP_FALL = 0.1  # s it keeps dropping once full, before the white-out
const SKIP_SPEED = 3.5 # how much faster the glass falls with R held all the way
const FOV_PUSH = 14.0  # degrees the camera pushes in
const INVERT = 0.05    # s of impact frame (negative) on the hit, before the white flash
const PUNCH = 9.0      # degrees of a sharp zoom kick on the hit (springs back into the slow push)
const SHAKE = 0.16     # camera shake on the hit (world units), dying away fast
const RIPPLES = [0.0, 0.16, 0.34] # s: three rings out from the cursor
const RIPPLE_TIME = 1.1

const RIPPLE_SHADER = """shader_type canvas_item;
uniform vec2 center = vec2(0.5);   // (in this rect's UV: top-down)
uniform float aspect = 1.7778;
uniform vec3 radius = vec3(-1.0);  // per ring, in screen heights
uniform vec3 amp = vec3(0.0);
uniform float invert = 0.0;        // the impact frame: the scene as a negative
uniform float split = 0.0;         // colour split along the rings
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
	vec2 su = SCREEN_UV - vec2(o.x, o.y * fy);
	vec2 cs = vec2(dir.x, dir.y * fy) * (glow * split + split * 0.3) * 0.012;
	vec3 c;
	c.r = textureLod(SCREEN_TEXTURE, su + cs, 0.0).r;
	c.g = textureLod(SCREEN_TEXTURE, su, 0.0).g;
	c.b = textureLod(SCREEN_TEXTURE, su - cs, 0.0).b;
	c += vec3(0.75, 0.88, 1.0) * glow * 0.35;
	c = mix(c, vec3(1.0) - c, invert);
	COLOR = vec4(c, 1.0);
}
"""

# the glass panes: what's behind bent through the pane (a little colour split), a bright sky reflected
# in it that shifts as the pane tumbles (more of it the more the pane is tilted), a specular streak
# sweeping across as it turns to face the light. Per pane data rides in the vertex colour: r, g = the
# reflection's offset (its tilt), b = glint, a = opacity; UV = the point's place across the pane.
# UV.x < 0: the bevelled rim, drawn as its plain vertex colour.
const GLASS_SHADER = """shader_type canvas_item;
uniform float aspect = 1.7778;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
vec3 sky(vec2 p) { // (y down: bright high up, deeper blue below, soft clouds)
	float up = clamp(1.0 - p.y * 0.9, 0.0, 1.0);
	vec3 c = mix(vec3(0.42, 0.46, 0.55), vec3(0.88, 0.9, 0.95), up);
	return c;
}
void fragment() {
	if (UV.x < -0.5) {
		COLOR = COLOR;
	} else {
		vec2 tilt = COLOR.rg * 2.0 - 1.0;
		float glint = COLOR.b;
		float fy = sign(dFdy(SCREEN_UV.y)) * sign(dFdy(UV.y) + 1e-6); // (SCREEN_UV may run bottom-up)
		vec2 sp = vec2(SCREEN_UV.x, fy > 0.0 ? SCREEN_UV.y : 1.0 - SCREEN_UV.y); // (y down)
		// behind the pane, bent like through thick glass, the colours a little apart
		vec2 bend = (UV - 0.5) * vec2(0.035, 0.035) + tilt * 0.01;
		vec2 b = vec2(bend.x, bend.y * fy);
		vec3 behind;
		behind = textureLod(SCREEN_TEXTURE, SCREEN_UV + b, 0.0).rgb;
		// the sky in it: moves with the pane's tilt, not with the screen only
		vec3 refl = sky(vec2(sp.x * aspect, sp.y) * 0.7 + tilt * 0.9 + UV * 0.18);
		float fres = clamp(0.04 + 0.16 * dot(tilt, tilt) + 0.16 * glint, 0.0, 0.4); // (more mirror the more it's tilted)
		// the specular streak: a diagonal band whose place follows the turn
		float d = UV.x * 0.75 + UV.y * 0.45 - (0.15 + 0.9 * (tilt.y * 0.5 + 0.5));
		float streak = exp(-d * d * 1400.0) * (0.25 + 0.5 * glint); // (one fine line of light)
		vec3 col = behind * vec3(0.88, 0.94, 1.0) * (1.0 - fres * 0.5) + refl * fres + vec3(streak); // (clear: the scene shows through, the sky on top)
		COLOR = vec4(min(col, vec3(1.0)), COLOR.a);
	}
}
"""

var game:Node
var spawn:Node
var cam:Camera = null
var cursor:Spatial = null
var base_fov:float = 70.0
var base_h:float = 0.0
var base_v:float = 0.0
var started:bool = false
var t0:int = 0
var flash:ColorRect
var halo:Control
var glass:Control
var glass_copy:BackBufferCopy
var crack_layer:Control
var spark_layer:Control
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
var skipping:bool = false
var hold:float = 0.0    # 0..1: how long R has been held (towards the skip)
var skip_k:float = 0.0  # 0..1: how far the speed-up has built
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
	crack_layer = _layer("_draw_cracks", false)
	glass_copy = BackBufferCopy.new() # (the panes see what's under them)
	glass_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(glass_copy)
	glass = _layer("_draw_glass", false)
	glass.material = ShaderMaterial.new()
	glass.material.shader = Shader.new()
	glass.material.shader.code = GLASS_SHADER
	spark_layer = _layer("_draw_sparks", false)
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
		glass.update() # (the glass shader is compiled under the run's start too)
		glass_copy.visible = warm_frames > 0 or !shards.empty()
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
	if game.ending: # (ended some other way: Game.end runs on its own)
		_finish()
		return
	# hold R to skip: while it's held the glass falls faster and faster (slow motion easing out);
	# let go before it's full and it eases back down; full: the white-out into the results
	game.giving_up = 0.0 # (the run's own hold-to-give-up is this now)
	if !skipping and end_at < 0.0 and el > STOP:
		if Input.is_action_pressed("give_up"): hold = min(1.0, hold + real_dt / HOLD_FILL)
		else: hold = max(0.0, hold - real_dt / HOLD_DROP)
		if hold >= 1.0:
			skipping = true
			end_at = el + SKIP_FALL
	var ts = 1.0 # (the moment's own time scale)
	if el < STOP: ts = 0.0
	elif el < SLOW_UNTIL: ts = SLOW
	else: ts = lerp(SLOW, 1.0, smoothstep(SLOW_UNTIL, SLOW_BACK, el))
	skip_k = 1.0 if skipping else smoothstep(0.0, 1.0, hold)
	Engine.time_scale = lerp(ts, 1.0, skip_k)
	var dt = real_dt * lerp(ts, SKIP_SPEED, skip_k * skip_k) # (the shards fall in the slow motion too; frozen in the hit-stop)
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
	var kick = PUNCH * (1.0 if el < STOP else exp(-(el - STOP) * 9.0) * cos((el - STOP) * 14.0)) # (a kick that springs back)
	var sh = SHAKE * exp(-el * 6.0) * (1.0 - skip_k)
	if is_instance_valid(cam):
		cam.fov = base_fov - FOV_PUSH * e - kick
		cam.h_offset = base_h + sh * (sin(el * 91.0) + 0.5 * sin(el * 157.0))
		cam.v_offset = base_v + sh * (cos(el * 83.0) + 0.5 * sin(el * 131.0))
	ripple.material.set_shader_param("invert", 1.0 if el < INVERT else 0.0)
	ripple.material.set_shader_param("split", max(0.0, 1.0 - el / 0.8))
	halo_k = min(1.0, el / 0.25) * (1.0 - smoothstep(1.2, 2.4, el))
	_ripples(el)
	_glass_step(el, dt)
	dim.color.a = DIM * smoothstep(DIM_FROM, DIM_TO, el)
	_cursor_step()
	cur_layer.update()
	halo.update()
	glass.update()
	crack_layer.update()
	spark_layer.update()
	glass_copy.visible = !shards.empty()
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
	if cam:
		base_fov = cam.fov
		base_h = cam.h_offset
		base_v = cam.v_offset
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
	for i in 40: sparks.append([Vector2(rng.randf() * vs.x, rng.randf() * vs.y), Vector2(rng.randf_range(-12, 12), rng.randf_range(20, 70)), rng.randf() * TAU])
	_ripple_on(true)
	_take_sound()
	if Engine.has_meta("rr_clear_sfx"):
		var p = AudioStreamPlayer.new()
		p.stream = Engine.get_meta("rr_clear_sfx")
		p.bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
		p.volume_db = -3.0 # (the sound is made 0.65x: the same loudness, no clipping)
		add_child(p)
		p.play()

func _finish():
	done = true
	Engine.time_scale = 1.0
	if is_instance_valid(cam):
		cam.h_offset = base_h
		cam.v_offset = base_v

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
	var lo = Vector2(1e9, 1e9)
	var hi = -lo
	for q in pts:
		lo = Vector2(min(lo.x, q.x), min(lo.y, q.y))
		hi = Vector2(max(hi.x, q.x), max(hi.y, q.y))
	var uvs = PoolVector2Array()
	for q in pts: uvs.append((q - lo) / (hi - lo))
	return [p, Vector2(rng.randf_range(-30, 30), rng.randf_range(60, 200)) * depth * vs.y / 1080.0,
		rng.randf() * TAU, rng.randf_range(-1.6, 1.6) / (3.0 if big else 1.0),
		rng.randf() * TAU, rng.randf_range(1.0, 4.0) / (3.0 if big else 1.0), depth, pts, uvs]

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
	var g = 700.0 * vs.y / 1080.0 * (1.0 + 3.0 * skip_k)
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

func _draw_cracks():
	var el = last_el
	# the cracks: dark lines with a light edge, gone as the pieces fall
	var ca = 1.0 if el < STOP + 0.12 else max(0.0, 1.0 - (el - STOP - 0.12) / 0.9)
	if ca > 0.0:
		for c in cracks:
			crack_layer.draw_polyline(c, Color(0.9, 0.93, 1.0, 0.55 * ca), 1.0) # (hairlines)

const LIGHT = Vector2(-0.6, -0.8) # (from the top left)
func _draw_glass():
	glass.material.set_shader_param("aspect", glass.rect_size.x / max(glass.rect_size.y, 1.0))
	var ci = glass.get_canvas_item()
	if warm_frames > 0 and shards.empty(): # (a speck, to compile the shader before it's needed)
		VisualServer.canvas_item_add_triangle_array(ci, PoolIntArray([0, 1, 2]), PoolVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]), PoolColorArray([Color(0.5, 0.5, 0, 0.01), Color(0.5, 0.5, 0, 0.01), Color(0.5, 0.5, 0, 0.01)]), PoolVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	shards.sort_custom(self, "_by_depth") # far shards first (smaller, dimmer)
	for s in shards:
		var cs = cos(s[4]) # (tumbling: the pane turns edge-on and back)
		var glint = pow(abs(cs), 10.0)
		var tf = Transform2D(s[2], s[0])
		var pts = PoolVector2Array()
		for q in s[7]: pts.append(tf.xform(Vector2(q.x * (0.15 + 0.85 * abs(cs)), q.y)))
		var a = clamp(0.4 + 0.2 * s[6], 0.4, 0.62) # (see-through: was 0.6-0.97)
		var body = Color(0.5 + 0.5 * sin(s[4]), 0.5 + 0.5 * sin(s[2] * 0.7 + s[4] * 0.5), glint, a)
		var cols = PoolColorArray()
		for q in pts: cols.append(body)
		VisualServer.canvas_item_add_triangle_array(ci, _fan(pts.size()), pts, cols, s[8]) # (convex: a fan)
		# the rim: an inner bevel, bright on the edges that face the light, dark on the others
		var c = Vector2.ZERO
		for q in pts: c += q
		c /= pts.size()
		var w = (0.8 + 0.6 * s[6]) * (0.5 + 0.5 * abs(cs)) # (a thin rim)
		var rp = PoolVector2Array()
		var rc = PoolColorArray()
		var ru = PoolVector2Array()
		var ri = PoolIntArray()
		for k in pts.size():
			var p0 = pts[k]
			var p1 = pts[(k + 1) % pts.size()]
			var n = (p1 - p0).tangent().normalized()
			if n.dot((p0 + p1) * 0.5 - c) < 0.0: n = -n
			var lit = n.dot(LIGHT)
			var col = Color(1, 1, 1, (0.5 + 0.4 * glint) * a) if lit > 0.0 else Color(0.85, 0.88, 0.95, 0.18 * a)
			col.a *= 0.45 + 0.55 * abs(lit)
			var b = rp.size()
			for q in [p0, p1, p1 - n * w, p0 - n * w]:
				rp.append(q)
				rc.append(col)
				ru.append(Vector2(-1, -1))
			ri.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
		VisualServer.canvas_item_add_triangle_array(ci, ri, rp, rc, ru)

func _draw_sparks():
	var el = last_el
	for p in sparks: # glitter
		var tw = 0.5 + 0.5 * sin(p[2])
		if tw > 0.35: spark_layer.draw_rect(Rect2(p[0], Vector2(1.5, 1.5)), Color(1, 1, 1, 0.5 * tw * min(1.0, el / 0.3)))

func _by_depth(a, b): return a[6] < b[6]

var fans = {}
func _fan(n:int) -> PoolIntArray:
	if !fans.has(n):
		var ix = PoolIntArray()
		for i in range(1, n - 1): ix.append_array([0, i, i + 1])
		fans[n] = ix
	return fans[n]

# a soft white bloom on the cursor and a beam of light through the hit: smooth gradients (meshes with
# a gaussian falloff in their vertex colours, additive), not stacked shapes
func _draw_halo():
	var ci = halo.get_canvas_item()
	if halo_k > 0.0:
		var p = cur_trail[-1] if !cur_trail.empty() else hit_p
		_glow_disc(ci, p, halo.rect_size.y * 0.1 * (0.6 + 0.4 * halo_k), Color(1.0, 0.95, 0.82, 0.5 * halo_k))
	var el = last_el
	var bk = (min(1.0, el / 0.06) if el < 0.06 else max(0.0, 1.0 - (el - 0.06) / 1.4))
	if bk > 0.0:
		bk = bk * bk * (3.0 - 2.0 * bk)
		_glow_beam(ci, hit_p.x, halo.rect_size.x * 0.06 * (0.3 + 0.7 * bk), halo.rect_size.y, Color(0.8, 0.86, 1.0, 0.6 * bk))

const GLOW_STEPS = 14
func _falloff(k:float) -> float: # (k 0 = the middle, 1 = the edge: gaussian, reaching 0 at the edge)
	return max(0.0, exp(-k * k * 4.0) - exp(-4.0)) / (1.0 - exp(-4.0))

func _glow_beam(ci:RID, x:float, half:float, h:float, c:Color):
	var pts = PoolVector2Array()
	var cols = PoolColorArray()
	var ix = PoolIntArray()
	var n = GLOW_STEPS * 2
	for i in n + 1:
		var u = float(i) / n * 2.0 - 1.0 # (-1 .. 1 across)
		var col = Color(c.r, c.g, c.b, c.a * _falloff(abs(u)))
		for y in [0.0, h]:
			pts.append(Vector2(x + u * half, y))
			cols.append(col)
		if i > 0:
			var b = i * 2
			ix.append_array([b - 2, b - 1, b, b - 1, b + 1, b])
	VisualServer.canvas_item_add_triangle_array(ci, ix, pts, cols)

func _glow_disc(ci:RID, p:Vector2, r:float, c:Color):
	var seg = 40
	var pts = PoolVector2Array([p])
	var cols = PoolColorArray([c])
	var ix = PoolIntArray()
	for ring in range(1, GLOW_STEPS + 1):
		var k = float(ring) / GLOW_STEPS
		var col = Color(c.r, c.g, c.b, c.a * _falloff(k))
		for j in seg:
			var a = TAU * j / seg
			pts.append(p + Vector2(cos(a), sin(a)) * r * k)
			cols.append(col)
	for j in seg: # (the centre fan)
		ix.append_array([0, 1 + j, 1 + (j + 1) % seg])
	for ring in range(1, GLOW_STEPS):
		var a0 = 1 + (ring - 1) * seg
		var b0 = a0 + seg
		for j in seg:
			var j2 = (j + 1) % seg
			ix.append_array([a0 + j, b0 + j, b0 + j2, a0 + j, b0 + j2, a0 + j2])
	VisualServer.canvas_item_add_triangle_array(ci, ix, pts, cols)

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
	var boom = 0.0
	var lp = 0.0
	var hp_prev = 0.0
	var hp = 0.0
	# glass breaking: a crunch, then shards tinkling (short high pings, most of them early)
	var pings = []
	for k in 46:
		var r = rng.randf()
		pings.append([0.012 + 0.75 * r * r, rng.randf_range(2300.0, 6800.0), rng.randf_range(0.035, 0.1) * (1.0 - 0.6 * r), rng.randf_range(28.0, 60.0), rng.randf() * TAU])
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
		boom += TAU * (38.0 + 30.0 * exp(-t * 10.0)) / rate # (a deep boom under it, longer)
		v += sin(boom) * 0.42 * exp(-t * 3.2)
		var wn = rng.randf() * 2.0 - 1.0
		hp = 0.86 * (hp + wn - hp_prev) # (high-passed noise: the crunch)
		hp_prev = wn
		v += hp * 0.3 * exp(-t * 22.0) * min(1.0, t * 900.0)
		for pg in pings:
			var dtp = t - pg[0]
			if dtp >= 0.0 and dtp < 0.14: v += sin(pg[4] + TAU * pg[1] * dtp) * pg[2] * exp(-dtp * pg[3])
		lp += ((rng.randf() * 2.0 - 1.0) - lp) * 0.6
		v += lp * 0.12 * exp(-t * 14.0) # (a bright sparkle at the hit)
		v *= min(1.0, t * 600.0) * 0.65 # (peaks just under full scale with the boom + glass)
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
