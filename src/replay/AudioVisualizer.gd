extends Control
# Menu audio visualizer, port of the rewrite's AudioSpectrum + jukebox progress shader:
# a strip of thin bars along the bottom of the menu, bars rising from the bottom edge,
# the part of the strip left of the song position drawn in the fill colour.

const MIN_FREQ = 0.0
const MAX_FREQ = 6000.0
const BAR_SIZE = 4.0
const BAR_GAP = 4.0
const BAR_MIN = 1.0
const RESPONSIVENESS = 24.0
const COLOR_FILL = Color(0.7882353, 0, 0.27058825, 1)
const COLOR_BACK = Color(1, 0.7921569, 0.8039216, 0.74509805)
const HEIGHT = 140.0 # bar strip height (was 64)
const FADE = 64.0 # soft fade above the strip so the map list melts into the bars
const FADE_COLOR = Color(0, 0, 0, 0.85)
const PREVIEW = "Main/Maps/Results/Results/RS/H1/Info/Control/PreviewMusic"

var bus:int = -1
var effect:AudioEffectSpectrumAnalyzer
var analyzer
var mags:PoolRealArray = PoolRealArray()
var ceiling:float = 0.01
var target_ceiling:float = 0.01
var progress:float = 0.0
var menu:Node
var preview_cache = null

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_top = 1
	anchor_right = 1
	anchor_bottom = 1
	margin_top = -(HEIGHT + 8)
	margin_left = 8
	margin_right = -8
	margin_bottom = -8
	bus = AudioServer.get_bus_index("Music")
	if bus < 0: return
	effect = AudioEffectSpectrumAnalyzer.new()
	AudioServer.add_bus_effect(bus, effect)
	analyzer = AudioServer.get_bus_effect_instance(bus, AudioServer.get_bus_effect_count(bus) - 1)

func _exit_tree():
	# take the analyzer off the Music bus again (gameplay manages effect 0 of that bus itself)
	if bus < 0 or !effect: return
	for i in range(AudioServer.get_bus_effect_count(bus) - 1, -1, -1):
		if AudioServer.get_bus_effect(bus, i) == effect:
			AudioServer.remove_bus_effect(bus, i)
			break

func _process(delta):
	if !analyzer or !is_visible_in_tree(): return
	var count = int(round((rect_size.x - BAR_SIZE) / (BAR_SIZE + BAR_GAP)))
	if count < 2: return
	if mags.size() != count:
		mags = PoolRealArray()
		mags.resize(count)
		for i in count: mags[i] = 0.0
	var step = (MAX_FREQ - MIN_FREQ) / count
	var k = min(1.0, delta * RESPONSIVENESS)
	var top = 0.0
	for i in count:
		var lo = MIN_FREQ + i * step
		var m = analyzer.get_magnitude_for_frequency_range(lo, lo + step).length()
		var v = lerp(mags[i], m, k)
		mags[i] = v
		if v > top: top = v
	if top > 0.0015: target_ceiling = top
	ceiling = lerp(ceiling, target_ceiling, min(1.0, delta * 6))
	progress = _song_progress()
	update()

func _song_progress() -> float:
	if !menu: menu = owner if owner else get_parent()
	var pm = menu.get_node_or_null(PREVIEW) if menu else null
	if !pm and menu: # map page re-layout moved it (under the mods bar)
		if !is_instance_valid(preview_cache): preview_cache = menu.find_node("PreviewMusic", true, false)
		pm = preview_cache
	if !pm: return 0.0
	for n in ["Song", "MenuSong"]:
		var p = pm.get_node_or_null(n)
		if p and p.playing and p.stream:
			var l = p.stream.get_length()
			if l > 0: return clamp(p.get_playback_position() / l, 0.0, 1.0)
	return 0.0

func _draw():
	_draw_fade()
	var count = mags.size()
	if count < 2: return
	var w = rect_size.x - BAR_SIZE
	var h = rect_size.y
	var split = progress * rect_size.x
	# (draw_multiline ignores the width in Godot 3, so each bar is a rect)
	for i in count:
		var s = clamp(mags[i] / ceiling, BAR_MIN / h, 1.0)
		var x = i / (count - 1.0) * w
		var bh = s * h
		draw_rect(Rect2(x, h - bh, BAR_SIZE, bh), COLOR_FILL if x + BAR_SIZE / 2 < split else COLOR_BACK)

func _draw_fade():
	# from transparent (FADE px above the strip) to FADE_COLOR at the strip, solid down to the screen edge
	var x0 = -8.0 # (not under the sidebar)
	var x1 = rect_size.x - margin_right
	var top = -FADE
	var mid = rect_size.y * 0.35
	var bottom = rect_size.y - margin_bottom
	var clear = Color(FADE_COLOR.r, FADE_COLOR.g, FADE_COLOR.b, 0)
	draw_polygon(PoolVector2Array([Vector2(x0, top), Vector2(x1, top), Vector2(x1, mid), Vector2(x0, mid)]),
		PoolColorArray([clear, clear, FADE_COLOR, FADE_COLOR]))
	draw_rect(Rect2(x0, mid, x1 - x0, bottom - mid), FADE_COLOR)
