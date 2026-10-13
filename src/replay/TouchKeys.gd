extends CanvasLayer
# In-game keyboard for touch screens (Rhythia-reimagined). On some phones the system keyboard opens
# but its text never reaches the game (search boxes stay empty, number boxes can't be edited).
# While a text box has focus this keyboard shows at the bottom of the screen instead; its keys are
# sent as normal key events, so every box (map search, editor fields, settings) works unchanged.
# Customize > Interface can turn it off to use the phone's keyboard. One instance on the root
# (added by menu2.gd on touch screens).

const ROWS = [["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
	["a", "s", "d", "f", "g", "h", "j", "k", "l", "'"],
	["SHIFT", "z", "x", "c", "v", "b", "n", "m", "-", "BACK"],
	["SYM", "_", "SPACE", ".", "DONE"]]
const SYMS = ["!", "?", "&", "#", "%", "+", "=", "/", "(", ")", ":", ",", "@", "*", "\"", "[", "]", "<", ">", "~"]

var target:LineEdit = null
var panel:PanelContainer
var keys:Array = []         # [Button, key]
var shift:bool = false
var sym:bool = false

func _ready():
	name = "TouchKeys"
	layer = 120
	pause_mode = PAUSE_MODE_PROCESS
	panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.05, 0.97)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.border_width_top = 1
	sb.set_content_margin_all(8)
	panel.add_stylebox_override("panel", sb)
	panel.anchor_top = 1
	panel.anchor_right = 1
	panel.anchor_bottom = 1
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 6)
	panel.add_child(v)
	for row in ROWS:
		var h = HBoxContainer.new()
		h.add_constant_override("separation", 6)
		v.add_child(h)
		for k in row:
			var b = Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.rect_min_size = Vector2(0, 52)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.size_flags_stretch_ratio = 5.0 if k == "SPACE" else (1.5 if k in ["SHIFT", "BACK", "SYM", "DONE"] else 1.0)
			b.connect("pressed", self, "_press", [k, b])
			h.add_child(b)
			keys.append([b, k])
	_labels()
	panel.visible = false
	get_viewport().connect("gui_focus_changed", self, "_focus")

static func enabled() -> bool:
	return bool(load("res://mods/replay/Reimagined.gd").val("touch_keys"))

func _focus(c):
	if !(c is LineEdit) or !c.editable or !enabled(): return
	target = c
	c.virtual_keyboard_enabled = false
	OS.hide_virtual_keyboard()
	shift = false
	sym = false
	_labels()
	panel.visible = true
	call_deferred("_fit")

func _fit():
	var h = panel.get_combined_minimum_size().y
	panel.margin_top = -h
	panel.margin_bottom = 0

func _process(_d):
	if !panel.visible: return
	if !is_instance_valid(target) or !target.is_visible_in_tree() or !target.has_focus() or !target.editable:
		_hide()

func _hide():
	panel.visible = false
	target = null

func _labels():
	var si = 0
	for e in keys:
		var k = e[1]
		var t = k
		if k == "SPACE": t = "space"
		elif k == "BACK": t = "<-"
		elif k == "SHIFT": t = "SHIFT" if !shift else "shift"
		elif k == "SYM": t = "abc" if sym else "?!#"
		elif k == "DONE": t = "OK"
		elif sym and k.length() == 1 and e[0].get_parent().get_index() in [1, 2]:
			t = SYMS[si % SYMS.size()]
			si += 1
		elif shift: t = k.to_upper()
		e[0].text = t

func _press(k:String, b:Button):
	if !is_instance_valid(target): return _hide()
	match k:
		"SHIFT":
			shift = !shift
			_labels()
		"SYM":
			sym = !sym
			_labels()
		"BACK": _send(KEY_BACKSPACE, 0)
		"SPACE": _send(0, 32) # (no KEY_SPACE: the map page starts the map on it)
		"DONE":
			_send(KEY_ENTER, 0)
			if is_instance_valid(target): target.release_focus()
			_hide()
		_:
			_send(0, ord(b.text))
			if shift:
				shift = false
				_labels()

# a normal key press + release, as if typed on a hardware keyboard
func _send(scancode:int, unicode:int):
	for p in [true, false]:
		var e = InputEventKey.new()
		e.pressed = p
		e.scancode = scancode
		e.unicode = unicode
		Input.parse_input_event(e)
