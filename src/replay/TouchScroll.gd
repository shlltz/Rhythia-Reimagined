extends Node
# Touch screens (Android): drag anywhere on a list or the settings page to scroll it, with momentum.
# Godot 3 only scrolls a ScrollContainer when the drag starts on an empty spot (buttons, sliders and
# check boxes keep the touch), and an ItemList can't be dragged at all. This works on the touch's
# emulated mouse events: a mostly vertical drag over a scrollable ScrollContainer / ItemList scrolls
# it, and the button the finger started on doesn't fire when it lifts.
# One instance on the root (added by menu2.gd), only when the device has a touch screen.

const START = 14.0    # px of vertical travel before it counts as a scroll
const FRICTION = 4.0  # momentum decay per second

var target = null     # ScrollContainer or ItemList
var bar:ScrollBar
var from:Vector2
var dragging:bool = false
var vel:float = 0.0
var coast = null

func _ready():
	name = "TouchScroll"
	pause_mode = PAUSE_MODE_PROCESS

func _input(ev):
	if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
		if ev.pressed:
			coast = null
			vel = 0.0
			dragging = false
			target = _find(ev.position)
			bar = _bar(target)
			from = ev.position
		else:
			if dragging:
				# lift outside the screen: the button pressed at the start gets no click
				ev.position = Vector2(-100000, -100000)
				ev.global_position = ev.position
				coast = target
			target = null
			dragging = false
	elif ev is InputEventMouseMotion and target and ev.button_mask & BUTTON_MASK_LEFT:
		if !is_instance_valid(target) or !target.is_visible_in_tree():
			target = null
			return
		if !dragging:
			var d = ev.position - from
			if abs(d.y) < START or abs(d.y) < abs(d.x): return
			dragging = true
		_scroll(target, -ev.relative.y)
		var dt = max(get_process_delta_time(), 0.001)
		vel = lerp(vel, -ev.relative.y / dt, 0.4)
		get_tree().set_input_as_handled() # buttons / sliders under the finger don't see the drag

func _process(delta):
	if coast == null: return
	if !is_instance_valid(coast) or !coast.is_visible_in_tree() or abs(vel) < 20:
		coast = null
		return
	_scroll(coast, vel * delta)
	vel *= max(0.0, 1.0 - FRICTION * delta)

func _scroll(c, dy:float):
	var b = _bar(c)
	if !b: return
	b.value = clamp(b.value + dy, b.min_value, max(b.min_value, b.max_value - b.page))
	if c is ScrollContainer: c.scroll_vertical = int(b.value)

func _bar(c):
	if c is ScrollContainer: return c.get_v_scrollbar()
	elif c is ItemList: return c.get_v_scroll()
	return null

func _can_scroll(c) -> bool:
	var b = _bar(c)
	return b != null and b.max_value - b.page > b.min_value + 1

# the scrollable under point p: highest canvas layer first, then the last drawn (deepest) one
func _find(p:Vector2):
	var best = null
	var best_key = -1000000
	var found = []
	_collect(get_tree().root, p, 0, found)
	for i in found.size():
		var key = found[i][1] * 100000 + i
		if key > best_key:
			best_key = key
			best = found[i][0]
	return best

func _collect(n:Node, p:Vector2, layer:int, out:Array):
	if n is Viewport and n != get_tree().root: return # 3D / render viewports: other coordinates
	if n is CanvasLayer:
		if n.get("visible") == false: return
		layer = n.layer
	elif n is CanvasItem and !n.visible: return
	if (n is ScrollContainer or n is ItemList) and n.get_global_rect().has_point(p) and _can_scroll(n):
		out.append([n, layer])
	for c in n.get_children(): _collect(c, p, layer, out)
