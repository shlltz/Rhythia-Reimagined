extends Reference
# Auto-delete mod: after a map was imported successfully, move the file it came from
# (.sspm / Vulnus .zip/.vmap archive / map .txt) to the Recycle Bin.
# Never touches files inside the game's own data folder (maps, temp, ...) or folders.

func trash(path:String) -> bool:
	if path == "" or path.begins_with("res://"): return false
	var g = ProjectSettings.globalize_path(path).replace("\\", "/")
	var user = ProjectSettings.globalize_path(Globals.p("user://")).replace("\\", "/").trim_suffix("/") + "/"
	if g.to_lower().begins_with(user.to_lower()): return false
	var d = Directory.new()
	if !d.file_exists(g): return false
	var err = OS.move_to_trash(g)
	if err == OK:
		print("[import] moved imported file to the Recycle Bin: %s" % g)
		Globals.notify(Globals.NOTIFY_INFO, "%s was moved to the Recycle Bin" % g.get_file(), "Map imported", 4)
		return true
	print("[import] could not move %s to the Recycle Bin (error %s)" % [g, err])
	return false
