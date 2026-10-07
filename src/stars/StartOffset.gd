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

func upd_label():
	var total_seconds = int(self.value)
	var minutes = floor(total_seconds / 60)
	var seconds = total_seconds % 60
	$TimeTextBox.text = "%d:%02d" % [minutes,seconds]
	var btn = _preview()
	if !btn or !btn.has_node("Song"): return
	var song_preview:AudioStreamPlayer = btn.get_node("Song")
	if !song_preview.playing and user and !btn.disabled: btn._pressed() # start the preview, then jump
	if song_preview.playing:
		song_preview.seek(max(0.0, total_seconds + Rhythia.music_offset / 1000.0))
