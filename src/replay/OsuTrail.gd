extends MultiMeshInstance
# osu!-style cursor trail: soft dots stamped along the cursor's path, each fading and shrinking
# over its lifetime. Drawn as 3D quads just behind the cursor plane (so the cursor stays on top),
# one MultiMesh draw call, additive blending. Colour / opacity / length / size come from
# Rhythia-reimagined settings; the dot image can be replaced by skin slot "trail".

const R = preload("res://mods/replay/Reimagined.gd")
const LIFE = 0.18              # seconds at length 1.0
const MAX_DOTS = 500
const BEHIND = 0.002           # world units behind the cursor

var cursor:Spatial
var cmesh:MeshInstance
var dots:Array = []            # [world position, birth time]
var last = null
var now:float = 0.0
var life:float = LIFE
var alpha:float = 1.0
var size:float = 1.0
var spacing:float = 0.04
var radius:float = 0.1

func _init(c:Spatial = null):
	cursor = c

func _ready():
	var cf = R.cfg()
	life = LIFE * clamp(float(cf.trail_length), 0.2, 4.0)
	alpha = clamp(float(cf.trail_alpha), 0.0, 1.0)
	size = clamp(float(cf.trail_size), 0.2, 3.0)
	spacing = 0.263 * Rhythia.cursor_scale * size * 0.16
	radius = 0.1315 * Rhythia.cursor_scale * 0.8 * size
	var tex = R.skin_tex("trail")
	if !tex: tex = dot_texture()
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.vertex_color_use_as_albedo = true
	m.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	m.params_billboard_mode = SpatialMaterial.BILLBOARD_ENABLED
	m.params_billboard_keep_scale = true
	m.albedo_texture = tex
	m.render_priority = -1
	var q = QuadMesh.new()
	q.size = Vector2(2, 2)
	q.material = m
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.color_format = MultiMesh.COLOR_FLOAT
	mm.mesh = q
	mm.instance_count = MAX_DOTS
	mm.visible_instance_count = 0
	multimesh = mm
	cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	set_as_toplevel(true)
	global_transform = Transform()
	if cursor: cmesh = cursor.get_node_or_null("Mesh")

static func dot_texture() -> Texture:
	if Engine.has_meta("rr_dot"): return Engine.get_meta("rr_dot")
	var img = Image.new()
	img.create(64, 64, false, Image.FORMAT_RGBA8)
	img.lock()
	for y in 64:
		for x in 64:
			var a = clamp(1.0 - Vector2(x - 31.5, y - 31.5).length() / 32.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
	img.unlock()
	var t = ImageTexture.new()
	t.create_from_image(img)
	Engine.set_meta("rr_dot", t)
	return t

func _process(delta):
	if !is_instance_valid(cursor): return
	now += delta
	var p:Vector3 = cursor.global_transform.origin
	if last == null or p.distance_to(last) > 2.5: last = p # first frame / teleport (seek)
	var d = p.distance_to(last)
	if d >= spacing:
		var n = int(d / spacing)
		var dir = (p - last) / d
		for i in range(1, n + 1):
			dots.append([last + dir * spacing * i, now - delta * (1.0 - float(i) / n)])
		last = last + dir * spacing * n
	while dots.size() > 0 and now - dots[0][1] > life: dots.pop_front()
	while dots.size() > MAX_DOTS: dots.pop_front()
	var base = Color(1, 1, 1)
	if cmesh and cmesh.get("material/0"): base = cmesh.get("material/0").albedo_color
	var c = R.trail_color(base)
	var off = Vector3(0, 0, -BEHIND)
	for i in dots.size():
		var q = dots[i]
		var k = clamp(1.0 - (now - q[1]) / life, 0.0, 1.0)
		var rr = radius * (0.45 + 0.55 * k)
		multimesh.set_instance_transform(i, Transform(Basis().scaled(Vector3(rr, rr, rr)), q[0] + off))
		multimesh.set_instance_color(i, Color(c.r, c.g, c.b, k * k * alpha * 0.4))
	multimesh.visible_instance_count = dots.size()
