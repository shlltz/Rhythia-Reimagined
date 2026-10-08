extends Control
# Map-page effects:
# - the cover art is an audio visualizer: it pulses with the bass and spectrum bars grow out of
#   its four edges
# - maps above 10 stars: cover + Start quake, lightning strikes the cover when the map is
#   selected / Start is clicked (soft: no flicker, no screen flash); hovering Start dims everything
#   else while Start shakes and glows
# - maps above 10 stars: chromatic aberration over the whole screen (stronger on the beat and
#   while Start is hovered) and glitch bursts on the cover art and the selected map's card
# - maps from 7 stars: glow along the left and right screen edges in the star colour, pulsing
#   with the bass (full strength at 10+)
# Lives as a full-screen top-level overlay child of SongInfoScreen (mouse ignored).

const HYPE_STARS = 10.0
const GLOW_FROM = 7.0       # side glow starts here, full at HYPE_STARS
const COVER_SCALE = 0.78    # cover drawn smaller so the spectrum bars have room
const BOLT_LIFE = 0.6
const BOLT = Color(0.75, 0.88, 1.0)
const GLOW = Color(0.55, 0.8, 1.0)

var page:Control
var cache = null
var song = null
var stars:float = -1.0
var hype:bool = false
var bass:float = 0.0
var t:float = 0.0
var kick:float = 0.0          # extra shake after a strike, decays
var flash:float = 0.0
var gate:float = 0.0         # 1 while the map's own song plays (not the menu background music)
var surge:float = 0.0        # burst after a speed mod raises the rating, decays
var accents = null           # map rhythm from StarCache.get_onsets: [ms, strength, ...]
var acc_i:int = 0
var last_heard:float = -1.0
var punch:float = 0.0        # 1 on a detected beat (kick), decays fast: the cover "hits"
var bass_avg:float = 0.0     # slow average of the bass, beats = jumps above it
var beat_cd:float = 0.0
var bass_prev:float = 0.0
var tilt_dir:float = 1.0
var side:float = 0.0         # side glow envelope (fast up, slow down)
var dim:float = 0.0
var bolts:Array = []          # [points, branches, age]
var strike_queue:Array = []   # seconds until the next strike
var shake_last:Dictionary = {} # node -> [offset applied, position we left it at]
var viz:Control = null
var run_hover:bool = false

func _ready():
	page = get_parent()
	set_as_toplevel(true)
	mouse_filter = MOUSE_FILTER_IGNORE
	VisualServer.canvas_item_set_z_as_relative_to_parent(get_canvas_item(), false)
	VisualServer.canvas_item_set_z_index(get_canvas_item(), 2) # above the bottom visualizer + sidebar
	cache = load("res://mods/stars/StarCache.gd").get_instance(get_tree())
	Rhythia.connect("selected_song_changed", self, "_on_song")

func _cover():
	var c = page.get_node_or_null("RS/H1/Right/ButtonDisp")
	return c if c else page.get_node_or_null("RS/H1/ButtonDisp")

# the map page's preview player (PreviewMusic/Song); the menu music is PreviewMusic/MenuSong
# first accent at or after `ms`
func _acc_index(ms:float) -> int:
	var lo = 0
	var hi = accents.size() / 2
	while lo < hi:
		var m = (lo + hi) / 2
		if accents[m * 2] < ms: lo = m + 1
		else: hi = m
	return lo

func _map_song_playing() -> bool:
	var p = page.ctrl_box.get_node_or_null("PreviewMusic/Song")
	return p != null and p.playing and !p.stream_paused

func _run():
	return page.run_btn

func _on_song(_s = null):
	song = Rhythia.selected_song
	stars = -1.0
	hype = false
	accents = null
	acc_i = 0
	_check_stars()

func _check_stars():
	if song == null or !cache: return
	var b = page.get("star_badge") # rating at the current speed (speed mods raise / lower it)
	var s = b.stars if b and b.song == song and b.stars >= 0 else cache.get_stars(song)
	if s == stars: return
	if stars >= 0 and s > stars + 0.005: # sped up: power surge
		surge = 1.0
		kick = max(kick, 0.5)
	var was = hype
	stars = s
	hype = stars > HYPE_STARS
	if hype and !was: _strikes([0.0]) # selected (or sped up past) a 10+ map

func _strikes(times:Array):
	for x in times: strike_queue.append(x)

func _input(e):
	if hype and e is InputEventMouseButton and e.pressed and e.button_index == BUTTON_LEFT:
		var r = _run()
		if r and r.is_visible_in_tree() and r.get_global_rect().has_point(e.position): _strikes([0.0])

func _process(delta):
	t += delta
	rect_position = Vector2.ZERO
	rect_size = get_viewport_rect().size
	var shown = page.is_visible_in_tree()
	if !shown:
		visible = false
		_fx_off()
		return
	visible = true
	if song != Rhythia.selected_song: _on_song()
	_check_stars()
	var e = 0.0
	var vis = get_tree().root.get_node_or_null("Menu/AudioVisualizer")
	if vis and vis.mags.size() > 8 and vis.ceiling > 0:
		for i in 6: e += vis.mags[i]
		e = clamp(e / 6.0 / vis.ceiling, 0.0, 1.0)
	gate = lerp(gate, 1.0 if _map_song_playing() else 0.0, 1.0 - exp(-delta * 8.0))
	e *= gate
	bass = max(e, bass - delta * 3.0)
	# the hit: the map's own notes (mapped to the music) at the moment you hear them -
	# preview position + time since the last mix - output latency. Spectrum guessing only as a
	# fallback while the note times load.
	if accents == null and song: accents = cache.get_onsets(song)
	var pl = page.ctrl_box.get_node_or_null("PreviewMusic/Song")
	if accents != null and accents.size() > 0 and pl and pl.playing and !pl.stream_paused:
		var heard = (pl.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()) * 1000.0
		if heard < last_heard - 60.0 or heard > last_heard + 1000.0: acc_i = _acc_index(heard) # seek / loop / restart
		last_heard = heard
		while acc_i * 2 < accents.size() and accents[acc_i * 2] <= heard:
			if heard - accents[acc_i * 2] < 120.0:
				punch = max(punch, accents[acc_i * 2 + 1])
				if accents[acc_i * 2 + 1] >= 1.0: tilt_dir = -tilt_dir
			acc_i += 1
	var raw = 0.0
	if vis and vis.mags.size() > 8:
		for i in 4: raw += vis.mags[i]
	var rising = raw - bass_prev
	bass_prev = raw
	bass_avg = lerp(bass_avg, raw, 1.0 - exp(-delta * 3.0))
	beat_cd -= delta
	if (accents == null or accents.size() == 0) and gate > 0.5 and raw > bass_avg * 1.15 and rising > 0.0 and e > 0.25 and beat_cd <= 0.0:
		punch = 1.0
		beat_cd = 0.15
		tilt_dir = -tilt_dir
	punch *= exp(-delta * 11.0) # (short and sharp: a hit, not a swell)
	side = max(max(e, punch * 0.9), side - delta * 1.6)
	var cover = _cover()
	var run = _run()
	if cover and !viz:
		viz = CoverViz.new()
		viz.hype = self
		cover.add_child(viz)
	# strikes
	for i in range(strike_queue.size() - 1, -1, -1):
		strike_queue[i] -= delta
		if strike_queue[i] <= 0:
			strike_queue.remove(i)
			if cover: _bolt(cover.get_global_rect())
	for b in bolts: b[2] += delta
	while bolts.size() > 0 and bolts[0][2] > BOLT_LIFE: bolts.pop_front()
	flash = max(0.0, flash - delta * 2.5)
	kick = max(0.0, kick - delta * 2.2)
	surge = max(0.0, surge - delta / 1.2)
	run_hover = hype and run and run.is_visible_in_tree() and !run.disabled and run.get_global_rect().has_point(get_viewport().get_mouse_position())
	dim = lerp(dim, 1.0 if run_hover else 0.0, 1.0 - exp(-delta * 10.0))
	# cover: pulse with the bass, quake on hype maps
	if cover:
		cover.rect_pivot_offset = cover.rect_size / 2
		var s = COVER_SCALE * (1.0 + bass * 0.012 + 0.08 * surge * surge) # (steady bob kept small: the hits carry the beat)
		s *= 1.0 + 0.11 * punch # the hit
		cover.rect_scale = Vector2(s, s)
		_shake(cover, (2.0 + bass * 3.0 + kick * 5.0) if hype else 0.0)
		cover.rect_rotation += tilt_dir * 1.4 * punch * punch # alternating little tilt per beat
		var f = 1.0 + 0.45 * punch # flash brighter on the beat
		cover.modulate = Color(f, f, f, cover.modulate.a)
	_fx(delta, cover)
	if run:
		run.rect_pivot_offset = run.rect_size / 2
		_shake(run, (1.5 + bass * 2.0 + kick * 3.0 + dim * 2.5) if hype else 0.0, false)
		if hype: # a little zoom while hovered (follows the dim; UIJuice's hover spring is skipped on hype maps)
			if !run.has_meta("rr_no_juice"): run.set_meta("rr_no_juice", true)
			var z = 1.0 + 0.07 * dim + 0.015 * punch * dim
			run.rect_scale = Vector2(z, z)
		elif run.has_meta("rr_no_juice"):
			run.remove_meta("rr_no_juice")
			run.rect_scale = Vector2.ONE
	update()

# ------------------------------------------------------------------ 10+ star screen fx
# Chromatic aberration: a CanvasLayer above the menu with a full-screen SCREEN_TEXTURE shader that
# pulls red / blue apart (more at the screen edges). Glitch: an overlay on the cover and on the
# selected map card that slices the picture into shifted bands with an RGB split, in short random
# bursts and on strong beats. Each overlay sits after a BackBufferCopy so it reads the screen as
# it is right there (one shared screen copy would miss whatever drew after it).
const CHROMA_SHADER = """shader_type canvas_item;
uniform float amount = 0.0; // px at the screen edge
uniform float tear = 0.0;   // 0..1 horizontal tearing during glitch bursts
float hash(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	float line = floor(uv.y * 90.0);
	uv.x += (hash(line + floor(TIME * 24.0)) - 0.5) * tear * 0.012 * step(0.82, hash(line * 3.7 + floor(TIME * 24.0)));
	vec2 d = uv - vec2(0.5);
	vec2 dir = d / max(length(d), 0.0001);
	vec2 off = dir * SCREEN_PIXEL_SIZE * amount * (0.25 + length(d) * 1.5);
	vec4 c = textureLod(SCREEN_TEXTURE, uv, 0.0);
	c.r = textureLod(SCREEN_TEXTURE, uv + off, 0.0).r;
	c.b = textureLod(SCREEN_TEXTURE, uv - off, 0.0).b;
	COLOR = vec4(c.rgb, 1.0);
}"""
const GLITCH_SHADER = """shader_type canvas_item;
uniform float power = 0.0; // 0..1
uniform vec2 size = vec2(300.0, 300.0); // overlay size in px (shifts are a share of the width)
uniform float seed = 0.0;
float hash(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	float tick = floor(TIME * 20.0) + seed;
	float band = floor(UV.y * 16.0 + hash(tick) * 3.0);
	float on = step(1.0 - power * 0.55, hash(band * 7.13 + tick));
	float shift = (hash(band * 1.7 + tick * 3.1) - 0.5) * 0.14 * on * power;
	vec2 uv = SCREEN_UV + vec2(shift * size.x * SCREEN_PIXEL_SIZE.x, 0.0);
	vec2 split = vec2((3.0 + 6.0 * on) * power * SCREEN_PIXEL_SIZE.x, 0.0);
	vec4 c = textureLod(SCREEN_TEXTURE, uv, 0.0);
	c.r = textureLod(SCREEN_TEXTURE, uv + split, 0.0).r;
	c.b = textureLod(SCREEN_TEXTURE, uv - split, 0.0).b;
	float blk = step(1.0 - power * 0.12, hash(floor(UV.x * 9.0) + floor(UV.y * 7.0) * 13.0 + tick * 1.7));
	c.rgb = mix(c.rgb, vec3(1.0) - c.rgb, blk * 0.65);
	float scan = 1.0 - power * 0.18 * step(0.5, fract(UV.y * size.y * 0.25));
	COLOR = vec4(c.rgb * scan, 1.0);
}"""
var fx_layer:CanvasLayer = null
var chroma:ColorRect = null
var fx_k:float = 0.0        # 0..1, fades in on hype maps
var glitch:float = 0.0      # current burst strength
var glitch_next:float = 1.0 # seconds to the next random burst
var glitch_left:float = 0.0
var fx_cover = null         # [BackBufferCopy, overlay] on the cover
var fx_card = null          # [BackBufferCopy, overlay, card] on the selected map card

func _fx_overlay(parent:Control, sd:float) -> Array:
	var bb = BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	parent.add_child(bb)
	var o = ColorRect.new()
	o.mouse_filter = MOUSE_FILTER_IGNORE
	o.anchor_right = 1
	o.anchor_bottom = 1
	o.material = ShaderMaterial.new()
	o.material.shader = Shader.new()
	o.material.shader.code = GLITCH_SHADER
	o.material.set_shader_param("seed", sd)
	parent.add_child(o)
	return [bb, o]

func _fx_free(a):
	if a == null: return
	for n in a:
		if n is Node and is_instance_valid(n) and n.get_parent() and (n is BackBufferCopy or n is ColorRect): n.queue_free()

func _fx_off():
	fx_k = 0.0
	if chroma: chroma.visible = false
	_fx_free(fx_cover); fx_cover = null
	_fx_free(fx_card); fx_card = null

func _map_card():
	var ml = get_tree().root.get_node_or_null("Menu/Main/Maps/MapRegistry/S/VBoxContainer")
	if !ml or !ml.is_visible_in_tree(): return null
	for b in ml.get("btns") if ml.get("btns") != null else []:
		if is_instance_valid(b) and b.get("song") == song and b.is_visible_in_tree(): return b
	return null

func _fx(delta:float, cover):
	fx_k = move_toward(fx_k, 1.0 if hype else 0.0, delta / (0.5 if hype else 0.3))
	if fx_k <= 0.0:
		_fx_off()
		return
	# glitch bursts: random ones every 0.7-2.6 s, and one on every strong beat
	glitch_next -= delta
	if glitch_next <= 0.0:
		glitch_next = rand_range(0.7, 2.6)
		glitch_left = rand_range(0.07, 0.22)
	if punch > 0.85 and glitch_left <= 0.0: glitch_left = 0.09
	glitch_left -= delta
	glitch = (rand_range(0.55, 1.0) if glitch_left > 0.0 else max(0.0, glitch - delta * 8.0)) * fx_k
	if !fx_layer:
		fx_layer = CanvasLayer.new()
		fx_layer.layer = 100 # over the menu and its overlays, under the volume overlay (128)
		add_child(fx_layer)
		chroma = ColorRect.new()
		chroma.anchor_right = 1
		chroma.anchor_bottom = 1
		chroma.mouse_filter = MOUSE_FILTER_IGNORE
		chroma.material = ShaderMaterial.new()
		chroma.material.shader = Shader.new()
		chroma.material.shader.code = CHROMA_SHADER
		fx_layer.add_child(chroma)
	chroma.visible = true
	# (kept gentle: the real glitching is on the cover and the map card only)
	chroma.material.set_shader_param("amount", fx_k * (1.0 + 2.0 * punch + 1.5 * dim + 1.0 * glitch))
	chroma.material.set_shader_param("tear", 0.0)
	# cover
	if cover and (fx_cover == null or !is_instance_valid(fx_cover[1]) or fx_cover[1].get_parent() != cover):
		_fx_free(fx_cover)
		fx_cover = _fx_overlay(cover, 3.1)
	if fx_cover:
		fx_cover[1].material.set_shader_param("power", glitch)
		fx_cover[1].material.set_shader_param("size", cover.rect_size)
		fx_cover[1].visible = glitch > 0.01
		fx_cover[0].visible = fx_cover[1].visible
	# selected map card (the list rebuilds its cards on every page change)
	var card = _map_card()
	if fx_card and (!is_instance_valid(fx_card[2]) or fx_card[2] != card):
		_fx_free(fx_card); fx_card = null
	if card and fx_card == null:
		fx_card = _fx_overlay(card, 11.7) + [card]
	if fx_card:
		fx_card[1].material.set_shader_param("power", glitch * 0.8)
		fx_card[1].material.set_shader_param("size", card.rect_size)
		fx_card[1].visible = glitch > 0.01
		fx_card[0].visible = fx_card[1].visible

func _exit_tree():
	_fx_off()

# shake offset on top of wherever the container put the node: a new random jolt QUAKE_HZ times a
# second, held in between - choppy like a real quake, and the same at any frame rate (a new jump
# every frame turned into a blur / flicker at high fps)
const QUAKE_HZ = 30.0
var shake_hold:Dictionary = {} # node -> [time of the next jolt, offset, rotation]
func _shake(n:Control, amp:float, tilt:bool = true):
	var last = shake_last.get(n, [Vector2.ZERO, n.rect_position])
	var base = n.rect_position - last[0] if n.rect_position.is_equal_approx(last[1]) else n.rect_position
	var off = Vector2.ZERO
	var rot = 0.0
	if amp > 0:
		var now = OS.get_ticks_msec() / 1000.0
		var h = shake_hold.get(n, [0.0, Vector2.ZERO, 0.0])
		if now >= h[0]:
			h = [now + 1.0 / QUAKE_HZ, Vector2(rand_range(-amp, amp), rand_range(-amp, amp)).round(), rand_range(-amp, amp) * 0.08]
			shake_hold[n] = h
		off = h[1]
		rot = h[2]
	n.rect_position = base + off
	n.rect_rotation = rot if tilt else 0.0
	shake_last[n] = [off, n.rect_position]

func _bolt(target:Rect2):
	var vp = get_viewport_rect().size
	var end = target.position + Vector2(rand_range(0.2, 0.8), rand_range(0.15, 0.6)) * target.size
	var start = Vector2(clamp(end.x + rand_range(-vp.x * 0.25, vp.x * 0.25), 0, vp.x), -20)
	var pts = _jag(start, end, 7)
	var branches = []
	for i in 2:
		var k = int(rand_range(2, pts.size() - 3))
		var a = pts[k]
		var dir = (end - start).normalized().rotated(rand_range(-0.9, 0.9))
		branches.append(_jag(a, a + dir * rand_range(60, 160), 4))
	bolts.append([pts, branches, 0.0])
	kick = 1.0

func _jag(a:Vector2, b:Vector2, depth:int) -> PoolVector2Array:
	var pts = [a, b]
	var amp = a.distance_to(b) * 0.18
	for _d in depth:
		var np = [pts[0]]
		for i in range(1, pts.size()):
			var m = (pts[i - 1] + pts[i]) / 2
			var n = (pts[i] - pts[i - 1]).tangent().normalized()
			np.append(m + n * rand_range(-amp, amp))
			np.append(pts[i])
		pts = np
		amp *= 0.55
	return PoolVector2Array(pts)

func _draw():
	var sz = rect_size
	var run = _run()
	var power = clamp((stars - GLOW_FROM) / (HYPE_STARS - GLOW_FROM), 0.0, 1.0) if stars >= GLOW_FROM else 0.0
	power = max(power, surge)
	if power > 0: # side glows: star colour fading in from both screen edges, breathing with the bass
		var gc = load("res://mods/stars/StarCache.gd").color_for(stars)
		var ga = power * (0.1 + 0.38 * max(side, surge))
		var gw = sz.x * (0.10 + 0.08 * side)
		for x in [[0.0, gw], [sz.x, sz.x - gw]]:
			var edge = Color(gc.r, gc.g, gc.b, ga)
			var clear = Color(gc.r, gc.g, gc.b, 0.0)
			draw_polygon(PoolVector2Array([Vector2(x[0], 0), Vector2(x[1], 0), Vector2(x[1], sz.y), Vector2(x[0], sz.y)]),
					PoolColorArray([edge, clear, clear, edge]))
	if dim > 0.01 and run:
		var r = run.get_global_rect().grow(10) # (room for the shake + glow)
		var c = Color(0, 0, 0, 0.72 * dim)
		draw_rect(Rect2(0, 0, sz.x, r.position.y), c)
		draw_rect(Rect2(0, r.end.y, sz.x, sz.y - r.end.y), c)
		draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), c)
		draw_rect(Rect2(r.end.x, r.position.y, sz.x - r.end.x, r.size.y), c)
		# soft rounded glow hugging the button (drawn in the button's own transform, so it follows
		# the shake and the rounded corners instead of boxy rings)
		var p = clamp(0.55 + 0.25 * sin(t * 9.0) + bass * 0.5 + punch * 0.4, 0.0, 1.0)
		var gs = StyleBoxFlat.new()
		gs.draw_center = false
		gs.set_corner_radius_all(8)
		gs.shadow_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.85 * dim * p)
		gs.shadow_size = int(10 + 8 * p)
		gs.border_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.9 * dim)
		gs.set_border_width_all(2)
		draw_set_transform_matrix(get_global_transform().affine_inverse() * run.get_global_transform())
		draw_style_box(gs, Rect2(Vector2.ZERO, run.rect_size))
		draw_set_transform_matrix(Transform2D.IDENTITY)
	for b in bolts:
		var a = clamp(1.0 - b[2] / BOLT_LIFE, 0.0, 1.0)
		a = a * a * 0.8 # smooth fade, no flicker
		var lines = [b[0]] + b[1]
		for li in lines.size():
			var l = lines[li]
			var w = 1.0 if li == 0 else 0.6
			draw_polyline(l, Color(GLOW.r, GLOW.g, GLOW.b, a * 0.18), 10.0 * w, true)
			draw_polyline(l, Color(BOLT.r, BOLT.g, BOLT.b, a * 0.6), 4.0 * w, true)
			draw_polyline(l, Color(1, 1, 1, a * 0.8), 1.5 * w, true)

# spectrum bars growing out of the cover's edges (drawn by the cover, so menus on top hide it)
class CoverViz extends Control:
	var hype = null
	const BARS = 20
	func _ready():
		anchor_right = 1
		anchor_bottom = 1
		mouse_filter = MOUSE_FILTER_IGNORE
		show_behind_parent = true
	func _process(_d):
		update()
	func _draw():
		var vis = get_tree().root.get_node_or_null("Menu/AudioVisualizer")
		if !vis or vis.mags.size() < 8 or vis.ceiling <= 0: return
		var col = Color(1, 1, 1, 0.55)
		if hype and hype.hype: col = load("res://mods/stars/StarCache.gd").color_for(hype.stars)
		var s = rect_size
		var n = min(vis.mags.size(), 64)
		var sides = [[Vector2(0, 0), Vector2(s.x, 0), Vector2(0, -1)], [Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(1, 0)],
				[Vector2(s.x, s.y), Vector2(0, s.y), Vector2(0, 1)], [Vector2(0, s.y), Vector2(0, 0), Vector2(-1, 0)]]
		for si in 4:
			var a = sides[si][0]
			var b = sides[si][1]
			var out = sides[si][2]
			for i in BARS:
				var f = abs((i + 0.5) / BARS * 2.0 - 1.0) # side centre = bass, corners = treble
				var k = int(f * f * n * 0.7)
				# same motion as the menu's bottom visualizer: each bar is its band's level as the
				# visualizer has it (its own smoothing + auto ceiling), no extra smoothing or beat boost
				var v = clamp(vis.mags[k] / vis.ceiling, 0.0, 1.0) * (hype.gate if hype else 1.0)
				if v < 0.03: continue # quiet: no bar (resting stubs looked like a dotted frame)
				var p = a.linear_interpolate(b, (i + 0.5) / BARS)
				var c = col
				c.a *= min(1.0, (v - 0.03) * 10.0) * (0.35 + 0.65 * v)
				draw_line(p + out * 6, p + out * (6 + v * 76), c, 5.0, true)
