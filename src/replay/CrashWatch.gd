extends Node
# Crash report (Rhythia-reimagined), mainly for phones: a marker file is written while the game
# runs and removed when it closes normally (or goes to the background - Android may kill it there
# without a crash). If the marker is still there at the next start, the last session crashed:
# the menu offers its log (the game keeps the previous logs, see ssp_mod.py file_logging).
# The engine doesn't flush plain log lines, so a crash loses the last seconds of the log: the marker
# also holds a short trail (every 2 s: screen, song, video memory), written and closed each time.

const MARK = "user://.rr_running"
const LOG_DIR = "user://logs" # (the engine's own user:// - NOT Globals.p, which points elsewhere on Android)

static func start(tree:SceneTree):
	if Engine.has_meta("rr_crashwatch"): return
	var crashed = File.new().file_exists(Globals.p(MARK))
	if crashed:
		var f = File.new()
		if f.open(Globals.p(MARK), File.READ) == OK:
			Engine.set_meta("rr_crash_trail", f.get_as_text())
			f.close()
	var n = load("res://mods/replay/CrashWatch.gd").new()
	n.name = "CrashWatch"
	Engine.set_meta("rr_crashwatch", n)
	Engine.set_meta("rr_crashed", crashed)
	tree.root.call_deferred("add_child", n)

# the crashed session's last moments ("" when there are none)
static func trail() -> String:
	if !crashed() or !Engine.has_meta("rr_crash_trail"): return ""
	var t = str(Engine.get_meta("rr_crash_trail"))
	return t if t.find(char(10)) >= 0 else "" # (old marker: just a timestamp)

static func crashed() -> bool:
	return Engine.has_meta("rr_crashed") and Engine.get_meta("rr_crashed")

# the newest old log (the session before this one), or ""
static func previous_log() -> String:
	var d = Directory.new()
	if d.open(LOG_DIR) != OK: return ""
	var best = ""
	d.list_dir_begin(true, true)
	var f = d.get_next()
	while f != "":
		if f.begins_with("godot") and f.ends_with(".log") and f != "godot.log" and f > best: best = f
		f = d.get_next()
	d.list_dir_end()
	return LOG_DIR + "/" + best if best != "" else ""

var lines:Array = []
var active:bool = false
var t0:int = 0
var acc:float = 0.0

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	t0 = OS.get_ticks_msec()
	_mark(true)

func _process(delta):
	acc += delta
	if acc < 2.0 or !active: return
	acc = 0.0
	lines.append(_now())
	if lines.size() > 15: lines.pop_front()
	_write()

# one trail line: time since start, scene, what's open on it, video memory
func _now() -> String:
	var tr = get_tree()
	var sc = tr.current_scene
	var what = sc.filename.get_file().get_basename() if sc and sc.filename != "" else (sc.name if sc else "?")
	var m = tr.root.get_node_or_null("Menu")
	if m:
		for n in ["ResultsScreen", "Editor", "Multiplayer", "ReplayBrowser", "ReimaginedPanel", "MapBrowser"]:
			var c = m.get_node_or_null(n)
			if c and c.get("visible") != false and !(n == "MapBrowser" and c.get("hidden")): what += " +" + n
	if what.begins_with("song") and Rhythia.selected_song: what += " map=" + str(Rhythia.selected_song.id)
	var mp = tr.root.get_node_or_null("RRMultiplayer")
	if mp and mp.status != "idle": what += " mp=%s/%s%s" % [mp.status, mp.phase, "/host" if mp.hosting() else ""]
	return "%5ds  %s  vram %.0f MB  tex %.0f MB  objects %d  fps %d" % [(OS.get_ticks_msec() - t0) / 1000,
		what, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_COUNT), Engine.get_frames_per_second()]

func _write():
	var f = File.new()
	if f.open(Globals.p(MARK), File.WRITE) == OK:
		f.store_string(str(OS.get_unix_time()) + char(10) + PoolStringArray(lines).join(char(10)) + char(10))
		f.close()

func _mark(on:bool):
	active = on
	if on: _write()
	else: Directory.new().remove(Globals.p(MARK))

func _notification(what):
	match what:
		NOTIFICATION_WM_QUIT_REQUEST, NOTIFICATION_APP_PAUSED: _mark(false)
		NOTIFICATION_APP_RESUMED: _mark(true)

func _exit_tree():
	_mark(false)
