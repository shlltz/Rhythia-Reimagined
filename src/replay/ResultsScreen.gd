extends CanvasLayer
# osu!-style results screen, laid out after the rewrite's Results scene (scenes/results.tscn):
# blurred cover background, a floating panel (mouse parallax) with title / mappers / difficulty,
# status (PASSED / DISQUALIFIED / FAILED / REPLAY), score, accuracy, hits, speed and mods, plus
# Back / Retry / Watch replay. Osu touches: counting score, grade stamp + applause (osuskin mod).
# Esc / Back = map selection, ` = retry. Data comes from Game.gd (Rhythia meta "last_run").

const UIAnim = preload("res://mods/replay/UIAnim.gd")
const OsuSfx = preload("res://mods/replay/OsuSfx.gd")
const W = 1180.0
const H = 660.0
const ACCENT = Color("#8a6cff")
const DIFFS = ["Easy", "Medium", "Hard", "Logic", "Tasukete"]
const MODS = [["mod_nofail", "NoFail"], ["mod_sudden_death", "SuddenDeath"], ["mod_hardrock", "HardRock"],
	["mod_flashlight", "Flashlight"], ["mod_ghost", "Ghost"], ["mod_nearsighted", "Nearsighted"],
	["mod_chaos", "Chaos"], ["mod_earthquake", "Earthquake"], ["mod_mirror_x", "MirrorX"],
	["mod_mirror_y", "MirrorY"], ["mod_extra_energy", "ExtraEnergy"], ["mod_no_regen", "NoRegen"]]
const BLUR = """
shader_type canvas_item;
void fragment() { COLOR = textureLod(TEXTURE, UV, 3.5) * vec4(0.32, 0.32, 0.32, 1.0); }
"""

var menu:Node
var sfx:Node
var run:Dictionary
var holder:Control
var score_label:Label
var grade_text:Label
var best_label:Label
var covered:Array = []
var t:float = 0.0
var stamped:bool = false
var closing:bool = false

func _init(data:Dictionary):
	run = data

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
	back.color = Color(0.04, 0.04, 0.05)
	back.anchor_right = 1; back.anchor_bottom = 1
	root.add_child(back)
	var cover_tex = song.cover if song and song.has_cover else null
	if cover_tex:
		var cb = TextureRect.new()
		var img = cover_tex.get_data()
		if img:
			var tex = ImageTexture.new()
			tex.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
			cb.texture = tex
		cb.expand = true
		cb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		cb.anchor_right = 1; cb.anchor_bottom = 1
		var mat = ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = BLUR
		cb.material = mat
		root.add_child(cb)

	holder = Panel.new()
	if ResourceLoader.exists("res://uitheme.tres"): holder.theme = load("res://uitheme.tres") # game font (modded font if installed)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.055, 0.86)
	sb.set_corner_radius_all(16)
	sb.corner_detail = 8
	sb.anti_aliasing = true
	sb.border_color = Color(1, 1, 1, 0.2)
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 24
	holder.add_stylebox_override("panel", sb)
	root.add_child(holder)
	holder.rect_size = Vector2(W, H)

	var c = TextureRect.new()
	c.texture = cover_tex
	c.expand = true
	c.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	holder.add_child(c)
	c.rect_position = Vector2(32, 32); c.rect_size = Vector2(150, 150)
	_tile(Rect2(30, 30, 154, 154), Color(1, 1, 1, 0.35), 8, false) # cover frame
	var title = ("[REPLAY] " if run.replay else "") + (song.name if song else "?")
	_label(title, Vector2(206, 34), 1.5, Color(1, 1, 1), 640)
	var diff = song.custom_data.get("difficulty_name", "") if song else ""
	if diff == "" and song and song.difficulty >= 0 and song.difficulty < DIFFS.size(): diff = DIFFS[song.difficulty]
	_label(("by " + song.creator if song else "") + ("   ·   " + diff if diff != "" else ""), Vector2(206, 84), 1.0, Color(1, 1, 1, 0.6), 640)
	var st = _status()
	var pill = _label(st[0], Vector2(220, 124), 1.1, st[1], 0)
	var pw = pill.get_font("font").get_string_size(st[0]).x if pill.get_font("font") else 120.0
	_tile(Rect2(206, 120, pw + 30, 34), st[1], 17, false, true)
	holder.move_child(pill, holder.get_child_count() - 1)
	best_label = _label("", Vector2(206, 158), 1.0, Color("#ffd75e"), 640)
	if run.get("when"):
		best_label.text = "played " + run.when
		best_label.modulate = Color(1, 1, 1, 0.5)

	var line = ColorRect.new() # divider under the header
	line.color = Color(1, 1, 1, 0.1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(line)
	line.rect_position = Vector2(32, 204); line.rect_size = Vector2(W - 470, 1) # (stops before the grade ring)
	_tile(Rect2(32, 222, 572, 116), Color(1, 1, 1, 0.16), 12)
	_label("SCORE", Vector2(50, 232), 0.85, Color(1, 1, 1, 0.5))
	score_label = _label("0", Vector2(48, 250), 3.2, Color(1, 1, 1))
	var acc = float(run.hits) / max(1.0, float(run.total))
	var rows = [
		["Accuracy", "%.2f%%" % (acc * 100)],
		["Hits", "%s / %s" % [Globals.comma_sep(run.hits), Globals.comma_sep(run.total)]],
		["Misses", Globals.comma_sep(run.misses)],
		["Max combo", Globals.comma_sep(run.combo) + ("  (FC)" if run.misses == 0 and run.end_type == Globals.END_PASS else "")],
		["Speed", "%.2fx" % run.speed],
		["Pauses", str(run.pauses)],
	]
	if run.end_type != Globals.END_PASS:
		rows.append(["Progress", "%.1f%%" % (clamp(run.position / max(1.0, run.length), 0, 1) * 100)])
	var stars = _stars(song)
	if stars > 0: rows.append(["Stars", "%.2f" % stars])
	for i in rows.size(): # one outlined tile per stat, two columns
		var x = 32 + (i % 2) * 290
		var y = 354 + int(i / 2) * 60
		_tile(Rect2(x, y, 282, 52), Color(1, 1, 1, 0.14), 10)
		_label(rows[i][0].to_upper(), Vector2(x + 16, y + 6), 0.7, Color(1, 1, 1, 0.5))
		_label(rows[i][1], Vector2(x + 16, y + 20), 1.2, Color(1, 1, 1))
	var mods = run.get("mods", null)
	if mods == null:
		mods = []
		for m in MODS:
			if Rhythia.get(m[0]): mods.append(m[1])
	if mods.size() > 0: _label("Mods   " + PoolStringArray(mods).join("  ·  "), Vector2(34, H - 40), 0.9, Color(1, 1, 1, 0.6), 640)

	var g = _grade(acc)
	grade_text = _label(g[0], Vector2(W - 420, 120), 15.0, g[2], 380)
	grade_text.align = Label.ALIGN_CENTER
	grade_text.rect_pivot_offset = grade_text.rect_size / 2
	grade_text.modulate.a = 0
	var ring = GradeRing.new() # thin ring in the grade colour behind the letter
	ring.col = g[2]
	ring.center = Vector2(W - 230, 352)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ring)
	holder.move_child(ring, grade_text.get_index())
	ring.rect_size = Vector2(W, H)
	grade_ring = ring

	var bar = HBoxContainer.new()
	bar.anchor_left = 0.5; bar.anchor_right = 0.5; bar.anchor_top = 1; bar.anchor_bottom = 1
	bar.margin_left = -330; bar.margin_right = 330; bar.margin_top = -96; bar.margin_bottom = -40
	bar.add_constant_override("separation", 16)
	root.add_child(bar)
	_button(bar, "Back", "_back")
	_button(bar, "Retry", "_retry")
	if run.replay_path != "" and File.new().file_exists(run.replay_path): _button(bar, "Watch replay", "_watch")

	_cover(true)
	UIAnim.play(root, Vector2.ZERO, Vector2.ZERO, 0.0, 1.0, 0.3)
	_layout()

static func current_mods() -> Array:
	var out = []
	for m in MODS:
		if Rhythia.get(m[0]): out.append(m[1])
	return out

func _label(text:String, pos:Vector2, scale:float, col:Color, width:float = 0) -> Label:
	var l = Label.new()
	l.text = text
	l.modulate = col
	holder.add_child(l)
	l.rect_position = pos
	var f = _font(int(round(scale * 18)))
	if f: l.add_font_override("font", f)
	else: l.rect_scale = Vector2(scale, scale)
	if width > 0:
		l.clip_text = true
		l.rect_size.x = width / (1.0 if f else scale)
	return l

var fonts:Dictionary = {}
func _font(size:int):
	if fonts.has(size): return fonts[size]
	var base = holder.get_font("font", "Label")
	var f = null
	if base is DynamicFont:
		f = base.duplicate()
		f.size = size
	fonts[size] = f
	return f

class GradeRing extends Control:
	var col:Color = Color(1, 1, 1)
	var center:Vector2
	var k:float = 0.0 # 0..1 animation time
	func _draw():
		if k <= 0: return
		var R = load("res://mods/replay/Ring.gd")
		var e = 1.0 - pow(1.0 - k, 3) # ease out: fast start, soft landing
		R.arc(self, center, 182, 1.5, 0, TAU, Color(col.r, col.g, col.b, 0.14 * e))
		R.arc(self, center, 168, 3.0, -PI / 2, -PI / 2 + TAU * e, Color(col.r, col.g, col.b, 0.6), true)

var grade_ring = null

static func _sbox(bg:Color, border:Color, w:int, r:int) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(r)
	sb.corner_detail = 6
	sb.anti_aliasing = true
	sb.draw_center = bg.a > 0
	return sb

# outlined, rounded box on the panel (stat tiles, frames, the status pill)
func _tile(r:Rect2, border:Color, radius:int, fill:bool = true, tint:bool = false) -> Panel:
	var p = Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg = Color(border.r, border.g, border.b, 0.1) if tint else (Color(1, 1, 1, 0.03) if fill else Color(0, 0, 0, 0))
	p.add_stylebox_override("panel", _sbox(bg, border, 2 if tint else 1, radius))
	holder.add_child(p)
	p.rect_position = r.position
	p.rect_size = r.size
	return p

func _button(bar:Control, text:String, cb:String):
	var b = Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(0, 50)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if ResourceLoader.exists("res://uitheme.tres"): b.theme = load("res://uitheme.tres")
	var main = cb == "_retry"
	var n = _sbox(Color(0, 0, 0, 0.45), ACCENT if main else Color(1, 1, 1, 0.4), 2, 12)
	var h = _sbox(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18), ACCENT.lightened(0.3), 2, 12)
	var pr = _sbox(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.32), ACCENT.lightened(0.3), 2, 12)
	for s in ["normal", "focus", "disabled"]: b.add_stylebox_override(s, n)
	b.add_stylebox_override("hover", h)
	b.add_stylebox_override("pressed", pr)
	for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_focus"]: b.add_color_override(k, Color(1, 1, 1))
	b.connect("mouse_entered", sfx, "play", ["click-short.ogg", -10.0])
	b.connect("pressed", self, cb)
	bar.add_child(b)

func _status() -> Array:
	if run.replay: return ["REPLAY", Color("#9ad0ff")]
	if run.end_type != Globals.END_PASS: return ["FAILED" if run.end_type == Globals.END_FAIL else "GAVE UP", Color("#ff6b6b")]
	if run.pauses > 0: return ["DISQUALIFIED (paused)", Color("#ffb35e")]
	return ["PASSED", Color("#6ff1a0")]

func _grade(acc:float) -> Array: # [shown, skin image, colour] (EndInfo.gd thresholds)
	if run.end_type != Globals.END_PASS: return ["F", "D", Color("#ff6b6b")]
	if acc >= 1.0: return ["SS", "X", Color("#ffe27a")]
	if acc >= 0.98: return ["S", "S", Color("#91fffa")]
	if acc >= 0.95: return ["A", "A", Color("#91ff92")]
	if acc >= 0.90: return ["B", "B", Color("#e7ffc0")]
	if acc >= 0.85: return ["C", "C", Color("#fcf7b3")]
	return ["D", "D", Color("#fcd0b3")]

func _stars(song) -> float:
	if !song or !ResourceLoader.exists("res://mods/stars/StarCache.gd"): return 0.0
	var sc = load("res://mods/stars/StarCache.gd").get_instance(get_tree())
	return sc.get_stars_at_now(song, run.speed) if sc else 0.0

# ------------------------------------------------------------------ animation
func _process(delta):
	t += delta
	_layout()
	# score counts up over 1.2 s (ease out), ticking
	var k = clamp(t / 1.2, 0.0, 1.0)
	var shown = int(run.score * (1.0 - pow(1.0 - k, 3)))
	score_label.text = Globals.comma_sep(shown)
	if !stamped and t > 1.25:
		stamped = true
		_stamp()
	if Rhythia.has_meta("last_run_best") and best_label.text == "":
		if Rhythia.get_meta("last_run_best"): best_label.text = "NEW PERSONAL BEST!"

func _stamp():
	grade_text.modulate.a = 1
	grade_text.rect_scale = Vector2(1.6, 1.6)
	var passed = run.end_type == Globals.END_PASS and !run.replay
	if run.get("stored"):
		sfx.play("menuclick.ogg", -8.0)
		return
	sfx.play("menuclick.ogg" if passed else "sectionfail.mp3", -8.0 if passed else -6.0) # no applause music

func _layout():
	var size = get_viewport().get_visible_rect().size
	var mouse = get_viewport().get_mouse_position()
	var target = (size - Vector2(W, H)) / 2 + (size / 2 - mouse) * (8.0 / size.y) - Vector2(0, 30)
	var dt = get_process_delta_time() # (smoothing by time, not per frame: same feel at any fps)
	holder.rect_position = holder.rect_position.linear_interpolate(target, 1.0 - exp(-dt * 12.0)) if t > 0.05 else target
	grade_text.rect_scale = grade_text.rect_scale.linear_interpolate(Vector2.ONE, 1.0 - exp(-dt * 11.0))
	if grade_ring and stamped: # ring sweeps in after the grade stamp
		var c = grade_text.rect_position + grade_text.rect_size / 2
		if grade_ring.k < 1.0 or !c.is_equal_approx(grade_ring.center):
			grade_ring.center = c
			grade_ring.k = min(1.0, grade_ring.k + dt / 0.7)
			grade_ring.update()

# ------------------------------------------------------------------ actions
func _input(ev):
	if closing or !(ev is InputEventKey) or !ev.pressed or ev.echo: return
	if ev.scancode == KEY_ESCAPE: _back()
	elif ev.scancode == KEY_QUOTELEFT: _retry()
	else: return
	get_tree().set_input_as_handled()

func _back():
	print("DBG %d results _back closing %s" % [OS.get_ticks_msec(), closing])
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

func _watch():
	if closing: return
	closing = true
	sfx.play("menuhit.mp3", -6.0)
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = run.replay_path
	_go("res://scenes/loaders/songload.tscn")

func _go(scene:String):
	if "black_fade_target" in menu: menu.black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
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
	print("DBG %d results exit, restoring %d" % [OS.get_ticks_msec(), covered.size()])
	_cover(false)
	if Rhythia.has_meta("last_run_best"): Rhythia.remove_meta("last_run_best")
