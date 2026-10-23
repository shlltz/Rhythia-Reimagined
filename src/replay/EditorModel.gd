extends Reference
# Beatmap editor data model (no UI, no engine objects: unit-testable). A note is [x, y, ms] exactly as
# Song.notes holds it: x / y on the 3x3 grid (0..2, floats allowed), ms an integer (the .sspm stores
# the time as an int32). Rhythia maps carry no BPM / offset (the engine plays absolute times), so
# bpm / offset / snap / bookmarks are editor aids only and live in the editor's own session file.
#
# Edits go through run() as commands (add / del / mov lists) and are grouped into undo steps with
# begin() / end(); undo stores the commands, not copies of the map.

const MAX_MS = 36000000          # 10 h: far above any map, below int32 overflow worries
const GRID_MIN = -1.0            # positions the game can draw (the grid is 0..2, quantum maps go a bit outside)
const GRID_MAX = 3.0

var notes:Array = []             # sorted by ms, then y, then x
var keys:Dictionary = {}         # "x|y|ms" -> true, to refuse duplicates and look notes up
var meta:Dictionary = {"id": "", "name": "", "creator": "", "difficulty": -1, "audio": "", "audio_ext": ""}
var bpm:float = 120.0
var offset:int = 0               # ms of the first beat
var div:int = 4                  # snap subdivisions per beat
var bookmarks:Array = []         # ms
var points:Array = []            # timing points after the first one (bpm / offset): [[ms, bpm], ...] by time
var extra_markers:int = 0        # marker types in the source map that this editor cannot keep (see validate)
var dirty:bool = false
var rev:int = 0                  # +1 on every change: views redraw / cache against it
var undo_stack:Array = []        # [{name, ops}]
var redo_stack:Array = []
var _open:Dictionary = {}        # group being recorded
var _depth:int = 0
const UNDO_LIMIT = 500

# ------------------------------------------------------------------ timing (static: shared with tests)
static func beat_ms(beat:float, bpm_:float, off:int) -> int:
	return int(round(off + beat * 60000.0 / bpm_)) # from the index each time: no accumulated drift

static func ms_beat(ms:float, bpm_:float, off:int) -> float:
	return (ms - off) * bpm_ / 60000.0

# nearest grid time (div subdivisions per beat); a time before the first grid line stays on the grid
static func snap(ms:float, bpm_:float, off:int, div_:int) -> int:
	var k = round((ms - off) * bpm_ * div_ / 60000.0)
	return int(round(off + k * 60000.0 / (bpm_ * div_)))

static func step_ms(bpm_:float, div_:int) -> float:
	return 60000.0 / (bpm_ * div_)

# ------------------------------------------------------------------ timing sections (BPM changes)
# Section 0 is bpm / offset and reaches back before the offset; every timing point starts a section
# that runs to the next one. Each point restarts the beat grid and the 4-beat measures on its own
# time (as osu! and the Quantum Editor do), so a note snapped before a change stays where it was.
func sections() -> Array:
	var out = [[float(offset), bpm]]
	for p in points:
		if float(p[0]) > out[out.size() - 1][0]: out.append([float(p[0]), float(p[1])])
	return out

static func _sec(ss:Array, ms:float) -> int:
	var i = 0
	while i + 1 < ss.size() and ss[i + 1][0] <= ms + 0.0001: i += 1
	return i

func bpm_at(ms:float) -> float:
	var ss = sections()
	return ss[_sec(ss, ms)][1]

# grid step at a time (div subdivisions per beat of that section; div_ 0.25 = one measure)
func step_at(ms:float, div_:float = 0.0) -> float:
	return 60000.0 / (bpm_at(ms) * (div if div_ <= 0.0 else div_))

# nearest grid time (the next section's start counts as a grid line)
func snap_t(ms:float, div_:float = 0.0) -> int:
	var d = div if div_ <= 0.0 else div_
	var ss = sections()
	var i = _sec(ss, ms)
	var st = 60000.0 / (ss[i][1] * d)
	var t = ss[i][0] + round((ms - ss[i][0]) / st) * st
	if i + 1 < ss.size() and abs(ss[i + 1][0] - ms) < abs(t - ms): t = ss[i + 1][0]
	return int(round(t))

# the grid line strictly after (dir > 0) or before (dir < 0) a time
func grid_next(t:float, dir:int, div_:float = 0.0) -> float:
	var d = div if div_ <= 0.0 else div_
	var ss = sections()
	var i = _sec(ss, t)
	var s0 = ss[i][0]
	var st = 60000.0 / (ss[i][1] * d)
	if dir > 0:
		var c = s0 + (floor((t - s0) / st + 0.001) + 1) * st
		if i + 1 < ss.size() and c > ss[i + 1][0] - 0.5: c = ss[i + 1][0]
		return c
	if i > 0 and t <= s0 + 0.5: # (at a section start: the last line of the section before)
		i -= 1
		s0 = ss[i][0]
		st = 60000.0 / (ss[i][1] * d)
	return s0 + (ceil((t - s0) / st - 0.001) - 1) * st

# beats from the offset (sections add up; a section shorter than a whole beat adds its fraction)
func beat_at(ms:float) -> float:
	var ss = sections()
	var i = _sec(ss, ms)
	var b = 0.0
	for j in range(1, i + 1): b += (ss[j][0] - ss[j - 1][0]) * ss[j - 1][1] / 60000.0
	return b + (ms - ss[i][0]) * ss[i][1] / 60000.0

# grid lines in [t0, t1] for drawing: [[ms, kind], ...] kind 0 = measure, 1 = beat, 2 = division
func grid_lines(t0:float, t1:float, with_div:bool, beat_stride:int = 1, limit:int = 6000) -> Array:
	var out = []
	var ss = sections()
	for i in ss.size():
		var s0 = ss[i][0]
		var e = ss[i + 1][0] if i + 1 < ss.size() else 1e12
		var a = max(t0, s0) if i > 0 else t0
		var b = min(t1, e)
		if b < a: continue
		var per = 60000.0 / ss[i][1]
		var k = int(floor((a - s0) / per))
		k -= posmod(k, beat_stride)
		while out.size() < limit:
			var t = s0 + k * per
			if t > b or t >= e - 0.5: break
			if t >= a - 0.5: out.append([t, 0 if posmod(k, 4) == 0 else 1])
			if with_div and beat_stride == 1:
				for q in range(1, div):
					var tq = t + q * per / div
					if tq >= a and tq <= b and tq < e - 0.5: out.append([tq, 2])
			k += beat_stride
	return out

# add / move / remove timing points (refused before the offset or on top of another one)
func add_point(ms:int, bpm_:float) -> bool:
	if ms <= offset: return false
	for p in points:
		if abs(int(p[0]) - ms) <= 1: return false
	points.append([ms, clamp(bpm_, 20.0, 400.0)])
	points.sort_custom(self, "_cmp_point")
	rev += 1
	return true

func _cmp_point(a, b) -> bool:
	return a[0] < b[0]

# "1:02.345" / "62.345" -> ms, -1 if it does not parse
static func parse_time(s:String) -> int:
	s = s.strip_edges()
	if s == "": return -1
	var parts = s.split(":")
	var sec = 0.0
	for p in parts:
		if !p.is_valid_float(): return -1
		sec = sec * 60.0 + float(p)
	return int(round(sec * 1000.0))

static func fmt_time(ms:int) -> String:
	var neg = ms < 0
	ms = abs(ms)
	return "%s%d:%02d.%03d" % ["-" if neg else "", ms / 60000, (ms / 1000) % 60, ms % 1000]

# [average notes per second from the first to the last note, most notes inside any 1 s window];
# notes sorted by ms (two pointers: one pass)
static func nps(ns:Array) -> Array:
	if ns.size() < 2: return [0.0, float(ns.size())]
	var span = max(1.0, float(ns[-1][2] - ns[0][2]))
	var peak = 0
	var j = 0
	for i in ns.size():
		while ns[i][2] - ns[j][2] >= 1000: j += 1
		peak = max(peak, i - j + 1)
	return [ns.size() / (span / 1000.0), float(peak)]

# ------------------------------------------------------------------ text format (Sound Space "id,x|y|ms,..." with 2-x / 2-y like Song.export_text)
static func to_txt(id:String, ns:Array) -> String:
	var parts = PoolStringArray([id])
	for n in ns: parts.append("%s|%s|%d" % [_num(2.0 - n[0]), _num(2.0 - n[1]), int(n[2])])
	return parts.join(",")

static func _num(v:float) -> String:
	var s = "%.4f" % v
	if "." in s:
		s = s.rstrip("0").rstrip(".")
	return "0" if s == "-0" else s

# -> {notes, invalid}; same parse as Song.loadRawData
static func from_txt(txt:String) -> Dictionary:
	var out = []
	var invalid = 0
	var split = txt.split(",")
	for i in range(1, split.size()):
		var s = split[i]
		if s == "": continue
		var d = s.split("|")
		if d.size() == 3 and d[0].is_valid_float() and d[1].is_valid_float() and d[2].is_valid_float():
			out.append([2.0 - float(d[0]), 2.0 - float(d[1]), int(round(float(d[2])))])
		else:
			invalid += 1
	return {"notes": out, "invalid": invalid}

# ------------------------------------------------------------------ storage
# (-0.0 and 0.0 are one position: + 0.0 turns -0.0 into 0.0, and "%.4f" of -0.00001 would read "-0.0000")
static func key_of(n:Array) -> String:
	return "%.4f|%.4f|%d" % [stepify(n[0], 0.0001) + 0.0, stepify(n[1], 0.0001) + 0.0, int(n[2])]

static func less(a:Array, b:Array) -> bool:
	if a[2] != b[2]: return a[2] < b[2]
	if a[1] != b[1]: return a[1] < b[1]
	return a[0] < b[0]

# first index with note ms >= t
func lower_bound(t:float) -> int:
	var lo = 0
	var hi = notes.size()
	while lo < hi:
		var mid = (lo + hi) / 2
		if notes[mid][2] < t: lo = mid + 1
		else: hi = mid
	return lo

func set_notes(ns:Array):
	notes = []
	keys = {}
	for n in ns:
		var c = [float(n[0]), float(n[1]), int(round(n[2]))]
		var k = key_of(c)
		if keys.has(k): continue
		keys[k] = true
		notes.append(c)
	notes.sort_custom(self, "_cmp")
	rev += 1

func _cmp(a, b) -> bool:
	return less(a, b)

func _insert(n:Array) -> bool:
	var k = key_of(n)
	if keys.has(k): return false
	keys[k] = true
	var lo = 0
	var hi = notes.size()
	while lo < hi:
		var mid = (lo + hi) / 2
		if less(notes[mid], n): lo = mid + 1
		else: hi = mid
	notes.insert(lo, n)
	return true

func _erase(n:Array) -> bool:
	var k = key_of(n)
	if !keys.has(k): return false
	keys.erase(k)
	var i = lower_bound(n[2])
	while i < notes.size() and notes[i][2] == n[2]:
		if key_of(notes[i]) == k:
			notes.remove(i)
			return true
		i += 1
	return false

func has_note(n:Array) -> bool:
	return keys.has(key_of(n))

# ------------------------------------------------------------------ commands + undo
func begin(name:String):
	_depth += 1
	if _depth == 1: _open = {"name": name, "ops": []}

func end():
	_depth = max(_depth - 1, 0)
	if _depth == 0 and _open.has("ops"):
		if _open.ops.size() > 0:
			undo_stack.append(_open)
			if undo_stack.size() > UNDO_LIMIT: undo_stack.pop_front()
			redo_stack = []
			dirty = true
			rev += 1
		_open = {}

# op: ["add", [notes]] | ["del", [notes]] | ["mov", [[old, new], ...]] ; returns the ops that really applied
func run(op:Array) -> int:
	var grouped = _depth > 0
	if !grouped: begin("edit")
	var done = _apply(op)
	if done.size() > 0: _open.ops.append([op[0], done])
	if !grouped: end()
	return done.size()

func _apply(op:Array) -> Array:
	var done = []
	match op[0]:
		"add":
			for n in op[1]:
				var c = [float(n[0]) + 0.0, float(n[1]) + 0.0, int(round(n[2]))]
				if _insert(c): done.append(c)
		"del":
			for n in op[1]:
				if _erase(n): done.append(n)
		"mov":
			for pr in op[1]:
				var o = pr[0]
				var nw = [float(pr[1][0]) + 0.0, float(pr[1][1]) + 0.0, int(round(pr[1][2]))]
				if key_of(o) == key_of(nw): continue
				if !keys.has(key_of(o)) or keys.has(key_of(nw)): continue # (a move onto another note is refused)
				_erase(o)
				_insert(nw)
				done.append([o, nw])
	return done

func _invert(op:Array) -> Array:
	match op[0]:
		"add": return ["del", op[1]]
		"del": return ["add", op[1]]
		_:
			var r = []
			for pr in op[1]: r.append([pr[1], pr[0]])
			return ["mov", r]

func can_undo() -> bool:
	return undo_stack.size() > 0

func can_redo() -> bool:
	return redo_stack.size() > 0

# after undo / redo: the notes that step put (back) into the map - the editor selects them
var touched:Array = []
func _placed(op:Array) -> Array:
	match op[0]:
		"add": return op[1]
		"mov":
			var r = []
			for pr in op[1]: r.append(pr[1])
			return r
	return []

func undo() -> String:
	if undo_stack.empty(): return ""
	var g = undo_stack.pop_back()
	touched = []
	for i in range(g.ops.size() - 1, -1, -1):
		var inv = _invert(g.ops[i])
		_apply(inv)
		touched += _placed(inv)
	redo_stack.append(g)
	dirty = true
	rev += 1
	return g.name

func redo() -> String:
	if redo_stack.empty(): return ""
	var g = redo_stack.pop_back()
	touched = []
	for op in g.ops:
		_apply(op)
		touched += _placed(op)
	undo_stack.append(g)
	dirty = true
	rev += 1
	return g.name

func history() -> Array: # newest first: [name, note count touched]
	var out = []
	for i in range(undo_stack.size() - 1, max(undo_stack.size() - 40, -1), -1):
		var c = 0
		for op in undo_stack[i].ops: c += op[1].size()
		out.append([undo_stack[i].name, c])
	return out

# ------------------------------------------------------------------ validation (Rhythia's real constraints only)
# -> [{sev: "error" | "warn" | "info", msg, ms (-1 = none)}]
func validate(audio_len_ms:float, audio_ok:bool) -> Array:
	var out = []
	if !audio_ok: out.append({"sev": "error", "msg": "Audio file missing or unreadable - the map cannot be saved or played.", "ms": -1})
	var id:String = meta.id
	if id == "": out.append({"sev": "error", "msg": "Map id is empty (it names the file).", "ms": -1})
	else:
		var bad = false
		for c in id:
			if !(c in "0123456789abcdefghijklmnopqrstuvwxyz_-"): bad = true
		if bad: out.append({"sev": "error", "msg": "Map id may only use a-z 0-9 _ - (lowercase).", "ms": -1})
	if str(meta.name).strip_edges() == "": out.append({"sev": "error", "msg": "Song title is empty.", "ms": -1})
	if str(meta.creator).strip_edges() == "": out.append({"sev": "warn", "msg": "Mapper name is empty (shows as Unknown).", "ms": -1})
	if notes.empty(): out.append({"sev": "error", "msg": "The map has no notes.", "ms": -1})
	if extra_markers > 0: out.append({"sev": "warn", "msg": "The source map has %d marker type(s) besides notes; the editor cannot keep them - saving drops them." % extra_markers, "ms": -1})
	var neg = 0
	var late = 0
	var offgrid = 0
	var first_neg = -1
	var first_late = -1
	var first_off = -1
	for n in notes:
		if n[2] < 0:
			neg += 1
			if first_neg < 0: first_neg = n[2]
		if n[2] > MAX_MS:
			late += 1
			if first_late < 0: first_late = n[2]
		elif audio_len_ms > 0 and n[2] > audio_len_ms + 50:
			late += 1
			if first_late < 0: first_late = n[2]
		if n[0] < GRID_MIN or n[0] > GRID_MAX or n[1] < GRID_MIN or n[1] > GRID_MAX:
			offgrid += 1
			if first_off < 0: first_off = n[2]
	if neg > 0: out.append({"sev": "error", "msg": "%d note(s) before 0:00 - the file stores times unsigned." % neg, "ms": first_neg})
	if late > 0: out.append({"sev": "warn", "msg": "%d note(s) after the end of the audio - they can never be hit." % late, "ms": first_late})
	if offgrid > 0: out.append({"sev": "warn", "msg": "%d note(s) far outside the 3x3 grid." % offgrid, "ms": first_off})
	# stacked notes: same time and nearly the same cell (exact duplicates cannot exist here)
	var stacked = 0
	var first_st = -1
	for i in range(notes.size()):
		var j = i + 1
		while j < notes.size() and notes[j][2] == notes[i][2]:
			if abs(notes[j][0] - notes[i][0]) < 0.25 and abs(notes[j][1] - notes[i][1]) < 0.25:
				stacked += 1
				if first_st < 0: first_st = notes[i][2]
			j += 1
	if stacked > 0: out.append({"sev": "info", "msg": "%d pair(s) of notes at the same time almost on top of each other." % stacked, "ms": first_st})
	if audio_len_ms > 0 and !notes.empty() and notes[0][2] < 500 and notes[0][2] >= 0:
		out.append({"sev": "info", "msg": "First note is within 0.5 s of the start; players get little warning.", "ms": notes[0][2]})
	return out

# ------------------------------------------------------------------ session (autosave / resume)
func to_dict() -> Dictionary:
	return {"v": 1, "meta": meta, "bpm": bpm, "offset": offset, "div": div, "bookmarks": bookmarks,
		"points": points, "extra_markers": extra_markers, "dirty": dirty, "notes": notes}

# timing points from saved data (anything malformed is dropped)
func set_points(a):
	points = []
	if typeof(a) != TYPE_ARRAY: return
	for p in a:
		if typeof(p) == TYPE_ARRAY and p.size() == 2: add_point(int(p[0]), float(p[1]))

static func from_dict(d:Dictionary):
	var m = load("res://mods/replay/EditorModel.gd").new()
	if typeof(d.get("meta")) == TYPE_DICTIONARY:
		for k in m.meta:
			if d.meta.has(k): m.meta[k] = d.meta[k]
	m.bpm = clamp(float(d.get("bpm", 120.0)), 20.0, 400.0)
	m.offset = int(d.get("offset", 0))
	m.div = int(clamp(int(d.get("div", 4)), 1, 16))
	m.bookmarks = d.get("bookmarks", []) if typeof(d.get("bookmarks")) == TYPE_ARRAY else []
	m.set_points(d.get("points", []))
	m.extra_markers = int(d.get("extra_markers", 0))
	m.dirty = bool(d.get("dirty", false))
	var ns = d.get("notes", [])
	if typeof(ns) == TYPE_ARRAY:
		var ok = []
		for n in ns:
			if typeof(n) == TYPE_ARRAY and n.size() == 3: ok.append(n)
		m.set_notes(ok)
	return m
