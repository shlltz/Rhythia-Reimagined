extends Node
# Startup intro check (with RR_SWAPS=swaps/intro_shots.py, which saves its frames): waits for the
# menu, notes whether the intro is gone and the music bus unmuted at its own volume; the Music bus
# (muted / dB) every 0.25 s shows the song fading in. Output: @@OUT@@/intro.txt
func _ready():
	call_deferred("run")

func run():
	var mb = AudioServer.get_bus_index("Music")
	var trail = []
	for i in 80:
		yield(get_tree().create_timer(0.25), "timeout")
		if mb < 0: continue
		var db = AudioServer.get_bus_volume_db(mb)
		trail.append("%s%.0f" % ["M" if AudioServer.is_bus_mute(mb) else "", db])
	var f = File.new()
	f.open("@@OUT@@/intro.txt", File.WRITE)
	f.store_line("intro gone: %s, music muted: %s, music volume %.1f dB" % [!get_tree().root.has_node("Intro"), AudioServer.is_bus_mute(mb) if mb >= 0 else false, AudioServer.get_bus_volume_db(mb) if mb >= 0 else 0.0])
	f.store_line("music bus every 0.25 s (M = muted): " + PoolStringArray(trail).join(" "))
	f.close()
	OS.kill(OS.get_process_id())
