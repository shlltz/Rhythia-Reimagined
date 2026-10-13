extends CanvasLayer
# Custom speed number pad for touch screens. The stock Speed box is a SpinBox that needs the
# Android keyboard, which often never shows or never commits the value, so on touch devices a tap
# on it opens this pad instead (SongInfoScreen._touch_speed). c = the SpeedMod/C row.

const PRESETS = [50, 75, 90, 110, 125, 150]

var c:Control
var txt:String = ""
var shown:Label

func _ready():
	layer = 70
	pause_mode = PAUSE_MODE_PROCESS
	var cs = c.get_node("CustomSpeed")
	txt = _fmt(cs.value)
	var root = Control.new()
	root.anchor_right = 1
	root.anchor_bottom = 1
	if cs.theme: root.theme = cs.theme
	add_child(root)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	dim.connect("gui_input", self, "_dim_input")
	root.add_child(dim)
	var panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.07, 0.98)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	panel.add_stylebox_override("panel", sb)
	var mid = CenterContainer.new()
	mid.anchor_right = 1
	mid.anchor_bottom = 1
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mid)
	mid.add_child(panel)
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 8)
	panel.add_child(v)
	var title = Label.new()
	title.text = "Custom speed"
	title.align = Label.ALIGN_CENTER
	title.modulate = Color(1, 1, 1, 0.6)
	v.add_child(title)
	shown = Label.new()
	shown.align = Label.ALIGN_CENTER
	shown.rect_min_size = Vector2(0, 44)
	shown.valign = Label.VALIGN_CENTER
	v.add_child(shown)
	var pre = GridContainer.new()
	pre.columns = 3
	v.add_child(pre)
	for p in PRESETS: pre.add_child(_btn(str(p) + "%", "_preset", [p], Vector2(96, 44)))
	var steps = HBoxContainer.new()
	v.add_child(steps)
	for s in [-5, -1, 1, 5]: steps.add_child(_btn(("+" if s > 0 else "") + str(s), "_step", [s], Vector2(70, 44)))
	var g = GridContainer.new()
	g.columns = 3
	v.add_child(g)
	for k in ["7", "8", "9", "4", "5", "6", "1", "2", "3", ".", "0", "<"]:
		g.add_child(_btn(k, "_key", [k], Vector2(96, 52)))
	var end = HBoxContainer.new()
	v.add_child(end)
	end.add_child(_btn("Cancel", "_close", [], Vector2(144, 48)))
	end.add_child(_btn("OK", "_ok", [], Vector2(144, 48)))
	_show()

func _btn(t:String, f:String, args:Array, sz:Vector2) -> Button:
	var b = Button.new()
	b.text = t
	b.rect_min_size = sz
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.connect("pressed", self, f, args)
	return b

static func _fmt(x:float) -> String:
	var s = "%.2f" % x
	while s.ends_with("0"): s = s.substr(0, s.length() - 1)
	return s.trim_suffix(".")

func _val() -> float:
	return float(txt) if txt != "" and txt != "." else 0.0

func _show():
	var ok = _val() >= 5.0
	shown.text = (txt if txt != "" else "0") + " %"
	shown.modulate = Color(1, 1, 1) if ok else Color(1, 0.4, 0.45)

func _key(k:String):
	if k == "<":
		txt = txt.substr(0, max(txt.length() - 1, 0))
	elif k == ".":
		if txt.find(".") < 0: txt += "."
	else:
		var dot = txt.find(".")
		if dot >= 0 and txt.length() - dot > 2: return # two decimals at most
		if dot < 0 and txt.length() >= 4: return       # 1000 % at most
		txt = k if txt == "0" else txt + k
	_show()

func _preset(p:int):
	txt = str(p)
	_show()

func _step(s:int):
	txt = _fmt(clamp(_val() + s, 5.0, 1000.0))
	_show()

func _ok():
	var x = clamp(stepify(_val(), 0.01), 5.0, 1000.0)
	var cs = c.get_node_or_null("CustomSpeed")
	var cb = c.get_node_or_null("Custom")
	if cs: cs.value = x
	if cb:
		if cb.pressed: cb.emit_signal("toggled", true) # already on custom: apply the new value
		else: cb.pressed = true
	_close()

func _dim_input(ev):
	if ev is InputEventMouseButton and ev.pressed: _close()

func _close():
	queue_free()
