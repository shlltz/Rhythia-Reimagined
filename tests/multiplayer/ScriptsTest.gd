extends Node
# Every mod script in this build compiles (a public build once shipped a pause menu that didn't parse:
# a file shared by both builds used something only the personal build had), and a live run's Esc
# opens the pause menu and Continue closes it. Output @@OUT@@/scripts.txt
const OUT = "@@OUT@@/scripts.txt"
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

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")

func scripts(dir:String, acc:Array):
	var d = Directory.new()
	if d.open(dir) != OK: return
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if d.current_is_dir(): scripts(dir + "/" + n, acc)
		elif n.ends_with(".gd"): acc.append(dir + "/" + n)
		n = d.get_next()
	d.list_dir_end()

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var all = []
	scripts("res://mods", all)
	ok("mod scripts found", all.size() > 50, all.size())
	var bad = []
	for p in all:
		if p.find("/bench/") >= 0: continue
		var f = File.new()
		if f.open(p, File.READ) == OK:
			var src = f.get_as_text()
			f.close()
			if src.find("class_name ") >= 0: continue # (a global class: the game loaded it at its stock path already, loading it again here clashes)
		var s = load(p)
		if !(s is GDScript) or !s.can_instance(): bad.append(p)
	ok("every mod script compiles", bad.empty(), bad)

	# pause menu in a live run
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	Rhythia.select_song(song)
	Rhythia.set("mod_nofail", true)
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var g = null
	var t = 0.0
	while !g and t < 30:
		yield(wait(0.25), "completed"); t += 0.25
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"): g = sc.get_node("Game")
	yield(wait(5.0), "completed")
	var sp = g.get_node("Spawn")
	var e = InputEventKey.new()
	e.scancode = KEY_ESCAPE
	e.pressed = true
	Input.parse_input_event(e)
	yield(wait(0.1), "completed")
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	yield(wait(0.8), "completed")
	ok("Esc opens the pause menu", sp.pause_menu is CanvasLayer and sp.pause_menu.is_open(), sp.pause_menu)
	if sp.pause_menu is CanvasLayer:
		sp.pause_menu.emit_signal("chosen", "continue")
		yield(wait(2.0), "completed")
		ok("Continue plays on", !sp.pause_menu.is_open() and sp.pause_state == 0, sp.pause_state)
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
