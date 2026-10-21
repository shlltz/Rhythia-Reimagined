extends Node
# dev probe: which GDScript operations crash this engine build when two threads run them at the
# same time. Output @@OUT@@/threads.txt (the last line printed is the case that crashed)
const OUT = "@@OUT@@/threads.txt"
var case_name = ""

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func _ready():
	call_deferred("run")

func work(kind):
	var n = 0
	for r in 300:
		var a = []
		for i in 400: a.append([randi() % 1000, randi() % 1000, i])
		match kind:
			"sort_arrays": a.sort()
			"sort_ints":
				var b = []
				for e in a: b.append(e[0] * 1000 + e[1])
				b.sort()
			"sort_custom": a.sort_custom(self, "_lt")
			"dicts":
				var d = {}
				for e in a: d[str(e[0])] = e
				n += d.size()
			"print": print("probe line %d %d" % [r, randi()])
			"error":
				if r % 3 == 0: push_error("probe error %d" % r)
			"get_float":
				var sp = StreamPeerBuffer.new()
				for e in a: sp.put_float(e[0] * 0.37)
				sp.seek(0)
				for e in a: n += int(sp.get_float())
			"strings":
				var s = PoolStringArray()
				for e in a: s.append("%d|%d|%d" % e)
				n += s.join(",").length()
	return n

func _lt(a, b):
	return a[0] < b[0]

func _thread(kind):
	return work(kind)

func run():
	Directory.new().remove(OUT)
	yield(get_tree().create_timer(5.0), "timeout")
	var kinds = OS.get_environment("RR_PROBE").split(",") if OS.get_environment("RR_PROBE") != "" else ["print", "error", "strings", "dicts", "sort_ints", "sort_custom", "sort_arrays"]
	if OS.get_environment("RR_PROBE_MAIN") != "":
		for kind in kinds:
			out("start %s / main only" % kind)
			work(kind)
			out("ok    %s / main only" % kind)
	for kind in kinds:
		for mode in ["one thread + idle main", "two threads"]:
			out("start %s / %s" % [kind, mode])
			var t1 = Thread.new()
			var t2 = Thread.new()
			t1.start(self, "_thread", kind)
			if mode == "two threads": t2.start(self, "_thread", kind)
			while t1.is_alive() or (mode == "two threads" and t2.is_alive()):
				yield(get_tree(), "idle_frame")
			t1.wait_to_finish()
			if mode == "two threads": t2.wait_to_finish()
			out("ok    %s / %s" % [kind, mode])
		# main thread working at the same time as one worker
		out("start %s / worker + main" % kind)
		var t3 = Thread.new()
		t3.start(self, "_thread", kind)
		work(kind)
		t3.wait_to_finish()
		out("ok    %s / worker + main" % kind)
	out("== all done")
	OS.kill(OS.get_process_id())
