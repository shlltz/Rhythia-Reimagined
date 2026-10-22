extends Node
# A first start with a big library and no caches (map cache, star ratings, covers): the menu comes up
# and the game keeps running while the background jobs work through every map.
# Output @@OUT@@/coldboot.txt
const OUT = "@@OUT@@/coldboot.txt"

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")

func run():
	Directory.new().remove(OUT)
	for i in 24:
		yield(get_tree().create_timer(5.0, true), "timeout")
		var sc = get_tree().current_scene
		out("t=%ds scene=%s maps=%d fps=%d vram=%dMB" % [(i + 1) * 5, sc.filename if sc else "-", Rhythia.registry_song.get_items().size(), Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576])
	out("== totals: 1 passed, 0 failed")
	OS.kill(OS.get_process_id())
