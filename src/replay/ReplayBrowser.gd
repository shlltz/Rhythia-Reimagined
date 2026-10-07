extends CanvasLayer
# Replay file browser (Sound Space Plus mod). Lists user://replays, double click / Watch to play.

var panel:Panel
var list:ItemList
var search:LineEdit
var info:Label
var entries:Array = []    # [{path, song, name, date, sort}]
var shown:Array = []
var starting:bool = false
var closing:bool = false
var bg:ColorRect

const UIAnim = preload("res://mods/replay/UIAnim.gd")
const POP_OFFSET = Vector2(0, 60) # panel slides up from here on open, down on close

func _ready():
	layer = 20
	bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	add_child(bg)

	panel = Panel.new()
	if ResourceLoader.exists("res://uitheme.tres"): panel.theme = load("res://uitheme.tres")
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.margin_left = -520
	panel.margin_right = 520
	panel.margin_top = -330
	panel.margin_bottom = 330
	add_child(panel)

	var title = Label.new()
	title.text = "Replays"
	title.margin_left = 20
	title.margin_top = 14
	title.margin_right = 400
	title.margin_bottom = 44
	panel.add_child(title)

	search = LineEdit.new()
	search.placeholder_text = "Search song / mapper / date"
	search.anchor_right = 1
	search.margin_left = 20
	search.margin_right = -20
	search.margin_top = 50
	search.margin_bottom = 82
	search.connect("text_changed", self, "_filter")
	panel.add_child(search)

	list = ItemList.new()
	list.anchor_right = 1
	list.anchor_bottom = 1
	list.margin_left = 20
	list.margin_right = -20
	list.margin_top = 92
	list.margin_bottom = -64
	list.connect("item_activated", self, "_watch")
	list.connect("item_selected", self, "_selected")
	panel.add_child(list)

	info = Label.new()
	info.anchor_top = 1
	info.anchor_bottom = 1
	info.margin_left = 20
	info.margin_right = 560
	info.margin_top = -52
	info.margin_bottom = -16
	info.clip_text = true
	panel.add_child(info)

	var y0 = -54
	var close = make_button("Close", -140, y0)
	close.connect("pressed", self, "close")
	var folder = make_button("Open Folder", -300, y0)
	folder.connect("pressed", self, "_open_folder")
	var watch = make_button("Watch", -460, y0)
	watch.connect("pressed", self, "_watch_selected")

	_load()
	_filter("")
	search.grab_focus()
	UIAnim.play(bg, Vector2.ZERO, Vector2.ZERO, 0.0, 1.0, 0.2)
	UIAnim.play(panel, POP_OFFSET, Vector2.ZERO, 0.0, 1.0, 0.3)

func make_button(text:String, x:float, y:float) -> Button:
	var b = Button.new()
	b.text = text
	b.anchor_left = 1
	b.anchor_top = 1
	b.anchor_right = 1
	b.anchor_bottom = 1
	b.margin_left = x
	b.margin_right = x + 140
	b.margin_top = y
	b.margin_bottom = y + 40
	panel.add_child(b)
	return b

func _load():
	var folder = Globals.p("user://replays")
	var dir = Directory.new()
	if dir.open(folder) != OK: return
	dir.list_dir_begin(true, true)
	var f = dir.get_next()
	while f != "":
		if f.get_extension() == "sspre":
			var base = f.get_basename()
			var dot = base.find_last(".")
			var song_id = base.substr(0, dot) if dot > 0 else base
			var date = base.substr(dot + 1) if dot > 0 else ""
			var song = Rhythia.registry_song.get_item(song_id)
			var title_text = song.name if song else "%s  (map not installed)" % song_id
			var p = date.replace("_", "-").split("-")
			var sort = 0
			var pretty = date
			if p.size() == 6:
				sort = int(p[0]) * 10000000000 + int(p[1]) * 100000000 + int(p[2]) * 1000000 + int(p[3]) * 10000 + int(p[4]) * 100 + int(p[5])
				pretty = "%s-%02d-%02d %02d:%02d" % [p[0], int(p[1]), int(p[2]), int(p[3]), int(p[4])]
			var creator = song.creator if song else ""
			entries.append({path = folder + "/" + f, song = song, name = title_text, date = pretty, sort = sort, creator = creator})
		f = dir.get_next()
	dir.list_dir_end()
	entries.sort_custom(self, "_newest_first")

func _newest_first(a, b):
	return a.sort > b.sort

func _filter(text:String):
	list.clear()
	shown = []
	var q = text.to_lower()
	for e in entries:
		if q != "" and not (q in e.name.to_lower() or q in e.date or q in str(e.creator).to_lower()):
			continue
		list.add_item("%s     %s" % [e.date, e.name])
		if !e.song: list.set_item_custom_fg_color(list.get_item_count() - 1, Color(1, 1, 1, 0.35))
		shown.append(e)
	info.text = "%d replay(s)" % shown.size()

func _selected(i:int):
	var e = shown[i]
	info.text = e.path.get_file()

func _watch_selected():
	var sel = list.get_selected_items()
	if sel.size() > 0: _watch(sel[0])

func _watch(i:int):
	if starting: return
	var e = shown[i]
	if !e.song:
		Globals.notify(Globals.NOTIFY_WARN, "This replay's map is not installed", "Replays")
		return
	starting = true
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = e.path
	var menu = get_tree().root.get_node_or_null("Menu")
	if menu and "black_fade_target" in menu: menu.black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")

func _open_folder():
	OS.shell_open(ProjectSettings.globalize_path(Globals.p("user://replays")))

func close():
	if closing: return
	closing = true
	UIAnim.play(panel, Vector2.ZERO, POP_OFFSET * 0.6, 1.0, 0.0, 0.16)
	UIAnim.play(bg, Vector2.ZERO, Vector2.ZERO, 1.0, 0.0, 0.16).connect("finished", self, "queue_free")

func _input(ev):
	if ev is InputEventKey and ev.pressed and ev.scancode == KEY_ESCAPE:
		get_tree().set_input_as_handled()
		close()
