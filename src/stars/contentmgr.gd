extends Node
# Content Manager root. Original behaviour + the CMStyle restyle (standalone mode:
# header bar with "Back to menu") + Esc on the first screen goes back to the menu.

const CMStyle = preload("res://mods/stars/CMStyle.gd")

func set_rpc_status(state:String):
	if not OS.has_feature("Android"):
		var activity = Discord.Activity.new()
		activity.set_type(Discord.ActivityType.Playing)
		activity.set_details("Content Manager")
		activity.set_state(state)

		var assets = activity.get_assets()
		assets.set_large_image("icon-bg")

		Discord.activity_manager.update_activity(activity)

func _ready():
	get_tree().paused = false
	$BlackFade.visible = true
	$BlackFade.color = Color(0,0,0,black_fade)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	add_child(CMStyle.new(true))

var black_fade_target:bool = false
var black_fade:float = 1

func _process(delta):
	if black_fade_target && black_fade != 1:
		black_fade = min(black_fade + (delta/0.3),1)
		$BlackFade.color = Color(0,0,0,black_fade)
	elif !black_fade_target && black_fade != 0:
		black_fade = max(black_fade - (delta/0.5),0)
		$BlackFade.color = Color(0,0,0,black_fade)
	$BlackFade.visible = black_fade != 0

func _unhandled_input(ev):
	# Esc on the first screen = back to menu
	if ev is InputEventKey and ev.pressed and !ev.echo and ev.scancode == KEY_ESCAPE:
		if $AddSong/SelectType.visible and !black_fade_target:
			$AddSong.back_to_menu()
