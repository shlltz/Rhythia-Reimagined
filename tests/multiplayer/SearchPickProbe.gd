extends Node
# osu!-style search pick: a search that drops the selected map picks the first result; one that
# still matches it keeps it. Output @@OUT@@/search.txt
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")
func run():
	yield(get_tree().create_timer(24.0), "timeout")
	var menu = get_tree().root.get_node("Menu")
	var tm = menu.get_node_or_null("TitleMenu")
	if tm: tm._close("")
	var first = null
	for s in Rhythia.registry_song.get_items():
		if !s.is_online and s.filePath.get_file() == "@@MAP1@@": first = s
	Rhythia.select_song(first)
	yield(get_tree().create_timer(2.0), "timeout")
	var list = menu.get_node("Main/Maps/MapRegistry/S/VBoxContainer")
	var f = File.new()
	f.open("@@OUT@@/search.txt", File.WRITE)
	for q in ["final-boss", "titanfall", "", "zzzznomatch", "camellia"]:
		list.update_search_text(q)
		yield(get_tree().create_timer(0.5), "timeout")
		f.store_line("%-12s -> %s (results %d, list at %s)" % [q, Rhythia.selected_song.name if Rhythia.selected_song else "-", list.disp.size(), list.disp[list.cur_map].name if list.disp.size() else "-"])
	f.close()
	OS.kill(OS.get_process_id())
