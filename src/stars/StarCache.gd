extends Node
# Star ratings + estimated BPM for every map, computed on a background thread and saved to
# user://star_ratings_v2.json / user://map_bpm_v2.json so each map is only processed once.
# Lives at /root/StarCache; get it with load(StarCache.PATH).get_instance(get_tree()).

signal rated(key, stars)
signal rated_at(memo_key, stars) # get_stars_at finished on the worker
signal onsets_ready(key, accents) # get_onsets finished on the worker
signal all_rated # queue emptied (list re-sorts)

const PATH = "res://mods/stars/StarCache.gd"
const SAVE_FILE = "user://star_ratings_v2.json" # v2 = rhythia.com star-calc (close-note merge); the old file is left alone
const BPM_FILE = "user://map_bpm_v2.json" # v2 = [main, low, high]; the old file is left alone
const StarRating = preload("res://mods/stars/StarRating.gd")

var ratings:Dictionary = {} # key -> stars at 1.0x
var bpms:Dictionary = {} # key -> [main, low, high] estimated BPM at 1.0x (0 = unknown)
var speed_memo:Dictionary = {} # "key@speed" -> stars
var onset_memo:Dictionary = {} # key -> accent times (see accent_times)
var queue:Array = []
var queued:Dictionary = {}
var dirty:bool = false
var mutex:Mutex = Mutex.new()
var sem:Semaphore = Semaphore.new()
var thread:Thread = Thread.new()
var running:bool = true

static func get_instance(tree:SceneTree) -> Node:
	if Engine.has_meta("StarCache"): return Engine.get_meta("StarCache")
	var n = load(PATH).new()
	n.name = "StarCache"
	Engine.set_meta("StarCache", n)
	tree.root.call_deferred("add_child", n)
	return n

static func key_of(song) -> String:
	return "%s|%d|%d" % [song.id, song.note_count, int(song.last_ms)]

func _init():
	ratings = _load(SAVE_FILE)
	bpms = _load(BPM_FILE)
	thread.start(self, "_worker")

static func _load(path:String) -> Dictionary:
	var f = File.new()
	if f.file_exists(path) and f.open(path, File.READ) == OK:
		var d = parse_json(f.get_as_text())
		f.close()
		if typeof(d) == TYPE_DICTIONARY: return d
	return {}

func _ready():
	# rate the whole library in the background (cached ones are skipped)
	if Rhythia.registry_song:
		for s in Rhythia.registry_song.get_items():
			if s is Song: get_stars(s)

# Stars at 1.0x, or -1 if not ready yet (it gets queued; listen to "rated").
func get_stars(song) -> float:
	if song == null or song.is_online or song.id == "!DELETED": return -1.0
	var k = key_of(song)
	if ratings.has(k):
		if !bpms.has(k): _queue(song, k)
		return float(ratings[k])
	_queue(song, k)
	return -1.0

# Estimated BPM at 1.0x: > 0 known, 0 couldn't tell, -1 not ready yet (listen to "rated").
func get_bpm(song) -> float:
	if song == null or song.is_online or song.id == "!DELETED": return -1.0
	var k = key_of(song)
	if bpms.has(k): return float(bpms[k][0])
	_queue(song, k)
	return -1.0

# [low, high] BPM at 1.0x (equal when the tempo is steady), or [] if not ready yet.
func get_bpm_range(song) -> Array:
	if get_bpm(song) < 0: return []
	var b = bpms[key_of(song)]
	return [float(b[1]), float(b[2])]

func _queue(song, k:String):
	mutex.lock()
	if !queued.has(k):
		queued[k] = true
		queue.append([k, _note_source(song), !ratings.has(k)])
		sem.post()
	mutex.unlock()

# Stars at a given speed, or -1 while the worker computes it (listen to "rated_at"; a 13k-note
# map took ~70 ms, which hitched the menu when it ran on the main thread).
static func memo_key(song, speed:float) -> String:
	return "%s@%.4f" % [key_of(song), speed]

func get_stars_at(song, speed:float) -> float:
	if is_equal_approx(speed, 1.0): return get_stars(song)
	if song == null or song.is_online: return -1.0
	var mk = memo_key(song, speed)
	if speed_memo.has(mk): return speed_memo[mk]
	mutex.lock()
	if !queued.has(mk):
		queued[mk] = true
		queue.push_front([mk, _note_source(song), false, speed]) # ahead of the background library rating
		sem.post()
	mutex.unlock()
	return -1.0

# same, but computed right here if it isn't known yet (results screen needs the number now)
func get_stars_at_now(song, speed:float) -> float:
	if is_equal_approx(speed, 1.0): return get_stars(song)
	if song == null or song.is_online: return -1.0
	var mk = memo_key(song, speed)
	if !speed_memo.has(mk): speed_memo[mk] = StarRating.new().calculate(_note_source(song).read_notes(), speed)
	return speed_memo[mk]

# The map's rhythm for visuals: [time ms, strength, time, strength, ...] - one entry per note
# onset (chords merged) at least ~half a beat after the previous kept one; strength 1 on the beat
# (after a pause, or on the beat grid of the last full hit), 0.45 for the notes in between (so
# streams don't turn into a constant buzz). null while the
# worker computes it (listen to "onsets_ready").
func get_onsets(song):
	if song == null or song.is_online: return []
	var k = key_of(song)
	if onset_memo.has(k): return onset_memo[k]
	var jk = k + "#onsets"
	mutex.lock()
	if !queued.has(jk):
		queued[jk] = true
		queue.push_front([k, _note_source(song), false, 0.0, "onsets"])
		sem.post()
	mutex.unlock()
	return null

func _on_onsets(k:String, acc:PoolRealArray):
	onset_memo[k] = acc
	mutex.lock()
	queued.erase(k + "#onsets")
	mutex.unlock()
	emit_signal("onsets_ready", k, acc)

static func accent_times(notes:Array) -> PoolRealArray:
	var times = []
	for n in notes: times.append(float(n[2]))
	times.sort()
	var bpm = estimate_bpm(notes)[0]
	var period = 60000.0 / bpm if bpm > 0 else 400.0
	var out = PoolRealArray()
	var last = -100000.0
	var anchor = -100000.0 # last full hit: the beat grid runs on from it
	for t in times:
		var gap = t - last
		if gap < period * 0.45: continue
		# full hit after a pause (>= ~1 beat), or on the beat grid of the last full hit; the notes
		# in between are half hits. (Gap alone made every note of a stream a half hit - dense maps
		# never got a real beat.)
		var d = (t - anchor) / period
		var strong = gap >= period * 0.9 or (round(d) >= 1 and abs(d - round(d)) < 0.15)
		if strong: anchor = t
		out.append(t)
		out.append(1.0 if strong else 0.45)
		last = t
	return out

func _on_speed_rated(mk:String, v:float):
	speed_memo[mk] = v
	mutex.lock()
	queued.erase(mk)
	mutex.unlock()
	emit_signal("rated_at", mk, v)

# A detached Song with just what read_notes() needs, so the worker never touches
# the Song objects the game is using.
func _note_source(song):
	var s = Song.new()
	s.id = song.id
	s.songType = song.songType
	s.filePath = song.filePath
	s.initFile = song.initFile
	s.rawData = song.rawData
	s.marker_types = song.marker_types.duplicate(true) # own copy: the worker must not share arrays with the game
	s.marker_count = song.marker_count
	s.note_count = song.note_count
	if song.notes.size() != 0 and song.songType == Globals.MAP_RAW:
		s.notes = song.notes.duplicate()
	return s

func _worker(_u):
	while true:
		sem.wait()
		mutex.lock()
		if !running:
			mutex.unlock()
			return
		var job = queue.pop_front() if queue.size() > 0 else null
		mutex.unlock()
		if job == null: continue
		var notes = job[1].read_notes()
		if job.size() > 4: # accent times for the map page's beat pulse
			call_deferred("_on_onsets", job[0], accent_times(notes))
			continue
		if job.size() > 3: # stars at a speed
			call_deferred("_on_speed_rated", job[0], StarRating.new().calculate(notes, job[3]) if notes.size() > 0 else 0.0)
			continue
		var stars = -1.0
		if job[2]: stars = StarRating.new().calculate(notes, 1.0) if notes.size() > 0 else 0.0
		call_deferred("_on_rated", job[0], stars, estimate_bpm(notes))

func _on_rated(k:String, stars:float, bpm:Array):
	if stars >= 0: ratings[k] = stars
	bpms[k] = bpm
	stars = float(ratings.get(k, 0.0))
	mutex.lock()
	queued.erase(k)
	var done = queue.size() == 0
	mutex.unlock()
	dirty = true
	emit_signal("rated", k, stars)
	if done:
		save()
		emit_signal("all_rated")

func save():
	if !dirty: return
	for p in [[SAVE_FILE, ratings], [BPM_FILE, bpms]]:
		var f = File.new()
		if f.open(p[0], File.WRITE) == OK:
			f.store_string(to_json(p[1]))
			f.close()
	dirty = false

# Tempo from note timing (maps carry no BPM). Notes -> onsets (chords merged) -> histogram of
# every note-pair gap up to 2 s (streams, jumps and gaps all vote) -> each beat length scores its
# own gap count plus its double (a real beat repeats), weighted by a soft tempo prior around
# 160 BPM to choose between half/double time -> refined to a fraction of a ms from every gap
# that fits. 16 s sections get the same treatment, locked near the main tempo, so maps whose
# tempo changes report a range. Returns [main, low, high] BPM at 1.0x ([0, 0, 0] = couldn't tell).
const BPM_MIN = 60.0
const BPM_MAX = 300.0
const BPM_CENTER = 160.0
const LAG_MAX = 2000
const SECTION_MS = 16000.0

static func estimate_bpm(notes:Array) -> Array:
	var times = []
	for n in notes: times.append(float(n[2]))
	times.sort()
	var on = []
	for t in times:
		if on.empty() or t - on.back() > 4.0: on.append(t)
	if on.size() < 8: return [0.0, 0.0, 0.0]
	var main = _tempo(on, 0, on.size(), BPM_CENTER, 0.75, BPM_MIN, BPM_MAX)
	if main <= 0: return [0.0, 0.0, 0.0]
	var secs = []
	var a = 0
	while a < on.size():
		var b = a
		while b < on.size() and on[b] - on[a] < SECTION_MS: b += 1
		if b - a >= 16:
			var t = _tempo(on, a, b, main, 0.25, main / 1.7, main * 1.7)
			if t > 0: secs.append(t)
		a = b
	var lo = main
	var hi = main
	for t in secs: # a section tempo counts once another section agrees (drops one-off misreads)
		var agree = 0
		for u in secs:
			if abs(u / t - 1.0) < 0.025: agree += 1
		if agree >= 2:
			lo = min(lo, t)
			hi = max(hi, t)
	if hi / lo < 1.03: return [main, main, main]
	return [main, lo, hi]

static func _sm(h:Array, l:int) -> float:
	return (h[l - 2] + 2.0 * h[l - 1] + 3.0 * h[l] + 2.0 * h[l + 1] + h[l + 2]) / 9.0

# beat length (as BPM) of onsets [a, b); pairs may look past b so a section sees across its end
static func _tempo(on:Array, a:int, b:int, center:float, sigma:float, bmin:float, bmax:float) -> float:
	var h = []
	var hs = []
	h.resize(LAG_MAX + 4)
	hs.resize(LAG_MAX + 4)
	for i in h.size():
		h[i] = 0.0
		hs[i] = 0.0
	for i in range(a, b):
		var ti = on[i]
		var j = i + 1
		while j < on.size() and on[j] - ti <= LAG_MAX:
			var d = on[j] - ti
			var l = int(round(d))
			h[l] += 1.0
			hs[l] += d
			j += 1
	var lmin = max(int(60000.0 / bmax), 20)
	var lmax = min(int(60000.0 / bmin), LAG_MAX / 2 - 4)
	var best = 0
	var best_sc = 0.0
	for l in range(lmin, lmax + 1):
		var sc = _sm(h, l) + _sm(h, 2 * l)
		if sc <= 0.0: continue
		var z = log(60000.0 / l / center) / log(2.0) / sigma
		sc *= exp(-0.5 * z * z)
		if sc > best_sc:
			best_sc = sc
			best = l
	if best == 0: return 0.0
	var w = 0.0
	var sum = 0.0
	for k in [1, 2]:
		var tol = 2 * k + 1
		for l in range(best * k - tol, best * k + tol + 1):
			w += h[l]
			sum += hs[l] / k
	if w < max(4.0, 0.15 * (b - a)): return 0.0 # too few gaps fit: no steady beat here
	var bpm = 60000.0 / (sum / w)
	return round(bpm) if abs(bpm - round(bpm)) < 0.3 else stepify(bpm, 0.1)

func _exit_tree():
	mutex.lock()
	running = false
	mutex.unlock()
	sem.post()
	thread.wait_to_finish()
	save()

# Star colour, osu!-style spectrum stretched for Rhythia's higher ratings
const COLORS = [
	[0.0, Color("#4290fb")], [2.0, Color("#4fc0ff")], [2.5, Color("#4fffd5")],
	[3.3, Color("#7cff4f")], [4.2, Color("#f6f05c")], [4.9, Color("#ff8068")],
	[5.8, Color("#ff4e6f")], [6.7, Color("#c645b8")], [7.7, Color("#6563de")],
	[9.0, Color("#9b30ff")], [11.0, Color("#ff2df0")], [13.0, Color("#ffffff")]]
static func color_for(stars:float) -> Color:
	if stars <= COLORS[0][0]: return COLORS[0][1]
	for i in range(1, COLORS.size()):
		if stars < COLORS[i][0]:
			var a = COLORS[i-1]; var b = COLORS[i]
			return a[1].linear_interpolate(b[1], (stars - a[0]) / (b[0] - a[0]))
	return COLORS[-1][1]
