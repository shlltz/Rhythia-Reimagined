extends Spatial
# perf mod: identical visuals; idle trail pieces stop processing and node/material lookups are cached

signal cache_me

export(float) var offset = 0

var started:bool = false
var t:float = 0

onready var cursor = get_node("../Spawn/Cursor")
onready var cursormesh = get_node("../Spawn/Cursor/Mesh")
onready var mesh:MeshInstance = $Mesh
var mat:SpatialMaterial

var last_origin = Vector3(-100,0,0)
var before
var can_reuse:bool = false
var transp_multi = 1
# Rhythia-reimagined: trail colour / opacity, hidden when another trail style is chosen
var rr_color = null
var rr_alpha:float = 1.0

func _ready():
	set_process(started)

func respawn(t_override=null,rot=0):
	if t_override:
		visible = true
		global_transform.origin = t_override
		mesh.rotation_degrees.x = rot
	else:
		visible = (cursor.global_transform.origin - Vector3(0,0,0.001)) != last_origin
		global_transform.origin = cursor.global_transform.origin - Vector3(0,0,0.001)
		if Input.is_key_pressed(KEY_V):
			global_transform.origin = Vector3((offset*3)-1.5,(offset*3)-1.5,-0.2)
	
	mat.albedo_color = cursormesh.get("material/0").albedo_color if rr_color == null else rr_color
	mat.albedo_color.a *= rr_alpha
	mesh.rotation = cursormesh.rotation

func upd_dumb(delta):
	if !Rhythia.smart_trail:
		t += (delta/Rhythia.trail_time)
	var a = clamp((t - 0.2),0,1)
	if Rhythia.trail_mode_opacity:
		mat.albedo_color.a = a * 0.6 * transp_multi * rr_alpha
	if Rhythia.trail_mode_scale:
		mesh.scale = Vector3(a*Rhythia.cursor_scale,1,a*Rhythia.cursor_scale)
	if !Rhythia.smart_trail and t >= 1:
		t -= 1
		respawn()

func update(delta):
	t -= (delta/Rhythia.trail_time)
	var a = clamp((t),0,1)
	if Rhythia.trail_mode_opacity:
		mat.albedo_color.a = a * 0.6 * transp_multi * rr_alpha
	if Rhythia.trail_mode_scale:
		mesh.scale = Vector3(a*Rhythia.cursor_scale,1,a*Rhythia.cursor_scale)
	if t <= 0:
		started = false
		visible = false
		set_process(false)
		emit_signal("cache_me")

func _process(delta):
	if started:
		if Rhythia.smart_trail: update(delta)
		else: upd_dumb(delta)

var init_done:bool = false
func init():
	if mesh == null: mesh = $Mesh
	if init_done: return
	init_done = true
	mat = mesh.get("material/0").duplicate()
	mesh.scale = Vector3(0,1,0)
	if not Rhythia.trail_mode_scale:
		mesh.scale = Vector3(Rhythia.cursor_scale,1,Rhythia.cursor_scale)
	mesh.set("material/0",mat)
	if ResourceLoader.exists("res://mods/replay/Reimagined.gd"):
		var cf = load("res://mods/replay/Reimagined.gd").cfg()
		if cf.trail_style != "game": mesh.visible = false
		if str(cf.trail_color) != "": rr_color = Color(cf.trail_color)
		rr_alpha = clamp(float(cf.trail_alpha), 0.0, 1.0)

func start():
	init()
	t = -offset
	started = true
	set_process(true)


func start_smart(v:float,pos:Vector3,rot:float):
	init()
	started = true
	set_process(true)
	t = 1 - v
	respawn(pos,rot)
