extends Node
# Map list rebuild cost (stars/v3MapList.gd) with the library as it is (online maps too when the
# network is on): how many maps, and the time of prepare_songs, _cache_stars, the sort and a whole
# reload_to_current_page, three times each.
# Output: @@OUT@@/list.txt
const OUT = "@@OUT@@/list.txt"

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")

func find(root:Node, part:String):
	var stack = [root]
	while !stack.empty():
		var x = stack.pop_back()
		if x.get_script() and x.get_script().resource_path.ends_with(part): return x
		for c in x.get_children(): stack.append(c)
	return null

func timed(obj, method:String, args:Array = []) -> float:
	var t0 = OS.get_ticks_usec()
	obj.callv(method, args)
	return (OS.get_ticks_usec() - t0) / 1000.0

func run():
	Directory.new().remove(OUT)
	yield(wait(20.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("")
	yield(wait(4.0), "completed")
	var items = Rhythia.registry_song.get_items()
	var online = 0
	for s in items: if s.is_online: online += 1
	var list = find(menu, "v3MapList.gd")
	out("maps: %d (%d online), list shows %d" % [items.size(), online, list.disp.size() if list else -1])
	for i in 3:
		out("prepare_songs %.1f ms   _cache_stars %.1f ms   reload_to_current_page %.1f ms" % [timed(list, "prepare_songs"), timed(list, "_cache_stars"), timed(list, "reload_to_current_page")])
		yield(wait(0.5), "completed")
	var rest = []
	for g in [list.easy, list.medium, list.hard, list.logic, list.amogus, list.unknown]: rest.append_array(g)
	var t0 = OS.get_ticks_usec()
	rest.sort_custom(list, list._sort_fn())
	out("sorting the %d maps with the list's sort: %.1f ms" % [rest.size(), (OS.get_ticks_usec() - t0) / 1000.0])
	# the native keyed sort (_fast_sort) orders exactly like each comparator: every neighbour pair is in
	# order under it, same maps, for each sort and both flip settings
	list._cache_stars()
	list.rr_sort = "length"
	list._rr_sort_keys(rest)
	var all_ok = true
	for fn in ["sortsong", "sortsongsimple", "sortname", "sortmapper", "sortkey", "sortkey_desc"]:
		for flips in [[false, false], [true, false], [false, true], [true, true]]:
			list.flip_display = flips[0]
			list.flip_name = flips[1]
			var a1 = rest.duplicate()
			var t1 = OS.get_ticks_usec()
			a1.sort_custom(list, fn)
			var slow = (OS.get_ticks_usec() - t1) / 1000.0
			t1 = OS.get_ticks_usec()
			var a2 = list._fast_sort(rest.duplicate(), fn)
			var fast = (OS.get_ticks_usec() - t1) / 1000.0
			var bad = 0
			for i in range(1, a2.size()):
				if list.call(fn, a2[i], a2[i - 1]): bad += 1
			var same = a2.size() == a1.size()
			var cnt = {}
			for x in a1: cnt[x] = cnt.get(x, 0) + 1
			for x in a2: cnt[x] = cnt.get(x, 0) - 1
			for k in cnt: if cnt[k] != 0: same = false
			if bad > 0 or !same: all_ok = false
			out("%-15s flip %s/%s: %4d maps, comparator %.1f ms, native %.1f ms, out of order %d, same maps %s" % [fn, flips[0], flips[1], a2.size(), slow, fast, bad, same])
	out("native sort matches every comparator: %s" % all_ok)
	list.flip_display = false
	list.flip_name = false
	list.rr_sort = "stars"
	out("== done")
	OS.kill(OS.get_process_id())
