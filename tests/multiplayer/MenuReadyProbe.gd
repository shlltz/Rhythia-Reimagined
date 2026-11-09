extends Node
# Which nodes' _ready make the menu slow to come up: a second menu is instanced and added under a
# holder (side effects are the test instance's own), every node's "ready" signal timestamped; the gap
# before a node's ready (its children are ready just before it) ~ its own _ready. Top 25.
# Output @@OUT@@/menuready.txt
var times = []
func _ready():
	call_deferred("run")
func _r(n):
	times.append([OS.get_ticks_usec(), n])
func run():
	yield(get_tree().create_timer(6.0), "timeout")
	var inst = load("res://scenes/menu/menu2.tscn").instance()
	var st = [inst]
	while !st.empty():
		var x = st.pop_back()
		x.connect("ready", self, "_r", [x])
		for c in x.get_children(): st.append(c)
	var holder = Node.new()
	add_child(holder)
	var u0 = OS.get_ticks_usec()
	holder.add_child(inst)
	var u1 = OS.get_ticks_usec()
	var gaps = []
	var prev = u0
	for t in times:
		var p = str(t[1].get_path()) if is_instance_valid(t[1]) and t[1].is_inside_tree() else "?"
		var sc = t[1].get_script() if is_instance_valid(t[1]) else null
		gaps.append([(t[0] - prev) / 1000.0, p.replace(str(holder.get_path()), ""), sc.resource_path.get_file() if sc else ""])
		prev = t[0]
	gaps.sort_custom(self, "_desc")
	var f = File.new()
	f.open("@@OUT@@/menuready.txt", File.WRITE)
	f.store_line("add_child (enter tree + every _ready): %.1f ms, %d ready signals" % [(u1 - u0) / 1000.0, times.size()])
	for g in gaps.slice(0, 24): f.store_line("%7.2f ms  %s  %s" % g)
	f.close()
	OS.kill(OS.get_process_id())
func _desc(a, b): return a[0] > b[0]
