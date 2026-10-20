extends Node
# single-player regression: a normal (autoplay) run still ends on the results screen, records a
# recent play, keeps Retry / quick retry, and nothing multiplayer is involved
const OUT = "@@OUT@@/solo.txt"
var passed = 0
var failed = 0
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")
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
func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
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
	ok("solo game started", g != null)
	yield(wait(3.0), "completed")
	ok("spawn active without any lobby", g and g.get_node("Spawn").active)
	ok("no multiplayer node", !get_tree().root.has_node("RRMultiplayer"))
	ok("quick retry available", g and g.get_node("Spawn").find_node("*", false, false) != null)
	var qr = false
	for c in g.get_node("Spawn").get_children():
		if c.get_script() and "QuickRetry" in str(c.get_script().resource_path): qr = true
	ok("QuickRetry node present", qr)
	g.end(Globals.END_GIVEUP)
	t = 0.0
	while t < 20 and !get_tree().root.has_node("Menu/ResultsScreen"):
		yield(wait(0.25), "completed"); t += 0.25
	ok("results screen after a solo run", get_tree().root.has_node("Menu/ResultsScreen"))
	ok("no multiplayer screen", !get_tree().root.has_node("Menu/Multiplayer"))
	var rp = load("res://mods/stars/RecentPlays.gd")
	var f = File.new()
	ok("recent play recorded", f.file_exists("user://recent_plays.json"))
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
