extends Node
# Performance benchmark (one instance, vsync off, uncapped fps so frame cost shows):
#  startup  - engine start -> menu ready
#  menu     - idle menu frame times, then rapid map switching (selected song changes every 100 ms)
#  load     - songload -> notes moving, for @@MAP2@@ (big map) and @@MAP1@@
#  play     - full autoplay of @@MAP1@@ (dense map): frame time p50/p95/p99/max, spikes, process
#             time, draw calls, objects, memory
#  cycle    - 3 more start / quit / back-to-menu rounds: objects + memory after each (leaks)
# Output: @@OUT@@/perf.json + perf.txt
const OUT = "@@OUT@@/perf.txt"
var res = {}
var frames = []        # frame deltas (ms) of the current capture
var capturing = false
var last_us = 0
var phys_ticked = false
var tags = []          # per frame: 1 = a physics tick ran, 2 = a note was hit (bits)
var game_ref = null
var last_hits = 0
var desync = []        # |audio position - game clock| per frame (ms)
var reseeks = 0        # audio position jumped (hard re-seek)
var mm_resizes = 0     # note MultiMesh buffer reallocations
var last_pos = -1.0
var last_pos_us = 0
var last_inst = -1
var hidden_frames = 0

func _physics_process(_d):
	phys_ticked = true

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	res.startup_ms = OS.get_ticks_msec()
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func _process(_d):
	OS.vsync_enabled = false # (the game re-applies its own fps settings on scene changes)
	Engine.target_fps = 0
	var u = OS.get_ticks_usec()
	if capturing and last_us > 0:
		frames.append((u - last_us) / 1000.0)
		var tag = 1 if phys_ticked else 0
		if is_instance_valid(game_ref):
			var h = int(game_ref.get("hits"))
			if h != last_hits: tag |= 2
			last_hits = h
		tags.append(tag)
		if OS.window_minimized: hidden_frames += 1 # (Windows paces a minimized window to the display: not the game's cost)
		_audio_frame(u)
	phys_ticked = false
	last_us = u

func _audio_frame(u:int):
	if !is_instance_valid(game_ref) or !game_ref.has_node("Spawn"): return
	var sp = game_ref.get_node("Spawn")
	var n = sp.get_node_or_null("Notes")
	if n and n.multimesh:
		if last_inst >= 0 and n.multimesh.instance_count != last_inst: mm_resizes += 1
		last_inst = n.multimesh.instance_count
	var m = sp.get_node_or_null("Music")
	if !m or !m.playing:
		last_pos = -1.0
		return
	var pos = (m.get_playback_position() + AudioServer.get_time_since_last_mix()) * 1000.0
	desync.append(abs(float(sp.ms) + float(Rhythia.music_offset) - pos))
	if last_pos >= 0:
		var expect = (u - last_pos_us) / 1000.0 * m.pitch_scale
		if abs((pos - last_pos) - expect) > 60.0: reseeks += 1
	last_pos = pos
	last_pos_us = u

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func begin():
	frames = []
	tags = []
	desync = []
	reseeks = 0
	mm_resizes = 0
	last_inst = -1
	last_pos = -1.0
	last_us = 0
	hidden_frames = 0
	capturing = true

func stats(tag:String) -> Dictionary:
	capturing = false
	var f = frames.duplicate()
	f.sort()
	var n = f.size()
	if n == 0: return {}
	var tot = 0.0
	for x in f: tot += x
	var med = f[n / 2]
	var spikes2 = 0
	var spikes33 = 0
	for x in frames:
		if x > med * 2.0 and x > 8.0: spikes2 += 1
		if x > 33.3: spikes33 += 1
	var d = {frames = n, avg_fps = stepify(1000.0 * n / tot, 0.1), p50 = stepify(med, 0.01),
		p95 = stepify(f[int(n * 0.95)], 0.01), p99 = stepify(f[int(n * 0.99)], 0.01), max = stepify(f[n - 1], 0.01),
		spikes_2x = spikes2, spikes_33ms = spikes33, minimized_frames = hidden_frames}
	for k in [["phys", 1], ["hit", 2]]: # mean frame time with / without a physics tick or a hit in it
		var a = [0.0, 0]
		var b = [0.0, 0]
		for i in min(frames.size(), tags.size()):
			var c = a if tags[i] & k[1] else b
			c[0] += frames[i]; c[1] += 1
		d[k[0] + "_frames"] = a[1]
		d[k[0] + "_mean"] = stepify(a[0] / max(a[1], 1), 0.01)
		d["no" + k[0] + "_mean"] = stepify(b[0] / max(b[1], 1), 0.01)
	if desync.size() > 0:
		var ds = desync.duplicate()
		ds.sort()
		d.desync_p50 = stepify(ds[ds.size() / 2], 0.1)
		d.desync_p99 = stepify(ds[int(ds.size() * 0.99)], 0.1)
		d.desync_max = stepify(ds[-1], 0.1)
		d.reseeks = reseeks
		d.mm_resizes = mm_resizes
	res[tag] = d
	out("%-10s %s" % [tag, JSON.print(d)])
	return d

func song(file):
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == file: return s
	return null

func mem() -> Dictionary:
	return {objects = Performance.get_monitor(Performance.OBJECT_COUNT), nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		resources = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), static_mb = stepify(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		orphans = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)}

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

# start a map with the autoplayer; returns the Game node once notes move (or null)
func start(s):
	if "fx" in "@@NAME@@": # every per-note visual on (exercises all MultiMeshes and effect copies)
		for k in ["note_spawn_effect", "note_visual_approach", "score_popup", "show_hit_effect", "show_miss_effect"]: Rhythia.set(k, true)
	Rhythia.select_song(s)
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = ""
	var t0 = OS.get_ticks_msec()
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var g = null
	while OS.get_ticks_msec() - t0 < 60000:
		yield(get_tree(), "idle_frame")
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game"):
			var cand = sc.get_node("Game")
			if cand.has_node("Spawn") and cand.get_node("Spawn").active:
				g = cand
				break
	res["load_" + s.filePath.get_file().get_basename().substr(0, 24)] = OS.get_ticks_msec() - t0
	out("load %s: %d ms" % [s.filePath.get_file(), OS.get_ticks_msec() - t0])
	return g

func back_to_menu(g):
	if is_instance_valid(g): g.end(Globals.END_GIVEUP)
	var t = 0.0
	while t < 30 and !(get_tree().current_scene and get_tree().current_scene.name == "Menu"):
		yield(wait(0.25), "completed"); t += 0.25
	yield(wait(2.0), "completed")
	var r = get_tree().current_scene.get_node_or_null("ResultsScreen")
	if r: r.queue_free()

func run():
	Directory.new().remove(OUT)
	out("== perf bench @@NAME@@  (%s, %s)" % [OS.get_video_driver_name(OS.get_current_video_driver()), OS.get_processor_name()])
	out("startup  %d ms (engine start -> menu ready)" % res.startup_ms)
	yield(wait(8.0), "completed") # (star ratings / map cache settle)
	yield(menu_ready(), "completed")
	if OS.get_environment("RR_PERF_PROFILE") == "low" and ResourceLoader.exists("res://mods/replay/Device.gd"): # (Customize > Device: low-end profile)
		out("profile: low-end (%d settings changed)" % load("res://mods/replay/Device.gd").apply_low())
	for kv in OS.get_environment("RR_PERF_SET").split(";", false): # ("rh:render_scale=0.75;rr:lite_fx=true": one setting at a time)
		var a = kv.split("=")
		var w = a[0].split(":")
		var v = parse_json(a[1]) if a[1] in ["true", "false"] or a[1].is_valid_float() else a[1]
		if w[0] == "rr": load("res://mods/replay/Reimagined.gd").cfg()[w[1]] = v
		else: Rhythia.set(w[1], v)
		out("set %s = %s" % [kv, str(v)])
	var quick = "@@NAME@@".begins_with("diag") # (gameplay only)
	begin()
	yield(wait(5.0), "completed")
	stats("menu_idle")
	# rapid map switching
	var local = []
	for s in Rhythia.registry_song.get_items():
		if !s.is_online: local.append(s)
	begin()
	for i in 40:
		var pick = local[i % local.size()]
		Rhythia.select_song(pick)
		yield(wait(0.1), "completed")
	stats("map_switch")
	res.mem_menu_start = mem()
	out("mem menu   " + JSON.print(res.mem_menu_start))
	# load time of the big map
	var big = song("@@MAP2@@")
	if big and (!quick or "@@NAME@@" == "diagbig"):
		var g = yield(start(big), "completed")
		yield(back_to_menu(g), "completed")
	# full autoplay of the dense map
	var dense = song("@@MAP1@@")
	var g = yield(start(dense), "completed")
	if g:
		game_ref = g
		last_hits = int(g.get("hits"))
		begin()
		var dc = []
		var t = 0.0
		var limit = dense.last_ms / 1000.0 + 3.0
		while t < limit and is_instance_valid(g) and !g.ending:
			yield(wait(1.0), "completed"); t += 1.0
			dc.append(Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME))
		stats("play")
		dc.sort()
		res.play_draw_calls_p50 = dc[dc.size() / 2] if dc.size() > 0 else -1
		out("draw calls p50 %s" % res.play_draw_calls_p50)
		res.mem_play_end = mem()
		out("mem play   " + JSON.print(res.mem_play_end))
		if is_instance_valid(g):
			out("play end: hits %s misses %s" % [g.get("hits"), g.get("misses")])
	yield(back_to_menu(g), "completed")
	# start / quit cycles: objects and memory should come back to the same level
	var cyc = []
	for k in (0 if quick else 3):
		var g2 = yield(start(dense), "completed")
		yield(wait(5.0), "completed")
		yield(back_to_menu(g2), "completed")
		cyc.append(mem())
		out("mem cycle%d %s" % [k + 1, JSON.print(cyc[-1])])
	res.mem_cycles = cyc
	var f = File.new()
	f.open("@@OUT@@/perf.json", File.WRITE)
	f.store_string(JSON.print(res, "  "))
	f.close()
	out("== done")
	OS.kill(OS.get_process_id())
