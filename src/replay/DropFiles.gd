extends Node
# Drop files onto the game window (any screen): colorsets (.txt: one colour per line, "m" =
# mirror), note meshes (.obj, its .mtl along with it), settings (.json: a settings.json from this
# game or a Rhythia-reimagined reimagined.json) and fonts (.ttf / .otf: the run HUD's font).
# Maps (.sspm / .phxm) and replays stay with the map list's own drop handler.
# Lives on the scene-tree root (added once by menu2.gd).

const R = preload("res://mods/replay/Reimagined.gd")
# settings that belong to this PC, not to a player's setup: never taken from a dropped file
const DEVICE_KEYS = ["window_fullscreen", "window_borderless", "vsync_enabled", "target_fps", "render_scale", "window_size",
	"window_position", "volume_master", "master_volume_db", "music_volume_db", "sfx_volume_db", "record_replays"]

func _ready():
	name = "DropFiles"
	pause_mode = PAUSE_MODE_PROCESS
	get_tree().connect("files_dropped", self, "_dropped")

func _dropped(files:PoolStringArray, _screen:int):
	var names = []
	for f in files: names.append(f.get_file().to_lower())
	for f in files:
		match f.get_extension().to_lower():
			"txt": _colorset(f)
			"obj": _mesh(f, names)
			"json": _settings(f)
			"ttf", "otf": _font(f)

func _say(ok:bool, text:String, title:String):
	Globals.notify(Globals.NOTIFY_SUCCEED if ok else Globals.NOTIFY_ERROR, text, title, 4)

# ---------------------------------------------------------------- colorsets
# a colorset file only: every line a colour (or "m"); a .txt map (the map list's job) doesn't match
static func colorset_lines(text:String):
	var cols = []
	for l in text.replace("\r", "").split("\n", false):
		var t = l.strip_edges()
		if t == "" or t.to_lower() == "m": continue
		var h = t.trim_prefix("#")
		if !(h.length() in [6, 8]) or !h.is_valid_hex_number(): return null
		cols.append(h)
	return cols if cols.size() > 0 else null

func _colorset(path:String):
	var f = File.new()
	if f.open(path, File.READ) != OK: return
	var text = f.get_as_text()
	f.close()
	if colorset_lines(text) == null: return # (not a colorset: a map .txt is the map list's)
	var dir = Directory.new()
	if !dir.dir_exists(Rhythia.user_colorset_dir): dir.make_dir_recursive(Rhythia.user_colorset_dir)
	var dst = Rhythia.user_colorset_dir.plus_file(path.get_file())
	var id = "custom_" + dst.get_file().to_lower().md5_text()
	if dir.copy(path, dst) != OK:
		_say(false, "Couldn't copy " + path.get_file() + " into the colorsets folder", "Colorset")
		return
	if !Rhythia.registry_colorset.get_item(id): Rhythia.load_color_txt(dst, id)
	var cs = Rhythia.registry_colorset.get_item(id)
	if cs: Rhythia.select_colorset(cs)
	var grid = _colorset_grid()
	if grid and ResourceLoader.exists("res://mods/replay/ColorsetMaker.gd"): load("res://mods/replay/ColorsetMaker.gd").refresh_grid(grid)
	_say(true, "Added \"%s\" and selected it" % path.get_file().get_basename(), "Colorset")

func _colorset_grid():
	var m = get_tree().root.get_node_or_null("Menu")
	if !m: return null
	var stack = [m] # (the settings page's colour grid listens for colorset changes)
	while !stack.empty():
		var n = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is Container and Rhythia.is_connected("selected_colorset_changed", n, "upd"): return n
	return null

# ---------------------------------------------------------------- note meshes
func _mesh(path:String, dropped:Array):
	var dir = Directory.new()
	if !dir.dir_exists(Rhythia.user_mesh_dir): dir.make_dir_recursive(Rhythia.user_mesh_dir)
	var dst = Rhythia.user_mesh_dir.plus_file(path.get_file())
	if dir.copy(path, dst) != OK:
		_say(false, "Couldn't copy " + path.get_file() + " into the meshes folder", "Note mesh")
		return
	var mtl = path.get_basename() + ".mtl" # (next to it, dropped with it or not)
	if dir.file_exists(mtl): dir.copy(mtl, Rhythia.user_mesh_dir.plus_file(mtl.get_file()))
	var id = "ugc_" + path.get_file().to_lower().replace(" ", "_")
	if !Rhythia.registry_mesh.get_item(id):
		Rhythia.registry_mesh.add_item(NoteMesh.new(id, path.get_file().get_basename() + " (custom)", dst, "???"))
	_say(true, "Added \"%s\": pick it in Settings > Notes > Note mesh" % path.get_file().get_basename(), "Note mesh")

# ---------------------------------------------------------------- settings
func _settings(path:String):
	var f = File.new()
	if f.open(path, File.READ) != OK: return
	var d = parse_json(f.get_as_text())
	f.close()
	if !(d is Dictionary): return
	if d.has("trail_style") or d.has("hud_style"): # (a reimagined.json: Customize's settings)
		_ask("Use the Customize settings in %s? Yours are kept in reimagined.json.bak first." % path.get_file(), "_take_customize", [path, d])
	elif d.has("approach_rate") or d.has("sensitivity"):
		_ask("Load the game settings in %s? Yours are saved to settings-backup.json first. Display, frame rate and volume settings stay as they are." % path.get_file(), "_take_game", [path, d])

func _ask(text:String, method:String, args:Array):
	Globals.confirm_prompt.open(text, "Settings file", [{text = "Load"}, {text = "Cancel"}])
	var pick = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	if pick == 0: callv(method, args)

func _take_game(_path:String, d:Dictionary):
	Rhythia.save_settings(Globals.p("user://settings-backup.json"))
	var cur = {}
	var f = File.new()
	if f.open(Globals.p("user://settings.json"), File.READ) == OK:
		var c = parse_json(f.get_as_text())
		f.close()
		if c is Dictionary: cur = c
	for k in d:
		if !(k in DEVICE_KEYS): cur[k] = d[k]
	var tmp = Globals.p("user://rr_settings_drop.json")
	if f.open(tmp, File.WRITE) != OK: return
	f.store_string(to_json(cur))
	f.close()
	Rhythia.load_saved_settings(tmp)
	load("res://mods/replay/PlayTrack.gd").refresh_settings_page(get_tree()) # (its boxes would put the old values back)
	Rhythia.save_settings()
	Directory.new().remove(tmp)
	_say(true, "Settings loaded (the old ones: settings-backup.json)", "Settings file")
	_reload_menu()

func _take_customize(_path:String, d:Dictionary):
	var dir = Directory.new()
	if dir.file_exists(Globals.p(R.FILE)): dir.copy(Globals.p(R.FILE), Globals.p(R.FILE) + ".bak")
	var cf = R.cfg()
	for k in d:
		if cf.has(k) and !(k in ["perf_saved", "player_name", "mp_name", "mp_recent", "mp_relay"]): cf[k] = d[k]
	R.save()
	_say(true, "Customize settings loaded (the old ones: reimagined.json.bak)", "Settings file")
	_reload_menu()

# the settings page reads its values once and writes them back: a fresh menu shows the new ones
func _reload_menu():
	var sc = get_tree().current_scene
	if sc and sc.name == "Menu":
		yield(get_tree().create_timer(0.6), "timeout")
		get_tree().change_scene("res://scenes/loaders/menuload.tscn")

# ---------------------------------------------------------------- fonts
func _font(path:String):
	var e = load("res://mods/replay/HudFont.gd").set_own(path)
	if e != "": _say(false, e[0].to_upper() + e.substr(1), "HUD font")
	else: _say(true, "\"%s\" is now the HUD font (Customize > Interface)" % path.get_file().get_basename(), "HUD font")
