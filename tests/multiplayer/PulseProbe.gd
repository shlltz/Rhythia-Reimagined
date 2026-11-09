extends Node
# Background cover pulse vs the map's notes: on the map page with the preview playing, logs each
# backdrop hit (punch jumping up) with the heard time and the nearest note accent; then a title menu
# screenshot. Output @@OUT@@/pulse.txt, page.png, title.png
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	OS.window_size = Vector2(1920, 1080)
	call_deferred("run")
var bd = null
var hy = null
var pl = null
var prev = 0.0
var hits = []
var sampling = false
func run():
	yield(get_tree().create_timer(24.0), "timeout")
	var menu = get_tree().root.get_node("Menu")
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("")
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": Rhythia.select_song(s)
	yield(get_tree().create_timer(3.0), "timeout")
	bd = menu.get_node_or_null("MapBackdrop")
	hy = menu.get_node_or_null("Main/Maps/Results/Results/Hype")
	pl = hy._preview_song() if hy else null
	sampling = true
	yield(get_tree().create_timer(6.0), "timeout")
	sampling = false
	var f = File.new()
	f.open("@@OUT@@/pulse.txt", File.WRITE)
	f.store_line("backdrop %s hype %s accents %s playing %s" % [bd != null, hy != null, hy.accents.size() / 2 if hy and hy.accents else -1, pl.playing if pl else false])
	var errs = []
	for h in hits:
		var best = 1e9
		if hy and hy.accents:
			for i in range(0, hy.accents.size(), 2):
				var d = h - hy.accents[i]
				if abs(d) < abs(best): best = d
		errs.append(best)
		f.store_line("hit at %.0f ms, nearest note %+.0f ms" % [h, best])
	f.store_line("%d hits" % hits.size())
	f.close()
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png("@@OUT@@/page.png")
	menu.show_title()
	yield(get_tree().create_timer(1.5), "timeout")
	img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png("@@OUT@@/title.png")
	OS.kill(OS.get_process_id())
func _process(_d):
	if !sampling or !bd or !pl: return
	var p = bd.punch
	if p > prev + 0.3:
		hits.append((pl.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()) * 1000.0)
	prev = p
