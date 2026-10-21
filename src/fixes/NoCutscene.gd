extends Node
# Replaces the stock intro cutscene (scenes/Intro.tscn, the floating cube character; Globals switches
# to it at launch until "Disable Intro Cutscene" is set): straight back to init, like the cutscene's end.

func _ready():
	get_tree().call_deferred("change_scene", "res://scenes/init.tscn")
