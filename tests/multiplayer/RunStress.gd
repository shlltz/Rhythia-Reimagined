extends Node
# Starts and leaves a map again and again (results screen in between): the game must not crash or
# hang at a run's start or end. Output @@OUT@@/stress.txt
const OUT = "@@OUT@@/stress.txt"
const N = 15

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")

func run():
	Directory.new().remove(OUT)
	out("thread_model %s" % ProjectSettings.get_setting("rendering/threads/thread_model"))
	yield(wait(6.0), "completed")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	var ok = 0
	for i in N:
		Rhythia.select_song(song)
		Rhythia.set("mod_nofail", true)
		get_tree().change_scene("res://scenes/loaders/songload.tscn")
		var g = null
		var t = 0.0
		while !g and t < 30:
			yield(wait(0.25), "completed"); t += 0.25
			var sc = get_tree().current_scene
			if sc and sc.has_node("Game"): g = sc.get_node("Game")
		if !g:
			out("FAIL  run %d didn't start" % i)
			continue
		yield(wait(1.5), "completed")
		g.end(Globals.END_GIVEUP)
		t = 0.0
		while t < 20 and !get_tree().root.has_node("Menu/ResultsScreen"):
			yield(wait(0.25), "completed"); t += 0.25
		yield(wait(0.6), "completed")
		ok += 1
		out("PASS  run %d" % i)
	out("== totals: %d passed, %d failed" % [ok, N - ok])
	OS.kill(OS.get_process_id())
