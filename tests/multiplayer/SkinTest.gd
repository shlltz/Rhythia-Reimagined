extends Node
# Skin profiles + editor (replay/Skins.gd, SkinPanel.gd). Phase 1: the editor opens from Customize,
# a skin made from the current look, edited (shape, own colours, size, cursor image + size, hit
# sound, HUD font), saved and used; a run then really draws it (the note mesh, colours, cursor
# texture, HUD font, hit sound); settings saved; reset of a group; export -> delete -> import gives
# the same skin; a bad package is refused or cleaned. Phase 2 (RR_PHASE=2, same user data via
# RR_KEEP=1): after a restart the skin's sound / own colours are back.
# Map: @@MAP1@@. Output @@OUT@@/skins.txt + sk_*.png
const OUT = "@@OUT@@/skins.txt"
var passed = 0
var failed = 0
var S

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
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/sk_" + n + ".png")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

# test files: a 64x64 PNG, a short 16-bit PCM WAV, a font copied out of the game
func make_files(dir:String):
	Directory.new().make_dir_recursive(dir)
	var img = Image.new()
	img.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 1.0, 0.4, 1.0))
	img.save_png(dir + "/cur.png")
	var f = File.new()
	f.open(dir + "/hit.wav", File.WRITE) # (a real WAV: the game can't load wav from files, so it must be refused)
	var n = 4410
	f.store_buffer("RIFF".to_ascii()); f.store_32(36 + n * 2); f.store_buffer("WAVEfmt ".to_ascii())
	f.store_32(16); f.store_16(1); f.store_16(1); f.store_32(44100); f.store_32(88200); f.store_16(2); f.store_16(16)
	f.store_buffer("data".to_ascii()); f.store_32(n * 2)
	for i in n: f.store_16(int(8000 * sin(i * 0.1)) & 0xffff)
	f.close()
	var song = null # an mp3: the test map's audio
	for s in Rhythia.registry_song.get_items():
		if s is Song and s.filePath.get_file() == "@@MAP1@@": song = s
	f.open(dir + "/hit.mp3", File.WRITE)
	f.store_buffer(song.get_music_buffer())
	f.close()
	var src = File.new()
	src.open("res://assets/font/Lato/Lato-Italic.ttf", File.READ)
	f.open(dir + "/font.ttf", File.WRITE)
	f.store_buffer(src.get_buffer(src.get_len()))
	src.close()
	f.close()
	f.open(dir + "/bad.png", File.WRITE)
	f.store_buffer(PoolByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
	f.close()

func run():
	Directory.new().remove(OUT) if OS.get_environment("RR_PHASE") != "2" else null
	yield(wait(6.0), "completed")
	S = load("res://mods/replay/Skins.gd")
	if OS.get_environment("RR_PHASE") == "2":
		yield(phase2(), "completed")
		return
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	var tdir = Globals.p("user://test_files")
	make_files(tdir)
	# ---- editor from Customize > Skin
	menu.open_customize()
	yield(wait(1.0), "completed")
	var cz = menu.get_node_or_null("ReimaginedPanel")
	ok("Customize open", cz != null)
	if cz:
		cz.show_tab("skin", false)
		cz._open_skin_editor()
	yield(wait(1.0), "completed")
	var p = menu.get_node_or_null("SkinPanel")
	ok("skin editor opens from Customize > Skin", p != null)
	if cz: cz.close()
	var before_size = Rhythia.note_size
	var before_mesh = Rhythia.selected_mesh.id
	p.name_edit.text = "Test skin"
	p._new()
	ok("skin made from the current look", S.list().has("Test skin") and p.cur_name == "Test skin", S.list())
	ok("its settings = the ones in use", abs(float(S.read("Test skin").settings.note_size) - before_size) < 0.001 and S.read("Test skin").settings.selected_mesh == before_mesh)
	# ---- edits
	p._set("note_size", 1.5)
	p._set("selected_mesh", "ssp_square")
	p._colors_set("#ff0000, #00ff00, #0000ff")
	p._set("cursor_scale", 2.0)
	ok("own cursor image accepted", S.set_file("Test skin", "cursor", tdir + "/cur.png") == "")
	ok("a .wav hit sound refused (the game can't play it from a file)", S.set_file("Test skin", "hit", tdir + "/hit.wav") != "")
	var he = S.set_file("Test skin", "hit", tdir + "/hit.mp3")
	ok("own hit sound accepted (mp3)", he == "", he)
	ok("own HUD font accepted", S.set_file("Test skin", "hud_font", tdir + "/font.ttf") == "")
	ok("broken image refused", S.set_file("Test skin", "note", tdir + "/bad.png") != "", S.set_file("Test skin", "note", tdir + "/bad.png"))
	ok("a text file as a mesh refused", S.set_file("Test skin", "mesh", tdir + "/hit.wav") != "")
	p._rebuild_preview()
	p._show_group("notes")
	yield(wait(1.5), "completed")
	ok("preview uses the chosen shape (square block mesh)", p.notes_mm.multimesh.mesh != null and p.notes_mm.multimesh.mesh.get_surface_count() > 0)
	ok("preview colours = the skin's own", p._colors()[0].is_equal_approx(Color("#ff0000")) and p._colors().size() == 3)
	shot("editor")
	p._save()
	ok("saved", !p.dirty and S.read("Test skin").settings.note_size == 1.5 and S.read("Test skin").colors.size() == 3)
	p._use()
	var tw = 0.0 # (the menu reloads to apply it)
	while tw < 10 and (Engine.has_meta("rr_skin_pending") or !get_tree().current_scene or !get_tree().current_scene.has_node("SkinPanel")):
		yield(wait(0.2), "completed"); tw += 0.2
	yield(wait(1.0), "completed")
	menu = get_tree().current_scene
	p = menu.get_node_or_null("SkinPanel")
	ok("menu reloaded, editor back on the skin", p != null and p.cur_name == "Test skin")
	ok("in use", S.active() == "Test skin")
	ok("BEFORE profile kept the old look", S.list().has(S.BEFORE) and abs(float(S.read(S.BEFORE).settings.note_size) - before_size) < 0.001)
	yield(wait(1.0), "completed") # (frames pass with the settings page alive: values must stay)
	ok("settings applied and kept by the settings page", Rhythia.note_size == 1.5 and Rhythia.selected_mesh.id == "ssp_square" and Rhythia.cursor_scale == 2.0, "%s %s %s" % [Rhythia.note_size, Rhythia.selected_mesh.id, Rhythia.cursor_scale])
	ok("own colours registered + selected", Rhythia.selected_colorset.id.begins_with("rrskin_") and Rhythia.selected_colorset.colors.size() == 3)
	var hs = Rhythia.hit_snd
	ok("hit sound swapped", hs is AudioStream and hs != Rhythia.def_hit_snd)
	var settings_text = ""
	var sf = File.new()
	if sf.open(Globals.p("user://settings.json"), File.READ) == OK:
		settings_text = sf.get_as_text()
		sf.close()
	ok("settings saved to settings.json", "1.5" in settings_text)
	p.close()
	yield(wait(0.5), "completed")
	# ---- a run draws it
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
	yield(wait(4.0), "completed")
	if g:
		var sp = g.get_node("Spawn")
		var square = load("res://assets/blocks/default.obj")
		ok("run: notes use the skin's shape", sp.get_node("Notes").multimesh.mesh.get_faces().size() == square.get_faces().size(), "%d vs %d faces" % [sp.get_node("Notes").multimesh.mesh.get_faces().size(), square.get_faces().size()])
		ok("run: note colours from the skin", sp.colors.size() == 3 and sp.colors[0].is_equal_approx(Color("#ff0000")))
		var ct = sp.get_node("Cursor/Mesh").get("material/0").albedo_texture
		ok("run: cursor uses the skin image", ct != null and ct.get_width() == 64, ct.get_width() if ct else "none")
		ok("run: cursor size", abs(sp.get_node("Cursor/Mesh").scale.x - 2.0) < 0.01, sp.get_node("Cursor/Mesh").scale)
		var hit_players = sp.get_node("HitSounds").get_children()
		var hp_len = hit_players[0].stream.get_length() if hit_players.size() > 0 and hit_players[0].stream else -1.0
		ok("run: hit sound players use the skin's sound", hit_players.size() > 0 and abs(hp_len - hs.get_length()) < 0.01 and hp_len > 1.0, "%d players, %.2f s vs %.2f s (Rhythia.hit_snd now %.2f s)" % [hit_players.size(), hp_len, hs.get_length(), Rhythia.hit_snd.get_length()])
		var hud = g.get_node_or_null("HUD")
		var skinned = 0
		if hud:
			var stack = [hud]
			while !stack.empty():
				var n = stack.pop_back()
				for c in n.get_children(): stack.append(c)
				if n is Label and n.has_font_override("font") and n.get_font("font") is DynamicFont and n.get_font("font").font_data and "font.ttf" in n.get_font("font").font_data.font_path: skinned += 1
		ok("run: HUD texts in the skin's font", skinned > 0, skinned)
		shot("run")
		g.end(Globals.END_GIVEUP)
	t = 0.0
	while t < 20 and !get_tree().root.has_node("Menu/ResultsScreen"):
		yield(wait(0.25), "completed"); t += 0.25
	# ---- reset a group, export / delete / import
	var d0 = S.read("Test skin")
	var pk = Globals.p("user://test_files/test.rrskin")
	ok("export", S.export_pkg("Test skin", pk) == "" and File.new().file_exists(pk))
	ok("delete", S.delete("Test skin") and !S.list().has("Test skin") and S.active() == "")
	var r = S.import_pkg(pk)
	ok("import", r is Array and r[0] == "Test skin", r)
	if r is Array:
		var d1 = S.read(r[0])
		ok("import: same settings + colours", to_json(d1.settings) == to_json(d0.settings) and str(d1.colors) == str(d0.colors))
		ok("import: same files", S.file_of(r[0], "cursor") != "" and S.file_of(r[0], "hit") != "" and S.file_of(r[0], "hud_font") != "")
	r = S.import_pkg(pk)
	ok("import again: a new name, nothing replaced", r is Array and r[0] == "Test skin (2)", r)
	# a package with a broken image and an unknown setting
	var P = load("res://mods/fixes/Phxm.gd")
	var sj = to_json({"name": "Bad pkg", "settings": {"note_size": 1.2, "evil_setting": "x", "cursor_color": "not a colour"}})
	P.write_zip(Globals.p("user://test_files/bad.rrskin"), [["skin.json", sj.to_utf8(), true], ["note.png", PoolByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]), false]])
	r = S.import_pkg(Globals.p("user://test_files/bad.rrskin"))
	ok("bad package: imported without the broken parts", r is Array and S.file_of(r[0], "note") == "" and !S.read(r[0]).settings.has("evil_setting") and !S.read(r[0]).settings.has("cursor_color") and S.read(r[0]).settings.note_size == 1.2, r)
	var f = File.new()
	f.open(Globals.p("user://test_files/junk.rrskin"), File.WRITE)
	f.store_buffer(PoolByteArray([0, 1, 2, 3]))
	f.close()
	r = S.import_pkg(Globals.p("user://test_files/junk.rrskin"))
	ok("not a package: an error, nothing installed", r is String)
	# reset one group (editor)
	menu = get_tree().current_scene
	menu.open_customize()
	yield(wait(0.5), "completed")
	menu.get_node("ReimaginedPanel")._open_skin_editor()
	yield(wait(0.8), "completed")
	p = menu.get_node("SkinPanel")
	p._select("Test skin")
	p.cur_group = "notes"
	p._reset_group()
	ok("reset group: notes back to the game's defaults", p.work.note_size == 1.0 and p.work.selected_mesh == "ssp_rounded" and p.work_colors == null)
	p._revert()
	ok("revert: back to the saved skin", p.work.note_size == 1.5)
	S.apply("Test skin")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())

func phase2():
	yield(wait(1.0), "completed")
	ok("after a restart: the skin is still in use", S.active() == "Test skin", S.active())
	ok("after a restart: its hit sound is loaded", Rhythia.hit_snd != Rhythia.def_hit_snd)
	ok("after a restart: its own colours are selected", Rhythia.selected_colorset and Rhythia.selected_colorset.id.begins_with("rrskin_"), Rhythia.selected_colorset.id if Rhythia.selected_colorset else "none")
	ok("after a restart: settings kept", Rhythia.note_size == 1.5 and Rhythia.selected_mesh.id == "ssp_square")
	out("== totals (phase 2): %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
