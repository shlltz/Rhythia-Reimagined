extends MeshInstance
# Cursor glow (Customize > Cursor trail): a soft additive halo just behind the cursor, in the
# cursor's colour. One billboard quad under Spawn/Cursor (one draw call); it follows the cursor's
# colour when that changes during a run (note colour / rainbow cursors). Added by HUD.gd.

const R = preload("res://mods/replay/Reimagined.gd")
const BEHIND = 0.003           # world units behind the cursor (it draws under the cursor)
const SIZE = 2.6               # halo width in cursor widths

var cmesh:MeshInstance
var mat:SpatialMaterial
var strength:float = 0.5
var last:Color = Color(0, 0, 0, 0)

static func texture() -> Texture:
	if Engine.has_meta("rr_glow_tex"): return Engine.get_meta("rr_glow_tex")
	var img = Image.new()
	img.create(64, 64, false, Image.FORMAT_RGBA8)
	img.lock()
	for y in 64:
		for x in 64:
			var r = clamp(Vector2(x - 31.5, y - 31.5).length() / 32.0, 0.0, 1.0)
			var a = 1.0 - r
			img.set_pixel(x, y, Color(1, 1, 1, a * a * a)) # (bright centre, long soft falloff)
	img.unlock()
	var t = ImageTexture.new()
	t.create_from_image(img)
	Engine.set_meta("rr_glow_tex", t)
	return t

func _ready():
	strength = clamp(float(R.val("cursor_glow")), 0.0, 1.0)
	cmesh = get_parent().get_node_or_null("Mesh")
	mat = SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_transparent = true
	mat.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	mat.params_billboard_mode = SpatialMaterial.BILLBOARD_ENABLED
	mat.params_billboard_keep_scale = true
	mat.albedo_texture = texture()
	mat.render_priority = -1
	var q = QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = mat
	mesh = q
	cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var s = 0.263 * Rhythia.cursor_scale * SIZE
	scale = Vector3(s, s, s)
	translation = Vector3(0, 0, -BEHIND)
	_process(0)

func _process(_d):
	var c = Color(1, 1, 1)
	if cmesh and cmesh.get("material/0"): c = cmesh.get("material/0").albedo_color
	if c == last: return
	last = c
	mat.albedo_color = Color(c.r, c.g, c.b, strength * 0.8)
