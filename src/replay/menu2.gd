extends Node

func idle_status():
	# after 5 min on the menu switch to "listening to music"
	var activity = Discord.Activity.new()
	activity.set_type(Discord.ActivityType.Playing)
	activity.set_details("Main Menu")
	activity.set_state("Listening to music")

	var assets = activity.get_assets()
	assets.set_large_image("icon-bg")
	
	Discord.activity_manager.update_activity(activity)

func _ready():
	get_tree().paused = false
	if Rhythia.arcw_mode:
		get_tree().change_scene("res://w.tscn")
	if Rhythia.sex_mode:
		get_tree().change_scene("res://sex.tscn")
	if Rhythia.memory_lane:
		get_tree().change_scene("res://dya.tscn")
	
	# fix audio pitchshifts
	if AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Music")) > 0:
		AudioServer.remove_bus_effect(AudioServer.get_bus_index("Music"),0)
	
	$BlackFade.visible = true
	$BlackFade.color = Color(0,0,0,black_fade)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# embedded content manager page (its root script is null): restyle if the stars mod is installed
	var cm = get_node_or_null("Main/Content/Menu")
	if cm and ResourceLoader.exists("res://mods/stars/CMStyle.gd"):
		cm.add_child(load("res://mods/stars/CMStyle.gd").new(false))

	if ProjectSettings.get_setting("application/config/discord_rpc"):
		var activity = Discord.Activity.new()
		activity.set_type(Discord.ActivityType.Playing)
		activity.set_details("Main Menu")	
		activity.set_state("Selecting a song")

		var assets = activity.get_assets()
		assets.set_large_image("icon-bg")

		Discord.activity_manager.update_activity(activity)
		
		get_tree().create_timer(300).connect("timeout",self,"idle_status")
	
	call_deferred("_add_replay_button")
	call_deferred("_add_topo_background")
	call_deferred("_add_animations")
	call_deferred("_add_visualizer")
	call_deferred("_add_music_pause")
	add_child(load("res://mods/replay/UIJuice.gd").new()) # osu-style hover/press springs
	call_deferred("_add_osu_screens")
	call_deferred("_add_settings_style")
	# Alt + wheel volume overlay: one instance on the root, survives scene changes
	if !get_tree().root.has_node("VolumeOverlay"):
		get_tree().root.call_deferred("add_child", load("res://mods/replay/VolumeOverlay.gd").new())
	# touch screens: drag-to-scroll for the settings page, replay list and other scroll areas
	if OS.has_touchscreen_ui_hint() and !get_tree().root.has_node("TouchScroll"):
		get_tree().root.call_deferred("add_child", load("res://mods/replay/TouchScroll.gd").new())

# ---------------------------------------------------------------- osu-style screens
# results screen after a run, title menu on startup and on Esc from map selection
func _add_osu_screens():
	if Rhythia.has_meta("last_run"):
		var run = Rhythia.get_meta("last_run")
		Rhythia.remove_meta("last_run")
		var r = load("res://mods/replay/ResultsScreen.gd").new(run)
		r.name = "ResultsScreen"
		add_child(r)
	elif !Engine.has_meta("title_seen"):
		show_title()
	Engine.set_meta("title_seen", true)

func _add_settings_style():
	var s = load("res://mods/replay/SettingsStyle.gd").new()
	s.name = "SettingsStyle"
	add_child(s)

func show_title():
	var t = get_node_or_null("TitleMenu")
	if t: t.show_menu()
	else:
		t = load("res://mods/replay/TitleMenu.gd").new()
		t.name = "TitleMenu"
		add_child(t)

func _input(ev):
	if ev is InputEventKey and ev.pressed and !ev.echo and ev.scancode == KEY_F1 and !has_node("ReimaginedPanel"):
		get_tree().set_input_as_handled()
		open_customize()
		return
	if !(ev is InputEventKey) or !ev.pressed or ev.echo or ev.scancode != KEY_ESCAPE: return
	var maps = get_node_or_null("Main/Maps")
	var st = get_node_or_null("Main/Settings")
	if !(maps and maps.is_visible_in_tree()) and !(st and st.is_visible_in_tree()): return
	for n in ["ResultsScreen", "ReplayBrowser", "ReimaginedPanel"]:
		if has_node(n): return
	var mb = get_node_or_null("MapBrowser")
	if mb and !mb.hidden: return
	var t = get_node_or_null("TitleMenu")
	if t and t.visible: return
	var f = get_viewport().gui_get_focus_owner()
	if f is LineEdit and f.text != "":
		f.release_focus() # first Esc just leaves the search box
		return
	get_tree().set_input_as_handled()
	show_title()

# ---------------------------------------------------------------- animations
const UIAnim = preload("res://mods/replay/UIAnim.gd")
const PAGE_RISE = Vector2(0, 18)
const MAP_SLIDE = Vector2(48, 0)
const TAB_SLIDE = Vector2(24, 0)

func _add_animations():
	# sidebar pages (Maps, Settings, Content, ...) fade + rise in when shown
	for p in $Main.get_children():
		if p is Control: p.connect("visibility_changed", self, "_page_shown", [p])
	# map info panel slides in when a map is picked
	Rhythia.connect("selected_song_changed", self, "_map_picked")
	var results = get_node_or_null("Main/Maps/Results")
	if results: results.connect("visibility_changed", self, "_map_picked")
	# settings tabs slide in on switch
	var tabs = get_node_or_null("Main/Settings/S/F/TabContainer")
	if tabs is TabContainer: tabs.connect("tab_changed", self, "_settings_tab", [tabs])

func _page_shown(page:Control):
	if page.visible: UIAnim.play(page, PAGE_RISE, Vector2.ZERO, 0.0, 1.0, 0.24)

func _map_picked(_song = null):
	var info = get_node_or_null("Main/Maps/Results/Results")
	if info and info.is_visible_in_tree(): UIAnim.play(info, MAP_SLIDE, Vector2.ZERO, 0.0, 1.0, 0.28)

func _settings_tab(_tab:int, tabs:TabContainer):
	var page = tabs.get_current_tab_control()
	if !page: return
	# the newly shown tab still has a stale position (the TabContainer only fits visible tabs);
	# tabs are hidden + empty panel, so the content always sits at the origin
	var old = page.get_node_or_null("UIAnim")
	if old: old.stop()
	page.rect_position = Vector2.ZERO
	var a = UIAnim.play(page, TAB_SLIDE, Vector2.ZERO, 0.0, 1.0, 0.22)
	a.base = Vector2.ZERO
	a.fixed_base = true

# dim animated topographic contour lines behind the menu
const TOPO_SHADER = """
shader_type canvas_item;
uniform float strength = 0.09;
uniform float speed = 0.05;
uniform float density = 11.0;
uniform vec2 offset = vec2(0.0); // parallax, in screen UV
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int k = 0; k < 4; k++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = (SCREEN_UV + offset) * vec2(1.7 * aspect, 1.7);
	float t = TIME * speed;
	vec2 q = vec2(fbm(p + vec2(t, 0.0)), fbm(p + vec2(5.2, -t)));
	float h = fbm(p + 1.6 * q + vec2(0.7 * t, -0.4 * t));
	float c = h * density;
	float d = abs(fract(c - 0.5) - 0.5) / max(fwidth(c), 0.0001);
	float line = 1.0 - clamp(d - 0.3, 0.0, 1.0);
	float major = step(0.5, fract(floor(c) * 0.2 + 0.05)) * 0.6 + 0.4;
	float vignette = 1.0 - smoothstep(0.35, 0.95, length((SCREEN_UV - 0.5) * vec2(1.0, 1.4)));
	COLOR = vec4(1.0, 1.0, 1.0, line * major * strength * (0.45 + 0.55 * vignette));
}
"""

# round pause/resume-all-music button at the bottom centre, above the visualizer
func _add_music_pause():
	if has_node("MusicPause"): return
	var b = load("res://mods/replay/MusicPause.gd").new()
	add_child(b)
	b.z_index = 3

# rewrite-style audio spectrum along the bottom (above the pages, under the sidebar)
func _add_visualizer():
	if has_node("AudioVisualizer"): return
	var v = load("res://mods/replay/AudioVisualizer.gd").new()
	v.name = "AudioVisualizer"
	add_child(v)
	move_child(v, $Main.get_index() + 1)
	v.z_index = 1 # the map list cards draw above normal menu children
	if has_node("Sidebar"): v.margin_left = $Sidebar.rect_size.x + 8

func _add_topo_background():
	if has_node("TopoBackground"): return
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = TOPO_SHADER
	mat.shader = sh
	var bg = ColorRect.new()
	bg.name = "TopoBackground"
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.material = mat
	add_child(bg)
	move_child(bg, 0)

# replay viewer mod: sidebar button that opens the replay browser
func _add_replay_button():
	var l = get_node_or_null("Sidebar/L")
	# hide the "Rhythia Rewrite" button and the version text (bottom left)
	if l and l.has_node("RhythiaRewrite"): l.get_node("RhythiaRewrite").visible = false
	if l is BoxContainer: l.alignment = BoxContainer.ALIGN_CENTER # icons in the middle of the bar
	for v in ["VersionNumber", "VersionNumberB"]:
		if has_node(v): get_node(v).modulate = Color(1, 1, 1, 0)
	if !l or l.has_node("Replays"): return
	var replays = _sidebar_button(l, "Replays", "res://assets/images/modifiers/64/replaying.png", "Settings", "open_replays")
	# online map browser (browser mod)
	var last = replays
	if ResourceLoader.exists(MAP_BROWSER):
		last = _sidebar_button(l, "Browse", "res://assets/images/ui/cloud_32.png", replays.name, "open_map_browser")
	# Rhythia-reimagined customize panel (icon drawn: three sliders)
	var cz = _sidebar_button(l, "Customize", "res://assets/images/ui/cloud_32.png", last.name, "open_customize")
	var tex = cz.get_node("Tex")
	tex.texture = null
	var ic = load("res://mods/replay/Reimagined.gd").SlidersIcon.new()
	ic.anchor_right = 1
	ic.anchor_bottom = 1
	tex.add_child(ic)
	load("res://mods/replay/Reimagined.gd").apply_sidebar_icons(self)

# copy of the Credits button without its signals (so it doesn't switch pages)
func _sidebar_button(l:Node, label:String, icon:String, after:String, method:String) -> Button:
	var b:Button = l.get_node("Credits").duplicate(14)
	b.name = label
	b.toggle_mode = false
	b.group = null
	b.pressed = false
	b.visible = true
	b.get_node("Label").text = label
	b.get_node("Tex").texture = load(icon)
	l.add_child(b)
	l.move_child(b, l.get_node(after).get_index() + 1)
	b.connect("pressed", self, method)
	return b

func open_replays():
	if has_node("ReplayBrowser"): return
	if has_node("Press"): get_node("Press").play()
	var browser = load("res://mods/replay/ReplayBrowser.gd").new()
	browser.name = "ReplayBrowser"
	add_child(browser)

func open_customize():
	if has_node("ReimaginedPanel"): return
	if has_node("Press"): get_node("Press").play()
	var p = load("res://mods/replay/ReimaginedPanel.gd").new()
	p.name = "ReimaginedPanel"
	add_child(p)

const MAP_BROWSER = "res://mods/browser/MapBrowser.gd"
func open_map_browser():
	if has_node("Press"): get_node("Press").play()
	var mb = get_node_or_null("MapBrowser")
	if mb:
		if mb.hidden: mb.show_browser() # still finishing downloads in the background
		return
	mb = load(MAP_BROWSER).new()
	mb.name = "MapBrowser"
	add_child(mb)

var black_fade_target:bool = false
var black_fade:float = 1

func _process(delta):
	if Input.is_action_just_pressed("ui_end") and Input.is_key_pressed(KEY_SHIFT):
		get_tree().change_scene("res://scenes/loaders/menuload.tscn")

	if black_fade_target && black_fade != 1:
		black_fade = min(black_fade + (delta/0.3),1)
		$BlackFade.color = Color(0,0,0,black_fade)
	elif !black_fade_target && black_fade != 0:
		black_fade = max(black_fade - (delta/0.5),0)
		$BlackFade.color = Color(0,0,0,black_fade)
	$BlackFade.visible = (black_fade != 0)
	_update_launch_zoom()
	_update_parallax(delta)

# ---------------------------------------------------------------- launch zoom
# The menu zooms into the screen while it fades to black (starting a map, replay,
# content manager), and zooms back out while it fades in.
const LAUNCH_ZOOM = 0.12

func _update_launch_zoom():
	var menu = self # untyped: this script says "extends Node" but the menu root is a ColorRect
	if !(menu is Control): return
	menu.rect_pivot_offset = menu.rect_size / 2
	var s = 1.0 + LAUNCH_ZOOM * black_fade * black_fade # accelerating in, decelerating out
	menu.rect_scale = Vector2(s, s)

# ---------------------------------------------------------------- parallax
# Mouse position nudges the menu: background drifts more than the content, the
# sidebar stays put so it is easy to hit.
const PARALLAX_BG = 16.0 # px at the screen edge
const PARALLAX_UI = 5.0
const PARALLAX_SMOOTH = 4.0 # 1/s, frame-rate independent
var parallax:Vector2 = Vector2.ZERO
var main_margins:Array = [] # Main's own margins (l, t, r, b), captured once
var particle_base:Dictionary = {} # Particles2D -> original position

func _update_parallax(delta):
	var size = get_viewport().get_visible_rect().size
	if size.x <= 0 or size.y <= 0: return
	var target = (get_viewport().get_mouse_position() / size - Vector2(0.5, 0.5)) * 2.0
	target = Vector2(clamp(target.x, -1, 1), clamp(target.y, -1, 1))
	parallax = parallax.linear_interpolate(target, 1.0 - exp(-min(delta, 0.1) * PARALLAX_SMOOTH))
	var main = $Main
	if main_margins.empty():
		main_margins = [main.margin_left, main.margin_top, main.margin_right, main.margin_bottom]
	var ui = -parallax * PARALLAX_UI
	main.margin_left = main_margins[0] + ui.x
	main.margin_right = main_margins[2] + ui.x
	main.margin_top = main_margins[1] + ui.y
	main.margin_bottom = main_margins[3] + ui.y
	var bg = -parallax * PARALLAX_BG
	var topo = get_node_or_null("TopoBackground")
	if topo: topo.material.set_shader_param("offset", -bg / size)
	for n in ["Particles", "Particles2"]:
		var p = get_node_or_null(n)
		if !p: continue
		if !particle_base.has(n): particle_base[n] = p.position
		p.position = particle_base[n] + bg
