extends Node
# Where gameplay frame spikes come from: autoplays @@MAP1@@ (vsync off, uncapped) and logs the 25
# slowest frames with the song time, hits so far, and the nodes created during that frame (by name /
# script), plus every frame over 4 ms. RR_SPIKE_RUNS=n plays it n times (first run vs later runs:
# one-time costs such as shader compiles show up only in the first).
# Output: @@OUT@@/spikes.txt
const OUT = "@@OUT@@/spikes.txt"
var last_us = 0
var rec = null
var added = []
var game = null

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
	if OS.get_environment("RR_SPIKE_VSYNC") != "1": # (default: uncapped, so frame cost shows)
		OS.vsync_enabled = false
		Engine.target_fps = 0
	else: OS.vsync_enabled = true
	get_tree().connect("node_added", self, "_added")
	call_deferred("run")

var seen = []
func _added(n):
	seen.append(weakref(n))
	if rec != null and added.size() < 40:
		var sc = n.get_script()
		added.append(n.name + ("[" + sc.resource_path.get_file() + "]" if sc and sc.resource_path != "" else "[" + n.get_class() + "]"))

func _process(_d):
	var now = OS.get_ticks_usec()
	if rec != null and last_us > 0 and is_instance_valid(game):
		var ms = (now - last_us) / 1000.0
		var sp = game.get_node_or_null("Spawn")
		rec.append([ms, sp.ms if sp else float(OS.get_ticks_msec()), int(game.get("hits")) if game.get("hits") != null else 0, added.duplicate(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	added = []
	last_us = now

func play(song):
	Rhythia.select_song(song)
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = ""
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	game = null
	var t = 0.0
	while t < 60 and !game:
		yield(get_tree(), "idle_frame")
		t += get_process_delta_time()
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game") and sc.get_node("Game").has_node("Spawn") and sc.get_node("Game/Spawn").active: game = sc.get_node("Game")
	rec = []
	while is_instance_valid(game) and get_tree().current_scene and get_tree().current_scene.has_node("Game"):
		yield(get_tree(), "idle_frame")
	var r = rec
	rec = null
	return r

func report(label:String, r:Array):
	var ts = []
	for x in r: ts.append(x[0])
	ts.sort()
	var late = 0
	for v in ts: if v > 1.5 * ts[ts.size() / 2]: late += 1
	out("== %s: %d frames, p50 %.2f ms, p99 %.2f ms, max %.2f ms, frames over 1.5x p50: %d" % [label, ts.size(), ts[ts.size() / 2], ts[int(ts.size() * 0.99)], ts[ts.size() - 1], late])
	var idx = range(r.size())
	var by = []
	for i in idx: by.append([r[i][0], i])
	by.sort_custom(self, "_desc")
	for k in min(25, by.size()):
		var x = r[by[k][1]]
		out("%7.2f ms  at %8.0f ms  frame %5d  hits %4d  process %.2f physics %.2f  %s" % [x[0], x[1], by[k][1], x[2], x[4], x[5], str(x[3]).left(200)])
	var pm = []
	for x in r: pm.append(x[4])
	pm.sort()
	out("   process time p50 %.2f ms p99 %.2f ms max %.2f ms" % [pm[pm.size() / 2], pm[int(pm.size() * 0.99)], pm[pm.size() - 1]])

func _desc(a, b): return a[0] > b[0]

# what exists after a run (menu): totals, root children, nodes per script / class, processing nodes
var prev = {}
func census(run:int):
	var counts = {}
	var proc = 0
	var stack = [get_tree().root]
	while !stack.empty():
		var n = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		var sc = n.get_script()
		var k = sc.resource_path.get_file() if sc and sc.resource_path != "" else n.get_class()
		counts[k] = counts.get(k, 0) + 1
		if n.is_processing() or n.is_physics_processing(): proc += 1
	var roots = []
	for c in get_tree().root.get_children(): roots.append(c.name)
	out("-- census after run %d: objects %d nodes %d orphans %d resources %d processing %d mem %.1f MB buses %d" % [run, Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), proc, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, AudioServer.bus_count])
	out("   root: " + str(roots))
	if !prev.empty():
		var diff = []
		for k in counts:
			if counts[k] != prev.get(k, 0): diff.append("%s %+d" % [k, counts[k] - prev.get(k, 0)])
		for k in prev:
			if !counts.has(k): diff.append("%s -%d" % [k, prev[k]])
		out("   changed: " + str(diff))
	prev = counts

func run():
	Directory.new().remove(OUT)
	yield(wait(10.0), "completed")
	if OS.get_environment("RR_SPIKE_MENU") == "1": # (the menu as the title closes: 6 s of frames)
		game = get_tree().current_scene
		rec = []
		var tm0 = get_tree().current_scene.get_node_or_null("TitleMenu")
		if tm0 and tm0.visible: tm0._close("")
		yield(wait(6.0), "completed")
		var r0 = rec
		rec = null
		report("menu after the title closes", r0)
		out("== done")
		OS.kill(OS.get_process_id())
		return
	var tm = get_tree().current_scene.get_node_or_null("TitleMenu")
	if tm and tm.visible: tm._close("")
	yield(wait(2.0), "completed")
	var song = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": song = s
	var n = int(OS.get_environment("RR_SPIKE_RUNS")) if OS.get_environment("RR_SPIKE_RUNS") != "" else 2
	for i in n:
		var r = yield(play(song), "completed")
		report("run %d" % (i + 1), r)
		var t = 0.0
		while t < 20 and !(get_tree().current_scene and get_tree().current_scene.name == "Menu"):
			yield(wait(0.25), "completed"); t += 0.25
		yield(wait(2.0), "completed")
		var rs = get_tree().current_scene.get_node_or_null("ResultsScreen")
		if rs: rs.queue_free()
		yield(wait(1.0), "completed")
		census(i + 1)
	var stray = []
	for w in seen:
		var o = w.get_ref()
		if o and !o.is_inside_tree():
			var osc = o.get_script()
			stray.append("%s [%s] %s" % [o.name, o.get_class(), osc.resource_path if osc else ""])
	out("-- nodes added during the runs that still exist outside the tree: %d" % stray.size())
	for x in stray: out("   " + x)
	out("== done")
	print("---- stray nodes")
	Node.print_stray_nodes()
	print("---- end")
	get_tree().quit() # (a normal exit flushes stdout)
