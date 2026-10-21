extends CanvasLayer
# Rhythia-reimagined Replay Studio: one replay analysed offline (ReplayStats.gd) - accuracy, combo
# and cursor speed over the song with every miss and pause marked, where the cursor was (heatmap),
# where the hits landed against the note centre, hit delays - and another replay of the same map laid
# over it (any of them, or the best-scoring one). WATCH / WATCH FROM open the replay viewer, at the
# time picked on the graphs or in the miss list. Opened from the replay browser and the results
# screen; the analysis runs on a worker thread. Keys: N / Shift+N next / previous miss, Enter watch
# from the picked time, Esc close. CLIP records a few seconds of the replay as a GIF (and an MP4 when
# ffmpeg is installed): ClipRecorder.gd / ClipExport.gd.

const S = preload("res://mods/replay/ReplayStats.gd")
const Look = preload("res://mods/replay/Look.gd")
const UIAnim = preload("res://mods/replay/UIAnim.gd")
const W = 1200.0
const H = 700.0
const COL_B = Color(1.0, 0.78, 0.3)
const COL_MISS = Color(1.0, 0.32, 0.36)
const COL_PICK = Color(0.35, 0.9, 1.0)

var path:String = ""             # the replay (set before adding the node, or use open())
var A = null                     # {path, rp, st, opts, label}
var B = null
var song = null
var pick_ms:float = -1.0
var thread:Thread = null
var cancel:bool = false
var closing:bool = false
var ACCENT:Color = Look.accent()
var root:Control
var card:Panel
var fonts:Dictionary = {}
var sub_lbl:Label
var status:Label
var stats_box:GridContainer
var graphs:Control
var heat:Control
var aim:Control
var miss_list:ItemList
var miss_ms:Array = []
var cmp:OptionButton
var cmp_paths:Array = []
var btn_watch:Button
var btn_from:Button

static func open(parent:Node, replay_path:String):
	var s = load("res://mods/replay/ReplayStudio.gd").new()
	s.path = replay_path
	s.name = "ReplayStudio"
	parent.add_child(s)
	return s

func _ready():
	layer = 40
	root = Control.new()
	root.anchor_right = 1
	root.anchor_bottom = 1
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists("res://uitheme.tres"): root.theme = load("res://uitheme.tres")
	add_child(root)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	root.add_child(dim)
	card = Panel.new()
	card.add_stylebox_override("panel", Look.box(Color(0.05, 0.05, 0.07, 0.98), Color(1, 1, 1, 0.12), 1, 10))
	card.anchor_left = 0.5; card.anchor_right = 0.5; card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.margin_left = -W / 2; card.margin_right = W / 2; card.margin_top = -H / 2; card.margin_bottom = H / 2
	root.add_child(card)
	var title = _label("Replay Studio", 28, Color(1, 1, 1))
	title.rect_position = Vector2(24, 12)
	card.add_child(title)
	sub_lbl = _label("", 13, Color(1, 1, 1, 0.45))
	sub_lbl.rect_position = Vector2(26, 50)
	sub_lbl.rect_size = Vector2(760, 20)
	sub_lbl.clip_text = true
	card.add_child(sub_lbl)
	var top = HBoxContainer.new()
	top.add_constant_override("separation", 8)
	top.rect_position = Vector2(W - 24 - 520, 16)
	top.rect_size = Vector2(520, 36)
	top.alignment = BoxContainer.ALIGN_END
	card.add_child(top)
	btn_watch = _btn("WATCH", "_watch", [false], 100)
	top.add_child(btn_watch)
	btn_from = _btn("WATCH FROM -", "_watch", [true], 170)
	btn_from.disabled = true
	top.add_child(btn_from)
	top.add_child(_btn("CLIP", "_clip_menu", [], 80))
	var x = _btn("X", "close", [], 38)
	x.flat = true
	top.add_child(x)
	# left: numbers
	var left = VBoxContainer.new()
	left.rect_position = Vector2(24, 84)
	left.rect_size = Vector2(262, H - 104)
	card.add_child(left)
	stats_box = GridContainer.new()
	stats_box.columns = 2
	stats_box.add_constant_override("vseparation", 5)
	stats_box.add_constant_override("hseparation", 10)
	left.add_child(stats_box)
	status = _label("Reading the replay...", 13, Color(1, 1, 1, 0.6))
	status.autowrap = true
	status.rect_min_size.x = 262
	left.add_child(status)
	# middle: graphs, misses, compare
	graphs = Graphs.new()
	graphs.studio = self
	graphs.rect_position = Vector2(302, 84)
	graphs.rect_size = Vector2(560, 380)
	card.add_child(graphs)
	var ml = _label("MISSES  (click: pick the time, double click: watch from there)", 12, Color(1, 1, 1, 0.45))
	ml.rect_position = Vector2(302, 474)
	card.add_child(ml)
	miss_list = ItemList.new()
	miss_list.rect_position = Vector2(302, 494)
	miss_list.rect_size = Vector2(560, H - 494 - 64)
	miss_list.connect("item_selected", self, "_miss_pick")
	miss_list.connect("item_activated", self, "_miss_watch")
	card.add_child(miss_list)
	var cr = HBoxContainer.new()
	cr.add_constant_override("separation", 8)
	cr.rect_position = Vector2(302, H - 54)
	cr.rect_size = Vector2(560, 36)
	card.add_child(cr)
	cr.add_child(_label("COMPARE WITH", 12, Color(1, 1, 1, 0.45)))
	cmp = OptionButton.new()
	cmp.focus_mode = Control.FOCUS_NONE
	cmp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmp.connect("item_selected", self, "_cmp_picked")
	cr.add_child(cmp)
	cr.add_child(_btn("BEST OF THIS MAP", "_cmp_best", [], 160))
	# right: heatmap + aim
	heat = Heat.new()
	heat.studio = self
	heat.rect_position = Vector2(878, 84)
	heat.rect_size = Vector2(298, 298)
	card.add_child(heat)
	aim = Aim.new()
	aim.studio = self
	aim.rect_position = Vector2(878, 396)
	aim.rect_size = Vector2(298, H - 396 - 20)
	card.add_child(aim)
	load("res://mods/replay/Device.gd").touch_fit(card) # (finger-sized buttons on touch screens)
	UIAnim.play(card, Vector2(0, 26), Vector2.ZERO, 0.0, 1.0, 0.3)
	_fill_compare()
	_start([path], "a")

func _input(ev):
	if !(ev is InputEventKey) or !ev.pressed or ev.echo: return
	match ev.scancode:
		KEY_ESCAPE: close()
		KEY_N: _jump_miss(-1 if ev.shift else 1)
		KEY_ENTER, KEY_KP_ENTER: if pick_ms >= 0: _watch(true)
		_: return
	get_tree().set_input_as_handled()

func close():
	if closing: return
	closing = true
	cancel = true
	if thread and thread.is_active(): thread.wait_to_finish()
	var t = UIAnim.play(root, Vector2.ZERO, Vector2.ZERO, 1.0, 0.0, 0.18)
	t.connect("finished", self, "queue_free")

# ------------------------------------------------------------------ analysis (worker thread)
# the map from the file name (<song id>.<date>.sspre), its notes read here (Song isn't thread safe)
func _song_of(p:String):
	var base = p.get_file().get_basename()
	var dot = base.find_last(".")
	return Rhythia.registry_song.get_item(base.substr(0, dot) if dot > 0 else base)

func _start(paths:Array, which:String):
	if thread and thread.is_active(): return
	var sg = _song_of(paths[0])
	if !sg:
		_set_status("This replay's map is not installed: nothing to compare it with.", true)
		return
	if which == "a": song = sg
	status.text = "Analysing %d replay(s)..." % paths.size() if paths.size() > 1 else "Analysing..."
	cancel = false
	thread = Thread.new()
	thread.start(self, "_work", [paths, which, sg.read_notes()])

func _work(a:Array):
	var best = null
	var count = 0
	for p in a[0]:
		if cancel: break
		var rp = S.parse(p)
		if !rp.ok:
			if a[0].size() == 1:
				call_deferred("_done", {"error": rp.error}, a[1])
				return
			continue
		var opts = S.opts_of(rp)
		var st = S.analyse(rp, a[2], opts)
		count += 1
		if best == null or st.score > best.st.score: best = {"path": p, "rp": rp, "st": st, "opts": opts, "of": 0}
	if best: best.of = count
	call_deferred("_done", best if best else {"error": "no readable replay"}, a[1])

func _done(r:Dictionary, which:String):
	if thread and thread.is_active(): thread.wait_to_finish()
	if closing: return
	if r.has("error"):
		_set_status("Can't analyse this replay: %s." % r.error, true)
		return
	r.label = _date_of(r.path)
	if which == "a":
		A = r
		_fill_stats()
		_fill_misses()
		var st = A.st
		sub_lbl.text = "%s   -   %s   -   cursor recorded every %d ms" % [song.name if song else A.rp.song_id, A.label, int(round(st.sample_ms))]
		_set_status("", false)
	else:
		B = r
		_fill_stats()
		_set_status("Comparing with %s%s." % [B.label, (" (the best score of %d other replay%s)" % [B.of, "" if B.of == 1 else "s"]) if which == "best" else ""], false)
	for c in [graphs, heat, aim]: c.update()

func _set_status(t:String, bad:bool):
	status.text = t
	status.add_color_override("font_color", COL_MISS if bad else Color(1, 1, 1, 0.6))

# ------------------------------------------------------------------ numbers
func _fill_stats():
	for c in stats_box.get_children(): c.queue_free()
	stats_box.columns = 3 if B else 2
	_row("", "THIS", "OTHER" if B else "")
	for r in _rows():
		_row(r[0], r[1], r[2] if B else "")

func _rows() -> Array:
	var out = []
	var a = A.st
	var b = B.st if B else null
	out.append(["Score", _num(a.score), _num(b.score) if b else ""])
	out.append(["Accuracy", "%.2f %%" % (a.accuracy * 100.0), ("%.2f %%" % (b.accuracy * 100.0)) if b else ""])
	out.append(["Hits / misses", "%d / %d" % [a.hits, a.misses], ("%d / %d" % [b.hits, b.misses]) if b else ""])
	out.append(["Max combo", str(a.max_combo), str(b.max_combo) if b else ""])
	out.append(["Ended", _ending(a), _ending(b) if b else ""])
	out.append(["Pauses", str(a.pauses.size()), str(b.pauses.size()) if b else ""])
	out.append(["Settings", _settings(A.opts), _settings(B.opts) if b else ""])
	out.append(["Aim (mean)", _aim_words(a.aim_mean), _aim_words(b.aim_mean) if b else ""])
	out.append(["Aim error", "%.2f cells" % a.aim_err, ("%.2f cells" % b.aim_err) if b else ""])
	out.append(["Hit delay", _delay(a), _delay(b) if b else ""])
	out.append(["Cursor", "%.0f cells, %.1f/s" % [a.travelled, a.avg_speed], ("%.0f cells, %.1f/s" % [b.travelled, b.avg_speed]) if b else ""])
	return out

func _row(k:String, a:String, b:String):
	var kl = _label(k, 13, Color(1, 1, 1, 0.5))
	kl.rect_min_size.x = 74
	stats_box.add_child(kl)
	var sz = (14 if !B else 13) if k != "" else 11
	var al = _label(a, sz, Color(1, 1, 1) if k != "" else Color(1, 1, 1, 0.4))
	al.autowrap = true
	al.rect_min_size.x = 178 if !B else 88
	stats_box.add_child(al)
	if B:
		var bl = _label(b, sz, COL_B if k != "" else Color(1, 1, 1, 0.4))
		bl.autowrap = true
		bl.rect_min_size.x = 88
		stats_box.add_child(bl)

func _ending(st:Dictionary) -> String:
	if st.gave_up: return "gave up %s" % _mmss(st.song_to)
	if st.judged >= st.notes: return "full run"
	return "failed %s, %d/%d" % [_mmss(st.song_to), st.judged, st.notes]

func _settings(o:Dictionary) -> String:
	var t = "%.2fx, box %.2f, %d ms" % [o.speed, o.hitbox, int(o.hit_window)]
	for m in [["mirror_x", "mirror X"], ["mirror_y", "mirror Y"], ["hardrock", "hard rock"]]:
		if o.get(m[0], false): t += ", " + m[1]
	return t

static func _aim_words(v:Vector2) -> String:
	var parts = []
	if abs(v.x) >= 0.01: parts.append("%.2f %s" % [abs(v.x), "right" if v.x > 0 else "left"])
	if abs(v.y) >= 0.01: parts.append("%.2f %s" % [abs(v.y), "low" if v.y > 0 else "high"])
	return "centred" if parts.empty() else PoolStringArray(parts).join(" ")

func _delay(st:Dictionary) -> String:
	if st.delay_median < 0: return "-"
	return "%d ms median (%d/%d)" % [int(st.delay_median), st.delay_known, st.hits]

static func _num(v:int) -> String:
	var s = str(abs(v))
	var out = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out

static func _mmss(ms:float) -> String:
	var t = max(ms, 0.0) / 1000.0
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]

func _date_of(p:String) -> String:
	var base = p.get_file().get_basename()
	var d = base.substr(base.find_last(".") + 1).replace("_", "-").split("-")
	if d.size() == 6: return "%s-%02d-%02d %02d:%02d" % [d[0], int(d[1]), int(d[2]), int(d[3]), int(d[4])]
	return base

# ------------------------------------------------------------------ misses, picking, watching
func _fill_misses():
	miss_list.clear()
	miss_ms = []
	for pn in A.st.per_note:
		if pn[1]: continue
		miss_ms.append(pn[0])
		miss_list.add_item("%s     note at (%s, %s)" % [_mmss(pn[0]), _g(pn[6]), _g(pn[7])])
	if miss_ms.empty(): miss_list.add_item("no misses")

static func _g(v:float) -> String:
	return str(int(v)) if abs(v - round(v)) < 0.001 else "%.2f" % v

func _miss_pick(i:int):
	if i < miss_ms.size(): pick(miss_ms[i])

func _miss_watch(i:int):
	if i < miss_ms.size():
		pick(miss_ms[i])
		_watch(true)

func _jump_miss(dir:int):
	if miss_ms.empty(): return
	var k = -1
	if dir > 0:
		for i in miss_ms.size():
			if miss_ms[i] > pick_ms + 0.5:
				k = i
				break
		if k < 0: k = 0
	else:
		for i in range(miss_ms.size() - 1, -1, -1):
			if miss_ms[i] < pick_ms - 0.5:
				k = i
				break
		if k < 0: k = miss_ms.size() - 1
	miss_list.select(k)
	miss_list.ensure_current_is_visible()
	pick(miss_ms[k])

func pick(ms:float):
	if !A: return
	pick_ms = clamp(ms, 0.0, A.st.song_to)
	btn_from.disabled = false
	btn_from.text = "WATCH FROM %s" % _mmss(max(pick_ms - 2000.0, 0.0))
	for c in [graphs, heat]: c.update()

# into the replay viewer (ReplayViewer.gd seeks on its first frames when rr_replay_seek is set)
func _watch(from_pick:bool):
	if !A or closing: return
	if !song:
		_set_status("This replay's map is not installed.", true)
		return
	if from_pick and pick_ms >= 0:
		var from = max(pick_ms - 2000.0, A.st.song_from + 1.0) # (2 s of lead-up)
		var r = S.rms_of(A.st, from)
		if r >= 0: Engine.set_meta("rr_replay_seek", [r, "FROM " + _mmss(max(from, 0.0))])
	closing = true
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = A.path
	var menu = get_tree().root.get_node_or_null("Menu")
	if menu and "black_fade_target" in menu: menu.black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")

# ------------------------------------------------------------------ clip export
const CLIP_LENGTHS = [3, 5, 8, 10]
var clip_pop:PopupPanel
var clip_len:OptionButton
var clip_mp4:CheckBox
var clip_info:Label

func _clip_menu():
	if !A: return
	if !clip_pop:
		clip_pop = PopupPanel.new()
		var v = VBoxContainer.new()
		v.add_constant_override("separation", 8)
		clip_pop.add_child(v)
		clip_info = _label("", 14, Color(1, 1, 1))
		v.add_child(clip_info)
		var h = HBoxContainer.new()
		h.add_child(_label("LENGTH", 12, Color(1, 1, 1, 0.5)))
		clip_len = OptionButton.new()
		for s in CLIP_LENGTHS: clip_len.add_item("%d s" % s)
		clip_len.select(1)
		clip_len.connect("item_selected", self, "_clip_refresh")
		h.add_child(clip_len)
		v.add_child(h)
		clip_mp4 = CheckBox.new()
		var ff = load("res://mods/replay/ClipExport.gd").has_ffmpeg()
		clip_mp4.text = "MP4 too (ffmpeg, with the song)" if ff else "MP4: needs ffmpeg installed (not found)"
		clip_mp4.disabled = !ff
		clip_mp4.pressed = ff
		v.add_child(clip_mp4)
		v.add_child(_label("The replay plays the clip at half speed while it records,", 12, Color(1, 1, 1, 0.5)))
		v.add_child(_label("then saves to the clips folder. Keep the window visible.", 12, Color(1, 1, 1, 0.5)))
		v.add_child(_btn("RECORD", "_record_clip", [], 160))
		root.add_child(clip_pop)
	_clip_refresh(0)
	clip_pop.popup_centered(Vector2(440, 210))

func _clip_start() -> float:
	if pick_ms >= 0: return max(pick_ms - 1000.0, 0.0)
	var first = A.st.rows[0][0] if A.st.rows.size() > 0 else 0.0
	return max(first - 1000.0, 0.0)

func _clip_refresh(_i):
	var s = _clip_start()
	clip_info.text = "Clip %s - %s%s" % [_mmss(s), _mmss(s + CLIP_LENGTHS[clip_len.selected] * 1000.0), "  (from the picked time)" if pick_ms >= 0 else ""]

# the clip as replay times (a song ms takes 1 / speed replay ms) + what ClipExport needs
func clip_request(start_ms:float, length_ms:float, mp4:bool) -> Dictionary:
	var from_rms = S.rms_of(A.st, max(start_ms, A.st.song_from + 1.0))
	if from_rms < 0: return {}
	var paused = false
	for pm in A.st.pauses:
		if pm >= start_ms - 1000.0 and pm <= start_ms + length_ms: paused = true
	var safe = ""
	for ch in ("%s_%s" % [song.name if song else A.rp.song_id, A.label]):
		safe += ch if (ch.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789-_") else "_"
	return {"from_rms": from_rms, "to_rms": from_rms + length_ms / max(A.opts.speed, 0.01),
		"name": "%s_%s" % [safe.left(60), _mmss(start_ms).replace(":", "m").replace(".", "s")], "mp4": mp4,
		"audio_from_ms": start_ms + Rhythia.music_offset, "audio_ok": !paused and abs(A.opts.speed - 1.0) < 0.001, "song": song}

func _record_clip():
	clip_pop.hide()
	var req = clip_request(_clip_start(), CLIP_LENGTHS[clip_len.selected] * 1000.0, clip_mp4.pressed and !clip_mp4.disabled)
	if req.empty():
		_set_status("That part of the song isn't in the replay.", true)
		return
	Engine.set_meta("rr_clip", req)
	_watch(false)

# ------------------------------------------------------------------ compare
func _fill_compare():
	cmp.clear()
	cmp_paths = [""]
	cmp.add_item("nothing")
	var base = path.get_file().get_basename()
	var sid = base.substr(0, base.find_last("."))
	var dir = Directory.new()
	var folder = path.get_base_dir()
	var found = []
	if dir.open(folder) == OK:
		dir.list_dir_begin(true, true)
		var f = dir.get_next()
		while f != "":
			if f.get_extension() == "sspre" and f != path.get_file() and f.get_basename().substr(0, f.get_basename().find_last(".")) == sid:
				found.append(folder + "/" + f)
			f = dir.get_next()
		dir.list_dir_end()
	found.sort()
	found.invert() # (dates in the name: newest first)
	for p in found:
		cmp_paths.append(p)
		cmp.add_item(_date_of(p))

func _cmp_picked(i:int):
	if i <= 0:
		B = null
		_fill_stats()
		_set_status("", false)
		for c in [graphs, heat, aim]: c.update()
		return
	_start([cmp_paths[i]], "b")

func _cmp_best():
	if cmp_paths.size() <= 1:
		_set_status("No other replay of this map to compare with.", false)
		return
	_start(cmp_paths.slice(1, cmp_paths.size() - 1), "best")

# ------------------------------------------------------------------ drawing
func t_range() -> Vector2:
	var t1 = A.st.song_to if A else 1000.0
	if B: t1 = max(t1, B.st.song_to)
	return Vector2(0.0, max(t1, 1000.0))

func _draw_graphs(c:Control, hover_x:float):
	var sz = c.rect_size
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.03))
	if !A:
		return
	var f = _font(12)
	var tr = t_range()
	var axis = 18.0
	var lh = (sz.y - axis) / 3.0
	var lanes = ["ACCURACY  (thick: overall, thin: last 25 notes)", "COMBO", "CURSOR SPEED  (cells / s)"]
	for i in 3:
		var r = Rect2(0, i * lh, sz.x, lh - 6)
		c.draw_rect(r, Color(1, 1, 1, 0.035))
		c.draw_string(f, Vector2(6, i * lh + 14), lanes[i], Color(1, 1, 1, 0.4))
	# misses / pauses / pick
	for pn in A.st.per_note:
		if !pn[1]:
			var x = _tx(pn[0], tr, sz.x)
			c.draw_line(Vector2(x, 0), Vector2(x, sz.y - axis), Color(COL_MISS.r, COL_MISS.g, COL_MISS.b, 0.45), 1.0)
	if B:
		for pn in B.st.per_note:
			if !pn[1]:
				var xb = _tx(pn[0], tr, sz.x)
				c.draw_line(Vector2(xb, sz.y - axis - 8), Vector2(xb, sz.y - axis), COL_B, 2.0)
	for pm in A.st.pauses:
		var xp = _tx(pm, tr, sz.x)
		c.draw_line(Vector2(xp, 0), Vector2(xp, sz.y - axis), Color(1, 1, 1, 0.5), 2.0)
	# curves (B under A)
	var lo = 1.0
	var mc = 1
	var mspd = 1.0
	for X in [A, B]:
		if !X: continue
		for r in X.st.rows:
			lo = min(lo, r[5])
			mc = max(mc, r[2])
		mspd = max(mspd, _p95(X.st.speed_curve))
	lo = clamp(floor(lo * 10.0) / 10.0, 0.0, 0.9)
	for X in [B, A]:
		if !X: continue
		var col = ACCENT if X == A else COL_B
		var acc = PoolVector2Array()
		var loc = PoolVector2Array()
		var cmb = PoolVector2Array()
		var prev_c = 0
		for r in X.st.rows:
			var x = _tx(r[0], tr, sz.x)
			acc.append(Vector2(x, _ty(r[4], lo, 1.0, 0, lh)))
			loc.append(Vector2(x, _ty(r[5], lo, 1.0, 0, lh)))
			cmb.append(Vector2(x, _ty(prev_c, 0, mc, lh, lh)))
			cmb.append(Vector2(x, _ty(r[2], 0, mc, lh, lh)))
			prev_c = r[2]
		if loc.size() > 1: c.draw_polyline(loc, Color(col.r, col.g, col.b, 0.35), 1.0)
		if acc.size() > 1: c.draw_polyline(acc, col, 2.0)
		if cmb.size() > 1: c.draw_polyline(cmb, col, 1.5)
		var sp = PoolVector2Array()
		var bin = X.st.speed_bin
		for k in X.st.speed_curve.size():
			var t = X.st.song_from + (k + 0.5) * bin
			if t < tr.x or t > tr.y: continue
			sp.append(Vector2(_tx(t, tr, sz.x), _ty(min(X.st.speed_curve[k], mspd), 0, mspd, 2 * lh, lh)))
		if sp.size() > 1: c.draw_polyline(sp, col, 1.5)
	c.draw_string(f, Vector2(sz.x - 60, 14), "%d %%" % int(round(lo * 100)) + " - 100", Color(1, 1, 1, 0.3))
	c.draw_string(f, Vector2(sz.x - 60, lh + 14), "max %d" % mc, Color(1, 1, 1, 0.3))
	c.draw_string(f, Vector2(sz.x - 60, 2 * lh + 14), "%.0f / s" % mspd, Color(1, 1, 1, 0.3))
	# time axis
	var step = 5000.0 if tr.y - tr.x < 90000 else 15000.0
	var t = 0.0
	while t <= tr.y:
		var xt = _tx(t, tr, sz.x)
		c.draw_line(Vector2(xt, sz.y - axis), Vector2(xt, sz.y - axis + 4), Color(1, 1, 1, 0.3), 1.0)
		c.draw_string(f, Vector2(xt + 2, sz.y - 2), _mmss(t).split(".")[0], Color(1, 1, 1, 0.35))
		t += step
	if pick_ms >= 0:
		var xk = _tx(pick_ms, tr, sz.x)
		c.draw_line(Vector2(xk, 0), Vector2(xk, sz.y - axis), COL_PICK, 2.0)
	if hover_x >= 0:
		var th = tr.x + hover_x / sz.x * (tr.y - tr.x)
		c.draw_line(Vector2(hover_x, 0), Vector2(hover_x, sz.y - axis), Color(1, 1, 1, 0.35), 1.0)
		var txt = _readout(A, th, "")
		if B: txt += "     " + _readout(B, th, "other ")
		var tw = f.get_string_size(txt).x
		var bx = clamp(hover_x + 8, 0, sz.x - tw - 8)
		c.draw_rect(Rect2(bx - 4, sz.y - axis - 22, tw + 8, 18), Color(0, 0, 0, 0.8))
		c.draw_string(f, Vector2(bx, sz.y - axis - 8), txt, Color(1, 1, 1))

func _readout(X, t:float, pre:String) -> String:
	var rows = X.st.rows
	var r = null
	for row in rows:
		if row[0] > t: break
		r = row
	var k = int(clamp((t - X.st.song_from) / X.st.speed_bin, 0, max(0, X.st.speed_curve.size() - 1)))
	var spd = X.st.speed_curve[k] if X.st.speed_curve.size() > 0 else 0.0
	if r == null: return "%s%s  speed %.1f" % [pre, _mmss(t), spd]
	return "%s%s  acc %.1f %% (last 25: %.0f %%)  combo %d  speed %.1f" % [pre, _mmss(t), r[4] * 100.0, r[5] * 100.0, r[2], spd]

static func _p95(a:PoolRealArray) -> float:
	var s = Array(a)
	s.sort()
	return s[int(s.size() * 0.95)] if s.size() > 0 else 1.0

static func _tx(t:float, tr:Vector2, w:float) -> float:
	return (t - tr.x) / max(tr.y - tr.x, 1.0) * w

static func _ty(v:float, lo:float, hi:float, top:float, h:float) -> float:
	return top + (h - 8) - clamp((v - lo) / max(hi - lo, 0.0001), 0.0, 1.0) * (h - 26)

func _draw_heat(c:Control):
	var sz = c.rect_size
	var f = _font(12)
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.03))
	c.draw_string(f, Vector2(6, 14), "WHERE THE CURSOR WAS  (red: misses)", Color(1, 1, 1, 0.4))
	if !A: return
	var area = Rect2(10, 22, sz.x - 20, sz.y - 32)
	var n = A.st.heat_n
	var mx = 0.0
	for v in A.st.heat: mx = max(mx, v)
	var cw = area.size.x / n
	for yy in n:
		for xx in n:
			var v = A.st.heat[yy * n + xx]
			if v <= 0 or mx <= 0: continue
			c.draw_rect(Rect2(area.position + Vector2(xx * cw, yy * cw), Vector2(cw + 0.5, cw + 0.5)), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.12 + 0.85 * sqrt(v / mx)))
	for k in 4: # (the 3 x 3 note cells)
		var p = area.position.x + (k * 1.0) / 3.0 * area.size.x
		c.draw_line(Vector2(p, area.position.y), Vector2(p, area.end.y), Color(1, 1, 1, 0.15), 1.0)
		var q = area.position.y + (k * 1.0) / 3.0 * area.size.y
		c.draw_line(Vector2(area.position.x, q), Vector2(area.end.x, q), Color(1, 1, 1, 0.15), 1.0)
	for pn in A.st.per_note:
		if pn[1]: continue
		var mp = area.position + Vector2((pn[6] + 0.5) / 3.0 * area.size.x, (pn[7] + 0.5) / 3.0 * area.size.y)
		c.draw_line(mp - Vector2(4, 4), mp + Vector2(4, 4), COL_MISS, 2.0)
		c.draw_line(mp - Vector2(4, -4), mp + Vector2(4, -4), COL_MISS, 2.0)

func _draw_aim(c:Control):
	var sz = c.rect_size
	var f = _font(12)
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.03))
	c.draw_string(f, Vector2(6, 14), "WHERE HITS LANDED ON THE NOTE", Color(1, 1, 1, 0.4))
	if !A: return
	var side = min(sz.x - 20, sz.y - 44)
	var ctr = Vector2(sz.x / 2.0, 22 + side / 2.0)
	var e = A.st.hitbox_half * 1.15
	var sc = side / 2.0 / e
	var hb = A.st.hitbox_half * sc
	c.draw_rect(Rect2(ctr - Vector2(hb, hb), Vector2(hb, hb) * 2), Color(1, 1, 1, 0.25), false, 1.0)
	c.draw_line(ctr - Vector2(hb, 0), ctr + Vector2(hb, 0), Color(1, 1, 1, 0.1), 1.0)
	c.draw_line(ctr - Vector2(0, hb), ctr + Vector2(0, hb), Color(1, 1, 1, 0.1), 1.0)
	for X in [B, A]:
		if !X: continue
		var col = ACCENT if X == A else COL_B
		for pn in X.st.per_note:
			if !pn[1]: continue
			var p = ctr + Vector2(clamp(pn[2], -e, e), clamp(pn[3], -e, e)) * sc
			c.draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), Color(col.r, col.g, col.b, 0.45))
		var m = ctr + X.st.aim_mean * sc
		c.draw_line(m - Vector2(7, 0), m + Vector2(7, 0), col, 2.0)
		c.draw_line(m - Vector2(0, 7), m + Vector2(0, 7), col, 2.0)
	c.draw_string(f, Vector2(8, sz.y - 6), "mean: %s   (box = hitbox)" % _aim_words(A.st.aim_mean), Color(1, 1, 1, 0.55))

# ------------------------------------------------------------------ building blocks
func _font(size:int):
	if fonts.has(size): return fonts[size]
	var base = root.get_font("font", "Label")
	var f = base
	if base is DynamicFont:
		f = base.duplicate()
		f.size = size
	fonts[size] = f
	return f

func _label(text:String, size:int, col:Color) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", _font(size))
	l.add_color_override("font_color", col)
	return l

func _btn(text:String, method:String, args:Array = [], w:float = 0) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(w, 36)
	b.connect("pressed", self, method, args)
	return b

class Graphs extends Control:
	var studio
	var hover_x:float = -1.0
	func _gui_input(ev):
		if ev is InputEventMouseMotion:
			hover_x = ev.position.x
			update()
		elif (ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
			var tr = studio.t_range()
			studio.pick(tr.x + ev.position.x / rect_size.x * (tr.y - tr.x))
	func _notification(what):
		if what == NOTIFICATION_MOUSE_EXIT:
			hover_x = -1.0
			update()
	func _draw():
		studio._draw_graphs(self, hover_x)

class Heat extends Control:
	var studio
	func _draw():
		studio._draw_heat(self)

class Aim extends Control:
	var studio
	func _draw():
		studio._draw_aim(self)
