extends Node
# dev probe: a real rewrite .phxm (@@MAP2@@ in the maps folder) imports, exports, re-imports.
# Output @@OUT@@/rw.txt + x_rw.phxm (check it with phxm_check.py)
const OUT = "@@OUT@@/rw.txt"

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func _ready():
	call_deferred("run")

func run():
	Directory.new().remove(OUT)
	yield(get_tree().create_timer(6.0), "timeout")
	var P = load("res://mods/fixes/Phxm.gd")
	var t0 = OS.get_ticks_usec()
	var r = P.import(Globals.p("user://maps/@@MAP2@@"))
	out("import %.0f ms: %s" % [(OS.get_ticks_usec() - t0) / 1000.0, (r.id + " | " + r.name + " | " + r.creator + " | notes %d | diff %d" % [r.read_notes().size(), r.difficulty]) if r is Song else str(r)])
	if r is Song:
		t0 = OS.get_ticks_usec()
		var ex = P.export(r, "@@OUT@@/x_rw.phxm")
		out("export %.0f ms: %s" % [(OS.get_ticks_usec() - t0) / 1000.0, str(ex)])
		var back = P.import(ex.path, "x_rw_back")
		var a = r.read_notes()
		var b = back.read_notes()
		var bad = 0
		for i in min(a.size(), b.size()):
			if int(a[i][2]) != int(b[i][2]) or abs(a[i][0] - b[i][0]) > 1e-4 or abs(a[i][1] - b[i][1]) > 1e-4: bad += 1
		out("re-import: %d notes, %d different" % [b.size(), bad])
	OS.kill(OS.get_process_id())
