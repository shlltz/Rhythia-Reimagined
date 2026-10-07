extends CanvasLayer
# Replay viewer overlay (Sound Space Plus mod).
# Space pause, Left/Right seek 5s (Shift 1s, Ctrl 15s), Up/Down speed, , . frame step while paused,
# H cycle UI (all -> hide viewer + replay icon -> hide everything), K keybind panel,
# Esc leave, click/drag the bar to seek.

const SPEEDS = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
const FRAME = 1000.0 / 60.0
const KEYS = [
	["SPACE", "Pause / play"],
	["LEFT  RIGHT", "Seek 5s"],
	["+ SHIFT / CTRL", "Seek 1s / 15s"],
	["UP  DOWN", "Speed 0.25x - 2x"],
	[",  .", "Frame back / forward"],
	["CLICK BAR", "Jump to time"],
	["H", "Hide UI (2 steps)"],
	["K", "Hide this panel"],
	["ESC", "Leave replay"],
]

var spawn = null          # NoteManager
var speed_i:int = 3
var ui_state:int = 0      # 0 all, 1 recording (HUD only), 2 clean
var show_keys:bool = true
var dragging:bool = false
var drag_value:float = 0
var last_drag_seek:int = 0
var flash_t:float = 0
var esc_was_down:bool = false

# hidden benchmark (F8): seek to 0:30, record 20 s of frames, write user://perf_log.txt
var bench_t:float = -1
var bench_frames:Array = []
var bench_cpu:float = 0
var bench_draw:float = 0

var root:Control
var bar:Control
var time_label:Label
var speed_label:Label
var state_label:Label
var center_label:Label
var keys_panel:Control

class SeekBar extends Control:
	var viewer = null
	func _draw():
		var w:float = rect_size.x
		var h:float = rect_size.y
		var y:float = h / 2
		var f:float = viewer.progress()
		draw_rect(Rect2(0, y - 2, w, 4), Color(1, 1, 1, 0.22))
		draw_rect(Rect2(0, y - 2, w * f, 4), Color(1, 1, 1, 0.95))
		# misses (Rhythia-reimagined): red ticks, one per pixel column
		var lastx = -10
		for m in viewer.miss_marks():
			var x = round(w * m)
			if x - lastx < 2: continue
			lastx = x
			draw_rect(Rect2(x - 1, y - 8, 2, 16), Color(1, 0.33, 0.4, 0.9))
		draw_rect(Rect2(w * f - 3, y - 9, 6, 18), Color(1, 1, 1, 1))
	func _gui_input(ev):
		if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
			if ev.pressed:
				viewer.begin_drag(clamp(ev.position.x / rect_size.x, 0, 1))
			else:
				viewer.end_drag(clamp(ev.position.x / rect_size.x, 0, 1))
			accept_event()
		elif ev is InputEventMouseMotion and viewer.dragging:
			viewer.drag(clamp(ev.position.x / rect_size.x, 0, 1))
			accept_event()

func font(size:int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	f.size = size
	return f

func make_label(size:int, align:int) -> Label:
	var l = Label.new()
	l.set("custom_fonts/font", font(size))
	l.align = align
	l.valign = Label.VALIGN_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func box(bg:Color, border:Color, width:int) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = width
	sb.border_width_top = width
	sb.border_width_right = width
	sb.border_width_bottom = width
	return sb

func _ready():
	layer = 50
	root = Control.new()
	root.anchor_right = 1
	root.anchor_bottom = 1
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel = Panel.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.border_width_top = 1
	sb.border_color = Color(1, 1, 1, 0.35)
	panel.set("custom_styles/panel", sb)
	panel.anchor_top = 1
	panel.anchor_right = 1
	panel.anchor_bottom = 1
	panel.margin_top = -86
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)

	bar = SeekBar.new()
	bar.viewer = self
	bar.anchor_right = 1
	bar.margin_left = 24
	bar.margin_right = -24
	bar.margin_top = 8
	bar.margin_bottom = 36
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(bar)

	state_label = make_label(20, Label.ALIGN_LEFT)
	state_label.margin_left = 24
	state_label.margin_top = 40
	state_label.margin_right = 140
	state_label.margin_bottom = 76
	panel.add_child(state_label)

	time_label = make_label(20, Label.ALIGN_LEFT)
	time_label.margin_left = 140
	time_label.margin_top = 40
	time_label.margin_right = 420
	time_label.margin_bottom = 76
	panel.add_child(time_label)

	speed_label = make_label(20, Label.ALIGN_LEFT)
	speed_label.margin_left = 420
	speed_label.margin_top = 40
	speed_label.margin_right = 560
	speed_label.margin_bottom = 76
	panel.add_child(speed_label)

	var hint = make_label(15, Label.ALIGN_RIGHT)
	hint.anchor_right = 1
	hint.margin_left = 560
	hint.margin_right = -24
	hint.margin_top = 40
	hint.margin_bottom = 76
	hint.text = "K  keybinds"
	hint.modulate = Color(1, 1, 1, 0.5)
	panel.add_child(hint)

	center_label = make_label(40, Label.ALIGN_CENTER)
	center_label.anchor_right = 1
	center_label.margin_top = 40
	center_label.margin_bottom = 100
	root.add_child(center_label)

	build_keys_panel()
	apply_ui_state()

# keybind panel: one row per function, key shown as an outlined key cap
func build_keys_panel():
	keys_panel = PanelContainer.new()
	keys_panel.set("custom_styles/panel", box(Color(0, 0, 0, 0.62), Color(1, 1, 1, 0.3), 1))
	keys_panel.anchor_left = 1
	keys_panel.anchor_top = 1
	keys_panel.anchor_right = 1
	keys_panel.anchor_bottom = 1
	keys_panel.margin_left = -404
	keys_panel.margin_right = -24
	keys_panel.margin_bottom = -104
	keys_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(keys_panel)

	var m = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: m.set("custom_constants/margin_" + side, 14)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys_panel.add_child(m)

	var v = VBoxContainer.new()
	v.set("custom_constants/separation", 7)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)

	var title = make_label(18, Label.ALIGN_LEFT)
	title.text = "REPLAY CONTROLS"
	v.add_child(title)
	var line = ColorRect.new()
	line.color = Color(1, 1, 1, 0.35)
	line.rect_min_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)

	var cap_style = box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.85), 1)
	cap_style.content_margin_left = 8
	cap_style.content_margin_right = 8
	cap_style.content_margin_top = 3
	cap_style.content_margin_bottom = 3
	for k in KEYS:
		var row = HBoxContainer.new()
		row.set("custom_constants/separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap = make_label(15, Label.ALIGN_CENTER)
		cap.text = k[0]
		cap.rect_min_size = Vector2(150, 0)
		cap.set("custom_styles/normal", cap_style)
		row.add_child(cap)
		var desc = make_label(15, Label.ALIGN_LEFT)
		desc.text = k[1]
		desc.modulate = Color(1, 1, 1, 0.85)
		row.add_child(desc)
		v.add_child(row)

func length() -> float:
	return max(spawn.replay_length(), 1)

# note times of the misses (0..1 of the length), from the replay's per-note results
var _misses = null
func miss_marks() -> Array:
	if _misses != null: return _misses
	var rp = Rhythia.replay
	if !rp or !spawn or spawn.notes.empty() or rp.note_results.empty(): return []
	var l = length()
	_misses = []
	for i in spawn.notes.size():
		if rp.note_results.has(i) and !rp.note_results[i] and spawn.notes[i][1] <= l: _misses.append(spawn.notes[i][1] / l)
	return _misses

func progress() -> float:
	if dragging: return drag_value
	return clamp(spawn.rms / length(), 0, 1)

func fmt(t_ms:float) -> String:
	var s:int = int(max(t_ms, 0) / 1000)
	return "%d:%02d" % [s / 60, s % 60]

func begin_drag(v:float):
	dragging = true
	drag_value = v
	do_seek(v * length())

func drag(v:float):
	drag_value = v
	var now = OS.get_ticks_msec()
	if now - last_drag_seek > 90:
		last_drag_seek = now
		do_seek(v * length())

func end_drag(v:float):
	if !dragging: return
	dragging = false
	do_seek(v * length())

func do_seek(t:float):
	spawn.replay_seek(t)

func set_speed(i:int):
	speed_i = int(clamp(i, 0, SPEEDS.size() - 1))
	spawn.set_replay_rate(SPEEDS[speed_i])
	flash("%.2fx" % SPEEDS[speed_i])

func toggle_pause():
	spawn.replay_paused = !spawn.replay_paused
	flash("PAUSED" if spawn.replay_paused else "")

func flash(t:String):
	center_label.text = t
	flash_t = 1.2 if t != "PAUSED" else 0

func leave():
	var game = spawn.get_parent()
	if game.ending: return
	spawn.replay_paused = false
	game.end(Globals.END_GIVEUP)

func apply_ui_state():
	var game = spawn.get_parent()
	var hud = game.get_node_or_null("HUD")
	if hud: hud.visible = ui_state < 2
	var icon = game.get_node_or_null("HUD/EnergyVP/Control/Modifiers/Icons/H/Replaying")
	if icon: icon.visible = ui_state == 0
	root.visible = ui_state == 0
	keys_panel.visible = show_keys
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if ui_state == 0 else Input.MOUSE_MODE_HIDDEN)

func _input(ev):
	if not (ev is InputEventKey) or not ev.pressed: return
	var handled = true
	match ev.scancode:
		KEY_SPACE:
			if ev.echo: return
			toggle_pause()
		KEY_ESCAPE:
			if ev.echo: return
			leave()
		KEY_LEFT, KEY_RIGHT:
			var amt:float = 5000
			if ev.shift: amt = 1000
			elif ev.control: amt = 15000
			if ev.scancode == KEY_LEFT: amt = -amt
			do_seek(spawn.rms + amt)
		KEY_UP:
			if ev.echo: return
			set_speed(speed_i + 1)
		KEY_DOWN:
			if ev.echo: return
			set_speed(speed_i - 1)
		KEY_PERIOD:
			if !spawn.replay_paused: spawn.replay_paused = true
			spawn.replay_step = FRAME / 1000.0
			flash("PAUSED")
		KEY_COMMA:
			if !spawn.replay_paused: spawn.replay_paused = true
			do_seek(spawn.rms - FRAME)
			flash("PAUSED")
		KEY_H:
			if ev.echo: return
			ui_state = (ui_state + 1) % 3
			apply_ui_state()
		KEY_F8:
			if ev.echo or bench_t >= 0: return
			do_seek(30000)
			spawn.replay_paused = false
			bench_t = 0
			bench_frames = []
			bench_cpu = 0
			bench_draw = 0
			flash("BENCH")
		KEY_K:
			if ev.echo: return
			show_keys = !show_keys
			apply_ui_state()
		_:
			handled = false
	if handled: get_tree().set_input_as_handled()

func bench_step(delta):
	bench_t += delta
	if bench_t < 0.5: return  # let the seek settle
	bench_frames.append(delta)
	bench_cpu += Performance.get_monitor(Performance.TIME_PROCESS)
	bench_draw += Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME)
	if bench_t < 20.5: return
	var n = bench_frames.size()
	var total = 0.0
	for d in bench_frames: total += d
	var sorted = bench_frames.duplicate()
	sorted.sort()
	var worst = 0.0
	var k = max(1, n / 100)
	for i in range(n - k, n): worst += sorted[i]
	worst /= k
	var line = "%s  frames %d  avg %.1f fps  1%% low %.1f fps  cpu(process) %.3f ms  draw calls %.0f\n" % [
		str(OS.get_unix_time()),
		n, n / total, 1.0 / worst, bench_cpu / n * 1000.0, bench_draw / n]
	var f = File.new()
	var path = Globals.p("user://perf_log.txt")
	if f.file_exists(path):
		f.open(path, File.READ_WRITE)
		f.seek_end()
	else:
		f.open(path, File.WRITE)
	f.store_string(line)
	f.close()
	flash("BENCH DONE %.0f fps" % (n / total))
	bench_t = -1

func _process(delta):
	if bench_t >= 0: bench_step(delta)
	# Esc is also polled, in case the key event never reaches _input
	var esc = Input.is_key_pressed(KEY_ESCAPE)
	if esc and !esc_was_down: leave()
	esc_was_down = esc

	if flash_t > 0:
		flash_t -= delta
		if flash_t <= 0 and !spawn.replay_paused: center_label.text = ""
	if spawn.replay_paused and center_label.text == "": center_label.text = "PAUSED"
	center_label.visible = ui_state == 0
	if !root.visible: return
	state_label.text = "PAUSED" if spawn.replay_paused else "PLAYING"
	time_label.text = "%s / %s" % [fmt(progress() * length()), fmt(length())]
	speed_label.text = "%.2fx" % SPEEDS[speed_i]
	bar.update()
