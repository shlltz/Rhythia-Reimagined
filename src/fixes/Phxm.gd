extends Reference
# .phxm maps (Rhythia-reimagined): the Rhythia rewrite's map format (Rhythia/Client MapParser.cs).
# A zip of metadata.json, objects.phxmo (notes), audio.<ext>, cover.png and maybe video.mp4; the
# rewrite also keeps every map unpacked as a folder of those files. Both are converted to the
# game's .sspm (Song.convert_to_sspm). Only the needed zip entries are read (the video can be big).
# Godot 3 has no zip reader: deflated entries are inflated as gzip streams built from the entry's
# own CRC and size (as MapBrowser does for .rhm).
#
# Export (export()): any map back to a .phxm the rewrite opens (same entries, metadata keys and
# note encoding as its MapParser.ExportEncode). What a .sspm can't hold is kept per song id in
# EXTRA at import - the objects.phxmo tail after the notes, rating, artist link / platform, the
# artist / title split, the mapper list - and written back on export, so a map survives a round
# trip. The tail is 11 sections (timing points, brightness, contrast, saturation, blur, fov, tint,
# position, rotation, ar factor, text: the rewrite's writer comments); both the rewrite and the
# Quantum Editor write them all empty and the rewrite never reads them, so this game can't play
# them either: they are only counted (effect_report) and carried along.

const TMP = "user://rr_phxm"
const EXTRA = "user://rr_phxm_extra"
const EXPORT_DIR = "user://exports"
const VERSION = 12
const DIFFS = ["N/A", "Easy", "Medium", "Hard", "Insane", "Illogical"] # rewrite names for .sspm difficulty 0..5
const SECTIONS = ["timing points", "brightness", "contrast", "saturation", "blur", "fov", "tint", "position", "rotation", "ar factor", "text"]
# bytes per object after its u32 time, from the Quantum Editor's reader (the only one that reads
# any): -1 = no known layout (timing points), -2 = text (u32 + u16-prefixed string + u8)
const SECTION_SIZE = [-1, 10, 10, 10, 10, 10, 9, 18, 10, 4, -2]

# a .phxm file, or a rewrite map folder (one with objects.phxmo)
static func is_map(path:String) -> bool:
	if path.get_extension().to_lower() == "phxm": return true
	return File.new().file_exists(path.plus_file("objects.phxmo"))

# Converts the map to user://maps/<id>.sspm and adds it to the library. Returns the Song (also when
# the map was already there) or an error String.
static func import(path:String, sid:String = ""):
	var s = load_song(path, sid)
	if s is String: return s
	var reg = Rhythia.registry_song
	var have = reg.get_item(s.id)
	if have and !have.is_online:
		_clear_tmp()
		return have
	var r = s.convert_to_sspm()
	_clear_tmp()
	if str(r) != "Converted!": return str(r)
	reg.check_and_remove_id(s.id)
	var added = reg.add_sspm_map(Globals.p("user://maps/%s.sspm") % s.id)
	if added == null: return "the converted map didn't load"
	return added

# A Song set up from the map, not saved yet (the import screen edits it first): notes, cover, and
# the audio copied to `tmp`, where convert_to_sspm reads it. Returns the Song or an error String.
# tex = false (worker threads): the cover stays a plain Image (Song.rr_cover_image) - no GPU texture.
static func load_song(path:String, sid:String = "", tex:bool = true, tmp:String = TMP):
	var files = _read_dir(path) if Directory.new().dir_exists(path) else _read_zip(path)
	if files is String: return files
	if !files.has("metadata.json") or !files.has("objects.phxmo"): return "not a .phxm map (no metadata.json / objects.phxmo)"
	var meta = parse_json(files["metadata.json"].get_string_from_utf8())
	if typeof(meta) != TYPE_DICTIONARY: return "unreadable metadata.json"
	var objs = parse_objects(files["objects.phxmo"])
	var data = objs.data
	if data == "": return "the map has no notes"
	var audio = PoolByteArray()
	for k in files:
		if k.begins_with("audio."): audio = files[k]
	if audio.size() == 0: return "the map has no audio"
	var fmt = Globals.audioLoader.get_format(audio)
	if fmt != "mp3" and fmt != "ogg": return "unsupported audio (only mp3 and ogg play here)"

	if sid == "": sid = _id(meta, path, files["objects.phxmo"])
	_clear_tmp(tmp)
	var d = Directory.new()
	d.make_dir_recursive(Globals.p(tmp))
	var music = Globals.p(tmp) + "/%s.%s" % [sid, fmt]
	var f = File.new()
	if f.open(music, File.WRITE) != OK: return "can't write the audio to " + music
	f.store_buffer(audio)
	f.close()

	var artist = str(meta.get("Artist", "")).strip_edges()
	var title = str(meta.get("Title", "")).strip_edges()
	if title == "": title = path.get_file().get_basename()
	var mappers = meta.get("Mappers")
	var creator = PoolStringArray(mappers).join(", ") if mappers is Array and !mappers.empty() else "Unknown"
	var s = Song.new(sid, ("%s - %s" % [artist, title]) if artist != "" else title, creator)
	s.song = s.name
	s.setup_from_data(sid + data, music)
	var diff = int(clamp(int(meta.get("Difficulty", 0)), 0, 5))
	s.difficulty = diff - 1
	var dn = str(meta.get("DifficultyName", "")).strip_edges()
	if dn != "" and dn != DIFFS[diff]: s.custom_data["difficulty_name"] = dn # (the default names are the game's own)
	for k in files:
		if k.begins_with("cover."):
			var img = _image(files[k])
			if img and !tex:
				s.rr_cover_image = img
				s.has_cover = true
			elif img:
				var t = ImageTexture.new()
				t.create_from_image(img)
				s.cover = t
				s.has_cover = true
	var extra = {"version": objs.version, "tail": Marshalls.raw_to_base64(objs.tail), "name": s.name, "creator": creator,
		"Artist": artist, "Title": title, "Mappers": mappers if mappers is Array else [], "Rating": meta.get("Rating", 0),
		"ArtistLink": str(meta.get("ArtistLink", "")), "ArtistPlatform": str(meta.get("ArtistPlatform", "")),
		"DifficultyName": dn, "HasVideo": bool(meta.get("HasVideo", false))}
	s.set_meta("rr_phxm_extra", extra)
	save_extra(sid, extra)
	return s

# objects.phxmo: u32 version (12), u32 note count, then per note u32 ms, u8 quantum, and x, y as two
# f32 (quantum) or two u8 (grid: 0..2), then the effect sections (kept as raw bytes: `tail`).
# Rewrite x, y = .sspm x - 1, 1 - y; written in the game's text format (2 - x, 2 - y), so
# txt x = 1 - X, txt y = 1 + Y. Returns {data, version, tail, notes}.
static func parse_objects(b:PoolByteArray) -> Dictionary:
	var out = {"data": "", "version": VERSION, "tail": PoolByteArray(), "notes": 0}
	if b.size() < 8: return out
	var sp = StreamPeerBuffer.new()
	sp.data_array = b
	sp.big_endian = false
	out.version = sp.get_u32()
	var count = sp.get_u32()
	var parts = PoolStringArray()
	for _i in count:
		if sp.get_available_bytes() < 7: break
		var ms = sp.get_u32()
		var x:float
		var y:float
		if sp.get_u8() != 0:
			if sp.get_available_bytes() < 8: break
			x = sp.get_float()
			y = sp.get_float()
		else:
			if sp.get_available_bytes() < 2: break
			x = sp.get_u8() - 1
			y = sp.get_u8() - 1
		parts.append("%s|%s|%d" % [str(1.0 - x), str(1.0 + y), ms])
	out.notes = parts.size()
	if sp.get_position() < b.size(): out.tail = b.subarray(sp.get_position(), b.size() - 1)
	out.data = ("," + parts.join(",")) if parts.size() > 0 else ""
	return out

# what the effect sections hold: {section name: count}; "unknown" = a non-empty section without a
# known layout, after which the rest can't be counted (the bytes are still kept for export)
static func effect_report(tail:PoolByteArray) -> Dictionary:
	var out = {}
	var sp = StreamPeerBuffer.new()
	sp.data_array = tail
	sp.big_endian = false
	for i in SECTIONS.size():
		if sp.get_available_bytes() < 4: break
		var n = sp.get_32()
		if n == 0: continue
		out[SECTIONS[i]] = n
		var sz = SECTION_SIZE[i]
		if sz == -1 or n < 0:
			out["unknown"] = true
			break
		for _j in n:
			if sz == -2:
				if sp.get_available_bytes() < 10: break
				sp.get_u32()
				sp.get_u32()
				var ln = sp.get_u16()
				sp.seek(sp.get_position() + ln + 1)
			else: sp.seek(sp.get_position() + 4 + sz)
	return out

static func effects_text(tail:PoolByteArray) -> String:
	var r = effect_report(tail)
	var parts = PoolStringArray()
	for k in r:
		if k != "unknown": parts.append("%d %s" % [r[k], k])
	if r.has("unknown"): parts.append("more of unknown layout")
	return parts.join(", ")

# ------------------------------------------------------------------ round-trip data
static func extra_path(sid:String) -> String:
	return Globals.p(EXTRA) + "/" + sid + ".json"

static func save_extra(sid:String, extra:Dictionary):
	Directory.new().make_dir_recursive(Globals.p(EXTRA))
	var f = File.new()
	if f.open(extra_path(sid), File.WRITE) == OK:
		f.store_string(to_json(extra))
		f.close()

static func load_extra(sid:String) -> Dictionary:
	var f = File.new()
	if !f.file_exists(extra_path(sid)) or f.open(extra_path(sid), File.READ) != OK: return {}
	var r = parse_json(f.get_as_text())
	f.close()
	return r if typeof(r) == TYPE_DICTIONARY else {}

# ------------------------------------------------------------------ export
# The map as a .phxm (default: EXPORT_DIR/<id>.phxm). Returns {path, notes, warnings} or an error
# String. Notes: rewrite X = x - 1, Y = 1 - y; the grid byte form only for whole numbers in -1..1
# (the rewrite's own rule), floats otherwise.
static func export(s, out_path:String = ""):
	if s == null: return "no map"
	var notes = s.read_notes()
	if notes.empty(): return "the map has no notes"
	var audio = s.get_music_buffer()
	if !(audio is PoolByteArray) or audio.size() == 0: return "the map has no audio"
	var ext = Globals.audioLoader.get_format(audio)
	if ext != "mp3" and ext != "ogg": return "its audio (%s) can't go into a .phxm (mp3 / ogg only)" % ext
	var warn = []
	var x = load_extra(s.id)
	var artist = ""
	var title = s.name
	if x.get("name", "") == s.name: # (renamed since the import: the new name is split instead)
		artist = str(x.get("Artist", ""))
		title = str(x.get("Title", s.name))
	elif " - " in s.name:
		artist = s.name.split(" - ", true, 1)[0].strip_edges()
		title = s.name.split(" - ", true, 1)[1].strip_edges()
	var mappers = []
	if x.get("Mappers") is Array and !x.Mappers.empty(): # (the .sspm joins mappers with " & ")
		var was = PoolStringArray(x.Mappers)
		if s.creator == x.get("creator", "") or s.creator == was.join(" & ") or s.creator == was.join(", "): mappers = x.Mappers
	if mappers.empty():
		for mp in s.creator.replace(" & ", ",").split(","):
			if mp.strip_edges() != "": mappers.append(mp.strip_edges())
	var diff = int(clamp(s.difficulty + 1, 0, 5))
	var dname = str(s.custom_data.get("difficulty_name", ""))
	if dname == "": dname = DIFFS[diff]
	var last = 0
	for n in notes: last = max(last, int(n[2]))
	var cover = _cover_png(s)
	if s.has_cover and cover.size() == 0: warn.append("the cover couldn't be read: exported without it")
	if x.get("HasVideo", false): warn.append("the original .phxm had a video: it isn't imported, so it isn't exported")
	var meta = {"ID": s.id, "Artist": artist, "ArtistLink": str(x.get("ArtistLink", "")), "ArtistPlatform": str(x.get("ArtistPlatform", "")),
		"Title": title, "Rating": x.get("Rating", 0), "Mappers": mappers, "Difficulty": diff, "DifficultyName": dname,
		"Length": last, "HasAudio": true, "HasCover": cover.size() > 0, "HasVideo": false, "AudioExt": ext}
	var tail = Marshalls.base64_to_raw(x.tail) if x.get("tail", "") != "" else PoolByteArray()
	if tail.size() == 0:
		for _i in SECTIONS.size(): tail.append_array(_le32(0))
	elif effects_text(tail) != "": warn.append("kept effects this game can't play: " + effects_text(tail))
	var objs = encode_objects(notes, int(x.get("version", VERSION)), tail)
	var entries = [["metadata.json", JSON.print(meta, "\t").to_utf8(), true], ["objects.phxmo", objs, true], ["audio." + ext, audio, false]]
	if cover.size() > 0: entries.append(["cover.png", cover, false])
	if out_path == "":
		Directory.new().make_dir_recursive(Globals.p(EXPORT_DIR))
		out_path = Globals.p(EXPORT_DIR) + "/" + s.id + ".phxm"
	var err = write_zip(out_path, entries)
	if err != "": return err
	return {"path": out_path, "notes": notes.size(), "warnings": warn}

# map page / editor "Export as .phxm": export, then say where it went (desktop: can open the folder)
static func export_prompt(s):
	var r = export(s)
	var txt = ""
	var opts = [{text = "OK"}]
	if r is String: txt = "Couldn't export the map: " + r
	else:
		txt = "Saved %d notes to\n%s\n\nOpen or drag it into the Rhythia rewrite." % [r.notes, r.path]
		for w in r.warnings: txt += "\n- " + w
		if OS.has_feature("pc"): opts.append({text = "Open folder"})
	Globals.confirm_prompt.open(txt, "Export .phxm", opts)
	var pick = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	if pick == 1 and r is Dictionary: OS.shell_open(r.path.get_base_dir())

# notes ([x, y, ms], .sspm space) -> objects.phxmo bytes
static func encode_objects(notes:Array, version:int, tail:PoolByteArray) -> PoolByteArray:
	var sorted = notes.duplicate()
	sorted.sort_custom(Sorter, "by_ms")
	var sp = StreamPeerBuffer.new()
	sp.big_endian = false
	sp.put_u32(version)
	sp.put_u32(sorted.size())
	for n in sorted:
		var X = float(n[0]) - 1.0
		var Y = 1.0 - float(n[1])
		var quantum = X != round(X) or Y != round(Y) or X < -1 or X > 1 or Y < -1 or Y > 1
		sp.put_u32(int(max(0, n[2])))
		sp.put_u8(1 if quantum else 0)
		if quantum:
			sp.put_float(X)
			sp.put_float(Y)
		else:
			sp.put_u8(int(round(X)) + 1)
			sp.put_u8(int(round(Y)) + 1)
	var out = sp.data_array
	out.append_array(tail)
	return out

class Sorter:
	static func by_ms(a, b):
		return a[2] < b[2]

# the cover as PNG bytes (the rewrite only reads cover.png): a stored PNG as it is, anything else
# re-encoded
static func _cover_png(s) -> PoolByteArray:
	if !s.has_cover: return PoolByteArray()
	if s.songType == Globals.MAP_SSPM2 and s.cover_offset > 0 and s.cover_length > 8:
		var f = File.new()
		if f.open(s.filePath, File.READ) == OK:
			f.seek(s.cover_offset)
			var b = f.get_buffer(s.cover_length)
			f.close()
			if b.size() > 8 and b[0] == 0x89 and b[1] == 0x50: return b
	var img = null
	if s.songType == Globals.MAP_SSPM or s.songType == Globals.MAP_SSPM2: img = s._cover_image()
	if !(img is Image) and s.cover is Texture: img = s.cover.get_data()
	if !(img is Image) or img.is_empty(): return PoolByteArray()
	return img.save_png_to_buffer()

# a zip of [name, bytes, try deflate] entries, written to path.tmp and moved into place. The CRC-32
# comes from a gzip of the entry (its trailer holds it); its deflate body is used when smaller.
static func write_zip(path:String, entries:Array) -> String:
	var f = File.new()
	if f.open(path + ".tmp", File.WRITE) != OK: return "can't write " + path
	var dt = OS.get_datetime()
	var dtime = (dt.hour << 11) | (dt.minute << 5) | int(dt.second / 2)
	var ddate = ((int(max(dt.year, 1980)) - 1980) << 9) | (dt.month << 5) | dt.day
	var cd = StreamPeerBuffer.new()
	cd.big_endian = false
	for e in entries:
		var name:PoolByteArray = str(e[0]).to_utf8()
		var raw:PoolByteArray = e[1]
		var crc = 0
		var data = raw
		var method = 0
		if raw.size() > 0:
			var gz = raw.compress(File.COMPRESSION_GZIP)
			if gz.size() < 18 or gz[0] != 0x1f or gz[1] != 0x8b:
				f.close()
				Directory.new().remove(path + ".tmp")
				return "couldn't checksum " + str(e[0])
			crc = _u32(gz, gz.size() - 8)
			if e[2] and gz[3] == 0 and gz.size() - 18 < raw.size():
				data = gz.subarray(10, gz.size() - 9)
				method = 8
		var at = f.get_position()
		for v in [[0x04034b50, 4], [20, 2], [0x0800, 2], [method, 2], [dtime, 2], [ddate, 2], [crc, 4], [data.size(), 4], [raw.size(), 4], [name.size(), 2], [0, 2]]:
			if v[1] == 4: f.store_32(v[0])
			else: f.store_16(v[0])
		f.store_buffer(name)
		f.store_buffer(data)
		for v in [[0x02014b50, 4], [20, 2], [20, 2], [0x0800, 2], [method, 2], [dtime, 2], [ddate, 2], [crc, 4], [data.size(), 4], [raw.size(), 4], [name.size(), 2], [0, 2], [0, 2], [0, 2], [0, 2], [0, 4], [at, 4]]:
			if v[1] == 4: cd.put_u32(v[0])
			else: cd.put_u16(v[0])
		cd.put_data(name)
	var cd_at = f.get_position()
	var cdb = cd.data_array
	f.store_buffer(cdb)
	for v in [[0x06054b50, 4], [0, 2], [0, 2], [entries.size(), 2], [entries.size(), 2], [cdb.size(), 4], [cd_at, 4], [0, 2]]:
		if v[1] == 4: f.store_32(v[0])
		else: f.store_16(v[0])
	var bad = f.get_error() != OK
	f.close()
	var d = Directory.new()
	if bad:
		d.remove(path + ".tmp")
		return "write failed: " + path
	if d.file_exists(path): d.remove(path)
	if d.rename(path + ".tmp", path) != OK: return "couldn't move the file into place: " + path
	return ""

# the song id: the map's own ID (often the .sspm id it came from, so a map imported both ways
# isn't added twice), cleaned to what Song.is_valid_id accepts
static func _id(meta:Dictionary, path:String, objects:PoolByteArray) -> String:
	var raw = str(meta.get("ID", "")).strip_edges()
	if raw == "": raw = path.get_file().get_basename()
	var out = ""
	for c in raw.to_lower():
		out += c if "0123456789abcdefghijklmnopqrstuvwxyz_-".find(c) != -1 else "_"
	while out.begins_with("_"): out = out.substr(1)
	if out.replace("_", "").length() < 3: out = "phxm_" + Marshalls.raw_to_base64(objects).md5_text().substr(0, 12)
	return out.substr(0, 100)

static func _wanted(name:String, only:Array = []) -> bool:
	if !only.empty(): return only.has(name)
	return name == "metadata.json" or name == "objects.phxmo" or name.begins_with("audio.") or name.begins_with("cover.")

# just metadata.json + objects.phxmo (previews: no audio / cover read); {meta, notes, last} or a String
static func peek(path:String):
	var only = ["metadata.json", "objects.phxmo"]
	var files = _read_dir(path, only) if Directory.new().dir_exists(path) else _read_zip(path, only)
	if files is String: return files
	if !files.has("metadata.json") or !files.has("objects.phxmo"): return "not a .phxm map"
	var meta = parse_json(files["metadata.json"].get_string_from_utf8())
	if typeof(meta) != TYPE_DICTIONARY: return "unreadable metadata.json"
	var o = files["objects.phxmo"]
	var n = _u32(o, 4) if o.size() >= 8 else 0
	return {"meta": meta, "notes": n, "id": _id(meta, path, o), "length": int(meta.get("Length", 0))}

static func _read_dir(path:String, only:Array = []) -> Dictionary:
	var out = {}
	var d = Directory.new()
	if d.open(path) != OK: return out
	var f = File.new()
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if !d.current_is_dir() and _wanted(n.to_lower(), only) and f.open(path.plus_file(n), File.READ) == OK:
			out[n.to_lower()] = f.get_buffer(f.get_len())
			f.close()
		n = d.get_next()
	d.list_dir_end()
	return out

static func _u16(b:PoolByteArray, i:int) -> int:
	return b[i] | (b[i + 1] << 8)

static func _u32(b:PoolByteArray, i:int) -> int:
	return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)

static func _le32(v:int) -> PoolByteArray:
	return PoolByteArray([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255])

# the wanted entries of the zip ({lower-case file name: bytes}, folders inside the zip ignored)
# or an error String
static func _read_zip(path:String, only:Array = []):
	var f = File.new()
	if f.open(path, File.READ) != OK: return "can't open " + path.get_file()
	var n = f.get_len()
	var tail = int(min(n, 65557))
	f.seek(n - tail)
	var b = f.get_buffer(tail)
	var eocd = -1
	var i = tail - 22
	while i >= 0:
		if b[i] == 0x50 and b[i + 1] == 0x4b and b[i + 2] == 5 and b[i + 3] == 6:
			eocd = i
			break
		i -= 1
	if eocd < 0: return "not a .phxm (zip) file"
	var count = _u16(b, eocd + 10)
	var cd_len = _u32(b, eocd + 12)
	var cd_at = _u32(b, eocd + 16)
	if cd_at + cd_len > n: return "broken zip directory"
	f.seek(cd_at)
	var c = f.get_buffer(cd_len)
	var p = 0
	var out = {}
	for _e in count:
		if p + 46 > c.size() or _u32(c, p) != 0x02014b50: return "broken zip directory"
		var method = _u16(c, p + 10)
		var crc = _u32(c, p + 16)
		var csize = _u32(c, p + 20)
		var usize = _u32(c, p + 24)
		var nlen = _u16(c, p + 28)
		var loc = _u32(c, p + 42)
		var name = c.subarray(p + 46, p + 45 + nlen).get_string_from_utf8().get_file().to_lower() if nlen > 0 else ""
		p += 46 + nlen + _u16(c, p + 30) + _u16(c, p + 32)
		if !_wanted(name, only) or out.has(name): continue
		f.seek(loc)
		var h = f.get_buffer(30)
		if h.size() < 30 or _u32(h, 0) != 0x04034b50: return "broken zip entry " + name
		f.seek(loc + 30 + _u16(h, 26) + _u16(h, 28))
		var data = f.get_buffer(csize) if csize > 0 else PoolByteArray()
		if data.size() != csize: return "truncated zip"
		if method == 8:
			var gz = PoolByteArray([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff])
			gz.append_array(data)
			gz.append_array(_le32(crc))
			gz.append_array(_le32(usize))
			data = gz.decompress(usize, File.COMPRESSION_GZIP) if usize > 0 else PoolByteArray()
			if data.size() != usize: return "couldn't inflate " + name
		elif method != 0: return "unsupported zip compression %d" % method
		out[name] = data
	f.close()
	return out

static func _image(buf:PoolByteArray):
	if buf.size() < 12: return null
	var img = Image.new()
	var err = ERR_FILE_UNRECOGNIZED
	if buf[0] == 0x89 and buf[1] == 0x50: err = img.load_png_from_buffer(buf)
	elif buf[0] == 0xFF and buf[1] == 0xD8: err = img.load_jpg_from_buffer(buf)
	elif buf[8] == 0x57 and buf[9] == 0x45: err = img.load_webp_from_buffer(buf)
	return img if err == OK else null

static func _clear_tmp(tmp:String = TMP):
	var d = Directory.new()
	var dir = Globals.p(tmp)
	if d.open(dir) != OK: return
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if !d.current_is_dir(): d.remove(dir + "/" + n)
		n = d.get_next()
	d.list_dir_end()
