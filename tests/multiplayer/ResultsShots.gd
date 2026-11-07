extends Node
# Results board pictures: a pass and a fail opened from made-up runs, mid-tally and finished, plus a
# click skipping the tally. Output @@OUT@@/results.txt + res_*.png
const OUT = "@@OUT@@/results.txt"
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")
func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()
func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")
func shot(n):
	yield(get_tree(), "idle_frame")
	var img = get_tree().root.get_texture().get_data()
	img.flip_y()
	img.resize(960, 540)
	img.save_png("@@OUT@@/res_%s.png" % n)
func open(r:Dictionary):
	Rhythia.set_meta("last_run", r)
	get_tree().change_scene("res://scenes/loaders/menuload.tscn")
	var t = 0.0
	while t < 15 and !get_tree().root.has_node("Menu/ResultsScreen"):
		yield(wait(0.1), "completed"); t += 0.1
	return get_tree().root.get_node_or_null("Menu/ResultsScreen")
func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	Rhythia.select_song(song)
	var base = {song = song, score = 1834520, hits = 1592, misses = 14, total = 1606, combo = 611, end_type = Globals.END_PASS,
		pauses = 0, position = 155000.0, length = 156000.0, speed = 1.0, replay = false, mods = [], resume = null, resumed = false, replay_path = ""}
	var rs = yield(open(base), "completed")
	yield(wait(0.85), "completed")
	yield(shot("pass_mid"), "completed")
	yield(wait(2.0), "completed")
	yield(shot("pass"), "completed")
	out("pass: stamped=%s rows=%d" % [rs.stamped, rs.rows.size()])
	var f = base.duplicate()
	f.end_type = Globals.END_FAIL; f.hits = 402; f.misses = 61; f.combo = 88; f.score = 312400; f.position = 61000.0; f.mods = ["NoFail"]; f.speed = 1.25
	rs._back()
	yield(wait(0.6), "completed")
	rs = yield(open(f), "completed")
	yield(wait(0.5), "completed")
	var mb = InputEventMouseButton.new(); mb.button_index = BUTTON_LEFT; mb.pressed = true
	Input.parse_input_event(mb)
	yield(wait(0.3), "completed")
	out("fail: a click skipped the tally: stamped=%s" % rs.stamped)
	yield(wait(0.6), "completed")
	yield(shot("fail"), "completed")
	OS.kill(OS.get_process_id())
