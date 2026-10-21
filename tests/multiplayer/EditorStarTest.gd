extends Node
# Map editor: live star rating (Editor._star_*) = the map list's rating for the same notes, updates
# after edits / undo without stalling the editor, .phxm next to the editor's export.
# Maps: @@MAP1@@ (.sspm), @@MAP2@@ (a big .phxm). Output @@OUT@@/editor_stars.txt + es_*.png
const OUT = "@@OUT@@/editor_stars.txt"
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

func shot(n):
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/es_" + n + ".png")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

# waits until the editor shows a settled rating; returns [stars, worst frame ms]
func settled(e):
	var worst = 0.0
	var last = OS.get_ticks_usec()
	var t = 0.0
	while t < 20.0:
		yield(get_tree(), "idle_frame")
		var now = OS.get_ticks_usec()
		worst = max(worst, (now - last) / 1000.0)
		t += (now - last) / 1e6
		last = now
		if e.star_val >= 0 and e.star_due < 0 and !(e.star_thread and e.star_thread.is_active()) and e.star_rev == e.m.rev: break
	return [e.star_val, worst]

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if s is Song and s.filePath.get_file() == "@@MAP1@@": song = s
	var sc = load("res://mods/stars/StarCache.gd").get_instance(get_tree())
	var t = 0.0
	while sc.get_stars(song) < 0 and t < 20:
		yield(wait(0.25), "completed"); t += 0.25
	var list_stars = sc.get_stars(song)
	menu.open_editor(song)
	yield(wait(1.5), "completed")
	var e = menu.get_node_or_null("Editor")
	ok("editor open with the map", e != null and e.m != null and e.m.notes.size() == song.read_notes().size())
	var r = yield(settled(e), "completed")
	ok("live rating = the map list's rating", abs(r[0] - list_stars) < 0.01, "%.3f vs %.3f" % [r[0], list_stars])
	ok("label shows it", e.star_lbl.text.begins_with("★ %.2f" % list_stars), e.star_lbl.text)
	shot("open")
	# a burst of notes -> the rating goes up; undo -> back to the same number
	var add = []
	for i in 60: add.append([float(i % 3), float((i / 3) % 3), 1000 + i * 60])
	e.m.begin("burst")
	e.m.run(["add", add])
	e.m.end()
	yield(get_tree(), "idle_frame")
	ok("pending marker right after the edit", " ..." in e.star_lbl.text or e.star_due >= 0, e.star_lbl.text)
	r = yield(settled(e), "completed")
	out("after +60 notes: %.2f (worst frame %.1f ms)" % [r[0], r[1]])
	ok("rating rises after a dense burst", r[0] > list_stars + 0.05, "%.2f -> %.2f" % [list_stars, r[0]])
	ok("editing stays smooth while it rates (worst frame < 50 ms)", r[1] < 50.0, "%.1f ms" % r[1])
	e.m.undo()
	r = yield(settled(e), "completed")
	ok("undo brings the same rating back", abs(r[0] - list_stars) < 0.01, "%.3f" % r[0])
	# nps
	var nps = load("res://mods/replay/EditorModel.gd").nps([[0, 0, 0], [0, 0, 100], [0, 0, 200], [0, 0, 1500], [0, 0, 3000]])
	ok("nps: average + busiest second", abs(nps[0] - 5.0 / 3.0) < 0.01 and nps[1] == 3.0, nps)
	# a big map: rated on the worker, same number as the list
	var big = null
	var P = load("res://mods/fixes/Phxm.gd")
	big = P.import(Globals.p("user://maps/@@MAP2@@"))
	if big is Song:
		t = 0.0
		while sc.get_stars(big) < 0 and t < 30:
			yield(wait(0.25), "completed"); t += 0.25
		e.m.dirty = false # (no "discard unsaved changes?" prompt in the test)
		e.open_song(big)
		yield(wait(1.0), "completed")
		r = yield(settled(e), "completed")
		ok("big map (%d notes): live rating = list rating" % e.m.notes.size(), abs(r[0] - sc.get_stars(big)) < 0.01, "%.3f vs %.3f, worst frame %.1f ms" % [r[0], sc.get_stars(big), r[1]])
		e.m.begin("one")
		e.m.run(["add", [[1.0, 1.0, 5]]])
		e.m.end()
		r = yield(settled(e), "completed")
		ok("big map: editing stays smooth while it rates (worst frame < 50 ms)", r[1] < 50.0, "%.1f ms" % r[1])
		shot("big")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
