extends Node
# Autoplay cursor (HumanDance.gd, spins one way, loops on turns against it): sampled over the whole map at 240 Hz - every note inside the hitbox at
# its time, no teleports, no end-of-map snap, a sane top speed; compared with the stock bouncy mover.
# Then a live autoplay run: the HumanDance mover is used, no misses, the cursor moves.
# Output @@OUT@@/auto.txt (+ auto.png with RR_SHOTS)
const OUT = "@@OUT@@/auto.txt"
var passed = 0
var failed = 0
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")
func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()
func check(ok, s):
	if ok: passed += 1
	else: failed += 1
	out(("PASS  " if ok else "FAIL  ") + s)
func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func stats(mv, notes):
	var hb = 0.57
	var inside = 0
	var worst = 0.0
	for n in notes:
		var c = mv.update(float(n[2]))
		var d = max(abs(c.x - n[0]), abs(c.y - n[1]))
		worst = max(worst, d)
		if d <= hb: inside += 1
	var step = 1000.0 / 240.0
	var t = float(notes[0][2]) - 2000.0
	var t1 = float(notes[-1][2]) + 2500.0
	var prev = mv.update(t)
	var maxstep = 0.0
	var at = 0.0
	var speeds = []
	var length = 0.0
	var turns = 0
	var wind = 0.0
	var win = 0.0
	var win_abs = 0.0
	var win_t = t
	var wind_abs = 0.0
	var pv = Vector2.ZERO
	while t < t1:
		t += step
		var c = mv.update(t)
		var d = c.distance_to(prev)
		if d > maxstep:
			maxstep = d
			at = t
		length += d
		speeds.append(d / step * 1000.0)
		var v = c - prev
		if pv.length() > 0.004 and v.length() > 0.004 and pv.normalized().dot(v.normalized()) < 0.5: turns += 1
		if pv.length() > 0.008 and v.length() > 0.008:
			var ang = pv.angle_to(v)
			win += ang
			win_abs += abs(ang)
		if t - win_t > 1500.0: # (turning direction kept within 1.5 s stretches)
			if win_abs > 1.0:
				wind += abs(win)
				wind_abs += win_abs
			win = 0.0; win_abs = 0.0; win_t = t
		pv = v
		prev = c
	speeds.sort()
	# easy parts (>= 450 ms between notes): how far the path strays from a straight line
	var slow_n = 0
	var slow_ratio = 0.0
	for i in range(1, notes.size()):
		var ta = float(notes[i - 1][2])
		var tb = float(notes[i][2])
		var chord = Vector2(notes[i][0], notes[i][1]).distance_to(Vector2(notes[i - 1][0], notes[i - 1][1]))
		if tb - ta < 450.0 or chord < 0.8: continue
		var len_ = 0.0
		var q = mv.update(ta)
		var tt = ta
		while tt < tb:
			tt += 4.0
			var c = mv.update(tt)
			len_ += c.distance_to(q)
			q = c
		slow_n += 1
		slow_ratio += len_ / chord
	var need = 0.0
	for i in range(1, notes.size()):
		if float(notes[i][2]) >= at - 300 and float(notes[i][2]) <= at + 300:
			var gap = max(float(notes[i][2]) - float(notes[i - 1][2]), 1.0)
			need = max(need, Vector2(notes[i][0], notes[i][1]).distance_to(Vector2(notes[i - 1][0], notes[i - 1][1])) / gap * step)
	return {slow = slow_ratio / max(slow_n, 1), slow_n = slow_n, spin = abs(wind) / max(wind_abs, 0.001), at = at, need = need, inside = inside, worst = worst, maxstep = maxstep, p99 = speeds[int(speeds.size() * 0.99)], length = length, turns = turns}

# the cursor path over 6 s of the map's busiest part, notes as squares (old -> new = dark -> bright)
func path_png(mv, notes, name):
	var img = Image.new()
	img.create(420, 420, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.05, 0.07))
	img.lock()
	var t0 = float(notes[int(notes.size() * 0.4)][2])
	var t1 = t0 + 6000.0
	for n in notes:
		if float(n[2]) < t0 or float(n[2]) > t1: continue
		var c = Vector2(60 + n[0] * 150, 60 + n[1] * 150)
		for k in range(-20, 21):
			for q in [-20, 20]:
				img.set_pixel(int(c.x + k), int(c.y + q), Color(0.3, 0.3, 0.4))
				img.set_pixel(int(c.x + q), int(c.y + k), Color(0.3, 0.3, 0.4))
	var t = t0
	while t < t1:
		var p = mv.update(t)
		var k = (t - t0) / 6000.0
		var x = int(60 + p.x * 150)
		var y = int(60 + p.y * 150)
		for dx in 2:
			for dy in 2:
				if x + dx >= 0 and x + dx < 420 and y + dy >= 0 and y + dy < 420:
					img.set_pixel(x + dx, y + dy, Color(0.3 + 0.7 * k, 0.5 + 0.4 * k, 1.0))
		t += 1.0
	img.unlock()
	img.save_png("@@OUT@@/%s.png" % name)

func run():
	Directory.new().remove(OUT)
	yield(wait(6.0), "completed")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	var song = Rhythia.selected_song
	var notes = song.read_notes()
	var hm = load("res://mods/replay/HumanDance.gd").new(song)
	var u = OS.get_ticks_usec()
	var a = stats(hm, notes)
	var us = (OS.get_ticks_usec() - u) / 1000.0
	var b = stats(BouncyDanceMover.new(song), notes)
	out("  %d notes; human %s" % [notes.size(), str(a)])
	out("  stock bouncy %s; spin flips %d" % [str(b), hm.flips])
	check(a.inside == notes.size(), "every note inside the hitbox at its time (%d / %d, worst %.2f)" % [a.inside, notes.size(), a.worst])
	check(a.maxstep < max(0.12, a.need * 2.2), "no teleports (largest 240 Hz step %.3f at %.0f ms; the map needs %.3f there on average)" % [a.maxstep, a.at, a.need])
	check(a.p99 < b.p99 * 0.8, "top speed sane (p99 %.1f units/s, stock %.1f)" % [a.p99, b.p99])
	check(a.turns < b.turns, "fewer sharp direction changes than stock (%d vs %d)" % [a.turns, b.turns])
	check(a.spin > b.spin + 0.1, "spins: one turning direction dominates (%.2f of all turning, stock %.2f)" % [a.spin, b.spin])
	check(a.slow_n == 0 or a.slow < 1.25, "easy parts move plainly (path / straight line %.2f over %d slow jumps, stock %.2f)" % [a.slow, a.slow_n, b.slow])
	if OS.get_environment("RR_SHOTS") != "":
		path_png(hm, notes, "auto_path_human")
		path_png(BouncyDanceMover.new(song), notes, "auto_path_stock")
	out("  sampling cost %.1f ms" % us)
	# a live autoplay run
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = ""
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
	var g = null
	var t0 = OS.get_ticks_msec()
	while OS.get_ticks_msec() - t0 < 30000 and !g:
		yield(get_tree(), "idle_frame")
		var sc = get_tree().current_scene
		if sc and sc.has_node("Game") and sc.get_node("Game/Spawn").active: g = sc.get_node("Game")
	yield(wait(10.0), "completed")
	var cur = g.get_node("Spawn/Cursor")
	var p0 = cur.transform.origin
	yield(wait(0.3), "completed")
	var moved = cur.transform.origin.distance_to(p0)
	check(Rhythia.replay.autoplayer and Rhythia.replay.dance.get_script().resource_path.ends_with("HumanDance.gd"), "autoplay uses the human mover")
	check(g.misses == 0 and g.hits > 10 and moved > 0.01, "live autoplay: %d hits, %d misses, cursor moved %.2f" % [g.hits, g.misses, moved])
	if OS.get_environment("RR_SHOTS") != "":
		var img = get_tree().root.get_texture().get_data()
		img.flip_y(); img.resize(640, 360)
		img.save_png("@@OUT@@/auto.png")
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
