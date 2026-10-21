extends Node
# Boot fixes (node in init.tscn, moves itself to the root so it outlives init being loaded twice):
# no stock update check. Init asked GitHub for Rhythia's latest release on every launch, and on a
# version mismatch offered to "update" - replacing the modded game file with stock Rhythia. Init
# reads settings.json (which may say disable_update = false), then reports "Init default assets
# 6/6", then checks: disable_update is set again at that point. (It also fixes the stock hang at
# "Check for updates" when networking is turned off: the check answered before init waited for it.)

func _ready():
	if get_parent() != get_tree().root:
		if !get_tree().root.has_node("RRBoot"):
			var me = load("res://mods/fixes/Boot.gd").new()
			me.name = "RRBoot"
			get_tree().root.call_deferred("add_child", me)
		queue_free()
		return
	Rhythia.disable_update = true
	Rhythia.connect("init_stage_reached", self, "_stage")

func _stage(s, _last = false):
	Rhythia.disable_update = true
	# a Rewrite Feel run was cut off (game closed / crashed): own settings back before the menu
	# reads them (replay mod, RewriteFeel.gd; settings.json has been read by this stage)
	if str(s).begins_with("Init default assets") and ResourceLoader.exists("res://mods/replay/RewriteFeel.gd"):
		load("res://mods/replay/RewriteFeel.gd").restore()
	# skin profile in use (replay mod, Skins.gd): its sounds + own note shape / colours, once the stock
	# custom sounds and the registries are loaded
	if str(s).begins_with("Load asset replacement 5/5") and ResourceLoader.exists("res://mods/replay/Skins.gd"):
		call_deferred("_skin")
	if str(s) == "Waiting for menu": call_deferred("queue_free") # (init's last stage)

func _skin():
	load("res://mods/replay/Skins.gd").restore_at_boot()
