extends Node
# Settings plumbing probe: fresh Rhythia defaults, does setting a control apply + save. Output @@OUT@@/settings2.txt
const OUT = "@@OUT@@/settings2.txt"
var f:File
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")
func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")
func sj() -> String:
	var g = File.new()
	if g.open(Globals.p("user://settings.json"), File.READ) != OK: return ""
	var t = g.get_as_text(); g.close(); return t
func run():
	yield(wait(6.0), "completed")
	f = File.new()
	f.open(OUT, File.WRITE)
	var t0 = OS.get_ticks_usec()
	var d = Rhythia.get_script().new()
	f.store_line("fresh instance: %d us, class %s" % [OS.get_ticks_usec() - t0, d.get_class()])
	for k in ["disable_pausing", "fov", "sensitivity", "hitwindow_ms", "note_hitbox_size", "cursor_color", "panel_bg", "approach_rate", "enable_grid", "record_replays"]:
		f.store_line("  %s: default=%s live=%s" % [k, str(d.get(k)), str(Rhythia.get(k))])
	var meths = []
	for m in Rhythia.get_method_list():
		if "save" in m.name or "setting" in m.name: meths.append(m.name)
	f.store_line("methods: " + str(meths))
	d.free()
	var menu = get_tree().root.get_node("Menu")
	var tabs = menu.get_node("Main/Settings/S/F/TabContainer")
	var cb = tabs.get_node("UI/UI/Group/H/Grid")
	var before = sj()
	var was = Rhythia.enable_grid
	cb.pressed = !cb.pressed
	yield(wait(1.5), "completed")
	f.store_line("checkbox set: Rhythia.enable_grid %s -> %s, settings.json changed: %s" % [str(was), str(Rhythia.enable_grid), str(sj() != before)])
	var sp = tabs.get_node("Gameplay/Camera/Group/H/FOV/FOV")
	before = sj()
	var fv = Rhythia.get("fov")
	sp.value = sp.value + 5
	yield(wait(1.5), "completed")
	f.store_line("spinbox set: fov %s -> %s, settings.json changed: %s" % [str(fv), str(Rhythia.get("fov")), str(sj() != before)])
	var cp = tabs.get_node("World & Cursor/Cursor/Group/H/cursor_color/Color")
	before = sj()
	cp.color = Color(1, 0, 0)
	yield(wait(0.5), "completed")
	f.store_line("color set (no signal): %s changed json %s" % [str(Rhythia.cursor_color), str(sj() != before)])
	cp.emit_signal("color_changed", Color(1, 0, 0))
	yield(wait(1.0), "completed")
	f.store_line("color + signal: %s changed json %s" % [str(Rhythia.cursor_color), str(sj() != before)])
	# all HBox rows: their child classes
	for t in tabs.get_children():
		for sec in t.get_children():
			var h = sec.get_node_or_null("Group/H")
			if !h: continue
			for r in h.get_children():
				if r is HBoxContainer or (r.get_class() == "Control"):
					var kids = []
					for c in r.get_children(): kids.append("%s:%s%s" % [c.name, c.get_class(), "" if c.visible else "(hid)"])
					f.store_line("%s/%s %s [%s] %s" % [t.name, r.name, r.get_class(), "vis" if r.visible else "hid", str(kids)])
	f.close()
	OS.kill(OS.get_process_id())
