extends CanvasLayer
# osu!-style startup intro: black screen, Rhythia logo zooms in on the intro sound, pulses on its hits,
# then zooms out + fades to reveal the menu. Injected into init.tscn; moves itself to the root so it
# survives the init -> menu scene change. Click / any key skips.

const PATH = "res://mods/intro/Intro.gd"
const SOUND = "res://mods/intro/intro.mp3"
const LOGO = "res://assets/images/branding/icon.png"
const MENU = "res://scenes/menu/menu2.tscn"

const IMPACT = 0.03                              # main hit in the sound
const PULSES = [0.51, 1.08, 1.17, 1.32, 1.47]    # smaller hits
const SOUND_END = 1.8                            # audible part is over
const OUTRO = 0.6
const MAX_WAIT = 6.0                             # never cover the screen longer than this past the sound

var bg:ColorRect
var flash:ColorRect
var glow:TextureRect
var logo:TextureRect
var rings:Control
var player:AudioStreamPlayer
var t:float = 0.0
var t_fallback:float = 0.0
var started:bool = false
var outro_t:float = -1.0
var music_bus:int = -1
var music_was_muted:bool = false

func _ready():
	if get_parent() != get_tree().root:
		# launched from init.tscn: run as a root node instead
		var me = load(PATH).new()
		me.name = "Intro"
		get_tree().root.call_deferred("add_child", me)
		queue_free()
		return
	layer = 128
	pause_mode = Node.PAUSE_MODE_PROCESS
	bg = rect(Color(0, 0, 0, 1))
	var tex = load(LOGO)
	glow = TextureRect.new()
	glow.texture = tex
	glow.expand = true
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add = CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	add_child(glow)
	logo = TextureRect.new()
	logo.texture = tex
	logo.expand = true
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	rings = Control.new()
	rings.anchor_right = 1
	rings.anchor_bottom = 1
	rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rings.connect("draw", self, "_draw_rings")
	add_child(rings)
	flash = rect(Color(1, 1, 1, 0))
	logo.modulate.a = 0
	glow.modulate.a = 0

	player = AudioStreamPlayer.new()
	var f = File.new()
	if f.open(SOUND, File.READ) == OK:
		var s = AudioStreamMP3.new()
		s.data = f.get_buffer(f.get_len())
		f.close()
		player.stream = s
	add_child(player)
	# keep the menu music quiet until the logo leaves
	music_bus = AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		music_was_muted = AudioServer.is_bus_mute(music_bus)
		AudioServer.set_bus_mute(music_bus, true)
	layout()
	get_tree().root.connect("size_changed", self, "layout")

func rect(c:Color) -> ColorRect:
	var r = ColorRect.new()
	r.color = c
	r.anchor_right = 1
	r.anchor_bottom = 1
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

func layout():
	var vs = get_viewport().get_visible_rect().size
	var d = vs.y * 0.36
	for n in [logo, glow]:
		n.rect_size = Vector2(d, d)
		n.rect_position = (vs - n.rect_size) / 2
		n.rect_pivot_offset = n.rect_size / 2

func wants_fullscreen() -> bool:
	var f = File.new()
	if f.open(Globals.p("user://settings.json"), File.READ) != OK: return false
	var r = JSON.parse(f.get_as_text())
	f.close()
	return r.error == OK and r.result is Dictionary and r.result.get("window_fullscreen", false) == true

var wait_fs:bool = false
var wait_t:float = 0.0
var settle:int = 0

func _process(delta):
	if !started:
		# the game opens windowed and switches to fullscreen ~1-2 s later: start after that,
		# so the zoom isn't lost in the switch (and init has applied the volume settings)
		if wait_t == 0.0: wait_fs = wants_fullscreen()
		wait_t += delta
		if wait_fs and !OS.window_fullscreen and wait_t < 4.0: return
		settle += 1
		if settle < 3: return
		started = true
		layout()
		if player.stream: player.play()
		return
	t_fallback += delta
	if player.playing:
		t = player.get_playback_position() + AudioServer.get_time_since_last_mix()
	else:
		t = max(t, t_fallback)

	if outro_t < 0:
		var menu_up = get_tree().current_scene and get_tree().current_scene.filename == MENU
		if t >= SOUND_END and (menu_up or t >= SOUND_END + MAX_WAIT): begin_outro()

	# logo: zoom in from 0.6 to 1.0 over the sound, punch on each hit
	var k = clamp(t / SOUND_END, 0.0, 1.0)
	var s = lerp(0.6, 1.0, 1.0 - pow(1.0 - k, 3))
	s += 0.07 * hit(t, IMPACT, 9.0)
	for p in PULSES: s += 0.025 * hit(t, p, 14.0)
	if t > SOUND_END: s += 0.012 * sin((t - SOUND_END) * 3.0)   # gentle breathing while waiting
	var alpha = clamp((t - IMPACT + 0.02) / 0.1, 0.0, 1.0)
	var glow_a = 0.25 + 0.5 * hit(t, IMPACT, 4.0)
	for p in PULSES: glow_a += 0.18 * hit(t, p, 10.0)
	flash.color.a = 0.28 * hit(t, IMPACT, 7.0)

	if outro_t >= 0:
		outro_t += delta
		var o = clamp(outro_t / OUTRO, 0.0, 1.0)
		s *= 1.0 + 0.7 * o * o
		alpha *= 1.0 - o
		glow_a *= 1.0 - o
		bg.color.a = 1.0 - clamp((outro_t - 0.1) / OUTRO, 0.0, 1.0)
		if outro_t >= OUTRO + 0.1:
			finish()
			return

	logo.rect_scale = Vector2(s, s)
	logo.modulate.a = alpha
	glow.rect_scale = Vector2(s * 1.12, s * 1.12)
	glow.modulate.a = alpha * glow_a
	rings.update()

func hit(now:float, at:float, decay:float) -> float:
	return exp(-(now - at) * decay) if now >= at else 0.0

func _draw_rings():
	# expanding outline from the logo on the main hit and the second hit
	var c = get_viewport().get_visible_rect().size / 2
	var r0 = get_viewport().get_visible_rect().size.y * 0.13
	for h in [[IMPACT, 0.75, 1.0], [PULSES[0], 0.6, 0.55]]:
		var age = t - h[0]
		if age < 0 or age > h[1]: continue
		var a = age / h[1]
		var r = r0 * (1.0 + 2.2 * (1.0 - pow(1.0 - a, 3)))
		rings.draw_arc(c, r, 0, TAU, 96, Color(1, 0.2, 0.3, (1.0 - a) * 0.6 * h[2]), max(2.0, r0 * 0.04), true)

func begin_outro():
	if outro_t < 0:
		outro_t = 0.0
		if music_bus >= 0: AudioServer.set_bus_mute(music_bus, music_was_muted)

func _input(ev):
	if outro_t >= 0 or t < 0.3: return
	if (ev is InputEventKey or ev is InputEventMouseButton) and ev.pressed:
		begin_outro()

func finish():
	if music_bus >= 0 and outro_t < 0: AudioServer.set_bus_mute(music_bus, music_was_muted)
	queue_free()
