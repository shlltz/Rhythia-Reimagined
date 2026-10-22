extends Reference
# Skin profiles (Rhythia-reimagined). A skin = the game's own skin settings (note shape, colours,
# size, opacity, spin, cursor, trail, hit / miss effects and sounds on / off, miss / score colours)
# + optional files that replace the game's: note.png (note image), cursor.png, trail.png,
# touch.png, hit / miss sounds, mesh.obj (a note shape), hud_font.ttf. Each lives in
# DIR/<name>/ (skin.json + files). SkinPanel.gd is the editor.
#
# Using a skin sets those settings (saved like any settings change) and points the renderer at the
# skin's files at runtime: NoteManager.gd takes the note / cursor / trail / touch images from it,
# Rhythia.hit_snd / miss_snd are swapped (the hit-sound players are made from them every run), HUD.gd
# uses the font. The files the game itself reads from the user folder (user://cursor.png, hit.mp3 ...)
# are never written or deleted: a skin without a file falls back to them. The first time a skin is
# used, the setup before it is kept as the profile BEFORE (settings + copies of those files).
#
# Packages (.rrskin) are zips of a skin folder. Import validates every file (images decode, audio
# is mp3 / ogg / wav, the mesh parses, the font loads, the settings are known keys of the right
# type) in a temporary folder and only then moves it in place; an existing skin is never replaced.

const DIR = "user://rr_skins"
const TMP = "user://rr_skins_tmp"
const EXT = "rrskin"
const BEFORE = "My setup (before skins)"
# setting -> [category, kind]
const KEYS = {
	"note_size": ["notes", "float"], "note_opacity": ["notes", "float"],
	"note_spin_x": ["notes", "float"], "note_spin_y": ["notes", "float"], "note_spin_z": ["notes", "float"],
	"cursor_scale": ["cursor", "float"], "cursor_color_type": ["cursor", "int"], "cursor_color": ["cursor", "color"],
	"cursor_spin": ["cursor", "float"], "cursor_trail": ["cursor", "bool"], "smart_trail": ["cursor", "bool"],
	"trail_detail": ["cursor", "int"], "trail_time": ["cursor", "float"], "trail_mode_scale": ["cursor", "bool"],
	"trail_mode_opacity": ["cursor", "bool"],
	"show_hit_effect": ["effects", "bool"], "show_miss_effect": ["effects", "bool"], "hit_effect_at_cursor": ["effects", "bool"],
	"miss_flash_color": ["effects", "color"],
	"play_hit_snd": ["sounds", "bool"], "play_miss_snd": ["sounds", "bool"],
	"miss_text_color": ["hud", "color"], "score_text_color": ["hud", "color"],
}
# registry selections (ids) -> [category, registry, Rhythia selector]
const PICKS = {
	"selected_mesh": ["notes", "registry_mesh", "select_mesh"],
	"selected_colorset": ["notes", "registry_colorset", "select_colorset"],
	"selected_hit_effect": ["effects", "registry_effect", "select_hit_effect"],
	"selected_miss_effect": ["effects", "registry_effect", "select_miss_effect"],
}
# the mod's own trail settings (Reimagined.gd)
const RR_KEYS = {"trail_style": "cursor", "trail_color": "cursor", "trail_alpha": "cursor", "trail_length": "cursor", "trail_size": "cursor"}
# files: slot -> [category, kind, extensions]
const FILES = {
	"note": ["notes", "image", ["png", "jpg", "webp"]], "mesh": ["notes", "obj", ["obj"]],
	"cursor": ["cursor", "image", ["png", "jpg", "webp"]], "trail": ["cursor", "image", ["png", "jpg", "webp"]],
	"touch": ["cursor", "image", ["png", "jpg", "webp"]],
	"hit": ["sounds", "audio", ["ogg", "mp3"]], "miss": ["sounds", "audio", ["ogg", "mp3"]], # (the game's AudioLoader can't load wav from files)
	"hud_font": ["hud", "font", ["ttf", "otf"]],
	"fail": ["sounds", "audio", ["ogg", "mp3"]], "menu": ["sounds", "audio", ["ogg", "mp3"]],
	# rewrite HUD pieces (RewriteHud.gd), as rewrite skins have them
	"rw_grid": ["hud", "image", ["png", "jpg", "webp"]], "rw_panel_left": ["hud", "image", ["png", "jpg", "webp"]],
	"rw_panel_right": ["hud", "image", ["png", "jpg", "webp"]], "rw_health": ["hud", "image", ["png", "jpg", "webp"]],
	"rw_health_bg": ["hud", "image", ["png", "jpg", "webp"]], "rw_progress": ["hud", "image", ["png", "jpg", "webp"]],
	"rw_progress_bg": ["hud", "image", ["png", "jpg", "webp"]], "rw_hits": ["hud", "image", ["png", "jpg", "webp"]],
	"rw_misses": ["hud", "image", ["png", "jpg", "webp"]],
}
const CATEGORIES = ["notes", "cursor", "effects", "sounds", "hud"]
# the game's own defaults (stock Rhythia.gd)
const DEFAULTS = {
	"note_size": 1.0, "note_opacity": 1.0, "note_spin_x": 0.0, "note_spin_y": 0.0, "note_spin_z": 0.0,
	"cursor_scale": 1.0, "cursor_color_type": 0, "cursor_color": "#ffffff", "cursor_spin": 0.0, "cursor_trail": false,
	"smart_trail": false, "trail_detail": 10, "trail_time": 0.15, "trail_mode_scale": true, "trail_mode_opacity": true,
	"show_hit_effect": true, "show_miss_effect": true, "hit_effect_at_cursor": true, "miss_flash_color": "#ff0000",
	"play_hit_snd": true, "play_miss_snd": true, "miss_text_color": "#ffffff", "score_text_color": "#ffffff",
	"selected_mesh": "ssp_rounded", "selected_colorset": "ssp_cottoncandy", "selected_hit_effect": "ssp_ripple", "selected_miss_effect": "ssp_miss",
	"trail_style": "game", "trail_color": "", "trail_alpha": 1.0, "trail_length": 1.0, "trail_size": 1.0,
}

static func R():
	return load("res://mods/replay/Reimagined.gd")

static func path_of(name:String) -> String:
	return Globals.p(DIR) + "/" + clean_name(name)

static func clean_name(n:String) -> String:
	var o = ""
	for c in n.strip_edges():
		o += c if !(c in "\\/:*?\"<>|") else "_"
	return o.substr(0, 60)

# ------------------------------------------------------------------ profiles
static func list() -> Array:
	var out = []
	var d = Directory.new()
	if d.open(Globals.p(DIR)) != OK: return out
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if d.current_is_dir() and File.new().file_exists(Globals.p(DIR) + "/" + n + "/skin.json"): out.append(n)
		n = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

static func active() -> String:
	var a = str(R().val("skin"))
	return a if a != "" and File.new().file_exists(path_of(a) + "/skin.json") else ""

static func read(name:String) -> Dictionary:
	var f = File.new()
	var p = path_of(name) + "/skin.json"
	if !f.file_exists(p) or f.open(p, File.READ) != OK: return {}
	var d = parse_json(f.get_as_text())
	f.close()
	return sanitize(d) if typeof(d) == TYPE_DICTIONARY else {}

# only known keys, each of the right type; colour sets as [html colours]
static func sanitize(d:Dictionary) -> Dictionary:
	var s = {}
	var src = d.get("settings", {}) if typeof(d.get("settings")) == TYPE_DICTIONARY else {}
	for k in src:
		var v = src[k]
		var num = typeof(v) in [TYPE_REAL, TYPE_INT]
		if KEYS.has(k):
			var kind = KEYS[k][1]
			if kind == "float" and num: s[k] = clamp(float(v), -10000.0, 10000.0)
			elif kind == "int" and num: s[k] = int(v)
			elif kind == "bool" and typeof(v) == TYPE_BOOL: s[k] = v
			elif kind == "color" and typeof(v) == TYPE_STRING and v.is_valid_html_color(): s[k] = Color(v).to_html(true)
		elif PICKS.has(k) and typeof(v) == TYPE_STRING: s[k] = v.substr(0, 100)
		elif k == "trail_style":
			if str(v) in ["game", "osu", "off"]: s[k] = str(v)
		elif k == "trail_color":
			if typeof(v) == TYPE_STRING and (v == "" or v.is_valid_html_color()): s[k] = v
		elif RR_KEYS.has(k) and num: s[k] = clamp(float(v), 0.0, 10.0)
	var out = {"settings": s, "name": str(d.get("name", "")).substr(0, 60), "author": str(d.get("author", "")).substr(0, 60), "version": 1}
	if d.get("colors") is Array:
		var cs = []
		for c in d.colors:
			if typeof(c) == TYPE_STRING and c.is_valid_html_color() and cs.size() < 64: cs.append(Color(c).to_html(false))
		if !cs.empty():
			out.colors = cs
			out.mirror = bool(d.get("mirror", false))
	return out

static func write(name:String, data:Dictionary) -> bool:
	var dir = path_of(name)
	Directory.new().make_dir_recursive(dir)
	var f = File.new()
	if f.open(dir + "/skin.json.tmp", File.WRITE) != OK: return false
	f.store_string(JSON.print(sanitize(data), "\t"))
	f.close()
	var d = Directory.new()
	if d.file_exists(dir + "/skin.json"): d.remove(dir + "/skin.json")
	return d.rename(dir + "/skin.json.tmp", dir + "/skin.json") == OK

# the file of a slot in a skin ("" when it has none)
static func file_of(name:String, slot:String) -> String:
	if name == "" or !FILES.has(slot): return ""
	for e in FILES[slot][2]:
		var p = path_of(name) + "/" + slot + "." + e
		if File.new().file_exists(p): return p
	return ""

static func set_file(name:String, slot:String, src:String) -> String:
	var ext = src.get_extension().to_lower()
	if !FILES.has(slot) or !(ext in FILES[slot][2]): return "a %s needs one of: %s" % [slot, PoolStringArray(FILES[slot][2]).join(", ")]
	var err = validate_file(slot, src)
	if err != "": return err
	clear_file(name, slot)
	Directory.new().make_dir_recursive(path_of(name))
	return "" if Directory.new().copy(src, path_of(name) + "/" + slot + "." + ext) == OK else "couldn't copy the file"

static func clear_file(name:String, slot:String):
	for e in FILES[slot][2]:
		var p = path_of(name) + "/" + slot + "." + e
		if File.new().file_exists(p): Directory.new().remove(p)

# "" = fine, else why the file can't be used
static func validate_file(slot:String, path:String) -> String:
	var f = File.new()
	if !f.file_exists(path): return "file not found"
	if f.open(path, File.READ) != OK: return "can't read the file"
	var size = f.get_len()
	var head = f.get_buffer(min(size, 16))
	f.close()
	if size > 50 * 1024 * 1024: return "the file is too big (50 MB at most)"
	match FILES[slot][1]:
		"image":
			var img = Image.new()
			if img.load(path) != OK or img.is_empty(): return "not an image the game can read"
			if img.get_width() > 4096 or img.get_height() > 4096: return "the image is too large (4096 px at most)"
		"audio":
			f.open(path, File.READ)
			var fmt = Globals.audioLoader.get_format(f.get_buffer(min(size, 64)))
			f.close()
			if !(fmt in ["mp3", "ogg"]): return "not mp3 / ogg audio (the game can't play wav files from the user folder)"
			var st = Globals.audioLoader.load_file(path)
			if !(st is AudioStream): return "the audio doesn't load"
		"obj":
			var m = ObjParse.load_obj(path)
			if m == null or !(m is Mesh) or m.get_surface_count() == 0: return "not a mesh the game can read (.obj)"
		"font":
			if head.size() < 4: return "not a font"
			var fd = DynamicFontData.new()
			fd.font_path = path
			var df = DynamicFont.new()
			df.font_data = fd
			df.size = 16
			if df.get_height() <= 0: return "not a font the game can read (.ttf / .otf)"
	return ""

# a new skin from the settings in use now (+ copies of the game's own user-folder files)
static func capture(name:String, with_files:bool = true) -> bool:
	var s = {}
	for k in KEYS:
		var v = Rhythia.get(k)
		s[k] = v.to_html(true) if v is Color else v
	for k in PICKS:
		var it = Rhythia.get(k)
		if it: s[k] = it.id
	for k in RR_KEYS: s[k] = R().val(k)
	var data = {"settings": s, "author": ""}
	if !write(name, data): return false
	if with_files:
		for slot in ["note", "cursor", "trail", "touch", "hit", "miss"]:
			for e in FILES[slot][2]:
				var p = Globals.p("user://" + slot + "." + e)
				if File.new().file_exists(p):
					Directory.new().copy(p, path_of(name) + "/" + slot + "." + e)
					break
	return true

# ------------------------------------------------------------------ using a skin
# Puts the skin's settings in place and makes the renderer use its files. Returns a list of things
# that couldn't be applied (a missing colour set id, ...), empty when everything worked.
static func apply(name:String) -> Array:
	var data = read(name)
	if data.empty(): return ["no such skin"]
	if active() == "" and name != BEFORE and !list().has(BEFORE): capture(BEFORE) # (the setup before any skin, once)
	var problems = []
	var s = data.settings
	for k in KEYS:
		if !s.has(k): continue
		Rhythia.set(k, Color(s[k]) if KEYS[k][1] == "color" else s[k])
	# own note shape / colours first, so the picks below can select them
	var mesh_file = file_of(name, "mesh")
	if mesh_file != "": s["selected_mesh"] = _register_mesh(name, mesh_file)
	if data.has("colors"): s["selected_colorset"] = _register_colorset(name, data.colors, data.get("mirror", false))
	for k in PICKS:
		if !s.has(k): continue
		var reg = Rhythia.get(PICKS[k][1])
		var it = reg.get_item(s[k]) if reg else null
		if it: Rhythia.call(PICKS[k][2], it)
		else: problems.append("%s: \"%s\" isn't installed here" % [k.replace("selected_", ""), s[k]])
	for k in RR_KEYS:
		if s.has(k): R().set_val(k, s[k])
	R().set_val("skin", name)
	_apply_sounds(name)
	Engine.remove_meta("rr_skin_tex")
	Engine.remove_meta("rr_skin_font")
	if Rhythia.has_method("save_settings"): Rhythia.save_settings()
	return problems

# The settings page's controls write their own value back into the setting every frame (stock
# CursorScale.gd and others), so settings changed under an open menu are undone. Like the game's own
# settings profiles (which go through init), the menu is reloaded and the skin applied the moment
# the new menu scene enters the tree - before its settings page reads anything (Watch).
const MENUS = ["res://scenes/loaders/menuload.tscn", "res://scenes/menu/menu2.tscn", "res://scenes/menu/oldmenu2.tscn"]
static func use_and_reload(tree:SceneTree, name:String):
	Engine.set_meta("rr_skin_pending", name)
	if !tree.root.has_node("RRSkinWatch"):
		var w = Watch.new()
		w.name = "RRSkinWatch"
		tree.root.add_child(w)
	var cur = tree.current_scene
	if cur and "black_fade_target" in cur: cur.black_fade_target = true
	yield(tree.create_timer(0.35), "timeout")
	tree.change_scene(cur.filename if cur and cur.filename in MENUS else "res://scenes/loaders/menuload.tscn")

class Watch extends Node:
	func _ready():
		get_tree().connect("node_added", self, "_added")
	func _added(n:Node):
		if n.get_parent() != get_tree().root or !(n.filename in load("res://mods/replay/Skins.gd").MENUS): return
		var name = Engine.get_meta("rr_skin_pending") if Engine.has_meta("rr_skin_pending") else ""
		Engine.remove_meta("rr_skin_pending")
		if name != "": Engine.set_meta("rr_skin_applied", [name, load("res://mods/replay/Skins.gd").apply(name)])
		queue_free()

# back to no skin: the game's own user-folder files again (settings stay as they are)
static func clear_active():
	R().set_val("skin", "")
	_apply_sounds("")
	Engine.remove_meta("rr_skin_tex")
	Engine.remove_meta("rr_skin_font")

# hit / miss sounds: the skin's, else the game's own (user folder file or built-in)
static func _apply_sounds(name:String):
	for e in [["hit", "hit_snd", "def_hit_snd"], ["miss", "miss_snd", "def_miss_snd"], ["fail", "fail_snd", "def_fail_snd"], ["menu", "menu_bgm", "def_menu_bgm"]]:
		var f = file_of(name, e[0])
		var st = Globals.audioLoader.load_file(f) if f != "" else null
		if !(st is AudioStream): st = Rhythia.get_stream_with_default("user://" + e[0], Rhythia.get(e[2]))
		if e[0] != "menu" and (st is AudioStreamOGGVorbis or st is AudioStreamMP3): st.loop = false
		Rhythia.set(e[1], st)
	Globals.error_sound = Rhythia.miss_snd
	if Rhythia.fail_asp: Rhythia.fail_asp.stream = Rhythia.fail_snd

static func _register_mesh(name:String, path:String) -> String:
	var id = "rrskin_" + clean_name(name).to_lower().replace(" ", "_")
	var reg = Rhythia.registry_mesh
	if reg.get_item(id): reg.check_and_remove_id(id)
	reg.add_item(NoteMesh.new(id, name + " (skin)", path, "skin"))
	return id

static func _register_colorset(name:String, colors:Array, mirror:bool) -> String:
	var id = "rrskin_" + clean_name(name).to_lower().replace(" ", "_")
	var cs = []
	for c in colors: cs.append(Color(c))
	var reg = Rhythia.registry_colorset
	if reg.get_item(id): reg.check_and_remove_id(id)
	var set = ColorSet.new(cs, id, name + " (skin)", "skin")
	set.mirror = mirror
	reg.add_item(set)
	return id

# at startup (Boot.gd, once settings and the stock files are loaded): the active skin's sounds and
# its own note shape / colours (registered again: registries are rebuilt every launch)
static func restore_at_boot():
	var a = active()
	if a == "": return
	var data = read(a)
	# the game read settings.json before these existed, so it fell back to a stock pick: what the
	# file says decides (a shape / colour set chosen by hand later is left alone)
	var saved = {}
	var f = File.new()
	if f.open(Globals.p("user://settings.json"), File.READ) == OK:
		var j = parse_json(f.get_as_text())
		f.close()
		if typeof(j) == TYPE_DICTIONARY: saved = j
	var mf = file_of(a, "mesh")
	if mf != "":
		var id = _register_mesh(a, mf)
		if str(saved.get("selected_mesh", "")) == id: Rhythia.select_mesh(Rhythia.registry_mesh.get_item(id))
	if data.has("colors"):
		var id = _register_colorset(a, data.colors, data.get("mirror", false))
		if str(saved.get("selected_colorset", "")) == id: Rhythia.select_colorset(Rhythia.registry_colorset.get_item(id))
	_apply_sounds(a)

# a texture for an image slot of the active skin (null = use the game's own); cached per session
static func texture(slot:String):
	var a = active()
	var f = file_of(a, slot)
	if f == "": return null
	var cache = Engine.get_meta("rr_skin_tex") if Engine.has_meta("rr_skin_tex") else {}
	var key = f + "|" + str(File.new().get_modified_time(f))
	if cache.has(key): return cache[key]
	var img = Image.new()
	var t = null
	if img.load(f) == OK:
		t = ImageTexture.new()
		t.create_from_image(img)
	cache[key] = t
	Engine.set_meta("rr_skin_tex", cache)
	return t

# the active skin's HUD font at a size (null = the game's own)
static func hud_font(size:int, name:String = ""):
	if name == "": name = active()
	var f = file_of(name, "hud_font")
	if f == "": return null
	var cache = Engine.get_meta("rr_skin_font") if Engine.has_meta("rr_skin_font") else {}
	var key = "%s|%d" % [f, size]
	if cache.has(key): return cache[key]
	var fd = DynamicFontData.new()
	fd.font_path = f
	var df = DynamicFont.new()
	df.font_data = fd
	df.size = size
	cache[key] = df
	Engine.set_meta("rr_skin_font", cache)
	return df

# ------------------------------------------------------------------ editing helpers
static func defaults_for(category:String) -> Dictionary:
	var out = {}
	for k in DEFAULTS:
		var cat = KEYS[k][0] if KEYS.has(k) else (PICKS[k][0] if PICKS.has(k) else RR_KEYS.get(k, ""))
		if cat == category: out[k] = DEFAULTS[k]
	return out

static func unique_name(want:String) -> String:
	var n = clean_name(want)
	if n == "": n = "Skin"
	var base = n
	var i = 2
	while list().has(n):
		n = "%s (%d)" % [base, i]
		i += 1
	return n

static func duplicate_skin(src:String, dst:String) -> String:
	dst = unique_name(dst)
	if _copy_dir(path_of(src), path_of(dst)) != OK: return ""
	return dst

static func rename(old:String, new:String) -> String:
	new = clean_name(new)
	if new == "" or list().has(new) or !list().has(old): return ""
	if Directory.new().rename(path_of(old), path_of(new)) != OK: return ""
	if str(R().val("skin")) == old: R().set_val("skin", new)
	return new

# to the recycle bin on desktop (it is the player's own work)
static func delete(name:String) -> bool:
	if !list().has(name): return false
	if active() == name: clear_active()
	var p = ProjectSettings.globalize_path(path_of(name))
	if OS.has_feature("pc"): return OS.move_to_trash(p) == OK
	var files = []
	var d = Directory.new()
	if d.open(path_of(name)) == OK:
		d.list_dir_begin(true, true)
		var n = d.get_next()
		while n != "":
			files.append(n)
			n = d.get_next()
		d.list_dir_end()
	for n in files: d.remove(path_of(name) + "/" + n)
	return d.remove(path_of(name)) == OK

static func _copy_dir(a:String, b:String) -> int:
	var d = Directory.new()
	if d.open(a) != OK: return ERR_CANT_OPEN
	d.make_dir_recursive(b)
	d.list_dir_begin(true, true)
	var n = d.get_next()
	var err = OK
	while n != "":
		if !d.current_is_dir() and d.copy(a + "/" + n, b + "/" + n) != OK: err = ERR_CANT_CREATE
		n = d.get_next()
	d.list_dir_end()
	return err

# ------------------------------------------------------------------ packages
static func export_pkg(name:String, out_path:String) -> String:
	var entries = []
	var d = Directory.new()
	if d.open(path_of(name)) != OK: return "no such skin"
	d.list_dir_begin(true, true)
	var n = d.get_next()
	var f = File.new()
	while n != "":
		if !d.current_is_dir() and f.open(path_of(name) + "/" + n, File.READ) == OK:
			entries.append([n, f.get_buffer(f.get_len()), n.ends_with(".json") or n.ends_with(".obj")])
			f.close()
		n = d.get_next()
	d.list_dir_end()
	return load("res://mods/fixes/Phxm.gd").write_zip(out_path, entries)

# a .rrskin -> a new skin (its own name, made unique); returns [name, warnings] or an error String
static func import_pkg(path:String):
	var P = load("res://mods/fixes/Phxm.gd")
	var allowed = ["skin.json"]
	for slot in FILES:
		for e in FILES[slot][2]: allowed.append(slot + "." + e)
	var files = P._read_zip(path, allowed)
	if files is String: return files
	if !files.has("skin.json"): return "not a skin package (no skin.json)"
	var raw = parse_json(files["skin.json"].get_string_from_utf8())
	if typeof(raw) != TYPE_DICTIONARY: return "skin.json is broken"
	var warn = []
	var tmp = Globals.p(TMP) + "/" + str(OS.get_ticks_usec())
	var d = Directory.new()
	d.make_dir_recursive(tmp)
	var f = File.new()
	for k in files:
		if k == "skin.json": continue
		var slot = k.get_basename()
		if f.open(tmp + "/" + k, File.WRITE) != OK: continue
		f.store_buffer(files[k])
		f.close()
		var err = validate_file(slot, tmp + "/" + k)
		if err != "":
			warn.append("%s left out: %s" % [k, err])
			d.remove(tmp + "/" + k)
	var data = sanitize(raw)
	var dropped = raw.get("settings", {}).size() - data.settings.size() if typeof(raw.get("settings")) == TYPE_DICTIONARY else 0
	if dropped > 0: warn.append("%d unknown or invalid settings left out" % dropped)
	if f.open(tmp + "/skin.json", File.WRITE) != OK: return "can't write the skin"
	f.store_string(JSON.print(data, "\t"))
	f.close()
	var name = unique_name(str(raw.get("name", path.get_file().get_basename())))
	d.make_dir_recursive(Globals.p(DIR))
	if d.rename(tmp, path_of(name)) != OK: return "couldn't install the skin"
	return [name, warn]

# ------------------------------------------------------------------ rhythia rewrite skins
# A rewrite skin (Rhythia/Client: user folder skins/<name>/ = config.toml, game/*.png, hit / miss /
# fail / menu .mp3) becomes a skin here: the files it shares with this game go to their slots, its
# HUD images to the rewrite HUD's, its colour set and note shape (config.toml) are looked up in the
# rewrite's user folder (colorsets/, meshes/), else its built-in ones are used. Its menu
# backgrounds ("spaces") and UI button images have no place in this game and are left out.
const RW_FILES = {"cursor.png": "cursor", "grid.png": "rw_grid", "panel_left_background.png": "rw_panel_left",
	"panel_right_background.png": "rw_panel_right", "health.png": "rw_health", "health_background.png": "rw_health_bg",
	"progress.png": "rw_progress", "progress_background.png": "rw_progress_bg", "hits.png": "rw_hits",
	"misses.png": "rw_misses", "hit.mp3": "hit", "miss.mp3": "miss", "fail.mp3": "fail", "menu.mp3": "menu"}
# the rewrite's own colour sets (user/colorsets/*.txt in its repository)
const RW_COLORSETS = {"default": ["ff0059", "ffd8e6"], "cotton candy": ["00ffed", "ff8ff9"], "tan": ["d7af7a", "ebd3b0"],
	"light blue and white": ["0f81b7", "e7eaec"], "café au lait": ["d9b49b", "ffe4cb"],
	"nebula": ["ff64b1", "e864c4", "d264d7", "ba64ec", "a564ff", "ba64ec", "d264d7", "e864c4"],
	"sunset": ["ff6d33", "ff623d", "ff5747", "ff4b50", "ff3f59", "ff3363", "ff3f59", "ff4b50", "ff5747", "ff623d"],
	"tundra": ["ffffff", "c8d9ff", "8fb2ff", "5286ff", "2655ff", "5286ff", "8fb2ff", "c8d9ff", "ffffff"]}
# its note shapes -> ours when its .obj isn't at hand
const RW_MESHES = {"squircle": "ssp_rounded", "square": "ssp_square", "cube": "ssp_block", "plane": "ssp_plane"}

# the rewrite's user folder: next to ours (both are custom user dirs in the same place), or where its
# user_folder_path.txt points
static func rewrite_root() -> String:
	var root = OS.get_user_data_dir().get_base_dir() + "/Rhythia"
	var f = File.new()
	if f.open(root + "/user_folder_path.txt", File.READ) == OK:
		var p = f.get_as_text().strip_edges().replace("\\", "/")
		f.close()
		if p != "" and Directory.new().dir_exists(p): root = p
	return root

# [[name, folder]] of the rewrite skins installed on this computer
static func rewrite_skins() -> Array:
	var out = []
	var dir = rewrite_root() + "/skins"
	var d = Directory.new()
	if d.open(dir) != OK: return out
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		var p = dir + "/" + n
		if d.current_is_dir() and (File.new().file_exists(p + "/config.toml") or Directory.new().dir_exists(p + "/game")): out.append([n, p])
		n = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

static func _read_bytes(p:String):
	var f = File.new()
	if !f.file_exists(p) or f.open(p, File.READ) != OK: return null
	var b = f.get_buffer(f.get_len())
	f.close()
	return b

# config.toml: flat `key = "value"` lines (Tomlyn writes snake_case; PascalCase is read too)
static func _toml(text:String) -> Dictionary:
	var out = {}
	for line in text.split("\n"):
		line = line.strip_edges()
		if line == "" or line.begins_with("#") or line.begins_with("[") or line.find("=") < 0: continue
		var k = line.substr(0, line.find("=")).strip_edges().replace("_", "").to_lower()
		var v = line.substr(line.find("=") + 1).strip_edges()
		if v.begins_with("\"") and v.find("\"", 1) > 0: v = v.substr(1, v.find("\"", 1) - 1)
		out[k] = v
	return out

static func _colors(text:String) -> Array:
	var out = []
	for c in text.replace("\r", "").replace("\n", ",").split(","):
		c = c.strip_edges().trim_prefix("#")
		if c != "" and c.is_valid_html_color(): out.append("#" + c)
	return out

# src = a rewrite skin folder, its config.toml, or a .zip of one -> [name, warnings] or an error String
static func import_rewrite(src:String):
	var files = {}   # file name -> bytes
	var root = ""    # the rewrite user folder the skin sits in ("" for a zip)
	var name = ""
	if src.get_extension().to_lower() == "toml": src = src.get_base_dir()
	if src.get_extension().to_lower() == "zip":
		var want = ["config.toml"]
		for k in RW_FILES: want.append(k)
		var z = load("res://mods/fixes/Phxm.gd")._read_zip(src, want)
		if z is String: return z
		files = z
		name = src.get_file().get_basename()
	else:
		if !Directory.new().dir_exists(src): return "folder not found"
		for k in RW_FILES:
			var b = _read_bytes(src + ("/" if k.ends_with(".mp3") else "/game/") + k)
			if b == null and !k.ends_with(".mp3"): b = _read_bytes(src + "/" + k)
			if b != null: files[k] = b
		var c = _read_bytes(src + "/config.toml")
		if c != null: files["config.toml"] = c
		name = src.get_file()
		root = src.get_base_dir().get_base_dir()
	var found = 0
	for k in RW_FILES:
		if files.has(k): found += 1
	if found == 0 and !files.has("config.toml"): return "not a Rhythia rewrite skin (no config.toml or game/*.png)"
	var cfg = _toml(files["config.toml"].get_string_from_utf8()) if files.has("config.toml") else {}
	var warn = []
	var tmp = Globals.p(TMP) + "/" + str(OS.get_ticks_usec())
	var d = Directory.new()
	d.make_dir_recursive(tmp)
	var f = File.new()
	for k in RW_FILES:
		if !files.has(k): continue
		var out = tmp + "/" + RW_FILES[k] + "." + k.get_extension()
		if f.open(out, File.WRITE) != OK: continue
		f.store_buffer(files[k])
		f.close()
		var err = validate_file(RW_FILES[k], out)
		if err != "":
			warn.append("%s left out: %s" % [k, err])
			d.remove(out)
	var data = {"settings": {}, "author": ""}
	# colour set: the rewrite user folder's file, else its built-in list
	var cs = str(cfg.get("notecolors", "default"))
	var cols = []
	if root != "":
		var b = _read_bytes(root + "/colorsets/" + cs + ".txt")
		if b != null: cols = _colors(b.get_string_from_utf8())
	if cols.empty() and RW_COLORSETS.has(cs.to_lower()):
		for c in RW_COLORSETS[cs.to_lower()]: cols.append("#" + c)
	if !cols.empty():
		data["colors"] = cols
		data["mirror"] = false
	elif cs != "":
		warn.append("colour set \"%s\" not found" % cs)
	# note shape: its .obj from the rewrite user folder, else the nearest of ours
	var mesh = str(cfg.get("notemesh", "squircle"))
	var got_mesh = false
	if root != "" and f.file_exists(root + "/meshes/" + mesh + ".obj"):
		var out = tmp + "/mesh.obj"
		if d.copy(root + "/meshes/" + mesh + ".obj", out) == OK:
			if validate_file("mesh", out) == "": got_mesh = true
			else: d.remove(out)
	if !got_mesh:
		if RW_MESHES.has(mesh.to_lower()): data.settings["selected_mesh"] = RW_MESHES[mesh.to_lower()]
		elif mesh != "": warn.append("note shape \"%s\" not found" % mesh)
	if f.open(tmp + "/skin.json", File.WRITE) != OK: return "can't write the skin"
	f.store_string(JSON.print(data, "\t"))
	f.close()
	name = unique_name(name + " (rewrite)")
	d.make_dir_recursive(Globals.p(DIR))
	if d.rename(tmp, path_of(name)) != OK: return "couldn't install the skin"
	return [name, warn]
