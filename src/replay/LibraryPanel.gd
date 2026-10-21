extends CanvasLayer
# Rhythia-reimagined "Library" panel (sidebar button, title card): library statistics + cleanup
# preview, duplicate finder, tags + bulk renaming (with undo), smart playlists, and the Rhythia
# rewrite importer. The logic lives in Library.gd / RewriteImport.gd; this is only the UI.
# Nothing is removed without a confirmation that lists what goes; maps go to the recycle bin.

const L = preload("res://mods/replay/Library.gd")
const Look = preload("res://mods/replay/Look.gd")
const UIAnim = preload("res://mods/replay/UIAnim.gd")
const RP = preload("res://mods/replay/ReimaginedPanel.gd") # (its TabButton)
const W = 1120.0
const H = 700.0
const TABS = [["overview", "Overview", "size, problems, cleanup"], ["dupes", "Duplicates", "same map twice"],
	["tags", "Tags & names", "tag, bulk rename, undo"], ["smart", "Smart playlists", "rules over your plays"],
	["import", "Import from rewrite", "its whole maps folder"]]
const DUP_COLLECTION = "Duplicates to review"

var ACCENT:Color = Look.accent()
var root:Control
var card:Panel
var content:Control
var pages:Dictionary = {}
var tab_buttons:Array = []
var cur:String = ""
var fonts:Dictionary = {}
var closing:bool = false
var dir_dialog:FileDialog

func _ready():
	layer = 30
	root = Control.new()
	root.anchor_right = 1
	root.anchor_bottom = 1
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists("res://uitheme.tres"): root.theme = load("res://uitheme.tres")
	add_child(root)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	root.add_child(dim)
	card = Panel.new()
	card.add_stylebox_override("panel", Look.box(Color(0.05, 0.05, 0.07, 0.98), Color(1, 1, 1, 0.12), 1, 10))
	card.anchor_left = 0.5; card.anchor_right = 0.5; card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.margin_left = -W / 2; card.margin_right = W / 2; card.margin_top = -H / 2; card.margin_bottom = H / 2
	root.add_child(card)
	var title = _label("Library", 32, Color(1, 1, 1))
	title.rect_position = Vector2(28, 18)
	card.add_child(title)
	var tag = _label("%d maps  -  tools never delete without asking" % L.local_maps().size(), 14, Color(1, 1, 1, 0.4))
	tag.rect_position = Vector2(30, 62)
	card.add_child(tag)
	var close = _btn("X", self, "close", [], 38)
	close.flat = true
	close.rect_position = Vector2(W - 58, 20)
	card.add_child(close)
	var tabs = VBoxContainer.new()
	tabs.rect_position = Vector2(16, 108)
	tabs.rect_size = Vector2(220, H - 130)
	tabs.add_constant_override("separation", 6)
	card.add_child(tabs)
	for t in TABS:
		var b = RP.TabButton.new()
		b.title = t[1]
		b.sub = t[2]
		b.font_big = _font(18)
		b.font_small = _font(13)
		b.rect_min_size = Vector2(220, 54)
		b.connect("pressed", self, "show_tab", [t[0]])
		tabs.add_child(b)
		tab_buttons.append(b)
	content = Control.new()
	content.rect_position = Vector2(256, 100)
	content.rect_size = Vector2(W - 256 - 24, H - 100 - 20)
	card.add_child(content)
	dir_dialog = FileDialog.new()
	dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	dir_dialog.mode = FileDialog.MODE_OPEN_DIR
	dir_dialog.window_title = "The rewrite's maps folder"
	dir_dialog.connect("dir_selected", self, "_imp_dir_picked")
	root.add_child(dir_dialog)
	_build_overview()
	_build_dupes()
	_build_tags()
	_build_smart()
	_build_import()
	show_tab(Engine.get_meta("rr_lib_tab") if Engine.has_meta("rr_lib_tab") else "overview", false)
	load("res://mods/replay/Device.gd").touch_fit(card) # (finger-sized buttons on touch screens)
	UIAnim.play(card, Vector2(0, 26), Vector2.ZERO, 0.0, 1.0, 0.3)

func _input(ev):
	if ev is InputEventKey and ev.pressed and !ev.echo and ev.scancode == KEY_ESCAPE:
		if dir_dialog.visible: return
		get_tree().set_input_as_handled()
		close()

func close():
	if closing: return
	if imp and imp.busy: imp.cancel()
	if dup_job: dup_job.cancelled = true
	closing = true
	var t = UIAnim.play(root, Vector2.ZERO, Vector2.ZERO, 1.0, 0.0, 0.2)
	t.connect("finished", self, "queue_free")

func show_tab(id:String, anim:bool = true):
	if id == cur or !pages.has(id): return
	cur = id
	Engine.set_meta("rr_lib_tab", id)
	for i in TABS.size():
		tab_buttons[i].selected = TABS[i][0] == id
		tab_buttons[i].update()
	for k in pages: pages[k].visible = k == id
	if has_method("_show_" + id): call("_show_" + id)
	if anim: UIAnim.play(pages[id], Vector2(18, 0), Vector2.ZERO, 0.0, 1.0, 0.22)

# ------------------------------------------------------------------ building blocks
func _font(size:int):
	if fonts.has(size): return fonts[size]
	var base = root.get_font("font", "Label")
	var f = base
	if base is DynamicFont:
		f = base.duplicate()
		f.size = size
	fonts[size] = f
	return f

func _label(text:String, size:int, col:Color) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", _font(size))
	l.add_color_override("font_color", col)
	return l

func _btn(text:String, target:Object, method:String, args:Array = [], w:float = 0) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(w, 34)
	b.connect("pressed", target, method, args)
	return b

func _page(id:String) -> VBoxContainer:
	var v = VBoxContainer.new()
	v.rect_size = content.rect_size
	v.add_constant_override("separation", 8)
	v.visible = false
	content.add_child(v)
	pages[id] = v
	return v

func _heading(p:Control, text:String, sub:String = ""):
	p.add_child(_label(text, 21, Color(1, 1, 1)))
	if sub != "":
		var s = _label(sub, 13, Color(1, 1, 1, 0.5))
		s.autowrap = true
		s.rect_min_size.x = content.rect_size.x
		p.add_child(s)

func _hbox(p:Control) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 8)
	p.add_child(h)
	return h

func _tree(p:Control, cols:int, titles:Array) -> Tree:
	var t = Tree.new()
	t.columns = cols
	t.hide_root = true
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.select_mode = Tree.SELECT_ROW
	if titles.size() > 0:
		t.set_column_titles_visible(true)
		for i in titles.size(): t.set_column_title(i, titles[i])
	p.add_child(t)
	return t

func _status(p:Control) -> Label:
	var l = _label("", 13, Color(1, 1, 1, 0.7))
	l.autowrap = true
	l.rect_min_size.x = content.rect_size.x
	p.add_child(l)
	return l

# confirm prompt (the game's own dialog): returns the picked index through `done`
func _ask(text:String, title:String, options:Array, target:Object, method:String, args:Array = []):
	var opts = []
	for o in options: opts.append({text = o})
	Globals.confirm_prompt.open(text, title, opts)
	var pick = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	target.callv(method, [pick] + args)

func _len_txt(ms:int) -> String:
	return "%d:%02d" % [int(ms / 60000), int(ms / 1000) % 60]

# ------------------------------------------------------------------ overview + cleanup
var ov_text:Label
var ov_tree:Tree
var ov_status:Label
var cleanup_rows:Array = []

func _build_overview():
	var p = _page("overview")
	_heading(p, "Overview", "What is in your library and what could be tidied. Cleanup only lists caches and leftovers the game rebuilds by itself; maps, replays, scores, settings and skins are never listed.")
	ov_text = _label("", 15, Color(1, 1, 1, 0.85))
	ov_text.autowrap = true
	ov_text.rect_min_size.x = content.rect_size.x
	p.add_child(ov_text)
	p.add_child(_label("Cleanup preview (tick what to move to the recycle bin)", 15, Color(1, 1, 1)))
	ov_tree = _tree(p, 3, ["", "size", "what it is"])
	ov_tree.set_column_expand(1, false)
	ov_tree.set_column_min_width(1, 110)
	var h = _hbox(p)
	h.add_child(_btn("Refresh", self, "_show_overview", [], 120))
	h.add_child(_btn("Clean up ticked", self, "_cleanup_ask", [], 180))
	ov_status = _status(p)

func _show_overview():
	var st = L.stats()
	var lines = PoolStringArray()
	lines.append("%d maps  -  %s in the maps folder (%d files)" % [st.maps, L.human_bytes(st.maps_dir[0]), st.maps_dir[1]])
	lines.append("replays: %s (%d)   caches: %s   tagged maps: %d   smart playlists: %d" % [L.human_bytes(st.replays[0]), st.replays[1], L.human_bytes(st.cache[0]), st.tags, st.smart])
	if st.broken.size() > 0:
		var n = []
		for s in st.broken.slice(0, 5): n.append(s.name if s.name != "" else s.id)
		lines.append("%d broken maps (the game can't read them): %s%s" % [st.broken.size(), PoolStringArray(n).join(", "), "..." if st.broken.size() > 5 else ""])
	else: lines.append("no broken maps")
	if st.no_audio.size() > 0: lines.append("%d maps without audio" % st.no_audio.size())
	ov_text.text = lines.join("\n")
	ov_tree.clear()
	var r = ov_tree.create_item()
	cleanup_rows = L.cleanup_plan()
	for e in cleanup_rows:
		var it = ov_tree.create_item(r)
		it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		it.set_editable(0, true)
		it.set_text(0, "%s  (%d files)" % [e.label, e.files])
		it.set_text(1, L.human_bytes(e.bytes))
		it.set_text(2, e.note)
		it.set_metadata(0, e)
	if cleanup_rows.empty(): ov_status.text = "Nothing to clean up."

func _cleanup_ask():
	var picked = []
	var it = ov_tree.get_root().get_children() if ov_tree.get_root() else null
	while it:
		if it.is_checked(0): picked.append(it.get_metadata(0))
		it = it.get_next()
	if picked.empty():
		ov_status.text = "Tick something first."
		return
	var txt = "Move these to the recycle bin?\n"
	var total = 0
	for e in picked:
		txt += "\n- %s: %d files, %s" % [e.label, e.files, L.human_bytes(e.bytes)]
		total += e.bytes
	_ask(txt, "Clean up %s" % L.human_bytes(total), ["Cancel", "Clean up"], self, "_cleanup_go", [picked])

func _cleanup_go(pick:int, picked:Array):
	if pick != 1: return
	var failed = 0
	for e in picked: failed += L.cleanup_apply(e)
	_show_overview()
	ov_status.text = "Done." + (" %d files couldn't be removed." % failed if failed > 0 else "")

# ------------------------------------------------------------------ duplicates
var dup_tree:Tree
var dup_status:Label
var dup_job = null
var dup_bar:ProgressBar

func _build_dupes():
	var p = _page("dupes")
	_heading(p, "Duplicate finder", "Exact = the same notes, read from every map file (also files the library hides because another file has the same map id). Possible = same title and length within 2 s but different notes (another version or difficulty). Tick the copies you don't want: nothing happens until you confirm.")
	var h = _hbox(p)
	h.add_child(_btn("Scan library", self, "_dup_scan", [], 160))
	h.add_child(_btn("Put ticked in a collection", self, "_dup_collect", [], 240))
	h.add_child(_btn("Recycle ticked maps...", self, "_dup_delete_ask", [], 220))
	dup_bar = ProgressBar.new()
	dup_bar.rect_min_size = Vector2(0, 8)
	dup_bar.percent_visible = false
	dup_bar.visible = false
	p.add_child(dup_bar)
	dup_tree = _tree(p, 5, ["map", "mapper", "notes", "length", "played"])
	dup_tree.set_column_min_width(0, 3) # (expand ratio: the name column gets most of the width)
	for c in [2, 3, 4]:
		dup_tree.set_column_expand(c, false)
		dup_tree.set_column_min_width(c, 80)
	dup_status = _status(p)

func _dup_scan():
	if dup_job: return
	dup_status.text = "Reading %d maps..." % L.local_maps().size()
	dup_bar.visible = true
	dup_job = L.scan_duplicates()
	dup_job.connect("done", self, "_dup_done")
	set_process(true)

func _process(_d):
	if dup_job and dup_bar: dup_bar.value = dup_job.progress * 100.0

func _dup_done(groups:Array):
	dup_job = null
	dup_bar.visible = false
	dup_tree.clear()
	var r = dup_tree.create_item()
	var hist = L.history()
	var exact = 0
	for g in groups:
		if g.kind == "exact": exact += 1
		var head = dup_tree.create_item(r)
		head.set_text(0, ("EXACT  " if g.kind == "exact" else "POSSIBLE  ") + str(g.items[0].name))
		head.set_custom_color(0, ACCENT.lightened(0.3) if g.kind == "exact" else Color(1, 1, 1, 0.6))
		head.set_selectable(0, false)
		for it in g.items:
			var row = dup_tree.create_item(head)
			row.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			row.set_editable(0, true)
			row.set_text(0, it.name + ("" if it.get("in_library", true) else "   (hidden: another file has this id)"))
			row.set_text(1, it.get("creator", ""))
			row.set_text(2, str(it.get("notes", "")))
			row.set_text(3, _len_txt(it.get("len", 0)))
			var h = hist.get(it.id, {})
			row.set_text(4, ("%d plays" % h.get("plays", 0)) if h.get("plays", 0) > 0 else ("PB" if h.get("best_file", false) else "-"))
			row.set_metadata(0, it)
			row.set_tooltip(0, "%s\nid %s\n%s" % [it.path, it.id, L.human_bytes(it.size)])
	dup_status.text = "%d groups: %d exact, %d possible. Keep the one with your scores (\"played\")." % [groups.size(), exact, groups.size() - exact] if !groups.empty() else "No duplicates found."

func _dup_ticked() -> Array:
	var out = []
	if !dup_tree.get_root(): return out
	var g = dup_tree.get_root().get_children()
	while g:
		var it = g.get_children()
		while it:
			if it.is_checked(0): out.append(it.get_metadata(0))
			it = it.get_next()
		g = g.get_next()
	return out

func _dup_collect():
	var ids = []
	for it in _dup_ticked():
		if it.get("in_library", true): ids.append(it.id)
	if ids.empty():
		dup_status.text = "Tick some maps first."
		return
	var R = load("res://mods/replay/Reimagined.gd")
	R.coll_create(DUP_COLLECTION)
	for id in ids:
		if !R.coll_has(DUP_COLLECTION, id): R.coll_toggle(DUP_COLLECTION, id)
	dup_status.text = "%d maps are in the collection \"%s\" (pick it in the map list's collection filter)." % [ids.size(), DUP_COLLECTION]

func _dup_delete_ask():
	var items = _dup_ticked()
	if items.empty():
		dup_status.text = "Tick the copies you don't want first."
		return
	var txt = "Move these %d map files to the recycle bin? Their personal bests and replays stay.\n" % items.size()
	for it in items.slice(0, 11): txt += "\n- " + it.path.get_file()
	if items.size() > 12: txt += "\n... and %d more" % (items.size() - 12)
	_ask(txt, "Recycle maps", ["Cancel", "Recycle"], self, "_dup_delete_go", [items])

# by file path: a hidden file shares its id with the map the library shows, so the id isn't enough
func _dup_delete_go(pick:int, items:Array):
	if pick != 1: return
	var done = 0
	var failed = []
	for it in items:
		var path = it.path
		if path == "" or path.begins_with("res://") or !File.new().file_exists(path):
			failed.append(path.get_file())
			continue
		var ok = OS.move_to_trash(ProjectSettings.globalize_path(path)) == OK if OS.has_feature("pc") else Directory.new().remove(path) == OK
		if !ok:
			failed.append(path.get_file())
			continue
		var s = Rhythia.registry_song.get_item(it.id)
		if s is Song and ProjectSettings.globalize_path(s.filePath) == path: Rhythia.registry_song.check_and_remove_id(it.id)
		done += 1
	if done > 0: get_tree().call_group("rr_collections", "_rr_collections_changed")
	dup_status.text = "%d maps moved to the recycle bin." % done + (" Couldn't remove: " + PoolStringArray(failed).join(", ") if !failed.empty() else "")
	_dup_scan()

# ------------------------------------------------------------------ tags + bulk rename
var tag_search:LineEdit
var tag_list:ItemList
var tag_edit:LineEdit
var tag_cloud:Label
var tpl_edit:LineEdit
var ren_tree:Tree
var tag_status:Label
var shown_maps:Array = []
var ren_plan:Array = []

func _build_tags():
	var p = _page("tags")
	_heading(p, "Tags & names", "Pick maps (Ctrl / Shift for many; search works like the map list, incl. tag=name), then tag them or rename them. Renaming changes the name stored in the map (what the list shows), never the file: scores, replays and collections stay attached. Every rename can be undone.")
	var h = _hbox(p)
	tag_search = LineEdit.new()
	tag_search.placeholder_text = "search maps (words, mapper=, tag=)"
	tag_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_search.connect("text_changed", self, "_tag_filter")
	h.add_child(tag_search)
	h.add_child(_btn("Select all shown", self, "_tag_select_all", [], 170))
	tag_list = ItemList.new()
	tag_list.select_mode = ItemList.SELECT_MULTI
	tag_list.rect_min_size = Vector2(0, 190)
	tag_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(tag_list)
	h = _hbox(p)
	tag_edit = LineEdit.new()
	tag_edit.placeholder_text = "tag"
	tag_edit.rect_min_size = Vector2(200, 0)
	h.add_child(tag_edit)
	h.add_child(_btn("Add tag", self, "_tag_apply", [true], 110))
	h.add_child(_btn("Remove tag", self, "_tag_apply", [false], 120))
	tag_cloud = _label("", 13, Color(1, 1, 1, 0.55))
	tag_cloud.autowrap = true
	tag_cloud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tag_cloud)
	h = _hbox(p)
	tpl_edit = LineEdit.new()
	tpl_edit.text = "{artist} - {title}"
	tpl_edit.hint_tooltip = "tokens: " + L.TOKENS
	tpl_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tpl_edit)
	h.add_child(_btn("Preview rename", self, "_ren_preview", [], 160))
	h.add_child(_btn("Apply", self, "_ren_ask", [], 90))
	h.add_child(_btn("Undo last", self, "_ren_undo_ask", [], 110))
	p.add_child(_label("tokens: " + L.TOKENS, 12, Color(1, 1, 1, 0.4)))
	ren_tree = _tree(p, 3, ["now", "after", ""])
	ren_tree.rect_min_size = Vector2(0, 120)
	ren_tree.set_column_expand(2, false)
	ren_tree.set_column_min_width(2, 110)
	tag_status = _status(p)

func _show_tags():
	_tag_filter(tag_search.text)

func _tag_filter(t:String):
	var words = []
	var tag_f = ""
	var mapper_f = ""
	for w in t.to_lower().split(" ", false):
		if w.begins_with("tag="): tag_f = w.substr(4)
		elif w.begins_with("mapper="): mapper_f = w.substr(7)
		else: words.append(w)
	shown_maps = []
	tag_list.clear()
	var all = L.local_maps()
	all.sort_custom(self, "_by_name")
	for s in all:
		var hay = (s.name + "\n" + s.creator).to_lower()
		var ok = true
		for w in words:
			if hay.find(w) == -1: ok = false
		if mapper_f != "" and s.creator.to_lower().find(mapper_f) == -1: ok = false
		if tag_f != "":
			var has = false
			for g in L.tags_of(s.id):
				if g.find(tag_f) != -1: has = true
			if !has: ok = false
		if !ok: continue
		shown_maps.append(s)
		var tg = L.tags_of(s.id)
		tag_list.add_item("%s   -  %s%s" % [s.name, s.creator, ("   [" + PoolStringArray(tg).join(", ") + "]") if !tg.empty() else ""])
	var cloud = []
	var at = L.all_tags()
	for k in at: cloud.append("%s (%d)" % [k, at[k]])
	tag_cloud.text = ("tags: " + PoolStringArray(cloud).join("  ")) if !cloud.empty() else "no tags yet"
	tag_status.text = "%d maps shown" % shown_maps.size()

func _by_name(a, b):
	return a.name.to_lower() < b.name.to_lower()

func _tag_select_all():
	for i in tag_list.get_item_count(): tag_list.select(i, false)

func _picked_maps() -> Array:
	var out = []
	for i in tag_list.get_selected_items(): out.append(shown_maps[i])
	return out

func _tag_apply(add:bool):
	var maps = _picked_maps()
	if maps.empty() or tag_edit.text.strip_edges() == "":
		tag_status.text = "Pick maps and type a tag."
		return
	var ids = []
	for s in maps: ids.append(s.id)
	var n = L.tag_maps(ids, tag_edit.text, add)
	_tag_filter(tag_search.text)
	tag_status.text = "%s \"%s\" on %d maps." % ["Added" if add else "Removed", L.clean_tag(tag_edit.text), n]

func _ren_preview():
	var maps = _picked_maps()
	if maps.empty():
		tag_status.text = "Pick the maps to rename."
		return
	ren_plan = L.rename_plan(maps, tpl_edit.text)
	ren_tree.clear()
	var r = ren_tree.create_item()
	var counts = {}
	for e in ren_plan:
		counts[e.status] = counts.get(e.status, 0) + 1
		var it = ren_tree.create_item(r)
		it.set_text(0, e.old)
		it.set_text(1, e.new)
		it.set_text(2, {"ok": "", "same": "unchanged", "collision": "renumbered", "empty": "empty: skipped", "builtin": "can't: skipped"}[e.status])
		if e.status == "collision": it.set_custom_color(2, Color(1, 0.8, 0.3))
	tag_status.text = "%d will change (%d renumbered to avoid the same name twice), %d unchanged, %d skipped. Nothing is written until you press Apply." % [counts.get("ok", 0) + counts.get("collision", 0), counts.get("collision", 0), counts.get("same", 0), counts.get("empty", 0) + counts.get("builtin", 0)]

func _ren_ask():
	var n = 0
	for e in ren_plan:
		if e.status in ["ok", "collision"]: n += 1
	if n == 0:
		tag_status.text = "Preview a rename first."
		return
	_ask("Rename %d maps? A copy of each file is kept so \"Undo last\" can put them back." % n, "Rename", ["Cancel", "Rename"], self, "_ren_go")

func _ren_go(pick:int):
	if pick != 1: return
	var r = L.rename_apply(ren_plan)
	ren_plan = []
	ren_tree.clear()
	_tag_filter(tag_search.text)
	var t = "Renamed %d maps." % r.done
	for f in r.failed: t += "\n%s: %s" % [f[0], f[1]]
	tag_status.text = t

func _ren_undo_ask():
	var j = L.journals()
	if j.empty():
		tag_status.text = "Nothing to undo."
		return
	_ask("Undo the rename of %d maps from %s?" % [j[0].rows.size(), _when(j[0].t)], "Undo rename", ["Cancel", "Undo"], self, "_ren_undo_go", [j[0].id])

func _ren_undo_go(pick:int, jid:String):
	if pick != 1: return
	var r = L.undo(jid)
	_tag_filter(tag_search.text)
	var t = "Put back %d maps." % r.restored
	for f in r.failed: t += "\n%s: %s" % [f[0], f[1]]
	tag_status.text = t

func _when(t:int) -> String:
	var d = OS.get_datetime_from_unix_time(t)
	return "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]

# ------------------------------------------------------------------ smart playlists
var sm_list:ItemList
var sm_fields:Dictionary = {}
var sm_preview:ItemList
var sm_status:Label
var sm_sel:int = -1
const SORTS = [["stars", "stars (low first)"], ["stars_desc", "stars (high first)"], ["plays", "most played"], ["last_played", "last played"], ["added", "newest file"], ["name", "name"]]

func _build_smart():
	var p = _page("smart")
	_heading(p, "Smart playlists", "Playlists that fill themselves from your real plays and ratings. Play counts and failed runs are the ones recorded since Rhythia|Reimagined started keeping them; a personal-best file counts as played. Pick one in the map list's collection filter (\"smart: ...\").")
	var h = _hbox(p)
	var left = VBoxContainer.new()
	left.rect_min_size = Vector2(250, 330)
	h.add_child(left)
	sm_list = ItemList.new()
	sm_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sm_list.connect("item_selected", self, "_sm_pick")
	left.add_child(sm_list)
	var lb = _hbox(left)
	lb.add_child(_btn("New", self, "_sm_new", [], 70))
	lb.add_child(_btn("Delete", self, "_sm_delete", [], 80))
	lb.add_child(_btn("Defaults", self, "_sm_defaults", [], 90))
	var form = GridContainer.new()
	form.columns = 2
	form.add_constant_override("vseparation", 6)
	form.add_constant_override("hseparation", 10)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(form)
	_sm_field(form, "name", "Name", LineEdit.new())
	for k in ["stars_min", "stars_max"]:
		var sp = SpinBox.new()
		sp.min_value = -1
		sp.max_value = 30
		sp.step = 0.1
		sp.hint_tooltip = "-1 = no limit"
		_sm_field(form, k, "Stars at least" if k == "stars_min" else "Stars at most", sp)
	var pl = OptionButton.new()
	for o in ["any", "played", "unplayed"]: pl.add_item(o)
	_sm_field(form, "played", "Played", pl)
	for k in [["failed_days", "Failed in the last (days)"], ["added_days", "Added in the last (days)"], ["limit", "At most (0 = all)"]]:
		var sp = SpinBox.new()
		sp.max_value = 100000
		_sm_field(form, k[0], k[1], sp)
	for k in [["favorites", "Favorites only"], ["untagged", "Maps without tags"]]:
		_sm_field(form, k[0], "", _check(k[1]))
	_sm_field(form, "tag", "Has tag", LineEdit.new())
	var so = OptionButton.new()
	for o in SORTS: so.add_item(o[1])
	_sm_field(form, "sort", "Sort", so)
	form.add_child(Control.new())
	var fb = HBoxContainer.new()
	fb.add_constant_override("separation", 8)
	fb.add_child(_btn("Save", self, "_sm_save", [], 90))
	fb.add_child(_btn("Show in map list", self, "_sm_use", [], 170))
	form.add_child(fb)
	sm_preview = ItemList.new()
	sm_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(sm_preview)
	sm_status = _status(p)

func _check(text:String) -> CheckBox:
	var c = CheckBox.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	return c

func _sm_field(form:Control, key:String, text:String, ctl:Control):
	form.add_child(_label(text, 14, Color(1, 1, 1, 0.8)))
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(ctl)
	sm_fields[key] = ctl

func _show_smart():
	sm_list.clear()
	var ctx = L.smart_ctx()
	for r in L.smart_lists(): sm_list.add_item("%s  (%d)" % [r.name, L.smart_eval(r, ctx).size()])
	if sm_sel >= 0 and sm_sel < sm_list.get_item_count():
		sm_list.select(sm_sel)
		_sm_fill(L.smart_lists()[sm_sel])
	elif sm_list.get_item_count() > 0:
		sm_list.select(0)
		_sm_pick(0)

func _sm_pick(i:int):
	sm_sel = i
	_sm_fill(L.smart_lists()[i])

func _sm_fill(r:Dictionary):
	sm_fields.name.text = r.get("name", "")
	sm_fields.stars_min.value = float(r.get("stars_min", -1))
	sm_fields.stars_max.value = float(r.get("stars_max", -1))
	sm_fields.played.select(max(0, ["any", "played", "unplayed"].find(str(r.get("played", "any")))))
	sm_fields.failed_days.value = int(r.get("failed_days", 0))
	sm_fields.added_days.value = int(r.get("added_days", 0))
	sm_fields.limit.value = int(r.get("limit", 0))
	sm_fields.favorites.pressed = bool(r.get("favorites", false))
	sm_fields.untagged.pressed = bool(r.get("untagged", false))
	sm_fields.tag.text = str(r.get("tag", ""))
	var si = 0
	for i in SORTS.size():
		if SORTS[i][0] == r.get("sort", "name"): si = i
	sm_fields.sort.select(si)
	_sm_preview(r)

func _sm_rule() -> Dictionary:
	var r = {"name": sm_fields.name.text.strip_edges()}
	if sm_fields.stars_min.value >= 0: r.stars_min = sm_fields.stars_min.value
	if sm_fields.stars_max.value >= 0: r.stars_max = sm_fields.stars_max.value
	var pl = ["any", "played", "unplayed"][max(0, sm_fields.played.selected)]
	if pl != "any": r.played = pl
	for k in ["failed_days", "added_days", "limit"]:
		if sm_fields[k].value > 0: r[k] = int(sm_fields[k].value)
	if sm_fields.favorites.pressed: r.favorites = true
	if sm_fields.untagged.pressed: r.untagged = true
	if sm_fields.tag.text.strip_edges() != "": r.tag = sm_fields.tag.text.strip_edges()
	r.sort = SORTS[max(0, sm_fields.sort.selected)][0]
	return r

func _sm_preview(r:Dictionary):
	sm_preview.clear()
	var res = L.smart_eval(r)
	for s in res.slice(0, 199): sm_preview.add_item("%s  -  %s" % [s.name, s.creator])
	sm_status.text = "%d maps match%s." % [res.size(), " (first 200 shown)" if res.size() > 200 else ""]

func _sm_save():
	var r = _sm_rule()
	if r.name == "":
		sm_status.text = "Give it a name."
		return
	var lists = L.smart_lists()
	for i in lists.size():
		if lists[i].name == r.name and i != sm_sel:
			sm_status.text = "Another playlist already has that name."
			return
	if sm_sel >= 0 and sm_sel < lists.size(): lists[sm_sel] = r
	else:
		lists.append(r)
		sm_sel = lists.size() - 1
	L.save_smart()
	_show_smart()

func _sm_new():
	sm_sel = -1
	_sm_fill({"name": "New playlist", "sort": "name"})
	sm_list.unselect_all()

func _sm_delete():
	var lists = L.smart_lists()
	if sm_sel < 0 or sm_sel >= lists.size(): return
	lists.remove(sm_sel)
	sm_sel = -1
	L.save_smart()
	_show_smart()

func _sm_defaults():
	var lists = L.smart_lists()
	var have = {}
	for r in lists: have[r.name] = true
	for r in L.SMART_DEFAULTS:
		if !have.has(r.name): lists.append(r.duplicate(true))
	L.save_smart()
	_show_smart()

func _sm_use():
	var r = _sm_rule()
	if L.smart_rule(r.name) == null:
		sm_status.text = "Save it first."
		return
	load("res://mods/replay/Reimagined.gd").set_val("collection", L.SMART_PREFIX + r.name)
	get_tree().call_group("rr_collections", "_rr_collections_changed")
	close()

# ------------------------------------------------------------------ import from the rewrite
var imp = null
var imp_dir:LineEdit
var imp_tree:Tree
var imp_bar:ProgressBar
var imp_status:Label
var imp_btns:Array = []
var imp_rows:Array = []

func _build_import():
	var p = _page("import")
	_heading(p, "Import from the Rhythia rewrite", "Reads every .phxm / .sspm map in the rewrite's maps folder (the folder itself is only read). New maps are ticked; maps you already have are left out, possible duplicates (same title + length) are unticked for you to decide.")
	var h = _hbox(p)
	imp_dir = LineEdit.new()
	imp_dir.text = load("res://mods/replay/RewriteImport.gd").default_folder()
	imp_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(imp_dir)
	if OS.has_feature("pc"): h.add_child(_btn("Browse...", self, "_imp_browse", [], 110))
	imp_btns.append(_btn("Scan", self, "_imp_scan", [], 90))
	h.add_child(imp_btns[-1])
	h = _hbox(p)
	imp_btns.append(_btn("Tick all new", self, "_imp_tick", ["new"], 140))
	h.add_child(imp_btns[-1])
	imp_btns.append(_btn("Tick duplicates too", self, "_imp_tick", ["possible duplicate"], 190))
	h.add_child(imp_btns[-1])
	imp_btns.append(_btn("Import ticked", self, "_imp_go", [], 160))
	h.add_child(imp_btns[-1])
	h.add_child(_btn("Cancel", self, "_imp_cancel", [], 100))
	imp_bar = ProgressBar.new()
	imp_bar.rect_min_size = Vector2(0, 8)
	imp_bar.percent_visible = false
	p.add_child(imp_bar)
	imp_tree = _tree(p, 5, ["map", "mapper", "notes", "length", "status"])
	for c in [2, 3]:
		imp_tree.set_column_expand(c, false)
		imp_tree.set_column_min_width(c, 80)
	imp_tree.set_column_expand(4, false)
	imp_tree.set_column_min_width(4, 170)
	imp_status = _status(p)
	imp = load("res://mods/replay/RewriteImport.gd").new()
	imp.name = "RewriteImport"
	add_child(imp)
	imp.connect("scan_progress", self, "_imp_scan_progress")
	imp.connect("scanned", self, "_imp_scanned")
	imp.connect("import_progress", self, "_imp_progress")
	imp.connect("imported", self, "_imp_done")

func _show_import():
	if imp_rows.empty():
		imp_status.text = "Folder found - press Scan." if Directory.new().dir_exists(imp_dir.text) else "No rewrite maps folder there. Pick the folder with Browse (or type its path)."

func _imp_browse():
	dir_dialog.current_dir = imp_dir.text if Directory.new().dir_exists(imp_dir.text) else OS.get_user_data_dir()
	dir_dialog.popup_centered_ratio(0.7)

func _imp_dir_picked(d:String):
	imp_dir.text = d

func _imp_busy(v:bool):
	for b in imp_btns: b.disabled = v

func _imp_scan():
	if !Directory.new().dir_exists(imp_dir.text):
		imp_status.text = "That folder doesn't exist."
		return
	imp_tree.clear()
	imp_rows = []
	_imp_busy(true)
	imp_status.text = "Scanning..."
	imp.scan(imp_dir.text)

func _imp_scan_progress(done:int, total:int):
	imp_bar.value = 100.0 * done / max(1, total)
	imp_status.text = "Scanning... %d / %d" % [done, total]

func _imp_scanned(rows:Array):
	_imp_busy(false)
	imp_rows = rows
	imp_bar.value = 100
	imp_tree.clear()
	var r = imp_tree.create_item()
	var c = {}
	for row in rows:
		var st = row.get("status", "error")
		c[st] = c.get(st, 0) + 1
		var it = imp_tree.create_item(r)
		it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		it.set_editable(0, st == "new" or st == "possible duplicate")
		it.set_checked(0, st == "new")
		it.set_text(0, row.get("name", row.path.get_file()))
		it.set_tooltip(0, row.path)
		it.set_text(1, row.get("creator", ""))
		it.set_text(2, str(row.get("notes", "")))
		it.set_text(3, _len_txt(row.get("length", 0)) if row.has("length") else "")
		it.set_text(4, row.get("error", st) if st == "error" else (st + (" of " + row.dup_of if row.has("dup_of") else "")))
		if st == "error": it.set_custom_color(4, Color(1, 0.45, 0.45))
		elif st == "installed": it.set_custom_color(4, Color(1, 1, 1, 0.4))
		elif st == "possible duplicate": it.set_custom_color(4, Color(1, 0.8, 0.3))
		it.set_metadata(0, row)
	imp_status.text = "%d maps found: %d new, %d already installed, %d possible duplicates, %d unreadable." % [rows.size(), c.get("new", 0), c.get("installed", 0), c.get("possible duplicate", 0), c.get("error", 0)]

func _imp_tick(status:String):
	if !imp_tree.get_root(): return
	var it = imp_tree.get_root().get_children()
	while it:
		if it.get_metadata(0).get("status", "") == status: it.set_checked(0, true)
		it = it.get_next()

func _imp_go():
	var rows = []
	if imp_tree.get_root():
		var it = imp_tree.get_root().get_children()
		while it:
			if it.is_checked(0): rows.append(it.get_metadata(0))
			it = it.get_next()
	if rows.empty():
		imp_status.text = "Nothing ticked."
		return
	_imp_busy(true)
	imp_bar.value = 0
	imp_status.text = "Importing %d maps..." % rows.size()
	imp.import_rows(rows)

func _imp_progress(done:int, total:int, row:Dictionary):
	imp_bar.value = 100.0 * done / max(1, total)
	imp_status.text = "Importing... %d / %d  (%s)" % [done, total, row.get("name", "")]

func _imp_done(rep:Dictionary):
	_imp_busy(false)
	var t = "Imported %d maps in %.1f s." % [rep.imported.size(), rep.ms / 1000.0]
	if rep.cancelled: t += " Cancelled before the end."
	if !rep.skipped.empty(): t += " Skipped %d (already there)." % rep.skipped.size()
	for f in rep.failed.slice(0, 7): t += "\n%s: %s" % [f[0].get("name", f[0].path.get_file()), f[1]]
	if rep.failed.size() > 8: t += "\n... %d more failed" % (rep.failed.size() - 8)
	imp_status.text = t
	imp.scan(imp_dir.text) # (statuses again: the imported ones are installed now)
	_imp_busy(true)

func _imp_cancel():
	if imp and imp.busy:
		imp.cancel()
		imp_status.text = "Stopping after the current map..."
