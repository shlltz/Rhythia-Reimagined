extends Node
# Long frames with nothing going on: sits on the menu (vsync off, uncapped) until RR_IDLE_S s after
# launch (default 50) and lists every frame over 40 ms with its time since launch.
# Output @@OUT@@/idle.txt
const OUT = "@@OUT@@/idle.txt"
var last_us = 0
var long = []

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.vsync_enabled = false
	Engine.target_fps = 0
	Directory.new().remove(OUT)

func _process(_d):
	var now = OS.get_ticks_usec()
	if last_us > 0 and now - last_us > 40000: long.append([(now - last_us) / 1000.0, now / 1000000.0])
	last_us = now
	var lim = float(OS.get_environment("RR_IDLE_S")) if OS.get_environment("RR_IDLE_S") != "" else 50.0
	if now / 1000000.0 > lim:
		set_process(false)
		for x in long: out("%7.2f ms at %.2f s since launch" % x)
		out("== done")
		OS.kill(OS.get_process_id())
