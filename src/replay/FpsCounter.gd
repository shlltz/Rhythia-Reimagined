extends CanvasLayer
# FPS counter in the top-right corner, on every screen (menus, gameplay, pause, results).
# Lives on the scene-tree root (added once by menu2.gd), so it survives scene changes.
# No per-frame script work: a Timer four times a second divides the frames the engine drew
# since the last tick (Engine.get_frames_drawn) by the real time that passed.
# Customize > Interface > "FPS counter" turns it off (Reimagined show_fps).

const UI_FONT = "res://assets/font/Lato/Lato-Regular.ttf"
const INTERVAL = 0.25
const MARGIN_X = 10
const MARGIN_Y = 6

var label:Label
var last_frames:int = 0
var last_us:int = 0
var timer:Timer

func _ready():
	name = "FpsCounter"
	layer = 127 # (under the volume rings, over everything else)
	pause_mode = PAUSE_MODE_PROCESS
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.align = Label.ALIGN_RIGHT
	label.anchor_left = 1
	label.anchor_right = 1
	label.margin_left = -160
	label.margin_right = -MARGIN_X
	label.margin_top = MARGIN_Y
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var data = load(UI_FONT) if ResourceLoader.exists(UI_FONT) else null
	if data is DynamicFontData:
		var f = DynamicFont.new()
		f.font_data = data
		f.size = 14
		label.add_font_override("font", f)
	label.add_color_override("font_color", Color(1, 1, 1, 0.7))
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.55))
	label.add_constant_override("shadow_offset_x", 1)
	label.add_constant_override("shadow_offset_y", 1)
	add_child(label)
	timer = Timer.new()
	timer.wait_time = INTERVAL
	timer.pause_mode = PAUSE_MODE_PROCESS
	timer.connect("timeout", self, "_tick")
	add_child(timer)
	set_shown(load("res://mods/replay/Reimagined.gd").val("show_fps"))

func set_shown(on:bool):
	label.visible = on
	if on:
		last_frames = Engine.get_frames_drawn()
		last_us = OS.get_ticks_usec()
		label.text = ""
		timer.start()
	else: timer.stop()

# hidden while Replay Studio records a clip (the frames are grabbed from the screen)
func hold(hidden:bool):
	label.visible = !hidden and load("res://mods/replay/Reimagined.gd").val("show_fps")

func _tick():
	var f = Engine.get_frames_drawn()
	var u = OS.get_ticks_usec()
	if u > last_us and f >= last_frames:
		label.text = "%d FPS" % int(round((f - last_frames) * 1000000.0 / (u - last_us)))
	last_frames = f
	last_us = u
