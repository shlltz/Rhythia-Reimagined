extends Reference
# The parts inside each HUD panel (Customize > HUD layout): their default boxes in the panel's own
# viewport pixels, per HUD style, and how a saved move / size / hide is put on the nodes when a run
# starts (HUD.gd for the legacy panels, RewriteHud.gd for the rewrite ones). Saved in
# reimagined.json "hud_parts": {style: {"Panel/part": [dx px, dy px, scale, shown]}}.

const R = preload("res://mods/replay/Reimagined.gd")
const SIZES = {"LeftHud": Vector2(300, 900), "RightHud": Vector2(300, 900), "TimerHud": Vector2(900, 300), "EnergyHud": Vector2(900, 300)}
# style -> panel -> [[part, label, default box]]
const PARTS = {
	"rewrite": {
		"LeftHud": [["score", "SCORE", Rect2(0, 270, 300, 90)], ["ring", "MULTIPLIER", Rect2(60, 495, 180, 180)], ["combo", "COMBO (ALT.)", Rect2(0, 749, 300, 50)]],
		"RightHud": [["acc", "ACCURACY", Rect2(0, 270, 300, 90)], ["hits", "HITS / MISSES", Rect2(19, 530, 262, 58)], ["sum", "NOTES", Rect2(0, 614, 300, 80)], ["simple", "MISSES (SIMPLE)", Rect2(0, 405, 300, 90)]],
		"TimerHud": [["title", "SONG NAME", Rect2(0, 60, 900, 70)], ["time", "TIME", Rect2(0, 145, 900, 60)], ["bar", "PROGRESS BAR", Rect2(50, 233, 800, 37)]],
		"EnergyHud": [["bar", "HEALTH BAR", Rect2(50, 4, 800, 37)], ["mods", "MODIFIERS", Rect2(50, 50, 800, 200)]],
	},
	"legacy": {
		"LeftHud": [["ring", "COMBO RING", Rect2(40, 30, 220, 220)], ["pauses", "PAUSES", Rect2(0, 280, 300, 130)], ["grade", "GRADE", Rect2(0, 450, 300, 170)], ["acc", "ACCURACY", Rect2(0, 652, 300, 192)]],
		"RightHud": [["score", "SCORE", Rect2(0, 40, 300, 130)], ["misses", "MISSES", Rect2(0, 280, 300, 130)], ["notes", "NOTES", Rect2(0, 652, 300, 130)]],
		"TimerHud": [["title", "SONG NAME", Rect2(0, 70, 900, 70)], ["time", "TIME", Rect2(0, 150, 900, 80)], ["bar", "PROGRESS BAR", Rect2(50, 246, 800, 14)]],
		"EnergyHud": [["bar", "HEALTH BAR", Rect2(50, 15, 800, 15)], ["mods", "MODIFIERS", Rect2(50, 50, 800, 200)]],
	},
}
# the legacy parts' nodes (HUD scene, under <viewport>/Control)
const LEGACY_NODES = {
	"LeftHud": {"ring": ["Combo"], "pauses": ["PausesTitle", "Pauses"], "grade": ["LetterGrade"], "acc": ["AccuracyTitle", "Accuracy", "AccuracyBar"]},
	"RightHud": {"score": ["ScoreTitle", "Score"], "misses": ["MissesTitle", "Misses"], "notes": ["NoteTitle", "Notes"]},
	"TimerHud": {"title": ["SongName"], "time": ["Label"], "bar": ["Time"]},
	"EnergyHud": {"bar": ["Energy"], "mods": ["Modifiers"]},
}
# what each panel holds, per style (the layout editor's names)
const PANEL_NAMES = {"rewrite": {"LeftHud": "SCORE / MULTIPLIER", "RightHud": "ACCURACY / HITS"}}
static func panel_name(st:String, sprite:String, fallback:String) -> String:
	return PANEL_NAMES.get(st, {}).get(sprite, fallback)

const VP = {"LeftHud": "LeftVP/Control", "RightHud": "RightVP/Control", "TimerHud": "TimerVP/Control", "EnergyHud": "EnergyVP/Control"}

static func style() -> String:
	return "legacy" if str(R.val("hud_style")) == "classic" else "rewrite"

static func parts(st:String, panel:String) -> Array:
	return PARTS.get(st, {}).get(panel, [])

static func entry(st:String, panel:String, part:String) -> Array:
	var all = R.cfg().get("hud_parts", {})
	var e = all.get(st, {}).get(panel + "/" + part, null) if typeof(all) == TYPE_DICTIONARY and typeof(all.get(st, {})) == TYPE_DICTIONARY else null
	if typeof(e) == TYPE_ARRAY and e.size() == 4: return e
	return [0.0, 0.0, 1.0, true]

static func put(st:String, panel:String, part:String, e:Array):
	var c = R.cfg()
	if typeof(c.get("hud_parts")) != TYPE_DICTIONARY: c["hud_parts"] = {}
	if typeof(c.hud_parts.get(st)) != TYPE_DICTIONARY: c.hud_parts[st] = {}
	if e[0] == 0.0 and e[1] == 0.0 and e[2] == 1.0 and e[3]: c.hud_parts[st].erase(panel + "/" + part)
	else: c.hud_parts[st][panel + "/" + part] = e

static func reset(st:String, panel:String = ""):
	var c = R.cfg()
	if typeof(c.get("hud_parts")) != TYPE_DICTIONARY or typeof(c.hud_parts.get(st)) != TYPE_DICTIONARY: return
	if panel == "":
		c.hud_parts[st] = {}
		return
	for k in c.hud_parts[st].keys():
		if k.begins_with(panel + "/"): c.hud_parts[st].erase(k)

# a saved part layout onto its nodes: moved, scaled round the part's own centre, hidden
static func apply(st:String, panel:String, part:String, nodes:Array):
	var e = entry(st, panel, part)
	if e[0] == 0.0 and e[1] == 0.0 and e[2] == 1.0 and e[3]: return
	var box = Rect2()
	for p in parts(st, panel):
		if p[0] == part: box = p[2]
	var c = box.position + box.size / 2
	var s = clamp(float(e[2]), 0.2, 4.0)
	for n in nodes:
		if !(n is Control): continue
		n.rect_pivot_offset = c - n.rect_position
		n.rect_position += Vector2(float(e[0]), float(e[1]))
		n.rect_scale *= Vector2(s, s)
		if !bool(e[3]): n.visible = false

# HUD.gd (legacy style): every part of every panel
static func apply_legacy(hud:Node):
	for panel in LEGACY_NODES:
		var root = hud.get_node_or_null(VP[panel])
		if !root: continue
		for part in LEGACY_NODES[panel]:
			var nodes = []
			for nm in LEGACY_NODES[panel][part]:
				var n = root.get_node_or_null(nm)
				if n: nodes.append(n)
			apply("legacy", panel, part, nodes)
