extends Node
# Smooth wheel scrolling for a ScrollContainer (personal build: the settings page, the Customize panel):
# a wheel notch moves a target and the page eases toward it instead of jumping 1/8 of a page. Takes
# the wheel before the page's own controls (a slider under the mouse no longer changes value while you
# scroll past it); left alone with Alt / Ctrl / Shift held (Alt+wheel = volume) or while a popup is
# open. A scroll from elsewhere (scrollbar drag, a tab switch resetting it) becomes the new target.
# SmoothScroll.attach(scroll_container).

const STEP = 120.0     # px per wheel notch
const RATE = 16.0      # easing toward the target, 1/s

var sc:ScrollContainer
var target:float = 0.0
var pos:float = 0.0    # the eased position (sub-pixel; scroll_vertical is an int)
var moving:bool = false

static func attach(s:ScrollContainer):
	if !s or s.has_node("SmoothScroll"): return
	var n = load("res://mods/replay/SmoothScroll.gd").new()
	n.name = "SmoothScroll"
	n.sc = s
	s.add_child(n)

func _ready():
	pos = sc.scroll_vertical
	target = pos
	set_process(false)

func _max() -> float:
	var b = sc.get_v_scrollbar()
	return max(0.0, b.max_value - b.page) if b else 0.0

func _input(ev):
	if !(ev is InputEventMouseButton) or !ev.pressed: return
	if ev.button_index != BUTTON_WHEEL_UP and ev.button_index != BUTTON_WHEEL_DOWN: return
	if ev.alt or ev.control or ev.shift: return
	if !sc.is_visible_in_tree() or !sc.get_global_rect().has_point(ev.position): return
	if get_viewport().gui_has_modal_stack(): return
	if _max() <= 0.0: return
	if !moving: pos = sc.scroll_vertical # (start from wherever it is now)
	if abs(target - pos) > STEP * 6 or !moving: target = pos
	var k = ev.factor if ev.factor > 0 else 1.0
	target = clamp(target + (STEP if ev.button_index == BUTTON_WHEEL_DOWN else -STEP) * k, 0.0, _max())
	moving = true
	set_process(true)
	get_tree().set_input_as_handled()

func _process(delta):
	if abs(sc.scroll_vertical - round(pos)) > 1.5: # scrolled from elsewhere: follow it
		pos = sc.scroll_vertical
		target = pos
	pos = lerp(pos, target, 1.0 - exp(-delta * RATE))
	if abs(target - pos) < 0.5:
		pos = target
		moving = false
		set_process(false)
	sc.scroll_vertical = int(round(pos))
