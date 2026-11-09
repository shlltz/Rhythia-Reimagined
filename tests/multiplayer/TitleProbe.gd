extends Node
# Title menu frame cost (uncapped): after the intro, 3 windows of 4 s; mean / p50 / p99 each.
# RR_RES as ScreenProbe. Output @@OUT@@/title.txt
const OUT = "@@OUT@@/title.txt"
var last_us = 0
var rec = null
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.vsync_enabled = false
	Engine.target_fps = 0
	var res = OS.get_environment("RR_RES").split("x")
	OS.window_size = Vector2(int(res[0]), int(res[1])) if res.size() == 2 else Vector2(1920, 1080)
	call_deferred("run")
func _process(_d):
	var now = OS.get_ticks_usec()
	if rec != null and last_us > 0: rec.append((now - last_us) / 1000.0)
	last_us = now
func run():
	yield(get_tree().create_timer(22.0), "timeout")
	var f = File.new()
	f.open(OUT, File.WRITE)
	var all = []
	for w in 3:
		rec = []
		yield(get_tree().create_timer(4.0), "timeout")
		var a = rec
		rec = null
		var s = 0.0
		for v in a: s += v
		a.sort()
		all.append(s / a.size())
		f.store_line("window %d: mean %.3f ms  p50 %.3f  p99 %.3f" % [w, s / a.size(), a[a.size() / 2], a[int(a.size() * 0.99)]])
	all.sort()
	f.store_line("median of windows: %.3f ms" % all[1])
	f.close()
	OS.kill(OS.get_process_id())
