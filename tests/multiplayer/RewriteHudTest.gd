extends Node
# Rewrite HUD (replay/RewriteHud.gd) + rewrite skin import (Skins.import_rewrite): the run's panels in
# the rewrite's layout with live values, its settings rows, a rewrite skin from a folder / config.toml /
# zip / the rewrite's user folder, used in a run (its images, grid frame, sounds), classic still works.
# Reads the real rewrite default skin (read only) at @@RWSKIN@@ when it exists.
# Output @@OUT@@/rwhud.txt + h_*.png
const OUT = "@@OUT@@/rwhud.txt"
const RW = "@@RWSKIN@@"
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

func shot(n):
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/h_" + n + ".png")

func play(secs = 4.0):
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
	yield(wait(secs), "completed")
	return g

func back(g):
	g.end(Globals.END_GIVEUP)
	var t = 0.0
	while t < 20 and !get_tree().root.has_node("Menu/ResultsScreen"):
		yield(wait(0.25), "completed"); t += 0.25

func find(root:Node, nm:String):
	var stack = [root]
	while !stack.empty():
		var x = stack.pop_back()
		if x.name == nm: return x
		for c in x.get_children(): stack.append(c)
	return null

func copy_tree(a:String, b:String):
	var d = Directory.new()
	if d.open(a) != OK: return
	d.make_dir_recursive(b)
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if d.current_is_dir(): copy_tree(a + "/" + n, b + "/" + n)
		elif !n.ends_with(".import"): Directory.new().copy(a + "/" + n, b + "/" + n)
		n = d.get_next()
	d.list_dir_end()

func read(p):
	var f = File.new()
	if f.open(p, File.READ) != OK: return PoolByteArray()
	var b = f.get_buffer(f.get_len()); f.close(); return b

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var R = load("res://mods/replay/Reimagined.gd")
	var S = load("res://mods/replay/Skins.gd")
	var RH = load("res://mods/replay/RewriteHud.gd")
	ok("RewriteHud.gd installed", RH != null)
	ok("rewrite HUD on by default", R.val("hud_style") == "rewrite")

	# settings rows
	var menu = get_tree().current_scene
	var rb = find(menu, "RewriteHud")
	var ab = find(menu, "AltCombo")
	var hp = find(menu, "HPEase")
	ok("settings rows: Rewrite HUD / Alt combo / HP easing", rb is CheckBox and ab is CheckBox and hp != null, [rb, ab, hp])
	if rb: ok("Rewrite HUD switch shows on", rb.pressed)

	# a run with the default look
	var g = yield(play(), "completed")
	var hud = g.get_node("HUD")
	var rw = hud.get_node_or_null("RRRewriteHud")
	ok("run: rewrite HUD attached", rw != null)
	ok("run: drawn in the left / right / timer viewports", hud.has_node("LeftVP/Control/RRRewrite") and hud.has_node("RightVP/Control/RRRewrite") and hud.has_node("TimerVP/Control/RRRewrite"))
	ok("run: stock panel labels hidden", !hud.get_node("RightVP/Control/Score").visible and !hud.get_node("LeftVP/Control/LetterGrade").visible and !hud.get_node("TimerVP/Control/Label").visible)
	if rw:
		yield(wait(0.2), "completed")
		ok("run: score / multiplier", rw.score.text == Globals.comma_sep(g.score) and rw.mult.text == "%dx" % g.combo_level, "%s %s" % [rw.score.text, rw.mult.text])
		ok("run: misses / hits / sum", rw.misses.text == Globals.comma_sep(g.misses) and rw.hits.text == Globals.comma_sep(g.hits) and rw.sum.text == Globals.comma_sep(g.hits + g.misses), "%s %s %s" % [rw.hits.text, rw.misses.text, rw.sum.text])
		var h = int(g.hits); var m = int(g.misses)
		var want = "100.00%" if h + m == 0 else "%.2f%%" % (floor(float(h) / (h + m) * 10000.0) / 100.0)
		ok("run: accuracy", rw.acc.text == want, rw.acc.text + " / " + want)
		var tf = rw.title.get_font("font")
		ok("run: title + time shown", rw.title.text != "" and (rw.title.text == hud.songnametxt.text or hud.songnametxt.text.begins_with(rw.title.text.substr(0, 8))) and rw.time.text == hud.timelabel.text, rw.title.text)
		ok("run: title fits its label (no cut-off ends)", tf.get_string_size(rw.title.text).x <= rw.title.rect_size.x, "%s / %s" % [tf.get_string_size(rw.title.text).x, rw.title.rect_size.x])
		ok("run: health bar follows energy", abs(rw.health.v - g.energy / g.max_energy) < 0.05, "%s %s" % [rw.health.v, g.energy])
		ok("run: progress bar moves", rw.progress.v > 0.0, rw.progress.v)
		ok("run: no grid frame without a skin", !g.get_node("Spawn").has_node("RRRewriteGrid"))
		var v = hud.get_node("ComboVP/Value")
		ok("run: combo outlined", v.get_color("font_color").a == 0.0)
	shot("default")
	yield(back(g), "completed")

	# alt combo (the switch of the menu we came back to)
	ab = find(get_tree().current_scene, "AltCombo")
	if ab: ab.pressed = true
	else: R.set_val("alt_combo", true)
	ok("alt combo switch saves", bool(R.val("alt_combo")))
	g = yield(play(2.0), "completed")
	rw = g.get_node("HUD/RRRewriteHud")
	ok("alt combo: count in the left panel, big one hidden", rw.alt_combo.visible and g.get_node("HUD/ComboVP/Value").self_modulate.a == 0.0)
	shot("alt")
	yield(back(g), "completed")
	R.set_val("alt_combo", false)

	# rewrite skins
	var have_rw = Directory.new().dir_exists(RW)
	ok("rewrite default skin present to test with", have_rw, RW)
	var e = S.import_rewrite("C:/no/such/skin")
	ok("missing folder -> error", e is String, e)
	var rname = ""
	if have_rw:
		var r = S.import_rewrite(RW + "/config.toml")
		ok("import from config.toml", r is Array, r)
		if r is Array:
			rname = r[0]
			ok("named after the folder", rname == "default (rewrite)", rname)
			for slot in ["cursor", "hit", "miss", "fail", "menu", "rw_grid", "rw_panel_left", "rw_panel_right", "rw_health", "rw_health_bg", "rw_progress", "rw_progress_bg", "rw_hits", "rw_misses"]:
				ok("slot " + slot, S.file_of(rname, slot) != "")
			var d = S.read(rname)
			ok("colours from its colour set", d.get("colors", []) == ["ff0059", "ffd8e6"], d.get("colors"))
			ok("note shape: its squircle.obj or rounded", S.file_of(rname, "mesh") != "" or d.settings.get("selected_mesh") == "ssp_rounded")
			ok("no warnings", r[1].empty(), r[1])
		# installed rewrite skins (a copy in this test's rewrite user folder)
		var root = S.rewrite_root()
		ok("rewrite root next to ours", root.ends_with("/Rhythia"), root)
		if root.find("/t/") >= 0 or root.find("\\t\\") >= 0: # (only ever writes inside the test folder)
			copy_tree(RW, root + "/skins/Copy Test")
			var found = S.rewrite_skins()
			var names = []
			for x in found: names.append(x[0])
			ok("installed rewrite skins listed", "Copy Test" in names, names)
		# zip (files in a folder inside it)
		var zp = OS.get_user_data_dir() + "/rwzip.zip"
		var entries = [["myskin/config.toml", "note_colors = \"Sunset\"\nnote_mesh = \"cube\"\n".to_utf8(), true],
			["myskin/game/cursor.png", read(RW + "/game/cursor.png"), false],
			["myskin/game/health.png", read(RW + "/game/health.png"), false],
			["myskin/hit.mp3", read(RW + "/hit.mp3"), false],
			["myskin/game/broken.png", "nope".to_utf8(), false]]
		var we = load("res://mods/fixes/Phxm.gd").write_zip(zp, entries)
		ok("test zip written", we == "", we)
		var rz = S.import_rewrite(zp)
		ok("import from zip", rz is Array, rz)
		if rz is Array:
			ok("zip: files", S.file_of(rz[0], "cursor") != "" and S.file_of(rz[0], "rw_health") != "" and S.file_of(rz[0], "hit") != "" and S.file_of(rz[0], "rw_grid") == "")
			var dz = S.read(rz[0])
			ok("zip: built-in colour set + shape", dz.get("colors", []).size() == 10 and dz.settings.get("selected_mesh") == "ssp_block", dz)
		var junk = OS.get_user_data_dir() + "/junk.zip"
		load("res://mods/fixes/Phxm.gd").write_zip(junk, [["readme.txt", "hi".to_utf8(), true]])
		ok("zip without a skin -> error", S.import_rewrite(junk) is String)

	# using the imported skin in a run
	if rname != "":
		var probs = S.apply(rname)
		ok("skin applies", probs.empty(), probs)
		ok("fail sound from the skin", Rhythia.fail_snd is AudioStream and Rhythia.fail_asp.stream == Rhythia.fail_snd)
		g = yield(play(), "completed")
		rw = g.get_node("HUD/RRRewriteHud")
		ok("skin run: grid frame instead of the border", g.get_node("Spawn").has_node("RRRewriteGrid") and !g.get_node("Spawn/Outer").visible)
		var lb = g.get_node("HUD/LeftVP/Control/RRRewrite").get_child(0)
		ok("skin run: panel image", lb.tex != null)
		ok("skin run: bar images", rw.health.fg != null and rw.progress.bg != null)
		shot("skin")
		yield(back(g), "completed")
		S.clear_active()

	# classic
	R.set_val("hud_style", "classic")
	g = yield(play(2.0), "completed")
	ok("classic: no rewrite HUD", !g.get_node("HUD").has_node("RRRewriteHud") and g.get_node("HUD/RightVP/Control/Score").visible)
	shot("classic")
	yield(back(g), "completed")
	R.set_val("hud_style", "rewrite")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
