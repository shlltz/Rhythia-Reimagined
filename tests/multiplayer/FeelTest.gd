extends Node
# Rewrite Feel was removed in 2.5.0: no switch in the settings, runs use the player's own values,
# and the restore file an old cut-off run left behind still gives the player's values back
# (replay/RewriteFeel.gd restore(), run by Boot.gd / menu2).
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
	ok("no rewrite_feel option any more", !R.DEFAULTS.has("rewrite_feel"))
	var menu = get_tree().current_scene
	var box = null
	var stack = [menu]
	while !stack.empty():
		var x = stack.pop_back()
		for c in x.get_children(): stack.append(c)
		if x.name == "RewriteFeel": box = x
	ok("no Rewrite Feel switch in the settings", box == null)
	var mine = own()
	var g = yield(play(), "completed")
	ok("a run uses the player's own values", g != null and same(own(), mine), own())
	if g: yield(back(g), "completed")
	# an old cut-off run's file: the player's values come back, the file goes
	var F = load("res://mods/replay/RewriteFeel.gd")
	var keep = own()
	var theirs = {}
	for k in KEYS: theirs[k] = float(keep[k]) + 1.0
	var f = File.new()
	f.open(F.FILE, File.WRITE)
	f.store_string(to_json(theirs))
	f.close()
	for k in KEYS: Rhythia.set(k, 30.0)
	F.restore()
	ok("a leftover restore file gives the values back and goes", same(own(), theirs) and !File.new().file_exists(F.FILE), own())
	for k in KEYS: Rhythia.set(k, keep[k])
	if Rhythia.has_method("save_settings"): Rhythia.save_settings()
	F.restore()
	ok("no file: nothing changes", same(own(), keep))
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
