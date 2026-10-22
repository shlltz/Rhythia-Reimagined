extends Node
# Rhythia rewrite library importer (Rhythia-reimagined). The rewrite (Rhythia/Client) keeps its
# maps as .phxm archives in <user folder>/maps/<map set>/ and an unpacked copy of each in
# <user folder>/cache/maps/<id>/ (MapUtil.cs, MapParser.cs); its user folder is the Godot user dir
# "Rhythia" next to ours unless user_folder_path.txt there ("CurrentDir:<path>") moved it.
#
# scan(folder): every .phxm / .sspm / unpacked map folder under it, read on a worker (metadata and
# note count only), duplicates of one map inside the folder merged (archive preferred), each one
# checked against the library: "installed" (its id is there), "possible duplicate" (same
# normalised name, length within 2 s) or "new". import_rows(rows): converted one by one on the
# worker (Phxm.load_song without textures + Song.convert_to_sspm); only adding each map to the
# library runs on the main thread. Cancel stops after the current map. Nothing is deleted or moved
# in the source folder.

signal scan_progress(done, total)
signal scanned(rows)
signal import_progress(done, total, row)
signal imported(report)

const TMP = "user://rr_phxm_bulk"
var thread:Thread = null
var cancelled:bool = false
var busy:bool = false
var _lib_ids:Dictionary = {}
var _lib_names:Dictionary = {}
var _report:Dictionary = {}

static func default_folder() -> String:
	var base = OS.get_user_data_dir().get_base_dir().plus_file("Rhythia")
	var f = File.new()
	var ptr = base.plus_file("user_folder_path.txt")
	if f.file_exists(ptr) and f.open(ptr, File.READ) == OK:
		for line in f.get_as_text().split("\n"):
			if line.begins_with("CurrentDir:"):
				var p = line.substr(11).strip_edges()
				if p != "" and Directory.new().dir_exists(p): base = p
		f.close()
	return base.plus_file("maps")

# ------------------------------------------------------------------ scan
func scan(folder:String) -> bool:
	if busy: return false
	busy = true
	cancelled = false
	_snapshot()
	thread = Thread.new()
	thread.start(self, "_scan_run", folder)
	return true

func _snapshot(): # the library as plain data for the worker
	_lib_ids = {}
	_lib_names = {}
	var L = load("res://mods/replay/Library.gd")
	for s in L.local_maps():
		_lib_ids[s.id] = s.name
		var k = L.norm(s.name)
		if k != "": _lib_names[k] = _lib_names.get(k, []) + [[int(s.last_ms), s.id]]

func _scan_run(folder:String):
	var found = []
	_walk(folder, found, 0)
	var P = load("res://mods/fixes/Phxm.gd")
	var L = load("res://mods/replay/Library.gd")
	var rows = []
	var by_id = {}
	for i in found.size():
		if cancelled: break
		var path = found[i]
		var row = {"path": path, "kind": "phxm" if path.get_extension().to_lower() == "phxm" else ("sspm" if path.get_extension().to_lower() == "sspm" else "folder")}
		if row.kind == "sspm":
			var s = Song.new()
			s.load_from_sspm(path)
			if s.is_broken or s.id == "":
				row.error = "broken .sspm"
			else:
				row.id = path.get_file().get_basename()
				row.name = s.name
				row.creator = s.creator
				row.notes = s.note_count
				row.length = int(s.last_ms)
		else:
			var pk = P.peek(path)
			if pk is String: row.error = pk
			else:
				var md = pk.meta
				row.id = pk.id
				var at = str(md.get("Artist", "")).strip_edges()
				var ti = str(md.get("Title", "")).strip_edges()
				row.name = ("%s - %s" % [at, ti]) if at != "" else ti
				row.creator = PoolStringArray(md.get("Mappers", [])).join(", ") if md.get("Mappers") is Array else ""
				row.notes = pk.notes
				row.length = pk.length
		if !row.has("error"):
			row.status = "new"
			if _lib_ids.has(row.id): row.status = "installed"
			else:
				for e in _lib_names.get(L.norm(row.name), []):
					if abs(e[0] - row.length) <= 2000:
						row.status = "possible duplicate"
						row.dup_of = e[1]
			if by_id.has(row.id): # the same map twice in the folder (archive + unpacked copy): keep the archive
				var j = by_id[row.id]
				if rows[j].kind == "folder" and row.kind != "folder": rows[j] = row
				continue
			by_id[row.id] = rows.size()
		rows.append(row)
		if i % 4 == 0: call_deferred("emit_signal", "scan_progress", i + 1, found.size())
	call_deferred("_scan_done", rows)

func _walk(p:String, out:Array, depth:int):
	if depth > 6 or cancelled: return
	var d = Directory.new()
	if d.open(p) != OK: return
	if File.new().file_exists(p.plus_file("objects.phxmo")):
		out.append(p)
		return
	var dirs = []
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if d.current_is_dir(): dirs.append(p.plus_file(n))
		elif n.get_extension().to_lower() in ["phxm", "sspm"]: out.append(p.plus_file(n))
		n = d.get_next()
	d.list_dir_end()
	dirs.sort()
	for sub in dirs: _walk(sub, out, depth + 1)

func _scan_done(rows:Array):
	if thread and thread.is_active(): thread.wait_to_finish()
	busy = false
	emit_signal("scanned", rows)

# ------------------------------------------------------------------ import
func import_rows(rows:Array) -> bool:
	if busy: return false
	busy = true
	cancelled = false
	_report = {"imported": [], "skipped": [], "failed": [], "cancelled": false, "ms": OS.get_ticks_msec()}
	thread = Thread.new()
	thread.start(self, "_import_run", rows)
	return true

func _import_run(rows:Array):
	var P = load("res://mods/fixes/Phxm.gd")
	for i in rows.size():
		if cancelled:
			_report.cancelled = true
			break
		var row = rows[i]
		var res = ""
		if row.kind == "sspm":
			var dest = Globals.p("user://maps/%s.sspm" % row.id)
			if File.new().file_exists(dest): res = "a map file with this id is already there"
			elif Directory.new().copy(row.path, dest) != OK: res = "couldn't copy the file"
			else: res = dest
		else:
			var s = P.load_song(row.path, "", false, TMP)
			if s is String: res = s
			elif File.new().file_exists(Globals.p("user://maps/%s.sspm" % s.id)): res = "a map file with this id is already there"
			else:
				var r = str(s.convert_to_sspm())
				res = Globals.p("user://maps/%s.sspm" % s.id) if r == "Converted!" else r
			P._clear_tmp(TMP)
		# (the library itself is only touched on the main thread)
		call_deferred("_one_done", i, rows.size(), row, res)
	call_deferred("_import_done")

func _one_done(i:int, total:int, row:Dictionary, res:String):
	var t0 = OS.get_ticks_usec()
	if res.ends_with(".sspm") and File.new().file_exists(res): # (errors are plain sentences)
		var reg = Rhythia.registry_song
		reg.check_and_remove_id(res.get_file().get_basename())
		if reg.add_sspm_map(res) != null: _report.imported.append(row)
		else: _report.failed.append([row, "the converted map didn't load"])
	elif "already there" in res: _report.skipped.append([row, res])
	else: _report.failed.append([row, res])
	_report.main_ms = max(_report.get("main_ms", 0.0), (OS.get_ticks_usec() - t0) / 1000.0)
	emit_signal("import_progress", i + 1, total, row)

func _import_done():
	if thread and thread.is_active(): thread.wait_to_finish()
	busy = false
	_report.ms = OS.get_ticks_msec() - _report.ms
	var t0 = OS.get_ticks_usec()
	if !_report.imported.empty(): # one list refresh at the end (it queues the new maps' star ratings itself)
		get_tree().call_group("rr_collections", "_rr_collections_changed")
	_report.refresh_ms = (OS.get_ticks_usec() - t0) / 1000.0
	emit_signal("imported", _report)

func cancel():
	cancelled = true

func _exit_tree():
	cancelled = true
	if thread and thread.is_active(): thread.wait_to_finish()
