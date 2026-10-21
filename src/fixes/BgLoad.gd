extends Node
# Background loading for the map pages (Rhythia-reimagined, after the Rhythia rewrite's MapCache.cs /
# MapList.cs: decode on a Task, hand the result back with CallDeferred). One worker thread:
#  - the selected map (the latest request wins): full cover decoded + preview stream built
#    (Song._cover_image / make_stream_threaded), then `loaded(map)` on the main thread
#  - list thumbnails (newest request first), then `thumb_loaded(map)`
# Textures are only made on the main thread (Android's GLES can't make them on another one).

signal loaded(map)
signal thumb_loaded(map)
const THUMB = 384 # the map list's size (v3MapList.THUMB): one thumbnail per map serves both menus

var thread:Thread
var sem:Semaphore = Semaphore.new()
var mx:Mutex = Mutex.new()
var want = null
var thumbs:Array = []
var quit:bool = false

# the fixes mod's Song.gd (with the thread-safe loaders) is installed
static func available() -> bool:
	for m in Song.get_script_method_list():
		if m.name == "make_stream_threaded": return true
	return false

func _ready():
	thread = Thread.new()
	thread.start(self, "_loop")

func request(map):
	mx.lock()
	want = map
	mx.unlock()
	sem.post()

func request_thumb(map):
	mx.lock()
	var add = !thumbs.has(map)
	if add: thumbs.append(map)
	mx.unlock()
	if add: sem.post()

func clear_thumbs():
	mx.lock()
	thumbs.clear()
	mx.unlock()

# every request posts once and a wake-up does at most one job, so no job is left waiting
func _loop(_u):
	while true:
		sem.wait()
		mx.lock()
		var map = want
		want = null
		var th = thumbs.pop_back() if map == null and thumbs.size() > 0 else null
		var q = quit
		mx.unlock()
		if q: return
		if map is Object and is_instance_valid(map):
			var img = map._cover_image() if map.has_cover and !map.loaded_cover() else null
			var st = map.make_stream_threaded() if !map.rr_stream else null
			call_deferred("_done", map, img, st)
		elif th is Object and is_instance_valid(th) and !th.thumb:
			call_deferred("_thumb_done", th, th.thumb_image(THUMB))

func _done(map, img, st):
	if !is_instance_valid(map): return
	if img != null and !map.loaded_cover(): map._cover_ready(img)
	if st: map.set_prefetched_stream(st)
	emit_signal("loaded", map)

func _thumb_done(map, img):
	if !is_instance_valid(map): return
	if !map.thumb: map.set_thumb(img)
	emit_signal("thumb_loaded", map)

func _exit_tree():
	if !thread: return
	mx.lock()
	quit = true
	mx.unlock()
	sem.post()
	thread.wait_to_finish()
	thread = null
