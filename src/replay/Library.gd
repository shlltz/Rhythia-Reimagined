extends Reference
# Library tools (Rhythia-reimagined): tags, smart playlists, duplicate finder, bulk display-name
# renaming with an undo journal, statistics and a cleanup preview. Logic only (LibraryPanel.gd is
# the UI). Everything reads the real library (Rhythia.registry_song), the real play history
# (RecentPlays.gd: every finished run since the mod started recording, plus the game's own
# personal-best files in user://bests) and the real star ratings (StarCache.gd). Nothing in here
# deletes a map; cleanup only ever moves cache files to the recycle bin, after a preview.

const TAGS_FILE = "user://rr_tags.json"
const SMART_FILE = "user://rr_smart.json"
const JOURNAL_DIR = "user://rr_library/journal"
const SMART_PREFIX = "smart:"     # collection names the map list treats as smart playlists

# ------------------------------------------------------------------ maps
static func local_maps() -> Array:
	var out = []
	if !Rhythia.registry_song: return out
	for s in Rhythia.registry_song.get_items():
		if s is Song and !s.is_online and s.id != "!DELETED": out.append(s)
	return out

# "Artist - Title" -> [artist, title] ("" artist when the name has no " - ")
static func split_name(n:String) -> Array:
	var i = n.find(" - ")
	return [n.substr(0, i).strip_edges(), n.substr(i + 3).strip_edges()] if i > 0 else ["", n.strip_edges()]

# lower case letters + digits only (duplicate names, the browser's "installed" check does the same)
static func norm(t:String) -> String:
	var o = ""
	for c in t.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c.ord_at(0) > 127: o += c
	return o

static func _read(path:String):
	var f = File.new()
	if !f.file_exists(Globals.p(path)) or f.open(Globals.p(path), File.READ) != OK: return null
	var r = parse_json(f.get_as_text())
	f.close()
	return r

static func _write(path:String, v) -> bool:
	Directory.new().make_dir_recursive(Globals.p(path).get_base_dir())
	var f = File.new()
	if f.open(Globals.p(path) + ".tmp", File.WRITE) != OK: return false
	f.store_string(to_json(v))
	f.close()
	var d = Directory.new()
	if d.file_exists(Globals.p(path)): d.remove(Globals.p(path))
	return d.rename(Globals.p(path) + ".tmp", Globals.p(path)) == OK

# ------------------------------------------------------------------ tags (id -> [tag])
static func tags() -> Dictionary:
	if Engine.has_meta("rr_tags"): return Engine.get_meta("rr_tags")
	var t = {}
	var d = _read(TAGS_FILE)
	if typeof(d) == TYPE_DICTIONARY:
		for k in d:
			if d[k] is Array and !d[k].empty(): t[str(k)] = d[k]
	Engine.set_meta("rr_tags", t)
	return t

static func clean_tag(t:String) -> String:
	return t.strip_edges().to_lower().replace(",", " ").replace("  ", " ")

static func tags_of(id:String) -> Array:
	return tags().get(id, [])

static func save_tags():
	_write(TAGS_FILE, tags())
	if Engine.get_main_loop(): Engine.get_main_loop().call_group("rr_collections", "_rr_collections_changed")

# add / remove one tag on many maps; returns how many maps changed
static func tag_maps(ids:Array, tag:String, add:bool) -> int:
	tag = clean_tag(tag)
	if tag == "": return 0
	var t = tags()
	var n = 0
	for id in ids:
		var cur:Array = t.get(id, []).duplicate()
		if add and !cur.has(tag): cur.append(tag)
		elif !add and cur.has(tag): cur.erase(tag)
		else: continue
		n += 1
		if cur.empty(): t.erase(id)
		else: t[id] = cur
	if n > 0: save_tags()
	return n

static func all_tags() -> Dictionary: # tag -> count
	var c = {}
	for id in tags():
		for g in tags()[id]: c[g] = c.get(g, 0) + 1
	return c

# ------------------------------------------------------------------ play history
# {id: {plays, fails:[unix times], last, best_file}} from the real records
static func history() -> Dictionary:
	var out = {}
	var rp = load("res://mods/stars/RecentPlays.gd")
	var all = rp._load() if rp else {}
	for id in all:
		var e = {"plays": 0, "fails": [], "last": 0}
		for p in all[id]:
			e.plays += 1
			e.last = max(e.last, int(p.get("t", 0)))
			if !p.get("passed", false): e.fails.append(int(p.get("t", 0)))
		out[id] = e
	var d = Directory.new()
	if d.open(Globals.p("user://bests")) == OK: # a personal-best file = played at least once (also before the mod)
		d.list_dir_begin(true, true)
		var n = d.get_next()
		while n != "":
			if !d.current_is_dir():
				if !out.has(n): out[n] = {"plays": 0, "fails": [], "last": 0}
				out[n]["best_file"] = true
			n = d.get_next()
		d.list_dir_end()
	return out

# ------------------------------------------------------------------ smart playlists
# rule keys (all optional): stars_min, stars_max, played ("any" | "played" | "unplayed"),
# failed_days (a failed run in the last N days), added_days (file newer than N days),
# favorites, untagged, tag, sort ("stars" | "stars_desc" | "plays" | "last_played" | "added" |
# "name"), limit (0 = all)
const SMART_DEFAULTS = [
	{"name": "Unplayed 5-7 stars", "stars_min": 5.0, "stars_max": 7.0, "played": "unplayed", "sort": "stars"},
	{"name": "Failed in the last 7 days", "failed_days": 7, "sort": "last_played"},
	{"name": "Recently added", "added_days": 14, "sort": "added"},
	{"name": "Favorites", "favorites": true, "sort": "name"},
	{"name": "No tags", "untagged": true, "sort": "name"},
	{"name": "Most played", "played": "played", "sort": "plays", "limit": 50},
]

static func smart_lists() -> Array:
	if Engine.has_meta("rr_smart"): return Engine.get_meta("rr_smart")
	var d = _read(SMART_FILE)
	var out = []
	if d is Array:
		for r in d:
			if typeof(r) == TYPE_DICTIONARY and str(r.get("name", "")) != "": out.append(r)
	else: out = SMART_DEFAULTS.duplicate(true)
	Engine.set_meta("rr_smart", out)
	return out

static func save_smart():
	_write(SMART_FILE, smart_lists())
	Engine.remove_meta("rr_smart_ids")
	if Engine.get_main_loop(): Engine.get_main_loop().call_group("rr_collections", "_rr_collections_changed")

static func smart_rule(name:String):
	for r in smart_lists():
		if r.name == name: return r
	return null

# the maps a rule matches, sorted. ctx = {history, stars} so a panel can evaluate many rules with
# one read of the history; maps without a rating yet don't match a star range.
static func smart_eval(rule:Dictionary, ctx = null) -> Array:
	if ctx == null: ctx = smart_ctx()
	var hist:Dictionary = ctx.history
	var now = OS.get_unix_time()
	var out = []
	for s in local_maps():
		var h = hist.get(s.id, {})
		var played = h.get("plays", 0) > 0 or h.get("best_file", false)
		var st = _stars(ctx, s)
		if rule.has("stars_min") and (st < 0 or st < float(rule.stars_min)): continue
		if rule.has("stars_max") and (st < 0 or st > float(rule.stars_max)): continue
		var want = str(rule.get("played", "any"))
		if (want == "played" and !played) or (want == "unplayed" and played): continue
		if int(rule.get("failed_days", 0)) > 0:
			var since = now - int(rule.failed_days) * 86400
			var hit = false
			for t in h.get("fails", []):
				if t >= since: hit = true
			if !hit: continue
		if int(rule.get("added_days", 0)) > 0 and _mtime(ctx, s) < now - int(rule.added_days) * 86400: continue
		if rule.get("favorites", false) and !Rhythia.favorite_songs.has(s.id): continue
		if rule.get("untagged", false) and !tags_of(s.id).empty(): continue
		if str(rule.get("tag", "")) != "" and !tags_of(s.id).has(clean_tag(rule.tag)): continue
		out.append(s)
	var k = []
	for s in out: k.append([_sort_key(rule.get("sort", "name"), s, ctx), s.name.to_lower(), s])
	k.sort_custom(Sorter, "by_key")
	out = []
	for e in k: out.append(e[2])
	var lim = int(rule.get("limit", 0))
	if lim > 0 and out.size() > lim: out.resize(lim)
	return out

static func smart_ctx() -> Dictionary:
	var sc = null
	if ResourceLoader.exists("res://mods/stars/StarCache.gd") and Engine.get_main_loop():
		sc = load("res://mods/stars/StarCache.gd").get_instance(Engine.get_main_loop())
	return {"history": history(), "stars": sc, "mtimes": {}}

static func _stars(ctx:Dictionary, s) -> float:
	return ctx.stars.get_stars(s) if ctx.stars else -1.0

static func _mtime(ctx:Dictionary, s) -> int:
	if !ctx.mtimes.has(s.id): ctx.mtimes[s.id] = File.new().get_modified_time(s.filePath) if s.filePath != "" else 0
	return ctx.mtimes[s.id]

static func _sort_key(sort:String, s, ctx:Dictionary):
	var h = ctx.history.get(s.id, {})
	match sort:
		"stars": return _stars(ctx, s)
		"stars_desc": return -_stars(ctx, s)
		"plays": return -h.get("plays", 0)
		"last_played": return -h.get("last", 0)
		"added": return -_mtime(ctx, s)
	return 0

class Sorter:
	static func by_key(a, b):
		if a[0] != b[0]: return a[0] < b[0]
		return a[1] < b[1]
	static func by_t(a, b):
		return a.get("t", 0) > b.get("t", 0)

# {id: true} for the map list's collection filter (cached for 2 s: the list calls it per rebuild)
static func smart_ids(name:String) -> Dictionary:
	var cache = Engine.get_meta("rr_smart_ids") if Engine.has_meta("rr_smart_ids") else {}
	var c = cache.get(name)
	if c and OS.get_ticks_msec() - c[0] < 2000: return c[1]
	var ids = {}
	var r = smart_rule(name)
	if r:
		for s in smart_eval(r): ids[s.id] = true
	cache[name] = [OS.get_ticks_msec(), ids]
	Engine.set_meta("rr_smart_ids", cache)
	return ids

# ------------------------------------------------------------------ duplicates
# Exact = the same notes: a fingerprint of the notes themselves (time + position rounded to
# 1/1000), read straight from each .sspm v2's marker block, so two files written by different
# editors still match. Other formats fall back to the file's MD5. Possible = same normalised name
# and length within 2 s, different notes. Every .sspm in the maps folder is read, also files the
# library hides because another file has the same map id inside. Fingerprints are cached by file
# time + size (HASH_CACHE), so a second scan is quick. The reads run on a worker (DupScan).
const HASH_CACHE = "user://rr_library/cache/note_hashes.json"

class DupScan extends Reference:
	signal done(groups)
	var thread:Thread = Thread.new()
	var items:Array = []
	var progress:float = 0.0
	var cancelled:bool = false
	var known:Dictionary = {}   # path -> library entry (plain data)
	var paths:Array = []

	func start(maps:Array, threaded:bool = true):
		var seen = {}
		for s in maps: # plain data only crosses to the worker
			if s.filePath == "": continue
			var fp = ProjectSettings.globalize_path(s.filePath) # (the library mixes user:// and absolute paths)
			known[fp] = {"id": s.id, "name": s.name, "creator": s.creator, "len": int(s.last_ms), "notes": int(s.note_count), "in_library": true}
			paths.append(fp)
			seen[fp] = true
		var dir = ProjectSettings.globalize_path(Globals.p("user://maps"))
		var d = Directory.new()
		if d.open(dir) == OK:
			d.list_dir_begin(true, true)
			var n = d.get_next()
			while n != "":
				var p = dir + "/" + n
				if !d.current_is_dir() and n.get_extension().to_lower() == "sspm" and !seen.has(p): paths.append(p)
				n = d.get_next()
			d.list_dir_end()
		if threaded: thread.start(self, "_run")
		else: _run(null) # (tests: script errors show up on the main thread)

	func _run(_u):
		var Lib = load("res://mods/replay/Library.gd")
		var cache = Lib._read(Lib.HASH_CACHE)
		if typeof(cache) != TYPE_DICTIONARY: cache = {}
		var f = File.new()
		for i in paths.size():
			if cancelled: break
			var p = paths[i]
			var it = known.get(p, {"in_library": false}).duplicate()
			it.path = p
			it.size = 0
			if f.open(p, File.READ) == OK:
				it.size = f.get_len()
				var mt = f.get_modified_time(p)
				var c = cache.get(p)
				if c is Array and c.size() == 3 and int(c[0]) == mt and int(c[1]) == it.size: it.key = c[2]
				else:
					it.key = Lib.note_fingerprint(f)
					cache[p] = [mt, it.size, it.key]
				if !it.in_library: Lib.read_header(f, it)
				f.close()
				if it.key == "": it.key = "m" + f.get_md5(p)
			if !it.has("id"): it.id = p.get_file().get_basename()
			if !it.has("name"): it.name = it.id
			items.append(it)
			progress = float(i + 1) / max(1, paths.size())
		Lib._write(Lib.HASH_CACHE, cache)
		call_deferred("_finish")

	func _finish():
		if thread.is_active(): thread.wait_to_finish()
		emit_signal("done", group(items))

	# groups: [{kind: "exact" | "possible", ids: [..], items: [..]}]
	static func group(items:Array) -> Array:
		var Lib = load("res://mods/replay/Library.gd")
		var by_key = {}
		var by_name = {}
		for it in items:
			if it.get("key", "") != "": by_key[it.key] = by_key.get(it.key, []) + [it]
			var nk = Lib.norm(it.get("name", ""))
			if nk != "": by_name[nk] = by_name.get(nk, []) + [it]
		var out = []
		for k in by_key:
			if by_key[k].size() < 2: continue
			var ids = []
			for it in by_key[k]: ids.append(it.id)
			out.append({"kind": "exact", "ids": ids, "items": by_key[k]})
		for k in by_name:
			var g = by_name[k]
			if g.size() < 2: continue
			var used = {}
			for a in g.size(): # lengths within 2 s of each other, and not all the same notes
				if used.has(a): continue
				var part = [g[a]]
				for b in range(a + 1, g.size()):
					if !used.has(b) and abs(g[a].get("len", 0) - g[b].get("len", 0)) <= 2000:
						part.append(g[b])
						used[b] = true
				var keys = {}
				for it in part: keys[it.get("key", it.id)] = true
				if part.size() >= 2 and keys.size() >= 2:
					var ids = []
					for it in part: ids.append(it.id)
					out.append({"kind": "possible", "ids": ids, "items": part})
		return out

static func scan_duplicates(maps:Array = [], threaded:bool = true) -> DupScan:
	var j = DupScan.new()
	j.start(maps if !maps.empty() else local_maps(), threaded)
	return j

# The notes of an open .sspm v2 as "n" + MD5 of (ms, x * 1000, y * 1000) ints, or "" when the file
# isn't a v2 map with only ssp_note markers (the caller uses the file's MD5 then). Layout: the
# sspm v2 header (u64 offset / length pairs at 0x30: custom data, audio, cover, marker
# definitions, markers), definition = u16 name + u8 value count + value types + 0x00; a marker =
# u32 ms + u8 definition index + its values (type 7 = position: u8 quantum, then 2 f32 or 2 u8).
static func note_fingerprint(f:File) -> String:
	var n = f.get_len()
	if n < 0x80: return ""
	f.seek(0)
	if f.get_buffer(4).get_string_from_ascii() != "SS+m" or f.get_16() != 2: return ""
	f.seek(0x60)
	var md_off = f.get_64()
	var md_len = f.get_64()
	var m_off = f.get_64()
	var m_len = f.get_64()
	if md_off <= 0 or md_off + md_len > n or m_off <= 0 or m_off + m_len > n or m_len <= 0: return ""
	f.seek(md_off)
	var defs = f.get_8()
	var note_def = -1
	for i in defs:
		var name = f.get_buffer(f.get_16()).get_string_from_utf8()
		var vc = f.get_8()
		var types = f.get_buffer(vc)
		f.get_8() # (end of the definition)
		if name == "ssp_note" and vc == 1 and types[0] == 7: note_def = i
		elif defs > 1: return "" # (other marker kinds: their sizes aren't needed elsewhere, so not parsed here)
	if note_def < 0: return ""
	f.seek(m_off)
	var buf = f.get_buffer(m_len)
	var sp = StreamPeerBuffer.new()
	sp.data_array = buf
	sp.big_endian = false
	var outp = StreamPeerBuffer.new()
	var notes = []
	while sp.get_available_bytes() >= 7:
		var ms = sp.get_u32()
		if sp.get_u8() != note_def: return ""
		var x:float
		var y:float
		if sp.get_u8() != 0:
			if sp.get_available_bytes() < 8: break
			x = sp.get_float()
			y = sp.get_float()
		else:
			x = sp.get_u8()
			y = sp.get_u8()
		# one int per note: ms << 30 | x << 15 | y (positions in 1/1000, shifted to 0..32767). Sorting
		# an Array of Arrays crashes this engine build (tests/multiplayer/ThreadProbe.gd); ints sort fine.
		var xi = int(clamp(round(x * 1000.0) + 16384, 0, 32767))
		var yi = int(clamp(round(y * 1000.0) + 16384, 0, 32767))
		notes.append((ms << 30) | (xi << 15) | yi)
	notes.sort() # (same notes in another order are the same map)
	for e in notes: outp.put_64(e)
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(outp.data_array)
	return "n" + ctx.finish().hex_encode()

# id / name / mappers / last ms / note count from an open .sspm v2 header (files the library hides)
static func read_header(f:File, it:Dictionary):
	f.seek(0)
	if f.get_buffer(4).get_string_from_ascii() != "SS+m" or f.get_16() != 2: return
	f.seek(0x1e)
	it.len = f.get_32()
	it.notes = f.get_32()
	f.seek(0x80)
	it.id = f.get_buffer(f.get_16()).get_string_from_utf8()
	it.name = f.get_buffer(f.get_16()).get_string_from_utf8()
	f.get_buffer(f.get_16())
	var m = []
	for _i in f.get_16(): m.append(f.get_buffer(f.get_16()).get_string_from_utf8())
	it.creator = PoolStringArray(m).join(" & ")

# ------------------------------------------------------------------ bulk rename (display names)
# The map's FILE name is its id: personal bests, replays, favourites, collections, tags and play
# history are all keyed by it, so files are never renamed. What changes is the name stored inside
# the .sspm (what the list shows and searches), through the game's own Song.convert_to_sspm(true).
# Every apply writes a journal (old name + a copy of each file before the change) so it can be
# undone exactly.
const TOKENS = "{artist} {title} {name} {mapper} {difficulty} {stars} {id}"

static func render_name(tpl:String, s, ctx = null) -> String:
	var at = split_name(s.name)
	var st = _stars(ctx, s) if ctx else -1.0
	var diff = str(s.custom_data.get("difficulty_name", ""))
	if diff == "" and s.difficulty >= 0: diff = ["Easy", "Medium", "Hard", "Logic", "Tasukete"][clamp(s.difficulty, 0, 4)]
	var out = tpl
	for kv in [["{artist}", at[0]], ["{title}", at[1]], ["{name}", s.name], ["{mapper}", s.creator], ["{difficulty}", diff],
			["{stars}", ("%.2f" % st) if st >= 0 else "?"], ["{id}", s.id]]:
		out = out.replace(kv[0], kv[1])
	out = out.replace("[]", "").replace("()", "")
	while "  " in out: out = out.replace("  ", " ")
	out = out.strip_edges()
	while out.begins_with("-") or out.ends_with("-"): # (an empty {artist} leaves "- Title")
		out = out.trim_prefix("-").trim_suffix("-").strip_edges()
	return out

# [{song, old, new, status}] where status = "same" | "ok" | "collision" | "empty" | "builtin";
# collisions (two maps ending with one name, or a name another map already has) get " (2)" etc.
static func rename_plan(maps:Array, tpl:String) -> Array:
	var ctx = smart_ctx()
	var taken = {}
	var chosen = {}
	for s in local_maps(): taken[s.name.to_lower()] = s.id
	var plan = []
	for s in maps: taken.erase(s.name.to_lower()) # the renamed maps free their own names
	for s in maps:
		var nn = render_name(tpl, s, ctx)
		var e = {"song": s, "old": s.name, "new": nn, "status": "ok"}
		if s.is_builtin or (s.songType != Globals.MAP_SSPM2 and s.songType != Globals.MAP_SSPM): e.status = "builtin"
		elif nn == "": e.status = "empty"
		elif nn == s.name: e.status = "same"
		else:
			var base = nn
			var i = 2
			while taken.has(nn.to_lower()) or chosen.has(nn.to_lower()):
				nn = "%s (%d)" % [base, i]
				i += 1
			if nn != base: e.status = "collision"
			e.new = nn
		chosen[e.new.to_lower()] = true
		plan.append(e)
	return plan

# applies the ok / collision rows; returns {done, failed:[[id, error]], journal}
static func rename_apply(plan:Array) -> Dictionary:
	var jid = "%d" % OS.get_unix_time()
	var dir = Globals.p(JOURNAL_DIR) + "/" + jid
	var d = Directory.new()
	d.make_dir_recursive(dir)
	var journal = {"id": jid, "t": OS.get_unix_time(), "kind": "rename", "rows": []}
	var res = {"done": 0, "failed": [], "journal": jid}
	for e in plan:
		if !(e.status in ["ok", "collision"]): continue
		var s = e.song
		var backup = dir + "/" + s.id + ".sspm"
		if d.copy(s.filePath, backup) != OK:
			res.failed.append([s.id, "couldn't back the file up"])
			continue
		var r = _rewrite_name(s, e.new)
		if r != "":
			d.copy(backup, s.filePath) # (put the file back as it was)
			_reload(s.filePath)
			res.failed.append([s.id, r])
			continue
		journal.rows.append({"id": s.id, "path": s.filePath, "old": e.old, "new": e.new, "backup": backup})
		res.done += 1
	_write(JOURNAL_DIR.plus_file(jid + ".json"), journal)
	if res.done > 0 and Engine.get_main_loop(): Engine.get_main_loop().call_group("rr_collections", "_rr_collections_changed")
	return res

static func _rewrite_name(s, new_name:String) -> String:
	var old = s.name
	s.name = new_name
	s.read_notes()
	var r = str(s.convert_to_sspm(true))
	if r != "Converted!":
		s.name = old
		return r
	return "" if _reload(s.filePath) else "the rewritten map didn't load"

# re-reads one map file into the library (after a rewrite or an undo)
static func _reload(path:String) -> bool:
	var reg = Rhythia.registry_song
	var id = path.get_file().get_basename()
	reg.check_and_remove_id(id)
	return reg.add_sspm_map(path) != null

static func journals() -> Array: # newest first
	var out = []
	var d = Directory.new()
	if d.open(Globals.p(JOURNAL_DIR)) != OK: return out
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if n.ends_with(".json"):
			var j = _read(JOURNAL_DIR.plus_file(n))
			if typeof(j) == TYPE_DICTIONARY and !j.get("undone", false): out.append(j)
		n = d.get_next()
	d.list_dir_end()
	out.sort_custom(Sorter, "by_t")
	return out

# puts every file of one journal back from its copies; returns {restored, failed}
static func undo(jid:String) -> Dictionary:
	var path = JOURNAL_DIR.plus_file(jid + ".json")
	var j = _read(path)
	var res = {"restored": 0, "failed": []}
	if typeof(j) != TYPE_DICTIONARY: return {"restored": 0, "failed": [["", "no such journal"]]}
	var d = Directory.new()
	for row in j.rows:
		if !d.file_exists(row.backup):
			res.failed.append([row.id, "its backup copy is gone"])
			continue
		if d.copy(row.backup, row.path) != OK or !_reload(row.path):
			res.failed.append([row.id, "couldn't restore the file"])
			continue
		res.restored += 1
	j["undone"] = true
	_write(path, j)
	if res.failed.empty(): _remove_dir(Globals.p(JOURNAL_DIR) + "/" + jid)
	if Engine.get_main_loop(): Engine.get_main_loop().call_group("rr_collections", "_rr_collections_changed")
	return res

static func _remove_dir(p:String):
	var d = Directory.new()
	if d.open(p) != OK: return
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if !d.current_is_dir(): d.remove(p + "/" + n)
		n = d.get_next()
	d.list_dir_end()
	d.remove(p)

# ------------------------------------------------------------------ statistics + cleanup
static func dir_size(p:String, recurse:bool = true) -> Array: # [bytes, files]
	var d = Directory.new()
	var out = [0, 0]
	if d.open(p) != OK: return out
	var f = File.new()
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		var full = p + "/" + n
		if d.current_is_dir():
			if recurse:
				var r = dir_size(full)
				out[0] += r[0]
				out[1] += r[1]
		elif f.open(full, File.READ) == OK:
			out[0] += f.get_len()
			out[1] += 1
			f.close()
		n = d.get_next()
	d.list_dir_end()
	return out

static func stats() -> Dictionary:
	var maps = local_maps()
	var broken = []
	var no_audio = []
	for s in maps:
		if s.is_broken: broken.append(s)
		elif s.warning != "" and "music" in s.warning.to_lower(): no_audio.append(s)
	return {"maps": maps.size(), "broken": broken, "no_audio": no_audio,
		"maps_dir": dir_size(Globals.p("user://maps")), "replays": dir_size(Globals.p("user://replays")),
		"cache": dir_size(Globals.p("user://cache")), "tags": tags().size(), "smart": smart_lists().size()}

# things that are safe to remove: [{label, path, bytes, files, note}] - caches the game or the mod
# rebuilds by itself, leftovers of finished jobs, backups of undone edits. Maps, replays, scores,
# settings and skins are never listed.
static func cleanup_plan() -> Array:
	var out = []
	for e in [["Map browser cover thumbnails", "user://cache/rhythia_covers", "downloaded again when the browser shows them"],
			[".phxm import leftovers", "user://rr_phxm", "temporary audio from imports"],
			["Rhythia downloads in progress", "user://rhythia_dl", "unpacked .rhm downloads"],
			["Map editor backups", "user://editor/backup", "older versions of maps saved in the editor"],
			["Rename journal copies", JOURNAL_DIR, "lets you undo renames; removing them makes the renames permanent"],
			["Duplicate finder cache", HASH_CACHE.get_base_dir(), "note fingerprints; the next scan reads every map again"]]:
		var p = Globals.p(e[1])
		var r = dir_size(p)
		if r[1] > 0: out.append({"label": e[0], "path": p, "bytes": r[0], "files": r[1], "note": e[2]})
	return out

# moves one cleanup entry's folder contents to the recycle bin (desktop) or deletes it (Android has
# no bin; trash = false too); returns the number of files it could not remove
static func cleanup_apply(entry:Dictionary, trash:bool = true) -> int:
	var failed = 0
	var files = []
	_list_files(entry.path, files)
	for f in files:
		var ok = OS.move_to_trash(ProjectSettings.globalize_path(f)) == OK if trash and OS.has_feature("pc") else Directory.new().remove(f) == OK
		if !ok: failed += 1
	return failed

static func _list_files(p:String, out:Array):
	var d = Directory.new()
	if d.open(p) != OK: return
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if d.current_is_dir(): _list_files(p + "/" + n, out)
		else: out.append(p + "/" + n)
		n = d.get_next()
	d.list_dir_end()

static func human_bytes(b:int) -> String:
	if b >= 1 << 30: return "%.2f GB" % (b / float(1 << 30))
	if b >= 1 << 20: return "%.1f MB" % (b / float(1 << 20))
	if b >= 1 << 10: return "%.0f KB" % (b / 1024.0)
	return "%d B" % b
