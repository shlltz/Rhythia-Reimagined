extends Node
# Crash report (Rhythia-reimagined), mainly for phones: a marker file is written while the game
# runs and removed when it closes normally (or goes to the background - Android may kill it there
# without a crash). If the marker is still there at the next start, the last session crashed:
# the menu offers its log (the game keeps the previous logs, see ssp_mod.py file_logging).

const MARK = "user://.rr_running"
const LOG_DIR = "user://logs"

static func start(tree:SceneTree):
	if Engine.has_meta("rr_crashwatch"): return
	var crashed = File.new().file_exists(Globals.p(MARK))
	var n = load("res://mods/replay/CrashWatch.gd").new()
	n.name = "CrashWatch"
	Engine.set_meta("rr_crashwatch", n)
	Engine.set_meta("rr_crashed", crashed)
	tree.root.call_deferred("add_child", n)

static func crashed() -> bool:
	return Engine.has_meta("rr_crashed") and Engine.get_meta("rr_crashed")

# the newest old log (the session before this one), or ""
static func previous_log() -> String:
	var d = Directory.new()
	if d.open(Globals.p(LOG_DIR)) != OK: return ""
	var best = ""
	d.list_dir_begin(true, true)
	var f = d.get_next()
	while f != "":
		if f.begins_with("godot") and f.ends_with(".log") and f != "godot.log" and f > best: best = f
		f = d.get_next()
	d.list_dir_end()
	return Globals.p(LOG_DIR) + "/" + best if best != "" else ""

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	_mark(true)

func _mark(on:bool):
	var p = Globals.p(MARK)
	if on:
		var f = File.new()
		if f.open(p, File.WRITE) == OK:
			f.store_string(str(OS.get_unix_time()))
			f.close()
	else:
		Directory.new().remove(p)

func _notification(what):
	match what:
		NOTIFICATION_WM_QUIT_REQUEST, NOTIFICATION_APP_PAUSED: _mark(false)
		NOTIFICATION_APP_RESUMED: _mark(true)

func _exit_tree():
	_mark(false)
