extends Control
# Map selection backdrop: the selected map's cover, blurred and dimmed, behind the whole menu (added
# by menu2.gd under everything else). Cross-fades on a new pick and only shows on the map pages.
# Cheap: the cover is shrunk once to SMALL px wide; the GPU's filtering plus a 9-tap blur on that
# small texture do the rest. The loading screen and the results screen use the same texture (Engine
# meta rr_backdrop) and look, so the background carries on from the map page into the run and back.

const SMALL = 192
const FADE = 0.35
const DIM = 0.44
const SETTLE = 0.12               # s a pick has to stay before its cover is fetched (scrolling the list)
const SHADER = """shader_type canvas_item;
uniform float grey = 0.0;
uniform float dim = 0.36;
uniform float radius = 0.012;
void fragment() {
	vec2 r = vec2(radius, radius * 1.6);
	vec4 c = texture(TEXTURE, UV) * 0.2;
	c += (texture(TEXTURE, UV + vec2(r.x, 0.0)) + texture(TEXTURE, UV - vec2(r.x, 0.0)) + texture(TEXTURE, UV + vec2(0.0, r.y)) + texture(TEXTURE, UV - vec2(0.0, r.y))) * 0.12;
	c += (texture(TEXTURE, UV + r) + texture(TEXTURE, UV - r) + texture(TEXTURE, UV + vec2(r.x, -r.y)) + texture(TEXTURE, UV + vec2(-r.x, r.y))) * 0.08;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, vec3(l), grey) * dim;
	COLOR = vec4(c.rgb, 1.0) * COLOR;
}"""
const PAGES = ["Main/Maps", "Main/Results", "Main/MapRegistry"] # new menu / classic page + grid

var front:TextureRect
var back:TextureRect
var song = null
var _pick_t:float = 0.0
var _want = null
var _fade:float = 1.0
var vis:float = 0.0               # page visibility (fades with the map page)
var zoom:float = 1.0              # set by menu2 during the launch transition

static func mono() -> bool:
	var L = load("res://mods/replay/Look.gd")
	for m in L.get_script_method_list():
		if m.name == "mono": return L.mono()
	return false

# the small blurred-to-be copy of a song's cover; null without one. loaded_only = never load / decode
# here (the map page's worker brings the full cover in)
static func small_texture(s, loaded_only:bool = false):
	if s == null or !s.has_cover: return null
	var tex = s.loaded_cover() if s.has_method("loaded_cover") else null
	if tex == null and !loaded_only: tex = s.cover
	if !(tex is Texture): return null
	var img = tex.get_data()
	if !(img is Image) or img.get_width() < 2: return null
	img = img.duplicate()
	if img.is_compressed(): img.decompress()
	var w = int(min(SMALL, img.get_width()))
	img.resize(w, int(max(2, round(w * float(img.get_height()) / img.get_width()))), Image.INTERPOLATE_BILINEAR)
	var t = ImageTexture.new()
	t.create_from_image(img, Texture.FLAG_FILTER)
	return t

static func make_rect() -> TextureRect:
	var r = TextureRect.new()
	r.anchor_right = 1
	r.anchor_bottom = 1
	r.expand = true
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m = ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = SHADER
	m.set_shader_param("grey", 1.0 if mono() else 0.0)
	m.set_shader_param("dim", DIM)
	r.material = m
	return r

func _init():
	name = "MapBackdrop"
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_IGNORE
	back = make_rect()
	add_child(back)
	front = make_rect()
	add_child(front)
	modulate.a = 0.0
	if Engine.has_meta("rr_backdrop"): # (back from a run: the same cover is already up)
		front.texture = Engine.get_meta("rr_backdrop")
		song = Rhythia.selected_song

func _process(delta):
	var menu = get_parent()
	var on = false
	for p in PAGES:
		var n = menu.get_node_or_null(p)
		if n and n.is_visible_in_tree(): on = true
	if Rhythia.selected_song != _want:
		_want = Rhythia.selected_song
		_pick_t = 0.0
	_pick_t += delta
	if _want != song and _pick_t >= SETTLE:
		var t = small_texture(_want, true)
		if t != null or _want == null or !_want.has_cover or _pick_t > 3.0: # (no cover after 3 s: let it go)
			song = _want
			back.texture = front.texture
			front.texture = t
			_fade = 0.0
			if t: Engine.set_meta("rr_backdrop", t)
			elif Engine.has_meta("rr_backdrop"): Engine.remove_meta("rr_backdrop")
	_fade = min(1.0, _fade + delta / FADE)
	var e = _fade * _fade * (3.0 - 2.0 * _fade)
	front.modulate.a = e
	back.modulate.a = 1.0 - e if back.texture else 0.0
	vis = move_toward(vis, 1.0 if on and front.texture != null else 0.0, delta / 0.3)
	modulate.a = vis
	# a slow drift with the menu's mouse parallax, slightly zoomed so the edges never show
	var size = rect_size
	var px = menu.get("parallax") if "parallax" in menu else Vector2.ZERO
	var s = 1.06 * zoom
	for r in [front, back]:
		r.rect_pivot_offset = size / 2
		r.rect_scale = Vector2(s, s)
		r.rect_position = -px * 12.0

# a map start from the map page (RunMapButton): the loading screen carries on the cover, the zoom
# (menu2 keeps rr_launch.scale / offset current while it zooms) and the preview that was playing
static func launch(menu:Node):
	if !menu: return
	var bd = menu.get_node_or_null("MapBackdrop")
	var pm = menu.find_node("PreviewMusic", true, false)
	if pm:
		for n in ["Song", "MenuSong"]:
			var p = pm.get_node_or_null(n)
			if p is AudioStreamPlayer and p.playing and p.stream:
				Engine.set_meta("rr_launch_audio", {stream = p.stream, pos = p.get_playback_position(), db = p.volume_db,
					bus = p.bus, pitch = p.pitch_scale, t = OS.get_ticks_msec()})
				break
	var seamless = bd != null and bd.vis > 0.5 and bd.front.texture != null and Rhythia.selected_song == bd.song
	Engine.set_meta("rr_launch", {t = OS.get_ticks_msec(), seamless = seamless, scale = 1.06, offset = Vector2.ZERO})
