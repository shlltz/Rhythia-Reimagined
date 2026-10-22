extends Reference
# Shared pieces of the map card screens (LoadScreen.gd, ResultsScreen.gd): the game's own font at
# any size, pills, stat tiles, the cover banner with rounded top corners and a dark fade for text,
# star rating, mod tags. Follows Look.gd: square corners and grey covers in the monochrome look,
# rounded and coloured otherwise.

const LOOK = "res://mods/replay/Look.gd"
const MODS = [["mod_nofail", "NF"], ["mod_sudden_death", "SD"], ["mod_hardrock", "HR"],
	["mod_flashlight", "FL"], ["mod_ghost", "GH"], ["mod_nearsighted", "NS"],
	["mod_chaos", "CH"], ["mod_earthquake", "EQ"], ["mod_mirror_x", "MX"],
	["mod_mirror_y", "MY"], ["mod_extra_energy", "EE"], ["mod_no_regen", "NR"]]
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
const BANNER_SHADER = """shader_type canvas_item;
uniform vec2 size = vec2(100.0);
uniform float radius = 18.0;
uniform float grey = 0.0;
uniform float shade = 0.82;
uniform float topo = 0.0;         // no cover: static contour lines in the difficulty colour instead
uniform vec4 tint : hint_color = vec4(1.0);
uniform vec2 seed = vec2(0.0);
varying vec2 p;
float hash(vec2 v) { return fract(sin(dot(v, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 v) {
	vec2 i = floor(v); vec2 f = fract(v); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 v) { float r = 0.0; float a = 0.5; for (int k = 0; k < 4; k++) { r += a * noise(v); v *= 2.03; a *= 0.5; } return r; }
void vertex() { p = VERTEX; }
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (topo > 0.5) {
		vec2 v = p / 360.0 + seed; // (broad, smooth shapes: two soft octaves, gentle warp)
		float h = noise(v + 0.35 * vec2(noise(v * 0.7 + 3.1), noise(v * 0.7 + 7.4))) * 0.7 + noise(v * 1.9 + 11.0) * 0.3;
		h *= 15.0;
		float d = abs(fract(h - 0.5) - 0.5) / max(fwidth(h), 0.0001);
		float line = 1.0 - smoothstep(0.35, 1.25, d); // (thin, even, anti-aliased)
		float major = 1.0;
		c = vec4(tint.rgb * 0.08 + vec3(0.02) + tint.rgb * line * 0.75, 1.0);
	}
	vec2 q = vec2(min(p.x, size.x - p.x), p.y);
	float a = 1.0;
	if (radius > 0.5 && q.x < radius && q.y < radius) a = 1.0 - smoothstep(radius - 1.0, radius + 0.5, length(vec2(radius) - q));
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, vec3(l), grey) * mix(1.0, 1.0 - shade, smoothstep(0.3, 1.0, p.y / size.y));
	COLOR = vec4(c.rgb, c.a * a) * COLOR;
}"""

static func mono() -> bool:
	return _has("mono") and load(LOOK).mono()

static func _has(m:String) -> bool:
	for x in load(LOOK).get_script_method_list():
		if x.name == m: return true
	return false

static func r(n:int) -> int: # corner radius in this look
	return 0 if mono() else n

static func accent() -> Color:
	return load(LOOK).accent()

static func box(bg:Color, border:Color = Color(0, 0, 0, 0), bw:int = 0, rad:int = 12) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(r(rad))
	sb.corner_detail = 8
	sb.anti_aliasing = true
	sb.draw_center = bg.a > 0
	return sb

# the game's font (uitheme: the modded font when installed) at a size
static func font(size:int, cache:Dictionary):
	if cache.has(size): return cache[size]
	var th = load("res://uitheme.tres") if ResourceLoader.exists("res://uitheme.tres") else null
	var base = th.default_font if th else null
	var f = null
	if base is DynamicFont:
		f = base.duplicate()
		f.size = size
	f = load("res://mods/replay/Reimagined.gd").heading_font(f, size)
	cache[size] = f
	return f

static func label(parent:Control, text:String, f, col:Color, pos:Vector2 = Vector2.ZERO, w:float = 0) -> Label:
	var l = Label.new()
	l.text = text
	if f: l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.rect_position = pos
	if w > 0:
		l.clip_text = true
		l.rect_size.x = w
	return l

# a rounded pill with text; width follows the text. -> the pill (its "label" meta is the Label)
static func pill(parent:Control, text:String, f, bg:Color, fg:Color, pos:Vector2, h:float = 32.0, border:Color = Color(0, 0, 0, 0)) -> Panel:
	var p = Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_stylebox_override("panel", box(bg, border, 1 if border.a > 0 else 0, int(h / 2)))
	parent.add_child(p)
	var l = label(p, text, f, fg)
	var tw = f.get_string_size(text).x if f else text.length() * 9.0
	p.rect_position = pos
	p.rect_size = Vector2(tw + 28, h)
	l.rect_position = Vector2(14, (h - (f.get_height() if f else 18.0)) / 2)
	p.set_meta("label", l)
	return p

# a pill row: next x after this pill
static func pill_end(p:Control, gap:float = 10.0) -> float:
	return p.rect_position.x + p.rect_size.x + gap

# a stat tile: small grey caption over a big value, optional note at the top right
static func tile(parent:Control, rect:Rect2, caption:String, value:String, fs, fb, note:String = "", value_col:Color = Color(1, 1, 1)) -> Panel:
	var p = Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_stylebox_override("panel", box(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.07), 1, 12))
	parent.add_child(p)
	p.rect_position = rect.position
	p.rect_size = rect.size
	label(p, caption, fs, Color(1, 1, 1, 0.5), Vector2(16, 12), rect.size.x - 24)
	if note != "":
		var n = label(p, note, fs, Color(1, 1, 1, 0.45), Vector2(16, 12), rect.size.x - 28)
		n.align = Label.ALIGN_RIGHT
	var v = label(p, value, fb, value_col, Vector2(16, rect.size.y - 14 - (fb.get_height() if fb else 22.0)), rect.size.x - 24)
	p.set_meta("value", v)
	return p

# the cover banner: rounded top corners (square in the monochrome look), darker towards the bottom
static func banner(parent:Control, tex:Texture, rect:Rect2, rad:int = 18, song = null) -> TextureRect:
	var t = TextureRect.new()
	t.texture = tex
	t.expand = true
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m = ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = BANNER_SHADER
	m.set_shader_param("size", rect.size)
	m.set_shader_param("radius", float(r(rad)))
	m.set_shader_param("grey", 0.0)
	t.material = m
	parent.add_child(t)
	t.rect_position = rect.position
	t.rect_size = rect.size
	if tex == null: no_cover(t, song)
	return t

# a map without a cover: the static contour texture in its difficulty colour (no placeholder picture)
static func no_cover(t:TextureRect, song):
	var img = Image.new()
	img.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1))
	var w = ImageTexture.new()
	w.create_from_image(img, 0)
	t.texture = w
	t.stretch_mode = TextureRect.STRETCH_SCALE
	var m = t.material
	m.set_shader_param("topo", 1.0)
	m.set_shader_param("tint", difficulty(song)[1])
	var h = hash(str(song.id)) if song and "id" in song else 0 # (each map its own pattern, always the same)
	m.set_shader_param("seed", Vector2(float(h & 1023) / 37.0, float((h >> 10) & 1023) / 41.0))

# a full-screen background for a map without a cover (loading / results screens): the same contours, dim
static func no_cover_bg(song) -> TextureRect:
	var t = TextureRect.new()
	t.anchor_right = 1
	t.anchor_bottom = 1
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m = ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = BANNER_SHADER
	m.set_shader_param("radius", 0.0)
	m.set_shader_param("shade", 0.0)
	t.material = m
	no_cover(t, song)
	t.modulate = Color(0.34, 0.34, 0.34)
	return t

static func stars(song, speed:float) -> float:
	if !song or !ResourceLoader.exists("res://mods/stars/StarCache.gd"): return 0.0
	var sc = load("res://mods/stars/StarCache.gd").get_instance(Engine.get_main_loop())
	return sc.get_stars_at_now(song, speed) if sc else 0.0

static func mmss(ms:float) -> String:
	var s = int(max(0.0, ms) / 1000.0)
	return "%d:%02d" % [s / 60, s % 60]

static func speed_now() -> float:
	return Globals.speed_multi[Rhythia.mod_speed_level] if Rhythia.mod_speed_level != Globals.SPEED_NORMAL else 1.0

static func speed_tag(speed:float) -> String:
	return "" if is_equal_approx(speed, 1.0) else "%sx" % str(stepify(speed, 0.01))

# short mod tags of the mods on now
static func mod_tags() -> Array:
	var out = []
	for m in MODS:
		if Rhythia.get(m[0]): out.append(m[1])
	return out

static func difficulty(song) -> Array: # [name, colour]
	if !song: return ["", Color(1, 1, 1)]
	var n = str(song.custom_data.get("difficulty_name", Globals.difficulty_names.get(song.difficulty, "")))
	return [n, Globals.difficulty_colors.get(song.difficulty, Color(1, 1, 1))]

static func today() -> String:
	var d = OS.get_date()
	return "%d %s %d" % [d.day, MONTHS[d.month - 1], d.year]

# the title logo (a custom skin logo if set; the stock one turns white in the monochrome look)
static func logo(t:TextureRect):
	var sk = load("res://mods/replay/Reimagined.gd").skin_tex("logo")
	t.texture = sk if sk else load("res://assets/images/branding/icon.png")
	if mono() and !sk and _has("grey_material"): t.material = load(LOOK).grey_material()

# text cut to a width with an ellipsis (Label.clip_text cuts mid-letter)
static func fit(text:String, f, w:float) -> String:
	if !f or f.get_string_size(text).x <= w: return text
	var lo = 0
	var hi = text.length()
	while lo < hi: # (longest prefix that fits with the dots)
		var mid = (lo + hi + 1) / 2
		if f.get_string_size(text.substr(0, mid).strip_edges() + "...").x <= w: lo = mid
		else: hi = mid - 1
	return text.substr(0, lo).strip_edges() + "..."

# the player's offline username (NamePanel.gd), else ""
static func player() -> String:
	return str(load("res://mods/replay/Reimagined.gd").val("player_name")).strip_edges()
