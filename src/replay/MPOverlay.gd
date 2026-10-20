extends CanvasLayer
# In-game multiplayer overlay (added to the song scene by MPClient.game_ready): a compact live
# scoreboard on the left edge, the enforced No Fail tag, and the shared-start countdown while the
# lead-in is held. Reads MPClient only; small and see-through so it stays out of the playfield.

const Look = preload("res://mods/replay/Look.gd")
const ROWS = 8

var client
var box:Control
var head:Label
var rows:Array = []
var banner:Label
var sub:Label
var fonts:Dictionary = {}
var _t:float = 0.0

func _ready():
	name = "MPOverlay"
	layer = 55
	pause_mode = PAUSE_MODE_PROCESS
	var root = Control.new()
	root.anchor_right = 1
	root.anchor_bottom = 1
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://uitheme.tres"): root.theme = load("res://uitheme.tres")
	add_child(root)
	box = Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.margin_left = 12
	box.margin_top = -150
	box.margin_right = 262
	box.margin_bottom = 150
	root.add_child(box)
	var bg = Panel.new()
	bg.add_stylebox_override("panel", Look.box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.1), 1, 0))
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bg)
	head = _lbl("MULTIPLAYER  /  NO FAIL ON", 11, Color(1, 1, 1, 0.55), box)
	head.rect_position = Vector2(10, 7)
	for i in ROWS:
		var r = _lbl("", 14, Color(1, 1, 1, 0.8), box)
		r.rect_position = Vector2(10, 28 + i * 21)
		r.rect_size = Vector2(220, 20)
		r.clip_text = true
		rows.append(r)
	banner = _lbl("", 34, Color(1, 1, 1), root)
	banner.anchor_left = 0; banner.anchor_right = 1
	banner.anchor_top = 0.3; banner.anchor_bottom = 0.3
	banner.margin_top = -24; banner.margin_bottom = 24
	banner.align = Label.ALIGN_CENTER
	sub = _lbl("", 16, Color(1, 1, 1, 0.6), root)
	sub.anchor_left = 0; sub.anchor_right = 1
	sub.anchor_top = 0.3; sub.anchor_bottom = 0.3
	sub.margin_top = 26; sub.margin_bottom = 50
	sub.align = Label.ALIGN_CENTER
	_update()

func _lbl(t:String, size:int, col:Color, parent:Control) -> Label:
	var l = Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if !fonts.has(size):
		var f = parent.get_font("font", "Label")
		if f is DynamicFont:
			f = f.duplicate()
			f.size = size
		fonts[size] = f
	l.add_font_override("font", fonts[size])
	l.add_color_override("font_color", col)
	l.add_color_override("font_color_shadow", Color(0, 0, 0, 0.7))
	l.add_constant_override("shadow_offset_x", 1)
	l.add_constant_override("shadow_offset_y", 1)
	parent.add_child(l)
	return l

func _process(delta):
	_t += delta
	if _t >= 0.1:
		_t = 0.0
		_update()

func _update():
	if !client or !is_instance_valid(client): return
	# start banner while the lead-in is held for the shared start
	match client.phase:
		"ready":
			var n = 0
			var tot = 0
			for p in client.players:
				if p.get("in_match", false):
					tot += 1
					if str(p.get("status", "")) in ["loaded", "playing"]: n += 1
			banner.text = "WAITING FOR PLAYERS"
			sub.text = "%d / %d loaded" % [n, max(tot, 1)] if tot > 0 else "loading..."
		"waiting":
			var left = max(client.go_local - OS.get_ticks_msec(), 0)
			banner.text = "STARTING IN %.1f" % (left / 1000.0)
			sub.text = "everyone starts together"
		_:
			banner.text = ""
			sub.text = ""
	if client.status == "reconnecting": sub.text = "connection lost - reconnecting..."
	elif client.status == "idle" and client.phase != "none": sub.text = "disconnected from the lobby - this run is local only"
	var list = client.board
	if list.empty():
		list = []
		for p in client.players:
			if p.get("in_match", false): list.append({pid = p.pid, name = p.name, score = p.get("s", {}).get("score", 0), conn = p.conn, status = p.status})
	var mine_i = -1
	for i in list.size():
		if int(list[i].get("pid", -1)) == client.pid: mine_i = i
	var shown = []
	for i in min(list.size(), ROWS): shown.append(i)
	if mine_i >= ROWS: shown[ROWS - 1] = mine_i # (the local player always shows, in the last row if far down)
	for r in rows.size():
		var l = rows[r]
		if r >= shown.size():
			l.text = ""
			continue
		var e = list[shown[r]]
		var mine = int(e.get("pid", -1)) == client.pid
		var tag = ""
		if str(e.get("conn", "ok")) != "ok": tag = "  (lost)"
		elif str(e.get("status", "")) == "finished": tag = "  done"
		elif str(e.get("status", "")) == "quit": tag = "  quit"
		l.text = "#%d  %s  %s%s" % [shown[r] + 1, _short(str(e.get("name", "?")), 11), _comma(int(e.get("score", 0))), tag]
		l.add_color_override("font_color", Color(1, 1, 1, 1.0) if mine else Color(1, 1, 1, 0.72))
	box.margin_top = -150
	box.margin_bottom = box.margin_top + 34 + max(shown.size(), 1) * 21

static func _short(s:String, n:int) -> String:
	return s if s.length() <= n else s.substr(0, n - 1) + "."

static func _comma(n:int) -> String:
	var s = str(n)
	var out = ""
	var k = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		k += 1
		if k % 3 == 0 and i > 0: out = "," + out
	return out
