extends Node
# What the menu scene costs to load and to instance (not added to the tree), 3 times each, uncached.
# Output @@OUT@@/menuload.txt
func _ready():
	call_deferred("run")
func run():
	yield(get_tree().create_timer(4.0), "timeout")
	var f = File.new()
	f.open("@@OUT@@/menuload.txt", File.WRITE)
	for i in 3:
		var u0 = OS.get_ticks_usec()
		var ps = ResourceLoader.load("res://scenes/menu/menu2.tscn", "", true)
		var u1 = OS.get_ticks_usec()
		var inst = ps.instance()
		var u2 = OS.get_ticks_usec()
		var n = 0
		var st = [inst]
		while !st.empty():
			var x = st.pop_back(); n += 1
			for c in x.get_children(): st.append(c)
		inst.free()
		f.store_line("load %.1f ms, instance %.1f ms, %d nodes" % [(u1 - u0) / 1000.0, (u2 - u1) / 1000.0, n])
	f.close()
	OS.kill(OS.get_process_id())
