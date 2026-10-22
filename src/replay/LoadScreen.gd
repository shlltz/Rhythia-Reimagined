extends Control
# Map loading screen (added by the songload.gd override): the map page's blurred cover carries on
# behind a map card (cover banner, title, difficulty, stars, length, notes, mapper, mods, the
# player row with the square logo turning slowly, a loading bar). The song preview that was playing
# on the map page keeps going here through a low-pass filter (muffled) and fades out with the
# screen. Coming from a map page start (MapBackdrop.launch) the zoom carries on from the menu's.

const CardUI = preload("res://mods/replay/CardUI.gd")
const MapBackdrop = preload("res://mods/replay/MapBackdrop.gd")
const W = 760.0
const BANNER_H = 300.0
const H = 552.0
const INTRO = 0.5
const MUFFLE_BUS = "RRMuffle"
const MUFFLE_HZ = 650.0           # low-pass cutoff once muffled
const MUFFLE_TIME = 0.6           # s from open to muffled

var bg:TextureRect
var card:Panel
var banner:TextureRect
var title:Label
var pills:Control
var mods_row:Control
var who:Label
var when_l:Label
var status:Label
var logo:TextureRect
var bar:Control
var fonts:Dictionary = {}
var t:float = 0.0
var progress:float = -1.0         # real progress (replays), -1 = time-based
var shown:float = 0.0             # the bar as drawn
var ready_:bool = false
var zoom0:float = 1.0
var drift:Vector2 = Vector2.ZERO
var player:AudioStreamPlayer = null
var base_db:float = 0.0

func _init():
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_IGNORE
	var dark = ColorRect.new()
	dark.color = Color(0.02, 0.02, 0.024)
	dark.anchor_right = 1; dark.anchor_bottom = 1
	dark.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dark)
	bg = MapBackdrop.make_rect()
	add_child(bg)
	if Engine.has_meta("rr_launch"): # (the menu's zoom, so the cover doesn't jump)
		var l = Engine.get_meta("rr_launch")
		zoom0 = float(l.get("scale", 1.0))
		drift = l.get("offset", Vector2.ZERO)
	_build()

func _f(size:int):
	return CardUI.font(size, fonts)

func _build():
	card = Panel.new()
	card.mouse_filter = MOUSE_FILTER_IGNORE
	var sb = CardUI.box(Color(0.06, 0.06, 0.07, 0.9), Color(1, 1, 1, 0.1), 1, 22)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 40
	card.add_stylebox_override("panel", sb)
	card.anchor_left = 0.5; card.anchor_right = 0.5; card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.margin_left = -W / 2; card.margin_right = W / 2; card.margin_top = -H / 2; card.margin_bottom = H / 2
	card.rect_pivot_offset = Vector2(W, H) / 2
	add_child(card)
	if CardUI.mono(): card.connect("draw", self, "_brackets")
	banner = CardUI.banner(card, null, Rect2(1, 1, W - 2, BANNER_H), 21)
	pills = Control.new() # top-left pills on the banner
	pills.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(pills)
	title = CardUI.label(card, "", _f(32), Color(1, 1, 1), Vector2(30, BANNER_H - 64), W - 60)
	mods_row = Control.new()
	mods_row.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(mods_row)
	var line = ColorRect.new()
	line.color = Color(1, 1, 1, 0.08)
	line.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(line)
	line.rect_position = Vector2(30, 432); line.rect_size = Vector2(W - 60, 1)
	logo = TextureRect.new()
	CardUI.logo(logo)
	logo.expand = true
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(logo)
	logo.rect_position = Vector2(34, 450); logo.rect_size = Vector2(56, 56)
	logo.rect_pivot_offset = logo.rect_size / 2
	who = CardUI.label(card, "", _f(22), Color(1, 1, 1), Vector2(112, 450), 420)
	when_l = CardUI.label(card, CardUI.today(), _f(15), Color(1, 1, 1, 0.45), Vector2(112, 480), 420)
	status = CardUI.label(card, "Loading", _f(15), Color(1, 1, 1, 0.6), Vector2(W - 230, 466), 200)
	status.align = Label.ALIGN_RIGHT
	bar = Control.new()
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	bar.connect("draw", self, "_draw_bar")
	card.add_child(bar)
	bar.rect_position = Vector2(30, H - 26); bar.rect_size = Vector2(W - 60, 4)
	card.modulate.a = 0.0

func _brackets():
	load(CardUI.LOOK).brackets(card, Rect2(Vector2(), card.rect_size).grow(10), 26.0, Color(1, 1, 1, 0.5), 2.0)

# fill the card from a Song; called again after a replay finished loading
func show_song(song, is_replay:bool = false):
	if song == null: return
	var small = Engine.get_meta("rr_backdrop") if Engine.has_meta("rr_backdrop") and Rhythia.selected_song == song else null
	if small == null: small = MapBackdrop.small_texture(song)
	bg.texture = small
	if song.has_cover:
		banner.texture = song.cover
		banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		banner.material.set_shader_param("topo", 0.0)
	else:
		CardUI.no_cover(banner, song) # (no placeholder picture: contour lines in the difficulty colour)
		if !has_node("NoCover"):
			var nb = CardUI.no_cover_bg(song)
			nb.name = "NoCover"
			add_child(nb)
			move_child(nb, bg.get_index())
	title.text = CardUI.fit(song.name, _f(32), W - 60)
	for c in pills.get_children(): c.queue_free()
	for c in mods_row.get_children(): c.queue_free()
	var fp = _f(15)
	var dark = Color(0, 0, 0, 0.55)
	var x = 24.0
	var d = CardUI.difficulty(song)
	if d[0] != "": x = CardUI.pill_end(CardUI.pill(pills, d[0], fp, dark, Color(1, 1, 1), Vector2(x, 22), 32, Color(1, 1, 1, 0.12)))
	if is_replay: CardUI.pill(pills, "Replay", fp, dark, CardUI.accent().lightened(0.3), Vector2(x, 22), 32, Color(1, 1, 1, 0.12))
	# stars / length / notes / mapper
	var speed = CardUI.speed_now()
	var row = Vector2(28, BANNER_H + 22)
	var st = CardUI.stars(song, speed)
	var soft = Color(1, 1, 1, 0.07)
	if st > 0: row.x = CardUI.pill_end(CardUI.pill(mods_row, "★ %.2f" % st, fp, Color(0, 0, 0, 0.7), Color(1, 1, 1), row, 34, Color(1, 1, 1, 0.16)))
	var len_ms = float(song.last_ms) / speed if "last_ms" in song else 0.0
	if len_ms > 0: row.x = CardUI.pill_end(CardUI.pill(mods_row, CardUI.mmss(len_ms), fp, Color(d[1].r, d[1].g, d[1].b, 0.14), d[1].lightened(0.25), row, 34))
	var n = song.note_count if "note_count" in song else 0
	if n > 0: row.x = CardUI.pill_end(CardUI.pill(mods_row, "%s notes" % Globals.comma_sep(n), fp, soft, Color(1, 1, 1, 0.85), row, 34))
	CardUI.pill(mods_row, "mapped by " + str(song.creator), fp, soft, Color(1, 1, 1, 0.85), row, 34)
	# mods
	var my = BANNER_H + 74
	CardUI.label(mods_row, "Mods", _f(16), Color(1, 1, 1, 0.45), Vector2(30, my + 6))
	var tags = CardUI.mod_tags()
	var sp = CardUI.speed_tag(speed)
	if sp != "": tags.push_front(sp)
	var mx = 92.0
	if tags.empty(): CardUI.label(mods_row, "None", _f(16), Color(1, 1, 1, 0.7), Vector2(mx, my + 6))
	for tg in tags:
		var acc = CardUI.accent()
		mx = CardUI.pill_end(CardUI.pill(mods_row, tg, _f(14), Color(acc.r, acc.g, acc.b, 0.85), Color(0.08, 0.06, 0.06), Vector2(mx, my), 32), 8)
	var name_ = CardUI.player()
	who.text = ("Replay" if is_replay else ((name_ + "'s play") if name_ != "" else "Your play"))
	_start_music()

func set_status(text:String):
	status.text = text
	if text == "Ready":
		ready_ = true

func set_progress(v:float):
	progress = clamp(v, 0.0, 1.0)

# ------------------------------------------------------------------ muffled preview
func _start_music():
	if player or !Engine.has_meta("rr_launch_audio"): return
	var a = Engine.get_meta("rr_launch_audio")
	Engine.remove_meta("rr_launch_audio")
	if !(a.get("stream") is AudioStream): return
	var bus = AudioServer.get_bus_index(MUFFLE_BUS)
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus, MUFFLE_BUS)
		var lp = AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(bus, lp)
	AudioServer.set_bus_send(bus, str(a.get("bus", "Master")))
	player = AudioStreamPlayer.new()
	player.stream = a.stream
	player.bus = MUFFLE_BUS
	player.pitch_scale = float(a.get("pitch", 1.0))
	base_db = float(a.get("db", 0.0))
	player.volume_db = base_db
	add_child(player)
	var pos = float(a.get("pos", 0.0)) + (OS.get_ticks_msec() - int(a.get("t", OS.get_ticks_msec()))) / 1000.0 * player.pitch_scale
	var l = a.stream.get_length()
	player.play(fmod(pos, l) if l > 1.0 else 0.0)

func _muffle(k:float):
	var bus = AudioServer.get_bus_index(MUFFLE_BUS)
	if bus < 0 or AudioServer.get_bus_effect_count(bus) == 0: return
	var lp = AudioServer.get_bus_effect(bus, 0)
	lp.cutoff_hz = 20000.0 * pow(MUFFLE_HZ / 20000.0, k) # (even steps to the ear)

func _exit_tree():
	if player: player.stop()
	var bus = AudioServer.get_bus_index(MUFFLE_BUS)
	if bus >= 0: AudioServer.remove_bus(bus)
	if Engine.has_meta("rr_launch"): Engine.remove_meta("rr_launch")

# ------------------------------------------------------------------ animation
func _process(delta):
	var dt = min(delta, 1.0 / 30.0) # (a load hitch doesn't skip the intro)
	t += dt
	var e = 1.0 - pow(1.0 - min(t / INTRO, 1.0), 3)
	card.modulate.a = e
	var s = 0.965 + 0.035 * e
	card.rect_scale = Vector2(s, s)
	card.margin_top = -H / 2 + 24.0 * (1.0 - e)
	card.margin_bottom = H / 2 + 24.0 * (1.0 - e)
	var z = zoom0 * (1.0 + 0.035 * (1.0 - exp(-t / 2.5))) # (the menu's zoom keeps going, slower and slower)
	bg.rect_pivot_offset = rect_size / 2
	bg.rect_scale = Vector2(z, z)
	bg.rect_position = -drift * 12.0
	logo.rect_rotation = fmod(t * 24.0, 360.0) # a slow turn
	var target = progress if progress >= 0.0 else 0.9 * (1.0 - exp(-t / 1.4))
	if ready_: target = 1.0
	shown = lerp(shown, target, 1.0 - exp(-delta * 8.0))
	bar.update()
	if player:
		_muffle(min(t / MUFFLE_TIME, 1.0))
		var fade = float(get_parent().get("black_fade")) if "black_fade" in get_parent() else 0.0
		player.volume_db = base_db - 3.0 - 40.0 * fade * fade # (follows the fade to the run)

func _draw_bar():
	var w = bar.rect_size.x
	var acc = CardUI.accent()
	bar.draw_rect(Rect2(0, 0, w, 4), Color(1, 1, 1, 0.08))
	bar.draw_rect(Rect2(0, 0, w * shown, 4), acc)
