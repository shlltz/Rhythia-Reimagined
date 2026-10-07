extends CanvasLayer
# osu!-style pause screen, opened by NoteManager when Esc pauses a live run.
# Continue (or Esc again) rewinds 0.75 s and plays on by itself, Retry restarts the map,
# Quit gives up (results screen). Up/Down + Enter work too. A paused run is disqualified.

signal chosen(what) # "continue" / "retry" / "quit"

const UIAnim = preload("res://mods/replay/UIAnim.gd")
const ITEMS = [["Continue", Color(0.35, 0.85, 0.45)], ["Retry", Color(1.0, 0.78, 0.25)], ["Quit", Color(1.0, 0.36, 0.36)]]
const BTN_W = 420.0
const BTN_H = 64.0
const BTN_GAP = 18.0

var dim:ColorRect
var box:Control
var buttons:Array = []
var sel:int = 0
var mouse_before:int = Input.MOUSE_MODE_VISIBLE

func _ready():
	layer = 60
	pause_mode = Node.PAUSE_MODE_PROCESS
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	add_child(dim)
	box = Control.new()
	box.anchor_left = 0.5; box.anchor_top = 0.5; box.anchor_right = 0.5; box.anchor_bottom = 0.5
	var h = 150 + ITEMS.size() * (BTN_H + BTN_GAP)
	box.margin_left = -BTN_W / 2; box.margin_right = BTN_W / 2
	box.margin_top = -h / 2; box.margin_bottom = h / 2
	if ResourceLoader.exists("res://uitheme.tres"): box.theme = load("res://uitheme.tres")
	add_child(box)
	_label("PAUSED", 0, 60, 2.0, Color(1, 1, 1))
	_label("this run is disqualified - it won't set a personal best", 66, 26, 1.0, Color(1, 1, 1, 0.5))
	for i in ITEMS.size():
		var b = Button.new()
		b.text = ITEMS[i][0]
		b.focus_mode = Control.FOCUS_NONE
		b.margin_left = 0; b.margin_right = BTN_W
		b.margin_top = 150 + i * (BTN_H + BTN_GAP); b.margin_bottom = b.margin_top + BTN_H
		b.connect("pressed", self, "_pick", [i])
		b.connect("mouse_entered", self, "_hover", [i])
		box.add_child(b)
		buttons.append(b)
	_hover(0)
	add_child(load("res://mods/replay/UIJuice.gd").new())
	visible_menu(false)

func _label(t:String, y:float, h:float, scale:float, col:Color) -> Label:
	var l = Label.new()
	l.text = t
	l.align = Label.ALIGN_CENTER
	l.valign = Label.VALIGN_CENTER
	l.margin_left = 0; l.margin_right = BTN_W; l.margin_top = y; l.margin_bottom = y + h
	l.rect_pivot_offset = Vector2(BTN_W / 2, h / 2)
	l.rect_scale = Vector2(scale, scale)
	l.modulate = col
	box.add_child(l)
	return l

func is_open() -> bool:
	return dim.visible

func open():
	if is_open(): return
	mouse_before = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	visible_menu(true)
	_hover(0)
	UIAnim.play(dim, Vector2.ZERO, Vector2.ZERO, 0.0, 1.0, 0.15)
	UIAnim.play(box, Vector2(0, 30), Vector2.ZERO, 0.0, 1.0, 0.22)

func close():
	if !is_open(): return
	Input.set_mouse_mode(mouse_before)
	visible_menu(false)

func visible_menu(on:bool):
	dim.visible = on
	box.visible = on
	set_process_input(on)

func _hover(i:int):
	sel = i
	for k in buttons.size():
		var c:Color = ITEMS[k][1]
		buttons[k].modulate = c if k == sel else Color(c.r, c.g, c.b, 0.55)

func _pick(i:int):
	if !is_open(): return
	emit_signal("chosen", ["continue", "retry", "quit"][i])

func _input(ev):
	if !(ev is InputEventKey) or !ev.pressed or ev.echo: return
	match ev.scancode:
		KEY_UP, KEY_W: _hover((sel + buttons.size() - 1) % buttons.size())
		KEY_DOWN, KEY_S: _hover((sel + 1) % buttons.size())
		KEY_ENTER, KEY_KP_ENTER: _pick(sel)
		_: return
	get_tree().set_input_as_handled()
