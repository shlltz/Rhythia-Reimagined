extends Node
# Diagnosis: Esc 0.25 s into the loading card; a watchdog thread logs every 0.25 s what the main
# thread last did (frame count, scene, resource queue) so a hang shows where it stopped.
# Output @@OUT@@/eschang.txt
const OUT = "@@OUT@@/eschang.txt"
var th = Thread.new()
var stop = false
var frames = 0
var scene_name = ""
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")
func _process(_d):
	frames += 1
	var sc = get_tree().current_scene
	scene_name = sc.name if sc else "-"
func _dog(_u):
	var f = File.new()
	f.open(OUT, File.WRITE)
	var t0 = OS.get_ticks_msec()
	while !stop and OS.get_ticks_msec() - t0 < 12000:
		var q = []
		for r in RQueue.queue: q.append(str(r.get_meta("path")).get_file() + " %d/%d" % [r.get_stage(), r.get_stage_count()])
		f.store_line("%5d ms  frames %d  scene %s  queue %s  pending %s" % [OS.get_ticks_msec() - t0, frames, scene_name, str(q), str(RQueue.pending.keys())])
		f.flush()
		OS.delay_msec(250)
	f.close()
func run():
	yield(get_tree().create_timer(6.0, true), "timeout")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	yield(get_tree().create_timer(1.0, true), "timeout")
	th.start(self, "_dog")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	yield(get_tree().create_timer(0.25, true), "timeout")
	var e = InputEventKey.new(); e.scancode = KEY_ESCAPE; e.pressed = true
	Input.parse_input_event(e)
	yield(get_tree().create_timer(6.0, true), "timeout")
	stop = true
	th.wait_to_finish()
	OS.kill(OS.get_process_id())
