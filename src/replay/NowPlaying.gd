extends Control
# "Now playing" card on the title screen (personal build, after the Rhythia lazer fork's NowPlaying, in
# the mono look): a sharp black slab with a thin outline and a white edge strip, "// NOW PLAYING", the
# map's cover, title and mapper, a progress line with the time, and pause / next buttons (next = a new
# random map from the jukebox). All drawn here, redrawn ~30 times a second while it plays.
# Added by TitleMenu.gd (top right).

const W = 460.0
const H = 112.0
const COVER = 76.0
const BTN = 34.0
const Look = preload("res://mods/replay/Look.gd")
const Icons = preload("res://mods/replay/Icons.gd")

var menu:Node
var f_title:Font
var f_small:Font
var f_tag:Font
var hover_btn:int = -1           # 0 pause, 1 next
var hover_k:Array = [0.0, 0.0]
var press_k:Array = [0.0, 0.0]
var redraw_t:float = 0.0

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	rect_size = Vector2(W, H)
	anchor_left = 1
	anchor_right = 1
	margin_left = -W - 44
	margin_right = -44
	margin_top = 80
	margin_bottom = 80 + H
	f_title = _font(21)
	f_small = _font(14)
	f_tag = _font(12)

func _font(size:int):
	var base = get_font("font", "Label")
	if base is DynamicFont:
		var f = base.duplicate()
		f.size = size
		return f
	return base

func _jb():
	return menu.get_node_or_null("Jukebox") if menu else null

func _music_paused() -> bool:
	var mp = menu.get_node_or_null("MusicPause") if menu else null
	if mp: return mp.paused
	var jb = _jb()
	var p = jb.player() if jb else null
	return p != null and p.stream_paused

func _btn_rect(i:int) -> Rect2:
	return Rect2(Vector2(W - 16 - BTN * (2 - i) - 8 * (1 - i), 22), Vector2(BTN, BTN))

func _process(delta):
	var m = get_local_mouse_position()
	var hb = -1
	for i in 2:
		if _btn_rect(i).grow(4).has_point(m): hb = i
	if hb != hover_btn:
		hover_btn = hb
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if hb >= 0 else CURSOR_ARROW
	var moving = false
	for i in 2:
		var h = lerp(hover_k[i], 1.0 if hover_btn == i else 0.0, 1.0 - exp(-delta * 14.0))
		var p = max(0.0, press_k[i] - delta * 5.0)
		if abs(h - hover_k[i]) > 0.002 or p != press_k[i]: moving = true
		hover_k[i] = h
		press_k[i] = p
	redraw_t += delta
	if moving or redraw_t >= 1.0 / 30.0:
		redraw_t = 0.0
		update()

func _gui_input(ev):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		if hover_btn == 0:
			press_k[0] = 1.0
			var mp = menu.get_node_or_null("MusicPause")
			if mp: mp.toggle()
			else:
				var p = _jb().player() if _jb() else null
				if p: p.stream_paused = !p.stream_paused
		elif hover_btn == 1:
			press_k[1] = 1.0
			if _jb(): _jb().next()
		accept_event()

static func _fmt(s:float) -> String:
	var t = int(max(0.0, s))
	return "%d:%02d" % [t / 60, t % 60]

# text cut to fit max_w px (with "..")
static func _fit(f:Font, s:String, max_w:float) -> String:
	if f.get_string_size(s).x <= max_w: return s
	while s.length() > 1 and f.get_string_size(s + "..").x > max_w: s = s.substr(0, s.length() - 1)
	return s + ".."

func _draw():
	var r = Rect2(Vector2.ZERO, Vector2(W, H))
	draw_rect(r, Color(0.02, 0.02, 0.024, 0.78))
	draw_rect(r, Color(1, 1, 1, 0.18), false, 1.0)
	draw_rect(Rect2(0, 0, 3, H), Color(1, 1, 1, 0.85))
	var jb = _jb()
	var s = jb.playing_map() if jb else null
	var p = jb.player() if jb else null
	var x0 = 18.0
	# cover (keeps its colours), or a music note in a frame
	var cr = Rect2(Vector2(x0, (H - COVER) / 2 - 4), Vector2(COVER, COVER))
	var tex = null
	if s:
		tex = s.thumb if "thumb" in s and s.thumb else (s.loaded_cover() if s.has_method("loaded_cover") else null)
	if tex: draw_texture_rect(tex, cr, false)
	else:
		draw_rect(cr, Color(1, 1, 1, 0.05))
		Icons.draw(self, "music-note", cr.grow(-24), Color(1, 1, 1, 0.35))
	draw_rect(cr, Color(1, 1, 1, 0.25), false, 1.0)
	var tx = cr.end.x + 16
	var text_w = _btn_rect(0).position.x - tx - 12
	if f_tag: draw_string(f_tag, Vector2(tx, 26), "// NOW PLAYING", Color(1, 1, 1, 0.42))
	if s:
		if f_title: draw_string(f_title, Vector2(tx, 54), _fit(f_title, s.name.to_upper(), text_w), Color(1, 1, 1))
		if f_small: draw_string(f_small, Vector2(tx, 76), _fit(f_small, "MAPPED BY " + str(s.creator).to_upper(), text_w), Color(1, 1, 1, 0.5))
	else:
		if f_title: draw_string(f_title, Vector2(tx, 54), "NOTHING PLAYING", Color(1, 1, 1, 0.6))
		if f_small: draw_string(f_small, Vector2(tx, 76), "PRESS NEXT FOR A RANDOM MAP", Color(1, 1, 1, 0.4))
	# progress line + time
	var length = p.stream.get_length() if s and p and p.stream else 0.0
	var pos = p.get_playback_position() if s and p else 0.0
	var ly = H - 18.0
	var lw = W - tx - 18
	draw_rect(Rect2(tx, ly, lw, 2), Color(1, 1, 1, 0.14))
	if length > 0:
		var k = clamp(pos / length, 0.0, 1.0)
		draw_rect(Rect2(tx, ly, lw * k, 2), Color(1, 1, 1, 0.9))
		draw_rect(Rect2(tx + lw * k - 1, ly - 3, 2, 8), Color(1, 1, 1))
		if f_tag:
			var t = "%s / %s" % [_fmt(pos), _fmt(length)]
			draw_string(f_tag, Vector2(W - 18 - f_tag.get_string_size(t).x, ly - 8), t, Color(1, 1, 1, 0.5))
	# buttons: pause / play, next
	var icons = ["play" if _music_paused() else "pause", "step-forward"]
	for i in 2:
		var br = _btn_rect(i)
		var h = hover_k[i]
		var ox = -press_k[i] * 2.0
		var b = Rect2(br.position + Vector2(ox, 0), br.size)
		draw_rect(b, Color(1, 1, 1, 0.04).linear_interpolate(Color(1, 1, 1, 0.95), h))
		draw_rect(b, Color(1, 1, 1, 0.3 + 0.5 * h), false, 1.0)
		var ink = Color(0.03, 0.03, 0.035) if h > 0.5 else Color(1, 1, 1, 0.85)
		if Icons.available(): Icons.draw(self, icons[i], b.grow(-9), ink)
		if h > 0.02: Look.brackets(self, b.grow(3.0 + 6.0 * (1.0 - h)), 7.0, Color(1, 1, 1, h * 0.9), 1.5)
