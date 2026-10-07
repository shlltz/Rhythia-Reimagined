extends Node
# Content Manager restyle: wizard card with step progress, list rows, footer band,
# primary/secondary buttons. Added as a child of a content manager root:
#  - standalone scene (contentmgr.gd): also adds a header bar + "Back to menu" buttons
#  - embedded menu page (menu2.gd, Main/Content/Menu, whose root script is null)
# Only properties change and nodes are only added; every node path AddSong.gd relies
# on stays the same.

const CMIcon = preload("res://mods/stars/CMIcon.gd")
const C_BG = Color("#08080a")
const C_HEADER = Color("#0e0e11")
const C_CARD = Color("#111114")
const C_FOOTER = Color("#0c0c0f")
const C_ROW = Color("#16161a")
const C_ROW_HOVER = Color("#1d1d22")
const C_ROW_PRESS = Color("#232329")
const C_FIELD = Color("#0b0b0d")
const C_LINE = Color("#26262c")
const C_LINE_HI = Color("#4a4a53")
const C_TEXT = Color("#ececf0")
const C_MUTED = Color("#8d8d97")
const C_ERROR = Color("#ff6b6b")
const C_OK = Color("#8ee59a")
const CLEAR = Color(0,0,0,0)

const CARD_W = 680.0
const PAD = 32.0
const HEADER_H = 72.0
const FOOTER_H = 106.0 # darker band holding the footer buttons
const BTN_H = 42.0
const DIVIDER_Y = 92.0 # line under the card title
const CONTENT_TOP = 48.0 # first row, relative to a screen (screens start 58px into the card)
const CONTENT_BOTTOM = -FOOTER_H - 16.0

# per screen: step index, card title, card height
const STEP_NAMES = ["FORMAT", "SOURCE", "DETAILS", "DONE"]
const SCREENS = {
	"SelectType": [0, "Choose a format", 520.0],
	"VulnusFile": [1, "Choose the source", 420.0],
	"SelectDifficulty": [1, "Pick a difficulty", 640.0],
	"TxtFile": [1, "Map data & details", 724.0],
	"Edit": [2, "Review the details", 520.0],
	"Finish": [3, "", 380.0],
}
const FINISH_TITLES = {"Wait": "Importing...", "Success": "Import complete", "Error": "Import failed"}
const FIELD_CAPTIONS = {"Id": "MAP ID", "SongName": "SONG", "Mapper": "MAPPER", "Difficulty": "DIFFICULTY"}

var standalone:bool = true
var root:Control
var add:Control
var header_h:float = 0.0
var font_data:DynamicFontData = null
var fonts:Dictionary = {}
var step_label:Label
var finish_icon:Control
var finish_back:Button
var field_labels:Array = [] # metadata labels whose "Mapper: " style prefixes get stripped
var status_rows:Array = [] # [Info label, dot] of the text-map data/music panels
var current_screen:String = ""
var current_finish:String = ""
var card_h:float = -1.0

func _init(is_standalone:bool = true):
	standalone = is_standalone
	name = "CMStyle"

func _ready():
	root = get_parent()
	add = root.get_node("AddSong")
	var title_font = add.get_node("Title").get_font("font")
	font_data = title_font.font_data if title_font is DynamicFont else null
	if font_data == null: # unexpected font setup, keep the stock look
		set_process(false)
		return
	header_h = HEADER_H if standalone else 0.0
	if standalone:
		root.set("color", C_BG)
		_build_header()
	_build_card()
	_style_select_type(add.get_node("SelectType"))
	_style_vulnus_file(add.get_node("VulnusFile"))
	_style_select_difficulty(add.get_node("SelectDifficulty"))
	_style_txt_file(add.get_node("TxtFile"))
	_style_edit(add.get_node("Edit"))
	_style_finish(add.get_node("Finish"))

func _process(delta):
	_fit_card(delta)
	_sync_screen()

# ---------------------------------------------------------------- helpers
func font(size:int) -> DynamicFont:
	if !fonts.has(size):
		var f = DynamicFont.new()
		f.font_data = font_data
		f.size = size
		f.use_filter = true
		fonts[size] = f
	return fonts[size]

func box(bg:Color, border:Color = CLEAR, width:int = 0, left:int = -1) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.draw_center = bg.a > 0
	if width > 0:
		s.border_color = border
		s.set_border_width_all(width)
		if left >= 0: s.border_width_left = left
	return s

func set_rect(c:Control, al:float, at:float, ar:float, ab:float, ml:float, mt:float, mr:float, mb:float):
	c.anchor_left = al; c.anchor_top = at; c.anchor_right = ar; c.anchor_bottom = ab
	c.margin_left = ml; c.margin_top = mt; c.margin_right = mr; c.margin_bottom = mb

func label_style(l:Label, size:int, col:Color, align:int = Label.ALIGN_LEFT):
	l.add_font_override("font", font(size))
	l.add_color_override("font_color", col)
	l.add_color_override("font_color_shadow", CLEAR)
	l.align = align

func new_label(text:String, size:int, col:Color, align:int = Label.ALIGN_LEFT) -> Label:
	var l = Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_style(l, size, col, align)
	return l

func new_icon(kind:String) -> Control:
	var ic = Control.new()
	ic.set_script(CMIcon)
	ic.kind = kind
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic

func new_button(text:String) -> Button:
	var b = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var t = Label.new()
	t.name = "Title"
	t.text = text
	t.valign = Label.VALIGN_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_rect(t, 0, 0, 1, 1, 0, 0, 0, 0)
	b.add_child(t)
	return b

func button_boxes(b:Control, normal:StyleBox, hover:StyleBox, pressed:StyleBox, focus:StyleBox, disabled:StyleBox = null):
	b.add_stylebox_override("normal", normal)
	b.add_stylebox_override("hover", hover)
	b.add_stylebox_override("pressed", pressed)
	b.add_stylebox_override("focus", focus)
	if disabled: b.add_stylebox_override("disabled", disabled)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

# list row: dark tile, brighter border + left accent on hover/press
func row_style(b:Button):
	button_boxes(b, box(C_ROW, C_LINE, 1), box(C_ROW_HOVER, C_TEXT, 1, 3), box(C_ROW_PRESS, C_TEXT, 1, 3),
		box(CLEAR, C_LINE_HI, 1), box(Color("#0f0f12"), Color("#1c1c20"), 1))

# outlined box used by the metadata fields and the cover picker
func outline_style(b:Control):
	button_boxes(b, box(CLEAR, C_LINE_HI, 1), box(Color(1,1,1,0.03), C_TEXT, 1), box(Color(1,1,1,0.06), C_TEXT, 1), box(CLEAR, C_TEXT, 1))

func primary_style(b:Button):
	button_boxes(b, box(Color("#f0f0f2")), box(Color("#ffffff")), box(Color("#cfcfd4")),
		box(CLEAR, Color("#ffffff"), 1), box(Color("#1e1e23"), C_LINE, 1))
	var t = b.get_node_or_null("Title")
	if t: label_style(t, 16, Color("#0a0a0c"), Label.ALIGN_CENTER)

func secondary_style(b:Button, size:int = 16):
	button_boxes(b, box(CLEAR, C_LINE_HI, 1), box(Color("#1a1a1f"), C_TEXT, 1), box(Color("#24242a"), C_TEXT, 1),
		box(CLEAR, C_TEXT, 1), box(CLEAR, C_LINE, 1))
	var t = b.get_node_or_null("Title")
	if t: label_style(t, size, C_TEXT, Label.ALIGN_CENTER)

func add_chevron(b:Button) -> Label:
	var chev = new_label(">", 22, C_MUTED, Label.ALIGN_CENTER)
	chev.valign = Label.VALIGN_CENTER
	set_rect(chev, 1, 0, 1, 1, -44, 0, -16, 0)
	b.add_child(chev)
	return chev

# Back (left) / action (right), centred in the footer band
func footer_left(b:Button, w:float = 170.0):
	var y = -(FOOTER_H + BTN_H) / 2
	set_rect(b, 0, 1, 0, 1, PAD, y, PAD + w, y + BTN_H)
	secondary_style(b)

func footer_right(b:Button, w:float = 220.0):
	var y = -(FOOTER_H + BTN_H) / 2
	set_rect(b, 1, 1, 1, 1, -PAD - w, y, -PAD, y + BTN_H)
	primary_style(b)

# the card title says what the screen is; the screen's own title label is no longer needed
func screen_style(scr:Control):
	scr.margin_top = 58
	scr.border_color = CLEAR
	scr.get_node("Title").visible = false
	for n in ["Error", "Success"]:
		var l = scr.get_node_or_null(n)
		if l:
			label_style(l, 15, C_ERROR if n == "Error" else C_OK, Label.ALIGN_LEFT)
			l.autowrap = true

# ---------------------------------------------------------------- layout
func _build_header():
	var header = Panel.new()
	header.name = "CMHeader"
	header.add_stylebox_override("panel", box(C_HEADER))
	set_rect(header, 0, 0, 1, 0, 0, 0, 0, HEADER_H)
	root.add_child(header)
	var line = ColorRect.new()
	line.color = C_LINE
	set_rect(line, 0, 1, 1, 1, 0, -1, 0, 0)
	header.add_child(line)
	var icon = TextureRect.new()
	icon.texture = load("res://assets/images/branding/icon.svg")
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_rect(icon, 0, 0, 0, 0, 28, 18, 64, 54)
	header.add_child(icon)
	var ht = new_label("CONTENT MANAGER", 22, C_TEXT)
	set_rect(ht, 0, 0, 0, 0, 80, 14, 600, 40)
	header.add_child(ht)
	var hs = new_label("Import maps into your library", 13, C_MUTED)
	set_rect(hs, 0, 0, 0, 0, 80, 40, 600, 58)
	header.add_child(hs)

	# "Back to menu" with an Esc keycap
	var back = new_button("<  Back to menu")
	secondary_style(back, 15)
	var bt = back.get_node("Title")
	bt.align = Label.ALIGN_LEFT
	set_rect(bt, 0, 0, 1, 1, 16, 0, -60, 0)
	var key = new_label("ESC", 11, C_MUTED, Label.ALIGN_CENTER)
	key.valign = Label.VALIGN_CENTER
	key.add_stylebox_override("normal", box(CLEAR, C_LINE_HI, 1))
	set_rect(key, 1, 0.5, 1, 0.5, -52, -10, -12, 10)
	back.add_child(key)
	set_rect(back, 1, 0, 1, 0, -28 - 220, 16, -28, 56)
	back.connect("pressed", add, "back_to_menu")
	header.add_child(back)
	root.move_child(header, root.get_node("BlackFade").get_index()) # keep the fade on top

func _build_card():
	var h0 = SCREENS["SelectType"][2]
	set_rect(add, 0.5, 0.5, 0.5, 0.5, -CARD_W / 2, -h0 / 2 + header_h / 2, CARD_W / 2, h0 / 2 + header_h / 2)
	var card = box(C_CARD, C_LINE, 1)
	card.shadow_color = Color(0, 0, 0, 0.55)
	card.shadow_size = 28
	add.add_stylebox_override("panel", card)
	add.connect("draw", self, "_draw_card")
	var at:Label = add.get_node("Title")
	set_rect(at, 0, 0, 1, 0, PAD, 42, -PAD, 74)
	label_style(at, 24, C_TEXT)
	# child of Title: AddSong.gd's reset hides every other direct child of the card
	step_label = new_label("", 11, C_MUTED)
	set_rect(step_label, 0, 0, 1, 0, 0, -18, 0, -4)
	at.add_child(step_label)

# 1. pick a type
func _style_select_type(st:Control):
	screen_style(st)
	var y = CONTENT_TOP
	for n in ["sspm", "txt", "vulnus", "sspmr"]: # most common first
		var b:Button = st.get_node(n)
		set_rect(b, 0, 0, 1, 0, PAD, y, -PAD, y + 84)
		row_style(b)
		var tex = b.get_node("TextureRect")
		set_rect(tex, 0, 0, 0, 0, 20, 20, 64, 64)
		if n != "sspm": # stock icons don't match; draw line icons instead
			tex.visible = false
			tex = new_icon({"txt": "file", "vulnus": "vulnus", "sspmr": "pack"}[n])
			set_rect(tex, 0, 0, 0, 0, 22, 22, 62, 62)
			b.add_child(tex)
		var t = b.get_node("Title")
		set_rect(t, 0, 0, 1, 0, 84, 14, -48, 40)
		label_style(t, 19, C_TEXT)
		t.valign = Label.VALIGN_CENTER
		var d = b.get_node("Describe")
		set_rect(d, 0, 0, 1, 1, 84, 42, -48, -8)
		label_style(d, 13, C_MUTED)
		d.autowrap = true
		var chev = add_chevron(b)
		if b.disabled:
			for c in [tex, t, d]: c.modulate.a = 0.4
			chev.text = "UNAVAILABLE"
			chev.add_font_override("font", font(10))
			chev.add_stylebox_override("normal", box(CLEAR, C_LINE_HI, 1))
			set_rect(chev, 1, 0, 1, 0, -124, 16, -16, 36)
		y += 96
	st.get_node("cancel").visible = false # header / sidebar leads back

# 2a. vulnus: zip or folder
func _style_vulnus_file(vf:Control):
	screen_style(vf)
	var y = CONTENT_TOP
	for n in ["zip", "folder"]:
		var b:Button = vf.get_node(n)
		set_rect(b, 0, 0, 1, 0, PAD, y, -PAD, y + 64)
		row_style(b)
		var ic = new_icon("zip" if n == "zip" else "folder")
		set_rect(ic, 0, 0, 0, 0, 20, 16, 52, 48)
		b.add_child(ic)
		var t = b.get_node("Title")
		set_rect(t, 0, 0, 1, 1, 68, 0, -48, 0)
		label_style(t, 17, C_TEXT)
		t.valign = Label.VALIGN_CENTER
		add_chevron(b)
		y += 76
	for n in ["Error", "Success"]:
		set_rect(vf.get_node(n), 0, 0, 1, 0, PAD, y + 4, -PAD, y + 60)
	footer_left(vf.get_node("cancel"))

# 2b. vulnus: difficulty list
func _style_select_difficulty(sd:Control):
	screen_style(sd)
	set_rect(sd.get_node("S"), 0, 0, 1, 1, PAD, CONTENT_TOP, -PAD, CONTENT_BOTTOM)
	sd.get_node("S/V").add_constant_override("separation", 14)
	var all:Button = sd.get_node("S/V/All")
	row_style(all)
	all.rect_min_size.y = 68
	var al = all.get_node("L")
	label_style(al, 18, C_TEXT)
	set_rect(al, 0, 0, 1, 0, 20, 12, -48, 36)
	var al2 = all.get_node("L2")
	label_style(al2, 13, C_MUTED)
	set_rect(al2, 0, 0, 1, 0, 20, 38, -48, 56)
	add_chevron(all)
	var item:Button = sd.get_node("S/V/L/Item") # template, duplicated per difficulty
	row_style(item)
	item.rect_min_size.y = 52
	var il = item.get_node("L")
	label_style(il, 16, C_TEXT)
	set_rect(il, 0, 0, 1, 1, 20, 0, -48, 0)
	il.valign = Label.VALIGN_CENTER
	add_chevron(item)
	sd.get_node("S/V/L").add_constant_override("separation", 8)
	footer_left(sd.get_node("cancel"))
	sd.get_node("cancel").visible = true

# 2c. raw text map: data + music panels, then the metadata fields
func _style_txt_file(tf:Control):
	screen_style(tf)
	var h = tf.get_node("H")
	set_rect(h, 0, 0, 1, 1, PAD, CONTENT_TOP, -PAD, CONTENT_BOTTOM)
	h.add_constant_override("separation", 12)
	for n in ["data", "audio"]:
		var p:Panel = h.get_node(n)
		p.rect_min_size.y = 72
		p.add_stylebox_override("panel", box(C_ROW, C_LINE, 1))
		var t = p.get_node("Title")
		set_rect(t, 0, 0, 1, 0, 18, 12, -170, 38)
		label_style(t, 17, C_TEXT)
		var i = p.get_node("Info")
		set_rect(i, 0, 1, 1, 1, 34, -32, -170, -12)
		label_style(i, 13, C_MUTED)
		var dot = ColorRect.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_rect(dot, 0, 1, 0, 1, 18, -25, 24, -19)
		p.add_child(dot)
		status_rows.append([i, dot])
		for bn in ["file", "paste", "preview"]:
			var b = p.get_node_or_null(bn)
			if !b: continue
			secondary_style(b, 13)
			if bn == "file": set_rect(b, 1, 0, 1, 0, -158, 8, -10, 34)
			else: set_rect(b, 1, 1, 1, 1, -158, -34, -10, -8)
	var done:Button = h.get_node("data/text_done")
	secondary_style(done, 13)
	set_rect(done, 1, 1, 1, 1, -80, -34, -10, -8)
	var temp:CheckBox = h.get_node("Temp")
	temp.add_font_override("font", font(13))
	temp.add_color_override("font_color", C_MUTED)
	temp.align = Button.ALIGN_LEFT
	h.get_node("E").rect_min_size.y = 262
	set_rect(h.get_node("E/Info"), 0, 0, 1, 0, 10, 24, -184, 160) # field boxes reach 10px left of their labels
	set_rect(h.get_node("E/Cover"), 1, 0, 1, 0, -160, 0, 0, 214)
	_style_fields(h.get_node("E/Info"), h.get_node("E/Cover"))
	footer_left(tf.get_node("cancel"))
	footer_right(tf.get_node("done"))

# 3. edit metadata
func _style_edit(ed:Control):
	screen_style(ed)
	set_rect(ed.get_node("Info"), 0, 0, 0, 0, PAD + 10, CONTENT_TOP + 24, CARD_W - PAD - 184, 300)
	set_rect(ed.get_node("Cover"), 1, 0, 1, 0, -PAD - 160, CONTENT_TOP, -PAD, CONTENT_TOP + 214)
	_style_fields(ed.get_node("Info"), ed.get_node("Cover"))
	footer_left(ed.get_node("cancel"))
	footer_right(ed.get_node("done"))

# 4. result: status icon + message, "Back to menu" (standalone) / "Import another map"
func _style_finish(fi:Control):
	screen_style(fi)
	finish_icon = new_icon("wait")
	set_rect(finish_icon, 0.5, 0, 0.5, 0, -28, CONTENT_TOP + 8, 28, CONTENT_TOP + 64)
	fi.add_child(finish_icon)
	for n in ["Wait", "Success", "Error"]:
		var l:Label = fi.get_node(n)
		set_rect(l, 0, 0, 1, 1, PAD, CONTENT_TOP + 84, -PAD, CONTENT_BOTTOM)
		label_style(l, 16, Color("#b8b8c0"), Label.ALIGN_CENTER)
		l.valign = Label.VALIGN_TOP
		l.autowrap = true
	footer_right(fi.get_node("ok"), 240)
	if standalone:
		finish_back = new_button("Back to menu")
		footer_left(finish_back)
		finish_back.connect("pressed", add, "back_to_menu")
		fi.add_child(finish_back)

# metadata fields as input boxes (the B button over each label is the click target)
func _style_fields(info:VBoxContainer, cover:Control):
	info.add_constant_override("separation", 30)
	info.get_node("Info").visible = false # the boxed fields make the hint obvious
	for n in FIELD_CAPTIONS:
		var l:Label = info.get_node(n)
		label_style(l, 15, C_TEXT)
		l.rect_min_size.y = 32
		l.valign = Label.VALIGN_CENTER
		l.clip_text = false # children (box, caption) sit outside the label rect
		field_labels.append(l)
		var cap = new_label(FIELD_CAPTIONS[n], 11, C_MUTED)
		set_rect(cap, 0, 0, 1, 0, -10, -22, 0, -6)
		l.add_child(cap)
		var b = l.get_node("B")
		b.flat = false
		set_rect(b, 0, 0, 1, 1, -10, -2, 0, 2)
		outline_style(b)
		if b is OptionButton: # label underneath shows the value
			for c in ["font_color", "font_color_hover", "font_color_pressed"]: b.add_color_override(c, CLEAR)
		var t = l.get_node_or_null("T") # Difficulty is a dropdown, no LineEdit
		if t:
			set_rect(t, 0, 0, 1, 1, -10, -2, 0, 2)
			t.add_font_override("font", font(15))
			t.add_stylebox_override("normal", box(C_FIELD, C_TEXT, 1))
			t.add_stylebox_override("focus", box(C_FIELD, C_TEXT, 1))
	set_rect(cover.get_node("T"), 0, 0, 0, 0, 0, 0, 160, 160)
	var cl = cover.get_node("T/B/Label")
	label_style(cl, 11, C_MUTED, Label.ALIGN_CENTER)
	cl.text = "Click to replace"
	set_rect(cl, 0, 1, 1, 1, 0, 6, 0, 22)
	outline_style(cover.get_node("T/B"))
	var cc:CheckBox = cover.get_node("C")
	set_rect(cc, 0, 0, 0, 0, 0, 188, 160, 212)
	cc.add_font_override("font", font(13))
	cc.add_color_override("font_color", C_MUTED)
	cc.align = Button.ALIGN_LEFT

# ---------------------------------------------------------------- per frame
func visible_screen() -> String:
	for n in SCREENS:
		if add.get_node(n).visible: return n
	return current_screen

# card height follows the visible screen (eases between sizes)
func _fit_card(delta):
	var scr = visible_screen()
	if scr == "": return
	var target = SCREENS[scr][2]
	if card_h < 0: card_h = target
	card_h = lerp(card_h, target, min(1.0, delta * 14.0))
	if abs(card_h - target) < 0.5: card_h = target
	add.margin_top = -card_h / 2 + header_h / 2
	add.margin_bottom = card_h / 2 + header_h / 2
	add.update()

# Text that AddSong.gd rewrites at runtime: card title/step, finish state, field
# prefixes, button captions, text-map status. Cheap checks, run every frame.
func _sync_screen():
	var scr = visible_screen()
	if scr == "": return
	if scr != current_screen:
		current_screen = scr
		var step = SCREENS[scr][0]
		step_label.text = "STEP %d OF %d  /  %s" % [step + 1, STEP_NAMES.size(), STEP_NAMES[step]]
		add.get_node("Title").text = SCREENS[scr][1]
		current_finish = ""
	if scr == "Finish": _sync_finish()
	for l in field_labels:
		for prefix in [tr("Mapper") + ": ", tr("Difficulty") + ": ", "Difficulty: "]:
			if l.text.begins_with(prefix): l.text = l.text.substr(prefix.length())
	for p in ["TxtFile/done", "Edit/done"]:
		var tl:Label = add.get_node(p + "/Title")
		if tl.text == "Finish": tl.text = "Save map"
	for row in status_rows:
		var info:Label = row[0]
		var col = C_OK
		if info.text == "Required": col = Color("#5c5c66")
		elif "nvalid" in info.text or "unsupported" in info.text: col = C_ERROR
		row[1].color = col
		info.add_color_override("font_color", C_ERROR if col == C_ERROR else C_MUTED)

func _sync_finish():
	var fi = add.get_node("Finish")
	var state = "Wait"
	if fi.get_node("Error").visible: state = "Error"
	elif fi.get_node("Success").visible: state = "Success"
	if finish_back: finish_back.visible = fi.get_node("ok").visible
	if state == current_finish: return
	current_finish = state
	add.get_node("Title").text = FINISH_TITLES[state]
	finish_icon.kind = {"Wait": "wait", "Success": "ok", "Error": "error"}[state]
	finish_icon.color = {"Wait": C_TEXT, "Success": C_OK, "Error": C_ERROR}[state]
	finish_icon.set_process(state == "Wait")
	finish_icon.update()

# step progress along the top edge, divider under the title, footer band
func _draw_card():
	var w = add.rect_size.x
	var h = add.rect_size.y
	var step = SCREENS[current_screen][0] if current_screen != "" else 0
	var gap = 4.0
	var seg = (w - 2 - gap * (STEP_NAMES.size() - 1)) / STEP_NAMES.size()
	for i in STEP_NAMES.size():
		add.draw_rect(Rect2(1 + i * (seg + gap), 1, seg, 3), C_TEXT if i <= step else C_LINE)
	add.draw_rect(Rect2(PAD, DIVIDER_Y, w - PAD * 2, 1), C_LINE)
	if current_screen != "SelectType":
		add.draw_rect(Rect2(1, h - FOOTER_H, w - 2, FOOTER_H - 1), C_FOOTER)
		add.draw_rect(Rect2(1, h - FOOTER_H, w - 2, 1), C_LINE)
