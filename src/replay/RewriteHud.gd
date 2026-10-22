extends Node
# Rewrite HUD (Settings > UI > "Rewrite HUD", on by default): the run's panels drawn like the Rhythia
# rewrite's (Rhythia/Client @9200e16, scenes/game.tscn + scripts/game/ui) - score and the multiplier
# ring on the left, accuracy and hits / misses on the right, the song name, time and progress bar
# above the grid, the health bar under it, the combo as a big outlined number behind the notes.
# The HUD's own viewports and 3D sprites stay (their places, the layout editor, the fade-in, the
# show / hide options); only what is drawn inside them changes. The stock labels are hidden, not
# removed: HUD.gd keeps writing to them.
# A skin made from a rewrite skin (Skins.import_rewrite) brings its panel / bar / icon images and its
# grid frame; without those the rewrite's default look is drawn.

const ORANGE = Color(1.0, 140.0 / 255.0, 0.0)
const REST_ALPHA = 0.62 # hits / misses counts between changes (they flash to 1)

var hud:Node
var Game:Node
var fonts:Dictionary = {}
var base_font:Font = null

var score:Label
var mult:Label
var ring:Control
var alt_combo:Label
var acc:Label
var hits:Label
var misses:Label
var simple_misses:Label
var sum:Label
var title:Label
var time:Label
var progress:Control
var health:Control
var hit_row:Array = []
var title_src:String = "~"

var hit_a:float = REST_ALPHA
var miss_a:float = REST_ALPHA
var last_hits:int = 0
var last_misses:int = 0
var hp:float = 1.0
var ring_p:float = 0.0
var ring_col:Color = Color.white
var hp_rate:float = 60.0

static func on() -> bool:
	return ResourceLoader.exists("res://mods/replay/Reimagined.gd") and str(load("res://mods/replay/Reimagined.gd").val("hud_style")) == "rewrite"

static func attach(h:Node):
	var n = load("res://mods/replay/RewriteHud.gd").new()
	n.name = "RRRewriteHud"
	n.hud = h
	h.add_child(n)

func _ready():
	Game = hud.Game
	var R = load("res://mods/replay/Reimagined.gd")
	hp_rate = clamp(float(R.val("hp_ease")), 10.0, 100.0)
	base_font = hud.scorelabel.get_font("font")
	var S = load("res://mods/replay/Skins.gd") if ResourceLoader.exists("res://mods/replay/Skins.gd") else null
	_left(S, bool(R.val("alt_combo")))
	_right(S)
	_timer(S)
	_energy(S)
	_combo(bool(R.val("alt_combo")))
	_grid(S)
	_parts()
	hp = _hp_target()
	_update(0.0)

func _tex(S, slot:String):
	return S.texture(slot) if S else null

func _font(size:int) -> Font:
	if fonts.has(size): return fonts[size]
	var f = base_font
	if f is DynamicFont:
		f = f.duplicate()
		f.size = size
	fonts[size] = f
	return f

func _label(parent:Control, size:int, y:float, h:float, a:float = 1.0) -> Label:
	var l = Label.new()
	l.add_font_override("font", _font(size))
	l.add_color_override("font_color", Color(1, 1, 1, a))
	l.align = Label.ALIGN_CENTER
	l.valign = Label.VALIGN_CENTER
	l.clip_text = true
	l.rect_position = Vector2(0, y - h / 2)
	l.rect_size = Vector2(parent.rect_size.x, h)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

# the stock contents of a viewport's root go invisible; returns the root to draw in
func _clear(path:String) -> Control:
	var c = hud.get_node_or_null(path)
	if !c: return null
	for n in c.get_children():
		if n is CanvasItem: n.visible = false
	if c is CanvasItem: c.self_modulate = Color(1, 1, 1, 0)
	return c

func _holder(c:Control) -> Control:
	var h = Control.new()
	h.name = "RRRewrite"
	h.rect_size = c.rect_size
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(h)
	return h

func _left(S, alt:bool):
	var c = _clear("LeftVP/Control")
	if !c: return
	var h = _holder(c)
	h.add_child(PanelBg.new(_tex(S, "rw_panel_left")))
	var full = !Rhythia.simple_hud
	var sz = h.rect_size
	score = _label(h, 60, sz.y * 0.35, 90)
	ring = Ring.new()
	ring.rect_size = Vector2(sz.x, sz.x)
	ring.rect_position = Vector2(0, sz.y * 0.65 - sz.x / 2)
	h.add_child(ring)
	mult = _label(h, 60, sz.y * 0.65, 90)
	alt_combo = _label(h, 36, sz.y * 0.86, 50)
	for n in [score, ring, mult]: n.visible = full
	alt_combo.visible = full and alt
	if !full: h.get_child(0).visible = false

func _right(S):
	var c = _clear("RightVP/Control")
	if !c: return
	var h = _holder(c)
	h.add_child(PanelBg.new(_tex(S, "rw_panel_right")))
	var full = !Rhythia.simple_hud
	var sz = h.rect_size
	var mid = sz.x / 2
	var y = sz.y * 0.625
	acc = _label(h, 60, sz.y * 0.35, 90)
	hits = _label(h, 44, y - 4, 56, REST_ALPHA)
	hits.align = Label.ALIGN_RIGHT
	hits.rect_size.x = mid - 38
	misses = _label(h, 44, y - 4, 56, REST_ALPHA)
	misses.align = Label.ALIGN_LEFT
	misses.rect_position.x = mid + 38
	misses.rect_size.x = mid - 38
	var hi = Mark.new(_tex(S, "rw_hits"), false)
	hi.rect_position = Vector2(mid - 34, y - 19)
	h.add_child(hi)
	var mi = Mark.new(_tex(S, "rw_misses"), true)
	mi.rect_position = Vector2(mid + 4, y - 19)
	h.add_child(mi)
	var line = ColorRect.new()
	line.color = Color(1, 1, 1, 0.35)
	line.rect_position = Vector2(19, sz.y * 0.65)
	line.rect_size = Vector2(sz.x - 38, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(line)
	sum = _label(h, 60, sz.y * 0.7 + 24, 80, 0.77)
	simple_misses = _label(h, 60, sz.y * 0.5, 90)
	hit_row = [hits, misses, hi, mi, line]
	for n in [h.get_child(0), acc, hits, misses, hi, mi, line, sum]: n.visible = full
	simple_misses.visible = !full

func _timer(S):
	var c = _clear("TimerVP/Control")
	if !c: return
	var h = _holder(c)
	title = _label(h, 36, 95, 70)
	time = _label(h, 32, 175, 60, 0.75)
	progress = Bar.new(_tex(S, "rw_progress"), _tex(S, "rw_progress_bg"), Color.white, Color(40 / 255.0, 40 / 255.0, 40 / 255.0))
	progress.rect_position = Vector2(50, 222)
	progress.rect_size = Vector2(800, 59)
	h.add_child(progress)

func _energy(S):
	var bar = hud.get_node_or_null("EnergyVP/Control/Energy")
	if !bar: return
	bar.self_modulate = Color(1, 1, 1, 0) # (stays for its place and the show / hide option)
	for n in bar.get_children():
		if n is CanvasItem: n.visible = false
	health = Bar.new(_tex(S, "rw_health"), _tex(S, "rw_health_bg"), Color(0, 1, 0), Color(1, 0, 0))
	health.rect_position = Vector2(50, -7)
	health.rect_size = Vector2(800, 59)
	health.visible = bar.visible
	bar.get_parent().add_child(health)
	bar.get_parent().move_child(health, bar.get_index())

# the combo behind the notes: outline only, like the rewrite's (alt counter: moved into the left panel)
func _combo(alt:bool):
	var v = hud.get_node_or_null("ComboVP/Value")
	if !(v is Label): return
	if alt:
		v.self_modulate = Color(1, 1, 1, 0)
		return
	var f = v.get_font("font")
	if f is DynamicFont:
		f = f.duplicate()
		f.outline_size = int(max(2, f.size / 24))
		f.outline_color = Color(1, 1, 1, 0.39)
		v.add_font_override("font", f)
	v.add_color_override("font_color", Color(1, 1, 1, 0))
	v.add_color_override("font_outline_modulate", Color(1, 1, 1, 1))

# a skin's rewrite grid frame (4 x 4 units round the 3 x 3 play area) instead of the border
func _grid(S):
	var t = _tex(S, "rw_grid")
	var sp = hud.Spawn
	var outer = sp.get_node_or_null("Outer") if sp else null
	if !t or !outer or !outer.visible: return
	var q = QuadMesh.new()
	q.size = Vector2(4, 4)
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.albedo_texture = t
	q.material = m
	var mi = MeshInstance.new()
	mi.name = "RRRewriteGrid"
	mi.mesh = q
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var s = outer.transform.basis.get_scale().x
	mi.transform = Transform(Basis().scaled(Vector3(s, s, s)), outer.transform.origin + Vector3(0, 0, -0.002))
	sp.add_child(mi)
	outer.visible = false

# Customize > HUD layout: the parts moved / sized / hidden inside their panels
func _parts():
	var P = load("res://mods/replay/HudParts.gd")
	var mods = hud.get_node_or_null("EnergyVP/Control/Modifiers")
	var map = {"LeftHud": {"score": [score], "ring": [ring, mult], "combo": [alt_combo]},
		"RightHud": {"acc": [acc], "hits": hit_row, "sum": [sum], "simple": [simple_misses]},
		"TimerHud": {"title": [title], "time": [time], "bar": [progress]},
		"EnergyHud": {"bar": [health], "mods": [mods]}}
	for panel in map:
		for part in map[panel]:
			var nodes = []
			for n in map[panel][part]:
				if n: nodes.append(n)
			P.apply("rewrite", panel, part, nodes)

func _hp_target() -> float:
	return clamp(Game.energy / max(Game.max_energy, 0.001), 0.0, 1.0)

func _process(delta:float):
	_update(delta)

func _update(delta:float):
	var judged = int(Game.total_notes)
	var h = int(Game.hits)
	var m = int(Game.misses)
	if score:
		score.text = Globals.comma_sep(Game.score)
		mult.text = "%dx" % Game.combo_level
		alt_combo.text = Globals.comma_sep(Game.combo)
		var target = 1.0 if Game.combo_level >= 8 else float(Game.lvl_progress) / 10.0
		ring_p = lerp(ring_p, target, min(1.0, delta * 16.0)) if delta > 0 else target
		ring_col = ring_col.linear_interpolate(ORANGE if Game.combo_level >= 8 else Color.white, min(1.0, delta * 2.0))
		ring.set_state(ring_p, ring_col)
	if acc:
		acc.text = "100.00%" if judged <= 0 or h + m == 0 else "%.2f%%" % (floor(float(h) / max(h + m, 1) * 10000.0) / 100.0)
		hits.text = Globals.comma_sep(h)
		misses.text = Globals.comma_sep(m)
		simple_misses.text = Globals.comma_sep(m)
		sum.text = Globals.comma_sep(h + m)
		if h != last_hits: hit_a = 1.0
		if m != last_misses: miss_a = 1.0
		last_hits = h
		last_misses = m
		var ha = move_toward(hit_a, REST_ALPHA, delta * 1.5)
		var ma = move_toward(miss_a, REST_ALPHA, delta * 1.5)
		if ha != hit_a: hits.add_color_override("font_color", Color(1, 1, 1, ha)) # (only while it fades: an override redraws)
		if ma != miss_a: misses.add_color_override("font_color", Color(1, 1, 1, ma))
		hit_a = ha
		miss_a = ma
	if title:
		if hud.songnametxt.text != title_src: # (shortened with an ellipsis for this label's own font and width)
			title_src = hud.songnametxt.text
			title.text = load("res://mods/replay/CardUI.gd").fit(title_src, title.get_font("font"), title.rect_size.x - 40)
		time.text = hud.timelabel.text
		progress.set_value(hud.timebar.value)
	if health:
		hp = lerp(hp, _hp_target(), min(1.0, delta * hp_rate)) if delta > 0 else _hp_target()
		health.set_value(hp)
		health.modulate.a = 0.5 if Game.energy <= 0 and !Rhythia.replaying else 1.0

# ------------------------------------------------------------------ pieces
# the panel's backing: the skin's image, else the rewrite's (black, 38%, faded at the top and bottom)
class PanelBg extends Control:
	var tex
	func _init(t):
		tex = t
		anchor_right = 1
		anchor_bottom = 1
		mouse_filter = MOUSE_FILTER_IGNORE
	func _draw():
		var r = Rect2(Vector2(), rect_size)
		if tex:
			draw_texture_rect(tex, r, false)
			return
		var a = Color(0, 0, 0, 0.38)
		var z = Color(0, 0, 0, 0)
		var f = rect_size.y * 0.1
		var w = rect_size.x
		var h = rect_size.y
		draw_polygon(PoolVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, f), Vector2(0, f)]), PoolColorArray([z, z, a, a]))
		draw_rect(Rect2(0, f, w, h - 2 * f), a)
		draw_polygon(PoolVector2Array([Vector2(0, h - f), Vector2(w, h - f), Vector2(w, h), Vector2(0, h)]), PoolColorArray([a, a, z, z]))

# the multiplier ring: a 10-sided outline (one side per hit to the next multiplier), filled clockwise
# from the top like the rewrite's combo_progress shader
class Ring extends Control:
	const SIDES = 10
	const BG = Color(0.155, 0.155, 0.155)
	var p:float = 0.0
	var col:Color = Color.white
	func _init():
		mouse_filter = MOUSE_FILTER_IGNORE
	func set_state(v:float, c:Color):
		if abs(v - p) < 0.0005 and c == col: return
		p = v
		col = c
		update()
	func _pt(i:int, r:float) -> Vector2:
		var a = TAU * float(i) / SIDES
		return rect_size / 2 + Vector2(sin(a), -cos(a)) * r
	func _draw():
		var r = rect_size.x * 0.256
		var w = max(3.0, rect_size.x * 0.014)
		var pts = PoolVector2Array()
		for i in SIDES + 1: pts.append(_pt(i, r))
		draw_polyline(pts, BG, w, true)
		if p <= 0.0: return
		var sweep = TAU * clamp(p, 0.0, 1.0)
		var fg = PoolVector2Array([pts[0]])
		for i in SIDES:
			var a1 = TAU * float(i + 1) / SIDES
			if a1 <= sweep:
				fg.append(pts[i + 1])
				continue
			# where the sweep's ray crosses this side
			var d = Vector2(sin(sweep), -cos(sweep))
			var e = pts[i + 1] - pts[i]
			var o = pts[i] - rect_size / 2
			var den = d.x * e.y - d.y * e.x
			if abs(den) > 0.00001:
				var t = (o.x * d.y - o.y * d.x) / den
				fg.append(pts[i] + e * clamp(t, 0.0, 1.0))
			break
		if fg.size() >= 2: draw_polyline(fg, col, w, true)

# hits / misses icon: the skin's image, else a drawn tick / cross
class Mark extends Control:
	var tex
	var cross:bool
	func _init(t, x:bool):
		tex = t
		cross = x
		rect_size = Vector2(30, 30)
		mouse_filter = MOUSE_FILTER_IGNORE
	func _draw():
		if tex:
			draw_texture_rect(tex, Rect2(Vector2(), rect_size), false)
			return
		var c = Color(1, 1, 1, 0.62)
		if cross:
			draw_line(Vector2(7, 7), Vector2(23, 23), c, 4, true)
			draw_line(Vector2(23, 7), Vector2(7, 23), c, 4, true)
		else:
			draw_polyline(PoolVector2Array([Vector2(5, 16), Vector2(12, 23), Vector2(25, 8)]), c, 4, true)

# a rewrite bar: its images are 1088 x 80 with the bar in the middle 1024 x 16 (32 px clear at the
# ends); the fill shows the image's left part up to the value (the rewrite tiles it at that width)
class Bar extends Control:
	const W = 1088.0
	var fg
	var bg
	var fg_col:Color
	var bg_col:Color
	var v:float = 0.0
	func _init(f, b, fc:Color, bc:Color):
		fg = f
		bg = b
		fg_col = fc
		bg_col = bc
		mouse_filter = MOUSE_FILTER_IGNORE
	func set_value(x:float):
		x = clamp(x, 0.0, 1.0)
		if abs(x - v) < 0.0005: return
		v = x
		update()
	func _draw():
		var k = (32.0 + v * 1024.0) / W
		var r = Rect2(Vector2(), rect_size)
		if bg: draw_texture_rect(bg, r, false)
		else: draw_rect(_inner(1.0), bg_col)
		if fg:
			var ts = fg.get_size()
			draw_texture_rect_region(fg, Rect2(0, 0, rect_size.x * k, rect_size.y), Rect2(0, 0, ts.x * k, ts.y))
		elif v > 0.0:
			draw_rect(_inner(v), fg_col)
	func _inner(x:float) -> Rect2:
		var h = rect_size.y * 15.0 / 80.0
		return Rect2(rect_size.x * 32.0 / W, (rect_size.y - h) / 2, rect_size.x * 1024.0 / W * x, h)
