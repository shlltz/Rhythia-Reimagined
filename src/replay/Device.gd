extends Reference
# Rhythia-reimagined device options (Customize > Device): the gyroscope cursor (GyroCursor.gd), a
# low-end device profile that can be undone, bigger touch targets. The gyroscope and the touch hint
# are read here so a desktop test can stand in for a phone (Engine metas rr_fake_gyro, rr_touch_ui).

const R = preload("res://mods/replay/Reimagined.gd")

# ------------------------------------------------------------------ low-end profile
# [where, setting, value]: "rr" = Reimagined's own settings, "rh" = the game's (settings.json).
# The values it replaces are kept (perf_saved) and put back by restore_low().
const LOW = [["rr", "lite_fx", true], ["rr", "glitch_fx", false], ["rr", "trail_style", "off"],
	["rh", "cursor_trail", false], ["rh", "note_spawn_effect", false], ["rh", "bloom", 0.0], ["rh", "glow", 0.0],
	["rh", "disable_bg_effects", true], ["rh", "rainbow_grid", false], ["rh", "rainbow_hud", false]]
# (not render_scale: below 1 the game renders through an extra scaled pass - measured 4 % slower here
# on a desktop GPU; whether it helps a phone's GPU is untested, so it stays the player's choice)

static func low_on() -> bool:
	var s = R.val("perf_saved")
	return s is Dictionary and !s.empty()

static func _read(e:Array):
	return R.val(e[1]) if e[0] == "rr" else Rhythia.get(e[1])

static func _write(where:String, k:String, v):
	if where == "rr": R.cfg()[k] = v
	else: Rhythia.set(k, v)

# returns how many settings it changed (0: they already were that light, nothing to undo)
static func apply_low() -> int:
	if low_on(): return 0
	var saved = {}
	for e in LOW:
		var cur = _read(e)
		var v = e[2]
		if typeof(cur) in [TYPE_REAL, TYPE_INT] and typeof(v) in [TYPE_REAL, TYPE_INT]:
			if abs(float(cur) - float(v)) < 0.0001: continue
		elif str(cur) == str(v): continue
		saved[e[0] + ":" + e[1]] = cur
		_write(e[0], e[1], v)
	R.cfg()["perf_saved"] = saved
	R.save()
	Rhythia.save_settings()
	return saved.size()

static func restore_low() -> int:
	if !low_on(): return 0
	var saved = R.val("perf_saved")
	for k in saved:
		var p = str(k).split(":", true, 1)
		var v = saved[k]
		if p[0] == "rh" and typeof(Rhythia.get(p[1])) == TYPE_BOOL: v = bool(v) # (JSON keeps bools; numbers come back as floats)
		_write(p[0], p[1], v)
	R.cfg()["perf_saved"] = {}
	R.save()
	Rhythia.save_settings()
	return saved.size()

# ------------------------------------------------------------------ gyroscope
const GYRO_SCALE = 4.0           # grid cells per radian of rotation at sensitivity 1

static func gyro() -> Vector3:
	if Engine.has_meta("rr_fake_gyro"): return Engine.get_meta("rr_fake_gyro")
	return Input.get_gyroscope()

# the gyroscope steers the cursor in runs (phones / tablets only: a desktop has none)
static func gyro_wanted() -> bool:
	return str(R.val("cursor_input")) == "gyro" and (OS.has_touchscreen_ui_hint() or Engine.has_meta("rr_fake_gyro"))

# cursor movement (grid cells, y down) for a gyroscope reading (rad/s, screen axes: Godot turns the
# sensor axes with the display): turning about the screen's vertical axis moves across, tilting about
# its horizontal axis moves up / down
static func gyro_delta(g:Vector3, dt:float, sens:float, inv_x:bool, inv_y:bool) -> Vector2:
	var d = Vector2(-g.y, -g.x) * GYRO_SCALE * sens * dt
	if inv_x: d.x = -d.x
	if inv_y: d.y = -d.y
	return d

# ------------------------------------------------------------------ touch targets
const TOUCH_MIN = 44.0           # px: the usual minimum for a finger

static func touch_ui() -> bool:
	if Engine.has_meta("rr_touch_ui"): return bool(Engine.get_meta("rr_touch_ui"))
	var t = str(R.val("touch_big"))
	return t == "on" or (t == "auto" and OS.has_touchscreen_ui_hint())

# raises every button / box / field under `n` to a finger's height (panels call this when built)
static func touch_fit(n:Node):
	if !touch_ui(): return
	var stack = [n]
	while !stack.empty():
		var c = stack.pop_back()
		for k in c.get_children(): stack.append(k)
		if c is BaseButton or c is LineEdit or c is SpinBox or c is OptionButton:
			if c.rect_min_size.y < TOUCH_MIN: c.rect_min_size.y = TOUCH_MIN
			if !(c.get_parent() is Container) and c.rect_size.y < TOUCH_MIN: c.rect_size.y = TOUCH_MIN
