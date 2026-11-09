extends VBoxContainer

signal search_updated
signal reset_filters
signal lock_type

var thread:Thread

var songs:Array = Rhythia.registry_song.get_items()
var btns:Array = []

var search_text:String = ""
var author_search_text:String = ""
var difficulty_filter:Array = Rhythia.last_difficulty_filter
var show_broken_maps:bool = false
var show_online_maps:bool = true
var flip_display:bool = false
var flip_name:bool = false

var cur_map:int = 0
var page_size:int = 10

var favorite:Array = []
var easy:Array = []
var medium:Array = []
var hard:Array = []
var logic:Array = []
var amogus:Array = []
var unknown:Array = []

var disp:Array = []

var ready:bool = false

var scroll_up:bool = false
var scroll_down:bool = false
var scroll_target:int = 0
var scrolling_to:bool = false

var check_drag:bool = false
var dragged:bool = false
var drag_cur_map:int = 0
var drag_start:Vector2 = Vector2()
var drag_offset:Vector2 = Vector2()

var momentum:float = 0

var size_x:int = 0

func next_index():
	return cur_map + int(floor(((page_size + 1)/2) * 1.2))

func prev_index():
	return cur_map - int(floor(((page_size + 1)/2) * 1.2))

func is_fav(s:Song): return favorite.has(s)

func search_matches(s:Song):
	return (
		difficulty_filter.has(s.difficulty) and
		(!s.is_online or show_online_maps) and
		(!s.is_broken or show_broken_maps) and
		(search_text == "" or _rr_search_match(s)) and
		(author_search_text == "" or s.creator.to_lower().find(author_search_text.to_lower()) != -1) and
		(rr_coll == null or rr_coll.has(s.id))
	)

var has_been_pressed = false

func play_song():
	if !Rhythia.selected_song: return
	if has_been_pressed: return
	emit_signal("lock_type") # prevent input to line edits (MapSearch and AuthorSearch)
	has_been_pressed = true
	get_viewport().get_node("Menu").black_fade_target = true
	yield(get_tree().create_timer(0.35),"timeout")
	load("res://mods/replay/ScreenSwap.gd").launch(get_tree()) # (the menu kept asleep: Esc on the card wakes it)

var pt = 1
func on_pressed(i):
	if dragged:
		dragged = false
		return
	if i < 0: return
	$Press.play()
	scroll_to(i)

	var s:Song = disp[i]
	if s != Rhythia.selected_song:
		Rhythia.select_song(s)
	else:
		print(pt)
		if pt < 0.25:
			# make sure all the things are stopped
			check_drag = false
			dragged = false
			scrolling_to = false
			momentum = 0
			play_song()
	pt = 0
	get_viewport().get_node("Menu/Main/Maps/Results").visible = true
	
func switch_to_play_screen():
	size_list()
	if Rhythia.menu_target == "res://scenes/menu/menu.tscn": return
	if disp.find(Rhythia.registry_song.get_item(Rhythia.selected_song.id)) == -1: #if the selected song is not in the list, reset filters to show it
		reset_filters()
	get_viewport().get_node("Menu/Sidebar").press(0,true)
	cur_map = disp.find(Rhythia.registry_song.get_item(Rhythia.selected_song.id))
	load_pg(true)

var was_maximized = OS.window_maximized
var was_fullscreen = OS.window_fullscreen
func _process(delta):
	if check_drag:
		drag_offset = get_global_mouse_position()
		if abs(drag_offset.y - drag_start.y) > 12: # (a drag, not a click: from here the list follows the mouse)
			check_drag = false
			dragged = true
			rr_dragging = true
			scrolling_to = false
			drag_start = drag_offset
			rr_drag_from = rr_pos
			rr_vel = 0.0
			rr_hist.clear()

	tween_length(delta)
	pt += delta
	if OS.window_maximized != was_maximized or OS.window_fullscreen != was_fullscreen:
		was_maximized = OS.window_maximized
		was_fullscreen = OS.window_fullscreen
		handle_window_resize()

func _physics_process(delta):
	# (scrolling: _rr_glide - one continuous position easing to a target; a card picked is scrolled to)
	if scrolling_to:
		rr_tgt = scroll_target
		if abs(rr_pos - scroll_target) < 0.05:
			scrolling_to = false
			if cur_map >= 0 and cur_map < disp.size() and disp[cur_map] != Rhythia.selected_song:
				Rhythia.select_song(disp[cur_map])

func check_drag_on():
	momentum = 0
	dragged = false
	rr_dragging = false
	check_drag = true
	drag_start = get_global_mouse_position()
	drag_offset = drag_start
	drag_cur_map = cur_map

func check_drag_off():
	check_drag = false
	if rr_dragging: # a fling: it carries on with the drag's speed and eases out
		rr_dragging = false
		if rr_hist.size() > 0 and OS.get_ticks_msec() - rr_hist[-1][0] > 80: rr_vel = 0.0 # (held still before letting go)
		rr_tgt = rr_pos + clamp(rr_vel * 0.25, -40.0, 40.0)

func select_random():
	if disp.size() == 0: return
	cur_map = randi()%disp.size()
	load_pg(true)
	

func load_pg(select_cur:bool=false):
	size_list()
	for n in btns: n.queue_free()
	btns.clear()
	thumb_mx.lock() # covers of the old page that haven't loaded yet: not needed any more
	thumb_queue.clear()
	thumb_mx.unlock()

	if disp.size() == 0: return
	page_size = ((get_parent().rect_size.y)/90) * 1.5
	if page_size % 2 != 0:
		page_size += 1
	#page size isnt accurate, its a ballpark
	cur_map = clamp(cur_map, 0, disp.size() - 1)
	for i in range(prev_index(), next_index() + 1):
		var btn:Panel = make_song_button(i)
		btn.rect_min_size = Vector2(350, 90)
		btns.append(btn)
		add_child(btn)
		btn.visible = true
		if i == cur_map and select_cur:
			if btn.song != Rhythia.selected_song:
				Rhythia.select_song(btn.song)
				btn.get_node("Select").pressed = true
	glide_y = 0.0
	if slide_t < 0.0: _rr_retarget(true)
	_rr_place()

func append_filtering_favorites(to:Array,from:Array):
	for s in from:
		if !is_fav(s) and search_matches(s):
			to.append(s)


func build_list():
	disp = []
	favorite = []
	_cache_stars()
	if _sort_fn().begins_with("sortkey"): _rr_sort_keys(star_of.keys()) # (star_of holds every map)
	for id in Rhythia.favorite_songs:
		var s = Rhythia.registry_song.get_item(id)
		if s and Rhythia.is_favorite(id) and search_matches(s):
			favorite.append(s)
	favorite = _fast_sort(favorite, _sort_fn())
	disp.append_array(favorite)
	# "difficulty" sort = star rating (Steam Rhythia formula), across all categories
	var rest:Array = []
	for group in [easy,medium,hard,logic,amogus,unknown]:
		append_filtering_favorites(rest,group)
	rest = _fast_sort(rest, _sort_fn())
	disp.append_array(rest)

var rr_batch:bool = false # reset_filters changes 6 filters: rebuild the list once, not 6 times (~200 ms hitch)
func reload_to_current_page(_a=null):
	if rr_batch: return
	scrolling_to = false
	build_list()
	load_pg()

func update_search_text(txt:String):
	search_text = txt
	if ready: _rr_search_pick()
	emit_signal("search_updated")

func update_author_search_text(txt:String):
	author_search_text = txt
	if ready: _rr_search_pick()
	emit_signal("search_updated")

# osu!-style: a search keeps the selected map if it still matches (the list goes to it), otherwise
# the first result is picked
func _rr_search_pick():
	if rr_batch: return
	scrolling_to = false
	build_list()
	if disp.size() == 0:
		load_pg()
		return
	var sel = Rhythia.registry_song.get_item(Rhythia.selected_song.id) if Rhythia.selected_song else null
	var at = disp.find(sel) if sel else -1
	cur_map = at if at != -1 else 0
	load_pg(at == -1)

func update_search_dfil(dfil:Array):
	difficulty_filter = dfil
	Rhythia.last_difficulty_filter = dfil
	if ready: reload_to_current_page()
	emit_signal("search_updated")

func update_search_showbroken(show:bool):
	show_broken_maps = show
	if ready: reload_to_current_page()

func update_search_showonline(show:bool):
	show_online_maps = show
	if ready: reload_to_current_page()

func update_search_flipped(flip:bool):
	flip_display = flip
	if ready: reload_to_current_page()

func update_search_flip_name(flip:bool):
	flip_name = flip
	easy = _fast_sort(easy, "sortsongsimple")
	medium = _fast_sort(medium, "sortsongsimple")
	hard = _fast_sort(hard, "sortsongsimple")
	logic = _fast_sort(logic, "sortsongsimple")
	amogus = _fast_sort(amogus, "sortsongsimple")
	if ready: reload_to_current_page()

func sortab(a, b): return a < b

# perf mod: the list's sorts done natively. Each map gets one integer key that orders like the
# comparator named by fn: its names, ids, stars and sort keys are first ranked by a native sort (a
# reversed part takes the rank from the other end), the ranks are packed into the integer with the
# map's index last, then the keys get one native sort. A GDScript comparator took ~60 ms for 2,300
# maps (the online maps included) on every list rebuild.
const FAST_MIN = 48 # (below this the comparator is as quick)
var rr_lower:Dictionary = {} # song -> [name, name.to_lower(), creator.to_lower()] (redone when the name changes)
func _fast_sort(arr:Array, fn:String) -> Array:
	var n = arr.size()
	var b = 1
	while (1 << b) < n + 1: b += 1
	if n < FAST_MIN or b * 4 + 1 > 62 or !(fn in ["sortsong", "sortsongsimple", "sortname", "sortmapper", "sortkey", "sortkey_desc"]):
		arr.sort_custom(self, fn)
		return arr
	var low = []
	low.resize(n)
	for i in n:
		var a = arr[i]
		var c = rr_lower.get(a)
		if c == null or c[0] != a.name:
			c = [a.name, a.name.to_lower(), a.creator.to_lower()]
			rr_lower[a] = c
		low[i] = c
	var nm = _ranks(arr, low, "name")
	var idr = _ranks(arr, low, "id")
	var keys = [] # (a plain Array: its ints are 64-bit, a PoolIntArray's only 32)
	keys.resize(n)
	match fn:
		"sortsong":
			var st = _ranks(arr, low, "stars")
			for i in n:
				var v = star_of.get(arr[i], -1.0)
				var k = 1 if v < 0 else 0
				k = (k << b) | _flip(st, v, flip_display)
				k = (k << b) | _flip(nm, low[i][1], flip_name)
				k = (k << b) | _flip(idr, arr[i].id, flip_name)
				keys[i] = (k << b) | i
		"sortsongsimple":
			for i in n:
				var k = (_flip(nm, low[i][1], flip_name) << b) | _flip(idr, arr[i].id, flip_name)
				keys[i] = (k << b) | i
		"sortname":
			for i in n:
				var k = (_flip(nm, low[i][1], flip_display) << b) | idr[0][arr[i].id]
				keys[i] = (k << b) | i
		"sortmapper":
			var cr = _ranks(arr, low, "creator")
			for i in n:
				var k = (_flip(cr, low[i][2], flip_display) << b) | _flip(nm, low[i][1], flip_display)
				k = (k << b) | idr[0][arr[i].id]
				keys[i] = (k << b) | i
		_: # sortkey (low first) / sortkey_desc (high first); maps without a key last either way
			var kr = _ranks(arr, low, "key")
			var desc = fn == "sortkey_desc"
			for i in n:
				var a = arr[i]
				var has = rr_key.has(a)
				var k = 0 if has else 1
				k = (k << b) | (_flip(kr, rr_key[a], desc != flip_display) if has else 0)
				k = (k << b) | _flip(nm, low[i][1], flip_display)
				k = (k << b) | idr[0][a.id]
				keys[i] = (k << b) | i
	var ks = keys
	ks.sort()
	var out = []
	out.resize(n)
	var mask = (1 << b) - 1
	for i in n: out[i] = arr[ks[i] & mask]
	return out

# [value -> its place among the distinct values of the maps (native sort), how many]
func _ranks(arr:Array, low:Array, what:String) -> Array:
	var seen = {}
	for i in arr.size():
		match what:
			"name": seen[low[i][1]] = true
			"id": seen[arr[i].id] = true
			"creator": seen[low[i][2]] = true
			"stars": seen[star_of.get(arr[i], -1.0)] = true
			"key": if rr_key.has(arr[i]): seen[rr_key[arr[i]]] = true
	var vals = seen.keys()
	vals.sort()
	var r = {}
	for i in vals.size(): r[vals[i]] = i
	return [r, vals.size()]

func _flip(r:Array, v, rev:bool) -> int:
	return r[1] - 1 - r[0][v] if rev else r[0][v]

func sortsongsimple(a:Song, b:Song):
	if flip_name:
		if a.name != b.name: return a.name.to_lower() > b.name.to_lower()
		else: return a.id > b.id
	else:
		if a.name != b.name: return a.name.to_lower() < b.name.to_lower()
		else: return a.id < b.id

# star rating, low -> high (high -> low when flipped); unrated maps go last, ties by name
var star_of:Dictionary = {}
func _cache_stars():
	var cache = load("res://mods/stars/StarCache.gd").get_instance(get_tree())
	if !cache.is_connected("all_rated",self,"_on_all_rated"):
		cache.connect("all_rated",self,"_on_all_rated")
	star_of = {}
	for group in [easy,medium,hard,logic,amogus,unknown]:
		for s in group: star_of[s] = cache.get_stars(s)
	for id in Rhythia.favorite_songs:
		var s = Rhythia.registry_song.get_item(id)
		if s: star_of[s] = cache.get_stars(s)

func _on_all_rated():
	if ready: reload_to_current_page()

func sortsong(a:Song, b:Song):
	var sa = star_of.get(a,-1.0)
	var sb = star_of.get(b,-1.0)
	if sa < 0 and sb >= 0: return false
	if sb < 0 and sa >= 0: return true
	if sa != sb:
		if flip_display: return sa > sb
		else: return sa < sb
	return sortsongsimple(a,b)

# ---------------------------------------------------------------- Rhythia-reimagined
# sort by stars / name / mapper and a collection filter (Reimagined.gd), both under Filters
const RR = "res://mods/replay/Reimagined.gd"
var rr_sort:String = "stars"
var rr_coll = null              # song id -> true, or null = all maps
var rr_sort_btn:OptionButton
var rr_coll_btn:OptionButton
const RR_SORTS = [["stars", "stars"], ["name", "name"], ["mapper", "mapper"], ["recent", "played"],
	["added", "added"], ["length", "length"], ["bpm", "bpm"]]

func _sort_fn() -> String:
	return {"name": "sortname", "mapper": "sortmapper", "recent": "sortkey_desc", "added": "sortkey_desc",
		"length": "sortkey", "bpm": "sortkey"}.get(rr_sort, "sortsong")

# sort keys for recently played / date added / length / bpm, filled before each sort (build_list).
# Maps without a key (never played, BPM not known yet) go last either way; ties by name.
var rr_key:Dictionary = {}
var rr_added:Dictionary = {}   # song id -> map file time, read once per session (one stat per map)

func _rr_sort_keys(group:Array):
	rr_key = {}
	match rr_sort:
		"recent":
			var plays = load("res://mods/stars/RecentPlays.gd")._load()
			for s in group:
				var p = plays.get(s.id)
				if p is Array and p.size() > 0 and p[p.size() - 1] is Dictionary: rr_key[s] = float(p[p.size() - 1].get("t", 0))
		"added":
			var f = File.new()
			for s in group:
				if !rr_added.has(s.id):
					var path = str(s.filePath)
					rr_added[s.id] = float(f.get_modified_time(Globals.p(path))) if path != "" and f.file_exists(Globals.p(path)) else -1.0
				if rr_added[s.id] > 0: rr_key[s] = rr_added[s.id]
		"length":
			for s in group: rr_key[s] = float(s.last_ms)
		"bpm":
			var cache = load("res://mods/stars/StarCache.gd").get_instance(get_tree())
			for s in group:
				var b = cache.get_bpm(s)
				if b > 0: rr_key[s] = b

# low -> high (flipped: high -> low)
func sortkey(a:Song, b:Song):
	var ha = rr_key.has(a)
	var hb = rr_key.has(b)
	if ha != hb: return ha
	if ha and rr_key[a] != rr_key[b]: return (rr_key[a] < rr_key[b]) != flip_display
	return sortname(a, b)

# newest first (flipped: oldest first) - played / added dates
func sortkey_desc(a:Song, b:Song):
	var ha = rr_key.has(a)
	var hb = rr_key.has(b)
	if ha != hb: return ha
	if ha and rr_key[a] != rr_key[b]: return (rr_key[a] > rr_key[b]) != flip_display
	return sortname(a, b)

# ---------------------------------------------------------------- search syntax (osu!-style)
# Every word has to appear in the title, the mapper or the difficulty name ("quoted words" stay
# together). Filters: stars / bpm / length / notes with = != < <= > >= (length in seconds or m:ss;
# "=" on a whole number matches that whole number, stars=6 -> 6.00-6.99), mapper=name. Stars and
# BPM are the 1.0x values. Parsed once per search text, not per map.
const RR_SEARCH_HELP = "Search: every word must match the title, mapper or difficulty  (\"quoted words\" stay together)\nFilters: stars>10  bpm<=180  length<2:30  notes>3000  mapper=name  tag=name\n(= != < <= > >=, stars / BPM at 1.0x speed)"
const RR_KEYS = {"stars": "stars", "star": "stars", "sr": "stars", "bpm": "bpm", "length": "length", "len": "length",
	"notes": "notes", "note": "notes", "mapper": "mapper", "creator": "mapper", "tag": "tag", "tags": "tag"}
const LIB = "res://mods/replay/Library.gd"
const LIB_SMART = "smart:"
var rr_q_src = null      # search text the parsed query belongs to
var rr_q_words:Array = []
var rr_q_filters:Array = [] # [key, op, value]

func _rr_parse_search():
	rr_q_src = search_text
	rr_q_words = []
	rr_q_filters = []
	var t = search_text.to_lower()
	var tokens = []
	var i = 0
	while i < t.length(): # split on spaces, "quoted parts" kept whole
		if t[i] == " ":
			i += 1
			continue
		if t[i] == "\"":
			var j = t.find("\"", i + 1)
			if j < 0: j = t.length()
			tokens.append(["q", t.substr(i + 1, j - i - 1)])
			i = j + 1
			continue
		var j = t.find(" ", i)
		if j < 0: j = t.length()
		tokens.append(["w", t.substr(i, j - i)])
		i = j
	for tk in tokens:
		var f = _rr_filter(tk[1]) if tk[0] == "w" else null
		if f: rr_q_filters.append(f)
		elif tk[1] != "": rr_q_words.append(tk[1])

# "stars>=10" -> ["stars", ">=", 10.0] (or null when it isn't a valid filter: then it's a word)
func _rr_filter(w:String):
	for op in ["<=", ">=", "!=", "==", "<", ">", "=", ":"]:
		var k = w.find(op)
		if k <= 0: continue
		var key = RR_KEYS.get(w.substr(0, k))
		var v = w.substr(k + op.length())
		if key == null or v == "": return null
		var o = "=" if op in ["==", ":"] else op
		if key == "mapper" or key == "tag":
			return [key, o, v] if o in ["=", "!="] else null
		var num = 0.0
		if key == "length" and ":" in v:
			var p = v.split(":")
			if p.size() != 2 or !p[0].is_valid_integer() or !p[1].is_valid_float(): return null
			num = float(p[0]) * 60.0 + float(p[1])
		elif v.is_valid_float(): num = float(v)
		else: return null
		return [key, o, num, v.is_valid_integer() and !(":" in v)]
	return null

func _rr_search_match(s:Song) -> bool:
	if rr_q_src != search_text: _rr_parse_search()
	if rr_q_words.size() > 0:
		var hay = (s.name + "\n" + s.creator + "\n" + str(s.custom_data.get("difficulty_name", ""))).to_lower()
		for w in rr_q_words:
			if hay.find(w) == -1: return false
	for f in rr_q_filters:
		if !_rr_filter_ok(s, f): return false
	return true

func _rr_filter_ok(s:Song, f:Array) -> bool:
	if f[0] == "mapper":
		var has = s.creator.to_lower().find(f[2]) != -1
		return has if f[1] == "=" else !has
	if f[0] == "tag":
		var has = false
		if ResourceLoader.exists(LIB):
			for t in load(LIB).tags_of(s.id):
				if t.find(f[2]) != -1: has = true
		return has if f[1] == "=" else !has
	var v = -1.0
	match f[0]:
		"stars": v = star_of.get(s, -1.0)
		"bpm": v = load("res://mods/stars/StarCache.gd").get_instance(get_tree()).get_bpm(s)
		"length": v = s.last_ms / 1000.0
		"notes": v = float(s.note_count)
	if v < 0 or (f[0] == "bpm" and v <= 0): return false # not rated / measured yet (BPM 0 = couldn't tell)
	var x = f[2]
	match f[1]:
		"=": return floor(v) == x if f[3] else abs(v - x) < 0.005
		"!=": return !(floor(v) == x if f[3] else abs(v - x) < 0.005)
		"<": return v < x
		"<=": return v <= x
		">": return v > x
		">=": return v >= x
	return false

func sortname(a:Song, b:Song):
	var x = a.name.to_lower()
	var y = b.name.to_lower()
	if x != y: return (x < y) != flip_display
	return a.id < b.id

func sortmapper(a:Song, b:Song):
	var x = a.creator.to_lower()
	var y = b.creator.to_lower()
	if x != y: return (x < y) != flip_display
	return sortname(a, b)

func _rr_init():
	if !ResourceLoader.exists(RR): return
	add_to_group("rr_collections")
	_rr_load()
	var se = get_node_or_null("/root/Menu/Main/Maps/MapRegistry/T/Search")
	if se: se.hint_tooltip = RR_SEARCH_HELP
	var f = get_node_or_null("/root/Menu/Main/Maps/Filters")
	if !f or !f.has_node("NameSort"): return
	if ResourceLoader.exists("res://mods/replay/UIKit.gd"): # (broken / online: switches, like Settings; the sort toggles keep their arrows)
		for c in f.get_children():
			if c is CheckBox and !("sort" in c.name.to_lower()):
				load("res://mods/replay/UIKit.gd").switch_box(c)
				c.add_constant_override("hseparation", 3) # (the switch is wider than the tick: at 1280 px "broken" ran off the screen)
	var at = f.get_node("NameSort").get_index() + 1
	var nodes = []
	nodes.append(_rr_caption("sort"))
	rr_sort_btn = _rr_option()
	rr_sort_btn.connect("item_selected", self, "_rr_sort_selected")
	nodes.append(rr_sort_btn)
	nodes.append(_rr_caption("collection"))
	rr_coll_btn = _rr_option()
	rr_coll_btn.connect("item_selected", self, "_rr_coll_selected")
	nodes.append(rr_coll_btn)
	for i in nodes.size():
		f.add_child(nodes[i])
		f.move_child(nodes[i], at + i)
	_rr_fill()

func _rr_caption(t:String) -> Label:
	var l = Label.new()
	l.text = t
	l.modulate = Color(1, 1, 1, 0.55)
	return l

func _rr_option() -> OptionButton:
	var o = OptionButton.new()
	o.clip_text = true
	o.focus_mode = FOCUS_NONE
	o.rect_min_size = Vector2(0, 28)
	return o

func _rr_load():
	var R = load(RR)
	rr_sort = R.val("sort")
	var c = str(R.val("collection"))
	rr_coll = null
	if c.begins_with(LIB_SMART) and ResourceLoader.exists(LIB): # smart playlist (Library.gd): evaluated from history / ratings
		rr_coll = load(LIB).smart_ids(c.substr(LIB_SMART.length()))
	elif c != "" and R.collections().has(c):
		rr_coll = {}
		for id in R.collections()[c]: rr_coll[id] = true

func _rr_fill():
	if !rr_sort_btn: return
	var R = load(RR)
	rr_sort_btn.clear()
	for i in RR_SORTS.size():
		rr_sort_btn.add_item(RR_SORTS[i][1], i)
		if RR_SORTS[i][0] == rr_sort: rr_sort_btn.select(i)
	rr_coll_btn.clear()
	rr_coll_btn.add_item("all maps", 0)
	var names = R.collections().keys()
	names.sort()
	for i in names.size():
		rr_coll_btn.add_item(names[i], i + 1)
		rr_coll_btn.set_item_metadata(i + 1, names[i])
		if names[i] == R.val("collection"): rr_coll_btn.select(i + 1)
	if ResourceLoader.exists(LIB):
		var n = rr_coll_btn.get_item_count()
		for r in load(LIB).smart_lists():
			rr_coll_btn.add_item("smart: " + r.name, n)
			rr_coll_btn.set_item_metadata(n, LIB_SMART + r.name)
			if LIB_SMART + r.name == R.val("collection"): rr_coll_btn.select(n)
			n += 1
	rr_coll_btn.hint_tooltip = "your collections (map packs) - Customize > Collections\nsmart playlists - Library"

func _rr_sort_selected(i:int):
	load(RR).set_val("sort", RR_SORTS[i][0])
	_rr_collections_changed()

func _rr_coll_selected(i:int):
	_rr_pick_collection(rr_coll_btn.get_item_metadata(i) if i > 0 else "")

func _rr_pick_collection(n:String):
	load(RR).set_val("collection", n)
	_rr_collections_changed()

# settings / collections changed (also called from the Customize panel and the map page)
func _rr_collections_changed():
	_rr_load()
	_rr_fill()
	if ready:
		cur_map = 0
		reload_to_current_page()
	emit_signal("search_updated")

func reset_filters():
	print("resetting filters")
	rr_batch = true
	emit_signal("reset_filters") # updates line edits (MapSearch and AuthorSearch)
	update_search_dfil([Globals.DIFF_UNKNOWN,Globals.DIFF_EASY,Globals.DIFF_MEDIUM,Globals.DIFF_HARD,Globals.DIFF_LOGIC,Globals.DIFF_AMOGUS])
	update_search_showbroken(false)
#	update_search_showonline(true) # main purpose of this is to show maps you have downloaded already, and this creates a little inconsistent behavior
	update_search_flipped(false)
	update_search_flip_name(false)
	if rr_coll != null: _rr_pick_collection("")
	rr_batch = false
	reload_to_current_page()

# perf mod: which songs are already in a difficulty list, as a set - the stock check was
# add_to.find(map) for every song (O(n^2): ~150 ms on the main thread once the online maps arrive)
var bucketed:Dictionary = {}
func prepare_songs():
	for i in range(songs.size()):
		var map:Song = songs[i]
		var add_to:Array
		match map.difficulty:
			Globals.DIFF_EASY: add_to = easy
			Globals.DIFF_MEDIUM: add_to = medium
			Globals.DIFF_HARD: add_to = hard
			Globals.DIFF_LOGIC: add_to = logic
			Globals.DIFF_AMOGUS: add_to = amogus
			_: add_to = unknown
		if !bucketed.has(map):
			bucketed[map] = true
			add_to.append(map)
	easy = _fast_sort(easy, "sortsongsimple")
	medium = _fast_sort(medium, "sortsongsimple")
	hard = _fast_sort(hard, "sortsongsimple")
	logic = _fast_sort(logic, "sortsongsimple")
	amogus = _fast_sort(amogus, "sortsongsimple")

func make_song_button(id:int=-1):
	if id < 0 or id >= disp.size():
		var btn:Panel = $EMPTY.duplicate()
		btn.rect_min_size = Vector2(int(size_x - (page_size/2) * 10), 0)
		return btn
	var map:Song = disp[id]
	if map == null: return
	var btn:Panel
	match map.difficulty:
		Globals.DIFF_EASY: btn = $EASY.duplicate()
		Globals.DIFF_MEDIUM: btn = $MEDIUM.duplicate()
		Globals.DIFF_HARD: btn = $HARD.duplicate()
		Globals.DIFF_LOGIC: btn = $LOGIC.duplicate()
		Globals.DIFF_AMOGUS: btn = $AMOGUS.duplicate()
		_: btn = $NODIF.duplicate()
	btn.rect_min_size = Vector2(size_x - 50, 0)
	btn.get_node("Label").visible = false
	if map.has_cover:
		btn.get_node("Cover").visible = true
		btn.get_node("Cover").texture = _list_cover(map)
	btn.get_node("Name").visible = true
	if map.name.length() > 55:
		btn.get_node("Name").text = strip_diacritics(map.name)
	else:
		btn.get_node("Name").text = map.name
	btn.song = map
	if map.warning != "" || map.is_broken:
		if map.is_broken: btn.get_node("Name").modulate = Color(1,0.4,0.4)
		else: btn.get_node("Name").modulate = Color(1,1,0.2)
	var rbtn:Button = btn.get_node("Select")
	if is_fav(map): btn.get_node("F").visible = true
	btn.get_node("Cloud").visible = map.is_online
	rbtn.disabled = false
	rbtn.connect("pressed",self,"on_pressed",[id])
	#set the pressed action mode to release so it doesn't trigger on mouse down
	rbtn.action_mode = 1
	rbtn.connect("button_down", self, "check_drag_on")
	rbtn.connect("button_up", self, "check_drag_off")
	rbtn.keep_pressed_outside = true
	rbtn.connect("gui_input", self, "_rr_card_input", [map, id])
	if map == Rhythia.selected_song:
		btn.get_node("Select").pressed = true
	# star rating badge (Steam Rhythia formula) under the map name, osu!-style
	btn.get_node("Name").margin_bottom = -28
	var badge = Control.new()
	badge.set_script(StarBadge)
	badge.align_left = true
	badge.anchor_left = 0; badge.anchor_right = 1
	badge.anchor_top = 1; badge.anchor_bottom = 1
	badge.margin_left = 26; badge.margin_right = -50
	badge.margin_top = -30; badge.margin_bottom = -8
	btn.add_child(badge)
	badge.set_song(map, _badge_font(btn))
	if Look.mono(): # personal build: white focus frame on the selected card
		_rr_card_look(btn)
		var fx = Control.new()
		fx.set_script(MapFocus)
		btn.add_child(fx)
	return btn

# personal build card look: dark base, the cover full-bleed fading in from the left (the name stays
# readable), a difficulty accent bar instead of the thick coloured border, no tile pattern, no
# animated button shader; hover / selection drawn by CardLook.gd and MapFocus.gd. The styles and
# the cover material are made once and shared by every card.
const CardLook = preload("res://mods/stars/CardLook.gd")
# room on the left for the hover / selected slide-out (CardLook.gd), so it isn't clipped by the list
var _room = -1.0
func _rr_room() -> float:
	if _room < 0: _room = CardLook.SEL_SLIDE + 2.0 if Look.mono() else 0.0
	return _room
const COVER_SHADER = """shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float k = smoothstep(0.02, 0.8, UV.x);
	COLOR = vec4(c.rgb * (0.3 + 0.7 * k), c.a) * COLOR;
}"""
var _look_res = null
func _rr_card_look(btn:Panel):
	if _look_res == null:
		var panel = StyleBoxFlat.new()
		panel.bg_color = Color(0.045, 0.045, 0.055, 0.9)
		var pressed = StyleBoxFlat.new()
		pressed.bg_color = Color(1, 1, 1, 0.06)
		var mat = ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = COVER_SHADER
		_look_res = [panel, pressed, StyleBoxEmpty.new(), mat]
	var col = btn.self_modulate
	btn.self_modulate = Color(1, 1, 1, 1)
	btn.add_stylebox_override("panel", _look_res[0])
	var tiles = btn.get_node_or_null("TextureRect")
	if tiles: tiles.visible = false
	var cv = btn.get_node("Cover")
	cv.material = _look_res[3]
	cv.margin_left = 0; cv.margin_top = 0; cv.margin_right = 0; cv.margin_bottom = 0
	var sel = btn.get_node("Select")
	sel.material = null
	for st in ["normal", "hover", "focus", "disabled"]: sel.add_stylebox_override(st, _look_res[2])
	sel.add_stylebox_override("pressed", _look_res[1])
	var fx = Control.new()
	fx.set_script(CardLook)
	fx.col = col
	btn.add_child(fx)
	btn.move_child(fx, cv.get_index() + 1) # (over the cover, under the name / badge / focus)

# right-click a card: that map's actions menu (the map page's ⋯ button: delete, copy, collections,
# export...) opens at the cursor, the map selected first so the menu acts on it
func _rr_card_input(ev, map, i:int):
	if !(ev is InputEventMouseButton) or ev.button_index != BUTTON_RIGHT or !ev.pressed: return
	get_tree().set_input_as_handled()
	if map != Rhythia.selected_song:
		scroll_to(i)
		Rhythia.select_song(map)
	var results = get_viewport().get_node_or_null("Menu/Main/Maps/Results")
	if results: results.visible = true
	call_deferred("_rr_card_menu", get_global_mouse_position())

func _rr_card_menu(at:Vector2):
	var page = get_viewport().get_node_or_null("Menu/Main/Maps/Results/Results")
	var a = null # (the ⋯ MenuButton; the page also has an old "Actions" box)
	var stack = [page] if page else []
	while !stack.empty() and a == null:
		var n = stack.pop_back()
		if n is MenuButton and n.name == "Actions": a = n
		for c in n.get_children(): stack.append(c)
	if a == null or a.disabled: return
	var pm = a.get_popup()
	pm.rect_position = at
	pm.popup()
	# keep it on screen
	var vs = get_viewport_rect().size
	pm.rect_position = Vector2(min(at.x, vs.x - pm.rect_size.x - 4), min(at.y, vs.y - pm.rect_size.y - 4))

const StarBadge = preload("res://mods/stars/StarBadge.gd")
const MapFocus = preload("res://mods/stars/MapFocus.gd")
const Look = preload("res://mods/replay/Look.gd")
var badge_font:Font = null
func _badge_font(btn:Control) -> Font:
	if badge_font: return badge_font
	var f = btn.get_node("Name").get_font("font")
	if f is DynamicFont:
		badge_font = f.duplicate()
		badge_font.size = 18
	else: badge_font = f
	return badge_font

func pg_up():
	scrolling_to = false
	rr_tgt = max(0.0, min(rr_tgt, rr_pos + 0.5) - 1.0)

func pg_down():
	scrolling_to = false
	rr_tgt = min(disp.size() - 1.0, max(rr_tgt, rr_pos - 0.5) + 1.0)

func _rr_shift_up():
	if cur_map <= 0: return
	cur_map -= 1

	$Press.play()
	var out:Panel = btns.pop_back()
	_rr_drop(out)

	var btn:Panel = make_song_button(prev_index())
	btns.insert(0,btn) # BEFORE
	add_child(btn)
	move_child(btn, 0) # to top
	btn.visible = true
	_rr_step(-1)

func _rr_shift_down():
	if cur_map >= disp.size() - 1: return
	cur_map += 1

	$Press.play()
	var out:Panel = btns.pop_front()
	_rr_drop(out)
	var btn:Panel = make_song_button(next_index())
	btns.append(btn) # AFTER
	add_child(btn) # at end
	btn.visible = true
	_rr_step(1)

# Scrolling (Rhythia-reimagined perf): stock grew the new card and shrank the old one over 0.2 s and
# eased every card's width - a min-size change on every frame, so the whole list laid itself out
# again each frame it moved (1,285 -> 227 fps while scrolling). Now a step swaps the cards at their
# final sizes (one layout) and the motion is drawn by moving things instead: the list slides by
# rect_position (glide_y, one card's height per step) and each card's left edge eases to its new
# width by an x offset (meta rr_dx) put back after every layout (sort_children).
var glide_y:float = 0.0
var glide_base = null              # the list's own y (without the glide)
var glide_set:float = 0.0          # y last written (anything else = moved by the game: new base)
const GLIDE_RATE = 20.0
const GLIDE_MAX = 2.5              # cards: further behind than this when steps come fast, it catches up

func _rr_drop(p:Control):
	if !is_instance_valid(p): return
	remove_child(p)
	p.queue_free()

func _rr_step(_dir:int):
	_rr_retarget(false)

# card widths for the current page (the curve of the list); keep = cards still look as wide as before
func _rr_retarget(snap:bool):
	if !is_connected("sort_children", self, "_rr_sorted"): connect("sort_children", self, "_rr_sorted")
	var w = size_x - _rr_room()
	for b in btns:
		if !is_instance_valid(b): continue
		if !b.has_meta("rr_dx"): b.set_meta("rr_dx", 0.0)
		if b.rect_min_size != Vector2(w, 90): b.rect_min_size = Vector2(w, 90)
	rr_arc_dirty = true

func _rr_sorted():
	rr_arc_dirty = true # (cards moved in the layout: their curve again)
	for b in btns:
		if is_instance_valid(b) and b.get_parent() == self: b.set_meta("rr_nx", b.rect_position.x)
	_rr_place()

func _rr_place():
	if glide_base == null or abs(rect_position.y - glide_set) > 0.01: glide_base = rect_position.y
	glide_set = glide_base + glide_y
	if abs(rect_position.y - glide_set) > 0.001: rect_position.y = glide_set
	for b in btns:
		if !is_instance_valid(b) or !b.has_meta("rr_nx"): continue
		# rr_hx: hover / selected slide-out (CardLook.gd) - the card grows out to the left, its right
		# edge stays where it was
		var hx = b.get_meta("rr_hx") if b.has_meta("rr_hx") else 0.0
		var x = b.get_meta("rr_nx") + (b.get_meta("rr_dx") if b.has_meta("rr_dx") else 0.0) - hx
		if abs(b.rect_position.x - x) > 0.01: b.rect_position.x = x
		if hx > 0.0 or b.has_meta("rr_grown"): # (only slid-out cards; at 0 it's put back once)
			var w = b.get_combined_minimum_size().x + hx
			if abs(b.rect_size.x - w) > 0.01: b.rect_size.x = w
			if hx > 0.0: b.set_meta("rr_grown", true)
			else: b.remove_meta("rr_grown")

# osu!-style carousel (Rhythia-reimagined): one continuous scroll position (in cards) easing toward a
# target - the wheel moves the target a card a notch, a drag holds the list to the mouse and a fling
# carries on; the cards swap when the position passes half a card (one new card, no relayout) and
# the list is drawn at the fraction by its offset. The cards bend away from the middle along a
# curve (an x offset from where each card is on screen, every frame it moves).
var rr_pos:float = 0.0          # cards, 0 = the first map in the middle
var rr_tgt:float = 0.0
var rr_cm:int = -1              # cur_map the position last saw (anything else: moved from outside)
var rr_vel:float = 0.0          # drag speed, cards a second
var rr_dragging:bool = false
var rr_drag_from:float = 0.0
var rr_hist:Array = []          # [msec, position] while dragging
var rr_arc_dirty:bool = true
const SCROLL_RATE = 11.0        # easing to the target (1/s)
const HOLD_RATE = 14.0          # cards a second with the UP / DOWN buttons held
const ARC = 120.0               # px the cards at the list's ends bend away

func _rr_glide(delta:float):
	var n = disp.size()
	if n == 0 or btns.size() == 0: return
	if cur_map != rr_cm: # moved from outside (a new page, search, random, the jukebox): no glide
		rr_pos = cur_map
		rr_tgt = cur_map
		rr_cm = cur_map
		rr_arc_dirty = true
	var h = 90.0 + get_constant("separation")
	var before = rr_pos
	if rr_dragging:
		var p = rr_drag_from - (get_global_mouse_position().y - drag_start.y) / h
		if p < 0.0: p = p * 0.35 # (past the ends it gives a little)
		elif p > n - 1: p = n - 1 + (p - n + 1) * 0.35
		rr_pos = p
		var now = OS.get_ticks_msec() # (the speed over the last 0.1 s: frame by frame it's noise at high fps)
		rr_hist.append([now, p])
		while rr_hist.size() > 2 and now - rr_hist[0][0] > 100: rr_hist.pop_front()
		var dt = (now - rr_hist[0][0]) / 1000.0
		rr_vel = (p - rr_hist[0][1]) / dt if dt > 0.01 else 0.0
		rr_tgt = clamp(p, 0, n - 1)
	else:
		if scroll_up: rr_tgt -= HOLD_RATE * delta
		if scroll_down: rr_tgt += HOLD_RATE * delta
		rr_tgt = clamp(rr_tgt, 0, n - 1)
		rr_pos = lerp(rr_pos, rr_tgt, 1.0 - exp(-delta * SCROLL_RATE))
		if abs(rr_pos - rr_tgt) < 0.001: rr_pos = rr_tgt
	var want = int(round(clamp(rr_pos, 0, n - 1)))
	if abs(want - cur_map) > page_size: # (a long way: the page is built there at once)
		cur_map = want
		load_pg()
	var guard = 0
	while want > cur_map and guard < 64:
		_rr_shift_down()
		guard += 1
	while want < cur_map and guard < 64:
		_rr_shift_up()
		guard += 1
	rr_cm = cur_map
	glide_y = (cur_map - rr_pos) * h
	if rr_pos != before or rr_arc_dirty:
		rr_arc_dirty = false
		_rr_place()
		_rr_arc()

func _rr_arc():
	var sc = get_parent()
	var half = max(1.0, sc.rect_size.y / 2.0)
	var changed = false
	for b in btns:
		if !is_instance_valid(b): continue
		var cy = rect_position.y + b.rect_position.y + b.rect_size.y / 2.0
		var t = clamp((cy - half) / half, -1.4, 1.4)
		var dx = ARC * t * t
		var old = b.get_meta("rr_dx") if b.has_meta("rr_dx") else 0.0
		if abs(old - dx) > 0.1:
			b.set_meta("rr_dx", dx)
			changed = true
	if changed: _rr_place()

# Card widths (the curve of the list). Stock started a new tween for every card on every physics
# frame (~1000 tweens a second); now each width just eases toward its target every frame - same
# look, a fraction of the work (Rhythia-reimagined). Height stays with tween_in / tween_out.
# rr_slide_in(): coming from the title screen the cards slide in from the right, one after another
# (width grows from 0 with the content clipped, so each card's left edge sweeps right to left).
const SLIDE_TIME = 0.45
const SLIDE_WAVE = 0.35 # top of the screen to the bottom
var slide_t:float = -1.0

func rr_slide_in():
	slide_t = 0.0
	for b in btns:
		if is_instance_valid(b):
			_slide_prep(b)
			b.rect_min_size.x = 0
			b.modulate.a = 0.0

# while a card is narrow: clip it, and keep the name on one line (no wrapping as it widens)
func _slide_prep(b:Control):
	if b.has_meta("rr_slide"): return
	b.set_meta("rr_slide", true)
	b.rect_clip_content = true
	var n = b.get_node_or_null("Name")
	if n is Label:
		b.set_meta("rr_wrap", n.autowrap)
		n.autowrap = false

func tween_length(delta:float = 0.016):
	var mid = (next_index() - prev_index()) / 2
	var a = 1.0 - exp(-delta * 20.0) # (about the old 0.15 s tween)
	var sliding = slide_t >= 0.0
	if sliding: slide_t += delta
	var done = true
	for i in btns.size():
		var b = btns[i]
		if !is_instance_valid(b): continue
		var w = size_x - 15 * abs(mid - i) - _rr_room()
		var nw:float
		if sliding:
			var vh = max(1.0, get_viewport_rect().size.y)
			var delay = clamp(b.rect_global_position.y / vh, 0.0, 1.0) * SLIDE_WAVE # wave down the screen
			var k = clamp((slide_t - delay) / SLIDE_TIME, 0.0, 1.0)
			if k < 1.0: done = false
			k = 1.0 - pow(1.0 - k, 3) # ease out
			nw = w * k
			_slide_prep(b)
			b.modulate.a = clamp(k * 1.6, 0.0, 1.0)
		else:
			continue # (widths: _rr_retarget / _rr_glide)
		if abs(nw - b.rect_min_size.x) > 0.2: b.rect_min_size.x = nw
	if sliding and done:
		slide_t = -1.0
		for b in btns:
			if is_instance_valid(b) and b.has_meta("rr_slide"):
				b.remove_meta("rr_slide")
				b.rect_clip_content = false
				b.modulate.a = 1.0
				var n = b.get_node_or_null("Name")
				if n is Label and b.has_meta("rr_wrap"): n.autowrap = b.get_meta("rr_wrap")
		_rr_retarget(true)
	if !sliding: _rr_glide(delta)


func _input(ev:InputEvent):
	if is_visible_in_tree() and ev is InputEventMouseButton and ev.is_pressed():
		if ev.button_index == BUTTON_WHEEL_UP:
			pg_up()
		elif ev.button_index == BUTTON_WHEEL_DOWN:
			pg_down()
	if ev is InputEventKey and ev.is_pressed():
		#if f2 is pressed, it will select a random map
		if ev.scancode == KEY_F2:
			print("F2")
			select_random()
		

func handle_window_resize():
#	get_tree().reload_current_scene()
	if ready: size_list()

func firstload():
#	if the button is held down, it will keep scrolling
	get_parent().get_parent().get_parent().get_node("ScrollControl/P").connect("button_down",self,"pg_down_cont")
	get_parent().get_parent().get_parent().get_node("ScrollControl/M").connect("button_down",self,"pg_up_cont")
	get_parent().get_parent().get_parent().get_node("ScrollControl/P").connect("button_up",self,"pg_down_stop")
	get_parent().get_parent().get_parent().get_node("ScrollControl/M").connect("button_up",self,"pg_up_stop")
	
	get_parent().get_parent().get_node("T/Random").connect("pressed",self,"select_random")
	prepare_songs()
	_rr_init()
	reload_to_current_page()
	ready = true
	Rhythia.connect("favorite_songs_changed",self,"reload_to_current_page")
	Rhythia.connect("download_done",self,"update_clouds")
	if Online.has_signal("rr_online_maps_added"): Online.connect("rr_online_maps_added", self, "_rr_online_added")
	get_viewport().connect("size_changed",self,"handle_window_resize")
	Rhythia.emit_signal("map_list_ready")

# the online maps came in after the menu was up (fixes/Online.gd loads them in the background): sort
# them into the difficulty lists and rebuild the page, staying on the selected map
func _rr_online_added():
	prepare_songs()
	build_list()
	if Rhythia.selected_song:
		var i = disp.find(Rhythia.selected_song)
		if i >= 0: cur_map = i
	load_pg()
	emit_signal("search_updated")

func update_clouds():
	for btn in btns:
		if btn.has_node("Cloud") and btn.song:
			btn.get_node("Cloud").visible = btn.song.is_online

func pg_up_cont():
	scrolling_to = false
	scroll_up = true
	
func pg_up_stop():
	scroll_up = false

func pg_down_cont():
	scrolling_to = false
	scroll_down = true

func pg_down_stop():
	scroll_down = false

func scroll_to(i:int):
	if i < 0 or i >= disp.size(): return
	scroll_target = i
	scrolling_to = true

func _ready():
	thread = Thread.new() # list covers (thumbnails), loaded as the maps come on screen
	thread.start(self, "_thumb_worker")

	randomize()
	if !visible: return
	$EASY.visible = false
	$MEDIUM.visible = false
	$HARD.visible = false
	$LOGIC.visible = false
	$AMOGUS.visible = false
	$NODIF.visible = false
	$EMPTY.visible = false

	difficulty_filter = Rhythia.last_difficulty_filter

	Engine.iterations_per_second = 60
	call_deferred("firstload")
	#tryna get the screen size but uh it no change
	size_list()
	
	print("size_x: ", size_x)

func _exit_tree():
	covers_stop = true
	thumb_sem.post()
	thread.wait_to_finish()

func size_list():
	size_x = get_viewport_rect().size.x/2.8
	$"..".rect_min_size.x = size_x
	# personal build: the list clips its cards and would shrink to the widest one - keep it the full
	# width so the room left of the cards (_rr_room) is inside the clip and the selected card's
	# grow-out shows
	if Look.mono():
		# the list fills its side of the page (the cards reach towards the cover; was a 1/2.8 strip
		# with empty space left of it)
		size_x = get_viewport_rect().size.x / 2.6 # (narrower: was 1/2.15)
		$"..".rect_min_size.x = size_x
		rect_min_size.x = size_x

# List covers (Rhythia-reimagined): the stock list loaded every map's full-size cover at startup
# and kept them all in video memory. Now each button gets a small thumbnail (THUMB px), decoded
# on the worker thread only when its map comes on screen; the texture is made on the main
# thread (Android's GLES can't make textures off it). Song keeps the last 120 thumbnails.
const THUMB = 384
var covers_stop:bool = false
var thumb_queue:Array = []
var thumb_mx = Mutex.new()
var thumb_sem = Semaphore.new()

func _list_cover(map):
	if !map.has_method("thumb_image"): return map.cover
	if map.thumb: return map.thumb
	var full = map.loaded_cover()
	if full: return full
	thumb_mx.lock()
	if !thumb_queue.has(map): thumb_queue.append(map)
	thumb_mx.unlock()
	thumb_sem.post()
	return null

func _thumb_worker(_u = null):
	while true:
		thumb_sem.wait()
		if covers_stop: return
		thumb_mx.lock()
		var s = thumb_queue.pop_back() if thumb_queue.size() > 0 else null # newest first: what's on screen now
		thumb_mx.unlock()
		if s == null: continue
		call_deferred("_thumb_ready", s, s.thumb_image(THUMB))

func _thumb_ready(s, img):
	if covers_stop: return
	if !s.thumb: s.set_thumb(img)
	if !s.thumb: return
	for b in btns:
		if is_instance_valid(b) and b.get("song") == s and b.has_node("Cover"):
			b.get_node("Cover").texture = s.thumb

func strip_diacritics(s:String): # we hardcoding tonight   -  edit nvm im literally a genius
#	var diacritics = "[̴̧̳̦̜̱͖̲̺͊͜1̷̨̛̝̼̓͒8̶̳̘̥̰̌̋̎͛̐͛̄̾ͅ6̶̡̛̦̻̭̅͝0̷̼̤͓̹͚͇͐͒́͗̿̍͋̕͜ ̸̦̥̻͈̳̥̲͖̆̀̽̋͘Ḇ̴̢̲̞̰͉̬͙̮̗͒̿̉͛͊P̸̩͉̻͓̱͕͖͉͕̉͌̈̅̃̈͑̚͜͝M̶̡̜͕̺̞͔̾̉ ̵̠̈È̸̛̤̖͍̈̓̏̒̆̋͘x̸̨̛͉̀͛͑͑́t̸̲̹̖̺̥̪̙͗̒̓̆̀͒͒̚r̷̲̩̦̓̔̓̑̀̿́̕͝ã̷̢̢̤̹̹̝̓͌̃͂t̸̲͉͊̀o̸͉͈̿̿̌͋̋n̶̗̺̩̱̠͚͌͛̈́͂̃̀̚͠͝ȩ̷̠̻͕̠̫̗͖̹̊]̶͖̙̳̳̲̪̌̆̄̈͊͛͘͜͜͜͝ ̸̧̩͕̲́̇̃̑A̶̱̖͔̪̦̮̐̉̀͗͊̚͝w̶̢͕̬̪̞̲͚͕̫̠̎̀̾̌̓̊̚͝͠â̵͇̮͖̜̱͙̗k̸̢̛̥̩͈̤̩͍̱͍͇̆̆̀̎̓͐̊̕ȩ̵̦̙̠̬̔̍́̚s̴̡̬̦̈́̈̄͌̃͠y̶̙͒͐̉̆̔ ̸̙̦̲̃͆̇́́͂͠C̵̨̖̻̯̪͎̀̊̄̏͛͗͝h̵̨̦̫̖͇̮̥̿͊̎̂͝r̴̖̙̤͖̤̻̝̬̗̓̄̓̆̇̈́̇̄͠ḭ̷̧̧͙̲͈̬̦̮̈́̀͗͌̕ͅs̴̯̿t̸̡̡͈̰̮͎̺͌̏ͅḿ̸̢̛̼̼͖̗ã̵̢̢̬͜s̶̡̙̼̥̣̺̻̭̱̈̈́̆̒̒̈́͠ͅ ̷̧̗͌́̐̌̽̅͠B̴̨̡̢̟͕̦̹͉̺̔ͅë̷̻̞͎̬͎̗͋̀͐́̅l̷̛̠̪͕͖̊̾l̶̹̤͊͊s̷̛͉͛͌̐͘̚̚͘ ̷͕̯̲̟̦̥͍̞͑̾̀͆͛͑̂͊͐R̵̮̮͖̥̜̠̖̥̲͇̋́i̵̟͚̭̣̙̫̙̘͍͛̍͝ͅņ̷̩͉̮̭͙̌͆g̵̨̡̹̗̗͍̟̟̩̓̾̂̍̆ ̴̺̥̙͉͉̾̉̽f̴͓̏̿̅̋͛̓̓o̴͈̎̀͒̏̚͠͝r̷̡̬͉͇̞̉̈̀ ̶̡̛̘̭̩͓̟̊̆̓̓̏̇͝͝H̴̢͓̫̰́̈̋E̶̛̛̥̬̯̺͊̏̽̀L̵̟̮̞̫̟͗̑̀͂̽͑̔̐̉̕L̷̛̹̼͎̰͗̾̆͋̊́̆͆"
#	if s.is_subsequence_ofi(diacritics):
#		return "[1860] BPM Extratone Awakesy Christmas Bells Ring for HELL"
#	return s
# ^^ this map is the only reason im doing this ^^
#	this removes all COMBINING UTF8 values to prevent spammed diactritics also known as zalgo text since it lags the maplist
#	i found those values at https://www.utf8-chartable.de/unicode-utf8-table.pl?number=1024&utf8=0x -  starts at U+0300 ends at U+036F
#	print(s)
	var pool:PoolByteArray = s.to_utf8()
#	print(pool)
	var output_bytes: Array = []
	
	# List of UTF-8 byte values to remove
	var byte_values_to_remove = [
		0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86,
		0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d,
		0x8e, 0x8f, 0x90, 0x91, 0x92, 0x93, 0x94,
		0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b,
		0x9c, 0x9d, 0x9e, 0x9f, 0xa0, 0xa1, 0xa2,
		0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9,
		0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb0,
		0xb1, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7,
		0xb8, 0xb9, 0xba, 0xbb, 0xbc, 0xbd, 0xbe,
		0xbf, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85,
		0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8c,
		0x8d, 0x8e, 0x8f, 0x90, 0x91, 0x92, 0x93,
		0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a,
		0x9b, 0x9c, 0x9d, 0x9e, 0x9f, 0xa0, 0xa1
	]
	
#	var prev_byte: int = -1
	var removed:bool = false
	for i in range(pool.size() - 1, -1, -1):
		if removed:
			removed = false
			continue
		var byte_value = pool[i]
		var prev_byte = -1
		if i != 0:
			prev_byte = pool[i - 1]
		
		if byte_value in byte_values_to_remove:
			# If the current byte his preceded by 0xcc or 0xcd, remove it and previous byte
			if prev_byte == 0xcc or prev_byte == 0xcd:
				removed = true
				continue
		output_bytes.insert(0, byte_value)
	
	return PoolByteArray(output_bytes).get_string_from_utf8()
	
