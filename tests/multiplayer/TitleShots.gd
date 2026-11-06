extends Node
# Personal-build look check: title screen (closed, open) and a map page with the beat backdrop -
# screenshots + how many beats the backdrop caught in 6 s. RR_RES / RR_FULL as ScreenProbe.
# Output: @@OUT@@/title.txt, title_closed.png, title_open.png, backdrop.png
const OUT = "@@OUT@@/title.txt"

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func shot(n:String):
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png("@@OUT@@/%s.png" % n)

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_fullscreen = OS.get_environment("RR_FULL") == "1"
	var res = OS.get_environment("RR_RES").split("x")
	if !OS.window_fullscreen: OS.window_size = Vector2(int(res[0]), int(res[1])) if res.size() == 2 else Vector2(1280, 720)
	call_deferred("run")

func run():
	Directory.new().remove(OUT)
	yield(wait(25.0), "completed")
	var menu = get_tree().root.get_node("Menu")
	var tm = menu.get_node_or_null("TitleMenu")
	out("title: %s, logo_side %.3f, tilt %.1f" % [tm != null, tm.logo_side if tm else 0.0, tm.tilt if tm else 0.0])
	var vz = menu.get_node_or_null("AudioVisualizer")
	var mx = 0.0
	var t1 = OS.get_ticks_msec()
	while OS.get_ticks_msec() - t1 < 4000:
		yield(get_tree(), "idle_frame")
		if vz and vz.ceiling > 0:
			for k in min(vz.mags.size(), 64): mx = max(mx, vz.mags[k] / vz.ceiling)
	var players = []
	for n in get_tree().root.find_node("PreviewMusic", true, false).get_children() if get_tree().root.find_node("PreviewMusic", true, false) else []:
		if n is AudioStreamPlayer: players.append("%s playing %s" % [n.name, n.playing])
	out("title spectrum max %.2f (ceiling %.4f); music: %s; bus Music muted %s" % [mx, vz.ceiling if vz else -1.0, str(players), AudioServer.is_bus_mute(AudioServer.get_bus_index("Music"))])
	var jb = menu.get_node_or_null("Jukebox")
	var p = jb.player() if jb else null
	out("jukebox: map %s, picked by jukebox %s, playing %s at %.1f s" % [Rhythia.selected_song.name if Rhythia.selected_song else "-", Engine.has_meta("rr_jb") and Engine.get_meta("rr_jb") == Rhythia.selected_song, p.playing if p else false, p.get_playback_position() if p else 0.0])
	var first = Rhythia.selected_song
	jb.next()
	yield(wait(2.0), "completed")
	out("next: map %s (changed %s), playing %s" % [Rhythia.selected_song.name if Rhythia.selected_song else "-", Rhythia.selected_song != first, p.playing if p else false])
	if p and p.stream:
		p.seek(p.stream.get_length() - 1.0)
		var before = Rhythia.selected_song
		yield(wait(3.0), "completed")
		out("song end -> next random map: %s" % (Rhythia.selected_song != before))
	yield(shot("title_closed"), "completed")
	if tm:
		out("expanded before: %s, visible %s" % [tm.expanded, tm.visible])
		tm._expand(true)
		yield(wait(1.2), "completed")
		out("expanded after: %s" % tm.expanded)
		yield(shot("title_open"), "completed")
		tm._close("")
	yield(wait(1.0), "completed")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@":
			Rhythia.select_song(s)
	yield(wait(3.0), "completed")
	var bd = menu.get_node_or_null("MapBackdrop")
	var beats = 0
	var peak = 0.0
	var t0 = OS.get_ticks_msec()
	var last = 0.0
	while OS.get_ticks_msec() - t0 < 6000:
		yield(get_tree(), "idle_frame")
		if bd.punch > 0.99 and last <= 0.99: beats += 1
		last = bd.punch
		peak = max(peak, bd.energy)
	out("backdrop: on %s, vis %.2f, beats in 6 s: %d, energy peak %.2f" % [bd.beat_on, bd.vis, beats, peak])
	yield(shot("backdrop"), "completed")
	out("== done")
	OS.kill(OS.get_process_id())
