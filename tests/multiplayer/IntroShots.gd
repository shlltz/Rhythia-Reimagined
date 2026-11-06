extends Node
# Startup intro check (with RR_SWAPS=swaps/intro_shots.py, which saves its frames): waits for the
# menu, notes whether the intro is gone and the music bus unmuted. Output: @@OUT@@/intro.txt
func _ready():
	call_deferred("run")

func run():
	yield(get_tree().create_timer(20.0), "timeout")
	var f = File.new()
	f.open("@@OUT@@/intro.txt", File.WRITE)
	var mb = AudioServer.get_bus_index("Music")
	f.store_line("intro gone: %s, music muted: %s" % [!get_tree().root.has_node("Intro"), AudioServer.is_bus_mute(mb) if mb >= 0 else false])
	f.close()
	OS.kill(OS.get_process_id())
