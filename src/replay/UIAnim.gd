extends Node
# Ease-out slide + fade for one Control (menu page, map info panel, settings tab, popup).
#   UIAnim.play(control, Vector2(40, 0))                           # slide in from 40px right, fade in
#   UIAnim.play(panel, Vector2.ZERO, Vector2(0, 40), 1, 0, 0.18)  # slide out + fade out
# Works on children of Containers too: the container re-sorts its children at any
# time (text change, resize), so the offset is re-applied after every sort.

signal finished

const PATH = "res://mods/replay/UIAnim.gd"
const MAX_STEP = 1.0 / 30.0

var target:Control
var from_off:Vector2
var to_off:Vector2
var from_a:float
var to_a:float
var duration:float
var t:float = 0.0
var eased:float = 0.0
var base:Vector2 # position the layout gives the control (no offset)
var fixed_base:bool = false # ignore container re-sorts (settings tabs: always at the origin)

static func play(target:Control, from_off:Vector2, to_off:Vector2 = Vector2.ZERO, from_a:float = 0.0, to_a:float = 1.0, duration:float = 0.25) -> Node:
	var base = target.rect_position
	var old = target.get_node_or_null("UIAnim")
	if old: # restart: keep the un-offset position, drop the running animation
		base = old.base
		old.stop()
	var a = load(PATH).new()
	a.name = "UIAnim"
	a.target = target
	a.base = base
	a.from_off = from_off
	a.to_off = to_off
	a.from_a = from_a
	a.to_a = to_a
	a.duration = max(duration, 0.01)
	target.add_child(a)
	a._apply()
	var parent = target.get_parent()
	if parent is Container: parent.connect("sort_children", a, "_on_sorted")
	return a

func _process(delta):
	if !is_instance_valid(target):
		queue_free()
		return
	# cap the step: a hitch (e.g. the replay browser loading its list) must not skip the animation
	t = min(t + min(delta, MAX_STEP) / duration, 1.0)
	eased = 1.0 - pow(1.0 - t, 3) # ease-out cubic
	_apply()
	if t >= 1.0:
		stop()
		emit_signal("finished")

func _apply():
	target.rect_position = base + from_off.linear_interpolate(to_off, eased)
	target.modulate.a = lerp(from_a, to_a, eased)

# the container just laid the control out again: that is the new base
func _on_sorted():
	if fixed_base:
		_apply()
		return
	base = target.rect_position
	_apply()

# end now, leaving the control at its final offset/alpha
func stop():
	set_process(false)
	if is_instance_valid(target):
		var parent = target.get_parent()
		if parent and parent.is_connected("sort_children", self, "_on_sorted"):
			parent.disconnect("sort_children", self, "_on_sorted")
		target.rect_position = base + to_off
		target.modulate.a = to_a
		if get_parent() == target: target.remove_child(self)
	queue_free()
