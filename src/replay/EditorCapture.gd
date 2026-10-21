extends Node
# Map editor audio capture (Rhythia-reimagined). The game can't decode mp3 / ogg to samples from a
# script, so the song is played muted at PITCH x speed through a bus with an AudioEffectCapture and
# its samples are read back as they are mixed. Every sample's song time is exact: frames read so far
# x PITCH / mix rate (the capture buffer is cleared and the player started under the audio lock, so
# the first frame captured is the song's first frame; frames the buffer dropped are counted in).
# Per ABIN ms of song it keeps the peak of a low band (one-pole low-pass at LO_HZ: kick / bass), a
# high band (what a low-pass at HI_HZ leaves out: snares / hats) and the whole signal, in dB scaled
# 0..1 (EditorAuto.gd reads these), plus waveform peaks per `wave_bin` ms (what the timeline draws).
# (Earlier builds read the bus peak meter once per frame: ~70 ms of song per value at 4x, too coarse
# for a beat - the tempo came out wrong.)

signal finished

const PITCH = 4.0
const ABIN = 10.0
const LO_HZ = 150.0
const HI_HZ = 2000.0
const BUS = "RRWave"
const MUTE_BUS = "RRMute"

var state:String = "idle"           # idle | loading | ready | failed
var len_ms:float = 0.0
var wave_bin:float = 25.0
var wave:PoolRealArray = PoolRealArray()
var lo:PoolRealArray = PoolRealArray()
var hi:PoolRealArray = PoolRealArray()
var al:PoolRealArray = PoolRealArray()
var bins:int = 0                    # analysis bins done
var wave_n:int = 0                  # waveform bins done

var _player:AudioStreamPlayer
var _cap:AudioEffectCapture
var _fpb:float = 1.0                # mix frames per analysis bin
var _frames:int = 0
var _edge:float = 0.0
var _a_lo:float = 0.0
var _a_hp:float = 0.0
var _f_lo:float = 0.0
var _f_hp:float = 0.0
var _p_lo:float = 0.0
var _p_hi:float = 0.0
var _p_al:float = 0.0
var _dropped:int = 0
var _quiet:float = 0.0
var worst_us:int = 0                # longest time one frame's reading + processing took

# the two buses (created once per session: removing them under a player crashed the game) and the
# capture effect. A bus can only send to a bus with a LOWER index, so the muted one comes first.
static func capture_effect() -> AudioEffectCapture:
	var mute = AudioServer.get_bus_index(MUTE_BUS)
	if mute < 0:
		AudioServer.add_bus()
		mute = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(mute, MUTE_BUS)
	AudioServer.set_bus_volume_db(mute, -80.0)
	AudioServer.set_bus_mute(mute, true)
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, BUS)
	if AudioServer.get_bus_index(BUS) < AudioServer.get_bus_index(MUTE_BUS):
		AudioServer.move_bus(AudioServer.get_bus_index(MUTE_BUS), AudioServer.get_bus_index(BUS))
	var bus = AudioServer.get_bus_index(BUS)
	AudioServer.set_bus_send(bus, MUTE_BUS)
	for i in AudioServer.get_bus_effect_count(bus):
		var e = AudioServer.get_bus_effect(bus, i)
		if e is AudioEffectCapture: return e
	var c = AudioEffectCapture.new()
	c.buffer_length = 3.0 # (s of mix; a longer hitch than that drops frames, which are counted in)
	AudioServer.add_bus_effect(bus, c)
	return c

func start(stream:AudioStream, length_ms:float, wbin:float = 25.0):
	stop()
	len_ms = length_ms
	wave_bin = wbin
	var nw = int(ceil(len_ms / wave_bin)) + 2
	var na = int(ceil(len_ms / ABIN)) + 2
	wave = _zeros(nw)
	lo = _zeros(na)
	hi = _zeros(na)
	al = _zeros(na)
	bins = 0
	wave_n = 0
	if !stream or len_ms <= 0 or !is_inside_tree(): # (in the tree first: a player outside it never mixes)
		state = "failed"
		return
	_cap = capture_effect()
	var rate = AudioServer.get_mix_rate()
	_fpb = ABIN / 1000.0 * rate / PITCH
	_a_lo = 1.0 - exp(-TAU * LO_HZ * PITCH / rate) # (cut-offs in song Hz: x PITCH in the mix)
	_a_hp = 1.0 - exp(-TAU * HI_HZ * PITCH / rate)
	_frames = 0
	_edge = _fpb
	_f_lo = 0.0
	_f_hp = 0.0
	_p_lo = 0.0
	_p_hi = 0.0
	_p_al = 0.0
	_quiet = 0.0
	worst_us = 0
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.bus = BUS
	_player.pitch_scale = PITCH
	add_child(_player)
	AudioServer.lock()
	_cap.clear_buffer()
	_dropped = _cap.get_discarded_frames()
	_player.play()
	AudioServer.unlock()
	state = "loading"
	set_process(true)

static func _zeros(n:int) -> PoolRealArray:
	var a = PoolRealArray()
	a.resize(n)
	for i in n: a[i] = 0.0
	return a

func stop():
	if is_instance_valid(_player):
		_player.stop()
		_player.queue_free()
	_player = null
	set_process(false)

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	set_process(state == "loading")

func _process(delta):
	if state != "loading": return
	var us = OS.get_ticks_usec()
	var avail = _cap.get_frames_available()
	if avail > 0:
		_quiet = 0.0
		_feed(_cap.get_buffer(avail))
	else:
		_quiet += delta
	worst_us = max(worst_us, OS.get_ticks_usec() - us)
	var d = _cap.get_discarded_frames()
	if d > _dropped: # (dropped while the buffer was full: they came after everything read so far)
		_skip(d - _dropped)
		_dropped = d
	var t = _frames / _fpb * ABIN
	var playing = is_instance_valid(_player) and _player.playing
	if t >= len_ms or (!playing and avail == 0) or _quiet > 3.0:
		if _p_al > 0.0 or _p_lo > 0.0: _bin()
		stop()
		state = "ready" if _frames > 0 else "failed"
		wave_n = wave.size() if state == "ready" else 0
		emit_signal("finished")

func _feed(buf:PoolVector2Array):
	var alo = _a_lo
	var ahp = _a_hp
	var flo = _f_lo
	var fhp = _f_hp
	var plo = _p_lo
	var phi = _p_hi
	var pal = _p_al
	var fr = _frames
	var edge = _edge
	for s in buf:
		var v = (s.x + s.y) * 0.5
		flo += alo * (v - flo)
		fhp += ahp * (v - fhp)
		plo = max(plo, abs(flo))
		phi = max(phi, abs(v - fhp))
		pal = max(pal, abs(v))
		fr += 1
		if fr >= edge:
			_p_lo = plo
			_p_hi = phi
			_p_al = pal
			_bin()
			plo = 0.0
			phi = 0.0
			pal = 0.0
			edge += _fpb
	_f_lo = flo
	_f_hp = fhp
	_p_lo = plo
	_p_hi = phi
	_p_al = pal
	_frames = fr
	_edge = edge

func _skip(n:int):
	_frames += n
	while _edge <= _frames:
		bins += 1
		_edge += _fpb
	_p_lo = 0.0
	_p_hi = 0.0
	_p_al = 0.0

func _bin():
	if bins < lo.size():
		lo[bins] = _db(_p_lo)
		hi[bins] = _db(_p_hi)
		al[bins] = _db(_p_al)
		var w = int(bins * ABIN / wave_bin)
		if w < wave.size():
			wave[w] = max(wave[w], pow(clamp(_p_al, 0.0, 1.0), 0.7))
			wave_n = w
	bins += 1
	_p_lo = 0.0
	_p_hi = 0.0
	_p_al = 0.0

static func _db(x:float) -> float:
	return clamp((linear2db(max(x, 1e-7)) + 70.0) / 70.0, 0.0, 1.0)
