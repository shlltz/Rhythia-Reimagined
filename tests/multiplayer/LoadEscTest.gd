extends Node
# Esc on the loading screen goes back to the map page and the run never starts. Output @@OUT@@/load_esc.txt
const OUT = "@@OUT@@/load_esc.txt"
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")
func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()
func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")
func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	yield(wait(1.0), "completed")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	yield(wait(1.2), "completed")
	var e = InputEventKey.new(); e.scancode = KEY_ESCAPE; e.pressed = true
	Input.parse_input_event(e)
	yield(wait(4.0), "completed")
	var sc = get_tree().current_scene
	var name = sc.filename if sc else ""
	var ok = sc and !sc.has_node("Game") and !("songload" in name)
	out(("PASS" if ok else "FAIL") + "  Esc on the loading screen goes back  " + name)
	out("== totals: %d passed, %d failed" % [1 if ok else 0, 0 if ok else 1])
	OS.kill(OS.get_process_id())
