extends Reference
# Rhythia-reimagined settings: user://reimagined.json (cursor trail, HUD layout, interface),
# skin overrides from user://reimagined_skin/<slot>.png and map collections
# (user://collections.json). Everything is static; caches live in Engine metas.

const FILE = "user://reimagined.json"
const COLL_FILE = "user://collections.json"
const SKIN_DIR = "user://reimagined_skin"
const DEFAULTS = {
	"trail_style": "game",      # game = the game's own trail (Settings) | osu | off
	"trail_color": "",          # "" = cursor colour, else html colour
	"trail_alpha": 1.0,
	"trail_length": 1.0,        # osu! trail lifetime multiplier
	"trail_size": 1.0,
	"hud": {},                  # HUD sprite -> [dx, dy, scale, shown]
	"hide_config_hud": true,    # HIT WINDOW / HITBOX SIZE panel at the start of a map
	"hide_hitbox_text": true,   # "Default hitboxes, default hitwindow" on the map page
	"sort": "stars",            # map list: stars | name | mapper
	"collection": "",           # map list filter ("" = all maps)
	"half_ghost_length": 1.0,   # Half Ghost: how long the notes take to fade (1.0 = game default)
	"swept_hitbox": true,
	"lite_fx": false,           # lighter effects for low-end PCs (also switched on for the session by fps_watch)       # count notes the cursor passes through between frames (NoteManager)
	"title_bg": "rain",         # title screen background: rain | snow | waves (topographic)
}
# side panels the layout editor moves: sprite, label, default centre (world x, y), size (w, h)
const HUD_ITEMS = [
	["LeftHud", "ACCURACY / COMBO", Vector2(-1.957, 0), Vector2(0.99, 2.97)],
	["RightHud", "SCORE / MISSES", Vector2(1.957, 0), Vector2(0.99, 2.97)],
	["TimerHud", "TIMER", Vector2(0, 1.98), Vector2(2.97, 0.42)],
	["EnergyHud", "HEALTH / MODS", Vector2(0, -2.02), Vector2(2.97, 0.42)],
]
# skin slots: file name (no .png), label, description
const SKIN_SLOTS = [
	["border", "Play area border", "frame around the grid"],
	["grid", "Play area grid", "3x3 lines inside the border"],
	["trail", "osu! trail dot", "one dot of the osu! cursor trail"],
	["logo", "Title logo", "the big logo on the title screen"],
]

# ------------------------------------------------------------------ settings
static func cfg() -> Dictionary:
	if Engine.has_meta("rr_cfg"): return Engine.get_meta("rr_cfg")
	var c = DEFAULTS.duplicate(true)
	var d = _read(FILE)
	for k in d:
		if c.has(k) and typeof(d[k]) == typeof(c[k]): c[k] = d[k]
	Engine.set_meta("rr_cfg", c)
	return c

static func val(k:String):
	return cfg()[k]

# Lighter effects: no full-screen colour split, no title-logo effect. On when the player picks it
# (Customize > Interface) or, for this session, when the effects keep the game under 40 fps.
static func lite() -> bool:
	return bool(val("lite_fx")) or Engine.has_meta("rr_auto_lite")

# call every frame while heavy effects run: ~3 s in total under 40 fps (with no fps cap below 45)
# switches lighter effects on for the rest of the session
static func fps_watch(delta:float):
	if Engine.has_meta("rr_auto_lite"): return
	if Engine.target_fps != 0 and Engine.target_fps < 45: return
	var slow = Engine.get_meta("rr_slow_s") if Engine.has_meta("rr_slow_s") else 0.0
	if Engine.get_frames_per_second() < 40 and delta < 0.5: slow += delta
	else: slow = max(0.0, slow - delta * 0.25)
	Engine.set_meta("rr_slow_s", slow)
	if slow > 3.0:
		Engine.set_meta("rr_auto_lite", true)
		print("Rhythia-reimagined: low fps, lighter effects on for this session")

static func set_val(k:String, v):
	cfg()[k] = v
	save()

static func save():
	_write(FILE, cfg())

static func hud_entry(sprite:String) -> Array: # [dx, dy, scale, shown]
	var h = cfg().hud
	if h.has(sprite) and h[sprite] is Array and h[sprite].size() == 4: return h[sprite]
	return [0.0, 0.0, 1.0, true]

static func trail_color(fallback:Color) -> Color:
	var s = str(cfg().trail_color)
	return Color(s) if s != "" else fallback

static func _read(path:String) -> Dictionary:
	var f = File.new()
	if f.open(Globals.p(path), File.READ) != OK: return {}
	var d = parse_json(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

static func _write(path:String, d:Dictionary):
	var f = File.new()
	if f.open(Globals.p(path), File.WRITE) == OK:
		f.store_string(to_json(d))
		f.close()

# ------------------------------------------------------------------ skin
static func skin_dir() -> String:
	return Globals.p(SKIN_DIR)

static func skin_path(slot:String) -> String:
	return skin_dir() + "/" + slot + ".png"

static func skin_tex(slot:String) -> Texture:
	var cache:Dictionary = Engine.get_meta("rr_skin") if Engine.has_meta("rr_skin") else {}
	if cache.has(slot): return cache[slot]
	var t = null
	var p = skin_path(slot)
	if File.new().file_exists(p):
		var img = Image.new()
		if img.load(p) == OK:
			t = ImageTexture.new()
			t.create_from_image(img)
	cache[slot] = t
	Engine.set_meta("rr_skin", cache)
	return t

static func skin_reload():
	Engine.set_meta("rr_skin", {})

# copy an image file into the skin folder as <slot>.png
static func skin_set(slot:String, from:String) -> bool:
	var img = Image.new()
	if img.load(from) != OK: return false
	var d = Directory.new()
	d.make_dir_recursive(skin_dir())
	var ok = img.save_png(skin_path(slot)) == OK
	skin_reload()
	return ok

static func skin_clear(slot:String):
	var p = skin_path(slot)
	if File.new().file_exists(p): OS.move_to_trash(ProjectSettings.globalize_path(p))
	skin_reload()

# sidebar icons can be replaced too: icon_<button name>.png
static func apply_sidebar_icons(menu:Node):
	var l = menu.get_node_or_null("Sidebar/L")
	if !l: return
	var I = load("res://mods/replay/Icons.gd")
	for b in l.get_children():
		var tex = b.get_node_or_null("Tex")
		if !(tex is TextureRect): continue
		if !tex.has_meta("rr_default"): tex.set_meta("rr_default", tex.texture)
		var t = skin_tex("icon_" + b.name.to_lower())
		var ic = I.SIDEBAR.get(b.name.to_lower(), "") if I.available() else ""
		var g = tex.get_node_or_null("RRGlyph")
		if ic != "" and !g: # Flaticon icon replaces the stock one
			g = I.Glyph.new(ic, 0.85)
			g.name = "RRGlyph"
			g.anchor_right = 1
			g.anchor_bottom = 1
			tex.add_child(g)
		tex.texture = t if t else (null if g else tex.get_meta("rr_default"))
		for ch in tex.get_children(): ch.visible = t == null and (g == null or ch == g) # drawn icon

# ------------------------------------------------------------------ collections
static func collections() -> Dictionary: # name -> [song ids]
	if Engine.has_meta("rr_coll"): return Engine.get_meta("rr_coll")
	var c = {}
	var d = _read(COLL_FILE)
	for k in d:
		if d[k] is Array: c[str(k)] = d[k]
	Engine.set_meta("rr_coll", c)
	return c

static func save_collections():
	_write(COLL_FILE, collections())
	if Engine.get_main_loop(): Engine.get_main_loop().call_group("rr_collections", "_rr_collections_changed")

static func coll_has(name:String, id:String) -> bool:
	return collections().has(name) and collections()[name].has(id)

static func coll_toggle(name:String, id:String):
	var c = collections()
	if !c.has(name): c[name] = []
	if c[name].has(id): c[name].erase(id)
	else: c[name].append(id)
	save_collections()

static func coll_create(name:String) -> bool:
	name = name.strip_edges()
	if name == "" or collections().has(name): return false
	collections()[name] = []
	save_collections()
	return true

static func coll_rename(old:String, new:String) -> bool:
	new = new.strip_edges()
	var c = collections()
	if new == "" or c.has(new) or !c.has(old): return false
	c[new] = c[old]
	c.erase(old)
	if cfg().collection == old: set_val("collection", new)
	save_collections()
	return true

static func coll_delete(name:String):
	collections().erase(name)
	if cfg().collection == name: set_val("collection", "")
	save_collections()

# ------------------------------------------------------------------ small drawn icon (sidebar button)
class SlidersIcon extends Control:
	func _ready():
		mouse_filter = MOUSE_FILTER_IGNORE
	func _draw():
		var w = rect_size.x
		var h = rect_size.y
		var col = Color(1, 1, 1, 0.92)
		for i in 3:
			var y = h * (0.25 + i * 0.25)
			draw_line(Vector2(w * 0.12, y), Vector2(w * 0.88, y), col, 3.0)
			var x = w * [0.68, 0.32, 0.55][i]
			draw_circle(Vector2(x, y), w * 0.11, Color(0, 0, 0))
			draw_arc(Vector2(x, y), w * 0.11, 0, TAU, 20, col, 3.0, true)
