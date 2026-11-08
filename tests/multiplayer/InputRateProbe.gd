extends Node
# Mouse polling rate vs frame time in a live run (NoFail): mouse moves are sent at RR_HZ a second
# (default 8000, a gaming mouse) for 6 s with the engine's accumulated input on, then 6 s off;
# frame times for each (p50 / p99 / max / frames over 4 ms). Output @@OUT@@/inputrate.txt
const OUT = "@@OUT@@/inputrate.txt"
var last_us = 0
var rec = null

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.vsync_enabled = false
	Engine.target_fps = 0
	call_deferred("run")

var hz = 8000.0
var owed = 0.0
var ang = 0.0
func _process(_d):
	var now = OS.get_ticks_usec()
	if rec != null and last_us > 0:
		var dt = (now - last_us) / 1000000.0
		rec.append(dt * 1000.0)
		owed += dt * hz
		while owed >= 1.0: # (a small circle, one event per poll)
			owed -= 1.0
			ang += 0.002
			var e = InputEventMouseMotion.new()
			e.relative = Vector2(cos(ang), sin(ang)) * 0.5
			e.position = get_viewport().get_visible_rect().size / 2
			e.global_position = e.position
			Input.parse_input_event(e)
	last_us = now

func stats(label, a):
	var b = a.duplicate()
	b.sort()
	var slow = 0
	for v in a: if v > 4.0: slow += 1
	out("%-24s frames %d  p50 %.2f ms  p99 %.2f  max %.2f  over 4 ms: %d" % [label, a.size(), b[b.size() / 2], b[int(b.size() * 0.99)], b[-1], slow])

func run():
	Directory.new().remove(OUT)
	if OS.get_environment("RR_HZ") != "": hz = float(OS.get_environment("RR_HZ"))
	yield(wait(6.0), "completed")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	Rhythia.mod_nofail = true
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var t = 0.0
	while t < 20:
		yield(wait(0.1), "completed"); t += 0.1
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game/Spawn") and sc.get_node("Game/Spawn").active: break
	yield(wait(4.0), "completed")
	for acc in [true, false, true, false]:
		Input.use_accumulated_input = acc
		rec = []
		yield(wait(6.0), "completed")
		var a = rec
		rec = null
		stats("%d Hz, accumulated %s" % [hz, acc], a)
	out("== done")
	OS.kill(OS.get_process_id())
