extends CanvasLayer
# osu!-style volume control: Alt + mouse wheel anywhere (menu, gameplay, replays).
# Master by default; scroll while hovering the Music / Effects ring to change that one.
# While the overlay is showing, plain wheel over it works too. Shift = 1% steps.
# Lives on the scene-tree root (added once by menu2.gd), so it survives scene changes.

const STEP = 0.05
const FINE_STEP = 0.01
const SHOW_TIME = 1.2 # seconds the overlay stays after the last change
const FADE_TIME = 0.2
const SAVE_DELAY = 1.5 # save settings.json this long after the last change
const SFX_BUSES = ["HitSound", "MissSound", "FailSound", "PBSound"]
const RING_W = 6.0
const UI_FONT = "res://assets/font/Lato/Lato-Regular.ttf"

const C_TEXT = Color("#ececf0")
const C_MUTED = Color("#8d8d97")
const C_TRACK = Color(1, 1, 1, 0.12)
const C_BG = Color(0.04, 0.04, 0.05, 0.92)

# name, buses it sets, centre offset from the bottom-right corner, ring radius
var meters = [
	{name = "MASTER", buses = ["Master"], pos = Vector2(-110, -110), r = 62.0},
	{name = "MUSIC", buses = ["Music"], pos = Vector2(-248, -160), r = 42.0},
	{name = "EFFECTS", buses = SFX_BUSES, pos = Vector2(-248, -62), r = 42.0},
]
var canvas:Control
var big_font:Font
var mid_font:Font
var label_font:Font
var alpha:float = 0.0
var show_left:float = 0.0
var save_left:float = -1.0
var active:int = 0 # meter last changed (highlighted)
var shown = [-1.0, -1.0, -1.0] # drawn level per meter, glides to the real one
var lit_k = [0.0, 0.0, 0.0] # highlight per meter, fades in / out
var R = preload("res://mods/replay/Ring.gd")

func _ready():
	name = "VolumeOverlay"
	layer = 128
	pause_mode = PAUSE_MODE_PROCESS
	canvas = Control.new()
	canvas.anchor_right = 1
	canvas.anchor_bottom = 1
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.connect("draw", self, "_draw_overlay")
	add_child(canvas)
	big_font = _ui_font(32)
	mid_font = _ui_font(22)
	label_font = _ui_font(11)
	canvas.visible = false

# the game's UI font (the font mod swaps this file for VCR OSD Mono); fallback = default font
func _ui_font(size:int) -> Font:
	var data = load(UI_FONT) if ResourceLoader.exists(UI_FONT) else null
	if !(data is DynamicFontData): return canvas.get_font("font")
	var f = DynamicFont.new()
	f.font_data = data
	f.size = size
	return f

# ---------------------------------------------------------------- input
func _input(ev):
	if not (ev is InputEventMouseButton and ev.pressed): return
	if ev.button_index != BUTTON_WHEEL_UP and ev.button_index != BUTTON_WHEEL_DOWN: return
	var hovered = _meter_at(canvas.get_local_mouse_position())
	if !ev.alt and !(alpha > 0.5 and hovered != -1): return
	var idx = hovered if hovered != -1 else 0
	var step = FINE_STEP if ev.shift else STEP
	_change(idx, step if ev.button_index == BUTTON_WHEEL_UP else -step)
	get_tree().set_input_as_handled()

func _meter_at(p:Vector2) -> int:
	var corner = canvas.rect_size
	for i in meters.size():
		if p.distance_to(corner + meters[i].pos) <= meters[i].r + 12: return i
	return -1

# ---------------------------------------------------------------- volume
func _bus_level(bus:String) -> float:
	var i = AudioServer.get_bus_index(bus)
	if i == -1: return 0.0
	return clamp(db2linear(AudioServer.get_bus_volume_db(i)), 0.0, 1.0)

func _set_bus_level(bus:String, level:float):
	var i = AudioServer.get_bus_index(bus)
	if i == -1: return
	var db = -80.0 if level <= 0.0 else linear2db(level)
	AudioServer.set_bus_volume_db(i, db)
	_sync_sliders(get_tree().current_scene, bus, db)

func meter_level(idx:int) -> float:
	return _bus_level(meters[idx].buses[0])

# every bus of the meter moves by the same amount (Effects keeps the hit/miss balance)
func _change(idx:int, delta:float):
	for bus in meters[idx].buses:
		_set_bus_level(bus, clamp(stepify(_bus_level(bus) + delta, 0.01), 0.0, 1.0))
	active = idx
	show_left = SHOW_TIME
	save_left = SAVE_DELAY
	canvas.visible = true
	canvas.update()

# keep the settings page's volume sliders (VolumeSetting.gd) in step
func _sync_sliders(node:Node, bus:String, db:float):
	if node == null: return
	if node.get("target_bus") == bus and node.has_method("update_db"):
		node.update_db(db)
	for c in node.get_children():
		_sync_sliders(c, bus, db)

func _process(delta):
	if save_left > 0:
		save_left -= delta
		if save_left <= 0: Rhythia.save_settings()
	if show_left > 0:
		show_left -= delta
		alpha = min(alpha + delta / FADE_TIME, 1.0)
	elif alpha > 0:
		alpha = max(alpha - delta / FADE_TIME, 0.0)
	else:
		if canvas.visible: canvas.visible = false
		for i in shown.size(): shown[i] = -1.0
		return
	var hovered = _meter_at(canvas.get_local_mouse_position())
	for i in meters.size():
		var lv = meter_level(i)
		shown[i] = lv if shown[i] < 0 else R.approach(shown[i], lv, 16.0, delta)
		lit_k[i] = R.approach(lit_k[i], 1.0 if i == active or i == hovered else 0.0, 12.0, delta)
	var e = alpha * alpha * (3.0 - 2.0 * alpha) # smoothstep fade
	canvas.modulate.a = e
	canvas.rect_pivot_offset = canvas.rect_size
	var s = 0.96 + 0.04 * e # small grow while fading in
	canvas.rect_scale = Vector2(s, s)
	canvas.update()

# ---------------------------------------------------------------- drawing
func _centered(f:Font, text:String, c:Vector2, col:Color):
	canvas.draw_string(f, c + Vector2(-f.get_string_size(text).x / 2, f.get_ascent() / 2), text, col)

func _draw_overlay():
	var corner = canvas.rect_size
	for i in meters.size():
		var m = meters[i]
		var c = corner + m.pos
		var col = C_MUTED.linear_interpolate(C_TEXT, lit_k[i])
		var level = meter_level(i)
		var drawn = shown[i] if shown[i] >= 0 else level
		R.disc(canvas, c, m.r + RING_W + 4, C_BG)
		R.arc(canvas, c, m.r, RING_W, 0, TAU, C_TRACK)
		if drawn > 0.002:
			R.arc(canvas, c, m.r, RING_W, -PI / 2, -PI / 2 + TAU * min(drawn, 1.0), col, true)
		var big = m.r > 50
		_centered(big_font if big else mid_font, "%d" % round(level * 100), c + Vector2(0, -6), col)
		_centered(label_font, m.name, c + Vector2(0, m.r * 0.42), col)
