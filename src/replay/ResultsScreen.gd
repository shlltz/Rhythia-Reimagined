extends CanvasLayer
# osu!-style results screen, laid out after the rewrite's Results scene (scenes/results.tscn):
# blurred cover background, a floating panel (mouse parallax) with title / mappers / difficulty,
# status (PASSED / DISQUALIFIED / FAILED / REPLAY), score, accuracy, hits, speed and mods, plus
# Back / Retry / Watch replay. Osu touches: counting score, grade stamp + applause (osuskin mod).
# Esc / Back = map selection, ` = retry. Data comes from Game.gd (Rhythia meta "last_run").

const UIAnim = preload("res://mods/replay/UIAnim.gd")
const OsuSfx = preload("res://mods/replay/OsuSfx.gd")
const W = 1180.0
const H = 600.0
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
	sb.bg_color = Color(0.06, 0.06, 0.08, 0.82)
	sb.set_corner_radius_all(12)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	holder.add_stylebox_override("panel", sb)
	root.add_child(holder)
	holder.rect_size = Vector2(W, H)

	var c = TextureRect.new()
	c.texture = cover_tex
	c.expand = true
	c.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	holder.add_child(c)
	c.rect_position = Vector2(32, 32); c.rect_size = Vector2(150, 150)
	var title = ("[REPLAY] " if run.replay else "") + (song.name if song else "?")
	_label(title, Vector2(206, 34), 1.5, Color(1, 1, 1), 640)
	var diff = song.custom_data.get("difficulty_name", "") if song else ""
	if diff == "" and song and song.difficulty >= 0 and song.difficulty < DIFFS.size(): diff = DIFFS[song.difficulty]
	_label(("by " + song.creator if song else "") + ("   ·   " + diff if diff != "" else ""), Vector2(206, 84), 1.0, Color(1, 1, 1, 0.6), 640)
	var st = _status()
	_label(st[0], Vector2(206, 122), 1.3, st[1], 640)
	best_label = _label("", Vector2(206, 158), 1.0, Color("#ffd75e"), 640)
	if run.get("when"):
		best_label.text = "played " + run.when
		best_label.modulate = Color(1, 1, 1, 0.5)

	_label("SCORE", Vector2(32, 214), 0.9, Color(1, 1, 1, 0.5))
	score_label = _label("0", Vector2(32, 236), 3.2, Color(1, 1, 1))
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
	for i in rows.size():
		var x = 32 + (i % 2) * 300
		var y = 360 + int(i / 2) * 52
		_label(rows[i][0], Vector2(x, y), 0.9, Color(1, 1, 1, 0.5))
		_label(rows[i][1], Vector2(x, y + 18), 1.3, Color(1, 1, 1))
	var mods = run.get("mods", null)
	if mods == null:
		mods = []
		for m in MODS:
			if Rhythia.get(m[0]): mods.append(m[1])
	if mods.size() > 0: _label("Mods: " + PoolStringArray(mods).join(", "), Vector2(32, H - 40), 0.9, Color(1, 1, 1, 0.6), 640)

	var g = _grade(acc)
	grade_text = _label(g[0], Vector2(W - 420, 120), 15.0, g[2], 380)
	grade_text.align = Label.ALIGN_CENTER
	grade_text.rect_pivot_offset = grade_text.rect_size / 2
	grade_text.modulate.a = 0

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

func _button(bar:Control, text:String, cb:String):
	var b = Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	if ResourceLoader.exists("res://uitheme.tres"): b.theme = load("res://uitheme.tres")
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
	holder.rect_position = holder.rect_position.linear_interpolate(target, 0.2) if t > 0.05 else target
	grade_text.rect_scale = grade_text.rect_scale.linear_interpolate(Vector2.ONE, 0.18)

# ------------------------------------------------------------------ actions
func _input(ev):
	if closing or !(ev is InputEventKey) or !ev.pressed or ev.echo: return
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
	_cover(false)
	if Rhythia.has_meta("last_run_best"): Rhythia.remove_meta("last_run_best")
