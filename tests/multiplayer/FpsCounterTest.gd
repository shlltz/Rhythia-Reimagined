extends Node
# FPS counter (replay/FpsCounter.gd): on the root from the menu on, "<n> FPS" in the top-right corner
# with a margin, updated (not stuck), the same node in a run and back in the menu, mouse clicks pass
# through it, Customize's switch hides / shows it, hidden while Replay Studio records a clip (hold).
# Map: @@MAP1@@. Output @@OUT@@/fps.txt + fps_menu.png, fps_game.png
const OUT = "@@OUT@@/fps.txt"
var passed = 0
var failed = 0

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func ok(what:String, cond:bool, info = ""):
	if cond: passed += 1
	else: failed += 1
	out("%s  %s  %s" % ["PASS" if cond else "FAIL", what, str(info)])

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func shot(name):
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png("@@OUT@@/" + name)

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func check_label(where:String, fc):
	var l:Label = fc.label
	var vp = get_viewport().get_visible_rect().size
	var r = l.get_global_rect()
	var re = RegEx.new()
	re.compile("^[0-9]+ FPS$")
	ok(where + ": text is '<n> FPS'", re.search(l.text) != null, l.text)
	ok(where + ": right edge 4-20 px from the screen edge", vp.x - r.end.x >= 4 and vp.x - r.end.x <= 20, vp.x - r.end.x)
	ok(where + ": top 2-16 px from the top", r.position.y >= 2 and r.position.y <= 16, r.position.y)
	ok(where + ": clicks pass through", l.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	ok(where + ": shown", l.is_visible_in_tree())

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var t = 0.0
	while t < 30:
		yield(wait(0.25), "completed"); t += 0.25
		var sc = get_tree().current_scene
		if !sc or sc.name != "Menu": continue
		var tm = sc.get_node_or_null("TitleMenu")
		if tm and tm.visible:
			tm._close("")
			yield(wait(1.0), "completed")
		break
	var fc = get_tree().root.get_node_or_null("FpsCounter")
	ok("counter on the root", fc != null)
	if !fc:
		out("== totals: %d passed, %d failed" % [passed, failed]); OS.kill(OS.get_process_id()); return
	yield(wait(1.0), "completed")
	check_label("menu", fc)
	# (a cap set here doesn't hold: the settings page puts the player's own value back every frame)
	var agree = 0
	var seen = {}
	for i in 6:
		yield(wait(0.5), "completed")
		seen[fc.label.text] = true
		var n = float(fc.label.text.split(" ")[0])
		var e = float(Engine.get_frames_per_second())
		if e > 0 and abs(n - e) / e < 0.15: agree += 1
	ok("matches the engine's own frame count (within 15%, 5 of 6 reads)", agree >= 5, [agree, fc.label.text, Engine.get_frames_per_second()])
	ok("updates (not stuck on one number)", seen.size() > 1, seen.keys())
	yield(shot("fps_menu.png"), "completed")
	var R = load("res://mods/replay/Reimagined.gd")
	var was = R.val("show_fps")
	R.cfg()["show_fps"] = false
	fc.set_shown(false)
	yield(wait(0.6), "completed")
	ok("switch off hides it", !fc.label.visible)
	R.cfg()["show_fps"] = true
	fc.set_shown(true)
	yield(wait(0.6), "completed")
	ok("switch on shows it again with a number", fc.label.visible and fc.label.text.ends_with("FPS"), fc.label.text)
	fc.hold(true)
	ok("hold (clip recording) hides it", !fc.label.visible)
	fc.hold(false)
	ok("hold released shows it", fc.label.visible)
	R.cfg()["show_fps"] = was
	# in a run
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	Rhythia.select_song(song)
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = ""
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var g = null
	var t0 = OS.get_ticks_msec()
	while OS.get_ticks_msec() - t0 < 60000 and !g:
		yield(get_tree(), "idle_frame")
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game") and sc.get_node("Game").has_node("Spawn") and sc.get_node("Game/Spawn").active: g = sc.get_node("Game")
	yield(wait(2.0), "completed")
	ok("same counter in the run", get_tree().root.get_node_or_null("FpsCounter") == fc)
	check_label("run", fc)
	yield(shot("fps_game.png"), "completed")
	get_tree().paused = true # (pause menu / end of a map pause the tree: it keeps counting)
	var before = fc.label.text
	yield(wait(1.0), "completed")
	ok("keeps counting while the tree is paused", fc.label.text.ends_with("FPS"), [before, fc.label.text])
	get_tree().paused = false
	if is_instance_valid(g): g.end(Globals.END_GIVEUP)
	t = 0.0
	while t < 20 and !(get_tree().current_scene and get_tree().current_scene.name == "Menu"):
		yield(wait(0.25), "completed"); t += 0.25
	yield(wait(1.0), "completed")
	ok("back in the menu: one counter", get_tree().root.get_node_or_null("FpsCounter") == fc and get_tree().root.get_children().count(fc) == 1)
	var cnt = 0
	for c in get_tree().root.get_children():
		if c.name.begins_with("FpsCounter"): cnt += 1
	ok("no second counter after the menu reloaded", cnt == 1, cnt)
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
