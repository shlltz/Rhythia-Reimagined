extends Control
# Replay analyzer (personal build; the idea of Steam Rhythia's replay toolbox, written from its look):
# a Toolbox panel in the replay viewer (bottom left) and an overlay drawn at the grid.
#   Cursor Path   - where the recorded cursor went over the last Path Window seconds (fading with
#                   age; yellow where it sat inside a note's hitbox while that note's hit window was open)
#   Cursor        - a ring + cross at the replay's exact recorded position
#   Note Hitbox   - the hitboxes of the notes around their time
#   Frame Marker  - a dot at every recorded cursor sample (the game records 1 / rec_interval s)
#   Game Cursor   - the game's own cursor on / off
#   Delta / Avg   - how long after its time the last hit note was reached (first sample inside the
#                   hitbox: ReplayStats' "delay") and the average so far; histogram over the hit window
# The analysis (ReplayStats.parse + analyse) runs once on a worker thread. Added by ReplayViewer.gd.
# Settings in reimagined.json: ra_path, ra_cursor, ra_hitbox, ra_frames, ra_game_cursor, ra_window.

const S = preload("res://mods/replay/ReplayStats.gd")
const Look = preload("res://mods/replay/Look.gd")
const W = 250.0
const H = 440.0
const ROW = 38.0
const ROWS = [["ra_path", "Cursor Path", true], ["ra_cursor", "Cursor", true], ["ra_hitbox", "Note Hitbox", false],
	["ra_frames", "Frame Marker", true], ["ra_game_cursor", "Game Cursor", true]]
const BINS = 16
const HIT_COL = Color(1.0, 0.82, 0.2)

var spawn                         # NoteManager
var viewer                        # ReplayViewer
var st = null                     # ReplayStats.analyse result (null until the worker is done)
var rp = null                     # ReplayStats.parse result
var hit_w:float = 55.0
var hbs:float = 0.57
var thread:Thread = null
var on:Dictionary = {}
var window:float = 0.6
var f_title:Font
var f_row:Font
var f_small:Font
var geo:ImmediateGeometry
var dragging_slider:bool = false
var state_txt:String = "analysing..."
# running stats up to the current time
var last_delta:float = -1.0
var avg:float = -1.0
var hist:Array = []
var stats_at:int = -1

func _R():
	return load("res://mods/replay/Reimagined.gd")

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	anchor_top = 1
	anchor_bottom = 1
	margin_left = 16
	margin_right = 16 + W
	margin_top = -104 - 16 - H
	margin_bottom = -104 - 16
	var R = _R()
	for r in ROWS:
		var v = R.val(r[0])
		on[r[0]] = r[2] if v == null else bool(v)
	var wv = R.val("ra_window")
	window = 0.6 if wv == null else clamp(float(wv), 0.1, 2.0)
	if ResourceLoader.exists("res://uitheme.tres"): theme = load("res://uitheme.tres") # (the game's font)
	f_title = _font(15)
	f_row = _font(14)
	f_small = _font(11)
	hist.resize(BINS)
	geo = ImmediateGeometry.new()
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.vertex_color_use_as_albedo = true
	m.flags_transparent = true
	m.flags_no_depth_test = true
	m.render_priority = 10
	geo.material_override = m
	geo.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	spawn.add_child(geo)
	_apply_game_cursor()
	var path = str(Rhythia.replay_path)
	if path == "" or !File.new().file_exists(path):
		state_txt = "no replay file (autoplay)"
		return
	var notes = Rhythia.selected_song.read_notes() if Rhythia.selected_song else []
	thread = Thread.new()
	if thread.start(self, "_work", [path, notes]) != OK:
		thread = null
		state_txt = "analysis failed to start"

func _font(size:int):
	var base = get_font("font", "Label")
	if base is DynamicFont:
		var f = base.duplicate()
		f.size = size
		return f
	return base

func _work(a):
	var p = S.parse(a[0])
	if !p.ok: return [p, null, {}]
	var opts = S.opts_of(p)
	return [p, S.analyse(p, a[1], opts), opts]

func _exit_tree():
	if thread: thread.wait_to_finish()
	if is_instance_valid(geo): geo.queue_free()

func _set(k:String, v):
	on[k] = v
	_R().set_val(k, v)
	if k == "ra_game_cursor": _apply_game_cursor()
	update()

func _apply_game_cursor():
	var c = spawn.get_node_or_null("Cursor") if spawn else null
	if c: c.visible = on.get("ra_game_cursor", true)

# ------------------------------------------------------------------ per frame
func _process(_delta):
	if thread and !thread.is_alive():
		var r = thread.wait_to_finish()
		thread = null
		if r is Array and r[1] is Dictionary:
			rp = r[0]
			st = r[1]
			hit_w = float(r[2].get("hit_window", 55.0))
			hbs = float(r[2].get("hitbox", 1.14)) / 2.0
			if hbs == 0.57: hbs = 0.56875
			state_txt = ""
		else:
			state_txt = "can't read this replay" + (": " + r[0].error if r is Array and r[0] is Dictionary and r[0].has("error") else "")
	_stats()
	_draw_overlay()
	update()

# Delta / Avg / histogram over the notes judged up to the current song time
func _stats():
	if st == null: return
	var now = spawn.ms
	var pn = st.per_note
	var n = 0
	while n < pn.size() and pn[n][0] <= now: n += 1
	if n == stats_at: return
	stats_at = n
	for i in BINS: hist[i] = 0
	var sum = 0.0
	var cnt = 0
	last_delta = -1.0
	for i in n:
		var d = pn[i][4]
		if !pn[i][1] or d < 0: continue
		sum += d
		cnt += 1
		last_delta = d
		hist[int(clamp(d / max(hit_w, 1.0) * BINS, 0, BINS - 1))] += 1
	avg = sum / cnt if cnt > 0 else -1.0

# the 3D overlay at the grid: path, frame markers, cursor ring, hitboxes (rebuilt every frame: a few
# hundred vertices at most)
func _draw_overlay():
	geo.clear()
	var vis = viewer.ui_state == 0
	geo.visible = vis
	if !vis or rp == null: return
	var ct = rp.cur_t
	var cx = rp.cur_x
	var cy = rp.cur_y
	var n = ct.size()
	if n == 0: return
	var now = spawn.rms
	var z = 0.004
	var k1 = S._first_at(ct, now)           # first sample after now
	var k0 = S._first_at(ct, now - window * 1000.0)
	var cur = S._cursor_at(ct, cx, cy, now)
	# notes around now: the ones whose window the path passes through (for the yellow parts)
	var due = []
	if spawn.notes_loaded:
		for nt in spawn.notes:
			var t = nt[1]
			if t > spawn.ms + 400: break
			if t >= spawn.ms - window * 1000.0 * spawn.speed_multi - hit_w: due.append(nt)
	if on.ra_hitbox:
		geo.begin(Mesh.PRIMITIVE_LINES)
		for nt in due:
			var age = abs(nt[1] - spawn.ms)
			var a = clamp(1.0 - age / 400.0, 0.15, 1.0)
			var c = Color(1, 1, 1, 0.75 * a)
			var p:Vector2 = nt[0]
			var q = [Vector3(p.x - hbs, p.y - hbs, z), Vector3(p.x + hbs, p.y - hbs, z), Vector3(p.x + hbs, p.y + hbs, z), Vector3(p.x - hbs, p.y + hbs, z)]
			for i in 4:
				geo.set_color(c); geo.add_vertex(q[i])
				geo.set_color(c); geo.add_vertex(q[(i + 1) % 4])
		geo.end()
	if on.ra_path and k1 > k0:
		geo.begin(Mesh.PRIMITIVE_LINES)
		var prev = Vector3(cx[max(k0 - 1, 0)], -cy[max(k0 - 1, 0)], z)
		var prev_t = ct[max(k0 - 1, 0)]
		for k in range(k0, min(k1, n)):
			var p = Vector3(cx[k], -cy[k], z)
			var a = clamp(1.0 - (now - ct[k]) / (window * 1000.0), 0.0, 1.0)
			var col = HIT_COL if _in_due(Vector2(p.x, p.y), S._sms(st.sms_at, ct[k]) if st else -1e9, due) else Color(1, 1, 1)
			col.a = 0.25 + 0.65 * a
			geo.set_color(col); geo.add_vertex(prev)
			geo.set_color(col); geo.add_vertex(p)
			prev = p
			prev_t = ct[k]
		var pc = Vector3(cur.x, -cur.y, z) # (last sample -> where the cursor is now)
		geo.set_color(Color(1, 1, 1, 0.9)); geo.add_vertex(prev)
		geo.set_color(Color(1, 1, 1, 0.9)); geo.add_vertex(pc)
		geo.end()
	if on.ra_frames and k1 > k0:
		geo.begin(Mesh.PRIMITIVE_TRIANGLES)
		var r = 0.04
		for k in range(k0, min(k1, n)):
			var p = Vector3(cx[k], -cy[k], z)
			var a = clamp(1.0 - (now - ct[k]) / (window * 1000.0), 0.0, 1.0)
			var col = HIT_COL if _in_due(Vector2(p.x, p.y), S._sms(st.sms_at, ct[k]) if st else -1e9, due) else Color(1, 1, 1)
			col.a = 0.35 + 0.65 * a
			_quad(p, r, col)
		geo.end()
	if on.ra_cursor:
		var pc = Vector3(cur.x, -cur.y, z)
		geo.begin(Mesh.PRIMITIVE_LINES)
		var rr = 0.13
		var seg = 28
		for i in seg:
			var a0 = TAU * i / seg
			var a1 = TAU * (i + 1) / seg
			geo.set_color(Color(1, 1, 1, 0.95)); geo.add_vertex(pc + Vector3(cos(a0), sin(a0), 0) * rr)
			geo.set_color(Color(1, 1, 1, 0.95)); geo.add_vertex(pc + Vector3(cos(a1), sin(a1), 0) * rr)
		for d in [Vector3(1, 0, 0), Vector3(0, 1, 0)]:
			geo.set_color(Color(1, 1, 1)); geo.add_vertex(pc - d * 0.06)
			geo.set_color(Color(1, 1, 1)); geo.add_vertex(pc + d * 0.06)
		geo.end()

# a sample (song time sms) inside the hitbox of a note whose hit window is open then = a hit frame
func _in_due(p:Vector2, sms:float, due:Array) -> bool:
	for nt in due:
		if sms < nt[1] or sms > nt[1] + hit_w: continue
		var q:Vector2 = nt[0]
		if abs(p.x - q.x) <= hbs and abs(p.y - q.y) <= hbs: return true
	return false

func _quad(p:Vector3, r:float, col:Color):
	var v = [p + Vector3(-r, -r, 0), p + Vector3(r, -r, 0), p + Vector3(r, r, 0), p + Vector3(-r, r, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		geo.set_color(col)
		geo.add_vertex(v[i])

# ------------------------------------------------------------------ panel
func _row_rect(i:int) -> Rect2:
	return Rect2(Vector2(0, 40 + i * ROW), Vector2(W, ROW))

func _slider_rect() -> Rect2:
	return Rect2(Vector2(16, 40 + ROWS.size() * ROW + 30), Vector2(W - 32, 16))

func _gui_input(ev):
	if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
		if ev.pressed:
			if _slider_rect().grow(6).has_point(ev.position):
				dragging_slider = true
				_slide(ev.position.x)
			else:
				for i in ROWS.size():
					if _row_rect(i).has_point(ev.position): _set(ROWS[i][0], !on[ROWS[i][0]])
		elif dragging_slider:
			dragging_slider = false
			_R().set_val("ra_window", window)
		accept_event()
	elif ev is InputEventMouseMotion and dragging_slider:
		_slide(ev.position.x)
		accept_event()

func _slide(x:float):
	var r = _slider_rect()
	window = stepify(lerp(0.1, 2.0, clamp((x - r.position.x) / r.size.x, 0.0, 1.0)), 0.05)

func _draw():
	var r = Rect2(Vector2.ZERO, Vector2(W, H))
	draw_rect(r, Color(0.02, 0.02, 0.024, 0.82))
	draw_rect(r, Color(1, 1, 1, 0.16), false, 1.0)
	draw_rect(Rect2(0, 0, 3, H), Color(1, 1, 1, 0.85))
	draw_string(f_title, Vector2(16, 26), "// TOOLBOX", Color(1, 1, 1, 0.9))
	var m = get_local_mouse_position()
	for i in ROWS.size():
		var rr = _row_rect(i)
		if rr.has_point(m): draw_rect(rr, Color(1, 1, 1, 0.05))
		draw_string(f_row, Vector2(16, rr.position.y + 24), ROWS[i][1].to_upper(), Color(1, 1, 1, 0.85))
		var v = on[ROWS[i][0]]
		var sw = Rect2(Vector2(W - 16 - 44, rr.position.y + 10), Vector2(44, 18))
		draw_rect(sw, Color(1, 1, 1, 0.9) if v else Color(1, 1, 1, 0.06))
		draw_rect(sw, Color(1, 1, 1, 0.5), false, 1.0)
		var knob = Rect2(Vector2(sw.position.x + (26 if v else 3), sw.position.y + 3), Vector2(15, 12))
		draw_rect(knob, Color(0.03, 0.03, 0.035) if v else Color(1, 1, 1, 0.7))
	# path window slider
	var sy = 40 + ROWS.size() * ROW
	draw_string(f_row, Vector2(16, sy + 20), "PATH WINDOW", Color(1, 1, 1, 0.85))
	var wt = "%.2fs" % window
	draw_string(f_row, Vector2(W - 16 - f_row.get_string_size(wt).x, sy + 20), wt, Color(1, 1, 1, 0.6))
	var sr = _slider_rect()
	var k = (window - 0.1) / 1.9
	draw_rect(Rect2(sr.position.x, sr.position.y + 7, sr.size.x, 2), Color(1, 1, 1, 0.18))
	draw_rect(Rect2(sr.position.x, sr.position.y + 7, sr.size.x * k, 2), Color(1, 1, 1, 0.9))
	draw_rect(Rect2(sr.position.x + sr.size.x * k - 5, sr.position.y + 1, 10, 14), Color(1, 1, 1))
	# delta / avg + histogram
	var ty = sy + 74
	if state_txt != "":
		draw_string(f_small, Vector2(16, ty), state_txt.to_upper(), Color(1, 1, 1, 0.45))
		return
	draw_string(f_row, Vector2(16, ty), "DELTA  %s" % ("%d ms" % int(round(last_delta)) if last_delta >= 0 else "-"), Color(1, 1, 1, 0.85))
	draw_string(f_row, Vector2(16, ty + 22), "AVG  %s" % ("%.2f ms" % avg if avg >= 0 else "-"), Color(1, 1, 1, 0.85))
	var hr = Rect2(Vector2(16, ty + 34), Vector2(W - 32, H - (ty + 34) - 26))
	draw_rect(hr, Color(1, 1, 1, 0.03))
	draw_rect(hr, Color(1, 1, 1, 0.12), false, 1.0)
	var mx = 1
	for c in hist: mx = max(mx, c)
	var bw = hr.size.x / BINS
	var last_bin = int(clamp(last_delta / max(hit_w, 1.0) * BINS, 0, BINS - 1)) if last_delta >= 0 else -1
	for i in BINS:
		var h = (hr.size.y - 8) * float(hist[i]) / mx
		if hist[i] > 0: h = max(h, 2.0)
		var col = Color(1, 1, 1, 0.95) if i == last_bin else Color(1, 1, 1, 0.5)
		draw_rect(Rect2(hr.position.x + i * bw + 2, hr.end.y - 4 - h, bw - 4, h), col)
	for i in range(0, BINS + 1, 4):
		var t = str(int(round(hit_w * i / BINS)))
		var x = hr.position.x + i * bw - f_small.get_string_size(t).x / 2
		draw_string(f_small, Vector2(clamp(x, hr.position.x, hr.end.x - 14), hr.end.y + 16), t, Color(1, 1, 1, 0.45))
