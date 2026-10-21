extends Node
# startup time only: engine start -> menu ready (driver added by menu2), then quit
func _ready():
	var f = File.new()
	f.open("@@OUT@@/startup.txt", File.WRITE)
	f.store_line("startup %d ms" % OS.get_ticks_msec())
	f.close()
	yield(get_tree().create_timer(3.0), "timeout") # (let the first frames settle, then leave)
	OS.kill(OS.get_process_id())
