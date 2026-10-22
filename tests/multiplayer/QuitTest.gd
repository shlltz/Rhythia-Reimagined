extends Node
# Clean quit: opens the menu, selects @@MAP1@@ (cover backdrop, preview), plays it for a few seconds,
# back to the menu, then quits the normal way (get_tree().quit()). mpbench prints CRASHED when the
# process doesn't exit cleanly. Output @@OUT@@/quit.txt
const OUT = "@@OUT@@/quit.txt"

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
	yield(wait(6.5), "completed")
	var menu = get_tree().root.get_node("Menu")
	var menu_scene = get_tree().current_scene.filename
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("")
	yield(wait(1.0), "completed")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	Rhythia.select_song(song)
	yield(wait(3.0), "completed")
	if "@@NAME@@" == "P":
		Rhythia.set("mod_nofail", true)
		get_tree().change_scene("res://scenes/loaders/songload.tscn")
		yield(wait(9.0), "completed")
		get_tree().change_scene(menu_scene)
		yield(wait(4.0), "completed")
	out("quitting")
	get_tree().quit()
