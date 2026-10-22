extends Reference
# Minimal animated GIF writer (Rhythia-reimagined Replay Studio clips): GIF89a, looping, one global
# palette (a 6 x 7 x 6 colour cube; the last 4 entries unused), every frame full size, LZW. Pure
# GDScript so it works on every platform the game runs on; about a microsecond per pixel - run it
# on a worker thread. begin() -> add_frame() per frame (RGB8 bytes, w x h x 3) -> finish().

const RL = 6
const GL = 7
const BL = 6

var w:int = 0
var h:int = 0
var delay_cs:int = 5
var out:StreamPeerBuffer
var _lut_r = PoolIntArray()
var _lut_g = PoolIntArray()
var _lut_b = PoolIntArray()

func begin(width:int, height:int, delay_hundredths:int):
	w = width
	h = height
	delay_cs = delay_hundredths
	out = StreamPeerBuffer.new()
	out.big_endian = false
	out.put_data("GIF89a".to_ascii())
	out.put_u16(w)
	out.put_u16(h)
	out.put_u8(0xF7) # global colour table, 8 bits per channel, 256 entries
	out.put_u8(0)
	out.put_u8(0)
	for i in 256:
		var c = palette_color(i)
		out.put_u8(c[0])
		out.put_u8(c[1])
		out.put_u8(c[2])
	out.put_u8(0x21) # NETSCAPE2.0: loop forever
	out.put_u8(0xFF)
	out.put_u8(11)
	out.put_data("NETSCAPE2.0".to_ascii())
	out.put_u8(3)
	out.put_u8(1)
	out.put_u16(0)
	out.put_u8(0)
	_lut_r.resize(256)
	_lut_g.resize(256)
	_lut_b.resize(256)
	for v in 256:
		_lut_r[v] = int(round(v * (RL - 1) / 255.0)) * GL * BL
		_lut_g[v] = int(round(v * (GL - 1) / 255.0)) * BL
		_lut_b[v] = int(round(v * (BL - 1) / 255.0))

static func palette_color(i:int) -> Array:
	if i >= RL * GL * BL: return [0, 0, 0]
	var r = i / (GL * BL)
	var g = (i / BL) % GL
	var b = i % BL
	return [int(round(r * 255.0 / (RL - 1))), int(round(g * 255.0 / (GL - 1))), int(round(b * 255.0 / (BL - 1)))]

# the palette index a colour gets (tests check decoded pixels against this)
func index_of(r:int, g:int, b:int) -> int:
	return _lut_r[r] + _lut_g[g] + _lut_b[b]

func add_frame(rgb:PoolByteArray):
	out.put_u8(0x21) # graphic control: no transparency, delay
	out.put_u8(0xF9)
	out.put_u8(4)
	out.put_u8(0)
	out.put_u16(delay_cs)
	out.put_u8(0)
	out.put_u8(0)
	out.put_u8(0x2C) # image descriptor: the whole screen, no local palette
	out.put_u16(0)
	out.put_u16(0)
	out.put_u16(w)
	out.put_u16(h)
	out.put_u8(0)
	out.put_u8(8) # LZW minimum code size
	var data = _lzw(rgb)
	var i = 0
	while i < data.size():
		var n = min(255, data.size() - i)
		out.put_u8(n)
		out.put_data(data.subarray(i, i + n - 1))
		i += n
	out.put_u8(0)

func finish() -> PoolByteArray:
	out.put_u8(0x3B)
	return out.data_array

# GIF LZW (codes LSB first; the code size grows when the next code would not fit, as decoders expect;
# a full table is cleared)
func _lzw(rgb:PoolByteArray) -> PoolByteArray:
	var n = w * h
	var res = PoolByteArray()
	var lr = _lut_r
	var lg = _lut_g
	var lb = _lut_b
	var dict = {}
	var nxt = 258
	var size = 9
	var acc = 0
	var nbits = 0
	# clear code first
	acc |= 256 << nbits
	nbits += size
	var prefix = lr[rgb[0]] + lg[rgb[1]] + lb[rgb[2]]
	var p = 3
	for _i in range(1, n):
		var k = lr[rgb[p]] + lg[rgb[p + 1]] + lb[rgb[p + 2]]
		p += 3
		var key = (prefix << 8) | k
		var hit = dict.get(key, -1)
		if hit >= 0:
			prefix = hit
			continue
		acc |= prefix << nbits
		nbits += size
		while nbits >= 8:
			res.append(acc & 0xFF)
			acc >>= 8
			nbits -= 8
		if nxt < 4096:
			dict[key] = nxt
			nxt += 1
			if nxt > (1 << size) and size < 12: size += 1
		else:
			acc |= 256 << nbits
			nbits += size
			while nbits >= 8:
				res.append(acc & 0xFF)
				acc >>= 8
				nbits -= 8
			dict = {}
			nxt = 258
			size = 9
		prefix = k
	acc |= prefix << nbits
	nbits += size
	if nxt < 4096: # (the decoder adds an entry for that last code too, and may grow the code size)
		nxt += 1
		if nxt > (1 << size) and size < 12: size += 1
	acc |= 257 << nbits
	nbits += size
	while nbits > 0:
		res.append(acc & 0xFF)
		acc >>= 8
		nbits -= 8
	return res
