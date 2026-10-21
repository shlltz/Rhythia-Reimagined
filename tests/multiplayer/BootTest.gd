extends Node
# launch fixes: no stock intro cutscene, no update check (also with networking off: stock hung),
# one logo intro, the removed options hidden in settings. Output @@OUT@@/boot.txt
const OUT = "@@OUT@@/boot.txt"
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

func _ready():
	Directory.new().remove(OUT)
	out("startup %d ms" % OS.get_ticks_msec())
	call_deferred("run")

func run():
	ok("menu reached without the 30 s cutscene", OS.get_ticks_msec() < 20000, "%d ms" % OS.get_ticks_msec())
	ok("update check off", Rhythia.disable_update)
	var intros = 0
	for c in get_tree().root.get_children():
		if c.get_script() and "intro/Intro.gd" in str(c.get_script().resource_path): intros += 1
	ok("at most one logo intro", intros <= 1, intros)
	yield(get_tree().create_timer(3.0), "timeout")
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("settings")
	yield(get_tree().create_timer(1.5), "timeout")
	var f = menu.get_node("Main/Settings/S/F")
	var hidden = true
	for p in ["TopButtons/TopButtonsHBox/CheckForUpdate", "TabContainer/Replays & Misc/Recording/Group/H/DisableAutoUpdate",
			"TabContainer/Replays & Misc/Experimental/Group/H/Intro", "TabContainer/Replays & Misc/Experimental/Group/H/DisableIntro"]:
		var n = f.get_node_or_null(p)
		if !n or n.visible: hidden = false
	ok("update / cutscene options hidden", hidden)
	var ss = menu.get_node("SettingsStyle")
	ss.search.text = "cutscene"
	ss._search(ss.search.text)
	ok("search doesn't bring them back", ss.search_info.text == "no settings match", ss.search_info.text)
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
