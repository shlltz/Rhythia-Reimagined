extends Node
# Library tools (replay/Library.gd, LibraryPanel.gd, RewriteImport.gd): tags + tag= search, smart
# playlists from (seeded) play history, duplicate finder, bulk rename + undo (byte-identical),
# cleanup preview, the rewrite folder importer (statuses, merge of archive + unpacked copy, import,
# frame times while it runs) and every panel tab. Maps: @@MAP1@@ (.sspm), then the phxm fixtures
# (t_*.phxm) and a real rewrite map (@@MAP2@@ onwards are copied into a fake rewrite folder).
# Output @@OUT@@/library.txt + l_*.png
const OUT = "@@OUT@@/library.txt"
var passed = 0
var failed = 0
var L
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

func shot(n):
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/l_" + n + ".png")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func song(id):
	var s = Rhythia.registry_song.get_item(id)
	return s if s is Song else null

# the same notes written again by this game under another map id (different bytes, same notes)
func copy_map(src_id:String, new_id:String):
	var s = Song.new()
	s.load_from_sspm(song(src_id).filePath)
	s.id = new_id
	s.read_notes()
	var r = s.convert_to_sspm()
	if str(r) != "Converted!": return r
	return Rhythia.registry_song.add_sspm_map(dir + new_id + ".sspm")

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	L = load("res://mods/replay/Library.gd")
	dir = Globals.p("user://maps/")
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	var roach = ""
	for s in Rhythia.registry_song.get_items():
		if s is Song and s.filePath.get_file() == "@@MAP1@@": roach = s.id
	ok("library has the test map", song(roach) != null, roach)

	# ---- duplicates: an exact copy under another file name + a different map with the same title
	ok("re-encoded copy", copy_map(roach, "lib_exact_copy") is Song)
	Directory.new().copy(song(roach).filePath, dir + "lib_hidden_copy.sspm") # (same id inside: the library shows only one)
	var P = load("res://mods/fixes/Phxm.gd")
	ok("fixture map imported", P.import(dir + "t_stored.phxm") is Song)
	var variant = P.import(dir + "t_quantum.phxm", "lib_variant") # (notes differ)
	if variant is Song:
		variant.name = song(roach).name # same title, different notes: "possible" only if the length is close
	out("variant: " + str(variant))
	var job = L.scan_duplicates()
	out("scan started")
	var t0 = OS.get_ticks_msec()
	var groups = yield(job, "done")
	out("duplicate scan: %d maps in %d ms" % [L.local_maps().size(), OS.get_ticks_msec() - t0])
	var exact = null
	for g in groups:
		if g.kind == "exact" and g.ids.has(roach): exact = g
	ok("exact duplicate: same notes written by another program", exact != null and exact.ids.has("lib_exact_copy"), groups)
	ok("exact duplicate: the .phxm import of the same map", exact != null and exact.ids.has("phxm_test_stored"))
	if exact == null or !exact.ids.has("phxm_test_stored"):
		for g in groups:
			for it in g.items: out("  %s %s %s" % [it.id, it.key, it.path])
	var hidden = false
	if exact:
		for it in exact.items:
			if it.path.ends_with("lib_hidden_copy.sspm") and !it.in_library: hidden = true
	var dup_paths = {}
	var twice = false
	for g in groups:
		for it in g.items:
			if g.kind == "exact" and dup_paths.has(it.path): twice = true
			dup_paths[it.path] = true
	ok("each file listed once", !twice)
	ok("exact duplicate: a file the library hides (same id) is listed", hidden)
	var possible = false
	for g in groups:
		if g.kind == "possible": possible = true
	ok("different notes are never exact", !(exact and exact.ids.has("lib_variant")))
	out("  groups: " + str(groups.size()) + (", possible: yes" if possible else ""))
	t0 = OS.get_ticks_msec()
	job = L.scan_duplicates()
	groups = yield(job, "done")
	out("second scan (cached fingerprints): %d ms" % (OS.get_ticks_msec() - t0))

	# ---- tags + the map list's tag= filter
	var n = L.tag_maps([roach, "lib_exact_copy"], "Training", true)
	ok("tags added", n == 2 and str(L.tags_of(roach)) == str(["training"]) and L.all_tags().get("training") == 2, L.all_tags())
	ok("tag saved to disk", File.new().file_exists(Globals.p(L.TAGS_FILE)))
	var ml = load("res://mods/replay/Classic.gd").map_list(menu)
	ok("map list found", ml != null)
	if ml:
		ml.search_text = "tag=train"
		ml._rr_parse_search()
		ok("search tag=train matches the tagged map only", ml._rr_search_match(song(roach)) and !ml._rr_search_match(song("phxm_test_stored")), ml.rr_q_filters)
		ml.search_text = ""
	n = L.tag_maps(["lib_exact_copy"], "training", false)
	ok("tag removed", n == 1 and L.tags_of("lib_exact_copy").empty())

	# ---- smart playlists from history (seeded recent_plays: the test's own user data)
	var now = OS.get_unix_time()
	var rp = {roach: [{"t": now - 2 * 86400, "passed": false, "score": 1}, {"t": now - 3600, "passed": true, "score": 2}],
		"phxm_test_stored": [{"t": now - 20 * 86400, "passed": false, "score": 1}]}
	var f = File.new()
	f.open(Globals.p("user://recent_plays.json"), File.WRITE)
	f.store_string(to_json(rp))
	f.close()
	var failed_week = L.smart_eval({"name": "x", "failed_days": 7, "sort": "last_played"})
	var ids = []
	for s in failed_week: ids.append(s.id)
	ok("smart: failed in the last 7 days = the map failed 2 days ago only", str(ids) == str([roach]), ids)
	var unplayed = L.smart_eval({"name": "x", "played": "unplayed"})
	var un_ids = {}
	for s in unplayed: un_ids[s.id] = true
	ok("smart: unplayed leaves out played maps", !un_ids.has(roach) and !un_ids.has("phxm_test_stored") and un_ids.has("lib_exact_copy"), un_ids.keys())
	var most = L.smart_eval({"name": "x", "played": "played", "sort": "plays"})
	ok("smart: most played first", most.size() >= 2 and most[0].id == roach, most)
	Rhythia.favorite_songs.append("phxm_test_stored")
	var fav = L.smart_eval({"name": "x", "favorites": true})
	ok("smart: favorites", fav.size() == 1 and fav[0].id == "phxm_test_stored")
	Rhythia.favorite_songs.erase("phxm_test_stored")
	var untagged = L.smart_eval({"name": "x", "untagged": true})
	var ut = {}
	for s in untagged: ut[s.id] = true
	ok("smart: untagged leaves out tagged", !ut.has(roach) and ut.has("lib_exact_copy"))
	var sc = load("res://mods/stars/StarCache.gd").get_instance(get_tree())
	var tt = 0.0
	while sc.get_stars(song(roach)) < 0 and tt < 20:
		yield(wait(0.25), "completed"); tt += 0.25
	var st = sc.get_stars(song(roach))
	var in_range = L.smart_eval({"name": "x", "stars_min": st - 0.01, "stars_max": st + 0.01})
	var ir = []
	for s in in_range: ir.append(s.id)
	ok("smart: star range uses the real ratings", ir.has(roach), "%.2f stars: %s" % [st, ir])
	# the map list filter
	L.smart_lists().append({"name": "Test failed", "failed_days": 7})
	L.save_smart()
	load("res://mods/replay/Reimagined.gd").set_val("collection", L.SMART_PREFIX + "Test failed")
	get_tree().call_group("rr_collections", "_rr_collections_changed")
	yield(wait(0.5), "completed")
	if ml: ok("map list: smart playlist filter", ml.rr_coll != null and ml.rr_coll.has(roach) and ml.rr_coll.size() == 1, ml.rr_coll)
	load("res://mods/replay/Reimagined.gd").set_val("collection", "")
	get_tree().call_group("rr_collections", "_rr_collections_changed")

	# ---- bulk rename + undo
	var a = song("lib_exact_copy")
	var b = song("phxm_test_stored")
	var md5a = File.new().get_md5(a.filePath)
	var md5b = File.new().get_md5(b.filePath)
	var old_a = a.name
	var plan = L.rename_plan([a, b], "{title} [{mapper}]")
	ok("rename plan: names + collision renumbered", plan.size() == 2 and plan[0].new == "Dancing Roach Autotune [BatBrice]" and plan[1].new == "Dancing Roach Autotune [BatBrice] (2)" and plan[1].status == "collision", [plan[0].new, plan[1].new, plan[1].status])
	ok("rename plan: nothing written yet", File.new().get_md5(a.filePath) == md5a)
	t0 = OS.get_ticks_msec()
	var res = L.rename_apply(plan)
	out("rename of 2 maps: %d ms" % (OS.get_ticks_msec() - t0))
	ok("rename applied", res.done == 2 and res.failed.empty(), res)
	ok("renamed in the library (re-read from the file)", song("lib_exact_copy").name == "Dancing Roach Autotune [BatBrice]" and song("phxm_test_stored").name == "Dancing Roach Autotune [BatBrice] (2)", [song("lib_exact_copy").name, song("phxm_test_stored").name])
	ok("renamed map keeps its notes", song("lib_exact_copy").read_notes().size() == song(roach).read_notes().size())
	ok("files really changed", File.new().get_md5(song("lib_exact_copy").filePath) != md5a)
	var js = L.journals()
	ok("journal written", js.size() == 1 and js[0].rows.size() == 2)
	res = L.undo(js[0].id)
	ok("undo restores", res.restored == 2 and res.failed.empty(), res)
	ok("undo: files byte-identical to before", File.new().get_md5(song("lib_exact_copy").filePath) == md5a and File.new().get_md5(song("phxm_test_stored").filePath) == md5b)
	ok("undo: old names back", song("lib_exact_copy").name == old_a)
	ok("undo: journal closed", L.journals().empty())

	# ---- cleanup preview (only caches / leftovers)
	Directory.new().make_dir_recursive(Globals.p("user://cache/rhythia_covers"))
	f.open(Globals.p("user://cache/rhythia_covers/x.png"), File.WRITE); f.store_buffer(PoolByteArray([1, 2, 3])); f.close()
	var cp = L.cleanup_plan()
	var labels = []
	for e in cp: labels.append(e.label)
	ok("cleanup lists the cover cache", "Map browser cover thumbnails" in labels, labels)
	var never = true
	for e in cp:
		for bad in ["/maps", "/replays", "/bests", "settings"]:
			if e.path.ends_with(bad): never = false
	ok("cleanup never lists maps / replays / scores / settings", never)
	for e in cp:
		if e.label == "Map browser cover thumbnails": ok("cleanup removes (test: no recycle bin)", L.cleanup_apply(e, false) == 0 and !File.new().file_exists(Globals.p("user://cache/rhythia_covers/x.png")))
	var stats = L.stats()
	ok("stats", stats.maps == L.local_maps().size() and stats.maps_dir[0] > 0, "%d maps, %s" % [stats.maps, L.human_bytes(stats.maps_dir[0])])

	# ---- rewrite folder importer: maps/<set>/*.phxm + cache/maps/<id>/ (unpacked copy)
	var rw = Globals.p("user://fake_rewrite")
	var d = Directory.new()
	d.make_dir_recursive(rw + "/maps/default")
	d.make_dir_recursive(rw + "/maps/pack two")
	d.make_dir_recursive(rw + "/cache/maps/phxm_test_fx")
	for fn in ["t_fx.phxm", "t_jp.phxm", "t_dup.phxm", "t_stored.phxm", "t_broken.phxm"]: d.copy(dir + fn, rw + "/maps/default/" + fn)
	var real = []
	var dd = Directory.new()
	dd.open(dir)
	dd.list_dir_begin(true, true)
	var fn2 = dd.get_next()
	while fn2 != "":
		if fn2.ends_with(".phxm") and !fn2.begins_with("t_") and !fn2.begins_with("x_"): real.append(fn2)
		fn2 = dd.get_next()
	dd.list_dir_end()
	for fn in real: d.copy(dir + fn, rw + "/maps/pack two/" + fn)
	var files = P._read_zip(dir + "t_fx.phxm")
	for k in files:
		f.open(rw + "/cache/maps/phxm_test_fx/" + k, File.WRITE); f.store_buffer(files[k]); f.close()
	var imp = load("res://mods/replay/RewriteImport.gd").new()
	add_child(imp)
	imp.scan(rw)
	var rows = yield(imp, "scanned")
	var by = {}
	for r in rows: by[r.get("id", r.path.get_file())] = r
	out("scan rows: " + str(rows.size()))
	ok("scan: archive + unpacked copy merged (archive kept)", by.has("phxm_test_fx") and by.phxm_test_fx.kind == "phxm", by.keys())
	ok("scan: already installed", by.has(roach) and by[roach].status == "installed", by.get(roach))
	ok("scan: broken file reported", by.has("t_broken.phxm") and by["t_broken.phxm"].has("error"))
	ok("scan: new map", by.has("phxm_test_fx") and by.phxm_test_fx.status in ["new", "possible duplicate"], by.get("phxm_test_fx"))
	var to_import = []
	for r in rows:
		if r.get("status", "") in ["new", "possible duplicate"]: to_import.append(r)
	# frame times while importing (the work is on the worker)
	var worst = 0.0
	var frames = 0
	imp.import_rows(to_import)
	var last = OS.get_ticks_usec()
	var rep = null
	imp.connect("imported", self, "_got", [], CONNECT_ONESHOT)
	got = null
	var start_u = last
	var worst_at = 0.0
	var long_frames = []
	while got == null:
		yield(get_tree(), "idle_frame")
		var now_u = OS.get_ticks_usec()
		var ft = (now_u - last) / 1000.0
		last = now_u
		if got != null: # (this frame ran the end-of-import refresh: reported below, not part of the import)
			if ft > 50: long_frames.append("%.0f ms at +%.0f ms (list refresh after the import)" % [ft, (now_u - start_u) / 1000.0])
			break
		if ft > 50: long_frames.append("%.0f ms at +%.0f ms" % [ft, (now_u - start_u) / 1000.0])
		worst = max(worst, ft)
		frames += 1
	for k in 30: # (and after it: the list refresh / ratings)
		yield(get_tree(), "idle_frame")
		var now_u = OS.get_ticks_usec()
		var ft = (now_u - last) / 1000.0
		if ft > 50: long_frames.append("%.0f ms at +%.0f ms (list refresh after the import)" % [ft, (now_u - start_u) / 1000.0])
		last = now_u
	rep = got
	out("  frames over 50 ms: " + str(long_frames))
	out("import of %d maps: %.1f s, %d frames, worst frame %.1f ms (main thread: %.1f ms per map at most, %.1f ms list refresh)" % [to_import.size(), rep.ms / 1000.0, frames, worst, rep.get("main_ms", -1), rep.get("refresh_ms", -1)])
	ok("import: all ticked maps imported", rep.imported.size() == to_import.size() and rep.failed.empty(), "%d / %d, failed %s" % [rep.imported.size(), to_import.size(), rep.failed])
	ok("import: maps in the library", song("phxm_test_fx") != null)
	ok("import: the menu kept running while it imported (worst frame < 100 ms)", worst < 100.0, "%.1f ms" % worst)
	ok("import: source folder untouched", File.new().file_exists(rw + "/maps/default/t_fx.phxm") and File.new().file_exists(rw + "/cache/maps/phxm_test_fx/objects.phxmo"))
	imp.scan(rw)
	rows = yield(imp, "scanned")
	var still_new = 0
	for r in rows:
		if r.get("status", "") == "new": still_new += 1
	ok("re-scan: nothing new left", still_new == 0, still_new)

	# ---- the panel: every tab opens
	menu.open_library()
	yield(wait(1.0), "completed")
	var p = menu.get_node_or_null("LibraryPanel")
	ok("panel opens", p != null)
	if p:
		for t in ["overview", "dupes", "tags", "smart", "import"]:
			p.show_tab(t, false)
			yield(wait(0.6), "completed")
			ok("tab " + t, p.pages[t].visible)
			shot(t)
		p.show_tab("dupes", false)
		p._dup_scan()
		var w = 0.0
		while p.dup_job and w < 20:
			yield(wait(0.25), "completed"); w += 0.25
		yield(wait(0.3), "completed")
		ok("panel: duplicate groups listed", p.dup_tree.get_root() and p.dup_tree.get_root().get_children() != null)
		shot("dupes_found")
		p.show_tab("smart", false)
		yield(wait(0.3), "completed")
		shot("smart")
		p.close()
	ok("sidebar Library button", menu.has_node("Sidebar/L/Library"))
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())

var got = null
func _got(r):
	got = r
