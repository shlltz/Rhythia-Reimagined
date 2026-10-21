extends Node
# Gyroscope cursor (Rhythia-reimagined, Customize > Device > Cursor: GYROSCOPE), added to a run by
# Game.gd on phones / tablets. Each frame the phone's rotation moves the cursor (Device.gyro_delta:
# turn it left / right to move across, tilt it to move up / down). Touch drags stop moving the cursor
# (their emulated mouse motion is taken before the cursor sees it); a second finger on the screen puts
# the cursor back in the centre. Replays store the cursor path, so they play back the same.

const D = preload("res://mods/replay/Device.gd")
const R = preload("res://mods/replay/Reimagined.gd")

var cursor = null

func _process(dt):
	if !is_instance_valid(cursor): return
	var d = D.gyro_delta(D.gyro(), dt, float(R.val("gyro_sens")), bool(R.val("gyro_inv_x")), bool(R.val("gyro_inv_y")))
	if d != Vector2.ZERO: cursor.move_cursor(d)

func _input(ev):
	if ev is InputEventMouseMotion:
		get_tree().set_input_as_handled()
	elif ev is InputEventScreenTouch and ev.pressed and ev.index >= 1 and is_instance_valid(cursor):
		cursor.move_cursor_abs(Vector2(1, 1))
