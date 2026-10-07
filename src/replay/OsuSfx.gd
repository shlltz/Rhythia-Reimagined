extends Node
# Loads osu!-skin sounds / images shipped by the osuskin mod (raw files in res://mods/osuskin/)
# and plays sounds through a small player pool. One instance lives on the root ("OsuSfx").
# Everything is optional: without the osuskin mod, sounds are silent and textures null.

const DIR = "res://mods/osuskin/"
const VOICES = 8

var streams:Dictionary = {}   # file -> AudioStream (null = missing)
var players:Array = []
var next_player:int = 0

static func inst(tree:SceneTree) -> Node:
	var n = tree.root.get_node_or_null("OsuSfx")
	if !n:
		n = load("res://mods/replay/OsuSfx.gd").new()
		n.name = "OsuSfx"
		tree.root.add_child(n)
	return n

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	var bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
	for i in VOICES:
		var p = AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		players.append(p)

const MASTER_DB = -12.0 # all modded menu sounds (quieter than the stock ones)

func play(file:String, db:float = -6.0):
	var s = stream(file)
	if !s: return
	var p:AudioStreamPlayer = players[next_player]
	next_player = (next_player + 1) % VOICES
	p.stream = s
	p.volume_db = db + MASTER_DB
	p.play()

func stream(file:String):
	if streams.has(file): return streams[file]
	var b = _bytes(file)
	var s = null
	if b:
		match file.get_extension():
			"ogg":
				s = AudioStreamOGGVorbis.new()
				s.data = b
			"mp3":
				s = AudioStreamMP3.new()
				s.data = b
			"wav": s = _wav(b)
	streams[file] = s
	return s

static func texture(file:String, mipmaps:bool = false):
	var b = _bytes(file)
	if !b: return null
	var img = Image.new()
	var err = img.load_png_from_buffer(b) if file.get_extension() == "png" else img.load_jpg_from_buffer(b)
	if err != OK: return null
	var t = ImageTexture.new()
	t.create_from_image(img, Texture.FLAG_FILTER | (Texture.FLAG_MIPMAPS if mipmaps else 0))
	return t

static func _bytes(file:String):
	var f = File.new()
	if !f.file_exists(DIR + file) or f.open(DIR + file, File.READ) != OK: return null
	var b = f.get_buffer(f.get_len())
	f.close()
	return b

# PCM .wav (8/16 bit, mono/stereo) -> AudioStreamSample
static func _wav(b:PoolByteArray):
	if b.size() < 44 or b.subarray(0, 3).get_string_from_ascii() != "RIFF": return null
	var p = 12
	var channels = 2
	var rate = 44100
	var bits = 16
	while p + 8 <= b.size():
		var id = b.subarray(p, p + 3).get_string_from_ascii()
		var size = b[p + 4] | (b[p + 5] << 8) | (b[p + 6] << 16) | (b[p + 7] << 24)
		if id == "fmt ":
			if (b[p + 8] | (b[p + 9] << 8)) != 1: return null # not PCM
			channels = b[p + 10] | (b[p + 11] << 8)
			rate = b[p + 12] | (b[p + 13] << 8) | (b[p + 14] << 16) | (b[p + 15] << 24)
			bits = b[p + 22] | (b[p + 23] << 8)
		elif id == "data":
			var s = AudioStreamSample.new()
			s.format = AudioStreamSample.FORMAT_16_BITS if bits == 16 else AudioStreamSample.FORMAT_8_BITS
			s.stereo = channels == 2
			s.mix_rate = rate
			var d = b.subarray(p + 8, min(p + 8 + size, b.size()) - 1)
			if bits == 8: # Godot wants signed 8-bit
				for i in d.size(): d[i] = (d[i] + 128) & 0xFF
			s.data = d
			return s
		p += 8 + size + (size & 1)
	return null
