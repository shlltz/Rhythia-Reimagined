extends Control
# Map-page effects:
# - the cover art is an audio visualizer: it pulses with the bass and spectrum bars grow out of
#   its four edges
# - maps above 10 stars: cover + Start quake, lightning strikes the cover when the map is
#   selected / Start is clicked (soft: no flicker, no screen flash); hovering Start dims everything
#   else while Start shakes and glows
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
	punch *= exp(-delta * 9.0)
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
		s *= 1.0 + 0.075 * punch # the hit
		cover.rect_scale = Vector2(s, s)
		_shake(cover, (2.0 + bass * 3.0 + kick * 5.0) if hype else 0.0)
		cover.rect_rotation += tilt_dir * 1.4 * punch * punch # alternating little tilt per beat
		var f = 1.0 + 0.3 * punch # flash brighter on the beat
		cover.modulate = Color(f, f, f, cover.modulate.a)
	if run:
		run.rect_pivot_offset = run.rect_size / 2
		_shake(run, (1.5 + bass * 2.0 + kick * 3.0 + dim * 2.5) if hype else 0.0, false)
	update()

# random offset on top of wherever the container put the node
func _shake(n:Control, amp:float, tilt:bool = true):
	var last = shake_last.get(n, [Vector2.ZERO, n.rect_position])
	var base = n.rect_position - last[0] if n.rect_position.is_equal_approx(last[1]) else n.rect_position
	var off = Vector2(rand_range(-amp, amp), rand_range(-amp, amp)).round() if amp > 0 else Vector2.ZERO
	n.rect_position = base + off
	n.rect_rotation = rand_range(-amp, amp) * 0.08 if amp > 0 and tilt else 0.0
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
				var v = clamp(vis.mags[k] / vis.ceiling * (1.0 + 0.6 * (hype.punch if hype else 0.0)), 0.0, 1.0) * (hype.gate if hype else 1.0)
				var p = a.linear_interpolate(b, (i + 0.5) / BARS)
				var c = col
				c.a *= 0.35 + 0.65 * v
				draw_line(p + out * 5, p + out * (8 + v * 70), c, 5.0)
