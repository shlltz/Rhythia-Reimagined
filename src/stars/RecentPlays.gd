extends VBoxContainer
# Recent plays of the selected map (like the rewrite / osu! local scores): every finished run is
# stored in user://recent_plays.json (Game.gd -> record()), listed best to worst (passed first,
# then score) with "x mins ago". Clicking a play with a saved replay watches it.

const FILE = "user://recent_plays.json"
const KEEP = 50            # plays kept per map
const SHOWN = 8

var list:VBoxContainer
var empty:Label
var toggle:Button
var body:VBoxContainer
var spacer:Control           # set by SongInfoScreen: the free space right of the cover column
var open:bool = false
var k:float = 0.0            # 0 closed .. 1 open (animated)
var count:int = 0

# closed: cover/info column centred; open: list on the left, column slides right
func set_open(v = null):
	open = !open if v == null else v
	Engine.set_meta("recent_open", open)
	_label()
	set_process(true)

func _label():
	toggle.text = ("[-] " if open else "[+] ") + "OTHER PLAYS (%d)" % count

func _process(delta):
	k = lerp(k, 1.0 if open else 0.0, 1.0 - exp(-delta * 12.0))
	if abs(k - (1.0 if open else 0.0)) < 0.002:
		k = 1.0 if open else 0.0
		set_process(false)
	size_flags_stretch_ratio = 1.0 + k * 0.6 if spacer else 1.6
	if spacer: spacer.size_flags_stretch_ratio = 1.0 - k * 0.999
	body.visible = k > 0.02
	body.modulate.a = k

# ------------------------------------------------------------------ storage
static func _load() -> Dictionary:
	var f = File.new()
	if f.open(Globals.p(FILE), File.READ) != OK: return {}
	var d = parse_json(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

static func record(run:Dictionary):
	var song = run.get("song")
	if !song or run.get("replay"): return
	var all = _load()
	var plays:Array = all.get(song.id, [])
	var acc = float(run.hits) / max(1.0, float(run.total))
	plays.append({t = OS.get_unix_time(), score = run.score, acc = acc, misses = run.misses, combo = run.combo,
		passed = run.end_type == Globals.END_PASS, pauses = run.pauses, speed = run.speed,
		replay = run.get("replay_path", ""), hits = run.hits, total = run.total, end = run.end_type,
		position = run.position, length = run.length, mods = run.get("mods", [])})
	while plays.size() > KEEP: plays.pop_front()
	all[song.id] = plays
	var f = File.new()
	if f.open(Globals.p(FILE), File.WRITE) == OK:
		f.store_string(to_json(all))
		f.close()

static func grade(p:Dictionary) -> Array: # [letter, colour] - EndInfo.gd thresholds
	if !p.passed: return ["F", Color("#ff6b6b")]
	var a = float(p.acc)
	if a >= 1.0: return ["SS", Color("#ffe27a")]
	if a >= 0.98: return ["S", Color("#91fffa")]
	if a >= 0.95: return ["A", Color("#91ff92")]
	if a >= 0.90: return ["B", Color("#e7ffc0")]
	if a >= 0.85: return ["C", Color("#fcf7b3")]
	return ["D", Color("#fcd0b3")]

static func ago(t:int) -> String:
	var s = OS.get_unix_time() - t
	if s < 60: return "just now"
	if s < 3600: return "%d min%s ago" % [s / 60, "" if s < 120 else "s"]
	if s < 86400: return "%d hour%s ago" % [s / 3600, "" if s < 7200 else "s"]
	return "%d day%s ago" % [s / 86400, "" if s < 172800 else "s"]

static func _better(a, b) -> bool:
	if a.passed != b.passed: return a.passed
	return a.score > b.score

# ------------------------------------------------------------------ UI
func _ready():
	add_constant_override("separation", 6)
	toggle = Button.new()
	toggle.flat = true
	toggle.focus_mode = FOCUS_NONE
	toggle.align = Button.ALIGN_LEFT
	toggle.size_flags_horizontal = 0
	toggle.modulate = Color(1, 1, 1, 0.75)
	for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_focus"]: # (the share theme's flat-button text was invisible)
		toggle.add_color_override(k, Color(1, 1, 1, 1.0 if k == "font_color_hover" else 0.85))
	toggle.connect("pressed", self, "set_open", [null])
	add_child(toggle)
	body = VBoxContainer.new()
	body.add_constant_override("separation", 4)
	add_child(body)
	empty = Label.new()
	empty.modulate = Color(1, 1, 1, 0.35)
	body.add_child(empty)
	list = VBoxContainer.new()
	list.add_constant_override("separation", 4)
	body.add_child(list)
	open = Engine.get_meta("recent_open") if Engine.has_meta("recent_open") else false
	k = 1.0 if open else 0.0
	Rhythia.connect("selected_song_changed", self, "refresh")
	var t = Timer.new() # keep "x mins ago" fresh
	t.wait_time = 30
	t.autostart = true
	t.connect("timeout", self, "refresh")
	add_child(t)
	refresh()

func refresh(_s = null):
	for c in list.get_children(): c.queue_free()
	var song = Rhythia.selected_song
	var plays:Array = _load().get(song.id, []) if song else []
	plays.sort_custom(self, "_better")
	# the best play is already the personal-best panel below: list the 2nd best to the worst
	empty.text = "No plays yet" if plays.empty() else "Only your best play so far"
	empty.visible = plays.size() < 2
	for i in range(1, min(plays.size(), SHOWN + 1)): list.add_child(_row(plays[i], false))
	count = max(0, plays.size() - 1)
	_label()
	set_process(true)

func _row(p:Dictionary, top:bool) -> Control:
	var b = Button.new()
	b.rect_min_size = Vector2(0, 40)
	b.focus_mode = FOCUS_NONE
	b.flat = true
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.07 if top else 0.035)
	sb.border_color = grade(p)[1]
	sb.border_width_left = 4
	var sh = sb.duplicate()
	sh.bg_color = Color(1, 1, 1, 0.12)
	for s in ["normal", "pressed", "disabled", "focus"]: b.add_stylebox_override(s, sb)
	b.add_stylebox_override("hover", sh)
	var has_replay = str(p.get("replay", "")) != "" and File.new().file_exists(str(p.replay))
	b.connect("pressed", self, "_open", [p])
	var g = grade(p)
	_cell(b, g[0], 12, 44, g[1])
	_cell(b, Globals.comma_sep(int(p.score)), 52, 118, Color(1, 1, 1))
	var acc = "%.2f%%" % (float(p.acc) * 100)
	var extra = "FC" if p.passed and int(p.misses) == 0 else "%d miss" % int(p.misses)
	if float(p.speed) != 1.0: extra += "  %.2fx" % float(p.speed)
	if int(p.pauses) > 0: extra += "  paused"
	var mid = _cell(b, acc + "  " + extra, 172, 0, Color(1, 1, 1, 0.75))
	mid.anchor_right = 1
	mid.margin_right = -112
	var a = _cell(b, ago(int(p.t)), -112, 104, Color(1, 1, 1, 0.45))
	a.anchor_left = 1; a.anchor_right = 1
	a.align = Label.ALIGN_RIGHT
	if !p.passed or int(p.pauses) > 0: b.modulate = Color(1, 1, 1, 0.6)
	return b

func _cell(parent:Control, text:String, x:float, w:float, col:Color) -> Label:
	var l = Label.new()
	l.text = text
	l.clip_text = true
	l.valign = Label.VALIGN_CENTER
	l.mouse_filter = MOUSE_FILTER_IGNORE
	l.anchor_bottom = 1
	l.margin_left = x; l.margin_right = x + w
	l.modulate = col
	parent.add_child(l)
	return l

# results screen for a stored play (Watch replay is on it when the replay file still exists)
func _open(p:Dictionary):
	var menu = get_tree().root.get_node_or_null("Menu")
	var rs = "res://mods/replay/ResultsScreen.gd"
	if !menu or !ResourceLoader.exists(rs) or menu.has_node("ResultsScreen"): return
	var song = Rhythia.selected_song
	var total = int(p.get("total", song.note_count if song else 0))
	var r = load(rs).new({song = song, score = int(p.score), hits = int(p.get("hits", round(float(p.acc) * total))),
		misses = int(p.misses), total = total, combo = int(p.combo),
		end_type = int(p.get("end", Globals.END_PASS if p.passed else Globals.END_FAIL)), pauses = int(p.pauses),
		position = float(p.get("position", 0)), length = float(p.get("length", song.last_ms if song else 1)),
		speed = float(p.speed), replay = false, replay_path = str(p.get("replay", "")), mods = p.get("mods", []),
		when = ago(int(p.t)), stored = true})
	r.name = "ResultsScreen"
	menu.add_child(r)

func _watch(path:String):
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = path
	var menu = get_tree().root.get_node_or_null("Menu")
	if menu and "black_fade_target" in menu: menu.black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
