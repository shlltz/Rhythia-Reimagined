extends Reference
# Settings generator (Customize > Generator): what your runs say about your settings.
# On live runs (not replays, autoplay, multiplayer or the editor's test runs) NoteManager keeps one
# of these. For every note it notes where the cursor was when the note came due, then the result:
# a hit, and how late (the game judges a note from its time on, so a hit well after the first frame
# means the cursor got there late), or a miss, and which way the cursor was off against the path
# into the note: short of it (under), past it (over) or beside it (wide). At the end of the run
# (20+ notes) a summary goes to user://rr_playtrack.json with the settings it was played with
# (the last KEEP runs). Nothing leaves this PC. advise() turns the summaries into suggestions,
# each with its reason; apply_setting() changes one setting the way the settings page would.

const FILE = "user://rr_playtrack.json"
const KEEP = 60
const RECENT = 20              # runs advise() looks at
const LATE_MS = 20.0
const KEYS = ["approach_rate", "spawn_distance", "sensitivity", "absolute_mode", "note_hitbox_size", "hitwindow_ms", "fov",
	"parallax", "cursor_scale"]

var due:Dictionary = {}        # note index -> cursor position when it came due
var hits:int = 0
var misses:int = 0
var late:int = 0
var late_sum:float = 0.0
var under:int = 0
var over:int = 0
var wide:int = 0

static func on() -> bool:
	return bool(load("res://mods/replay/Reimagined.gd").val("track_plays"))

# ---------------------------------------------------------------- during a run (NoteManager)
func came_due(i:int, cursor:Vector2):
	if !due.has(i): due[i] = cursor

func hit(late_ms:float, frame_ms:float):
	hits += 1
	late_sum += late_ms
	if late_ms > max(LATE_MS, frame_ms * 1.5): late += 1

func miss(i:int, notes:Array, cursor:Vector2):
	misses += 1
	var c:Vector2 = due.get(i, cursor)
	var n:Vector2 = notes[i][0]
	var axis = n - notes[i - 1][0] if i > 0 else Vector2.ZERO
	if axis.length() < 0.25: # (a stack / the first note: no path to measure along)
		wide += 1
		return
	var u = axis.normalized()
	var along = (c - n).dot(u)
	var side = abs((c - n).cross(u))
	if side > abs(along): wide += 1
	elif along < 0.0: under += 1
	else: over += 1

func finish(song, end_type:int, speed:float):
	if hits + misses < 20 or !song: return
	var s = {}
	for k in KEYS: s[k] = Rhythia.get(k)
	var all = load_all()
	all.append({t = OS.get_unix_time(), map = str(song.id), name = str(song.name), notes = hits + misses, hits = hits, misses = misses,
		late = late, late_ms = late_sum / max(hits, 1), under = under, over = over, wide = wide, speed = speed,
		passed = end_type == Globals.END_PASS, settings = s})
	while all.size() > KEEP: all.pop_front()
	var f = File.new()
	if f.open(Globals.p(FILE), File.WRITE) == OK:
		f.store_string(to_json(all))
		f.close()

# ---------------------------------------------------------------- stored runs
static func load_all() -> Array:
	var f = File.new()
	if !f.file_exists(Globals.p(FILE)) or f.open(Globals.p(FILE), File.READ) != OK: return []
	var d = parse_json(f.get_as_text())
	f.close()
	return d if d is Array else []

static func forget():
	Directory.new().remove(Globals.p(FILE))

static func summary(runs:Array) -> Dictionary:
	var s = {runs = runs.size(), notes = 0, hits = 0, misses = 0, late = 0, under = 0, over = 0, wide = 0, late_ms = 0.0}
	for r in runs:
		for k in ["notes", "hits", "misses", "late", "under", "over", "wide"]: s[k] += int(r.get(k, 0))
		s.late_ms += float(r.get("late_ms", 0.0)) * int(r.get("hits", 0))
	s.late_ms /= max(s.hits, 1)
	s.acc = float(s.hits) / max(s.notes, 1)
	s.late_share = float(s.late) / max(s.hits, 1)
	return s

static func _key(st:Dictionary) -> String:
	return "%.2f|%.1f|%.2f" % [float(st.get("sensitivity", 0)), float(st.get("approach_rate", 0)), float(st.get("spawn_distance", 0))]

static func _round(v:float, step:float) -> float:
	return stepify(v, step)

# suggestions: [{id, title, why, set: {setting: value}}]
static func advise(all:Array) -> Array:
	var out = []
	var runs = all.slice(max(0, all.size() - RECENT), all.size() - 1) if all.size() > 0 else []
	var s = summary(runs)
	if s.runs < 3 or s.notes < 800: return out
	var ar = float(Rhythia.approach_rate)
	var sd = float(Rhythia.spawn_distance)
	# reading time: lots of hits only after the cursor arrived late
	if s.late_share > 0.30 and s.hits > 300:
		var nsd = _round(min(sd * 1.15, 60.0), 0.5)
		if nsd > sd:
			out.append({id = "reading", title = "More time to read the notes",
				why = "%d%% of your hits came more than %d ms after the note's time: the cursor tends to get there late. Notes that appear a little further away (spawn distance %.1f -> %.1f) give you %d ms more to see each one at the same speed." % [
					int(round(s.late_share * 100)), int(LATE_MS), sd, nsd, int(round((nsd - sd) / max(ar, 1.0) * 1000.0))],
				set = {"spawn_distance": nsd}})
	# aim: which way the misses fall
	var aimed = s.under + s.over
	if !bool(Rhythia.absolute_mode) and aimed >= 15:
		var sens = float(Rhythia.sensitivity)
		var r = float(s.over) / aimed
		if r >= 0.65:
			var ns = _round(sens * 0.93, 0.01)
			out.append({id = "sens_down", title = "Lower sensitivity a little",
				why = "%d of your %d misses along the path were past the note (overshooting). Sensitivity %.2f -> %.2f moves the cursor 7%% less for the same hand movement." % [s.over, aimed, sens, ns],
				set = {"sensitivity": ns}})
		elif r <= 0.35:
			var ns2 = _round(sens * 1.07, 0.01)
			out.append({id = "sens_up", title = "Raise sensitivity a little",
				why = "%d of your %d misses along the path were short of the note (not getting there). Sensitivity %.2f -> %.2f moves the cursor 7%% more for the same hand movement." % [s.under, aimed, sens, ns2],
				set = {"sensitivity": ns2}})
	# what you played best with (3+ runs with those settings, compared with the current ones)
	var groups = {}
	for r2 in all:
		var st = r2.get("settings", {})
		if !(st is Dictionary): continue
		var k = _key(st)
		if !groups.has(k): groups[k] = {runs = [], st = st}
		groups[k].runs.append(r2)
	var cur_key = _key({sensitivity = Rhythia.sensitivity, approach_rate = Rhythia.approach_rate, spawn_distance = Rhythia.spawn_distance})
	if groups.has(cur_key) and groups[cur_key].runs.size() >= 3:
		var cur = summary(groups[cur_key].runs)
		var best = null
		for k2 in groups:
			if k2 == cur_key or groups[k2].runs.size() < 3: continue
			var g = summary(groups[k2].runs)
			if g.acc >= cur.acc + 0.02 and (best == null or g.acc > best[1].acc): best = [k2, g]
		if best:
			var st2 = groups[best[0]].st
			out.append({id = "best", title = "Back to the settings you played best with",
				why = "With sensitivity %.2f, approach rate %.1f, spawn distance %.1f you hit %.1f%% over %d runs; with your current ones %.1f%% over %d (on the maps you played then)." % [
					float(st2.sensitivity), float(st2.approach_rate), float(st2.spawn_distance), best[1].acc * 100, best[1].runs, cur.acc * 100, cur.runs],
				set = {"sensitivity": float(st2.sensitivity), "approach_rate": float(st2.approach_rate), "spawn_distance": float(st2.spawn_distance)}})
	return out

# ---------------------------------------------------------------- applying
# sets one game setting and saves
static func apply_setting(tree:SceneTree, key:String, v):
	Rhythia.set(key, v)
	refresh_settings_page(tree)
	Rhythia.save_settings()

# The settings page's number boxes copy their own value into the game on every frame, so a setting
# changed from outside would be put back at once: each box reads the game's value again (its own
# _ready does exactly that).
static func refresh_settings_page(tree:SceneTree):
	var stack = [tree.root]
	while !stack.empty():
		var n = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if !(n is Range) or !n.get_script() or !n.has_method("upd"): continue
		if !n.get_script().resource_path.begins_with("res://scripts/ui/settings/"): continue
		if n.is_connected("changed", n, "upd"): n.disconnect("changed", n, "upd")
		n._ready()
