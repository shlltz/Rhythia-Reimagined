extends CanvasLayer
# Online map browser for Steam Rhythia's public map database (rhythia.com): search by name,
# filter by status, sort by star rating, one-click download into the game.
# .sspm maps are installed as they are; .rhm maps (zip: "map" JSON + audio + cover) are unpacked
# with Windows' tar.exe and converted to .sspm with the game's own writer (Song.convert_to_sspm).

const API = "https://production.rhythia.com/api/getBeatmaps"
const UA = "User-Agent: SoundSpacePlus-Legacy (Rhythia Tweaks)"
const PER_PAGE = 50          # server page size
const MAX_PAGES = 25         # pages loaded per search (1250 maps), then sorted here
const ROWS = 40              # cards per browser page
const TMP = "user://rhythia_dl"
const RECORD = "user://rhythia_online.json"   # online map id -> installed song id
const STATUSES = [["Any", ""], ["Ranked", "RANKED"], ["Approved", "APPROVED"], ["Unranked", "UNRANKED"]]
const SORTS = ["Hardest", "Easiest", "Newest", "Most played", "Longest", "Shortest"]
const HEAD_H = 140.0
const DIFFS = ["N/A", "Easy", "Medium", "Hard", "Logic", "Tasukete"]
const UIAnim = preload("res://mods/replay/UIAnim.gd")

var bg:ColorRect
var panel:Panel
var search:LineEdit
var status_i:int = 1           # Ranked
var sort_i:int = 0
var status_links:Array = []
var sort_links:Array = []
var fonts:Dictionary = {}
var info:Label
var scroll:ScrollContainer
var rows_box:GridContainer
var page_label:Label
var prev_btn:Button
var next_btn:Button
var api:HTTPRequest
var dl_http:HTTPRequest
var debounce:Timer
var star_script = null

var maps:Array = []          # results of the current search (API dictionaries)
var total:int = 0
var ui_page:int = 0
var query_id:int = 0
var pending:Array = [0, 0]   # [page, query id] of the request in flight
var loading:bool = false
var record:Dictionary = {}
var state:Dictionary = {}    # online id -> "queued" / "downloading" / "installing" / "failed"
var queue:Array = []         # maps waiting to download
var dl_current = null
var rows:Dictionary = {}     # online id -> row
var covers:Dictionary = {}   # image url -> Texture (null when it failed)
var hidden:bool = false

func _ready():
	layer = 20
	pause_mode = Node.PAUSE_MODE_PROCESS
	if ResourceLoader.exists("res://mods/stars/StarCache.gd"): star_script = load("res://mods/stars/StarCache.gd")
	record = _load_json(RECORD)
	_clear_tmp()
	_build_ui()
	api = _http("_on_api")
	dl_http = _http("_on_download")
	_start_covers()
	debounce = Timer.new()
	debounce.one_shot = true
	debounce.wait_time = 0.45
	debounce.connect("timeout", self, "new_query")
	add_child(debounce)
	new_query()
	search.grab_focus()
	show_browser()

func _http(cb:String) -> HTTPRequest:
	var h = HTTPRequest.new()
	h.use_threads = true
	h.timeout = 60
	h.connect("request_completed", self, cb)
	add_child(h)
	return h

# ------------------------------------------------------------------ UI
func _build_ui():
	bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	add_child(bg)
	panel = Panel.new()
	if ResourceLoader.exists("res://uitheme.tres"): panel.theme = load("res://uitheme.tres")
	# osu!lazer-style overlay: almost the whole screen, rises from the bottom
	panel.anchor_right = 1; panel.anchor_bottom = 1
	panel.margin_left = 96; panel.margin_right = -36; panel.margin_top = 44; panel.margin_bottom = 0
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.04, 0.04, 0.055, 0.99)
	ps.border_color = Color(1, 1, 1, 0.1)
	ps.border_width_top = 1; ps.border_width_left = 1; ps.border_width_right = 1
	ps.corner_radius_top_left = 10; ps.corner_radius_top_right = 10
	ps.shadow_color = Color(0, 0, 0, 0.6)
	ps.shadow_size = 30
	panel.add_stylebox_override("panel", ps)
	add_child(panel)

	# header: title, search bar, status pills (left) + sort pills (right)
	var head = Panel.new()
	var hs = StyleBoxFlat.new()
	hs.bg_color = Color(0.07, 0.07, 0.09)
	hs.corner_radius_top_left = 10; hs.corner_radius_top_right = 10
	head.add_stylebox_override("panel", hs)
	head.anchor_right = 1
	head.margin_bottom = HEAD_H
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(head)
	var crumb = _label("RHYTHIA", Rect2(28, 10, 200, 30))
	crumb.add_font_override("font", _font(22))
	var crumb2 = _label("online maps", Rect2(28 + _font(22).get_string_size("RHYTHIA  ").x, 10, 300, 30))
	crumb2.add_font_override("font", _font(22))
	crumb2.add_color_override("font_color", ACCENT)
	search = LineEdit.new()
	search.placeholder_text = "search maps..."
	search.add_font_override("font", _font(18))
	for k in ["normal", "focus"]:
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.05 if k == "normal" else 0.08)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 48
		sb.content_margin_right = 14
		if k == "focus":
			sb.border_color = ACCENT
			sb.set_border_width_all(1)
		search.add_stylebox_override(k, sb)
	_place(search, Rect2(24, 46, 600, 44))
	_stretch(search, -24)
	search.connect("text_changed", self, "_on_search_changed")
	search.connect("text_entered", self, "_on_search_entered")
	var mag = SearchIcon.new()
	mag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(mag, Rect2(38, 56, 24, 24))
	var x = 28.0
	for i in STATUSES.size():
		var l = _link(STATUSES[i][0], "_on_status", i)
		var w = _font(16).get_string_size(STATUSES[i][0]).x + 32
		_place(l, Rect2(x, 99, w, 30))
		x += w + 8
		status_links.append(l)
	var sh = HBoxContainer.new()
	sh.alignment = BoxContainer.ALIGN_END
	sh.add_constant_override("separation", 8)
	sh.anchor_left = 1; sh.anchor_right = 1
	sh.margin_left = -900; sh.margin_right = -24; sh.margin_top = 99; sh.margin_bottom = 129
	panel.add_child(sh)
	for i in SORTS.size():
		var l = _link(SORTS[i], "_on_sort", i)
		sh.add_child(l)
		sort_links.append(l)
	_paint_links()

	info = _label("", Rect2(28, HEAD_H + 6, 1160, 26))
	info.modulate = Color(1, 1, 1, 0.55)
	info.clip_text = true
	_stretch(info, -28)

	scroll = ScrollContainer.new()
	scroll.scroll_horizontal_enabled = false
	_place(scroll, Rect2(24, HEAD_H + 38, 1160, 570))
	_stretch(scroll, -18)
	scroll.anchor_bottom = 1
	scroll.margin_bottom = -70
	rows_box = GridContainer.new()
	rows_box.columns = 2
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.add_constant_override("hseparation", 14)
	rows_box.add_constant_override("vseparation", 12)
	scroll.add_child(rows_box)
	scroll.connect("resized", self, "_columns")

	prev_btn = _button("<", Rect2(24, 706, 60, 40), "_on_prev")
	page_label = _label("", Rect2(90, 712, 120, 30))
	page_label.align = Label.ALIGN_CENTER
	next_btn = _button(">", Rect2(216, 706, 60, 40), "_on_next")
	var om = _button("Open maps folder", Rect2(820, 706, 200, 40), "_open_maps")
	var cl = _button("Close", Rect2(1040, 706, 140, 40), "close")
	for c in [prev_btn, page_label, next_btn]: _bottom(c, -56)
	_right(om, -380, -180)
	_right(cl, -160, -24)
	_bottom(om, -56)
	_bottom(cl, -56)

func _font(size:int):
	if fonts.has(size): return fonts[size]
	var base = panel.get_font("font", "Label")
	var f = base
	if base is DynamicFont:
		f = base.duplicate()
		f.size = size
	fonts[size] = f
	return f

# pill tab: dark, purple when picked (same look as the Customize panel)
func _link(t:String, method:String, i:int) -> Button:
	var b = Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.add_font_override("font", _font(16))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.connect("pressed", self, method, [i])
	return b

func _paint_links():
	for g in [[status_links, status_i], [sort_links, sort_i]]:
		for i in g[0].size():
			var on = i == g[1]
			var c = Color(1, 1, 1) if on else Color(1, 1, 1, 0.55)
			g[0][i].add_color_override("font_color", c)
			g[0][i].add_color_override("font_color_pressed", c)
			g[0][i].add_color_override("font_color_hover", Color(1, 1, 1))
			for k in ["normal", "hover", "pressed"]:
				var sb = StyleBoxFlat.new()
				sb.set_corner_radius_all(15)
				sb.content_margin_left = 14; sb.content_margin_right = 14
				if on:
					sb.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.32)
					sb.border_color = ACCENT
					sb.set_border_width_all(1)
				else: sb.bg_color = Color(1, 1, 1, 0.08 if k == "hover" else 0.035)
				g[0][i].add_stylebox_override(k, sb)

func _columns():
	if rows_box: rows_box.columns = 3 if scroll.rect_size.x > 2200 else (1 if scroll.rect_size.x < 900 else 2)

# layout helpers for the full-size panel (offsets from the right / bottom edge)
func _stretch(c:Control, right:float):
	c.anchor_right = 1
	c.margin_right = right

func _right(c:Control, l:float, r:float):
	c.anchor_left = 1; c.anchor_right = 1
	c.margin_left = l; c.margin_right = r

func _bottom(c:Control, top:float):
	var h = c.margin_bottom - c.margin_top
	c.anchor_top = 1; c.anchor_bottom = 1
	c.margin_top = top; c.margin_bottom = top + h

func _place(c:Control, r:Rect2):
	c.margin_left = r.position.x; c.margin_top = r.position.y
	c.margin_right = r.position.x + r.size.x; c.margin_bottom = r.position.y + r.size.y
	panel.add_child(c)

func _label(t:String, r:Rect2) -> Label:
	var l = Label.new()
	l.text = t
	l.valign = Label.VALIGN_CENTER
	_place(l, r)
	return l

func _button(t:String, r:Rect2, cb:String) -> Button:
	var b = Button.new()
	b.text = t
	b.connect("pressed", self, cb)
	_place(b, r)
	return b

# ------------------------------------------------------------------ searching
func _on_search_changed(_t): debounce.start()
func _on_search_entered(_t):
	debounce.stop()
	new_query()
func _on_status(i:int):
	status_i = i
	_paint_links()
	new_query()
func _on_sort(i:int):
	sort_i = i
	_paint_links()
	_sort()
	ui_page = 0
	_render()

func new_query():
	query_id += 1
	maps = []
	total = 0
	ui_page = 0
	loading = true
	api.cancel_request()
	_render()
	_fetch(1, query_id)

func _fetch(page:int, qid:int):
	pending = [page, qid]
	var q = {"session": "", "page": page}
	var t = search.text.strip_edges()
	if t != "": q["textFilter"] = t
	var st = STATUSES[status_i][1]
	if st != "": q["status"] = st
	var err = api.request(API, PoolStringArray([UA, "Content-Type: application/json"]), true, HTTPClient.METHOD_POST, to_json(q))
	if err != OK:
		loading = false
		info.text = "Couldn't reach rhythia.com (error %d)" % err

func _on_api(result, code, _headers, body):
	var page = pending[0]
	if pending[1] != query_id: return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		loading = false
		info.text = "rhythia.com didn't answer (result %d, HTTP %d) - check your connection" % [result, code]
		return
	var d = parse_json(body.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY:
		loading = false
		info.text = "Unexpected answer from rhythia.com"
		return
	total = int(d.get("total", 0))
	var got = d.get("beatmaps")
	if got is Array:
		for b in got:
			if b is Dictionary and b.get("beatmapFile"): maps.append(b)
	var pages = min(ceil(total / float(PER_PAGE)), MAX_PAGES)
	loading = page < pages and got is Array and got.size() > 0
	_sort()
	if loading:
		_fetch(page + 1, query_id)
		if page == 1: _render()
		else: _update_info()
	else:
		_render()

func _num(b:Dictionary, k:String) -> float:
	var v = b.get(k)
	return float(v) if v != null else 0.0
func _stars_desc(a, b): return _num(a, "starRating") > _num(b, "starRating")
func _stars_asc(a, b): return _num(a, "starRating") < _num(b, "starRating")
func _newest(a, b): return str(a.get("created_at", "")) > str(b.get("created_at", ""))
func _played(a, b): return _num(a, "playcount") > _num(b, "playcount")
func _longest(a, b): return _num(a, "length") > _num(b, "length")
func _shortest(a, b): return _num(a, "length") < _num(b, "length")

func _sort():
	var f = ["_stars_desc", "_stars_asc", "_newest", "_played", "_longest", "_shortest"][sort_i]
	maps.sort_custom(self, f)

func _update_info():
	var t = ""
	if maps.size() == 0:
		t = "Searching rhythia.com..." if loading else "No maps found"
	else:
		t = "%d maps on rhythia.com" % total
		if loading: t += "  ·  loading %d..." % maps.size()
		elif total > maps.size(): t += "  ·  showing the newest %d (search to narrow it down)" % maps.size()
		t += "  ·  sorted by " + SORTS[sort_i].to_lower()
	info.text = t

func _render():
	for c in rows_box.get_children(): c.queue_free()
	rows = {}
	online = {}
	cover_wait = {}
	cover_todo = []
	var pages = max(1, int(ceil(maps.size() / float(ROWS))))
	ui_page = int(clamp(ui_page, 0, pages - 1))
	for i in range(ui_page * ROWS, min(maps.size(), (ui_page + 1) * ROWS)):
		rows_box.add_child(_make_row(maps[i]))
	page_label.text = "%d / %d" % [ui_page + 1, pages]
	prev_btn.disabled = ui_page == 0
	next_btn.disabled = ui_page >= pages - 1
	scroll.scroll_vertical = 0
	_update_info()

func _on_prev():
	ui_page -= 1
	_render()
func _on_next():
	ui_page += 1
	_render()

# ------------------------------------------------------------------ map cards
const CARD_H = 104.0
const STATUS_COL = {"RANKED": Color("#b3ff66"), "APPROVED": Color("#66ccff"), "LOVED": Color("#ff66aa"), "UNRANKED": Color("#9aa3ad")}
const DIFF_COL = [Color("#9aa3ad"), Color("#4fd86b"), Color("#ffcc33"), Color("#ff5555"), Color("#b27cff"), Color("#7d7d7d")]
const CARD_BG = Color(0.075, 0.075, 0.095)
const CARD_HOVER = Color(0.1, 0.1, 0.13)
const ACCENT = Color("#8a6cff")

# "Artist - Title" -> [title, artist]
static func _split(t:String) -> Array:
	var i = t.find(" - ")
	if i > 0: return [t.substr(i + 3), t.substr(0, i)]
	return [t, ""]

func _make_row(b:Dictionary) -> Control:
	var oid = int(b.id)
	online[oid] = b
	var card = Panel.new()
	card.rect_min_size = Vector2(0, CARD_H)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.rect_clip_content = true
	var cs = StyleBoxFlat.new()
	cs.bg_color = CARD_BG
	cs.set_corner_radius_all(6)
	cs.border_color = Color(1, 1, 1, 0.06)
	cs.set_border_width_all(1)
	card.add_stylebox_override("panel", cs)
	card.connect("mouse_entered", self, "_hover", [card, true])
	card.connect("mouse_exited", self, "_hover", [card, false])
	var url = str(b.get("image", ""))

	# cover art behind the text, faded (the 128 px thumbnail stretched = soft, no blur pass needed)
	var back = TextureRect.new()
	back.name = "Back"
	back.expand = true
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	back.anchor_right = 1; back.anchor_bottom = 1
	back.margin_left = CARD_H
	back.modulate = Color(1, 1, 1, 0.12)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(back)
	var cov = TextureRect.new()
	cov.expand = true
	cov.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cov.rect_size = Vector2(CARD_H, CARD_H)
	cov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cov)
	_want_cover(url, cov)
	_want_cover(url, back)

	var names = _split(str(b.get("title", "?")))
	var x0 = CARD_H + 14
	_text(card, names[0], 21, Color(1, 1, 1), x0, 8, -150)
	_text(card, ("by " + names[1]) if names[1] != "" else "unknown artist", 15, Color(1, 1, 1, 0.85), x0, 33, -150)
	var mb = _text(card, "mapper", 13, Color(1, 1, 1, 0.45), x0, 54, 0)
	mb.anchor_right = 0
	mb.margin_right = x0 + _font(13).get_string_size("mapper  ").x
	_text(card, str(b.get("ownerUsername", "?")), 13, ACCENT.lightened(0.3), mb.margin_right, 54, -150)

	# pills: status, stars, difficulty, then length / plays / format
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 6)
	row.anchor_right = 1
	row.margin_left = x0; row.margin_top = 76; row.margin_right = -12; row.margin_bottom = 94
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var st = str(b.get("status", "")).to_upper()
	if st != "" and st != "NULL": row.add_child(_pill(st, STATUS_COL.get(st, Color("#9aa3ad"))))
	var stars = _num(b, "starRating")
	var scol = star_script.color_for(stars) if star_script else Color(1, 1, 1)
	var strip = ColorRect.new() # star colour along the cover's bottom edge
	strip.color = scol
	strip.rect_position = Vector2(0, CARD_H - 3)
	strip.rect_size = Vector2(CARD_H, 3)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(strip)
	var star = StarTag.new()
	star.stars = stars
	star.col = Color(0.08, 0.08, 0.1)
	star.font = _font(12)
	star.rect_min_size = Vector2(_font(12).get_string_size("%.2f" % stars).x + 22, 16)
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sp = _pill("", scol)
	sp.add_child(star)
	row.add_child(sp)
	var d = int(_num(b, "difficulty"))
	if d > 0 and d < DIFFS.size(): row.add_child(_pill(DIFFS[d].to_upper(), DIFF_COL[d]))
	var extra = Label.new()
	extra.text = _meta(b)
	extra.clip_text = true
	extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	extra.add_font_override("font", _font(13))
	extra.modulate = Color(1, 1, 1, 0.55)
	extra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(extra)

	var btn = Button.new()
	btn.name = "Get"
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_font_override("font", _font(14))
	btn.anchor_left = 1; btn.anchor_right = 1
	btn.margin_left = -140; btn.margin_right = -12; btn.margin_top = 12; btn.margin_bottom = 42
	btn.connect("pressed", self, "_download", [b])
	card.add_child(btn)
	rows[oid] = card
	_refresh_row(oid)
	return card

func _text(parent:Control, s:String, size:int, col:Color, x:float, y:float, right:float) -> Label:
	var l = Label.new()
	l.text = s
	l.clip_text = true
	l.add_font_override("font", _font(size))
	l.add_color_override("font_color", col)
	l.anchor_right = 1
	l.margin_left = x; l.margin_top = y; l.margin_right = right; l.margin_bottom = y + size + 6
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _pill(s:String, col:Color) -> PanelContainer:
	var p = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 8; sb.content_margin_right = 8; sb.content_margin_top = 1; sb.content_margin_bottom = 1
	p.add_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if s != "":
		var l = Label.new()
		l.text = s
		l.add_font_override("font", _font(12))
		l.add_color_override("font_color", Color(0.08, 0.08, 0.1))
		l.valign = Label.VALIGN_CENTER
		p.add_child(l)
	return p

func _length(b:Dictionary) -> String:
	var ms = int(_num(b, "length"))
	return "%d:%02d" % [ms / 60000, (ms / 1000) % 60] if ms > 0 else ""

func _meta(b:Dictionary) -> String:
	var parts = []
	var l = _length(b)
	if l != "": parts.append(l)
	parts.append("%d plays" % int(_num(b, "playcount")))
	parts.append(".rhm" if str(b.beatmapFile).to_lower().ends_with(".rhm") else ".sspm")
	return PoolStringArray(parts).join("  ·  ")

func _hover(card:Panel, on:bool):
	if !is_instance_valid(card): return
	var sb = card.get_stylebox("panel")
	sb.bg_color = CARD_HOVER if on else CARD_BG
	sb.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.7) if on else Color(1, 1, 1, 0.06)
	card.get_node("Back").modulate.a = 0.2 if on else 0.12
	card.update()

func _refresh_row(oid:int):
	if !rows.has(oid) or !is_instance_valid(rows[oid]): return
	var btn:Button = rows[oid].get_node("Get")
	var st = state.get(oid, "")
	btn.disabled = true
	var col = Color(1, 1, 1, 0.12)
	if _installed(oid):
		btn.text = "Installed"
		col = Color(0.45, 0.85, 0.45, 0.25)
	elif st == "queued": btn.text = "Queued"
	elif st == "downloading": btn.text = "Downloading"
	elif st == "installing": btn.text = "Installing..."
	else:
		btn.disabled = false
		btn.text = "Retry" if st == "failed" else "Download"
		col = Color(1, 0.4, 0.4, 0.35) if st == "failed" else Color(0.55, 0.42, 1.0, 0.6)
	for k in ["normal", "hover", "pressed", "disabled"]:
		var sb = StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.15) if k == "hover" else col
		sb.set_corner_radius_all(15)
		btn.add_stylebox_override(k, sb)
	btn.add_color_override("font_color_disabled", Color(1, 1, 1, 0.75))

func _installed(oid:int) -> bool:
	var reg = Rhythia.registry_song
	if !reg: return false
	var sid = record.get(str(oid))
	if sid != null and reg.get_item(str(sid)): return true # get_item returns false when missing
	if reg.get_item("rhythia_%d" % oid): return true
	var b = online.get(oid)
	return b != null and _in_library(b)

# ------------------------------------------------------------------ maps already in the library
# Maps imported some other way (sspm from Discord, old downloads...) are found by their name:
# same title once case/spaces/punctuation are ignored, and the same length (±3 s) when both know it.
const LEN_SLACK = 3000
var online:Dictionary = {}   # online id -> API dictionary (for the rows on screen)
var library:Dictionary = {}  # normalized name -> [last_ms, ...]
var _norm_re:RegEx

func _norm(t:String) -> String:
	if !_norm_re:
		_norm_re = RegEx.new()
		_norm_re.compile("[^\\p{L}\\p{N}]+")
	return _norm_re.sub(t.to_lower(), "", true)

func _index_library():
	library = {}
	var reg = Rhythia.registry_song
	if !reg: return
	for s in reg.get_items():
		if !s or s.is_online: continue
		for n in [s.name, s.song]:
			var k = _norm(str(n))
			if k.length() < 2: continue
			if !library.has(k): library[k] = []
			library[k].append(float(s.last_ms))

func _in_library(b:Dictionary) -> bool:
	var k = _norm(str(b.get("title", "")))
	if !library.has(k): return false
	var ms = _num(b, "length")
	if ms <= 0: return true
	for l in library[k]:
		if l <= 0 or abs(l - ms) <= LEN_SLACK: return true
	return false

class SearchIcon extends Control:
	func _draw():
		var c = Color(1, 1, 1, 0.7)
		var I = load("res://mods/replay/Icons.gd") if ResourceLoader.exists("res://mods/replay/Icons.gd") else null
		if I and I.available():
			I.draw(self, "search", Rect2(Vector2(), rect_size), c)
			return
		draw_arc(Vector2(10, 10), 7, 0, TAU, 24, c, 2.5, true)
		draw_line(Vector2(15, 15), Vector2(22, 22), c, 3.0, true)

class StarTag extends Control:
	var stars:float = 0.0
	var col:Color = Color(1, 1, 1)
	var font:Font = null
	func _draw():
		var f:Font = font if font else get_font("font", "Label")
		var h = rect_size.y
		var r = h * 0.3
		var c = Vector2(r + 2, h / 2)
		var pts = PoolVector2Array()
		for i in range(10):
			var a = -PI / 2 + i * PI / 5
			var rr = r if i % 2 == 0 else r * 0.45
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts, col)
		var base = (h - f.get_height()) / 2 + f.get_ascent()
		draw_string(f, Vector2(r * 2 + 10, base), "%.2f" % stars, col)

# ------------------------------------------------------------------ covers
# rhythia.com covers are full-size PNGs (0.2-1 MB each), so: COVER_SLOTS downloads at once,
# decoding + shrinking on a worker thread, and 128 px thumbnails kept on disk (COVER_DIR),
# so each cover is downloaded only once.
const COVER_SLOTS = 8
const COVER_DIR = "user://cache/rhythia_covers"
const THUMB = 128
var cover_wait:Dictionary = {}   # url -> [TextureRect, ...] (rows on screen)
var cover_todo:Array = []        # urls to fetch, in row order
var cover_idle:Array = []        # free HTTPRequests
var cover_thread:Thread
var cover_mutex:Mutex
var cover_sem:Semaphore
var cover_jobs:Array = []        # [url, PoolByteArray from the net, or "" = read the disk thumbnail]
var cover_stop:bool = false

func _start_covers():
	Directory.new().make_dir_recursive(Globals.p(COVER_DIR))
	for i in COVER_SLOTS:
		var h = HTTPRequest.new()
		h.use_threads = true
		h.timeout = 30
		h.connect("request_completed", self, "_on_cover", [h])
		add_child(h)
		cover_idle.append(h)
	cover_mutex = Mutex.new()
	cover_sem = Semaphore.new()
	cover_thread = Thread.new()
	cover_thread.start(self, "_cover_worker")

func _stop_covers():
	if !cover_thread: return
	cover_stop = true
	cover_sem.post()
	cover_thread.wait_to_finish()
	cover_thread = null

func _thumb_path(url:String) -> String:
	return Globals.p(COVER_DIR) + "/" + url.md5_text() + ".png"

func _want_cover(url:String, rect:TextureRect):
	if url == "" or url == "Null": return
	if covers.has(url):
		if covers[url]: rect.texture = covers[url]
		return
	if cover_wait.has(url):
		cover_wait[url].append(rect)
		return
	cover_wait[url] = [rect]
	if File.new().file_exists(_thumb_path(url)): _cover_job(url, "")
	else:
		cover_todo.append(url)
		_next_cover()

func _next_cover():
	while !cover_idle.empty() and !cover_todo.empty():
		var url = cover_todo.pop_front()
		if !cover_wait.has(url): continue # its row went away (page change)
		var h:HTTPRequest = cover_idle.pop_back()
		h.set_meta("url", url)
		if h.request(url, PoolStringArray([UA])) != OK:
			cover_idle.append(h)
			_cover_done(url, null)

func _on_cover(result, code, _headers, body, h:HTTPRequest):
	var url = h.get_meta("url")
	cover_idle.append(h)
	if result == HTTPRequest.RESULT_SUCCESS and code == 200: _cover_job(url, body)
	else: _cover_done(url, null)
	_next_cover()

func _cover_job(url:String, data):
	cover_mutex.lock()
	cover_jobs.append([url, data])
	cover_mutex.unlock()
	cover_sem.post()

func _cover_worker(_u):
	while true:
		cover_sem.wait()
		if cover_stop: return
		cover_mutex.lock()
		var job = cover_jobs.pop_front() if !cover_jobs.empty() else null
		cover_mutex.unlock()
		if job == null: continue
		var img = null
		if job[1] is String:
			img = Image.new()
			if img.load(_thumb_path(job[0])) != OK: img = null
		else:
			img = _image(job[1], THUMB)
			if img: img.save_png(_thumb_path(job[0]))
		call_deferred("_cover_done", job[0], img)

func _cover_done(url:String, img):
	var tex = null
	if img:
		tex = ImageTexture.new()
		tex.create_from_image(img)
	covers[url] = tex
	for r in cover_wait.get(url, []):
		if tex and is_instance_valid(r): r.texture = tex
	cover_wait.erase(url)

static func _texture(buf:PoolByteArray, max_size:int = 0):
	var img = _image(buf, max_size)
	if !img: return null
	var t = ImageTexture.new()
	t.create_from_image(img)
	return t

static func _image(buf:PoolByteArray, max_size:int = 0):
	if buf.size() < 12: return null
	var img = Image.new()
	var err = ERR_FILE_UNRECOGNIZED
	if buf[0] == 0x89 and buf[1] == 0x50: err = img.load_png_from_buffer(buf)
	elif buf[0] == 0xFF and buf[1] == 0xD8: err = img.load_jpg_from_buffer(buf)
	elif buf[8] == 0x57 and buf[9] == 0x45: err = img.load_webp_from_buffer(buf)
	if err != OK: return null
	if max_size > 0 and max(img.get_width(), img.get_height()) > max_size:
		var s = float(max_size) / max(img.get_width(), img.get_height())
		img.resize(int(max(1, img.get_width() * s)), int(max(1, img.get_height() * s)), Image.INTERPOLATE_BILINEAR)
	return img

# ------------------------------------------------------------------ downloading + installing
func _download(b:Dictionary):
	var oid = int(b.id)
	if _installed(oid) or state.get(oid, "") in ["queued", "downloading", "installing"]: return
	state[oid] = "queued"
	queue.append(b)
	_refresh_row(oid)
	_next_download()

func _next_download():
	if dl_current != null or queue.empty(): return
	dl_current = queue.pop_front()
	var oid = int(dl_current.id)
	var url = str(dl_current.beatmapFile)
	state[oid] = "downloading"
	_refresh_row(oid)
	Directory.new().make_dir_recursive(Globals.p(TMP))
	dl_http.download_file = Globals.p(TMP) + "/%d.%s" % [oid, "rhm" if url.to_lower().ends_with(".rhm") else "sspm"]
	var err = dl_http.request(url, PoolStringArray([UA]))
	if err != OK: _finish_download(oid, "!couldn't start the download (error %d)" % err)

func _process(_delta):
	if dl_current == null: return
	var oid = int(dl_current.id)
	if state.get(oid) == "downloading" and rows.has(oid) and is_instance_valid(rows[oid]):
		var size = dl_http.get_body_size()
		if size > 0: rows[oid].get_node("Get").text = "%d%%" % int(100.0 * dl_http.get_downloaded_bytes() / size)

func _on_download(result, code, _headers, _body):
	var oid = int(dl_current.id)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish_download(oid, "!download failed (result %d, HTTP %d)" % [result, code])
		return
	state[oid] = "installing"
	_refresh_row(oid)
	yield(get_tree(), "idle_frame") # show "Installing..." before the work
	var path = dl_http.download_file
	var sid = _install_rhm(dl_current, path) if path.ends_with(".rhm") else _install_sspm(dl_current, path)
	_finish_download(oid, sid)

# res = installed song id, or an error message starting with "!"
func _finish_download(oid:int, res:String):
	var b = dl_current
	dl_current = null
	if res.begins_with("!"):
		state[oid] = "failed"
		Globals.notify(Globals.NOTIFY_ERROR, "%s: %s" % [str(b.get("title", oid)), res.trim_prefix("!")], "Map download", 6)
	else:
		state.erase(oid)
		record[str(oid)] = res
		_save_json(RECORD, record)
		Globals.notify(Globals.NOTIFY_SUCCEED, str(b.get("title", res)), "Map downloaded", 3)
		_refresh_library()
		_index_library()
	_clear_tmp()
	_refresh_row(oid)
	if queue.empty() and hidden:
		queue_free()
		return
	_next_download()

func _install_sspm(b:Dictionary, path:String) -> String:
	var d = Directory.new()
	var dest = Globals.p("user://maps/rhythia_%d.sspm" % int(b.id))
	if d.file_exists(dest): d.remove(dest)
	if d.rename(path, dest) != OK: return "!couldn't move the map into the maps folder"
	var s = Song.new()
	var r = s.load_from_sspm(dest)
	if r is String:
		d.remove(dest)
		return "!" + r
	var reg = Rhythia.registry_song
	var have = reg.get_item(s.id)
	if have and str(have.filePath) != dest:
		d.remove(dest) # the same map is already in the library
		return s.id
	reg.check_and_remove_id(s.id)
	reg.add_item(s)
	return s.id

func _install_rhm(b:Dictionary, path:String) -> String:
	var oid = int(b.id)
	var sid = "rhythia_%d" % oid
	var reg = Rhythia.registry_song
	if reg.get_item(sid): return sid
	var dir = Globals.p(TMP) + "/%d" % oid
	var d = Directory.new()
	d.make_dir_recursive(dir)
	var err = _unzip(path, dir)
	if err != "":
		if OS.get_name() == "Android": return "!couldn't unpack the .rhm file (" + err + ")"
		var out = [] # fall back to tar.exe on Windows, unzip elsewhere (GNU tar can't read zips)
		var src = ProjectSettings.globalize_path(path)
		var dst = ProjectSettings.globalize_path(dir)
		var code:int
		if OS.get_name() == "Windows": # (one command line there, so the paths need quotes)
			code = OS.execute("tar", ["-xf", '"%s"' % src, "-C", '"%s"' % dst], true, out, true)
		else:
			code = OS.execute("unzip", ["-o", "-q", src, "-d", dst], true, out, true)
		if code != 0: return "!couldn't unpack the .rhm file (%s; exit %d)" % [err, code]
	var f = File.new()
	if f.open(dir + "/map", File.READ) != OK: return "!the .rhm file has no map data"
	var m = parse_json(f.get_as_text())
	f.close()
	if typeof(m) != TYPE_DICTIONARY or !(m.get("Notes") is Array) or m.Notes.empty(): return "!unreadable map data"
	var audio = dir + "/audio"
	if f.open(audio, File.READ) != OK: return "!the .rhm file has no audio"
	var head = f.get_buffer(4).get_string_from_ascii()
	f.close()
	var ext = "ogg" if head == "OggS" else "mp3"
	d.rename(audio, audio + "." + ext)
	audio += "." + ext

	var mappers = m.get("Mappers")
	var creator = PoolStringArray(mappers).join(", ") if mappers is Array else str(b.get("ownerUsername", ""))
	var title = str(m.Title) if m.get("Title") else str(b.get("title", sid))
	var s = Song.new(sid, title, creator)
	if m.get("SongName"): s.song = str(m.SongName)
	# .rhm X/Y = .sspm note positions; the game's text format stores 2 - x / 2 - y
	var parts = PoolStringArray([sid])
	for n in m.Notes:
		parts.append("%s|%s|%d" % [str(2.0 - float(n.X)), str(2.0 - float(n.Y)), int(n.Time)])
	s.setup_from_data(parts.join(","), audio)
	s.difficulty = int(clamp(int(m.get("Difficulty", 0)) - 1, -1, 4))
	if m.get("CustomDifficultyName"): s.custom_data["difficulty_name"] = str(m.CustomDifficultyName)
	if f.open(dir + "/cover", File.READ) == OK:
		var tex = _texture(f.get_buffer(f.get_len()))
		f.close()
		if tex:
			s.cover = tex
			s.has_cover = true
	var r = s.convert_to_sspm()
	if str(r) != "Converted!": return "!" + str(r)
	reg.check_and_remove_id(sid)
	if reg.add_sspm_map(Globals.p("user://maps/%s.sspm") % sid) == null: return "!the converted map didn't load"
	return sid

# .rhm files are zips. Godot 3 has no zip reader and no shell tar on Android, so: read the zip
# directory, and inflate each deflated entry as a gzip stream built from the entry's own CRC and
# size (Godot decompresses gzip). Returns "" when done, else what went wrong.
static func _u16(b:PoolByteArray, i:int) -> int:
	return b[i] | (b[i + 1] << 8)

static func _u32(b:PoolByteArray, i:int) -> int:
	return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)

static func _le32(v:int) -> PoolByteArray:
	return PoolByteArray([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255])

static func _unzip(path:String, dir:String) -> String:
	var f = File.new()
	if f.open(path, File.READ) != OK: return "can't open the download"
	var b:PoolByteArray = f.get_buffer(f.get_len())
	f.close()
	var n = b.size()
	var eocd = -1
	var i = n - 22
	while i >= max(0, n - 65557):
		if b[i] == 0x50 and b[i + 1] == 0x4b and b[i + 2] == 5 and b[i + 3] == 6:
			eocd = i
			break
		i -= 1
	if eocd < 0: return "not a zip file"
	var count = _u16(b, eocd + 10)
	var p = _u32(b, eocd + 16)
	var d = Directory.new()
	for _e in count:
		if p + 46 > n or _u32(b, p) != 0x02014b50: return "broken zip directory"
		var method = _u16(b, p + 10)
		var crc = _u32(b, p + 16)
		var csize = _u32(b, p + 20)
		var usize = _u32(b, p + 24)
		var nlen = _u16(b, p + 28)
		var skip = nlen + _u16(b, p + 30) + _u16(b, p + 32)
		var loc = _u32(b, p + 42)
		var name = b.subarray(p + 46, p + 45 + nlen).get_string_from_utf8()
		p += 46 + skip
		if name.ends_with("/") or name.find("..") != -1: continue
		if loc + 30 > n: return "broken zip entry"
		var start = loc + 30 + _u16(b, loc + 26) + _u16(b, loc + 28)
		var data = PoolByteArray()
		if csize > 0:
			if start + csize > n: return "truncated zip"
			data = b.subarray(start, start + csize - 1)
		if method == 8:
			var gz = PoolByteArray([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff])
			gz.append_array(data)
			gz.append_array(_le32(crc))
			gz.append_array(_le32(usize))
			data = gz.decompress(usize, File.COMPRESSION_GZIP) if usize > 0 else PoolByteArray()
			if data.size() != usize: return "couldn't inflate " + name
		elif method != 0: return "unsupported zip compression %d" % method
		var out = dir + "/" + name
		d.make_dir_recursive(out.get_base_dir())
		if f.open(out, File.WRITE) != OK: return "can't write " + name
		f.store_buffer(data)
		f.close()
	return ""

func _refresh_library():
	var list = get_tree().root.get_node_or_null("Menu/Main/Maps/MapRegistry/S/VBoxContainer")
	if list and list.has_method("prepare_songs"):
		list.prepare_songs()
		list.build_list()

# ------------------------------------------------------------------ files
func _clear_tmp():
	if dl_current != null: return
	if Directory.new().dir_exists(Globals.p(TMP)): _rm_tree(Globals.p(TMP))

func _rm_tree(path:String):
	var d = Directory.new()
	if d.open(path) != OK: return
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if d.current_is_dir(): _rm_tree(path + "/" + n)
		else: d.remove(path + "/" + n)
		n = d.get_next()
	d.list_dir_end()
	Directory.new().remove(path)

static func _load_json(path:String) -> Dictionary:
	var f = File.new()
	if f.open(Globals.p(path), File.READ) != OK: return {}
	var d = parse_json(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

static func _save_json(path:String, d:Dictionary):
	var f = File.new()
	if f.open(Globals.p(path), File.WRITE) == OK:
		f.store_string(to_json(d))
		f.close()

func _open_maps():
	OS.shell_open(ProjectSettings.globalize_path(Globals.p("user://maps")))

# ------------------------------------------------------------------ open / close
# Closing only hides the browser; it frees itself once its downloads are done.
# The menu page underneath (map list) reacts to typing/wheel/F2 from its own _input (its search box
# grabs focus on any key), so it is hidden while the browser is open, like switching sidebar pages.
var covered_pages:Array = []
func _cover_pages(on:bool):
	if on:
		var main = get_parent().get_node_or_null("Main") if get_parent() else null
		if main:
			for p in main.get_children():
				if p is Control and p.visible:
					p.visible = false
					covered_pages.append(p)
	else:
		for p in covered_pages:
			if is_instance_valid(p): p.visible = true
		covered_pages = []

func _exit_tree():
	_cover_pages(false)
	_stop_covers()

func show_browser():
	hidden = false
	if rows_box:
		_index_library() # maps may have been imported/deleted while it was hidden
		for oid in rows.keys(): _refresh_row(oid)
	_cover_pages(true)
	bg.visible = true
	panel.visible = true
	set_process_input(true)
	UIAnim.play(bg, Vector2.ZERO, Vector2.ZERO, 0.0, 1.0, 0.25)
	UIAnim.play(panel, Vector2(0, panel.get_viewport_rect().size.y), Vector2.ZERO, 1.0, 1.0, 0.5) # slide up

func close():
	if hidden: return
	hidden = true
	set_process_input(false)
	_cover_pages(false)
	UIAnim.play(panel, Vector2.ZERO, Vector2(0, panel.get_viewport_rect().size.y), 1.0, 1.0, 0.3) # back down
	UIAnim.play(bg, Vector2.ZERO, Vector2.ZERO, 1.0, 0.0, 0.3).connect("finished", self, "_after_close")

func _after_close():
	if !hidden: return
	bg.visible = false
	panel.visible = false
	if dl_current == null and queue.empty(): queue_free()

func _input(ev):
	if ev is InputEventKey and ev.pressed and ev.scancode == KEY_ESCAPE:
		get_tree().set_input_as_handled()
		close()
