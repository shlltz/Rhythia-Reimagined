extends CanvasLayer
# First start: ask for a username, like osu! offline - a local name only (no account, nothing sent
# anywhere), shown on the loading and results screens ("<name>'s play", "Played by <name>").
# Guest skips it. Changed later in Customize > Interface. Added by menu2.gd while the name is unset.

const CardUI = preload("res://mods/replay/CardUI.gd")
const MAX = 20
var fonts:Dictionary = {}
var edit:LineEdit
var note:Label
var go_btn:Button
var card:Panel
var t:float = 0.0

static func clean(s:String) -> String:
	var out = ""
	for ch in s.strip_edges():
		var c = ord(ch)
		if c < 32 or c == 127 or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069): continue
		out += ch
	return out.strip_edges().substr(0, MAX)

static func needed() -> bool:
	return str(load("res://mods/replay/Reimagined.gd").val("player_name")) == "" and !Engine.has_meta("rr_name_asked")

func _f(n:int):
	return CardUI.font(n, fonts)

func _ready():
	layer = 20
	Engine.set_meta("rr_name_asked", true)
	var root = Control.new()
	root.anchor_right = 1; root.anchor_bottom = 1
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists("res://uitheme.tres"): root.theme = load("res://uitheme.tres")
	add_child(root)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.anchor_right = 1; dim.anchor_bottom = 1
	root.add_child(dim)
	card = Panel.new()
	var sb = CardUI.box(Color(0.06, 0.06, 0.07, 0.96), Color(1, 1, 1, 0.12), 1, 22)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 40
	card.add_stylebox_override("panel", sb)
	card.anchor_left = 0.5; card.anchor_right = 0.5; card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.margin_left = -280; card.margin_right = 280; card.margin_top = -170; card.margin_bottom = 170
	card.rect_pivot_offset = Vector2(560, 340) / 2
	root.add_child(card)
	if CardUI.mono(): card.connect("draw", self, "_brackets")
	var logo = TextureRect.new()
	logo.expand = true
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CardUI.logo(logo)
	card.add_child(logo)
	logo.rect_position = Vector2(32, 34); logo.rect_size = Vector2(44, 44)
	CardUI.label(card, "Choose a username", _f(26), Color(1, 1, 1), Vector2(94, 34), 440)
	CardUI.label(card, "Offline play, like osu! without an account", _f(15), Color(1, 1, 1, 0.5), Vector2(94, 68), 440)
	edit = LineEdit.new()
	edit.max_length = MAX
	edit.placeholder_text = "username"
	edit.add_font_override("font", _f(20))
	var eb = CardUI.box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.18), 1, 12)
	eb.content_margin_left = 16; eb.content_margin_right = 16
	edit.add_stylebox_override("normal", eb)
	edit.add_stylebox_override("focus", CardUI.box(Color(1, 1, 1, 0.07), CardUI.accent(), 2, 12))
	card.add_child(edit)
	edit.rect_position = Vector2(32, 116); edit.rect_size = Vector2(496, 52)
	edit.connect("text_changed", self, "_typed")
	edit.connect("text_entered", self, "_enter")
	note = CardUI.label(card, "Shown on your loading and results screens. Stays on this PC: nothing is sent anywhere.", _f(14), Color(1, 1, 1, 0.45), Vector2(32, 180), 496)
	note.autowrap = true
	note.clip_text = false
	note.rect_size = Vector2(496, 40)
	go_btn = _button("PLAY OFFLINE", "_confirm", true)
	go_btn.rect_position = Vector2(32, 258); go_btn.rect_size = Vector2(300, 50)
	var g = _button("AS GUEST", "_guest", false)
	g.rect_position = Vector2(344, 258); g.rect_size = Vector2(184, 50)
	_typed("")
	edit.call_deferred("grab_focus")
	card.modulate.a = 0.0

func _brackets():
	load(CardUI.LOOK).brackets(card, Rect2(Vector2(), card.rect_size).grow(10), 26.0, Color(1, 1, 1, 0.5), 2.0)

func _button(text:String, cb:String, main:bool) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_font_override("font", _f(17))
	var acc = CardUI.accent()
	b.add_stylebox_override("normal", CardUI.box(Color(acc.r, acc.g, acc.b, 0.2) if main else Color(1, 1, 1, 0.04), acc if main else Color(1, 1, 1, 0.22), 2 if main else 1, 14))
	b.add_stylebox_override("hover", CardUI.box(Color(acc.r, acc.g, acc.b, 0.3), acc.lightened(0.3), 2, 14))
	b.add_stylebox_override("pressed", CardUI.box(Color(acc.r, acc.g, acc.b, 0.4), acc.lightened(0.3), 2, 14))
	b.add_stylebox_override("disabled", CardUI.box(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.1), 1, 14))
	for k in ["font_color", "font_color_hover", "font_color_pressed"]: b.add_color_override(k, Color(1, 1, 1))
	b.add_color_override("font_color_disabled", Color(1, 1, 1, 0.3))
	b.connect("pressed", self, cb)
	card.add_child(b)
	return b

func _typed(_t):
	var n = clean(edit.text)
	go_btn.disabled = n == ""
	go_btn.text = ("PLAY AS " + n.to_upper()) if n != "" else "PLAY OFFLINE"
	go_btn.text = CardUI.fit(go_btn.text, _f(17), 270)

func _enter(_t):
	_confirm()

func _confirm():
	var n = clean(edit.text)
	if n == "": return
	_save(n)

func _guest():
	_save("Guest")

func _save(n:String):
	load("res://mods/replay/Reimagined.gd").set_val("player_name", n)
	set_process(false)
	var a = load("res://mods/replay/UIAnim.gd").play(get_child(0), Vector2.ZERO, Vector2.ZERO, 1.0, 0.0, 0.2)
	a.connect("finished", self, "queue_free")

func _input(ev):
	if ev is InputEventKey and ev.pressed and ev.scancode == KEY_ESCAPE:
		get_tree().set_input_as_handled() # (the title menu behind doesn't get it)

func _process(delta):
	t += delta
	var e = 1.0 - pow(1.0 - min(t / 0.35, 1.0), 3)
	card.modulate.a = e
	var s = 0.96 + 0.04 * e
	card.rect_scale = Vector2(s, s)
