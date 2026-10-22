extends Node
# Customize > HUD layout: the window grows with the screen, Rewrite / Legacy switch, panels and the
# parts inside them moved / sized / hidden with the mouse handlers and the sliders, and a run puts
# them on the real HUD nodes in both styles.
# Output @@OUT@@/hudlayout.txt + l_*.png
const OUT = "@@OUT@@/hudlayout.txt"
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
	var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/l_" + n + ".png")

func play(secs = 3.0):
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

func click(ctl:Control, at:Vector2, button = BUTTON_LEFT, pressed = true, dbl = false):
	var e = InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.doubleclick = dbl
	e.position = at
	ctl._gui_input(e)

func drag(ctl:Control, a:Vector2, b:Vector2):
	click(ctl, a)
	var m = InputEventMouseMotion.new()
	m.position = b
	ctl._gui_input(m)
	click(ctl, b, BUTTON_LEFT, false)

func open_panel():
	var menu = get_tree().current_scene
	menu.open_customize()
	yield(wait(0.8), "completed")
	var p = menu.get_node_or_null("ReimaginedPanel")
	if p: p.show_tab("hud", false)
	yield(wait(0.4), "completed")
	return p

func close_panel(p):
	p.close()
	yield(wait(0.6), "completed")

func idx(name):
	var R = load("res://mods/replay/Reimagined.gd")
	for i in R.HUD_ITEMS.size():
		if R.HUD_ITEMS[i][0] == name: return i
	return -1

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var R = load("res://mods/replay/Reimagined.gd")
	var P = load("res://mods/replay/HudParts.gd")
	ok("HudParts.gd installed", P != null)

	# small window: the old size
	var p = yield(open_panel(), "completed")
	ok("panel opens", p != null)
	if !p:
		out("== totals: %d passed, %d failed" % [passed, failed]); OS.kill(OS.get_process_id()); return
	ok("1280x720: card fits the screen", p.W <= 1280 and p.H <= 720 and p.W >= 1060, "%s x %s" % [p.W, p.H])
	shot("small")
	yield(close_panel(p), "completed")

	# big window
	OS.window_size = Vector2(1920, 1080)
	yield(wait(1.0), "completed")
	p = yield(open_panel(), "completed")
	ok("1920x1080: bigger card", p.W > 1400 and p.H > 900, "%s x %s" % [p.W, p.H])
	ok("1920x1080: bigger text", p.ui_k > 1.1, p.ui_k)
	ok("layout switch: rewrite picked", P.style() == "rewrite")
	ok("part editor empty until a panel is picked", p.part_ed.panel == "")

	# pick the right panel in the panel editor, then its accuracy part
	var ed = p.hud_ed
	var ri = idx("RightHud")
	var rc = ed.rect_of(ri)
	click(ed, rc.position + rc.size / 2)
	click(ed, rc.position + rc.size / 2, BUTTON_LEFT, false)
	ok("click picks a panel", ed.sel == ri and p.hud_t.get("panel") == "RightHud", p.hud_t)
	ok("its parts show", p.part_ed.panel == "RightHud" and p.part_ed.items().size() == 4)
	var pe = p.part_ed
	var ai = -1
	for i in pe.items().size():
		if pe.items()[i][0] == "acc": ai = i
	var ar = pe.rect_of(ai)
	drag(pe, ar.position + ar.size / 2, ar.position + ar.size / 2 + Vector2(0, 60))
	var e = P.entry("rewrite", "RightHud", "acc")
	ok("drag moves a part (panel pixels)", e[1] > 40 and e[0] == 0.0, e)
	ok("sliders follow the picked part", p.hud_t.get("part") == "acc" and abs(p.hud_w.y.get_child(0).value - float(e[1])) < 0.5, p.hud_w.y.get_child(0).value)
	p.hud_w.size.get_child(0).value = 1.5
	ok("size slider sets the part", abs(float(P.entry("rewrite", "RightHud", "acc")[2]) - 1.5) < 0.01)
	var si = -1
	for i in pe.items().size():
		if pe.items()[i][0] == "sum": si = i
	var sr = pe.rect_of(si)
	click(pe, sr.position + sr.size / 2, BUTTON_RIGHT)
	ok("right-click hides a part", !bool(P.entry("rewrite", "RightHud", "sum")[3]))
	# the panel itself, with the slider
	click(ed, rc.position + rc.size / 2)
	click(ed, rc.position + rc.size / 2, BUTTON_LEFT, false)
	p.hud_w.x.get_child(0).value = 0.5
	ok("x slider moves the panel", abs(float(R.hud_entry("RightHud")[0]) - 0.5) < 0.01, R.hud_entry("RightHud"))
	# the combo number is a panel too
	ok("combo is in the layout", idx("ComboHud") >= 0)
	# a timer part
	var ti = idx("TimerHud")
	var tc = ed.rect_of(ti)
	click(ed, tc.position + tc.size / 2)
	click(ed, tc.position + tc.size / 2, BUTTON_LEFT, false)
	var bi = -1
	for i in pe.items().size():
		if pe.items()[i][0] == "title": bi = i
	pe.sel = bi
	p._part_picked(bi)
	p.hud_w.y.get_child(0).value = -40
	ok("title part moved up", float(P.entry("rewrite", "TimerHud", "title")[1]) == -40.0)
	yield(wait(0.3), "completed")
	shot("big")
	var saved = File.new().file_exists(Globals.p("user://reimagined.json"))
	ok("saved", saved)
	yield(close_panel(p), "completed")

	# the run: rewrite parts on their nodes
	var g = yield(play(), "completed")
	var rw = g.get_node("HUD/RRRewriteHud")
	var base_y = 270.0
	ok("run: accuracy moved down + bigger", rw.acc.rect_position.y > base_y + 40 and abs(rw.acc.rect_scale.x - 1.5) < 0.01, "%s %s" % [rw.acc.rect_position, rw.acc.rect_scale])
	ok("run: notes count hidden", !rw.sum.visible)
	ok("run: title moved up", rw.title.rect_position.y < 60 - 30, rw.title.rect_position)
	var rh = g.get_node("HUD/RightHud")
	ok("run: right panel moved", rh.transform.origin.x > 1.957 + 0.4, rh.transform.origin)
	shot("run_rewrite")
	yield(back(g), "completed")

	# legacy: its own parts
	p = yield(open_panel(), "completed")
	for b in p.get_tree().get_nodes_in_group("__none__"): pass
	p._hud_style("legacy")
	ok("switch to legacy saves", R.val("hud_style") == "classic")
	ok("alt combo greys out on legacy", p.hud_w.alt.disabled)
	p._hud_picked(idx("LeftHud"))
	var li = -1
	for i in p.part_ed.items().size():
		if p.part_ed.items()[i][0] == "grade": li = i
	p.part_ed.sel = li
	p._part_picked(li)
	p.hud_w.x.get_child(0).value = 30
	p.hud_w.size.get_child(0).value = 0.6
	ok("legacy part saved", P.entry("legacy", "LeftHud", "grade") == [30.0, 0.0, 0.6, true], P.entry("legacy", "LeftHud", "grade"))
	ok("rewrite parts kept apart", float(P.entry("rewrite", "RightHud", "acc")[2]) == 1.5)
	yield(close_panel(p), "completed")
	g = yield(play(), "completed")
	var lg = g.get_node("HUD/LeftVP/Control/LetterGrade")
	ok("run: legacy grade moved + smaller", !g.get_node("HUD").has_node("RRRewriteHud") and lg.rect_position.x == 30.0 and abs(lg.rect_scale.x - 0.6) < 0.01, "%s %s" % [lg.rect_position, lg.rect_scale])
	shot("run_legacy")
	yield(back(g), "completed")

	# reset
	p = yield(open_panel(), "completed")
	p._hud_reset_parts()
	p._hud_reset()
	p._hud_style("rewrite")
	ok("reset parts + panels", P.entry("legacy", "LeftHud", "grade") == [0.0, 0.0, 1.0, true] and R.cfg().hud.empty())
	yield(close_panel(p), "completed")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
