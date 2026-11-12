extends Node
# Quantum Editor playtest (fixes mod). SSQE starts the game with --a=<audio> --t=<map.txt> --sp=<speed>
# --sf=<start ms>. Stock already loads --a/--t as a single map (Rhythia.single_map_mode_txt) but then
# stops on the menu; init.gd asks begin() for its target instead, so the run starts straight away at
# SSQE's speed and position. The title screen is skipped for the session. A custom speed (not one of
# the presets) is written to custom_speed, which settings.json keeps: the old value goes back on quit.

const SONGLOAD = "res://scenes/loaders/songload.tscn"

var old_custom:float = 1.0

static func begin() -> String:
	var a:Dictionary = Globals.cmdline
	var sp:float = float(a.get("sp", "1"))
	if !(sp > 0.05 and sp < 10.0): sp = 1.0
	Rhythia.start_offset = max(float(a.get("sf", "0")), 0.0)
	Rhythia.replaying = false
	var level:int = -1
	for i in Globals.speed_multi.size():
		if i != Globals.SPEED_CUSTOM and abs(float(Globals.speed_multi[i]) - sp) < 0.0005:
			level = i
			break
	if level == -1:
		var root = Engine.get_main_loop().root
		if !root.has_node("RRPlaytest"): # (init can run twice: keep the first old value)
			var keep = load("res://mods/fixes/Playtest.gd").new()
			keep.name = "RRPlaytest"
			keep.old_custom = Rhythia.custom_speed
			root.call_deferred("add_child", keep)
		Rhythia.custom_speed = sp
		level = Globals.SPEED_CUSTOM
	Rhythia.mod_speed_level = level
	Engine.set_meta("title_seen", true)
	print("[playtest] speed %s, start %s ms" % [sp, Rhythia.start_offset])
	return SONGLOAD

func _notification(what):
	if what == NOTIFICATION_WM_QUIT_REQUEST:
		Rhythia.custom_speed = old_custom
