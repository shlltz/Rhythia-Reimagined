extends Control
# Small "[star] 8.77  172 BPM" badge ("150-180 BPM" when the tempo changes). The star is drawn (the UI font has no star glyph).
# Fills itself in when StarCache finishes rating the map.

var song = null
var key:String = ""
var stars:float = -1.0
var bpm:float = -1.0
var bpm_range:Array = []
var speed:float = 1.0
var font:Font = null
var cache = null
var align_left:bool = false
var suffix:String = ""
var from_stars:float = -1.0
var anim:float = 0.0 # 1 -> 0 after a speed change: the number counts to the new rating, the star pops
var pill:bool = true # dark backdrop so the star colour reads on any button

# speed != 1: rating of the map played at that speed (computed immediately)
func _ready():
	set_process(anim > 0)

func _process(delta):
	anim = max(0.0, anim - delta / 0.7)
	if anim <= 0: set_process(false)
	update()

func set_song(s, f:Font = null, spd:float = 1.0):
	var prev_key = key
	var prev = stars
	song = s
	speed = spd
	font = f
	suffix = ""
	if cache and cache.is_connected("rated", self, "_on_rated"):
		cache.disconnect("rated", self, "_on_rated")
	mouse_filter = MOUSE_FILTER_IGNORE
	cache = load("res://mods/stars/StarCache.gd").get_instance(get_tree() if is_inside_tree() else Engine.get_main_loop())
	key = cache.key_of(song)
	if cache.is_connected("rated_at", self, "_on_rated_at"): cache.disconnect("rated_at", self, "_on_rated_at")
	if is_equal_approx(speed, 1.0):
		stars = cache.get_stars(song)
	else:
		stars = cache.get_stars_at(song, speed)
		suffix = " (%sx)" % str(stepify(speed, 0.01))
		if stars < 0: # computing on the worker: keep showing the old number, animate when it lands
			cache.connect("rated_at", self, "_on_rated_at", [cache.memo_key(song, speed)])
			if prev_key == key and prev >= 0: stars = prev
	if prev_key == key and prev >= 0 and stars >= 0 and abs(stars - prev) > 0.005: # same map, new speed
		from_stars = prev
		anim = 1.0
		set_process(true)
	bpm = cache.get_bpm(song)
	bpm_range = cache.get_bpm_range(song)
	if (stars < 0 or bpm < 0) and !cache.is_connected("rated", self, "_on_rated"):
		cache.connect("rated", self, "_on_rated")
	update()

func _on_rated_at(mk, v, want):
	if mk != want: return
	cache.disconnect("rated_at", self, "_on_rated_at")
	if stars >= 0 and abs(v - stars) > 0.005:
		from_stars = stars
		anim = 1.0
		set_process(true)
	stars = v
	update()

func _on_rated(k, v):
	if k != key: return
	if is_equal_approx(speed, 1.0): stars = v
	bpm = cache.get_bpm(song)
	bpm_range = cache.get_bpm_range(song)
	cache.disconnect("rated", self, "_on_rated")
	update()

func _exit_tree():
	if cache and cache.is_connected("rated", self, "_on_rated"):
		cache.disconnect("rated", self, "_on_rated")
	if cache and cache.is_connected("rated_at", self, "_on_rated_at"):
		cache.disconnect("rated_at", self, "_on_rated_at")

static func star_points(c:Vector2, r:float) -> PoolVector2Array:
	var pts = PoolVector2Array()
	for i in range(10):
		var a = -PI / 2 + i * PI / 5
		var rr = r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts

func _draw():
	var f:Font = font if font else get_font("font", "Label")
	var sv = stars if anim <= 0 or from_stars < 0 else lerp(stars, from_stars, anim * anim)
	var txt = ("..." if stars < 0 else "%.2f" % sv) + suffix
	var btxt = ""
	if bpm > 0:
		btxt = "   %d BPM" % int(round(bpm * speed))
		if bpm_range.size() == 2 and int(round(bpm_range[0] * speed)) != int(round(bpm_range[1] * speed)):
			btxt = "   %d-%d BPM" % [int(round(bpm_range[0] * speed)), int(round(bpm_range[1] * speed))]
	var h = rect_size.y
	var r = h * 0.42
	var sw = f.get_string_size(txt).x
	var tw = sw + (f.get_string_size(btxt).x if btxt != "" else 0.0)
	var x0 = 0.0 if align_left else rect_size.x - tw - r * 2 - 4
	var col = Color(0.6, 0.6, 0.6) if stars < 0 else load("res://mods/stars/StarCache.gd").color_for(sv)
	if pill:
		x0 += 6 if align_left else -10
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.7)
		sb.set_corner_radius_all(int(h / 2))
		draw_style_box(sb, Rect2(x0 - 6, 0, tw + r * 2 + 4 + 18, h))
	var c = Vector2(x0 + r, h / 2)
	if anim > 0 and stars > from_stars: # rating went up: glow burst behind the star
		draw_circle(c, r * (1.2 + 1.3 * (1.0 - anim)), Color(col.r, col.g, col.b, 0.45 * anim))
	var rs = r * (1.0 + 0.35 * anim)
	draw_colored_polygon(star_points(c + Vector2(1, 1), rs), Color(0, 0, 0, 0.6))
	draw_colored_polygon(star_points(c, rs), col)
	var base = (h - f.get_height()) / 2 + f.get_ascent()
	draw_string(f, Vector2(x0 + r * 2 + 4 + 1, base + 1), txt, Color(0, 0, 0, 0.6))
	draw_string(f, Vector2(x0 + r * 2 + 4, base), txt, Color(1, 1, 1))
	if btxt != "":
		var bx = x0 + r * 2 + 4 + sw
		draw_string(f, Vector2(bx + 1, base + 1), btxt, Color(0, 0, 0, 0.6))
		draw_string(f, Vector2(bx, base), btxt, Color(1, 1, 1, 0.7))
