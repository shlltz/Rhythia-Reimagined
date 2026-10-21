extends Node
# Cost of each selected_song_changed handler: for each map, set the selection without the signal,
# then call every connected handler directly and time it. Output @@OUT@@/handlers.txt
const OUT = "@@OUT@@/handlers.txt"

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

func run():
	Directory.new().remove(OUT)
	yield(wait(9.0), "completed")
	var menu = get_tree().current_scene
	if menu.has_node("TitleMenu"): menu.get_node("TitleMenu")._close("")
	yield(wait(1.5), "completed")
	var local = []
	for s in Rhythia.registry_song.get_items():
		if !s.is_online: local.append(s)
	var conns = Rhythia.get_signal_connection_list("selected_song_changed")
	var cost = {}
	for pass_i in 2: # pass 0 = maps never shown before (cold), pass 1 = shown once (warm)
		for k in cost.keys(): cost[k] = []
		for s in local:
			Rhythia.selected_song = s
			for c in conns:
				if !is_instance_valid(c.target): continue
				var key = "%s.%s" % [c.target.get_script().resource_path.get_file() if c.target.get_script() else c.target.name, c.method]
				var t0 = OS.get_ticks_usec()
				c.target.call(c.method, s)
				var dt = (OS.get_ticks_usec() - t0) / 1000.0
				if !cost.has(key): cost[key] = []
				cost[key].append(dt)
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
		out("-- %s (%d maps): handler  mean / max ms" % ["cold" if pass_i == 0 else "warm", local.size()])
		var rows = []
		for k in cost.keys():
			var tot = 0.0
			var mx = 0.0
			for x in cost[k]:
				tot += x
				mx = max(mx, x)
			rows.append([tot / max(1, cost[k].size()), mx, k, cost[k].size()])
		rows.sort()
		rows.invert()
		for r in rows: out("  %7.2f  %7.2f  %s  (x%d)" % [r[0], r[1], r[2], r[3]])
	out("== done")
	OS.kill(OS.get_process_id())
