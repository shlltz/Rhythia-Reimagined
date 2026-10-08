extends Spatial
class_name NoteManager

signal ms_change
signal timer_update
signal hit
signal miss

export(Material) var note_solid_mat
export(Material) var note_transparent_mat
export(Material) var asq_mat

var approach_rate:float = Rhythia.get("approach_rate")
var hit_window:float = Rhythia.get("hitwindow_ms")
var speed_multi:float = Globals.speed_multi[Rhythia.mod_speed_level]
var ms:float = Rhythia.start_offset - (3000 * speed_multi) # make waiting time shorter on lower speeds
var notes_loaded:bool = false
var hitsync_ensured:bool = false

var active:bool = false

var noteNodes:Array = []
var noteCache:Array = []
var noteQueue:Array = []
var colors:Array = Rhythia.selected_colorset.colors
var hitEffect:Spatial = load(Rhythia.selected_hit_effect.path).instance()
var missEffect:Spatial = load(Rhythia.selected_miss_effect.path).instance()
var scoreEffect:Spatial = load("res://assets/notefx/score/score.tscn").instance()
var hit_id:String = Rhythia.selected_hit_effect.id
var miss_id:String = Rhythia.selected_miss_effect.id
var chaos_rng:RandomNumberGenerator = RandomNumberGenerator.new()
var earthquake_rng:RandomNumberGenerator = RandomNumberGenerator.new()

var matcache_hit:Dictionary = {}
var matcache_miss:Dictionary = {}

const base_position = Vector3(-1,1,0)

var prev_ms:float = -100000

var next_ms:float = 0

var last_cursor_position:Vector3 = Vector3(-1,1,0)


# new mmi note stuff
var fade_in_enabled:bool = true
var fade_in_start:float = 8
var fade_in_end:float = 6

var fade_out_enabled:bool = false
var fade_out_start:float = 3
var fade_out_end:float = 1

var fade_out_base:float = 1


var notes:Array = []
var current_note:int = 0
var note_transform_scale:Vector3

var grid_pushback:float = 0.1 # default 0.1
var pushback_defaults:Dictionary = {
	"do_pushback": 4,
	"never": 0.1
}

func linstep(a:float,b:float,x:float):
	if a == b: return float(x >= a)
	return clamp(((x - a) / (b - a)),0,1)

# perf mod: settings and nodes used per note per frame, looked up once
var c_spawn_distance:float = 0
var c_spawn_effect:bool = false
var c_chaos:bool = false
var c_earthquake:bool = false
var c_note_size:float = 1
var c_note_opacity:float = 1
var c_approach_follow:bool = false
var c_ghost:bool = false
var c_spin_x:float = 0
var c_spin_y:float = 0
var c_spin_z:float = 0
onready var notes_mm_node = $Notes
onready var asq_node = $ASq
onready var spawnfx_node = $SpawnEffect

func cache_settings():
	$Label.text = ""
	c_spawn_distance = Rhythia.get("spawn_distance")
	c_spawn_effect = Rhythia.note_spawn_effect
	c_chaos = Rhythia.mod_chaos
	c_earthquake = Rhythia.mod_earthquake
	c_note_size = Rhythia.note_size
	c_note_opacity = Rhythia.note_opacity
	c_approach_follow = Rhythia.visual_approach_follow
	c_ghost = Rhythia.mod_ghost
	c_spin_x = Rhythia.note_spin_x
	c_spin_y = Rhythia.note_spin_y
	c_spin_z = Rhythia.note_spin_z

func note_reposition(i:int):
	var real_position:Vector2 = notes[i][0]
	var notems:float = notes[i][1]
	var state:int = notes[i][2]
	var col:Color = notes[i][3]
	var chaos_offset:Vector2 = notes[i][4]
	var nt:Transform = notes[i][5]
	
	var approachSpeed:float = approach_rate / speed_multi
	
	var current_offset_ms:float = notems - ms
	var current_dist:float = approachSpeed*current_offset_ms/1000
	
	if (
		(current_dist <= c_spawn_distance and current_dist >= (grid_pushback * -1) and sign(approachSpeed) == 1) or
		(current_dist >= -50 and current_dist <= 0.1 and sign(approachSpeed) == -1) or
		sign(approachSpeed) == 0
	) and state == Globals.NSTATE_ACTIVE: # state 2 = miss # and current_dist >= -0.5
		
#		if !was_visible:
#			was_visible = true
#			if c_spawn_effect:
#				if !Rhythia.mod_nearsighted: spawn_effect_t = 1
		
		
		nt.origin.z = -current_dist
#		visible = true
		
		var spawn_effect_t = 1 - clamp(4*(c_spawn_distance - current_dist)/c_spawn_distance, 0, 1)
		if c_spawn_effect:
			spawnfx_node.multimesh.set_instance_color(i - current_note, Color(col.r, col.g, col.b, col.a))
			if spawn_effect_t != 0:
				var effect_transform = Transform.IDENTITY
				effect_transform.origin = nt.origin
				effect_transform.basis = effect_transform.basis.scaled(Vector3.ONE * 1 * c_note_size)
				effect_transform.basis = effect_transform.basis.scaled(Vector3(1*spawn_effect_t, 0.9 + (0.1*spawn_effect_t), 1))
				effect_transform.basis = effect_transform.basis.rotated(Vector3(1,0,0), deg2rad(90))
				spawnfx_node.multimesh.set_instance_transform(i - current_note, effect_transform)
			else: spawnfx_node.multimesh.set_instance_transform(i - current_note, Transform.IDENTITY.scaled(Vector3.ZERO))
		
		if c_chaos:
			var v = ease(max((current_offset_ms-250)/400,0),1.5)
			nt.origin.x = real_position.x + (chaos_offset.x * v)	
			nt.origin.y = real_position.y + (chaos_offset.y * v)
		
		if c_earthquake:
			var rcoord = Vector2(earthquake_rng.randf_range(-0.25,0.25),earthquake_rng.randf_range(-0.25,0.25))
			nt.origin.x = real_position.x + (rcoord.x * (current_dist * 0.1))
			nt.origin.y = real_position.y + (rcoord.y * (current_dist * 0.1))

#		if Rhythia.note_visual_approach:
#			$Approach.opacity = 1 - (current_dist / c_spawn_distance)
#
#			$Approach.scale.x = 0.4 * ((current_dist / c_spawn_distance) + 0.6)
#			$Approach.scale.y = 0.4 * ((current_dist / c_spawn_distance) + 0.6)
#
#			$Approach.global_translation.z = 0
			
		# note spin; not doing this all in a single Vector3 because we're trying to rotate locally
		if c_spin_x != 0: nt.basis = nt.basis.rotated(Vector3(1,0,0),c_spin_x / 2000)
		if c_spin_y != 0: nt.basis = nt.basis.rotated(Vector3(0,1,0),c_spin_y / 2000)
		if c_spin_z != 0: nt.basis = nt.basis.rotated(Vector3(0,0,1),c_spin_z / 2000)
		
		var alpha:float = c_note_opacity
		var fade_in:float = 1
		var fade_out:float = 1
		
		if fade_in_enabled or fade_out_enabled:
			
			if fade_in_enabled: 
				fade_in = (pow(linstep(fade_in_start,fade_in_end,current_dist), 1.3)) * c_note_opacity
			if fade_out_enabled:
				fade_out = ((1 - fade_out_base) + (pow(linstep(fade_out_end,fade_out_start,current_dist), 1.3) * fade_out_base)) * c_note_opacity
			
			alpha = min(fade_in,fade_out)
		
		
		notes_mm_node.multimesh.set_instance_transform(i - current_note, nt)
		notes_mm_node.multimesh.set_instance_color(i - current_note, Color(col.r, col.g, col.b, col.a * alpha))
		if asq:
			var sc = (linstep(0,c_spawn_distance,current_dist) + 0.6) * 0.4
			
			var at = Transform()
			at = at.scaled(Vector3(sc,sc,sc))
			at.origin = nt.origin#Vector3(nt.origin.x, nt.origin.y, 0)
			if !c_approach_follow:
				at.origin.z = 0
			
			asq_node.multimesh.set_instance_transform(i - current_note, at)
			if c_ghost:
				asq_node.multimesh.set_instance_color(i - current_note, Color(1,1,1,1 * alpha))
			else:
				asq_node.multimesh.set_instance_color(i - current_note, Color(1,1,1,pow(linstep(c_spawn_distance,0,current_dist),1.7)))
		
#		$Label.text += "(%.02f: %s -> %s = %s) %s\n" % [current_dist,fade_in_start,fade_in_end,fade_in,alpha]
		
		return true
	else:
		notes_mm_node.multimesh.set_instance_transform(i - current_note, Transform(Basis(), Vector3(0, 0, 10)))
		notes_mm_node.multimesh.set_instance_color(i - current_note, Color(0,0,0,0))
		if asq:
			asq_node.multimesh.set_instance_transform(i - current_note, Transform(Basis(), Vector3(0, 0, 10)))
			asq_node.multimesh.set_instance_color(i - current_note, Color(0,0,0,0))
		if c_spawn_effect:
			spawnfx_node.multimesh.set_instance_transform(i - current_note, Transform(Basis(), Vector3(0, 0, 10)))
			spawnfx_node.multimesh.set_instance_color(i - current_note, Color(0,0,0,0))
#		if Rhythia.play_hit_snd and Rhythia.ensure_hitsync: 
#			if Rhythia.sfx_2d:
#				$"../Hit2D".play()
#			else:
#				$"../Hit".transform = transform
#				$"../Hit".play()
#		visible = false
		return false#!(state == Globals.NSTATE_ACTIVE and sign(approachSpeed) == 1 and current_dist > 100)

func note_check_collision(i:int):
	var cpos:Vector3 = $Cursor.transform.origin
	
	if Rhythia.replaying and Rhythia.replay.sv != 1:
		return Rhythia.replay.should_hit(i)
	else:
		var hbs:float = Rhythia.note_hitbox_size/2
		if hbs == 0.57: hbs = 0.56875 # 1.1375
		var ori:Vector2 = notes[i][0]
		if (cpos.x <= ori.x + hbs and cpos.x >= ori.x - hbs) and (cpos.y <= ori.y + hbs and cpos.y >= ori.y - hbs):
			return true
		return sweep_on and !Rhythia.replaying and _swept_hit(i, ori, hbs)

# Swept hitbox (Rhythia-reimagined, Customize > Gameplay). Stock Sound Space (and the Rhythia
# rewrite, same 1.14 box / 55 ms window) only tests where the cursor IS on each frame, so a fast
# flick that crosses a note between two frames never counts - worse at low fps / on phones.
# This also tests the straight path the cursor travelled since the last frame, limited to the
# part of that frame inside the note's hit window. Same box, same window: only the gaps between
# frames are closed. Replays store their hit results, so they play back the same either way.
var sweep_on:bool = false
var sweep_from:Vector2 = Vector2()
var sweep_from_ms:float = -1e9
var sweep_to:Vector2 = Vector2()
var sweep_to_ms:float = -1e9

func _sweep_frame():
	var cp:Vector3 = $Cursor.transform.origin
	if ms < sweep_to_ms: # rewind / restart: no path to sweep
		sweep_to_ms = -1e9
	if ms > sweep_to_ms:
		sweep_from = sweep_to
		sweep_from_ms = sweep_to_ms
		sweep_to_ms = ms
	sweep_to = Vector2(cp.x, cp.y)

func _swept_hit(i:int, ori:Vector2, hbs:float) -> bool:
	var span = sweep_to_ms - sweep_from_ms
	if span <= 0.0 or span > 100.0 * max(speed_multi, 1.0): return false # first frame / long hitch
	var nms:float = notes[i][1]
	var t0 = clamp((nms - sweep_from_ms) / span, 0.0, 1.0)
	var t1 = clamp((nms + hit_window - sweep_from_ms) / span, 0.0, 1.0)
	if t1 <= t0: return false
	return _segment_hits_box(sweep_from.linear_interpolate(sweep_to, t0), sweep_from.linear_interpolate(sweep_to, t1), ori, hbs)

# does the segment a-b touch the square centred on c with half size h (slab test)
static func _segment_hits_box(a:Vector2, b:Vector2, c:Vector2, h:float) -> bool:
	var d = b - a
	var lo = 0.0
	var hi = 1.0
	for ax in 2:
		var p = a.x if ax == 0 else a.y
		var dd = d.x if ax == 0 else d.y
		var mn = (c.x if ax == 0 else c.y) - h
		var mx = (c.x if ax == 0 else c.y) + h
		if abs(dd) < 0.000001:
			if p < mn or p > mx: return false
		else:
			var u0 = (mn - p) / dd
			var u1 = (mx - p) / dd
			if u0 > u1:
				var s = u0; u0 = u1; u1 = s
			lo = max(lo, u0)
			hi = min(hi, u1)
			if lo > hi: return false
	return true

var asq = Rhythia.note_visual_approach
var last_reposition_ms:float = -10000
var out_of_notes:bool = false
func reposition_notes(force:bool=false,rerun_start:int=-1):
	var rerun_required:bool = false
	c_spawn_distance = Rhythia.get("spawn_distance")
#	force = force or OS.has_feature("debug")
	if current_note == notes.size():
#		$Label.text += "out_of_notes\n"
		notes_mm_node.multimesh.visible_instance_count = 0
		if asq: asq_node.multimesh.visible_instance_count = 0
		if c_spawn_effect: spawnfx_node.multimesh.visible_instance_count = 0
		out_of_notes = true
		return false
	
	var note_passed:bool = false
	var is_first:bool = true
	
#	$Label.text += "ms: %s\n\n" % [ ms ]
#	$Label.text += "current: %s\n" % [ current_note ]
#	$Label.text += "total: %s\n" % [ notes.size() ]
#	$Label.text += "visible: %s\n" % [ notes_mm_node.multimesh.visible_instance_count ]
	
	if last_reposition_ms > ms:
#		$Label.text += "rewind detected\n"
		print("rewind detected")
		for i in range(0, notes.size()):
			if notes[i][1] > ms:
				current_note = max(i - 1, 0)
				break
	
	last_reposition_ms = ms
	_sweep_frame()
	
	for i in range(max(current_note,rerun_start), notes.size()):
		var notems:float = notes[i][1]
		next_ms = notems
		if force:
#			if is_first: $Label.text += "force\n"
			note_reposition(i)
		else:
			if note_reposition(i) == false:
#				$Label.text += "(%s) reposition == false\n" % [ i ]
				notes_mm_node.multimesh.visible_instance_count = i - current_note + 1
				if asq: asq_node.multimesh.visible_instance_count = i - current_note + 1
				if c_spawn_effect: spawnfx_node.multimesh.visible_instance_count = i - current_note
				if ms < notems:
#					$Label.text += "(%s) note is end of visible area\n" % [ i ]
					if notes[i][2] == Globals.NSTATE_ACTIVE:
						return note_passed
		
		if (i - current_note + 2) > notes_mm_node.multimesh.instance_count:
			rerun_required = true
			notes_mm_node.multimesh.instance_count = min(notes_mm_node.multimesh.instance_count + 10, notes.size())
			if asq: asq_node.multimesh.instance_count = notes_mm_node.multimesh.instance_count
			if c_spawn_effect: spawnfx_node.multimesh.instance_count = notes_mm_node.multimesh.instance_count
			break
		
		if ms < notems and is_first:
			is_first = false
#			$Label.text += "next_ms: %s\n" % [ notems ]
#			next_ms = notems
		elif ms >= notems and notes[i][2] == Globals.NSTATE_ACTIVE:
			var result = Rhythia.visual_mode or note_check_collision(i)

			if !result and (ms > notems + hit_window or pause_state == -1):
#				$Label.text += "MISS %s @ %s\n" % [ i, ms ]
#				note_passed = true
				# notes should not be in the hitwindow if the game is paused
				if !Rhythia.replaying and Rhythia.record_replays:
					Rhythia.replay.note_miss(i)
				notes[i][2] = Globals.NSTATE_MISS
				if Rhythia.play_miss_snd: 
					if Rhythia.sfx_2d:
						$Miss2D.play()
					else:
						$Miss.transform = notes[i][5]
						$Miss.play()
				if Rhythia.show_miss_effect:
					var pos:Vector3 = Vector3(
						notes[i][5].origin.x,
						notes[i][5].origin.y,
						0.002
					)

					missEffect.duplicate().spawn(self,pos,notes[i][3],miss_id,true)
				emit_signal("miss",notes[i][3])
				prev_ms = notems
			elif result:
#				$Label.text += "HIT %s @ %s\n" % [ i, ms ]
#				note_passed = true
				if !Rhythia.replaying and Rhythia.record_replays:
					Rhythia.replay.note_hit(i)
				notes[i][2] = Globals.NSTATE_HIT
#				if Rhythia.play_hit_snd and !Rhythia.ensure_hitsync:
#					var sfx
#					if Rhythia.sfx_2d:
#						sfx = $Hit2D.duplicate()
#						add_child(sfx)
#					else:
#						sfx = $Hit.duplicate()
#						add_child(sfx)
#						sfx.transform = notes[i][5]
#					sfx.connect("finished", sfx, "queue_free")
#					if Rhythia.hit_pitch: sfx.pitch_scale = rand_range(Rhythia.hit_pitch_min,Rhythia.hit_pitch_max)
				if Rhythia.play_hit_snd:
					SFXManager.play_hitsfx(notes[i][5])
				var pos:Vector3 = Vector3(
					$Cursor.global_transform.origin.x,
					$Cursor.global_transform.origin.y,
					0.002
				)
				if Rhythia.show_hit_effect and !Rhythia.visual_mode:
					if !Rhythia.hit_effect_at_cursor:
						pos.x = (global_transform * notes[i][5]).origin.x
						pos.y = (global_transform * notes[i][5]).origin.y

					hitEffect.duplicate().spawn(get_parent(),pos,notes[i][3],hit_id,false)
				emit_signal("hit",notes[i][3])
				var score:int = get_parent().hit(notes[i][3])
				if Rhythia.score_popup:
					scoreEffect.duplicate().spawn(get_parent(),pos,notes[i][3],score)

				prev_ms = notems
		elif ms > (notems + hit_window) + 100:
#			$Label.text += "PASS %s\n" % [ i ]
		
			current_note = i + 1
#	$Label.text += "last note is visible!"
	notes_mm_node.multimesh.visible_instance_count = notes.size() - current_note
	if asq: asq_node.multimesh.visible_instance_count = notes.size() - current_note
	if c_spawn_effect: spawnfx_node.multimesh.instance_count = notes.size() - current_note
	
	if rerun_required: reposition_notes()
	return note_passed

var color_index:int = 0
var note_count:int = 0

func sort_note_nodes(a,b):
	return a.notems < b.notems

func sort_note_queue(a,b):
	return a[2] < b[2]

func spawn_notes(note_array:Array):
	note_array.sort_custom(self,"sort_note_queue")
	
	var nscale = 0.45 * Rhythia.note_size * (Rhythia.note_hitbox_size / 1.14)
	note_transform_scale = Vector3(nscale, nscale, nscale)
	
	next_ms = note_array[0][2]
	var colorset:Array = Rhythia.selected_colorset.colors
	for i in range(note_array.size()):
		var data:Array = note_array[i]
		if (data[2] >= Rhythia.start_offset):
			var note:Array = [
				Vector2(data[0], -data[1]), # position
				
				data[2], # notems
				
				Globals.NSTATE_ACTIVE, # state
				
				colorset[i % colorset.size()], # color
				
				Vector2( # chaos offset
					chaos_rng.randf_range(-1,1),
					chaos_rng.randf_range(-1,1)
				).normalized() * 2,
				
				Transform() # note transform
			]
			
			if Rhythia.mod_hardrock: note[0] = ((note[0] - Vector2(1,-1)) * 1.35) + Vector2(1,-1)
			if Rhythia.mod_mirror_x: note[0].x = 2 - note[0].x
			if Rhythia.mod_mirror_y: note[0].y = (-note[0].y) - 2
			note[5] = note[5].scaled(note_transform_scale)
			note[5].origin = Vector3(note[0].x,note[0].y,4)
			
			
			notes.append(note)
	
	var last_ms = note_array[-1][2]
	var inst_count = max(35,ceil(10000 * (float(notes.size()) / float(last_ms))))
	$Notes.multimesh.instance_count = inst_count
	if asq:
		$ASq.multimesh.instance_count = inst_count
		
	notes_loaded = true
	call_deferred("reposition_notes",true)


func _ready():
	cache_settings()
	if ResourceLoader.exists("res://mods/replay/Reimagined.gd"):
		sweep_on = bool(load("res://mods/replay/Reimagined.gd").val("swept_hitbox"))
	if Rhythia.do_note_pushback:
		grid_pushback = pushback_defaults.do_pushback
	else:
		grid_pushback = pushback_defaults.never

	if Rhythia.speed_hitwindow:
		hit_window = Rhythia.get("hitwindow_ms") * speed_multi
	
	if Rhythia.mod_hardrock:
		hit_window = hit_window * 0.8

	$Note.speed_multi = speed_multi
	$Music.pitch_scale = speed_multi
	# reset any pitch shift
	if AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Music")) > 0:
		AudioServer.remove_bus_effect(AudioServer.get_bus_index("Music"),0)
	if Rhythia.retain_song_pitch and not speed_multi == 1.0 :
		var shift = AudioEffectPitchShift.new()
		shift.pitch_scale = 1.0 / speed_multi
		AudioServer.add_bus_effect(AudioServer.get_bus_index("Music"),shift)
	$Miss.stream = Rhythia.miss_snd
#	$Hit.stream = Rhythia.hit_snd
	$Miss2D.stream = Rhythia.miss_snd
#	$Hit2D.stream = Rhythia.hit_snd
	SFXManager.setup()
	
	
	if !Rhythia.replaying and Rhythia.record_replays:
		Rhythia.replay = Replay.new()
		Rhythia.replay.start_recording(Rhythia.selected_song)
	
	if Rhythia.replaying and !Rhythia.replay.autoplayer and !Rhythia.queue_active:
		replay_viewer = load("res://mods/replay/ReplayViewer.gd").new()
		replay_viewer.spawn = self
		add_child(replay_viewer)
	
	chaos_rng.seed = hash(Rhythia.selected_song.id)
	earthquake_rng.seed = hash(Rhythia.selected_song.id)
	
	
	if Rhythia.mod_ghost:
		fade_out_enabled = true
		fade_out_start = ((18.0/50)*approach_rate)
		fade_out_end = ((6.0/50.0)*approach_rate)
		
	elif Rhythia.half_ghost:
		fade_out_enabled = true
		# Rhythia-reimagined: adjustable fade length (Customize > Interface), 1.0 = stock 12 -> 3
		var hg_len = 1.0
		if ResourceLoader.exists("res://mods/replay/Reimagined.gd"):
			hg_len = clamp(float(load("res://mods/replay/Reimagined.gd").val("half_ghost_length")), 0.1, 4.0)
		fade_out_end = ((3.0/50.0)*approach_rate)
		fade_out_start = fade_out_end + ((9.0/50.0)*approach_rate) * hg_len
		fade_out_base = 0.8
	
	if Rhythia.mod_nearsighted:
		fade_in_enabled = true
		fade_in_start = ((30.0/50.0)*approach_rate)
		fade_in_end = ((5.0/50.0)*approach_rate)
	else:
		fade_in_enabled = Rhythia.get("fade_length") != 0
		if Rhythia.get("fade_length") != 0: 
			fade_in_start = Rhythia.get("spawn_distance")
			fade_in_end = Rhythia.get("spawn_distance")*(1.0 - Rhythia.get("fade_length"))
	
	
	$Notes.multimesh = MultiMesh.new()
	$Notes.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	$Notes.multimesh.color_format = MultiMesh.COLOR_FLOAT
	$Notes.multimesh.instance_count = 1
	if asq:
		$ASq.multimesh = MultiMesh.new()
		$ASq.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		$ASq.multimesh.color_format = MultiMesh.COLOR_8BIT
		$ASq.multimesh.mesh = QuadMesh.new()
		$ASq.multimesh.mesh.size = Vector2(3.35,3.35)
		$ASq.multimesh.mesh.surface_set_material(0,asq_mat)
		$ASq.multimesh.instance_count = 1
	else:
		$ASq.visible = false
	
	
	var mesh:Mesh
	if "user://" in Rhythia.selected_mesh.path:
		var m = ObjParse.load_obj(Rhythia.selected_mesh.path)
		if m != null:
			mesh = m
		else:
			mesh = load("res://assets/blocks/rounded.obj")
	else:
		mesh = load(Rhythia.selected_mesh.path)
	
	
	var img = Globals.imageLoader.load_if_exists("user://note")
	if img:
		note_solid_mat.set_shader_param("image",img)
		note_transparent_mat.set_shader_param("image",img)
		note_solid_mat.set_shader_param("use_image",true)
		note_transparent_mat.set_shader_param("use_image",true)
	
	mesh.surface_set_material(0,note_solid_mat)
	if mesh.get_surface_count() > 1:
		mesh.surface_set_material(1,note_transparent_mat)
	if mesh.get_surface_count() > 2:
		mesh.surface_set_material(2,note_solid_mat)
		
	$Notes.multimesh.mesh = mesh
	
	# setup for effects (user://hit and user://miss images)
	if hitEffect.has_method("setup"): hitEffect.setup(hit_id,false)
	hitEffect.visible = false
	add_child(hitEffect)
	
	if missEffect.has_method("setup"): missEffect.setup(miss_id,true)
	missEffect.visible = false
	add_child(missEffect)
	
	# force everything to be loaded now
	yield(get_tree(),"idle_frame")
	hitEffect.duplicate().spawn(get_parent(),Vector3(0,0,-400),Color(1,1,1),hit_id,false)
	missEffect.duplicate().spawn(self,Vector3(0,0,-400),Color(1,1,1),miss_id,true)
	$Notes.multimesh.set_instance_color(0,Color(0,0,0,0))
	$Notes.multimesh.set_instance_transform(0,Transform())
	if asq:
		$ASq.multimesh.set_instance_color(0,Color(0,0,0,0))
		$ASq.multimesh.set_instance_transform(0,Transform())
	if Rhythia.note_spawn_effect:
		$SpawnEffect.multimesh.set_instance_transform(0, Transform(Basis(), Vector3(0, 0, 10)))
		$SpawnEffect.multimesh.set_instance_color(0, Color(0,0,0,0))
	$Note.visible = true
	$Note.transform.origin = Vector3(0,0,-400)
	yield(get_tree(),"idle_frame")
	$Note.visible = false
	
	# Precache notes
#	if Rhythia.visual_mode: # Precache a bunch of notes, because we're probably going to need them
#		for i in range(800):
#			var n = $Note.duplicate()
#			noteCache.append(n)
##			add_child(n)
#	else:
#		for i in range(25):
#			var n = $Note.duplicate()
#			noteCache.append(n)

var music_started:bool = false
const cursor_offset = Vector3(1,-1,0)
onready var cam:Camera = get_node("../..").get_node("Camera")
var hlpower = (0.1 * Rhythia.get("parallax"))
onready var Grid = get_node("../HUD")

func do_half_lock():
	var cursorpos = $Cursor.transform.origin
	if Rhythia.follow_drift_cursor:
		cursorpos += $Cursor/Mesh2.transform.origin
	var centeroff = cursorpos - cursor_offset
	var hlm = 0.25
	var uim = Rhythia.get("ui_parallax") * 0.1
	var grm = Rhythia.get("grid_parallax") * 0.1
	cam.transform.origin = Vector3(
		centeroff.x*hlpower*hlm, centeroff.y*hlpower*hlm, 3.75
	)
	Grid.transform.origin = Vector3(
		-centeroff.x*hlm*uim, -centeroff.y*hlm*uim, Grid.transform.origin.z
	)
	transform.origin = Vector3(
		-(centeroff.x*hlm*grm)-1, -(centeroff.y*hlm*grm)+1, 0
	)

var sh:Vector2 = Vector2(-0.5,-0.5)
var edgec:float = 0
func do_spin():
	var centeroff = get_node("../..").get_node("SpinPos").global_transform.origin + cursor_offset
	
	var cx = centeroff.x
	var cy = -centeroff.y
	cx = clamp(cx, (0 + sh.x + edgec), (3 + sh.x - edgec))
	cy = clamp(cy, (0 + sh.y + edgec), (3 + sh.y - edgec))
	centeroff.x = cx - cursor_offset.x
	centeroff.y = -cy - cursor_offset.y
	
	var hlm = 0.25
	var uim = Rhythia.get("ui_parallax") * 0.1
	var grm = Rhythia.get("grid_parallax") * 0.1
	Grid.transform.origin = Vector3(
		-centeroff.x*hlm*uim, -centeroff.y*hlm*uim, Grid.transform.origin.z
	)
	transform.origin = Vector3(
		-(centeroff.x*hlm*grm)-1, -(centeroff.y*hlm*grm)+1, 0
	)

func do_vr_cursor():
	var centeroff = Rhythia.vr_player.primary_ray.get_collision_point() + cursor_offset
	
	var cx = centeroff.x
	var cy = -centeroff.y
	cx = clamp(cx, (0 + sh.x + edgec), (3 + sh.x - edgec))
	cy = clamp(cy, (0 + sh.y + edgec), (3 + sh.y - edgec))
	centeroff.x = cx - cursor_offset.x
	centeroff.y = -cy - cursor_offset.y
	
	var hlm = 0.25
	var uim = Rhythia.get("ui_parallax") * 0.1
	var grm = Rhythia.get("grid_parallax") * 0.1
	cam.transform.origin = Vector3(
		centeroff.x*hlpower, centeroff.y*hlpower, 3.735
	)
	Grid.transform.origin = Vector3(
		-centeroff.x*hlm*uim, -centeroff.y*hlm*uim, Grid.transform.origin.z
	)
	transform.origin = Vector3(
		-(centeroff.x*hlm*grm)-1, -(centeroff.y*hlm*grm)+1, 0
	)
	get_node("Cursor").transform.origin = centeroff + cursor_offset

func comma_sep(number):
	var string = str(number)
	var mod = string.length() % 3
	var res = ""
	
	for i in range(0, string.length()):
		if i != 0 && i % 3 == mod:
			res += ","
		res += string[i]
	
	return res

var spawn_ms_dist:float = ((max(Rhythia.get("spawn_distance") / Rhythia.get("approach_rate"),0.6) * 1000) + 500)

func do_note_queue():
	pass
	#	var rem:int = 0
	#	for n in noteQueue:
	#		if n[2] <= (ms + (spawn_ms_dist * speed_multi)):
	#			rem += 1
	#
	#			spawn_note(n)
	#			noteQueue.remove(noteQueue.find(n))
	#		else:
	#			break


var rec_t:float = 0
var rms:float = 0
var rec_interval:float = 12
var pause_state:float = 0
var pause_cooldown:float = 0
var pause_ms:float = 0
var replay_unpause:bool = false
var can_skip:bool = ((next_ms-prev_ms) > 5000) and (next_ms >= max(ms+(3000*speed_multi),1100*speed_multi))
var ms_offset:float = 0

var replay_sig:Array = []
var last_usec = OS.get_ticks_usec()

# replay viewer mod
var replay_rate:float = 1.0
var replay_paused:bool = false
var replay_step:float = 0.0
var replay_viewer = null

func _set_rec_interval(delta:float):
	var newpos = $Cursor.transform.origin
	var diff = last_cursor_position.distance_to(newpos)/delta
	
	var min_interval = 30
	var max_interval = 144
	match Rhythia.record_limit:
		1:
			min_interval = 60
			max_interval = 240
	if Engine.target_fps != 0:
		max_interval = min(max_interval,Engine.target_fps)
		min_interval = min(min_interval,max_interval)
	var target_interval = min_interval+((diff/12)*(max_interval-min_interval))
	var new_interval = rec_interval
	if rec_interval != target_interval:
		match Rhythia.record_mode:
			0:
				new_interval = target_interval
			1:
				if target_interval > rec_interval: new_interval += (target_interval-rec_interval) * (delta / 0.2)
				else: new_interval += (target_interval-rec_interval) * (delta / 2)
			2:
				if target_interval > rec_interval: new_interval += (target_interval-rec_interval) * (delta / 2)
				else: new_interval = target_interval
	rec_interval = clamp(new_interval,min_interval,max_interval)
	
	last_cursor_position = newpos

func _process(delta:float):
	var u = OS.get_ticks_usec()
	delta = float(u - last_usec) / 1_000_000.0
	last_usec = u
	
	if replay_viewer:
		if replay_paused:
			delta = replay_step
			replay_step = 0
		else:
			delta *= replay_rate
		$Music.stream_paused = replay_paused
	
	if Rhythia.vr: do_vr_cursor()
	elif Rhythia.get("cam_unlock"): do_spin()
	else: do_half_lock()
	
	if !Rhythia.replaying: _set_rec_interval(delta)
	
	if active and notes_loaded:
		if !notes_loaded: return
		can_skip = ((next_ms-prev_ms) > 5000) and (next_ms >= max(ms+(3000*speed_multi),1100*speed_multi)) and ($Notes.multimesh.visible_instance_count <= 1)
		
		$Cursor.can_switch_move_modes = (ms < Rhythia.music_offset)
		
		if !Rhythia.replaying:
			_live_pause(delta)
		elif Rhythia.replay.sv != 1:
			var should_pause:bool = false
			var should_giveup:bool = false
			var should_skip:bool = false
			var just_started_unpause:bool = false
			var just_cancelled_unpause:bool = false
			var should_end_unpause:bool = false
			if replay_sig.size() != 0:
				print(replay_sig)
			for s in replay_sig:
				if s[1] == Globals.RS_PAUSE: should_pause = true
				elif s[1] == Globals.RS_GIVEUP: should_giveup = true
				elif s[1] == Globals.RS_SKIP: should_skip = true
				elif s[1] == Globals.RS_START_UNPAUSE:
					just_started_unpause = true
					replay_unpause = true
				elif s[1] == Globals.RS_CANCEL_UNPAUSE:
					just_cancelled_unpause = true
					replay_unpause = false
				elif s[1] == Globals.RS_FINISH_UNPAUSE:
					should_end_unpause = true

			if should_skip:
				var prev_ms = ms
				if Rhythia.record_replays:
					Rhythia.replay.store_sig(rms,Globals.RS_SKIP)
				ms = next_ms - 1000 - (1000*speed_multi)
				emit_signal("ms_change",ms)
				do_note_queue()
				if (ms + Rhythia.music_offset) >= Rhythia.start_offset:
					$Music.play((ms + Rhythia.music_offset)/1000)
					music_started = true
			if just_cancelled_unpause:
				pause_state = -1
				ms = pause_ms# - (750 * speed_multi)
				Rhythia.replay.store_sig(rms,Globals.RS_CANCEL_UNPAUSE)
				emit_signal("ms_change",ms)
				$Music.stop()
			elif should_pause:
				print("PAUSED AT MS %.0f" % ms)
				if Rhythia.record_replays:
					Rhythia.replay.store_sig(rms,Globals.RS_PAUSE)
				Rhythia.song_end_pause_count += 1
				pause_state = -1
	#			ms -= 750
				emit_signal("ms_change",ms)
				pause_ms = ms# + (750 * speed_multi)
				$Music.stop()
				get_parent().combo_level = 1
				get_parent().lvl_progress = 0
				get_parent().update_hud()
			elif just_started_unpause:
	#				print("YEAH baby that's what i've been waiting for")
	#				print(pause_ms)
				pause_state = 1
				ms = pause_ms - (pause_state * (750 * speed_multi))
				emit_signal("ms_change",ms)
				$Music.volume_db = -30
				$Music.play((ms + Rhythia.music_offset)/1000)
			if replay_unpause and pause_state >= 0:
				pause_state = max(pause_state - (delta/0.75), 0)
				$Music.volume_db = min($Music.volume_db + (delta * 30), 0)
				if should_end_unpause:
		#				print("YEAH baby that's what i've been waiting for")
					$Music.volume_db = Rhythia.music_volume_db
					pause_state = 0
			if should_giveup: get_parent().end(Globals.END_GIVEUP)
		
		rms += delta * 1000
		rec_t += delta
		if pause_state == 0 or (pause_state > 0 and (menu_unpause or replay_unpause)):
			ms += delta * 1000 * speed_multi
			emit_signal("ms_change",ms)
			do_note_queue()
			if (ms + Rhythia.music_offset) >= Rhythia.start_offset and !music_started:
				$Music.play((ms + Rhythia.music_offset)/1000)
				music_started = true
		
		if Rhythia.replaying:
			replay_sig = Rhythia.replay.get_signals(rms)
		
		emit_signal("timer_update",ms,can_skip)
		
		if $Music.playing and !Rhythia.disable_desync:
			var playback_pos:float = $Music.get_playback_position()*1000.0
			if abs(playback_pos - (ms + Rhythia.music_offset)) > (100 * max(speed_multi, 1.0)):
				if Rhythia.desync_alerts:
					Globals.notify(
						Globals.NOTIFY_WARN,
						"Audio was desynced by %.2f ms, correcting." % [playback_pos - (ms + Rhythia.music_offset)],
						"Music Sync Correction"
					)
				$Music.play((ms + Rhythia.music_offset)/1000.0)
		
		var rn_res:bool = reposition_notes()
		if !Rhythia.replaying and Rhythia.record_replays:
			var should_write_pos:bool = rn_res
			var ri = 1/round(max(32,rec_interval))
			if pause_state == -1: ri /= 3
			if rn_res or rec_t >= ri:
				rec_t = 0
				should_write_pos = true
				Rhythia.replay.store_cursor_pos(rms,$Cursor.rpos.x,$Cursor.rpos.y)
		
		if Rhythia.rainbow_grid:
			$Inner.get("material/0").albedo_color = Color.from_hsv(Rhythia.rainbow_t*0.1,0.65,1)
			$Outer.get("material/0").albedo_color = Color.from_hsv(Rhythia.rainbow_t*0.1,0.65,1)


# ---------- replay viewer mod ----------
func set_replay_rate(r:float):
	replay_rate = r
	$Music.pitch_scale = speed_multi * replay_rate

func _sim_hit(game):
	game.hits += 1
	game.total_notes += 1
	if !Rhythia.mod_no_regen: game.energy = clamp(game.energy + game.energy_per_hit, 0, game.max_energy)
	game.combo += 1
	if game.combo > game.max_combo: game.max_combo = game.combo
	var points = game.get_point_amt()
	if game.combo_level != 8:
		game.lvl_progress += 1
	if game.combo_level != 8 and game.lvl_progress == 10:
		game.lvl_progress = 0
		game.combo_level += 1
		if game.combo_level == 8: game.lvl_progress = 10
	game.score += points

# returns true when this miss would have failed the replay
func _sim_miss(game) -> bool:
	game.misses += 1
	game.total_notes += 1
	game.energy = clamp(game.energy - 1, 0, game.max_energy)
	game.combo = 0
	game.lvl_progress = 0
	if game.combo_level != 1: game.combo_level -= 1
	if game.energy == 0:
		if Rhythia.mod_nofail: game.song_has_failed = true
		else: return true
	return false

func _sim_should_hit(i:int, sms:float) -> bool:
	var rp = Rhythia.replay
	if rp.sv != 1: return rp.should_hit(i)
	var p:Vector2 = rp.get_cursor_position(sms)
	var hbs:float = Rhythia.note_hitbox_size/2
	if hbs == 0.57: hbs = 0.56875
	var ori:Vector2 = notes[i][0]
	return (p.x <= ori.x + hbs and p.x >= ori.x - hbs) and (p.y <= ori.y + hbs and p.y >= ori.y - hbs)

func replay_length() -> float:
	return Rhythia.replay.length_ms()

# Rebuilds the whole replay state at replay time `target` (real ms, same clock as rms)
# by re-running the recorded signals and note results from the start, silently.
# replay times (rms) of every miss, for the viewer's seek bar: one silent run over the whole
# replay with the same judging as replay_seek, then the state is rebuilt at the current time
var sim_miss_log = null
func replay_miss_times() -> Array:
	if !replay_viewer or !notes_loaded: return []
	var keep = rms
	var pauses = Rhythia.song_end_pause_count
	sim_miss_log = []
	replay_seek(Rhythia.replay.length_ms(), true)
	var out = sim_miss_log
	sim_miss_log = null
	replay_seek(keep)
	Rhythia.song_end_pause_count = pauses
	return out

func replay_seek(target:float, dry:bool = false):
	if !replay_viewer or !notes_loaded: return
	var rp = Rhythia.replay
	var game = get_parent()
	if game.ending: return
	target = clamp(target, 0, rp.length_ms())
	
	for n in notes: n[2] = Globals.NSTATE_ACTIVE
	game.score = 0
	game.combo = 0
	game.combo_level = 1
	game.lvl_progress = 0
	game.hits = 0
	game.misses = 0
	game.total_notes = 0
	game.energy = game.max_energy
	game.max_combo = 0
	game.song_has_failed = false
	Rhythia.song_end_pause_count = 0
	
	var sms:float = Rhythia.start_offset - (3000 * speed_multi)
	var srms:float = 0
	var ps:float = 0
	var pms:float = 0
	var unp:bool = false
	var cur:int = 0
	var last_judged:float = -100000
	var pending:Array = []
	var trig_i:int = 0
	var trig:Array = rp.triggers
	var end_type:int = -1
	var dt:float = 5.0
	
	while srms < target and end_type == -1:
		var sp = false
		var sg = false
		var sk = false
		var su = false
		var sc = false
		var se = false
		for s in pending:
			if s[1] == Globals.RS_PAUSE: sp = true
			elif s[1] == Globals.RS_GIVEUP: sg = true
			elif s[1] == Globals.RS_SKIP: sk = true
			elif s[1] == Globals.RS_START_UNPAUSE:
				su = true
				unp = true
			elif s[1] == Globals.RS_CANCEL_UNPAUSE:
				sc = true
				unp = false
			elif s[1] == Globals.RS_FINISH_UNPAUSE: se = true
		if sk:
			var nx:float = sms
			for k in range(cur, notes.size()):
				if notes[k][1] > sms:
					nx = notes[k][1]
					break
			sms = nx - 1000 - (1000 * speed_multi)
		if sc:
			ps = -1
			sms = pms
		elif sp:
			Rhythia.song_end_pause_count += 1
			ps = -1
			pms = sms
			game.combo_level = 1
			game.lvl_progress = 0
		elif su:
			ps = 1
			sms = pms - (750 * speed_multi)
		if unp and ps >= 0:
			ps = max(ps - (dt / 750.0), 0)
			if se: ps = 0
		if sg:
			end_type = Globals.END_GIVEUP
			break
		
		var step:float = min(dt, target - srms)
		srms += step
		if ps == 0 or (ps > 0 and unp):
			sms += step * speed_multi
		
		pending = []
		while trig_i < trig.size() and trig[trig_i][0] <= srms:
			pending.append(trig[trig_i])
			trig_i += 1
		
		var i:int = cur
		var judge_ms:float = sms
		while i < notes.size():
			var nms:float = notes[i][1]
			if nms > sms: break
			if notes[i][2] == Globals.NSTATE_ACTIVE:
				if Rhythia.visual_mode or _sim_should_hit(i, judge_ms):
					notes[i][2] = Globals.NSTATE_HIT
					_sim_hit(game)
					last_judged = nms
				elif sms > nms + hit_window or ps == -1:
					notes[i][2] = Globals.NSTATE_MISS
					last_judged = nms
					if sim_miss_log != null: sim_miss_log.append(srms)
					if _sim_miss(game):
						end_type = Globals.END_FAIL
						break
			if i == cur and notes[i][2] != Globals.NSTATE_ACTIVE and sms > nms + hit_window + 100:
				cur = i + 1
			i += 1
	
	if dry: return
	ms = sms
	rms = srms
	pause_state = ps
	pause_ms = pms
	replay_unpause = unp
	current_note = cur
	prev_ms = last_judged
	replay_sig = pending
	rp.trigger_index = trig_i
	rp.last_pos_offset = 0
	last_reposition_ms = ms
	out_of_notes = false
	
	music_started = (ms + Rhythia.music_offset) >= Rhythia.start_offset
	if music_started and pause_state != -1:
		$Music.volume_db = Rhythia.music_volume_db if pause_state == 0 else -30
		$Music.play((ms + Rhythia.music_offset) / 1000.0)
		$Music.stream_paused = replay_paused
	else:
		$Music.stop()
	
	game.update_hud()
	emit_signal("ms_change", ms)
	emit_signal("timer_update", ms, false)
	if end_type != -1: game.end(end_type)

func _exit_tree():
	# Remove anything sitting outside of the tree
	scoreEffect.queue_free()
	for n in noteCache:
		n.queue_free()

# ---------------------------------------------------------------- pause menu mod
# osu!-style: Esc pauses and opens PauseMenu, Esc/Continue rewinds 0.75 s and plays on by itself
# (no holding), Space only skips intros/breaks. Recorded with the stock replay signals, so
# replays play back the same. Any pause disqualifies the run (EndInfo.gd / Game.gd).
var pause_menu = null
var menu_unpause:bool = false
var keys_down:Dictionary = {}

func _key_just(k:int) -> bool:
	var down = Input.is_key_pressed(k)
	var was = keys_down.get(k, false)
	keys_down[k] = down
	return down and !was

# mobile "tap to pause" (stock HUD TouchScreenButton) presses the "pause" action, which is also
# Space on PC; Space alone stays skip, so the action only counts while Space isn't held
func _mobile_pause_just() -> bool:
	var down = Input.is_action_pressed("pause") and !Input.is_key_pressed(KEY_SPACE)
	var was = keys_down.get("mpause", false)
	keys_down["mpause"] = down
	return down and !was

func _live_pause(delta:float):
	var mp = _mobile_pause_just()
	var space = _key_just(KEY_SPACE)
	# the mobile button is the phone's Space too: it skips the intro / a break when a skip is
	# possible (like the stock game), and pauses otherwise
	if mp and pause_state == 0 and can_skip:
		space = true
		mp = false
	var esc = _key_just(KEY_ESCAPE) or mp
	if pause_state == 0:
		pause_cooldown = max(pause_cooldown - delta, 0)
		if space and can_skip:
			if Rhythia.record_replays:
				Rhythia.replay.store_sig(rms,Globals.RS_SKIP)
			ms = next_ms - 1000 - (1000*speed_multi)
			emit_signal("ms_change",ms)
			do_note_queue()
		elif esc and !_can_pause():
			print("ESC: can't pause now (ms %.0f, cooldown %.2f, pausing disabled %s)" % [ms, pause_cooldown, Rhythia.disable_pausing])
		elif esc:
			print("PAUSED AT MS %.0f" % ms)
			if Rhythia.record_replays:
				Rhythia.replay.store_pause(rms)
			Rhythia.song_end_pause_count += 1
			pause_state = -1
			emit_signal("ms_change",ms)
			pause_ms = ms
			$Music.stop()
			get_parent().combo_level = 1
			get_parent().lvl_progress = 0
			get_parent().update_hud()
			_open_pause_menu()
	elif pause_state < 0:
		if esc: _pause_choice("continue")
	else: # counting back in after Continue
		if esc:
			if Rhythia.record_replays:
				Rhythia.replay.store_sig(rms,Globals.RS_CANCEL_UNPAUSE)
			menu_unpause = false
			pause_state = -1
			ms = pause_ms
			emit_signal("ms_change",ms)
			$Music.stop()
			_open_pause_menu()
			return
		pause_state = max(pause_state - (delta/0.75), 0)
		$Music.volume_db = min($Music.volume_db + (delta * 30), Rhythia.music_volume_db)
		if pause_state == 0:
			if Rhythia.record_replays:
				Rhythia.replay.store_sig(rms,Globals.RS_FINISH_UNPAUSE)
			$Music.volume_db = Rhythia.music_volume_db
			menu_unpause = false
			pause_cooldown = 0.3

# osu!-style: pause any time until the map is over (stock needed 1 s into the song)
func _can_pause() -> bool:
	return ms < get_parent().last_ms and pause_cooldown == 0 and !Rhythia.disable_pausing and !get_parent().ending

func _open_pause_menu():
	if !pause_menu:
		pause_menu = load("res://mods/replay/PauseMenu.gd").new()
		add_child(pause_menu)
		pause_menu.connect("chosen", self, "_pause_choice")
	pause_menu.open()

func _pause_choice(what:String):
	if pause_state >= 0: return
	if pause_menu: pause_menu.close()
	match what:
		"continue":
			if Rhythia.record_replays:
				Rhythia.replay.store_sig(rms,Globals.RS_START_UNPAUSE)
			menu_unpause = true
			pause_state = 1
			ms = pause_ms - (pause_state * (750 * speed_multi))
			emit_signal("ms_change",ms)
			$Music.volume_db = Rhythia.music_volume_db - 30
			if (ms + Rhythia.music_offset) >= Rhythia.start_offset:
				$Music.play((ms + Rhythia.music_offset)/1000)
				music_started = true
			else: music_started = false # paused in the lead-in: music starts on time again
		"retry":
			get_tree().change_scene("res://scenes/song.tscn")
		"quit":
			get_parent().end(Globals.END_GIVEUP)

