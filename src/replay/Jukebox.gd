extends Node
# Background music from your maps (personal build, after the Rhythia lazer fork's jukebox): on the
# first menu of a session a random map from the library is selected, so its song plays through the
# map page's preview player (PreviewMusic/Song), from the beginning (the preview starts mid-song), and
# its cover is the backdrop. When a song the
# jukebox picked comes round to its start again (the preview loops), the next random map follows.
# A map you pick yourself loops as before; next() (the now playing panel) hands it back to the
# jukebox. Added by menu2.gd as "Jukebox". Engine meta rr_jb = the song the jukebox picked.

var menu:Node
var bag:Array = []                # shuffled maps still to come (no repeats until all have played)
var last_pos:float = -1.0
var started:bool = false
var restart:bool = false          # the next stream that plays is the jukebox's song: seek it to 0:00
var restart_from = null           # (the stream playing before it)
var restart_t:float = 0.0

func _ready():
	menu = get_parent()
	Rhythia.connect("selected_song_changed", self, "_picked")

func _exit_tree():
	if Rhythia.is_connected("selected_song_changed", self, "_picked"): Rhythia.disconnect("selected_song_changed", self, "_picked")

# the player the selected map's song plays through (null before the map page is built)
var _player_cache = null
func player() -> AudioStreamPlayer:
	if !is_instance_valid(_player_cache):
		var pm = menu.find_node("PreviewMusic", true, false)
		_player_cache = pm.get_node_or_null("Song") if pm else null
	return _player_cache

func playing_map():
	var p = player()
	if p and p.stream and (p.playing or p.stream_paused): return Rhythia.selected_song
	return null

func _process(delta):
	if !started:
		# once per session, after the map list has its maps
		if Engine.has_meta("rr_jb_started"):
			started = true
		else:
			var list = menu.get_node_or_null("Main/Maps/MapRegistry/S/VBoxContainer")
			if (list and list.get("ready")) or (!list and Rhythia.registry_song and Rhythia.registry_song.get_items().size() > 0):
				started = true
				Engine.set_meta("rr_jb_started", true)
				next()
		return
	var p = player()
	if !p or !p.stream or !Engine.has_meta("rr_jb") or Engine.get_meta("rr_jb") != Rhythia.selected_song:
		last_pos = -1.0
		return
	if p.stream_paused: return
	# the preview starts in the middle of the song: the jukebox's song starts from the beginning
	# (once its stream is in - the map page builds it on a worker)
	if restart:
		restart_t += delta
		if p.playing and p.stream != restart_from:
			restart = false
			p.seek(0.0)
			last_pos = -1.0
			return
		if restart_t > 6.0: restart = false
	var pos = p.get_playback_position()
	var length = p.stream.get_length()
	# looped back to the start, or stopped at the end: next map
	if last_pos >= 0 and ((pos + 2.0 < last_pos and last_pos > length - 3.0) or (!p.playing and last_pos > length - 3.0)):
		last_pos = -1.0
		next()
		return
	last_pos = pos if p.playing else last_pos

func _picked(_s = null):
	if Engine.has_meta("rr_jb") and Engine.get_meta("rr_jb") != Rhythia.selected_song: Engine.remove_meta("rr_jb")

# select the next random map from the library (its song plays as the preview)
func next():
	var s = _draw()
	if s == null: return
	Engine.set_meta("rr_jb", s)
	last_pos = -1.0
	var old = player()
	restart_from = old.stream if old else null
	restart = true
	restart_t = 0.0
	Rhythia.select_song(s)
	_sync_list(s)
	var p = player() # (preview off in the settings: play it anyway, it's the background music)
	if p and !Rhythia.auto_preview_song:
		var btn = p.get_parent()
		if btn and btn.has_method("upd"): btn.upd(s)

func _draw():
	if bag.empty():
		for s in Rhythia.registry_song.get_items():
			if s and !s.is_online and !s.is_broken and s != Rhythia.selected_song: bag.append(s)
		bag.shuffle()
	return bag.pop_back() if !bag.empty() else null

# the map list scrolls to the jukebox's map (so the selection is on screen when you get there)
func _sync_list(s):
	var list = menu.get_node_or_null("Main/Maps/MapRegistry/S/VBoxContainer")
	if !list or !list.get("ready") or !("disp" in list): return
	var i = list.disp.find(s)
	if i < 0: return
	list.cur_map = i
	list.load_pg(false)
