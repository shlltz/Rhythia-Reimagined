extends Node
# osu!-style button feel: every button under the parent grows a little on hover, squashes on
# press and springs back with a small overshoot on release. One spring per moving button,
# buttons at rest cost nothing. Buttons added later (map cards, pages) are picked up too.

const HOVER = 1.04
const PRESS = 0.93
const STIFF = 420.0   # spring stiffness
const DAMP = 20.0     # spring damping (lower = more bounce)
const KICK = 3.0      # extra velocity on release (the "pop")

var root:Node
var anim:Dictionary = {}   # button -> [scale, velocity, target, base Vector2]

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	root = get_parent()
	get_tree().connect("node_added", self, "_hook")
	_hook_tree(root)

func _hook_tree(n:Node):
	for c in n.get_children():
		_hook(c)
		_hook_tree(c)

func _hook(n:Node):
	if !(n is BaseButton) or n.has_meta("juice") or !root.is_a_parent_of(n): return
	n.set_meta("juice", true)
	n.connect("mouse_entered", self, "_aim", [n, HOVER])
	n.connect("mouse_exited", self, "_aim", [n, 1.0])
	n.connect("button_down", self, "_aim", [n, PRESS])
	n.connect("button_up", self, "_release", [n])

func _state(b:Control) -> Array:
	if !anim.has(b): anim[b] = [1.0, 0.0, 1.0, b.rect_scale]
	return anim[b]

func _aim(b:Control, target:float):
	if !is_instance_valid(b) or (b is BaseButton and b.disabled): return
	_state(b)[2] = target
	set_process(true)

func _release(b:Control):
	if !is_instance_valid(b): return
	var st = _state(b)
	st[2] = HOVER if b.get_global_rect().has_point(b.get_global_mouse_position()) else 1.0
	st[1] += KICK
	set_process(true)

func _process(delta):
	delta = min(delta, 1.0 / 30.0) # stay stable on frame hitches
	for b in anim.keys():
		if !is_instance_valid(b) or !b.is_visible_in_tree():
			if is_instance_valid(b): b.rect_scale = anim[b][3]
			anim.erase(b)
			continue
		var st = anim[b]
		st[1] += ((st[2] - st[0]) * STIFF - st[1] * DAMP) * delta
		st[0] += st[1] * delta
		if st[2] == 1.0 and abs(st[0] - 1.0) < 0.001 and abs(st[1]) < 0.01:
			b.rect_scale = st[3]
			anim.erase(b)
			continue
		b.rect_pivot_offset = b.rect_size / 2
		b.rect_scale = st[3] * st[0]
	if anim.empty(): set_process(false)
