extends Control
# Round button in the top left corner of the menu: pauses / resumes every music player (anything
# on the Music bus: menu music, map previews). Players created while paused start paused too.
# Everything is resumed when the menu closes, so gameplay audio is never affected.
# Auto-hides: fades out after IDLE_HIDE s without mouse movement, back in when the mouse moves.

const BUSES = ["Music"]
const SIZE = 44.0
const ACCENT = Color("#8a6cff")
const IDLE_HIDE = 2.5

var paused:bool = false
var hover:bool = false
var idle:float = 0.0
var icons = null # Icons.gd when the Flaticon font is there

func _ready():
	name = "MusicPause"
	# top left corner, centred over the sidebar column
	margin_left = 7
	margin_right = 7 + SIZE
	margin_top = 12
	margin_bottom = 12 + SIZE
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	hint_tooltip = "Pause / resume music"
	icons = load("res://mods/replay/Icons.gd")
	if !icons.available(): icons = null
	connect("mouse_entered", self, "_hover", [true])
	connect("mouse_exited", self, "_hover", [false])
	get_tree().connect("node_added", self, "_on_node_added")

func _input(e):
	if e is InputEventMouseMotion: idle = 0.0

func _process(delta):
	idle += delta
	var show = hover or idle < IDLE_HIDE
	var a = move_toward(modulate.a, 1.0 if show else 0.0, delta / (0.15 if show else 0.4))
	if a != modulate.a:
		modulate.a = a
		mouse_filter = MOUSE_FILTER_STOP if a > 0.2 else MOUSE_FILTER_IGNORE # hidden = no invisible click target

func _hover(v:bool):
	hover = v
	update()

func _gui_input(e):
	if e is InputEventMouseButton and e.button_index == BUTTON_LEFT:
		accept_event()
		if !e.pressed and Rect2(Vector2(), rect_size).has_point(e.position): toggle()

func toggle():
	paused = !paused
	_apply(get_tree().root)
	update()

func _is_music(n:Node) -> bool:
	return (n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D) and n.bus in BUSES

func _apply(n:Node):
	if _is_music(n): n.stream_paused = paused
	for c in n.get_children(): _apply(c)

func _on_node_added(n:Node):
	if paused and _is_music(n): n.stream_paused = true

func _exit_tree():
	if get_tree().is_connected("node_added", self, "_on_node_added"):
		get_tree().disconnect("node_added", self, "_on_node_added")
	if paused:
		paused = false
		_apply(get_tree().root)

func _draw():
	var c = rect_size / 2
	var r = SIZE / 2
	draw_circle(c, r, Color(0, 0, 0, 0.75))
	var ring = ACCENT if paused else Color(1, 1, 1, 0.35 if !hover else 0.7)
	draw_arc(c, r - 1, 0, TAU, 48, ring, 2.0, true)
	var col = Color(1, 1, 1, 0.95 if hover else 0.8)
	if icons:
		var s = SIZE * 0.4
		icons.draw(self, "play" if paused else "pause", Rect2(c - Vector2(s, s) / 2 + Vector2(1 if paused else 0, 0), Vector2(s, s)), col)
	elif paused: # play triangle
		draw_colored_polygon(PoolVector2Array([c + Vector2(-5, -9), c + Vector2(-5, 9), c + Vector2(10, 0)]), col)
	else: # pause bars
		draw_rect(Rect2(c + Vector2(-8, -9), Vector2(5, 18)), col)
		draw_rect(Rect2(c + Vector2(3, -9), Vector2(5, 18)), col)
