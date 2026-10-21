extends Node
# Where does map switching cost go? Lists what reacts to a selection change, then switches maps
# (every 100 ms, 3 s) while turning suspects off one by one (cumulative). Output @@OUT@@/probe.txt
const OUT = "@@OUT@@/probe.txt"
var frames = []
var capturing = false
var last_us = 0

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = false
	OS.window_size = Vector2(1280, 720)
	call_deferred("run")

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func _process(_d):
	OS.vsync_enabled = false
	Engine.target_fps = 0
	var u = OS.get_ticks_usec()
	if capturing and last_us > 0: frames.append((u - last_us) / 1000.0)
	last_us = u

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func path_of(o):
	return str(o.get_path()) if o is Node and o.is_inside_tree() else str(o)

func switch(tag, local):
	frames = []
	last_us = 0
	capturing = true
	for i in 30:
		Rhythia.select_song(local[i % local.size()])
		yield(wait(0.1), "completed")
	capturing = false
	var f = frames.duplicate()
	f.sort()
	var n = f.size()
	out("%-16s frames %4d  p50 %5.2f  p95 %5.2f  p99 %6.2f  max %6.2f" % [tag, n, f[n / 2], f[int(n * 0.95)], f[int(n * 0.99)], f[n - 1]])

func scripts_with(root:Node, part:String, acc:Array):
	if root.get_script() and part in str(root.get_script().resource_path): acc.append(root)
	for c in root.get_children(): scripts_with(c, part, acc)
	return acc

func run():
	Directory.new().remove(OUT)
	yield(wait(9.0), "completed")
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	yield(wait(1.5), "completed")
	out("-- selected_song_changed handlers")
	for c in Rhythia.get_signal_connection_list("selected_song_changed"):
		var s = c.target.get_script()
		out("  %s.%s  (%s)" % [path_of(c.target), c.method, s.resource_path if s else "-"])
	out("-- mods_changed handlers: %d" % Rhythia.get_signal_connection_list("mods_changed").size())
	var local = []
	for s in Rhythia.registry_song.get_items():
		if !s.is_online: local.append(s)
	out("local maps: %d" % local.size())
	yield(switch("base", local), "completed")
	yield(switch("base again", local), "completed")
	# audio players that play while switching
	var players = []
	var stack = [get_tree().root]
	while !stack.empty():
		var n = stack.pop_back()
		if n is AudioStreamPlayer and n.playing: players.append(n)
		for c in n.get_children(): stack.append(c)
	for p in players: out("  playing: %s  %s" % [path_of(p), p.stream.get_class() if p.stream else "-"])
	# 1. Hype (own build: cover pulse / spectrum / glows)
	for h in scripts_with(get_tree().root, "Hype.gd", []):
		h.set_process(false)
		if h is CanvasItem: h.visible = false
		h.queue_free()
	yield(switch("-hype", local), "completed")
	# 2. map page slide-in animation
	if Rhythia.is_connected("selected_song_changed", menu, "_map_picked"): Rhythia.disconnect("selected_song_changed", menu, "_map_picked")
	yield(switch("-slide anim", local), "completed")
	# 3. audio visualizer
	var v = menu.get_node_or_null("AudioVisualizer")
	if v:
		v.set_process(false)
		v.visible = false
	yield(switch("-visualizer", local), "completed")
	# 4. star badges + recent plays on the map page
	for c in Rhythia.get_signal_connection_list("selected_song_changed"):
		var sp = c.target.get_script().resource_path if c.target.get_script() else ""
		if "SongInfoScreen" in sp or "RecentPlays" in sp or "StarBadge" in sp: Rhythia.disconnect("selected_song_changed", c.target, c.method)
	yield(switch("-map page update", local), "completed")
	# 5. everything else listening to the selection
	for c in Rhythia.get_signal_connection_list("selected_song_changed"):
		Rhythia.disconnect("selected_song_changed", c.target, c.method)
	yield(switch("-all handlers", local), "completed")
	out("== done")
	OS.kill(OS.get_process_id())
