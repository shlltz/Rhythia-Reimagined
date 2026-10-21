extends Node
# Classic song page restyle (Main/Results/Results, the stock legacymenu SongInfoScreen): three cards
# - map (big cover, name / mapper / stars, Start + icon buttons), personal best, modifiers (speed,
# start from, health model, the mod checkboxes in groups). The stock nodes are only moved and
# restyled, never reparented: the game's own scripts find them by path. Added by Classic.gd.

const GAP = 20.0
const COL_A = 400.0     # map card
const COL_B = 300.0     # personal best card
const MOD_GROUPS = [["EASIER", ["NoFail", "EasyMode"]],
	["HARDER", ["SuddenDeath", "HardMode", "HardRock", "Flashlight", "Ghost", "Chaos", "Earthquake", "Nearsight"]],
	["SPECIAL", ["MirrorX", "MirrorY", "VisualMode", "InvertMouse"]]]
var si:Control
var Look
var mono:bool = false
var cards:Array = []
var heads:Array = []

func _ready():
	name = "RRLook"
	si = get_parent()
	Look = load("res://mods/replay/Look.gd")
	var p = "res://mods/look/mono.flag"
	mono = ResourceLoader.exists(p) or File.new().file_exists(p)
	for i in 3:
		var c = Panel.new()
		c.name = "RRCard%d" % i
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_stylebox_override("panel", Look.box(Color(0, 0, 0, 0.45), _acc(0.3), 1, 12))
		si.add_child(c)
		si.move_child(c, i) # behind everything
		cards.append(c)
	_style_info()
	_style_buttons()
	_style_mods()
	si.connect("resized", self, "_layout")
	call_deferred("_layout")

func _acc(a:float) -> Color:
	var c = Look.accent()
	return Color(c.r, c.g, c.b, a)

func _layout():
	var w = si.rect_size.x
	var h = si.rect_size.y
	var xb = COL_A + GAP
	var xc = xb + COL_B + GAP
	var wc = max(380.0, w - xc)
	cards[0].rect_position = Vector2(0, 8); cards[0].rect_size = Vector2(COL_A, h - 16)
	cards[1].rect_position = Vector2(xb, 8); cards[1].rect_size = Vector2(COL_B, 360)
	cards[2].rect_position = Vector2(xc, 8); cards[2].rect_size = Vector2(wc, h - 16)
	# map card: cover centred on top, the info column under it
	var bd = si.get_node("ButtonDisp")
	var cs = 200.0
	_size_cover(bd, cs)
	bd.rect_position = Vector2((COL_A - cs) / 2, 28)
	var info = si.get_node("Info")
	var d = info.get_node_or_null("D")
	if d:
		d.rect_min_size.x = 0
		for c in d.get_children(): c.rect_size.x = COL_A - 40
	info.rect_position = Vector2(8, 28 + cs + 12)
	info.rect_size = Vector2(COL_A - 16, 0)
	# personal best (the stock page moves it back down: kept in place in _process)
	var ei = si.get_node_or_null("EndInfo")
	if ei: ei_pos = Vector2(xb + (COL_B - ei.rect_size.x) / 2, 36)
	_process(0)
	# modifiers
	var mt = si.get_node_or_null("ModsTitle")
	if mt: mt.rect_position = Vector2(xc + GAP, 18)
	var hb = si.get_node_or_null("Hitboxes")
	if hb:
		hb.rect_position = Vector2(xc + GAP, 56)
		hb.rect_size = Vector2(wc - 2 * GAP, 24)
	var mh = si.get_node_or_null("ModsHolder")
	if mh:
		mh.rect_position = Vector2(xc + 6, 88)
		mh.rect_size = Vector2(wc - 12, h - 104)

var ei_pos = null
func _process(_d):
	var ei = si.get_node_or_null("EndInfo")
	if ei and ei_pos != null and ei.rect_position != ei_pos: ei.rect_position = ei_pos

# cover panels (one per difficulty) at size s; the hype mod drives the cover's scale, so no scaling
func _size_cover(bd:Control, s:float):
	bd.rect_size = Vector2(s, s)
	bd.rect_min_size = bd.rect_size
	for p in bd.get_children():
		if !(p is Control): continue
		p.rect_size = Vector2(s, s)
		for c in p.get_children():
			if c is Control and c.name != "F": c.rect_size = Vector2(s - 12, s - 12) - (Vector2(8, 0) if c is Label else Vector2.ZERO)

func _style_info():
	var v = si.get_node_or_null("Info/M/V")
	if !v: return
	var stars = v.get_node_or_null("RRStars")
	var mapper = v.get_node_or_null("Mapper")
	if stars and mapper: v.move_child(stars, mapper.get_index() + 1)
	v.add_constant_override("separation", 4)
	var nm = v.get_node_or_null("Name/L")
	if nm:
		nm.autowrap = true
		nm.add_color_override("font_color", Color(1, 1, 1))
	var idl = v.get_node_or_null("Id/L")
	if idl:
		idl.clip_text = true
		idl.add_color_override("font_color", Color(1, 1, 1, 0.38))
	var idt = v.get_node_or_null("Id/Title")
	if !idt: idt = v.get_node_or_null("Id/L/Title")
	if idt: idt.add_color_override("font_color", Color(1, 1, 1, 0.38))
	var data = si.get_node_or_null("Info/D/Data")
	if data: data.add_color_override("font_color", Color(1, 1, 1, 0.8))

# Start + favourite / preview / actions: Start full width, the three as equal icon buttons
func _style_buttons():
	var run = si.get_node_or_null("Info/M/V/Run/Run")
	var row = si.get_node_or_null("Info/M/V/Buttons/Control")
	if !run or !row: return
	run.rect_min_size.y = 48
	row.add_constant_override("separation", 8)
	var glyph = "res://mods/stars/IconGlyph.gd"
	for n in [["Favorite", "heart", "Favorite"], ["PreviewMusic", "play", "Play / stop the song"], ["Actions", "menu", "Map actions"]]:
		var b = row.get_node_or_null(n[0])
		if !b: continue
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.rect_min_size = Vector2(0, 40)
		b.hint_tooltip = n[2]
		if ResourceLoader.exists(glyph) and !b.has_node("RRGlyph"):
			b.clip_text = true
			b.icon = null
			for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_disabled", "font_color_focus"]:
				b.add_color_override(k, Color(0, 0, 0, 0))
			var g = load(glyph).new(n[1])
			g.name = "RRGlyph"
			b.add_child(g)
	for b in [run] + row.get_children():
		if !(b is BaseButton): continue
		var big = b == run
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			var bg = Color(0, 0, 0, 0.35)
			var edge = _acc(1.0 if big else 0.6)
			if st == "hover":
				bg = Look.accent() if big and mono else _acc(0.18)
				edge = Look.accent()
			elif st == "pressed":
				bg = _acc(0.75 if mono else 0.32)
				edge = Look.accent()
			elif st == "disabled": edge.a = 0.2
			b.add_stylebox_override(st, Look.box(bg, edge, 1 if mono else 2, 8))
	run.text = run.text.to_upper() if mono else run.text
	for k in ["font_color", "font_color_focus"]: run.add_color_override(k, Color(1, 1, 1, 0.95))
	for k in ["font_color_hover", "font_color_pressed"]:
		run.add_color_override(k, Look.on_accent() if mono else Color(1, 1, 1))

# Speed (label above its row), Start From, Health Model, then the checkboxes in two columns per group
func _style_mods():
	var mh = si.get_node_or_null("ModsHolder")
	var mods = si.get_node_or_null("ModsHolder/Mods")
	if !mods: return
	if mh is ScrollContainer: mh.scroll_horizontal_enabled = false
	var hb = si.get_node_or_null("Hitboxes")
	if hb:
		hb.align = Label.ALIGN_LEFT
		hb.autowrap = true
		hb.add_color_override("font_color", Color(1, 1, 1, 0.55))
	var head_col = Look.accent().lightened(0.25)
	var y = 0.0
	var sp = mods.get_node_or_null("SpeedMod")
	if sp:
		var l = sp.get_node_or_null("Label")
		if l:
			l.align = Label.ALIGN_LEFT
			l.rect_position = Vector2(0, -28)
			l.rect_size = Vector2(200, 26)
		sp.rect_position = Vector2(8, y + 28)
		var cust = sp.get_node_or_null("C/CustomSpeed")
		if cust: # (the % box ran past the card edge with the wider personal-build font)
			cust.rect_min_size.x = 104
			cust.size_flags_horizontal = 0
		y += 28 + 32 + 24
	for n in ["StartOffset", "HpModel"]:
		var c = mods.get_node_or_null(n)
		if !c: continue
		c.rect_position = Vector2(150, y + (6 if c is HSlider else 0))
		var l = c.get_node_or_null("Label")
		if l: l.clip_text = false
		y += 40
	y += 8
	var col_a = 150.0
	var col_b = 350.0
	for g in MOD_GROUPS:
		var head = Label.new()
		head.text = g[0]
		head.add_color_override("font_color", head_col)
		head.rect_position = Vector2(8, y)
		mods.add_child(head)
		heads.append(head)
		y += 26
		var i = 0
		for n in g[1]:
			var box = mods.get_node_or_null(n)
			if !box or !box.visible: continue
			box.rect_position = Vector2(col_a if i % 2 == 0 else col_b, y + int(i / 2) * 30)
			var lbl = box.get_node_or_null("Label")
			if lbl:
				lbl.clip_text = false
				lbl.add_color_override("font_color", Color(1, 1, 1, 0.92))
				lbl.rect_position.x = -150
				lbl.rect_size.x = 140
			i += 1
		y += int((i + 1) / 2) * 30 + 10
	var gs = mods.get_node_or_null("GradeSystem") # hidden by the game; kept out of the way
	if gs and !gs.visible: gs.rect_position = Vector2(150, y)
	mods.rect_min_size = Vector2(430, y + 8)
	mods.rect_size = mods.rect_min_size
