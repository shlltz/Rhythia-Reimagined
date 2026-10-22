extends Node
# Replay Studio clip export, writing side (Rhythia-reimagined). Lives on the tree root so it outlives
# the replay's scene; ClipRecorder.gd feeds it frames while the replay plays the clip. A worker thread
# saves the MP4 frames as PNGs as they come, then writes
#   - <name>.gif always (GifWriter.gd: GIF_W x GIF_H, GIF_FPS fps),
#   - <name>.mp4 only when ffmpeg is installed (on PATH; nothing is ever downloaded): the frames at
#     MP4_FPS fps, H.264, with the song's audio when the clip has no pause and plays at 1x,
# into user://clips/, then says where (a notification + a line on screen) and frees itself.

const GW = preload("res://mods/replay/GifWriter.gd")
const GIF_W = 400
const GIF_H = 225
const GIF_FPS = 20
const MP4_FPS = 30
const DIR = "user://clips"

var clip:Dictionary = {}         # {name, mp4, audio_from_ms, audio_ok, song}; audio_buf set in finish()
var gif_frames:Array = []        # PoolByteArray RGB8 per frame
var _queue:Array = []            # [Image, png path]
var _mutex = Mutex.new()
var _sem = Semaphore.new()
var _thread:Thread = null
var _stop:bool = false
var _png_n:int = 0
var _finishing:bool = false
var progress:String = ""
var result:Dictionary = {}       # {gif, mp4, error}
var label:Label

static func has_ffmpeg() -> bool:
	if Engine.has_meta("rr_ffmpeg"): return Engine.get_meta("rr_ffmpeg")
	var out = []
	var ok = false
	if OS.get_name() in ["Windows", "X11", "OSX"]:
		ok = OS.execute("ffmpeg", ["-hide_banner", "-version"], true, out, true) == 0 and str(out).find("ffmpeg") >= 0
	Engine.set_meta("rr_ffmpeg", ok)
	return ok

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	var cl = CanvasLayer.new()
	cl.layer = 120
	add_child(cl)
	label = Label.new()
	label.anchor_left = 1; label.anchor_right = 1; label.anchor_top = 1; label.anchor_bottom = 1
	label.margin_left = -520; label.margin_right = -16; label.margin_top = -40; label.margin_bottom = -12
	label.align = Label.ALIGN_RIGHT
	label.add_color_override("font_color", Color(1, 1, 1, 0.85))
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.8))
	cl.add_child(label)
	Directory.new().make_dir_recursive(_tmp())
	_thread = Thread.new()
	_thread.start(self, "_work")

func _tmp() -> String:
	return "%s/%s_frames" % [DIR, clip.get("name", "clip")]

func push_gif(img:Image):
	var im = img.duplicate()
	im.resize(GIF_W, GIF_H, Image.INTERPOLATE_BILINEAR)
	im.convert(Image.FORMAT_RGB8)
	gif_frames.append(im.get_data())

func push_mp4(img:Image):
	_mutex.lock()
	_queue.append([img, "%s/f_%05d.png" % [_tmp(), _png_n]])
	_png_n += 1
	_mutex.unlock()
	_sem.post()

# recording over: write everything (cancelled = drop it all). The song's audio is read here, on the
# main thread (Song isn't thread safe).
func finish(cancelled:bool = false):
	if !cancelled and clip.get("mp4", false) and clip.get("audio_ok", false) and clip.get("song"):
		clip.audio_buf = clip.song.get_music_buffer()
	_finishing = true
	if cancelled:
		_stop = true
		gif_frames = []
	_sem.post()

func _process(_d):
	_mutex.lock()
	var t = progress
	var done = result.size() > 0
	_mutex.unlock()
	if label: label.text = t
	if done and _thread: _done() # (the worker's last step: joining it is immediate)

func _say(t:String):
	_mutex.lock()
	progress = t
	_mutex.unlock()

func _work(_a):
	# 1) PNG frames for the MP4, as they arrive
	while true:
		_sem.wait()
		_mutex.lock()
		var item = _queue.pop_front() if _queue.size() > 0 else null
		var left = _queue.size()
		_mutex.unlock()
		if item:
			item[0].save_png(item[1])
			if _finishing: _say("Saving clip frames... %d left" % left)
			continue
		if _finishing: break
	if _stop:
		_cleanup()
		_mutex.lock()
		result = {"error": "cancelled"}
		_mutex.unlock()
		return
	var stamp = clip.get("name", "clip")
	var gif_path = "%s/%s.gif" % [DIR, stamp]
	var mp4_path = "%s/%s.mp4" % [DIR, stamp]
	var res = {}
	# 2) GIF
	if gif_frames.size() > 0:
		var g = GW.new()
		g.begin(GIF_W, GIF_H, int(round(100.0 / GIF_FPS)))
		for i in gif_frames.size():
			if i % 5 == 0: _say("Writing GIF... %d %%" % int(100.0 * i / gif_frames.size()))
			g.add_frame(gif_frames[i])
		var f = File.new()
		if f.open(gif_path, File.WRITE) == OK:
			f.store_buffer(g.finish())
			f.close()
			res.gif = gif_path
	gif_frames = []
	# 3) MP4 through ffmpeg
	if clip.get("mp4", false) and _png_n > 0:
		_say("Writing MP4 (ffmpeg)...")
		var args = ["-v", "error", "-y", "-framerate", str(MP4_FPS), "-i", ProjectSettings.globalize_path(_tmp() + "/f_%05d.png")]
		var audio = ""
		if !clip.get("audio_ok", false):
			res.audio_note = "a pause or another speed inside the clip"
		elif !clip.has("audio_buf") or clip.audio_buf == null or clip.audio_buf.size() == 0:
			res.audio_note = "the map's audio couldn't be read"
		elif _audio_ext(clip.audio_buf) == "":
			res.audio_note = "unknown audio format"
		else:
			var buf = clip.audio_buf
			var ext = _audio_ext(buf)
			if ext != "":
				audio = "%s/audio.%s" % [_tmp(), ext]
				var af = File.new()
				if af.open(audio, File.WRITE) == OK:
					af.store_buffer(buf)
					af.close()
					args += ["-ss", "%.3f" % (max(clip.audio_from_ms, 0.0) / 1000.0), "-i", ProjectSettings.globalize_path(audio), "-map", "0:v", "-map", "1:a", "-c:a", "aac", "-b:a", "192k", "-shortest"]
				else:
					audio = ""
		args += ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-movflags", "+faststart", ProjectSettings.globalize_path(mp4_path)]
		var out = []
		var code = OS.execute("ffmpeg", args, true, out, true)
		if code == 0 and File.new().file_exists(mp4_path):
			res.mp4 = mp4_path
			res.mp4_audio = audio != ""
		else:
			res.mp4_error = "ffmpeg exit %d: %s" % [code, str(out).strip_edges().left(200)]
	_cleanup()
	if !res.has("gif") and !res.has("mp4"): res.error = res.get("mp4_error", "nothing was written")
	_mutex.lock()
	result = res
	_mutex.unlock()

static func _audio_ext(b:PoolByteArray) -> String:
	if b.size() < 12: return ""
	var head = b.subarray(0, 3).get_string_from_ascii() # (subarray's end is inclusive: 4 bytes)
	if head.begins_with("ID3") or (b[0] == 0xFF and (b[1] & 0xE0) == 0xE0): return "mp3"
	if head == "OggS": return "ogg"
	if head == "RIFF": return "wav"
	return ""

func _cleanup():
	var d = Directory.new()
	if d.open(_tmp()) == OK:
		d.list_dir_begin(true, true)
		var f = d.get_next()
		while f != "":
			d.remove(_tmp() + "/" + f)
			f = d.get_next()
		d.list_dir_end()
	d.remove(_tmp())

func _done():
	_thread.wait_to_finish()
	_thread = null
	_mutex.lock()
	var r = result
	result = {}
	_mutex.unlock()
	var msg = ""
	if r.has("error"):
		msg = "Clip not saved: %s" % r.error
		if r.error != "cancelled": Globals.notify(Globals.NOTIFY_ERROR, msg, "Replay Studio")
	else:
		var parts = []
		if r.has("gif"): parts.append(r.gif.get_file())
		if r.has("mp4"): parts.append(r.mp4.get_file() + ("" if r.mp4_audio else " (no sound)"))
		msg = "Clip saved: %s  (%s)" % [PoolStringArray(parts).join(", "), ProjectSettings.globalize_path(DIR)]
		if r.has("mp4_error"): msg += "  - MP4 failed: " + r.mp4_error
		Globals.notify(Globals.NOTIFY_SUCCEED, msg, "Replay Studio")
	Engine.set_meta("rr_clip_result", r)
	_say(msg)
	yield(get_tree().create_timer(6.0), "timeout")
	queue_free()
