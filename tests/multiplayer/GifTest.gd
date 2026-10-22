extends Node
# GIF writer (replay/GifWriter.gd): frames with gradients and noise (enough to fill the LZW table
# several times, so the table clears too) are written, then decoded by ffmpeg (when it is on PATH)
# and compared pixel by pixel with the palette colour each source pixel should get.
# Output @@OUT@@/gif_test.txt
const OUT = "@@OUT@@/gif_test.txt"
var passed = 0
var failed = 0

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func ok(n, c, d = ""):
	if c: passed += 1
	else: failed += 1
	out(("PASS  " if c else "FAIL  ") + n + ("  " + str(d) if str(d) != "" else ""))

func _ready():
	call_deferred("run")

func frame(w:int, h:int, k:int) -> PoolByteArray:
	var rng = RandomNumberGenerator.new()
	rng.seed = 100 + k
	var b = PoolByteArray()
	b.resize(w * h * 3)
	var i = 0
	for y in h:
		for x in w:
			if x < w / 2:
				b[i] = (x * 255 / (w / 2) + k * 20) % 256
				b[i + 1] = y * 255 / h
				b[i + 2] = 128
			else:
				b[i] = rng.randi() % 256
				b[i + 1] = rng.randi() % 256
				b[i + 2] = rng.randi() % 256
			i += 3
	return b

func run():
	Directory.new().remove(OUT)
	yield(get_tree().create_timer(1.0), "timeout")
	var G = load("res://mods/replay/GifWriter.gd")
	var w = 160
	var h = 90
	var g = G.new()
	g.begin(w, h, 5)
	var frames = []
	var t0 = OS.get_ticks_msec()
	for k in 3:
		var fr = frame(w, h, k)
		frames.append(fr)
		g.add_frame(fr)
	var data = g.finish()
	var ms = OS.get_ticks_msec() - t0
	out("3 frames %dx%d encoded in %d ms (%.2f us / pixel), %d bytes" % [w, h, ms, ms * 1000.0 / (3 * w * h), data.size()])
	var path = OS.get_user_data_dir() + "/gif_test.gif"
	var f = File.new()
	f.open(path, File.WRITE)
	f.store_buffer(data)
	f.close()
	ok("file starts GIF89a, ends with the trailer", data.subarray(0, 5).get_string_from_ascii() == "GIF89a" and data[data.size() - 1] == 0x3B)
	var outp = []
	var raw = OS.get_user_data_dir() + "/gif_test.raw"
	var code = OS.execute("ffmpeg", ["-v", "error", "-y", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24", raw], true, outp, true)
	if code != 0:
		out("ffmpeg not usable here (%d): %s" % [code, str(outp)])
		ok("decoded by ffmpeg", false, "ffmpeg exit %d" % code)
	else:
		f.open(raw, File.READ)
		var dec = f.get_buffer(f.get_len())
		f.close()
		ok("3 frames decoded", dec.size() == 3 * w * h * 3, dec.size())
		var bad = 0
		for k in 3:
			var src = frames[k]
			for i in w * h:
				var c = G.palette_color(g.index_of(src[i * 3], src[i * 3 + 1], src[i * 3 + 2]))
				var o = (k * w * h + i) * 3
				if o + 2 >= dec.size() or dec[o] != c[0] or dec[o + 1] != c[1] or dec[o + 2] != c[2]: bad += 1
		ok("every pixel decodes to its palette colour", bad == 0, "%d wrong" % bad)
		var probe = []
		OS.execute("ffprobe", ["-v", "error", "-count_frames", "-select_streams", "v:0", "-show_entries", "stream=nb_read_frames,width,height", "-of", "csv=p=0", path], true, probe, true)
		out("ffprobe: %s" % str(probe).strip_edges())
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
