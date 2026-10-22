extends Node
# .phxm import (fixes/Phxm.gd): .phxm files made by phxm_fixtures.py from @@MAP1@@ (copied into the
# maps folder next to it) must give the same notes as the .sspm itself. Also deflated / nested zips,
# quantum positions, ids, duplicates, a broken file, a rewrite map folder, drag-and-drop on both
# menus and the import screen. Output @@OUT@@/phxm.txt
const OUT = "@@OUT@@/phxm.txt"
var passed = 0
var failed = 0
var P
var dir

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

func notes_of(s) -> Array:
	var n = s.read_notes().duplicate()
	n.sort_custom(self, "_by_ms")
	return n

func _by_ms(a, b):
	return a[2] < b[2] or (a[2] == b[2] and (a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])))

# [x, y, ms] lists equal (positions to 1e-4)
func same(a:Array, b:Array) -> String:
	if a.size() != b.size(): return "count %d vs %d" % [a.size(), b.size()]
	for i in a.size():
		if int(a[i][2]) != int(b[i][2]) or abs(a[i][0] - b[i][0]) > 1e-4 or abs(a[i][1] - b[i][1]) > 1e-4:
			return "note %d: %s vs %s" % [i, str(a[i]), str(b[i])]
	return ""

func sspm_count() -> int:
	var n = 0
	var d = Directory.new()
	d.open(dir)
	d.list_dir_begin(true, true)
	var f = d.get_next()
	while f != "":
		if f.ends_with(".sspm"): n += 1
		f = d.get_next()
	d.list_dir_end()
	return n

func b64(b:PoolByteArray) -> String:
	return Marshalls.raw_to_base64(b)

func run_btn(menu):
	var stack = [menu]
	while !stack.empty():
		var n = stack.pop_back()
		if n.get_script() and str(n.get_script().resource_path).ends_with("RunMapButton.gd"): return n
		for c in n.get_children(): stack.append(c)
	return null

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	P = load("res://mods/fixes/Phxm.gd")
	ok("Phxm.gd installed", P != null)
	dir = Globals.p("user://maps/")
	var orig = Song.new()
	orig.load_from_sspm(dir + "@@MAP1@@")
	var on = notes_of(orig)
	out("original: %s, %d notes, difficulty %d" % [orig.id, on.size(), orig.difficulty])

	var t0 = OS.get_ticks_usec()
	var r = P.import(dir + "t_stored.phxm")
	out("stored import: %.1f ms" % ((OS.get_ticks_usec() - t0) / 1000.0))
	ok("stored zip imports", r is Song, r)
	if r is Song:
		ok("id from metadata", r.id == "phxm_test_stored", r.id)
		ok("saved as .sspm", File.new().file_exists(dir + "phxm_test_stored.sspm"))
		ok("in the library", Rhythia.registry_song.get_item("phxm_test_stored") != null)
		ok("notes = the original .sspm's", same(notes_of(r), on) == "", same(notes_of(r), on))
		ok("name = Artist - Title", r.name == "DunkMemer - Dancing Roach Autotune", r.name)
		ok("mapper", r.creator == "BatBrice", r.creator)
		ok("difficulty", r.difficulty == orig.difficulty, "%d vs %d" % [r.difficulty, orig.difficulty])
		ok("default difficulty name not stored", !r.custom_data.has("difficulty_name"), r.custom_data)
		var c = r.cover
		ok("cover", r.has_cover and c != null and c.get_width() == 64 and c.get_height() == 48, str(c.get_size()) if c else "none")
		var st = r.stream()
		ok("audio plays", st is AudioStreamMP3 and st != Globals.error_sound and st.get_length() > 1.0, st)
	ok("temp audio cleaned up", !File.new().file_exists(Globals.p(P.TMP) + "/phxm_test_stored.mp3"))

	r = P.import(dir + "t_deflate.phxm")
	ok("deflated zip in a subfolder (+ video entry) imports", r is Song, r)
	if r is Song:
		ok("id cleaned (Roach Deflate! -> roach_deflate_)", r.id == "roach_deflate_", r.id)
		ok("notes (deflated)", same(notes_of(r), on) == "", same(notes_of(r), on))
		ok("custom difficulty name kept", r.custom_data.get("difficulty_name") == "Expert+", r.custom_data)

	r = P.import(dir + "t_quantum.phxm")
	ok("quantum map imports", r is Song, r)
	if r is Song:
		var want = [[1.5, 1.25, 1000], [2.0, 0.0, 1500], [0.0, 2.0, 2000], [1.3333, 0.25, 2500]]
		ok("quantum / grid positions (rewrite X+1, 1-Y)", same(notes_of(r), want) == "", same(notes_of(r), want))

	r = P.import(dir + "t_jp.phxm")
	ok("non-latin ID -> phxm_<hash>", r is Song and r.id.begins_with("phxm_") and r.id.length() == 17, r.id if r is Song else r)

	var before = sspm_count()
	r = P.import(dir + "t_dup.phxm")
	ok("same map as an installed .sspm: no duplicate", r is Song and r.id == orig.id and sspm_count() == before, "%s, %d -> %d" % [r.id if r is Song else r, before, sspm_count()])

	r = P.import(dir + "t_broken.phxm")
	ok("broken file -> error message", r is String, r)
	out("  (" + str(r) + ")")

	# map browser: .phxm downloads (offline: the install step on a downloaded file)
	var mbs = load("res://mods/browser/MapBrowser.gd")
	if mbs:
		ok("browser: file type from the link", mbs._map_ext("https://x/m/Map.PHXM?t=1") == "phxm" and mbs._map_ext("https://x/a.rhm") == "rhm" and mbs._map_ext("https://x/a.sspm") == "sspm")
		var mb = mbs.new()
		var res = mb._install_phxm({"id": 77}, dir + "t_stored.phxm")
		ok("browser: .phxm installed as rhythia_<id>", res == "rhythia_77" and Rhythia.registry_song.get_item("rhythia_77") != null, res)
		mb.free()
	# a rewrite map folder (its maps folder keeps every map unpacked)
	var fd = Globals.p("user://phxm_dir")
	Directory.new().make_dir_recursive(fd)
	var files = P._read_zip(dir + "t_stored.phxm")
	for k in files:
		var data = files[k]
		if k == "metadata.json":
			var m = parse_json(data.get_string_from_utf8())
			m.ID = "phxm_test_dir"
			data = to_json(m).to_utf8()
		var f = File.new()
		f.open(fd + "/" + k, File.WRITE)
		f.store_buffer(data)
		f.close()
	ok("folder recognised", P.is_map(fd))
	ok("non-map path not recognised", !P.is_map(dir + "@@MAP1@@") and !P.is_map(Globals.p("user://")))
	r = P.import(fd)
	ok("rewrite map folder imports", r is Song and r.id == "phxm_test_dir", r.id if r is Song else r)
	if r is Song: ok("notes (folder)", same(notes_of(r), on) == "", same(notes_of(r), on))

	# ---- export: back to the rewrite's format, and round trips
	var keys = ["ID", "Artist", "ArtistLink", "ArtistPlatform", "Title", "Rating", "Mappers", "Difficulty", "DifficultyName", "Length", "HasAudio", "HasCover", "HasVideo", "AudioExt"]
	t0 = OS.get_ticks_usec()
	var ex = P.export(orig, "@@OUT@@/x_orig.phxm")
	out("export: %.1f ms" % ((OS.get_ticks_usec() - t0) / 1000.0))
	ok("export: .sspm -> .phxm", ex is Dictionary, ex)
	if ex is Dictionary:
		var z = P._read_zip(ex.path)
		ok("export: zip readable, entries", z is Dictionary and z.has("metadata.json") and z.has("objects.phxmo") and z.has("audio.mp3") and (z.has("cover.png") == orig.has_cover), z.keys() if z is Dictionary else z)
		var md = parse_json(z["metadata.json"].get_string_from_utf8())
		var ks = md.keys()
		ks.sort()
		var want_k = keys.duplicate()
		want_k.sort()
		ok("export: metadata keys = the rewrite's", str(ks) == str(want_k), ks)
		ok("export: metadata values", md.ID == orig.id and md.Artist == "DunkMemer" and md.Title == "Dancing Roach Autotune" and str(md.Mappers) == str(["BatBrice"]) and int(md.Difficulty) == orig.difficulty + 1 and md.AudioExt == "mp3" and int(md.Length) == int(on[-1][2]), md)
		r = P.import(ex.path, "x_orig_back")
		ok("export -> import: same notes", r is Song and same(notes_of(r), on) == "", same(notes_of(r), on) if r is Song else r)
	# effects + extra metadata survive import -> export
	var src = P._read_zip(dir + "t_fx.phxm")
	var src_md = parse_json(src["metadata.json"].get_string_from_utf8())
	var src_obj = P.parse_objects(src["objects.phxmo"])
	r = P.import(dir + "t_fx.phxm")
	ok("fx map imports", r is Song, r)
	ok("fx: effects counted", P.effect_report(src_obj.tail).hash() == {"brightness": 1, "text": 1}.hash(), P.effect_report(src_obj.tail))
	if r is Song:
		ex = P.export(r, "@@OUT@@/x_fx.phxm")
		ok("fx: export", ex is Dictionary, ex)
		if ex is Dictionary:
			out("  warnings: " + str(ex.warnings))
			var z = P._read_zip(ex.path)
			var md = parse_json(z["metadata.json"].get_string_from_utf8())
			var o = P.parse_objects(z["objects.phxmo"])
			ok("fx: effect sections byte-identical", b64(o.tail) == b64(src_obj.tail), "%d vs %d bytes" % [o.tail.size(), src_obj.tail.size()])
			var diffs = []
			for k in keys:
				if k != "Length" and str(md.get(k)) != str(src_md.get(k)): diffs.append("%s: %s vs %s" % [k, md.get(k), src_md.get(k)])
			ok("fx: metadata round trip (rating, link, platform, mappers, difficulty name, artist / title)", diffs.empty(), diffs)
			ok("fx: same notes", same(notes_of(P.import(ex.path, "x_fx_back")), on) == "")
			ok("fx: the export says what can't play here", str(ex.warnings).find("brightness") != -1)
		# renamed after the import: the new name is what gets exported
		r.name = "New Artist - New Title"
		ex = P.export(r, "@@OUT@@/x_renamed.phxm")
		if ex is Dictionary:
			var md = parse_json(P._read_zip(ex.path)["metadata.json"].get_string_from_utf8())
			ok("renamed: artist / title from the new name", md.Artist == "New Artist" and md.Title == "New Title", md)
	# a timing point (no layout defined anywhere): reported as unknown, kept byte for byte
	src = P._read_zip(dir + "t_tp.phxm")
	src_obj = P.parse_objects(src["objects.phxmo"])
	ok("timing point: reported as unknown layout", P.effect_report(src_obj.tail).has("unknown"), P.effect_report(src_obj.tail))
	r = P.import(dir + "t_tp.phxm")
	if r is Song:
		ex = P.export(r, "@@OUT@@/x_tp.phxm")
		ok("timing point: kept byte for byte", ex is Dictionary and b64(P.parse_objects(P._read_zip(ex.path)["objects.phxmo"]).tail) == b64(src_obj.tail))
	# quantum / off-grid positions survive both ways
	src = P._read_zip(dir + "t_rtq.phxm")
	r = P.import(dir + "t_rtq.phxm")
	if r is Song:
		ex = P.export(r, "@@OUT@@/x_rtq.phxm")
		var back = P.import(ex.path, "x_rtq_back") if ex is Dictionary else null
		ok("quantum: round trip", back is Song and same(notes_of(back), notes_of(r)) == "", same(notes_of(back), notes_of(r)) if back is Song else ex)
		if ex is Dictionary:
			var a = P._read_zip(ex.path)["objects.phxmo"]
			var b = src["objects.phxmo"]
			ok("quantum: grid / quantum flags as the rewrite writes them", a.size() == b.size() and a[8 + 4] == b[8 + 4] and a[8 + 4 + 5 + 8] == b[8 + 4 + 5 + 8], "%d vs %d bytes" % [a.size(), b.size()])

	# drag and drop: new menu
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	yield(wait(1.0), "completed")
	var b = run_btn(menu)
	ok("run button (new menu)", b != null)
	if b:
		b.files_dropped(PoolStringArray([dir + "t_drop.phxm"]), 0)
		yield(wait(1.0), "completed")
		ok("drop: map imported + selected (new menu)", Rhythia.selected_song and Rhythia.selected_song.id == "phxm_test_drop", Rhythia.selected_song.id if Rhythia.selected_song else "none")
		ok("drop: song page shown", menu.get_node("Main/Maps/Results").visible)
		ok("drop: file in the game folder kept", File.new().file_exists(dir + "t_drop.phxm"))
	# classic menu
	get_tree().change_scene("res://scenes/menu/oldmenu2.tscn")
	yield(wait(3.0), "completed")
	menu = get_tree().current_scene
	load("res://mods/replay/Classic.gd").show_page(menu, "maps")
	yield(wait(1.0), "completed")
	b = run_btn(menu)
	ok("run button (classic menu)", b != null)
	if b:
		b.files_dropped(PoolStringArray([dir + "t_drop2.phxm"]), 0)
		yield(wait(1.0), "completed")
		ok("drop: map imported + selected (classic)", Rhythia.selected_song and Rhythia.selected_song.id == "phxm_test_drop2", Rhythia.selected_song.id if Rhythia.selected_song else "none")
		ok("drop: classic song page shown", menu.get_node("Main/Results").visible)
		var k = InputEventKey.new()
		k.scancode = KEY_A
		k.pressed = true
		Input.parse_input_event(k)
		k = k.duplicate()
		k.pressed = false
		Input.parse_input_event(k)
		yield(wait(0.5), "completed")
		ok("key on the classic song page: still there", get_tree().current_scene == menu and !b.has_been_pressed)
	# import screen
	get_tree().change_scene("res://scenes/menu/contentmgr.tscn")
	yield(wait(2.0), "completed")
	var a = get_tree().current_scene.get_node("AddSong")
	ok("import screen mentions .phxm", ".phxm" in a.get_node("SelectType/sspm/Describe").text, a.get_node("SelectType/sspm/Describe").text)
	a.opening = a.FO_SSPM
	a.file_selected(PoolStringArray([dir + "t_broken.phxm"]))
	yield(wait(0.3), "completed")
	ok("import screen: broken .phxm shows the error", a.get_node("Finish/Error").visible and a.get_node("Finish/Error").text != "", a.get_node("Finish/Error").text)
	a.get_node("Finish").visible = false
	a.get_node("Finish/Error").visible = false
	a.opening = a.FO_SSPM
	a.file_selected(PoolStringArray([dir + "t_dialog.phxm"]))
	yield(wait(0.5), "completed")
	ok("import screen: .phxm opens the edit page", a.get_node("Edit").visible and a.song and a.song.id == "phxm_test_dialog", a.song.id if a.song else "none")
	ok("import screen: cover shown", a.get_node("Edit/Cover/T").texture == a.song.cover)
	a.finish_map()
	yield(wait(1.5), "completed")
	ok("import screen: finished", a.get_node("Finish/Success").visible, a.get_node("Finish/Error").text)
	var s = Rhythia.registry_song.get_item("phxm_test_dialog")
	ok("import screen: map in the library with its notes", s != null and same(notes_of(s), on) == "", same(notes_of(s), on) if s else "missing")
	shot("import")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())

func shot(n):
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/p_" + n + ".png")
