extends Node
# Rewrite Feel (replay/RewriteFeel.gd): a run with it on uses the rewrite's values and note fade,
# the menu gets the player's own values back, a cut-off run is recovered, off = untouched.
# Output @@OUT@@/feel.txt + f_*.png
const OUT = "@@OUT@@/feel.txt"
const KEYS = ["approach_rate", "spawn_distance", "fov", "parallax", "ui_parallax", "grid_parallax"]
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

func own() -> Dictionary:
	var d = {}
	for k in KEYS: d[k] = Rhythia.get(k)
	return d

# equal to 1e-4 (a float that went through the settings page can differ in the last digits)
func same(a:Dictionary, b:Dictionary) -> bool:
	for k in b:
		if abs(float(a.get(k, -999)) - float(b[k])) > 1e-4: return false
	return true

func shot(n):
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/f_" + n + ".png")

# start @@MAP1@@, return the Game node after 3 s of play
func play():
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	Rhythia.select_song(song)
	Rhythia.set("mod_nofail", true)
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var t = 0.0
	var g = null
	while t < 30 and !g:
		yield(wait(0.25), "completed"); t += 0.25
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"): g = sc.get_node("Game")
	yield(wait(3.0), "completed")
	return g

func back(g):
	g.end(Globals.END_GIVEUP)
	var t = 0.0
	while t < 20 and !get_tree().root.has_node("Menu/ResultsScreen"):
		yield(wait(0.25), "completed"); t += 0.25

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var R = load("res://mods/replay/Reimagined.gd")
	var F = load("res://mods/replay/RewriteFeel.gd")
	ok("RewriteFeel.gd installed", F != null)
	ok("off by default", !bool(R.val("rewrite_feel")))
	# the player's own values (made different from the rewrite's)
	Rhythia.set("approach_rate", 25.4); Rhythia.set("spawn_distance", 9.7); Rhythia.set("fov", 77.0)
	Rhythia.set("parallax", 7.0); Rhythia.set("ui_parallax", 3.12); Rhythia.set("grid_parallax", 1.0)
	var mine = own()

	# off: nothing changes
	var g = yield(play(), "completed")
	ok("off: run uses own values", same(own(), mine) and !g.get_node("Spawn").rw_feel, own())
	yield(back(g), "completed")

	# the switch in Customize > Gameplay
	var menu = get_tree().current_scene
	var box = null
	for n in [menu]:
		var stack = [n]
		while !stack.empty():
			var x = stack.pop_back()
			if x.name == "RewriteFeel" and x is CheckBox: box = x
			for c in x.get_children(): stack.append(c)
	ok("switch in Gameplay settings", box != null)
	if box: box.pressed = true
	else: R.set_val("rewrite_feel", true)
	ok("switch saves the option", bool(R.val("rewrite_feel")))

	g = yield(play(), "completed")
	var sp = g.get_node("Spawn")
	var cam = g.get_parent().get_node_or_null("Camera")
	ok("on: rewrite values in the run", Rhythia.approach_rate == 30.0 and Rhythia.spawn_distance == 15.0 and Rhythia.fov == 70.0 and Rhythia.parallax == 10.0 and Rhythia.ui_parallax == 0.0 and Rhythia.grid_parallax == 0.0, own())
	ok("on: notes approach at 30", sp.approach_rate == 30.0 and sp.c_spawn_distance == 15.0, "%s / %s" % [sp.approach_rate, sp.c_spawn_distance])
	ok("on: camera FoV 70", cam != null and abs(cam.fov - 70.0) < 0.5, cam.fov if cam else "no camera")
	ok("on: rewrite fade + pushback (55 ms deep)", sp.rw_feel and abs(sp.grid_pushback - 1.65) < 0.001, "%s %s" % [sp.rw_feel, sp.grid_pushback])
	ok("on: own values kept in a file meanwhile", File.new().file_exists(F.FILE))
	shot("on")
	yield(back(g), "completed")
	ok("menu: own values back", same(own(), mine), own())
	ok("menu: file removed", !File.new().file_exists(F.FILE))

	# run cut off (game closed / crashed): the file brings them back on the next menu
	F.apply()
	Engine.remove_meta("rr_feel_saved")
	ok("cut-off run: values still swapped", Rhythia.approach_rate == 30.0)
	F.restore()
	ok("cut-off run: own values recovered", same(own(), mine) and !File.new().file_exists(F.FILE), own())

	if box: box.pressed = false
	else: R.set_val("rewrite_feel", false)
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
