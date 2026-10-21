extends Reference
# .phxm maps (Rhythia-reimagined): the Rhythia rewrite's map format (Rhythia/Client MapParser.cs).
# A zip of metadata.json, objects.phxmo (notes), audio.<ext>, cover.png and maybe video.mp4; the
# rewrite also keeps every map unpacked as a folder of those files. Both are converted to the
# game's .sspm (Song.convert_to_sspm). Only the needed zip entries are read (the video can be big).
# Godot 3 has no zip reader: deflated entries are inflated as gzip streams built from the entry's
# own CRC and size (as MapBrowser does for .rhm).

const TMP = "user://rr_phxm"
const DIFFS = ["N/A", "Easy", "Medium", "Hard", "Insane", "Illogical"] # rewrite names for .sspm difficulty 0..5

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
# the audio copied to TMP, where convert_to_sspm reads it. Returns the Song or an error String.
static func load_song(path:String, sid:String = ""):
	var files = _read_dir(path) if Directory.new().dir_exists(path) else _read_zip(path)
	if files is String: return files
	if !files.has("metadata.json") or !files.has("objects.phxmo"): return "not a .phxm map (no metadata.json / objects.phxmo)"
	var meta = parse_json(files["metadata.json"].get_string_from_utf8())
	if typeof(meta) != TYPE_DICTIONARY: return "unreadable metadata.json"
	var data = _note_data(files["objects.phxmo"])
	if data == "": return "the map has no notes"
	var audio = PoolByteArray()
	for k in files:
		if k.begins_with("audio."): audio = files[k]
	if audio.size() == 0: return "the map has no audio"
	var fmt = Globals.audioLoader.get_format(audio)
	if fmt != "mp3" and fmt != "ogg": return "unsupported audio (only mp3 and ogg play here)"

	if sid == "": sid = _id(meta, path, files["objects.phxmo"])
	_clear_tmp()
	var d = Directory.new()
	d.make_dir_recursive(Globals.p(TMP))
	var music = Globals.p(TMP) + "/%s.%s" % [sid, fmt]
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
			if img:
				var t = ImageTexture.new()
				t.create_from_image(img)
				s.cover = t
				s.has_cover = true
	return s

# objects.phxmo: u32 (12), u32 note count, then per note u32 ms, u8 quantum, and x, y as two f32
# (quantum) or two u8 (grid: 0..2); the timing/effect lists after the notes aren't used here.
# Rewrite x, y = .sspm x - 1, 1 - y; written in the game's text format (2 - x, 2 - y), so
# txt x = 1 - X, txt y = 1 + Y.
static func _note_data(b:PoolByteArray) -> String:
	if b.size() < 8: return ""
	var sp = StreamPeerBuffer.new()
	sp.data_array = b
	sp.big_endian = false
	sp.get_u32()
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
	return ("," + parts.join(",")) if parts.size() > 0 else ""

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

static func _wanted(name:String) -> bool:
	return name == "metadata.json" or name == "objects.phxmo" or name.begins_with("audio.") or name.begins_with("cover.")

static func _read_dir(path:String) -> Dictionary:
	var out = {}
	var d = Directory.new()
	if d.open(path) != OK: return out
	var f = File.new()
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if !d.current_is_dir() and _wanted(n.to_lower()) and f.open(path.plus_file(n), File.READ) == OK:
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
static func _read_zip(path:String):
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
		if !_wanted(name) or out.has(name): continue
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

static func _clear_tmp():
	var d = Directory.new()
	var dir = Globals.p(TMP)
	if d.open(dir) != OK: return
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if !d.current_is_dir(): d.remove(dir + "/" + n)
		n = d.get_next()
	d.list_dir_end()
