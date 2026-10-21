extends Node
# Replay Studio clip recording (Rhythia-reimagined): added by ReplayViewer.gd when the studio asked for
# a clip (Engine meta "rr_clip": {from_rms, to_rms, name, mp4, audio_from_ms, audio_ok, song}). It
# seeks to just before the clip, hides the viewer's controls (the HUD stays), plays at half speed (time to grab frames) and
# grabs the frame after each draw (VisualServer "frame_post_draw") on the GIF and MP4 frame grids of
# replay time; a grid slot the game stepped past gets the same frame again, so the clip keeps the
# replay's timing. ClipExport.gd (on the tree root) writes the files after the replay closes.
# A window that isn't drawn (minimized) gives no frames: after 3 s without one the clip is dropped.

const EX = preload("res://mods/replay/ClipExport.gd")

var viewer = null
var clip:Dictionary = {}
var ex = null
var state:String = "wait"        # wait | rec | done
var next_gif:float = 0.0
var next_mp4:float = 0.0
var want:bool = false
var last_grab:int = 0

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	VisualServer.connect("frame_post_draw", self, "_post_draw")

func _process(_d):
	var sp = viewer.spawn
	if state == "wait":
		if !sp or !sp.notes_loaded: return
		viewer.do_seek(max(clip.from_rms - 600.0, 0.0))
		viewer.ui_state = 1 # (the viewer's "recording" state: the HUD stays, its own controls go)
		viewer.show_keys = false
		viewer.apply_ui_state()
		viewer.set_speed(1) # (0.5x)
		viewer.flash("")
		sp.replay_paused = false
		ex = EX.new()
		ex.clip = clip
		get_tree().root.add_child(ex)
		next_gif = clip.from_rms
		next_mp4 = clip.from_rms
		last_grab = OS.get_ticks_msec()
		state = "rec"
	elif state == "rec":
		sp.replay_paused = false
		if sp.rms >= clip.to_rms:
			_end(false, "")
		elif OS.get_ticks_msec() - last_grab > 3000:
			_end(true, "the game window wasn't drawn (minimized?) - keep it visible while a clip records")
		elif sp.rms >= min(next_gif, next_mp4 if clip.mp4 else 1e18):
			want = true

func _post_draw():
	if state != "rec" or !want: return
	want = false
	var rms = viewer.spawn.rms
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	last_grab = OS.get_ticks_msec()
	while next_gif <= rms and next_gif < clip.to_rms:
		ex.push_gif(img)
		next_gif += 1000.0 / EX.GIF_FPS
	if clip.mp4:
		while next_mp4 <= rms and next_mp4 < clip.to_rms:
			ex.push_mp4(img)
			next_mp4 += 1000.0 / EX.MP4_FPS

func _end(cancelled:bool, why:String):
	if state != "rec": return
	state = "done"
	ex.finish(cancelled)
	if cancelled: Globals.notify(Globals.NOTIFY_WARN, "Clip cancelled: " + why, "Replay Studio")
	viewer.leave()

func _exit_tree(): # (the replay was left by hand while recording)
	if state == "rec":
		state = "done"
		ex.finish(true)
