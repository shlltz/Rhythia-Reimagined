extends CanvasLayer
# Results screen: one map card over the map's blurred cover (the same backdrop as the map page and
# the loading screen, MapBackdrop.gd). Cover banner with the status and title, stars / difficulty /
# length, a grade ring with the accuracy, the counting score, stat tiles (accuracy, max combo, hits,
# misses, pauses, speed or progress, mods, played), who played and when; Back / Retry / From fail
# point / Watch replay / Analyse under it. Esc / Back = map selection, ` = retry. Data comes from
# Game.gd (Rhythia meta "last_run"); stored plays from RecentPlays.gd (run.stored, run.when).

const UIAnim = preload("res://mods/replay/UIAnim.gd")
const OsuSfx = preload("res://mods/replay/OsuSfx.gd")
const CardUI = preload("res://mods/replay/CardUI.gd")
const MapBackdrop = preload("res://mods/replay/MapBackdrop.gd")
const W = 720.0
const H = 822.0
const BANNER_H = 260.0
const RING_C = Vector2(160, 446)
const RING_R = 104.0
const MODS = [["mod_nofail", "NoFail"], ["mod_sudden_death", "SuddenDeath"], ["mod_hardrock", "HardRock"],
	["mod_flashlight", "Flashlight"], ["mod_ghost", "Ghost"], ["mod_nearsighted", "Nearsighted"],
	["mod_chaos", "Chaos"], ["mod_earthquake", "Earthquake"], ["mod_mirror_x", "MirrorX"],
	["mod_mirror_y", "MirrorY"], ["mod_extra_energy", "ExtraEnergy"], ["mod_no_regen", "NoRegen"]]
const SHORT = {"NoFail": "NF", "SuddenDeath": "SD", "HardRock": "HR", "Flashlight": "FL", "Ghost": "GH",
	"Nearsighted": "NS", "Chaos": "CH", "Earthquake": "EQ", "MirrorX": "MX", "MirrorY": "MY", "ExtraEnergy": "EE", "NoRegen": "NR"}

var ACCENT:Color = CardUI.accent()
var menu:Node
var sfx:Node
var run:Dictionary
var holder:Control
var score_label:Label
var grade_text:Label
var acc_label:Label
var best_label:Label
var covered:Array = []
var t:float = 0.0
var stamped:bool = false
var closing:bool = false
var mono:bool = CardUI.mono()
var shake:float = 0.0
var flash:ColorRect = null
var fonts:Dictionary = {}
var grade_ring = null
var bd:TextureRect = null
var bd_zoom:float = 0.0           # set while leaving into the loading screen

func _init(data:Dictionary):
	run = data

func _f(size:int):
	return CardUI.font(size, fonts)

func _ready():
	layer = 16
	menu = get_parent()
	sfx = OsuSfx.inst(get_tree())
	var song = run.song
	var root = Control.new()
	root.anchor_right = 1; root.anchor_bottom = 1
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var back = ColorRect.new()
	back.color = Color(0.02, 0.02, 0.024)
	back.anchor_right = 1; back.anchor_bottom = 1
	root.add_child(back)
	bd = MapBackdrop.make_rect() # the map page's blurred cover (same look as the backdrop behind the menu)
	bd.texture = Engine.get_meta("rr_backdrop") if Engine.has_meta("rr_backdrop") and Rhythia.selected_song == song else MapBackdrop.small_texture(song)
	root.add_child(bd)
	if bd.texture == null and song: root.add_child(CardUI.no_cover_bg(song))
	if mono: # personal build: the tally board (this card's look + ULTRAKILL's results)
		_build_board(root)
		_buttons(root)
		_cover(true)
		UIAnim.play(root, Vector2.ZERO, Vector2.ZERO, 0.0, 1.0, 0.3)
		_layout()
		return

	holder = Panel.new()
	if ResourceLoader.exists("res://uitheme.tres"): holder.theme = load("res://uitheme.tres")
	var sb = CardUI.box(Color(0.06, 0.06, 0.07, 0.9), Color(1, 1, 1, 0.1), 1, 24)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 40
	holder.add_stylebox_override("panel", sb)
	root.add_child(holder)
	holder.rect_size = Vector2(W, H)
	if mono: holder.connect("draw", self, "_draw_frame") # console frame: corner brackets outside the card

	# ---- banner: cover, status, title, mapper
	var cover_tex = song.cover if song and song.has_cover else null
	CardUI.banner(holder, cover_tex, Rect2(1, 1, W - 2, BANNER_H), 23, song) # (no cover: contour lines in the difficulty colour)
	var st = _status()
	var sp = CardUI.pill(holder, "      " + st[0], _f(15), Color(0, 0, 0, 0.6), Color(1, 1, 1), Vector2(22, 22), 34, Color(1, 1, 1, 0.14))
	var dot = Dot.new() # status colour dot inside the pill
	dot.col = st[1]
	dot.rect_position = Vector2(16, 12); dot.rect_size = Vector2(10, 10)
	sp.add_child(dot)
	var title = ("[REPLAY] " if run.replay else "") + (song.name if song else "?")
	CardUI.label(holder, CardUI.fit(title, _f(30), W - 60), _f(30), Color(1, 1, 1), Vector2(30, BANNER_H - 82), W - 60)
	CardUI.label(holder, "mapped by " + (str(song.creator) if song else "?"), _f(17), Color(1, 1, 1, 0.65), Vector2(30, BANNER_H - 40), W - 60)

	# ---- pills: stars, difficulty, length
	var fp = _f(15)
	var row = Vector2(28, BANNER_H + 22)
	var stars = CardUI.stars(song, run.speed)
	if stars > 0:
		var stext = "★ %.2f" % stars
		if mono and CardUI._has("danger"):
			var dg = load(CardUI.LOOK).danger(stars)
			stext += "  // %s %s" % [dg[0], dg[1]]
		row.x = CardUI.pill_end(CardUI.pill(holder, stext, fp, Color(0, 0, 0, 0.7), Color(1, 1, 1), row, 34, Color(1, 1, 1, 0.16)))
	var d = CardUI.difficulty(song)
	if d[0] != "": row.x = CardUI.pill_end(CardUI.pill(holder, d[0], fp, Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.9), row, 34))
	if run.length > 0: row.x = CardUI.pill_end(CardUI.pill(holder, CardUI.mmss(float(run.length) / max(0.01, run.speed)), fp, Color(d[1].r, d[1].g, d[1].b, 0.14), d[1].lightened(0.25), row, 34))
	if run.get("resumed"): CardUI.pill(holder, "Resumed", fp, Color(1, 0.7, 0.35, 0.16), Color("#ffb35e"), row, 34)

	# ---- grade ring + accuracy, score
	var acc = float(run.hits) / max(1.0, float(run.total))
	var g = _grade(acc)
	var ring = GradeRing.new()
	ring.col = ACCENT if !mono else Color(1, 1, 1, 0.85)
	ring.frac = acc
	ring.center = RING_C
	ring.radius = RING_R
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ring)
	ring.rect_size = Vector2(W, H)
	grade_ring = ring
	# the letter alone, centred in the ring (the box is tall enough for the personal build's bigger face)
	grade_text = CardUI.label(holder, g[0], _f(128), g[2], Vector2(RING_C.x - 110, RING_C.y - 100), 220)
	grade_text.align = Label.ALIGN_CENTER
	grade_text.valign = Label.VALIGN_CENTER
	grade_text.clip_text = false
	grade_text.rect_size = Vector2(220, 200)
	acc_label = CardUI.label(holder, "%.2f%%" % (acc * 100), _f(20), Color(1, 1, 1, 0.75), Vector2(RING_C.x - 110, RING_C.y + 40), 220)
	acc_label.align = Label.ALIGN_CENTER
	acc_label.visible = false # (only the grade in the ring: accuracy is in the tiles)
	if mono: _mono_grade(g)
	grade_text.rect_pivot_offset = grade_text.rect_size / 2
	grade_text.modulate.a = 0
	var sx = 318.0
	CardUI.label(holder, "Score", _f(18), Color(1, 1, 1, 0.5), Vector2(sx, RING_C.y - 70))
	score_label = CardUI.label(holder, "0", _f(58), Color(1, 1, 1), Vector2(sx - 2, RING_C.y - 46), W - sx - 30)
	best_label = CardUI.label(holder, "", _f(16), Color("#ffd75e"), Vector2(sx, RING_C.y + 32), W - sx - 30)
	if mono: # evaluation line under the score (from the grade, real run data)
		var v = {"SS": "FLAWLESS", "S": "EXCELLENT", "A": "STRONG", "B": "ADEQUATE", "C": "MARGINAL", "D": "POOR", "F": "TERMINATED"}[g[0]]
		var Lk = load(CardUI.LOOK)
		var vc = Color(1, 1, 1, 0.55)
		if g[0] == "F": vc = load(CardUI.LOOK).CRIT.lightened(0.15)
		elif g[0] in ["SS", "S"] and CardUI._has("hot"): vc = Lk.hot(0.95)
		CardUI.label(holder, "// EVALUATION: " + v, _f(15), vc, Vector2(sx, RING_C.y + 58), W - sx - 30)

	# ---- stat tiles (2 rows of 4)
	var fs = _f(14)
	var fb = _f(24)
	var tw = (W - 56 - 3 * 12) / 4.0
	var y0 = 590.0
	var tiles = [
		["Accuracy", "%.2f%%" % (acc * 100), ""],
		["Max combo", Globals.comma_sep(run.combo) + "x", "FC" if run.misses == 0 and run.end_type == Globals.END_PASS else ""],
		["Hits", Globals.comma_sep(run.hits), "of " + Globals.comma_sep(run.total)],
		["Misses", Globals.comma_sep(run.misses), ""],
		["Pauses", str(run.pauses), ""],
		["Progress", "%.1f%%" % (clamp(run.position / max(1.0, run.length), 0, 1) * 100), ""] if run.end_type != Globals.END_PASS else ["Speed", "%.2fx" % run.speed, ""],
		["Mods", "", ""],
		["Played", str(run.get("when", "just now")), ""],
	]
	for i in tiles.size():
		var r = Rect2(28 + (i % 4) * (tw + 12), y0 + int(i / 4) * 92, tw, 80)
		var vf = fb if fb.get_string_size(tiles[i][1]).x <= tw - 30 else _f(18) # (a long value - "11 days ago" - steps down instead of being cut)
		var tl = CardUI.tile(holder, r, tiles[i][0], CardUI.fit(tiles[i][1], vf, tw - 30), fs, vf, tiles[i][2])
		if tiles[i][0] == "Mods": _mod_tags(tl)
	var name_ = CardUI.player()
	var foot = CardUI.label(holder, ("Played by %s  ·  " % name_ if name_ != "" else "") + CardUI.today(), _f(16), Color(1, 1, 1, 0.45), Vector2(30, H - 44), W - 60)
	foot.align = Label.ALIGN_CENTER
	if run.get("stored") and run.get("when"): foot.text = ("Played by %s  ·  " % name_ if name_ != "" else "") + "played " + str(run.when)

	_buttons(root)

	_cover(true)
	UIAnim.play(root, Vector2.ZERO, Vector2.ZERO, 0.0, 1.0, 0.3)
	_layout()

func _buttons(root:Control):
	var bar = HBoxContainer.new()
	bar.anchor_left = 0.5; bar.anchor_right = 0.5; bar.anchor_top = 1; bar.anchor_bottom = 1
	bar.margin_left = -330; bar.margin_right = 330; bar.margin_top = -86; bar.margin_bottom = -34
	bar.add_constant_override("separation", 14)
	root.add_child(bar)
	_button(bar, "Back", "_back")
	_button(bar, "Retry", "_retry")
	if run.get("resume") and ResourceLoader.exists("res://mods/replay/Checkpoint.gd"):
		var rb = _button(bar, "From fail point", "_retry_resume")
		if rb: rb.hint_tooltip = "Retry from %s: the last exact checkpoint at least 2 s before you failed.\nScore, combo and health as they were there. Can't set a personal best; no replay." % _mmss(run.resume.snap.at)
		bar.margin_left -= 85 # (a 4th / 5th button: the bar grows instead of squeezing the labels)
		bar.margin_right += 85
	if run.replay_path != "" and File.new().file_exists(run.replay_path):
		_button(bar, "Watch replay", "_watch")
		if ResourceLoader.exists("res://mods/replay/ReplayStudio.gd"):
			_button(bar, "Analyse", "_analyse")
			bar.margin_left -= 85
			bar.margin_right += 85


func _mod_tags(tl:Panel):
	var mods = run.get("mods", null)
	if mods == null: mods = current_mods()
	var tags = []
	var sp = CardUI.speed_tag(run.speed)
	if sp != "": tags.append(sp)
	for m in mods: tags.append(SHORT.get(m, m))
	var v = tl.get_meta("value")
	if tags.empty():
		v.text = "None"
		return
	v.text = ""
	var x = 14.0
	for tg in tags:
		if x > tl.rect_size.x - 40: break
		x = CardUI.pill_end(CardUI.pill(tl, tg, _f(13), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85), Color(0.08, 0.06, 0.06), Vector2(x, tl.rect_size.y - 40), 28), 6)

func _draw_frame():
	var Lk = load(CardUI.LOOK)
	Lk.brackets(holder, Rect2(Vector2(), holder.rect_size).grow(10), 26.0, Lk.hot(0.55) if CardUI._has("hot") else Color(1, 1, 1, 0.5), 2.0)

# personal build: the osu! skin's rank art (Wrath) inside the ring, else a heavy face + static glitch
func _mono_grade(g:Array):
	var Look = load(CardUI.LOOK)
	var art = _rank_art(g[1]) if g[0] != "F" else null # (osu! has no fail rank: F stays a letter)
	if art:
		grade_ring.col = art[1]
		var tr = TextureRect.new()
		tr.texture = art[0]
		tr.expand = true
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var side = RING_R * 2.3
		tr.rect_size = Vector2(side, side)
		tr.rect_position = (grade_text.rect_size - tr.rect_size) / 2
		tr.material = ShaderMaterial.new()
		tr.material.shader = Shader.new()
		tr.material.shader.code = "shader_type canvas_item;\nuniform float edge = 0.0;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tvec2 q = abs(UV - vec2(0.5)) * 2.0;\n\tc.a *= smoothstep(edge, edge + 0.22, UV.x) * (1.0 - smoothstep(0.45, 1.0, q.x)) * (1.0 - smoothstep(0.45, 1.0, q.y)) * (1.0 - smoothstep(0.7, 1.15, length(q)));\n\tCOLOR = c * COLOR;\n}"
		tr.material.set_shader_param("edge", art[2])
		grade_text.add_child(tr)
		grade_text.self_modulate.a = 0.0 # (the label keeps its pop-in animation, the art rides on it)
		acc_label.visible = false # (the art fills the ring)
	elif CardUI._has("grade_font"):
		var gf = Look.grade_font(150) # (its letters are ~70% of the size: about half the ring)
		if gf: grade_text.add_font_override("font", gf)
		if CardUI._has("static_glitch"): Look.static_glitch(grade_text, 2.0, 4.0)

static func current_mods() -> Array:
	var out = []
	for m in MODS:
		if Rhythia.get(m[0]): out.append(m[1])
	return out

# rank art from the osuskin mod (ranking-X / S / A / B / C / D.png, 2436x600 canvases with the
# letter in the middle): cropped to what is drawn. The skin's S has a meme picture left of the
# letter - everything left of the letter is cleared first. null when the image isn't there.
const RANK_CUT = {"S": 1042}
func _rank_art(k:String):
	var p = "res://mods/osuskin/ranking-%s.png" % k
	if !File.new().file_exists(p): return null
	var img = Image.new()
	if img.load(p) != OK: return null
	if RANK_CUT.has(k): # (blit of a clear image: fill_rect is Godot 4)
		var clear = Image.new()
		clear.create(RANK_CUT[k], img.get_height(), false, img.get_format())
		clear.fill(Color(0, 0, 0, 0))
		img.blit_rect(clear, Rect2(Vector2.ZERO, clear.get_size()), Vector2.ZERO)
	var used = img.get_used_rect()
	if used.size.x <= 0: return null
	# the letter's solid core (on a 1/8 copy: cheap) sets the centre and the ring colour - the glow
	# around it is lopsided, so a plain crop left the letter off-centre
	var sm = img.duplicate()
	sm.resize(int(img.get_width() / 8), int(img.get_height() / 8), Image.INTERPOLATE_BILINEAR)
	sm.lock()
	var lo = Vector2(INF, INF)
	var hi = Vector2(-INF, -INF)
	var sum = Color(0, 0, 0, 0)
	var n = 0
	for y in sm.get_height():
		for x in sm.get_width():
			var c = sm.get_pixel(x, y)
			if c.a < 0.85: continue
			lo = Vector2(min(lo.x, x), min(lo.y, y))
			hi = Vector2(max(hi.x, x), max(hi.y, y))
			sum += c
			n += 1
	sm.unlock()
	var mid = used.position + used.size / 2
	var col = Color(1, 1, 1)
	if n > 0:
		mid = (lo + hi + Vector2.ONE) * 4.0 # (x8 / 2)
		col = Color(sum.r / n, sum.g / n, sum.b / n).lightened(0.15)
	# square crop centred on the core, big enough for all of the glow
	var half = max(max(mid.x - used.position.x, used.end.x - mid.x), max(mid.y - used.position.y, used.end.y - mid.y))
	var out = Image.new()
	out.create(int(half * 2), int(half * 2), false, img.get_format())
	out.fill(Color(0, 0, 0, 0))
	var src = Rect2(mid - Vector2(half, half), Vector2(half, half) * 2).clip(Rect2(Vector2.ZERO, img.get_size()))
	out.blit_rect(img, src, src.position - (mid - Vector2(half, half)))
	var tx = ImageTexture.new()
	tx.create_from_image(out, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	var edge = 0.0 # where the cleared meme area ends, as a fraction of the crop width
	if RANK_CUT.has(k): edge = clamp((RANK_CUT[k] - (mid.x - half)) / (half * 2), 0.0, 1.0)
	return [tx, col, edge]

class Dot extends Control:
	var col:Color = Color(1, 1, 1)
	func _draw():
		draw_circle(rect_size / 2, rect_size.x / 2, col)

# the accuracy ring around the grade: a faint full track, the accuracy part sweeping in
class GradeRing extends Control:
	var col:Color = Color(1, 1, 1)
	var center:Vector2
	var radius:float = 100.0
	var frac:float = 1.0
	var k:float = 0.0 # 0..1 animation time
	func _draw():
		var R = load("res://mods/replay/Ring.gd")
		R.arc(self, center, radius, 10.0, 0, TAU, Color(1, 1, 1, 0.06))
		if k <= 0: return
		var e = 1.0 - pow(1.0 - k, 3) # ease out: fast start, soft landing
		R.arc(self, center, radius, 10.0, -PI / 2, -PI / 2 + TAU * frac * e, Color(col.r, col.g, col.b, 0.95), true)
		R.arc(self, center, radius + 14, 1.5, 0, TAU, Color(col.r, col.g, col.b, 0.12 * e))

func _button(bar:Control, text:String, cb:String):
	var b = Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(0, 50)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if ResourceLoader.exists("res://uitheme.tres"): b.theme = load("res://uitheme.tres")
	var main = cb == "_retry"
	var n = CardUI.box(Color(0.06, 0.06, 0.07, 0.85) if !main else Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.2), ACCENT if main else Color(1, 1, 1, 0.22), 1 if !main else 2, 14)
	var h = CardUI.box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.24), ACCENT.lightened(0.3), 2, 14)
	var pr = CardUI.box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.36), ACCENT.lightened(0.3), 2, 14)
	for s in ["normal", "focus", "disabled"]: b.add_stylebox_override(s, n)
	b.add_stylebox_override("hover", h)
	b.add_stylebox_override("pressed", pr)
	for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_focus"]: b.add_color_override(k, Color(1, 1, 1))
	b.add_font_override("font", _f(17))
	b.connect("mouse_entered", sfx, "play", ["click-short.ogg", -10.0])
	b.connect("pressed", self, cb)
	bar.add_child(b)
	return b

func _status() -> Array:
	if run.replay: return ["Replay", Color("#9ad0ff")]
	if run.end_type != Globals.END_PASS: return [("Failed" if run.end_type == Globals.END_FAIL else "Gave up") + (" (resumed)" if run.get("resumed") else ""), Color("#ff6b6b")]
	if run.pauses > 0: return ["Disqualified (paused)", Color("#ffb35e")]
	if run.get("resumed"): return ["Cleared (resumed)", Color("#ffb35e")]
	return ["Cleared", Color("#5cdb9a")]

func _grade(acc:float) -> Array: # [shown, skin image, colour] (EndInfo.gd thresholds)
	if run.end_type != Globals.END_PASS: return ["F", "D", Color("#ff6b6b")]
	if acc >= 1.0: return ["SS", "X", Color("#ffe27a")]
	if acc >= 0.98: return ["S", "S", Color("#5cc8ff")]
	if acc >= 0.95: return ["A", "A", Color("#91ff92")]
	if acc >= 0.90: return ["B", "B", Color("#e7ffc0")]
	if acc >= 0.85: return ["C", "C", Color("#fcf7b3")]
	return ["D", "D", Color("#fcd0b3")]

# ------------------------------------------------------------------ animation
func _process(delta):
	t += delta
	shake = max(0.0, shake - delta / 0.28)
	if flash:
		flash.color.a = max(0.0, flash.color.a - delta / 0.22)
		if flash.color.a <= 0.0:
			flash.queue_free()
			flash = null
	_layout()
	if board:
		_tally()
		return
	# score counts up over 1.2 s (ease out)
	var k = clamp(t / 1.2, 0.0, 1.0)
	var shown = int(run.score * (1.0 - pow(1.0 - k, 3)))
	score_label.text = ("%08d" % shown) if mono else Globals.comma_sep(shown) # (osu!-style zero padded score in the personal build)
	if !stamped and t > 1.25:
		stamped = true
		_stamp()
	if Rhythia.has_meta("last_run_best") and best_label.text == "":
		if Rhythia.get_meta("last_run_best"): best_label.text = "NEW PERSONAL BEST!"

func _stamp():
	if mono and CardUI._has("fx_on") and load(CardUI.LOOK).fx_on() and !run.get("stored"): # decisive payoff: a short red / white hit on S, SS and a failed run
		var Look = load(CardUI.LOOK)
		var gk = _grade(float(run.hits) / max(1.0, float(run.total)))[0]
		if gk in ["SS", "S", "F"]:
			var fc = Look.CRIT if gk == "F" else Look.hot()
			flash = ColorRect.new()
			flash.color = Color(fc.r, fc.g, fc.b, 0.3 if gk != "S" else 0.22)
			flash.anchor_right = 1; flash.anchor_bottom = 1
			flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
			get_child(0).add_child(flash)
			shake = 1.0
	grade_text.modulate.a = 1
	grade_text.rect_scale = Vector2(1.3, 1.3) # (pops in, settles inside the ring)
	var passed = run.end_type == Globals.END_PASS and !run.replay
	if run.get("stored"):
		sfx.play("menuclick.ogg", -8.0)
		return
	sfx.play("menuclick.ogg" if passed else "sectionfail.mp3", -8.0 if passed else -6.0)

func _layout():
	var size = get_viewport().get_visible_rect().size
	var mouse = get_viewport().get_mouse_position()
	var hs = holder.rect_size
	var k = clamp(min((size.y - 120.0) / hs.y, (size.x - 40.0) / hs.x), 0.4, 1.0) # (short windows: shrink so the button bar stays below the card)
	holder.rect_scale = Vector2(k, k)
	var target = Vector2((size.x - hs.x * k) / 2, max(12.0, (size.y - 108.0 - hs.y * k) / 2)) + (size / 2 - mouse) * (6.0 / size.y)
	if shake > 0.0: target += Vector2(randf() - 0.5, randf() - 0.5) * 22.0 * shake # (short impact shake)
	var dt = get_process_delta_time() # (smoothing by time, not per frame: same feel at any fps)
	holder.rect_position = holder.rect_position.linear_interpolate(target, 1.0 - exp(-dt * 12.0)) if t > 0.05 else target
	grade_text.rect_scale = grade_text.rect_scale.linear_interpolate(Vector2.ONE, 1.0 - exp(-dt * 11.0))
	if bd: # the backdrop drifts a little with the mouse, like the menu's
		bd.rect_pivot_offset = size / 2
		var z = bd_zoom if bd_zoom > 0.0 else 1.03
		bd.rect_scale = Vector2(z, z)
		if bd_zoom <= 0.0: bd.rect_position = (size / 2 - mouse) * (14.0 / size.y)
	if grade_ring and stamped and grade_ring.k < 1.0: # ring sweeps in after the grade stamp
		grade_ring.k = min(1.0, grade_ring.k + dt / 0.8)
		grade_ring.update()

# ------------------------------------------------------------------ actions
func _input(ev):
	if board and !closing and t < T_RANK and ev.is_pressed() and ((ev is InputEventMouseButton and ev.button_index <= BUTTON_MIDDLE) or (ev is InputEventKey and ev.scancode in [KEY_SPACE, KEY_ENTER])):
		_skip_tally() # (a click / Space / Enter: the whole tally at once)
		get_tree().set_input_as_handled()
		return
	if closing or !(ev is InputEventKey) or !ev.pressed or ev.echo: return
	if menu.has_node("ReplayStudio"): return # (Esc closes the studio over it first)
	if ev.scancode == KEY_ESCAPE: _back()
	elif ev.scancode == KEY_QUOTELEFT: _retry()
	else: return
	get_tree().set_input_as_handled()

func _back():
	if closing: return
	closing = true
	sfx.play("menuback.wav", -6.0)
	var a = UIAnim.play(get_child(0), Vector2.ZERO, Vector2.ZERO, 1.0, 0.0, 0.22)
	a.connect("finished", self, "queue_free")

func _retry():
	if closing: return
	closing = true
	sfx.play("menuhit.mp3", -6.0)
	Rhythia.replaying = false
	_go("res://scenes/loaders/songload.tscn")

# Checkpoint.gd: the same map from the last exact snapshot before the fail, with its state back
func _mmss(ms:float) -> String:
	return "%d:%02d" % [int(ms / 60000), int(ms / 1000) % 60]

func _retry_resume():
	if closing or !run.get("resume"): return
	closing = true
	sfx.play("menuhit.mp3", -6.0)
	Rhythia.replaying = false
	load("res://mods/replay/Checkpoint.gd").start(run.resume)
	_go("res://scenes/loaders/songload.tscn")

func _watch():
	if closing: return
	closing = true
	sfx.play("menuhit.mp3", -6.0)
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = run.replay_path
	_go("res://scenes/loaders/songload.tscn")

# Replay Studio (ReplayStudio.gd) over the results: graphs, heatmap, aim of the run just played
func _analyse():
	if closing or menu.has_node("ReplayStudio"): return
	sfx.play("menuhit.mp3", -6.0)
	load("res://mods/replay/ReplayStudio.gd").open(menu, run.replay_path)

# into the loading screen: the card fades, the cover stays and zooms like a map page start
func _go(scene:String):
	Engine.set_meta("rr_launch", {t = OS.get_ticks_msec(), seamless = bd != null and bd.texture != null, scale = 1.03,
		offset = -bd.rect_position / 12.0 if bd else Vector2.ZERO})
	var root = get_child(0)
	var a = UIAnim.play(holder, Vector2.ZERO, Vector2.ZERO, 1.0, 0.0, 0.3)
	for c in root.get_children():
		if c is BoxContainer: UIAnim.play(c, Vector2.ZERO, Vector2(0, 20), 1.0, 0.0, 0.25)
	var t0 = OS.get_ticks_msec()
	while OS.get_ticks_msec() - t0 < 450:
		var e = (OS.get_ticks_msec() - t0) / 450.0
		var z = 1.03 * (1.0 + 0.1 * e * e * (3.0 - 2.0 * e))
		bd_zoom = z
		Engine.get_meta("rr_launch")["scale"] = z
		if bg_fx: bg_fx.modulate.a = 1.0 - e # (the loading screen opens on the plain cover)
		yield(get_tree(), "idle_frame")
	get_tree().change_scene(scene)

func _cover(on:bool):
	if on:
		var main = menu.get_node_or_null("Main")
		if main:
			for p in main.get_children():
				if p is Control and p.visible:
					p.visible = false
					covered.append(p)
	else:
		for p in covered:
			if is_instance_valid(p): p.visible = true
		covered = []

func _exit_tree():
	_cover(false)
	if Rhythia.has_meta("last_run_best"): Rhythia.remove_meta("last_run_best")

# ------------------------------------------------------------------ the tally board (personal build)
# This card's look (dark panel, corner brackets, the blurred cover) with ULTRAKILL's results layout:
# the title and "-- difficulty --" in VCR mono, three stat rows (accuracy / combo / misses) each with
# its own rank letter in a box, a big rank square, bonus lines, mods, hits and the total, over the
# cover pixelated and tinted in the rank's colour. They tally in one by one (counting values with
# ticks, the ranks popping in), then the big rank stamps; a click / Space / Enter skips to the end.
const BW = 940.0
const BH = 760.0
const UK_FONT = "res://assets/font/UbuntuMono/Regular.ttf" # (= VCR OSD Mono in this build)
const RANK_COL = {"SS": Color("#f0b020"), "S": Color("#ff2a2a"), "A": Color("#ff8a1e"), "B": Color("#ffd23c"),
	"C": Color("#4ccf5a"), "D": Color("#3b8cff"), "F": Color("#8a1018")}
const T_ROW0 = 0.3     # the first row
const T_ROW = 0.3      # between rows
const T_BONUS = 1.25
const T_TOTAL = 1.5
const T_RANK = 2.1     # the big rank stamps
const BG_SHADER = """shader_type canvas_item;
uniform float px = 14.0;
uniform vec4 tint = vec4(0.0, 0.0, 0.0, 0.5);
void fragment() {
	vec2 sz = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = (floor(SCREEN_UV * sz / px) + 0.5) * px / sz;
	vec3 c = texture(SCREEN_TEXTURE, uv).rgb;
	COLOR = vec4(mix(c, tint.rgb, tint.a), 1.0);
}"""

var board:bool = false
var bg_fx:ColorRect = null
var rows = []          # {at, panel, value, target, fmt, box, ranked}
var bonuses = []       # {at, node, shown}
var rank_sq:Panel = null
var skipping:bool = false
var next_tick:float = 0.0
var vf = {}

func _v(size:int):
	if vf.has(size): return vf[size]
	var f = null
	if ResourceLoader.exists(UK_FONT):
		f = DynamicFont.new()
		f.font_data = load(UK_FONT)
		f.size = size
	else: f = _f(size)
	vf[size] = f
	return f

func _uk_label(parent:Control, text:String, size:int, col:Color, pos:Vector2, w:float = 0.0, align:int = Label.ALIGN_LEFT) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", _v(size))
	l.add_color_override("font_color", col)
	l.rect_position = pos
	if w > 0: l.rect_size = Vector2(w, 0)
	l.align = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _dark(parent:Control, r:Rect2, a:float = 0.38) -> ColorRect:
	var c = ColorRect.new()
	c.color = Color(0, 0, 0, a)
	c.rect_position = r.position
	c.rect_size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c

static func row_rank(kind:String, run_:Dictionary) -> String:
	var total = max(1.0, float(run_.total))
	if kind == "acc":
		var a = float(run_.hits) / total
		return "S" if a >= 0.98 else ("A" if a >= 0.95 else ("B" if a >= 0.90 else ("C" if a >= 0.85 else "D")))
	if kind == "combo":
		if run_.misses == 0 and run_.end_type == Globals.END_PASS: return "S"
		var c = float(run_.combo) / total
		return "A" if c >= 0.75 else ("B" if c >= 0.5 else ("C" if c >= 0.25 else "D"))
	var m = float(run_.misses) / total
	return "S" if m == 0.0 else ("A" if m <= 0.01 else ("B" if m <= 0.03 else ("C" if m <= 0.06 else "D")))

func _build_board(root:Control):
	board = true
	var song = run.song
	var acc = float(run.hits) / max(1.0, float(run.total))
	var g = _grade(acc)
	var rc:Color = RANK_COL.get(g[0], Color(1, 1, 1))
	# the cover, pixelated and tinted in the rank's colour (over the blurred backdrop, under the board)
	bg_fx = ColorRect.new()
	bg_fx.anchor_right = 1; bg_fx.anchor_bottom = 1
	bg_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_fx.material = ShaderMaterial.new()
	bg_fx.material.shader = Shader.new()
	bg_fx.material.shader.code = BG_SHADER
	bg_fx.material.set_shader_param("tint", Color(rc.r * 0.3, rc.g * 0.3, rc.b * 0.3, 0.8))
	root.add_child(bg_fx)

	holder = Panel.new()
	if ResourceLoader.exists("res://uitheme.tres"): holder.theme = load("res://uitheme.tres")
	var sb = CardUI.box(Color(0.03, 0.03, 0.035, 0.62), Color(1, 1, 1, 0.1), 1, 18)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 36
	holder.add_stylebox_override("panel", sb)
	root.add_child(holder)
	holder.rect_size = Vector2(BW, BH)
	holder.connect("draw", self, "_draw_frame")

	# ---- header: status, title, -- difficulty --, the map line
	var st = _status()
	var stxt = "// " + st[0].to_upper()
	if run.end_type != Globals.END_PASS and !run.replay:
		stxt += "  AT %s (%d%%)" % [_mmss(run.position), int(clamp(run.position / max(1.0, run.length), 0, 1) * 100)]
	_uk_label(holder, stxt, 18, st[1], Vector2(0, 22), BW, Label.ALIGN_CENTER)
	var title = ("[REPLAY] " if run.replay else "") + (song.name if song else "?")
	_uk_label(holder, CardUI.fit(title.to_upper(), _v(44), BW - 80), 44, Color(1, 1, 1), Vector2(0, 46), BW, Label.ALIGN_CENTER)
	var d = CardUI.difficulty(song)
	_uk_label(holder, "-- %s --" % (d[0].to_upper() if d[0] != "" else "UNRATED"), 26, Color(1, 1, 1, 0.9), Vector2(0, 100), BW, Label.ALIGN_CENTER)
	var info = []
	var stars = CardUI.stars(song, run.speed)
	if stars > 0: info.append("★ %.2f" % stars)
	if run.length > 0: info.append(CardUI.mmss(float(run.length) / max(0.01, run.speed)))
	info.append("mapped by " + (str(song.creator) if song else "?"))
	var il = CardUI.label(holder, PoolStringArray(info).join("   ·   "), _f(15), Color(1, 1, 1, 0.45), Vector2(0, 138), BW)
	il.align = Label.ALIGN_CENTER

	# ---- the three rows, each with its rank
	var defs = [["ACCURACY:", acc * 100.0, "%.2f%%", "acc"], ["COMBO:", float(run.combo), "%dx", "combo"], ["MISSES:", float(run.misses), "%d", "miss"]]
	for i in defs.size():
		var y = 184.0 + i * 100.0
		var panel = Control.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(panel)
		_dark(panel, Rect2(40, y, 430, 84))
		_uk_label(panel, defs[i][0], 30, Color(1, 1, 1, 0.62), Vector2(62, y + 24))
		var val = _uk_label(panel, "", 30, Color(1, 1, 1), Vector2(250, y + 24), 200, Label.ALIGN_RIGHT)
		var rk = row_rank(defs[i][3], run)
		var box = Control.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.rect_position = Vector2(482, y)
		box.rect_size = Vector2(76, 84)
		box.rect_pivot_offset = box.rect_size / 2
		holder.add_child(box)
		_dark(box, Rect2(Vector2.ZERO, box.rect_size))
		_uk_label(box, rk, 54, RANK_COL[rk], Vector2(0, 10), 76, Label.ALIGN_CENTER)
		panel.modulate.a = 0.0
		box.modulate.a = 0.0
		rows.append({at = T_ROW0 + i * T_ROW, panel = panel, value = val, target = defs[i][1], fmt = defs[i][2], box = box, ranked = false})

	# ---- the big rank square (the grade, white on its colour)
	rank_sq = Panel.new()
	rank_sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs = StyleBoxFlat.new()
	rs.bg_color = rc
	rank_sq.add_stylebox_override("panel", rs)
	rank_sq.rect_position = Vector2(600, 184)
	rank_sq.rect_size = Vector2(284, 284)
	rank_sq.rect_pivot_offset = rank_sq.rect_size / 2
	holder.add_child(rank_sq)
	grade_text = _uk_label(rank_sq, g[0], 230 if g[0].length() == 1 else 150, Color(1, 1, 1), Vector2.ZERO, 284, Label.ALIGN_CENTER)
	grade_text.valign = Label.VALIGN_CENTER
	grade_text.rect_size = Vector2(284, 284)
	grade_text.rect_pivot_offset = grade_text.rect_size / 2
	grade_text.modulate.a = 0.0
	rank_sq.modulate.a = 0.0

	# ---- bonus lines (+ good / - bad), mods, hits, total
	var lines = []
	if run.replay: lines.append(["+ REPLAY", Color(0.6, 0.82, 1)])
	if run.end_type == Globals.END_PASS and run.misses == 0: lines.append(["+ FULL COMBO", Color(1, 1, 1)])
	if run.end_type == Globals.END_PASS and run.pauses == 0 and !run.replay: lines.append(["+ NO PAUSES", Color(1, 1, 1)])
	if run.pauses > 0: lines.append(["- PAUSED x%d" % run.pauses, Color("#ff5a5a")])
	if run.get("resumed"): lines.append(["- RESUMED", Color("#ffb35e")])
	if run.end_type == Globals.END_FAIL: lines.append(["- ENERGY DEPLETED", Color("#ff5a5a")])
	elif run.end_type == Globals.END_GIVEUP: lines.append(["- GAVE UP", Color("#ff5a5a")])
	if lines.empty(): lines.append(["+ CLEARED", Color(1, 1, 1)])
	for i in min(lines.size(), 3):
		var l = _uk_label(holder, lines[i][0], 24, lines[i][1], Vector2(62, 500 + i * 36))
		l.modulate.a = 0.0
		bonuses.append({at = T_BONUS + i * 0.1, node = l, shown = false})
	var ml = _uk_label(holder, "MODS:", 24, Color(1, 1, 1, 0.62), Vector2(600, 500))
	var mods = run.get("mods", null)
	if mods == null: mods = current_mods()
	var tags = []
	var spd = CardUI.speed_tag(run.speed)
	if spd != "": tags.append(spd)
	for m in mods: tags.append(SHORT.get(m, m))
	var mv = _uk_label(holder, CardUI.fit(PoolStringArray(tags).join("  ") if !tags.empty() else "-", _v(24), 284), 24, Color(1, 1, 1), Vector2(600, 540))
	for n in [ml, mv]: n.modulate.a = 0.0
	bonuses.append({at = T_BONUS, node = ml, shown = false})
	bonuses.append({at = T_BONUS + 0.1, node = mv, shown = false})
	var hits_row = Control.new()
	hits_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(hits_row)
	_uk_label(hits_row, "HITS:", 28, Color(1, 1, 1, 0.62), Vector2(62, 628))
	_uk_label(hits_row, "%s / %s" % [Globals.comma_sep(run.hits), Globals.comma_sep(run.total)], 28, Color(1, 1, 1), Vector2(250, 628), 220, Label.ALIGN_RIGHT)
	hits_row.modulate.a = 0.0
	bonuses.append({at = T_TOTAL - 0.1, node = hits_row, shown = false})
	var tl = _uk_label(holder, "TOTAL:", 28, Color(1, 1, 1, 0.62), Vector2(600, 628))
	tl.modulate.a = 0.0
	bonuses.append({at = T_TOTAL, node = tl, shown = false})
	score_label = _uk_label(holder, "", 28, Color(1, 1, 1), Vector2(690, 628), 210, Label.ALIGN_RIGHT)
	best_label = _uk_label(holder, "", 20, Color("#ffd75e"), Vector2(560, 672), 340, Label.ALIGN_RIGHT)
	var name_ = CardUI.player()
	var when_ = ("played " + str(run.when)) if run.get("stored") and run.get("when") else CardUI.today()
	CardUI.label(holder, ("played by %s  ·  " % name_ if name_ != "" else "") + when_, _f(15), Color(1, 1, 1, 0.38), Vector2(40, BH - 38), BW - 80)

func _tick(db:float = -15.0):
	if skipping or t < next_tick: return
	next_tick = t + 0.045
	sfx.play("click-short.ogg", db)

func _tally():
	var dt = get_process_delta_time()
	for r in rows:
		if t < r.at: continue
		var k = clamp((t - r.at) / 0.24, 0.0, 1.0)
		var e = 1.0 - pow(1.0 - k, 2)
		r.panel.modulate.a = min(1.0, (t - r.at) / 0.08)
		r.value.text = (r.fmt % (r.target * e)) if r.fmt == "%.2f%%" else (r.fmt % int(round(r.target * e)))
		if k < 1.0: _tick()
		if !r.ranked and t >= r.at + 0.27:
			r.ranked = true
			r.box.modulate.a = 1.0
			r.box.rect_scale = Vector2(1.6, 1.6)
			if !skipping: sfx.play("menuclick.ogg", -9.0)
		if r.ranked: r.box.rect_scale = r.box.rect_scale.linear_interpolate(Vector2.ONE, 1.0 - exp(-dt * 16.0))
	for b in bonuses:
		if t < b.at: continue
		b.node.modulate.a = min(1.0, (t - b.at) / 0.08)
		if !b.shown:
			b.shown = true
			if !skipping: sfx.play("click-short.ogg", -11.0)
	if t >= T_TOTAL:
		var k = clamp((t - T_TOTAL) / 0.5, 0.0, 1.0)
		score_label.text = Globals.comma_sep(int(run.score * (1.0 - pow(1.0 - k, 3))))
		if k < 1.0: _tick(-17.0)
	if !stamped and t >= T_RANK:
		stamped = true
		rank_sq.modulate.a = 1.0
		rank_sq.rect_scale = Vector2(1.35, 1.35)
		_stamp()
	if stamped: rank_sq.rect_scale = rank_sq.rect_scale.linear_interpolate(Vector2.ONE, 1.0 - exp(-dt * 12.0))
	if Rhythia.has_meta("last_run_best") and best_label.text == "":
		if Rhythia.get_meta("last_run_best"): best_label.text = "+ NEW PERSONAL BEST"
	skipping = false

func _skip_tally():
	skipping = true
	t = T_RANK + 0.6 # (past every count: all values whole)
	_tally()
