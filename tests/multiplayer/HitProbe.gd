extends Node
# What does one note hit cost? In a running map (autoplay), times each part of NoteManager's hit
# path 60 times (3 per frame): hit effect copy + spawn, score popup, hit sound, Game.hit (score /
# HUD) and the "hit" signal listeners. Output @@OUT@@/hits.txt
const OUT = "@@OUT@@/hits.txt"

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func timed(tag, obj, fn, args, acc):
	var t0 = OS.get_ticks_usec()
	obj.callv(fn, args)
	var dt = (OS.get_ticks_usec() - t0) / 1000.0
	if !acc.has(tag): acc[tag] = []
	acc[tag].append(dt)

func run():
	Directory.new().remove(OUT)
	yield(wait(9.0), "completed")
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	Rhythia.select_song(song)
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = ""
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var g = null
	var t = 0.0
	while t < 30 and !g:
		yield(wait(0.25), "completed"); t += 0.25
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game") and sc.get_node("Game/Spawn").active: g = sc.get_node("Game")
	yield(wait(3.0), "completed")
	var sp = g.get_node("Spawn")
	out("settings: hit effect %s, at cursor %s, score popup %s, hit sound %s, sfx_2d %s" % [Rhythia.show_hit_effect, Rhythia.hit_effect_at_cursor, Rhythia.score_popup, Rhythia.play_hit_snd, Rhythia.sfx_2d])
	out("hit listeners: %s" % str(sp.get_signal_connection_list("hit")))
	var acc = {}
	var col = Color(1, 0.4, 0.6)
	var pos = Vector3(1, -1, 0.002)
	var tr = Transform(Basis(), Vector3(1, -1, 0))
	for k in 20:
		for j in 3:
			var t0 = OS.get_ticks_usec()
			var fx = sp.hitEffect.duplicate()
			var t1 = OS.get_ticks_usec()
			fx.spawn(g, pos, col, sp.hit_id, false)
			var t2 = OS.get_ticks_usec()
			if !acc.has("hit fx duplicate"): acc["hit fx duplicate"] = []; acc["hit fx spawn"] = []
			acc["hit fx duplicate"].append((t1 - t0) / 1000.0)
			acc["hit fx spawn"].append((t2 - t1) / 1000.0)
			timed("score popup dup+spawn", self, "_score", [sp, g, pos, col], acc)
			timed("hit sound", SFXManager, "play_hitsfx", [tr], acc)
			timed("Game.hit (score/HUD)", g, "hit", [col], acc)
			timed("emit hit signal", sp, "emit_signal", ["hit", col], acc)
		yield(get_tree(), "idle_frame")
	for k in acc.keys():
		var a = acc[k]
		var tot = 0.0
		var mx = 0.0
		for x in a:
			tot += x
			mx = max(mx, x)
		out("%-24s mean %6.3f ms   max %6.3f ms   (x%d)" % [k, tot / a.size(), mx, a.size()])
	out("== done")
	OS.kill(OS.get_process_id())

func _score(sp, g, pos, col):
	sp.scoreEffect.duplicate().spawn(g, pos, col, 300)
