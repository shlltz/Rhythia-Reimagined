extends Reference
# One look for the mod's own tool screens, taken from the map editor (the most finished of them):
# square outlined buttons that fill with the accent on hover, a visible keyboard focus ring, the
# same inputs and lists, "// TITLE" headers and a centred note for empty lists. Built on Look.gd's
# colours, so both builds (personal and public) get their own accent (only what both Look.gd have).

const Look = preload("res://mods/replay/Look.gd")

static func _box(bg:Color, border:Color, pad_x:int = 12, pad_y:int = 4) -> StyleBoxFlat:
	var sb = Look.box(bg, border, 1, 0)
	sb.content_margin_left = pad_x; sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y; sb.content_margin_bottom = pad_y
	return sb

static func button(b:Button, font = null) -> Button:
	if font: b.add_font_override("font", font)
	if b.rect_min_size.y < 30: b.rect_min_size.y = 30
	var acc = Look.accent()
	b.add_stylebox_override("normal", _box(Look.SURFACE, Look.LINE_HI))
	b.add_stylebox_override("hover", _box(acc, acc))
	b.add_stylebox_override("pressed", _box(acc, acc))
	b.add_stylebox_override("hover_pressed", _box(acc, acc))
	b.add_stylebox_override("disabled", _box(Look.BG, Look.LINE))
	var f = _box(Color(0, 0, 0, 0), acc)
	f.draw_center = false
	f.set_border_width_all(2)
	b.add_stylebox_override("focus", f)
	b.add_color_override("font_color", Look.TEXT)
	b.add_color_override("font_color_hover", Look.on_accent())
	b.add_color_override("font_color_pressed", Look.on_accent())
	b.add_color_override("font_color_hover_pressed", Look.on_accent())
	b.add_color_override("font_color_disabled", Look.TEXT_3)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

static func input(c:Control, font = null):
	var le:LineEdit = c.get_line_edit() if c is SpinBox else (c if c is LineEdit else null)
	if le:
		if font: le.add_font_override("font", font)
		le.add_stylebox_override("normal", _box(Look.SURFACE, Look.LINE_HI, 8, 4))
		le.add_stylebox_override("focus", _box(Look.SURFACE_HI, Look.accent(), 8, 4))
		le.add_color_override("font_color", Look.TEXT)
		le.add_color_override("font_color_uneditable", Look.TEXT_2)
		le.add_color_override("cursor_color", Look.accent())
	elif c is Button:
		button(c, font)

static func list(l:ItemList, font = null):
	if font: l.add_font_override("font", font)
	var bg = _box(Look.SURFACE, Look.LINE, 6, 6)
	l.add_stylebox_override("bg", bg)
	l.add_stylebox_override("bg_focus", _box(Look.SURFACE, Look.LINE_HI, 6, 6))
	var acc = Look.accent()
	l.add_stylebox_override("selected", _box(Color(acc.r, acc.g, acc.b, 0.25), Color(acc.r, acc.g, acc.b, 0.25), 6, 2))
	l.add_stylebox_override("selected_focus", _box(Color(acc.r, acc.g, acc.b, 0.35), acc, 6, 2))
	l.add_stylebox_override("cursor", StyleBoxEmpty.new())
	l.add_stylebox_override("cursor_unfocused", StyleBoxEmpty.new())
	l.add_color_override("font_color", Look.TEXT_2)
	l.add_color_override("font_color_selected", Look.TEXT)
	l.add_constant_override("vseparation", 6)

# a tick box shown as a small switch (only its icons change: the box, its script and its place stay)
static func switch_box(c:CheckBox):
	var ic = switch_icons()
	for k in ["checked", "radio_checked"]: c.add_icon_override(k, ic[0])
	for k in ["unchecked", "radio_unchecked"]: c.add_icon_override(k, ic[1])
	for k in ["checked_disabled", "radio_checked_disabled"]: c.add_icon_override(k, ic[2])
	for k in ["unchecked_disabled", "radio_unchecked_disabled"]: c.add_icon_override(k, ic[3])

# [on, off, on disabled, off disabled], drawn once per session (rounded, square in the mono look)
static func switch_icons() -> Array:
	if Engine.has_meta("rr_switch_icons"): return Engine.get_meta("rr_switch_icons")
	var acc = Look.accent()
	var sq = load("res://mods/replay/CardUI.gd").mono()
	var out = []
	for st in [[true, 1.0], [false, 1.0], [true, 0.35], [false, 0.35]]:
		out.append(_switch_tex(st[0], acc, sq, st[1]))
	Engine.set_meta("rr_switch_icons", out)
	return out

static func _switch_tex(on:bool, acc:Color, sq:bool, a:float) -> ImageTexture:
	var w = 36
	var h = 20
	var img = Image.new()
	img.create(w, h, false, Image.FORMAT_RGBA8)
	img.lock()
	var r = h / 2.0
	var track = Color(acc.r, acc.g, acc.b, 0.9 * a) if on else Color(1, 1, 1, 0.1 * a)
	var edge = Color(acc.r, acc.g, acc.b, a) if on else Color(1, 1, 1, 0.38 * a)
	var kx = (w - r) if on else r
	var knob = (Color(0, 0, 0, a) if sq else Color(1, 1, 1, a)) if on else Color(1, 1, 1, 0.75 * a)
	for y in h:
		for x in w:
			var p = Vector2(x + 0.5, y + 0.5)
			var d:float # signed distance to the track outline (negative inside)
			if sq: d = max(abs(p.x - w / 2.0) - w / 2.0, abs(p.y - r) - r)
			else: d = Vector2(p.x - clamp(p.x, r, w - r), p.y - r).length() - r
			var col = Color(0, 0, 0, 0)
			var cov = clamp(0.5 - d, 0, 1)
			if cov > 0:
				col = track if d < -1.2 else edge
				col.a *= cov
			var kd:float = (max(abs(p.x - kx), abs(p.y - r)) - (r - 4)) if sq else (p.distance_to(Vector2(kx, r)) - (r - 4))
			var kc = clamp(0.5 - kd, 0, 1)
			if kc > 0:
				if col.a > 0: col = col.linear_interpolate(Color(knob.r, knob.g, knob.b, 1), kc * knob.a)
				else: col = Color(knob.r, knob.g, knob.b, knob.a * kc)
			img.set_pixel(x, y, col)
	img.unlock()
	var t = ImageTexture.new()
	t.create_from_image(img, Texture.FLAG_FILTER)
	return t

# "// SKIN EDITOR" in the header font, like the editor's top bar
static func header(text:String, font) -> Label:
	var l = Label.new()
	l.text = "// " + text.to_upper()
	if font: l.add_font_override("font", font)
	l.add_color_override("font_color", Look.TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# a centred note over an empty list ("No replays yet ..."); shown / hidden by the caller
static func empty_note(over:Control, text:String, font) -> Label:
	var l = Label.new()
	l.text = text
	l.autowrap = true
	l.align = Label.ALIGN_CENTER
	l.valign = Label.VALIGN_CENTER
	l.anchor_right = 1; l.anchor_bottom = 1
	l.margin_left = 24; l.margin_right = -24
	if font: l.add_font_override("font", font)
	l.add_color_override("font_color", Look.TEXT_3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.add_child(l)
	return l
