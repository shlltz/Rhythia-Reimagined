extends Node
# HUD viewports render only when something in them changes (HUD.gd vp_mark). This checks that no
# change is missed: during an autoplay of @@MAP1@@, 24 times at random moments it pauses the game,
# lets pending renders land, grabs every shown HUD viewport, forces one more render and grabs it
# again. A difference means the panel was showing stale content. Viewports that render on every
# frame anyway (shining SS grade, pause / give-up) are skipped and counted.
# RR_HUD_STYLE=classic|rewrite picks the HUD. Output: @@OUT@@/hudvp.txt (+ hud_<n>.png)
const OUT = "@@OUT@@/hudvp.txt"

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func frames(n):
	for i in n: yield(VisualServer, "frame_post_draw")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func song(file):
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == file: return s
	return null

func sig(vp:Viewport) -> String:
	var img = vp.get_texture().get_data()
	return img.get_data().hex_encode().sha256_text()

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	var t = 0.0
	while t < 30:
		yield(wait(0.25), "completed"); t += 0.25
		var sc = get_tree().current_scene
		if !sc or sc.name != "Menu": continue
		var tm = sc.get_node_or_null("TitleMenu")
		if tm and tm.visible:
			tm._close("")
			yield(wait(1.0), "completed")
		break
	var style = OS.get_environment("RR_HUD_STYLE")
	if style != "": load("res://mods/replay/Reimagined.gd").cfg()["hud_style"] = style
	out("== hudvp @@NAME@@: hud style %s" % load("res://mods/replay/Reimagined.gd").val("hud_style"))
	Rhythia.select_song(song("@@MAP1@@"))
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = ""
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var g = null
	var t0 = OS.get_ticks_msec()
	while OS.get_ticks_msec() - t0 < 60000 and !g:
		yield(get_tree(), "idle_frame")
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game") and sc.get_node("Game").has_node("Spawn") and sc.get_node("Game/Spawn").active: g = sc.get_node("Game")
	if !g:
		out("FAIL no game"); OS.kill(OS.get_process_id()); return
	var hud = g.get_node("HUD")
	yield(wait(2.0), "completed")
	var wait_hits = int(OS.get_environment("RR_HUD_HITS")) if OS.get_environment("RR_HUD_HITS") != "" else 0
	while is_instance_valid(g) and int(g.hits) < wait_hits and OS.get_ticks_msec() - t0 < 120000: # (into the dense part)
		yield(wait(0.25), "completed")
	var checks = 0
	var stale = 0
	var skipped = 0
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	for k in 24:
		yield(wait(rng.randf_range(0.15, 0.9)), "completed")
		if !is_instance_valid(g) or g.ending: break
		get_tree().paused = true
		yield(frames(3), "completed") # (marks made while it ran have rendered)
		for pair in hud.vp_pairs:
			var vp:Viewport = pair[0]
			if !pair[1].is_visible_in_tree(): continue
			if vp.render_target_update_mode == Viewport.UPDATE_ALWAYS:
				skipped += 1
				continue
			var a = sig(vp)
			vp.render_target_update_mode = Viewport.UPDATE_ONCE
			yield(frames(2), "completed")
			var b = sig(vp)
			checks += 1
			if a != b:
				stale += 1
				out("STALE %s at %.0f ms (hits %s)" % [vp.name, g.get_node("Spawn").ms, str(g.hits)])
		if k == 12:
			var img = get_viewport().get_texture().get_data()
			img.flip_y()
			img.save_png("@@OUT@@/hud_%s.png" % load("res://mods/replay/Reimagined.gd").val("hud_style"))
		get_tree().paused = false
	out("checks %d, stale %d, every-frame viewports skipped %d, hits %s" % [checks, stale, skipped, str(g.hits) if is_instance_valid(g) else "?"])
	out("PASS" if stale == 0 and checks > 40 else "FAIL")
	out("== done")
	OS.kill(OS.get_process_id())
