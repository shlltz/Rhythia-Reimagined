extends Reference
# Star rating matching Steam Rhythia (rhythia.com).
# Port of rhythia.com's star-calc rate() (was cunev/rhythia-web-utils rateMap): notes become osu!standard circles
# (x,y * 50 px, CS2 AR8 OD8, stack leniency 0) rated with osu-standard-stable 5.0.1
# + Relax, so only Aim counts. Includes the template note that rateMap leaves in
# (256,192 @ 24202 ms) so numbers line up with the site.
# Usage: StarRating.new().calculate(song.read_notes(), speed)

const TEMPLATE_NOTE = [256.0, 192.0, 24202.0]
const SCALE = 0.71 # CS2: (1 - 0.7*(2-5)/5) / 2
const RADIUS = 64.0 * SCALE
const NORMALIZED_RADIUS = 50.0
const MIN_DELTA_TIME = 25.0
const STACK_DISTANCE = 3.0
const SECTION_LENGTH = 400.0
const DECAY_WEIGHT = 0.9
const AIM_MULTIPLIER = 23.55
const AIM_DECAY_BASE = 0.15
const WIDE_ANGLE_MULTIPLIER = 1.5
const ACUTE_ANGLE_MULTIPLIER = 1.95
const VELOCITY_CHANGE_MULTIPLIER = 0.75
const DIFFICULTY_MULTIPLIER = 0.0675
const PERFORMANCE_BASE_MULTIPLIER = 1.14

# rhythia.com's current rate() (rhythia-online-release api/utils/star-calc): notes sorted by time,
# a note closer than 1.25 grid units to the note before it is dropped (so moves to a neighbouring
# cell don't count), and the last note is never added
const MERGE_DISTANCE = 1.25
var site_filter:bool = true # false = the old web-utils behaviour (kept for comparisons)
func _site_filter(notes:Array) -> Array:
	var ns:Array = _stable_sort_by_time(notes)
	var out:Array = []
	var i:int = 0
	while i < ns.size() - 1:
		var a = ns[i]
		var b = ns[i + 1]
		if Vector2(float(b[0]) - float(a[0]), float(b[1]) - float(a[1])).length() < MERGE_DISTANCE:
			ns.remove(i + 1)
			continue
		out.append(a)
		i += 1
	return out

# notes: Array of [x, y, ms] (Legacy grid units 0..2). clock_rate = speed multiplier.
func calculate(notes:Array, clock_rate:float = 1.0) -> float:
	# --- build hit objects: [x, y, time, stack_height]
	var objs:Array = [[TEMPLATE_NOTE[0], TEMPLATE_NOTE[1], TEMPLATE_NOTE[2], 0]]
	for n in (_site_filter(notes) if site_filter else notes):
		objs.append([floor(float(n[0]) * 50.0 + 0.5), floor(float(n[1]) * 50.0 + 0.5), float(n[2]), 0])
	objs = _stable_sort_by_time(objs)
	if objs.size() < 2: return 0.0
	_apply_stacking(objs)

	var sf:float = NORMALIZED_RADIUS / RADIUS
	var pos:Array = []
	for o in objs:
		var off:float = o[3] * SCALE * -6.4
		pos.append(Vector2(o[0] + off, o[1] + off))

	# --- difficulty objects
	var count:int = objs.size() - 1
	var delta:PoolRealArray = PoolRealArray(); delta.resize(count)
	var start:PoolRealArray = PoolRealArray(); start.resize(count)
	var strain_time:PoolRealArray = PoolRealArray(); strain_time.resize(count)
	var jump:PoolRealArray = PoolRealArray(); jump.resize(count)
	var angle:PoolRealArray = PoolRealArray(); angle.resize(count) # -1 = none
	for i in range(1, objs.size()):
		var d:int = i - 1
		delta[d] = (objs[i][2] - objs[i-1][2]) / clock_rate
		start[d] = objs[i][2] / clock_rate
		strain_time[d] = max(delta[d], MIN_DELTA_TIME)
		jump[d] = (pos[i] * sf - pos[i-1] * sf).length()
		angle[d] = -1.0
		if i > 1:
			var v1:Vector2 = pos[i-2] - pos[i-1]
			var v2:Vector2 = pos[i] - pos[i-1]
			angle[d] = abs(atan2(v1.x * v2.y - v1.y * v2.x, v1.dot(v2)))

	# --- aim strain (sections of 400 ms)
	var peaks:Array = []
	var section_peak:float = 0.0
	var section_end:float = ceil(start[0] / SECTION_LENGTH) * SECTION_LENGTH
	var strain:float = 0.0
	for d in range(count):
		while start[d] > section_end:
			peaks.append(section_peak)
			var prev_start:float = start[d-1] if d > 0 else 0.0
			section_peak = strain * pow(AIM_DECAY_BASE, (section_end - prev_start) / 1000.0)
			section_end += SECTION_LENGTH
		strain *= pow(AIM_DECAY_BASE, delta[d] / 1000.0)
		strain += _aim_value(d, strain_time, jump, angle) * AIM_MULTIPLIER
		section_peak = max(strain, section_peak)
	peaks.append(section_peak)

	# --- difficulty value (reduced top sections, weighted sum)
	var strains:Array = []
	for p in peaks:
		if p > 0: strains.append(p)
	strains.sort(); strains.invert()
	for i in range(min(strains.size(), 10)):
		var s:float = log(lerp(1.0, 10.0, clamp(i / 10.0, 0.0, 1.0))) / log(10.0)
		strains[i] *= lerp(0.75, 1.0, s)
	strains.sort(); strains.invert()
	var difficulty:float = 0.0
	var weight:float = 1.0
	for s in strains:
		difficulty += s * weight
		weight *= DECAY_WEIGHT
	difficulty *= 1.06

	# --- star rating (Relax: aim * 0.9, speed 0)
	var aim_rating:float = sqrt(difficulty) * DIFFICULTY_MULTIPLIER * 0.9
	var base_aim:float = pow(5.0 * max(1.0, aim_rating / 0.0675) - 4.0, 3) / 100000.0
	var base_speed:float = 1.0 / 100000.0
	var base_perf:float = pow(pow(base_aim, 1.1) + pow(base_speed, 1.1), 1.0 / 1.1)
	if base_perf <= 0.00001: return 0.0
	return pow(PERFORMANCE_BASE_MULTIPLIER, 1.0 / 3.0) * 0.027 * (pow(100000.0 / pow(2.0, 1.0 / 1.1) * base_perf, 1.0 / 3.0) + 4.0)

func _aim_value(d:int, strain_time:PoolRealArray, jump:PoolRealArray, angle:PoolRealArray) -> float:
	if d <= 1: return 0.0
	var curr_v:float = jump[d] / strain_time[d]
	var prev_v:float = jump[d-1] / strain_time[d-1]
	var wide:float = 0.0
	var acute:float = 0.0
	var vel_change:float = 0.0
	var aim:float = curr_v
	if max(strain_time[d], strain_time[d-1]) < 1.25 * min(strain_time[d], strain_time[d-1]):
		if angle[d] >= 0 and angle[d-1] >= 0 and angle[d-2] >= 0:
			var angle_bonus:float = min(curr_v, prev_v)
			wide = _wide(angle[d])
			acute = 1.0 - wide
			if strain_time[d] > 100:
				acute = 0.0
			else:
				acute *= 1.0 - _wide(angle[d-1])
				acute *= min(angle_bonus, 125.0 / strain_time[d])
				acute *= pow(sin(PI / 2.0 * min(1.0, (100.0 - strain_time[d]) / 25.0)), 2)
				acute *= pow(sin(PI / 2.0 * (clamp(jump[d], 50.0, 100.0) - 50.0) / 50.0), 2)
			wide *= angle_bonus * (1.0 - min(wide, pow(_wide(angle[d-1]), 3)))
			acute *= 0.5 + 0.5 * (1.0 - min(acute, pow(1.0 - _wide(angle[d-2]), 3)))
	if max(prev_v, curr_v) != 0:
		var dist_ratio:float = pow(sin(PI / 2.0 * abs(prev_v - curr_v) / max(prev_v, curr_v)), 2)
		var overlap_buff:float = min(125.0 / min(strain_time[d], strain_time[d-1]), abs(prev_v - curr_v))
		vel_change = overlap_buff * dist_ratio
		vel_change *= pow(min(strain_time[d], strain_time[d-1]) / max(strain_time[d], strain_time[d-1]), 2)
	aim += max(acute * ACUTE_ANGLE_MULTIPLIER, wide * WIDE_ANGLE_MULTIPLIER + vel_change * VELOCITY_CHANGE_MULTIPLIER)
	return aim

func _wide(a:float) -> float:
	return pow(sin(0.75 * (clamp(a, PI / 6.0, 5.0 / 6.0 * PI) - PI / 6.0)), 2)

# osu stacking ("new" algorithm) with stack leniency 0: only same-time circles < 3 px apart stack.
func _apply_stacking(objs:Array):
	for i in range(objs.size() - 1, 0, -1):
		var oi:Array = objs[i]
		if oi[3] != 0: continue
		var n:int = i
		n -= 1
		while n >= 0:
			var on:Array = objs[n]
			if oi[2] - on[2] > 0: break
			if Vector2(on[0], on[1]).distance_to(Vector2(oi[0], oi[1])) < STACK_DISTANCE:
				on[3] = oi[3] + 1
				oi = on
			n -= 1

func _stable_sort_by_time(objs:Array) -> Array:
	# Array.sort_custom is not stable; tie-break on index to keep the original order (JS sort is stable)
	var tagged:Array = []
	for i in range(objs.size()): tagged.append([objs[i][2], i, objs[i]])
	tagged.sort_custom(self, "_tag_less")
	var out:Array = []
	for t in tagged: out.append(t[2])
	return out

func _tag_less(a, b) -> bool:
	if a[0] == b[0]: return a[1] < b[1]
	return a[0] < b[0]
