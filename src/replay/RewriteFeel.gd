extends Node
# "Rewrite Feel" (Customize > Gameplay): runs play with the Rhythia rewrite's default look
# (Rhythia/Client @9200e16: SettingsProfile.cs defaults, NoteRenderer.cs, CameraLock.cs) -
# approach rate 30 at distance 15, FoV 70, camera sway 0.25 of the cursor (= parallax 10 here)
# with the grid and HUD still, and its note fade + pushback (NoteManager.rw_feel). Gameplay itself
# (hitbox, hit window, timing, cursor) is already the same in both games.
# The player's own values are swapped in for the run only: songload applies, and an instance of
# this script on the root (RRFeelWatch) restores them the moment a menu scene enters the tree -
# before its settings page reads them (restoring in menu2._ready was too late: the page's boxes
# had already taken the run's values and wrote them back). A file keeps them meanwhile; after a
# closed / crashed run Boot.gd restores from it at startup, before the menu exists.

const FILE = "user://rr_feel_restore.json"
const MENUS = ["res://scenes/loaders/menuload.tscn", "res://scenes/menu/menu2.tscn", "res://scenes/menu/oldmenu2.tscn"]
const VALUES = {"approach_rate": 30.0, "spawn_distance": 15.0, "fov": 70.0, "parallax": 10.0, "ui_parallax": 0.0, "grid_parallax": 0.0}

static func on() -> bool:
	return ResourceLoader.exists("res://mods/replay/Reimagined.gd") and bool(load("res://mods/replay/Reimagined.gd").val("rewrite_feel"))

static func active() -> bool:
	return Engine.has_meta("rr_feel_saved")

# songload: before the game scene (NoteManager / Camera read these when they are made)
static func apply():
	if active() or !on(): return
	var saved = {}
	for k in VALUES: saved[k] = Rhythia.get(k)
	var f = File.new()
	if f.open(FILE, File.WRITE) == OK:
		f.store_string(to_json(saved))
		f.close()
	Engine.set_meta("rr_feel_saved", saved)
	for k in VALUES: Rhythia.set(k, VALUES[k])
	var root = Engine.get_main_loop().root
	if !root.has_node("RRFeelWatch"):
		var w = load("res://mods/replay/RewriteFeel.gd").new()
		w.name = "RRFeelWatch"
		root.call_deferred("add_child", w)

# the watcher (RRFeelWatch)
func _ready():
	get_tree().connect("node_added", self, "_added")

func _added(n:Node):
	if n.get_parent() == get_tree().root and n.filename in MENUS:
		restore()
		queue_free()

# menu: the player's own values back (from the file after a closed / crashed run, then saved)
static func restore():
	var saved = {}
	var from_file = !active()
	if !from_file:
		saved = Engine.get_meta("rr_feel_saved")
		Engine.remove_meta("rr_feel_saved")
	else:
		var f = File.new()
		if !f.file_exists(FILE) or f.open(FILE, File.READ) != OK: return
		var r = JSON.parse(f.get_as_text())
		f.close()
		if r.error == OK and typeof(r.result) == TYPE_DICTIONARY: saved = r.result
	Directory.new().remove(FILE)
	for k in saved:
		if VALUES.has(k): Rhythia.set(k, float(saved[k]))
	if from_file and !saved.empty() and Rhythia.has_method("save_settings"):
		Rhythia.save_settings()
		print("[feel] restored the settings Rewrite Feel had swapped for a run")
