extends Node
# Rhythia-reimagined settings page: the game's settings (Main/Settings) in the Customize panel's
# look - one big dark card with a header, a tab column on the left (the TabContainer's own tab
# bar is hidden; the buttons just switch current_tab) and the settings scrolling on the right.
# Nothing is moved out of its parent: the game finds every setting by path.

const ACCENT = Color("#8a6cff")
const LEFT = 92.0              # right of the sidebar
const TAB_W = 270.0
const SUBS = {"Gameplay": "modifiers, camera", "Notes": "look, colours, spawning",
	"World & Cursor": "background, cursor", "UI": "HUD, colours", "Video & Audio": "graphics, volume",
	"Replays & Misc": "replays, other"}

var settings:Control
var scroll:ScrollContainer
var tabs:TabContainer
var buttons:Array = []
var fonts:Dictionary = {}
var menu:Node

func _ready():
	menu = get_parent()
	settings = menu.get_node_or_null("Main/Settings")
	scroll = menu.get_node_or_null("Main/Settings/S")
	tabs = menu.get_node_or_null("Main/Settings/S/F/TabContainer")
	if !settings or !scroll or !tabs: return
	if ResourceLoader.exists("res://uitheme.tres") and !settings.theme: settings.theme = load("res://uitheme.tres")

	var card = Panel.new()
	card.name = "RRCard"
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.94)
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.set_border_width_all(1)
	card.add_stylebox_override("panel", sb)
	card.anchor_right = 1
	card.anchor_bottom = 1
	card.margin_left = LEFT - 20
	card.margin_top = 20
	card.margin_right = -24
	card.margin_bottom = -20
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings.add_child(card)
	settings.move_child(card, 0)

	var title = _label("SETTINGS", 40, Color(1, 1, 1))
	title.rect_position = Vector2(28, 18)
	card.add_child(title)
	var sub = _label("game, audio, visuals", 16, Color(1, 1, 1, 0.42))
	sub.rect_position = Vector2(31, 70)
	card.add_child(sub)
	var line = ColorRect.new()
	line.color = Color(1, 1, 1, 0.07)
	line.anchor_right = 1
	line.margin_top = 108
	line.margin_bottom = 109
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(line)
	var hint = _label("ESC  title screen", 14, Color(1, 1, 1, 0.3))
	hint.anchor_left = 1; hint.anchor_right = 1
	hint.margin_left = -260; hint.margin_right = -28; hint.margin_top = 44; hint.margin_bottom = 64
	hint.align = Label.ALIGN_RIGHT
	card.add_child(hint)

	# tab column (in Settings, not the card, so it gets clicks)
	var col = VBoxContainer.new()
	col.name = "RRTabs"
	col.rect_position = Vector2(LEFT, 146)
	col.rect_size = Vector2(TAB_W, 600)
	col.add_constant_override("separation", 8)
	settings.add_child(col)
	var TabButton = load("res://mods/replay/ReimaginedPanel.gd").TabButton
	for i in tabs.get_tab_count():
		var c = tabs.get_tab_control(i)
		var b = TabButton.new()
		b.title = tabs.get_tab_title(i)
		b.sub = SUBS.get(c.name, "")
		b.font_big = _font(23)
		b.font_small = _font(14)
		b.rect_min_size = Vector2(TAB_W, 64)
		b.connect("pressed", self, "_pick", [i])
		col.add_child(b)
		buttons.append(b)
	var gap = Control.new()
	gap.rect_min_size = Vector2(0, 18)
	col.add_child(gap)
	var cz = TabButton.new()
	cz.title = "Customize"
	cz.sub = "trail, HUD, skin, collections"
	cz.font_big = _font(23)
	cz.font_small = _font(14)
	cz.rect_min_size = Vector2(TAB_W, 64)
	cz.connect("pressed", menu, "open_customize", [], CONNECT_DEFERRED)
	col.add_child(cz)

	# settings on the right, filling the card
	tabs.tabs_visible = false
	tabs.add_stylebox_override("panel", StyleBoxEmpty.new())
	scroll.margin_left = LEFT + TAB_W + 40
	scroll.margin_top = 128
	scroll.margin_right = -48
	scroll.margin_bottom = -36
	var f = scroll.get_node("F")
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.add_constant_override("separation", 14)
	for t in tabs.get_children():
		for sec in t.get_children():
			var st = sec.get_node_or_null("SectionTitle")
			if st is Label:
				st.add_font_override("font", _font(28))
				st.add_color_override("font_color", Color(1, 1, 1))
			var sl = sec.get_node_or_null("SectionLine")
			if sl is HSeparator:
				var ls = StyleBoxLine.new()
				ls.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45)
				ls.thickness = 2
				sl.add_stylebox_override("separator", ls)
	_add_half_ghost_fade()
	_add_hitbox_mode()
	scroll.connect("resized", self, "_fit")
	settings.connect("visibility_changed", self, "_visibility")
	_visibility()
	tabs.connect("tab_changed", self, "_tab_changed")
	_fit()
	_tab_changed(tabs.current_tab)

# Rhythia-reimagined setting right under the game's Fade Length (Notes tab): a copy of that row
# without its script, saved to reimagined.json (NoteManager reads it when Half Ghost is on)
func _add_half_ghost_fade():
	var fl = tabs.get_node_or_null("Notes/Notes/Group/H/FadeLength")
	if !fl or fl.get_parent().has_node("HalfGhostFade"): return
	var R = load("res://mods/replay/Reimagined.gd")
	var row = fl.duplicate(0)
	row.name = "HalfGhostFade"
	var tip = "[def. 100%] Half Ghost: how long notes take to fade out. Lower = they stay solid longer and fade fast just before the hit"
	row.hint_tooltip = tip
	var sb:SpinBox = row.get_node("FadeLength")
	sb.min_value = 25
	sb.max_value = 300
	sb.step = 5
	sb.suffix = "%"
	sb.value = round(float(R.val("half_ghost_length")) * 100)
	sb.hint_tooltip = tip
	sb.connect("value_changed", self, "_half_ghost_changed")
	row.get_node("Label").text = "Half Ghost Fade"
	fl.get_parent().add_child(row)
	fl.get_parent().move_child(row, fl.get_index() + 1)

# hitbox system switch, under Hitbox Size / Hit Window (NoteManager: swept vs classic check)
func _add_hitbox_mode():
	var sw = tabs.get_node_or_null("Gameplay/Modifiers/Group/H/SpeedWindow")
	var hw = tabs.get_node_or_null("Gameplay/Modifiers/Group/H/HitWindow")
	if !sw or sw.get_parent().has_node("SweptHitbox"): return
	var c:CheckBox = sw.duplicate(0) # (no script: the game's checkbox script writes a Rhythia setting)
	c.name = "SweptHitbox"
	c.text = "Swept Hitbox"
	c.hint_tooltip = "[def. on] Rhythia-reimagined hitbox. Classic checks where your cursor is once per frame, so a fast flick that crosses a note between two frames misses. Swept also checks the path your cursor moved since the last frame. Same hitbox size, same hit window - only the gaps between frames are closed. Off = classic. Applies on the next map."
	c.pressed = bool(load("res://mods/replay/Reimagined.gd").val("swept_hitbox"))
	c.connect("toggled", self, "_swept_changed")
	sw.get_parent().add_child(c)
	sw.get_parent().move_child(c, (hw.get_index() + 1) if hw else sw.get_index())

func _swept_changed(on:bool):
	load("res://mods/replay/Reimagined.gd").set_val("swept_hitbox", on)

func _half_ghost_changed(v:float):
	load("res://mods/replay/Reimagined.gd").set_val("half_ghost_length", v / 100.0)

func _font(size:int):
	if fonts.has(size): return fonts[size]
	var base = settings.get_font("font", "Label")
	var f = base
	if base is DynamicFont:
		f = base.duplicate()
		f.size = size
	fonts[size] = f
	return f

func _label(text:String, size:int, col:Color) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", _font(size))
	l.add_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# every tab page fills the TabContainer from its origin; after the wide Replays & Misc tab the
# others came back anchored off to the right (x = 1344 on a 1398 wide page)
func _pin_tabs():
	for c in tabs.get_children():
		if !(c is Control): continue
		c.anchor_left = 0
		c.anchor_top = 0
		c.anchor_right = 1
		c.anchor_bottom = 1
		c.margin_left = 0
		c.margin_top = 0
		c.margin_right = 0
		c.margin_bottom = 0

# a wide tab (Replays & Misc: a row of buttons) stretched the page and it never shrank back,
# pushing the next tab's settings off to the right
func _shrink():
	var f = scroll.get_node_or_null("F")
	if !f: return
	tabs.rect_size.x = 0
	f.rect_size.x = 0
	_fit()
	scroll.scroll_horizontal = 0

func _fit():
	var f = scroll.get_node_or_null("F")
	if f: f.rect_min_size.x = scroll.rect_size.x - 16

func _pick(i:int):
	if tabs.current_tab != i:
		tabs.current_tab = i
		scroll.scroll_vertical = 0
		scroll.scroll_horizontal = 0
		if menu.has_node("Press"): menu.get_node("Press").play()

func _tab_changed(i:int):
	_pin_tabs()
	for k in buttons.size():
		buttons[k].selected = k == i
		buttons[k].update()

# the bottom visualizer would sit over the card: hide it while the settings page is open
func _visibility():
	var v = menu.get_node_or_null("AudioVisualizer")
	if v: v.visible = !settings.visible
