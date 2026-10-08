extends HSlider
# Start From slider (stock script, Rhythia-reimagined fixes): the map preview follows the slider so
# you can find the spot by ear. Stock looked the preview player up by an absolute path, which broke
# when SongInfoScreen moved the buttons under the mods bar, so the song never seeked. Moving the
# slider (or typing a time) also starts the preview there when it isn't playing.

var user:bool = false # true while the change comes from the player, not a map change

func get_seconds_from_ms(ms:float):
	return max(floor(ms / 1000),0)

func value_changed(value):
	Rhythia.start_offset = value * 1000
	call_deferred("upd_label")

func on_map_selected(map):
	user = false
	self.max_value = get_seconds_from_ms(Rhythia.selected_song.last_ms)
	self.value = 0

func _ready():
	connect("value_changed",self,"value_changed")
	$TimeTextBox.connect("text_entered", self, "time_text_entered")
	Rhythia.connect("selected_song_changed",self,"on_map_selected")

	if (Rhythia.selected_song != null):	# after song pass
		on_map_selected(null)
		self.value = Rhythia.start_offset / 1000

func _gui_input(ev):
	if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventMouseMotion and ev.button_mask) or ev is InputEventKey or ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		user = true

func time_text_entered(new_text):
	var time = new_text.split(':',false,1)
	var total_seconds:int

	if time.size() == 2: total_seconds = int(time[0]) * 60 + int(time[1])
	else: total_seconds = int(time[0])
	user = true
	self.value = total_seconds

var preview:Button = null
func _preview() -> Button:
	if !is_instance_valid(preview):
		var menu = get_tree().root.get_node_or_null("Menu")
		preview = menu.find_node("PreviewMusic", true, false) if menu else null
	return preview

# Crash hardening (Rhythia-reimagined): a drag fires value_changed on every mouse move and each
# one seeked the preview (a fresh decoder restart on the audio thread every frame), could press
# the preview button again while it was still starting, and could seek past the end of a song
# shorter than the map. Now: seeks are throttled while dragging (the exact spot is seeked when
# the slider settles), the preview is started at most once per 0.5 s and never for maps whose
# music failed to load, and every seek stays inside the song.
const SEEK_GAP_MS = 80
var last_seek_ms:int = -100000
var last_start_ms:int = -100000
var seek_pending:bool = false

func upd_label():
	var total_seconds = int(self.value)
	var minutes = floor(total_seconds / 60)
	var seconds = total_seconds % 60
	$TimeTextBox.text = "%d:%02d" % [minutes,seconds]
	_sync_preview()

func _sync_preview():
	var btn = _preview()
	if !btn or !btn.is_inside_tree() or !btn.has_node("Song"): return
	var song_preview:AudioStreamPlayer = btn.get_node("Song")
	var now = OS.get_ticks_msec()
	if !song_preview.playing:
		if !user or btn.disabled or now - last_start_ms < 500: return
		var s = Rhythia.selected_song
		if !s or s.is_broken: return
		last_start_ms = now
		btn._pressed() # start the preview, then jump
		if !song_preview.playing or song_preview.stream == Globals.error_sound:
			return
	if now - last_seek_ms < SEEK_GAP_MS: # dragging: seek again when it settles
		if !seek_pending:
			seek_pending = true
			get_tree().create_timer(SEEK_GAP_MS / 1000.0).connect("timeout", self, "_flush_seek")
		return
	last_seek_ms = now
	var st = song_preview.stream
	if !st or st == Globals.error_sound: return
	var length = st.get_length()
	var to = max(0.0, int(self.value) + Rhythia.music_offset / 1000.0)
	if length > 1.0: to = min(to, length - 0.5)
	song_preview.seek(to)

func _flush_seek():
	seek_pending = false
	if is_inside_tree(): _sync_preview()
