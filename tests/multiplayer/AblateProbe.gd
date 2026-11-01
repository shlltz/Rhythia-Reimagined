extends Node
# Where gameplay frame time goes: autoplays @@MAP1@@ (vsync off, uncapped) and switches one part
# off at a time for a short window, with a control window (nothing off) between every two, so slow
# drift (thermal, song density) cancels out. Per window: mean / p50 / p99 frame time.
# Parts: hud (every HUD viewport + sprite), notes (note MultiMeshes), trail (cursor trail spawning),
# cursor, grid (border meshes), fps (the FPS counter), scripts_nm (NoteManager processing paused:
# notes freeze - shows its script cost; hits stop for that window).
# Run with RR_USER_SETTINGS=1 to use the player's own settings. Output: @@OUT@@/ablate.txt
const OUT = "@@OUT@@/ablate.txt"
const WIN = 2.5
var last_us = 0
var frames = []
var capturing = false

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func _process(_d):
	OS.vsync_enabled = false
	Engine.target_fps = 0
	var u = OS.get_ticks_usec()
	if capturing and last_us > 0:
		frames.append((u - last_us) / 1000.0)
	last_us = u

func song(file):
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == file: return s
	return null

func menu_ready():
	var t = 0.0
	while t < 30:
		yield(wait(0.25), "completed"); t += 0.25
		var sc = get_tree().current_scene
		if !sc or sc.name != "Menu": continue
		var tm = sc.get_node_or_null("TitleMenu")
		if tm and tm.visible:
			tm._close("")
			yield(wait(1.0), "completed")
		return

func start(s):
	Rhythia.select_song(s)
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = ""
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var t0 = OS.get_ticks_msec()
	while OS.get_ticks_msec() - t0 < 60000:
		yield(get_tree(), "idle_frame")
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"):
			var g = sc.get_node("Game")
			if g.has_node("Spawn") and g.get_node("Spawn").active: return g
	return null

func toggle(g, part:String, off:bool):
	var sp = g.get_node("Spawn")
	match part:
		"hud": g.get_node("HUD").visible = !off
		"hudvp": # the viewports stop rendering (their sprites keep the last picture)
			var h = g.get_node("HUD")
			if off:
				saved_pairs = h.vp_pairs
				h.vp_pairs = []
				for pr in saved_pairs: pr[0].render_target_update_mode = Viewport.UPDATE_DISABLED
			else:
				h.vp_pairs = saved_pairs
				for pr in saved_pairs: pr[0].render_target_update_mode = Viewport.UPDATE_ALWAYS
		"notes":
			sp.get_node("Notes").visible = !off
			sp.get_node("ASq").visible = !off
		"trail": Rhythia.cursor_trail = !off if off else trail_was
		"cursor": sp.get_node("Cursor").visible = !off
		"grid":
			sp.get_node("Outer").visible = !off
			sp.get_node("Inner").visible = !off
		"fps":
			var fc = get_tree().root.get_node_or_null("FpsCounter")
			if fc: fc.hold(off)
		"scripts_nm": sp.set_process(!off)

var trail_was = true
var saved_pairs = []

func measure(tag:String, g) -> Dictionary:
	frames = []; last_us = 0
	capturing = true
	yield(wait(WIN), "completed")
	capturing = false
	var f = frames.duplicate(); f.sort()
	var n = f.size()
	if n == 0 or !is_instance_valid(g): return {}
	var tot = 0.0
	for x in f: tot += x
	return {tag = tag, n = n, mean = tot / n, p50 = f[n / 2], p99 = f[int(n * 0.99)]}

func run():
	Directory.new().remove(OUT)
	out("== ablate @@NAME@@ (%s, %s)" % [OS.get_video_driver_name(OS.get_current_video_driver()), OS.get_processor_name()])
	yield(wait(6.0), "completed")
	yield(menu_ready(), "completed")
	trail_was = Rhythia.cursor_trail
	out("settings: trail %s smart %s detail %s time %s, hit fx %s, spawn fx %s, approach sq %s, hud %s" % [Rhythia.cursor_trail, Rhythia.smart_trail,
		Rhythia.trail_detail, Rhythia.trail_time, Rhythia.show_hit_effect, Rhythia.note_spawn_effect, Rhythia.note_visual_approach,
		load("res://mods/replay/Reimagined.gd").val("hud_style")])
	var parts = ["hud", "hudvp", "notes", "trail", "cursor", "grid", "fps", "scripts_nm"]
	var acc = {}
	var rounds = int(OS.get_environment("RR_ABLATE_ROUNDS")) if OS.get_environment("RR_ABLATE_ROUNDS") != "" else 2
	out("rounds %d, map %s" % [rounds, str(song("@@MAP1@@"))])
	for r in range(rounds):
		var g = yield(start(song("@@MAP1@@")), "completed")
		if !g:
			out("no game")
			break
		yield(wait(3.0), "completed")
		for p in parts:
			if !is_instance_valid(g) or g.ending: break
			var c = yield(measure("ctl", g), "completed")
			toggle(g, p, true)
			yield(wait(0.3), "completed")
			var a = yield(measure(p, g), "completed")
			if is_instance_valid(g): toggle(g, p, false)
			yield(wait(0.3), "completed")
			if c.empty() or a.empty(): continue
			if !acc.has(p): acc[p] = []
			acc[p].append([c.mean - a.mean, c.p50 - a.p50, c.p99 - a.p99, c.mean])
			out("r%d %-10s ctl mean %.3f p50 %.3f p99 %.3f | off mean %.3f p50 %.3f p99 %.3f" % [r, p,
				c.mean, c.p50, c.p99, a.mean, a.p50, a.p99])
		if is_instance_valid(g): g.end(Globals.END_GIVEUP)
		yield(wait(4.0), "completed")
		var rs = get_tree().current_scene.get_node_or_null("ResultsScreen") if get_tree().current_scene else null
		if rs: rs.queue_free()
	out("-- saved per frame by switching the part off (ms; mean of rounds): mean / p50 / p99, of a control mean")
	for p in parts:
		if !acc.has(p): continue
		var s = [0.0, 0.0, 0.0, 0.0]
		for row in acc[p]:
			for i in 4: s[i] += row[i] / acc[p].size()
		out("%-10s %.3f / %.3f / %.3f  (ctl %.3f)" % [p, s[0], s[1], s[2], s[3]])
	out("== done")
	OS.kill(OS.get_process_id())
