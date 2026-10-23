extends Reference
# Leftover of "Rewrite Feel" (removed in 2.5.0): that option swapped the player's approach rate,
# spawn distance, FoV and parallax for a run and kept their own values in FILE until the menu put
# them back. A run cut off (game closed / crashed) before 2.5.0 left them there: Boot.gd and menu2
# put them back at startup, and the file goes.

const FILE = "user://rr_feel_restore.json"
const KEYS = ["approach_rate", "spawn_distance", "fov", "parallax", "ui_parallax", "grid_parallax"]

static func restore():
	var f = File.new()
	if !f.file_exists(FILE) or f.open(FILE, File.READ) != OK: return
	var r = JSON.parse(f.get_as_text())
	f.close()
	Directory.new().remove(FILE)
	if r.error != OK or typeof(r.result) != TYPE_DICTIONARY: return
	var n = 0
	for k in r.result:
		if k in KEYS:
			Rhythia.set(k, float(r.result[k]))
			n += 1
	if n > 0 and Rhythia.has_method("save_settings"):
		Rhythia.save_settings()
		print("[feel] restored the settings a Rewrite Feel run had swapped")
