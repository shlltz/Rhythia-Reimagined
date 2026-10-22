extends CanvasLayer
# Multiplayer screens (menu2 child "Multiplayer"): home (name, create / join, how to connect),
# create lobby, join lobby (address / room code, LAN lobbies, recent), the lobby (players on the
# right, map + rules + ready / start, chat) and the match results. Everything shown comes from
# MPClient (root "RRMultiplayer"); every button calls a client action the host then checks.

const P = preload("res://mods/replay/MPProto.gd")
const Relay = preload("res://mods/replay/MPRelay.gd")
const Look = preload("res://mods/replay/Look.gd")
const UIAnim = preload("res://mods/replay/UIAnim.gd")
const TOP_H = 56.0

var menu:Node
var client
var root:Control
var body:Control
var screens:Dictionary = {}
var screen:String = ""
var fonts:Dictionary = {}
var title_lbl:Label
var status_lbl:Label
var back_btn:Button
var toast:Label
var _toast_t:float = 0.0
var pick_bar:Control
var picking:bool = false
var covered:Array = []
var results_on:bool = false

# home
var name_edit:LineEdit
# create
var c_name:LineEdit
var c_pw:LineEdit
var c_max:int = 8
var c_max_lbl:Label
var c_port:LineEdit
var c_status:Label
var c_btn:Button
var c_online_btn:Button
var c_relay:LineEdit
var j_relay:LineEdit
# join
var j_addr:LineEdit
var j_pw:LineEdit
var j_status:Label
var j_btn:Button
var j_lan:VBoxContainer
var j_lan_note:Label
var j_recent:VBoxContainer
# lobby
var l_name:Label
var l_sub:Label
var l_code_btn:Button
var l_map_name:Label
var l_map_sub:Label
var l_map_state:Label
var l_rules:Label
var l_host_row:HBoxContainer
var l_speed_lbl:Label
var l_mods_row:GridContainer
var l_mod_btns:Dictionary = {}
var l_ready_btn:Button
var l_start_btn:Button
var l_abort_btn:Button
var l_settings_btn:Button
var l_why:Label
var l_settings_row:HBoxContainer
var s_name:LineEdit
var s_pw:LineEdit
var s_max:int = 8
var s_max_lbl:Label
var l_players_hdr:Label
var l_players:VBoxContainer
var l_chat_scroll:ScrollContainer
var l_chat:VBoxContainer
var l_chat_in:LineEdit
var l_results:Panel
var l_left:Control
var r_title:Label
var r_sub:Label
var r_list:VBoxContainer
var r_again:Button

func _ready():
	layer = 18
	pause_mode = PAUSE_MODE_PROCESS
	menu = get_parent()
	client = load("res://mods/replay/MPClient.gd").get_client(get_tree())
	root = Control.new()
	root.anchor_right = 1
	root.anchor_bottom = 1
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists("res://uitheme.tres"): root.theme = load("res://uitheme.tres")
	add_child(root)
	var bg = ColorRect.new()
	bg.color = Look.BG
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	_build_top()
	body = Control.new()
	body.anchor_right = 1
	body.anchor_bottom = 1
	body.margin_top = TOP_H
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)
	_build_home()
	_build_create()
	_build_join()
	_build_lobby()
	_build_pick_bar()
	toast = _lbl("", 16, Look.TEXT)
	toast.anchor_left = 0.5; toast.anchor_right = 0.5; toast.anchor_top = 1; toast.anchor_bottom = 1
	toast.margin_left = -420; toast.margin_right = 420; toast.margin_top = -64; toast.margin_bottom = -30
	toast.align = Label.ALIGN_CENTER
	toast.autowrap = true
	toast.modulate.a = 0
	root.add_child(toast)
	client.connect("changed", self, "_changed")
	client.connect("notice", self, "_notice")
	_cover(true)
	_show("lobby" if client.connected_or_trying() else "home")
	if Engine.has_meta("rr_mp_results"):
		Engine.remove_meta("rr_mp_results")
		_set_results(true)
	UIAnim.play(root, Vector2(0, 18), Vector2.ZERO, 0.0, 1.0, 0.25)

func _exit_tree():
	_cover(false)
	if client and is_instance_valid(client):
		client.lan_listen(false)
		if client.is_connected("changed", self, "_changed"): client.disconnect("changed", self, "_changed")
		if client.is_connected("notice", self, "_notice"): client.disconnect("notice", self, "_notice")
	if picking:
		Engine.remove_meta("rr_mp_picking")
		_pick_mode_page(false)

# the menu pages stay hidden behind the lobby (the map search grabs typed keys, Space starts a map)
func _cover(on:bool):
	if on:
		var main = menu.get_node_or_null("Main")
		if main:
			for c in main.get_children():
				if c is CanvasItem and c.visible and !(c in covered):
					c.visible = false
					covered.append(c)
	else:
		for c in covered:
			if is_instance_valid(c): c.visible = true
		covered = []

# ---------------------------------------------------------------- building blocks
func _font(size:int):
	if fonts.has(size): return fonts[size]
	var base = root.get_font("font", "Label")
	var f = base
	if base is DynamicFont:
		f = base.duplicate()
		f.size = size
	f = load("res://mods/replay/Reimagined.gd").heading_font(f, size)
	fonts[size] = f
	return f

func _lbl(text:String, size:int = 15, col:Color = Look.TEXT_2) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", _font(size))
	l.add_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _btn(text:String, method:String, args:Array = [], w:int = 0, h:int = 40, toggle:bool = false) -> Button:
	var b = Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.add_font_override("font", _font(15))
	b.rect_min_size = Vector2(w, h)
	b.add_stylebox_override("normal", Look.box(Look.SURFACE, Look.LINE_HI, 1, 0))
	for st in ["hover", "pressed", "hover_pressed"]: b.add_stylebox_override(st, Look.box(Look.accent(), Look.accent(), 1, 0))
	b.add_stylebox_override("disabled", Look.box(Look.BG, Look.LINE, 1, 0))
	b.add_color_override("font_color", Look.TEXT)
	for st in ["font_color_hover", "font_color_pressed", "font_color_hover_pressed"]: b.add_color_override(st, Look.on_accent())
	b.add_color_override("font_color_disabled", Look.TEXT_3)
	b.connect("toggled" if toggle else "pressed", self, method, args)
	return b

func _edit(placeholder:String, w:int = 0) -> LineEdit:
	var e = LineEdit.new()
	e.placeholder_text = placeholder
	e.rect_min_size = Vector2(w, 40)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_font_override("font", _font(15))
	e.add_stylebox_override("normal", Look.box(Look.SURFACE, Look.LINE_HI, 1, 0))
	e.add_stylebox_override("focus", Look.box(Look.SURFACE_HI, Look.accent(), 1, 0))
	e.add_stylebox_override("read_only", Look.box(Look.BG, Look.LINE, 1, 0))
	e.add_color_override("font_color", Look.TEXT)
	e.add_color_override("font_color_uneditable", Look.TEXT_3)
	return e

# a padded vertical box in a framed panel: [panel, vbox]
func _card(parent:Control, sep:int = 8) -> Array:
	var p = PanelContainer.new()
	var sb = Look.box(Look.SURFACE, Look.LINE, 1, 0)
	sb.content_margin_left = 16; sb.content_margin_right = 16; sb.content_margin_top = 12; sb.content_margin_bottom = 12
	p.add_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v = VBoxContainer.new()
	v.add_constant_override("separation", sep)
	p.add_child(v)
	return [p, v]

func _row(parent:Control, sep:int = 8) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_constant_override("separation", sep)
	parent.add_child(h)
	return h

# a scrolling page with a centred column w px wide: [scroll, column]
func _centre_column(w:float) -> Array:
	var sc = ScrollContainer.new()
	sc.anchor_right = 1
	sc.anchor_bottom = 1
	sc.scroll_horizontal_enabled = false
	var cc = CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(cc)
	var v = VBoxContainer.new()
	v.rect_min_size.x = w
	v.add_constant_override("separation", 12)
	cc.add_child(v)
	return [sc, v]

func _vw() -> float:
	return get_viewport().get_visible_rect().size.x

# ---------------------------------------------------------------- top bar
func _build_top():
	var top = Panel.new()
	top.add_stylebox_override("panel", Look.box(Look.SURFACE, Look.LINE, 1, 0))
	top.anchor_right = 1
	top.margin_bottom = TOP_H
	root.add_child(top)
	title_lbl = _lbl("// MULTIPLAYER", 26, Look.TEXT)
	title_lbl.rect_position = Vector2(20, 12)
	top.add_child(title_lbl)
	status_lbl = _lbl("", 14, Look.TEXT_3)
	status_lbl.rect_position = Vector2(270, 19)
	top.add_child(status_lbl)
	back_btn = _btn("BACK", "_back", [], 170, 38)
	back_btn.anchor_left = 1; back_btn.anchor_right = 1
	back_btn.margin_left = -186; back_btn.margin_right = -16; back_btn.margin_top = 9; back_btn.margin_bottom = 47
	top.add_child(back_btn)

func _back():
	match screen:
		"lobby": _confirm_leave()
		"create", "join": _show("home")
		_: queue_free()

var _leave_armed:int = 0
func _confirm_leave():
	if !client.connected_or_trying():
		_show("home")
		return
	if _leave_armed > 0 and OS.get_ticks_msec() - _leave_armed < 2500:
		_leave_armed = 0
		client.leave()
		_set_results(false)
		_show("home")
		return
	_leave_armed = OS.get_ticks_msec()
	back_btn.text = "LEAVE? (again)"
	_notice("Press LEAVE again to leave the lobby" + (" - this closes it for everyone" if client.hosting() else ""), false)

func _show(s:String):
	screen = s
	for k in screens: screens[k].visible = k == s
	client.lan_listen(s == "join")
	match s:
		"home":
			back_btn.text = "BACK"
			name_edit.text = client.my_name
			results_on = false
		"create":
			back_btn.text = "BACK"
			if c_name.text == "": c_name.text = "%s's lobby" % client.my_name
			c_status.text = ""
			c_btn.disabled = false
			c_online_btn.disabled = false
			c_relay.text = str(client._cfg("mp_relay", ""))
		"join":
			back_btn.text = "BACK"
			j_status.text = ""
			j_btn.disabled = false
			_refresh_recent()
			_refresh_lan()
		"lobby":
			back_btn.text = "LEAVE LOBBY"
			_refresh_lobby()
			_refresh_players()
			_refresh_chat()
	_refresh_status()

# the host's view of its relay tunnel: what players can do right now
func _tunnel_status() -> String:
	var h = client.host_node
	if !h or !is_instance_valid(h) or !h.tunnel: return "LAN"
	var tu = h.tunnel
	match tu.state:
		"connecting": return "CONNECTING TO THE RELAY"
		"creating": return "CREATING ROOM"
		"ready":
			var n = 0
			for c in h.conns:
				if c.relayed and c.pid > 0: n += 1
			return ("ONLINE %s   /   " % tu.code) + (("%d VIA RELAY" % n) if n > 0 else "WAITING FOR PLAYERS") + (("   /   RELAY %d MS" % tu.relay_rtt) if tu.relay_rtt >= 0 else "")
		"reconnecting": return ("RELAY: RECONNECTING (%s)" % tu.error_text.to_upper()) if tu.error_text != "" else "RELAY: RECONNECTING"
		"failed": return "RELAY FAILED: " + tu.error_text.to_upper()
	return "LAN"

func _refresh_status():
	var t = ""
	match client.status:
		"idle": t = ""
		"online":
			t = ("%d MS" % client.rtt) if client.rtt >= 0 else "ONLINE"
			if client.relayed():
				var rr = client.relay_rtt()
				var j = client.jitter()
				t = "RELAYED   /   PING " + t + ((" (%d TO RELAY)" % rr) if rr >= 0 else "") + (("   /   JITTER %d MS" % j) if j >= 0 else "")
			elif client.hosting(): t = "HOSTING   /   " + _tunnel_status()
			else: t = "DIRECT   /   PING " + t
		"reconnecting": t = "RECONNECTING..."
		_: t = client.status_text.to_upper()
	status_lbl.text = t

# ---------------------------------------------------------------- home
func _build_home():
	var col = _centre_column(min(680.0, _vw() - 48))
	body.add_child(col[0])
	screens["home"] = col[0]
	var v = col[1]
	v.add_child(_lbl("YOUR NAME", 13, Look.TEXT_3))
	var r = _row(v)
	name_edit = _edit("your name in lobbies")
	name_edit.max_length = P.NAME_MAX
	name_edit.connect("text_entered", self, "_save_name")
	r.add_child(name_edit)
	r.add_child(_btn("SAVE", "_save_name_btn", [], 110))
	var note = _lbl("Only a display name for lobbies - no account, no password. Others may use the same name.", 13, Look.TEXT_3)
	note.autowrap = true
	v.add_child(note)
	var gap = Control.new()
	gap.rect_min_size.y = 8
	v.add_child(gap)
	var r2 = _row(v, 12)
	var cb = _btn("CREATE LOBBY", "_go_create", [], 0, 56)
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.add_font_override("font", _font(18))
	r2.add_child(cb)
	var jb = _btn("JOIN LOBBY", "_go_join", [], 0, 56)
	jb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jb.add_font_override("font", _font(18))
	r2.add_child(jb)
	var c = _card(v, 6)
	c[1].add_child(_lbl("HOW TO CONNECT", 13, Look.TEXT_3))
	for line in [
		"Same network (home Wi-Fi / LAN): one player creates a lobby, the others open JOIN and pick it from LAN lobbies, or type the room code or address shown in the lobby.",
		"Over the internet: CREATE LOBBY > HOST ONLINE opens the lobby through a relay server - no port forwarding, VPN or IP addresses. Share the room code or the invite link; friends paste it into JOIN. This needs a relay server address: this game has none built in, so use one your community runs or run your own (relay/ folder, docs/RELAY.md).",
		"Without a relay: the host forwards TCP port %d on their router and shares their public IP (e.g. 203.0.113.7:%d), or everyone joins the same virtual LAN (Tailscale, ZeroTier, Radmin VPN)." % [P.PORT, P.PORT],
		"Firewall: allow SoundSpacePlus.exe when Windows asks (TCP %d for lobbies, UDP %d for finding lobbies on the LAN). Phones on mobile data can usually join but not host." % [P.PORT, P.LAN_PORT],
		"Everyone needs the same map in their library. Multiplayer always plays with No Fail; scores here are session results, not verified records."]:
		var l = _lbl(line, 14, Look.TEXT_2)
		l.autowrap = true
		c[1].add_child(l)

func _save_name_btn():
	_save_name(name_edit.text)

func _save_name(t:String):
	client.set_my_name(t)
	name_edit.text = client.my_name
	name_edit.release_focus()
	_notice("Name saved: " + client.my_name, false)

func _go_create():
	if name_edit.text != client.my_name: _save_name(name_edit.text)
	_show("create")

func _go_join():
	if name_edit.text != client.my_name: _save_name(name_edit.text)
	_show("join")

# ---------------------------------------------------------------- create
func _build_create():
	var col = _centre_column(min(620.0, _vw() - 48))
	body.add_child(col[0])
	screens["create"] = col[0]
	var v = col[1]
	v.add_child(_lbl("CREATE LOBBY", 22, Look.TEXT))
	v.add_child(_lbl("LOBBY NAME", 13, Look.TEXT_3))
	c_name = _edit("lobby name")
	c_name.max_length = P.LOBBY_NAME_MAX
	v.add_child(c_name)
	v.add_child(_lbl("PASSWORD (optional)", 13, Look.TEXT_3))
	c_pw = _edit("leave empty for an open lobby")
	c_pw.secret = true
	c_pw.max_length = P.PW_MAX
	v.add_child(c_pw)
	var r = _row(v, 16)
	var a = VBoxContainer.new()
	r.add_child(a)
	a.add_child(_lbl("PLAYERS", 13, Look.TEXT_3))
	var mr = _row(a, 6)
	mr.add_child(_btn("-", "_c_max", [-1], 44))
	c_max_lbl = _lbl(str(c_max), 18, Look.TEXT)
	c_max_lbl.rect_min_size = Vector2(44, 40)
	c_max_lbl.align = Label.ALIGN_CENTER
	c_max_lbl.valign = Label.VALIGN_CENTER
	mr.add_child(c_max_lbl)
	mr.add_child(_btn("+", "_c_max", [1], 44))
	var b = VBoxContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(b)
	b.add_child(_lbl("PORT (TCP)", 13, Look.TEXT_3))
	c_port = _edit(str(P.PORT))
	c_port.text = str(P.PORT)
	b.add_child(c_port)
	var note = _lbl("Your game hosts the lobby while you play - keep it open. On this network, others connect to your address on this port.", 13, Look.TEXT_3)
	note.autowrap = true
	v.add_child(note)
	v.add_child(_lbl("RELAY SERVER (for HOST ONLINE)", 13, Look.TEXT_3))
	c_relay = _edit("relay.example.org")
	c_relay.text = str(client._cfg("mp_relay", ""))
	v.add_child(c_relay)
	var br = _row(v, 12)
	c_btn = _btn("CREATE LAN LOBBY", "_create", [false], 0, 52)
	c_btn.add_font_override("font", _font(18))
	c_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(c_btn)
	c_online_btn = _btn("HOST ONLINE", "_create", [true], 0, 52)
	c_online_btn.add_font_override("font", _font(18))
	c_online_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(c_online_btn)
	c_status = _lbl("", 14, Look.TEXT_2)
	c_status.autowrap = true
	v.add_child(c_status)

func _c_max(d:int):
	c_max = int(clamp(c_max + d, 2, P.MAX_PLAYERS))
	c_max_lbl.text = str(c_max)

func _create(online:bool = false):
	var port = int(c_port.text) if c_port.text.strip_edges().is_valid_integer() else -1
	if port < 1024 or port > 65535:
		c_status.text = "Use a port between 1024 and 65535 (default %d)." % P.PORT
		c_status.add_color_override("font_color", Look.CRIT)
		return
	var relay = ""
	if online:
		relay = Relay.base_url(c_relay.text)
		if relay == "":
			c_status.add_color_override("font_color", Look.CRIT)
			c_status.text = "HOST ONLINE needs a relay server address (like relay.example.org). This game has none built in: use one your community runs, or run your own (docs/RELAY.md)." if c_relay.text.strip_edges() == "" else "That relay address isn't usable. Type a name like relay.example.org (or wss://... / ws://127.0.0.1:8080 for a local test relay)."
			return
		client._cfg_set("mp_relay", c_relay.text.strip_edges())
	c_btn.disabled = true
	c_online_btn.disabled = true
	c_status.add_color_override("font_color", Look.TEXT_2)
	c_status.text = "Creating the room..." if online else "Starting the lobby..."
	var err = client.host_lobby({name = c_name.text, pw = c_pw.text, max = c_max, port = port, relay = relay})
	if err != "":
		c_btn.disabled = false
		c_online_btn.disabled = false
		c_status.add_color_override("font_color", Look.CRIT)
		c_status.text = err
		return
	_show("lobby")

# ---------------------------------------------------------------- join
func _build_join():
	var vw = _vw()
	var col = _centre_column(min(1000.0, vw - 48))
	body.add_child(col[0])
	screens["join"] = col[0]
	var v = col[1]
	v.add_child(_lbl("JOIN LOBBY", 22, Look.TEXT))
	var cols = HBoxContainer.new() if vw > 900 else VBoxContainer.new()
	cols.add_constant_override("separation", 16)
	v.add_child(cols)
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.3
	left.rect_min_size.x = 380 if vw > 900 else 0
	left.add_constant_override("separation", 8)
	cols.add_child(left)
	left.add_child(_lbl("INVITE LINK, ROOM CODE OR ADDRESS", 13, Look.TEXT_3))
	j_addr = _edit("https://relay.example.org/j/ABCD-EFGH  or  ABCD-EFGH  or  192.168.1.20:%d" % P.PORT)
	j_addr.connect("text_entered", self, "_join_entered")
	left.add_child(j_addr)
	left.add_child(_lbl("PASSWORD (if the lobby has one)", 13, Look.TEXT_3))
	j_pw = _edit("")
	j_pw.secret = true
	j_pw.connect("text_entered", self, "_join_entered")
	left.add_child(j_pw)
	left.add_child(_lbl("RELAY SERVER (only for a bare online code; invite links carry it)", 13, Look.TEXT_3))
	j_relay = _edit("relay.example.org")
	j_relay.text = str(client._cfg("mp_relay", ""))
	left.add_child(j_relay)
	j_btn = _btn("JOIN", "_join", [], 0, 52)
	j_btn.add_font_override("font", _font(18))
	left.add_child(j_btn)
	j_status = _lbl("", 14, Look.TEXT_2)
	j_status.autowrap = true
	left.add_child(j_status)
	left.add_child(_lbl("RECENT", 13, Look.TEXT_3))
	j_recent = VBoxContainer.new()
	left.add_child(j_recent)
	var right = _card(cols, 6)
	right[0].rect_min_size.x = 340 if vw > 900 else 0
	right[1].add_child(_lbl("LAN LOBBIES", 13, Look.TEXT_3))
	j_lan_note = _lbl("Looking for lobbies on this network...", 13, Look.TEXT_3)
	j_lan_note.autowrap = true
	right[1].add_child(j_lan_note)
	j_lan = VBoxContainer.new()
	j_lan.add_constant_override("separation", 6)
	right[1].add_child(j_lan)

func _join_entered(_t):
	_join()

func _join():
	var inv = Relay.parse_invite(j_addr.text)
	if !inv.empty():
		var base = inv.base
		if base == "":
			base = Relay.base_url(j_relay.text)
			if base == "":
				j_status.add_color_override("font_color", Look.CRIT)
				j_status.text = "%s is an online room code: paste the host's invite link instead, or type the relay server it uses under RELAY SERVER." % inv.code
				return
			client._cfg_set("mp_relay", j_relay.text.strip_edges())
		j_btn.disabled = true
		j_status.add_color_override("font_color", Look.TEXT_2)
		j_status.text = "Joining room %s through %s ..." % [inv.code, base.replace("wss://", "").replace("ws://", "")]
		client.join_online(base, inv.code, j_pw.text)
		return
	var a = P.parse_address(j_addr.text)
	if a.empty():
		j_status.add_color_override("font_color", Look.CRIT)
		j_status.text = "Paste an invite link, an online room code like ABCD-EFGH, a LAN room code like ABCDE-FGHJK, or an address like 192.168.1.20:%d." % P.PORT
		return
	_join_to(a[0], a[1], j_pw.text)

func _join_to(host:String, port:int, pw:String):
	j_btn.disabled = true
	j_status.add_color_override("font_color", Look.TEXT_2)
	j_status.text = "Connecting to %s:%d ..." % [host, port]
	client.join(host, port, pw)

func _refresh_recent():
	for c in j_recent.get_children(): c.queue_free()
	for a in client._cfg("mp_recent", []):
		var b = _btn(str(a), "_recent_pick", [str(a)], 0, 34)
		b.align = Button.ALIGN_LEFT
		j_recent.add_child(b)

func _recent_pick(a:String):
	j_addr.text = a
	_join()

func _refresh_lan():
	if screen != "join": return
	for c in j_lan.get_children(): c.queue_free()
	if client.lan_error != "": j_lan_note.text = client.lan_error
	elif client.lan.empty(): j_lan_note.text = "Looking for lobbies on this network... (none yet)"
	else: j_lan_note.text = "Found on this network:"
	for k in client.lan.keys():
		var e = client.lan[k]
		var r = HBoxContainer.new()
		r.add_constant_override("separation", 8)
		var info = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_lbl(("[password] " if e.pw else "") + (e.name if e.name != "" else "lobby"), 15, Look.TEXT))
		info.add_child(_lbl("%d/%d players   /   %s%s   /   %s" % [e.n, e.max, e.state, (" - " + e.map) if e.map != "" else "", k], 12, Look.TEXT_3))
		r.add_child(info)
		r.add_child(_btn("JOIN", "_lan_join", [e.ip, e.port, e.pw], 80, 40))
		j_lan.add_child(r)

func _lan_join(ip:String, port:int, pw:bool):
	j_addr.text = "%s:%d" % [ip, port]
	if pw and j_pw.text == "":
		j_status.add_color_override("font_color", Look.TEXT_2)
		j_status.text = "This lobby has a password: type it above, then JOIN."
		j_pw.grab_focus()
		return
	_join_to(ip, port, j_pw.text)

# ---------------------------------------------------------------- lobby
func _build_lobby():
	var vw = _vw()
	var lb = Control.new()
	lb.anchor_right = 1
	lb.anchor_bottom = 1
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(lb)
	screens["lobby"] = lb
	var right_w = clamp(vw * 0.28, 260.0, 380.0)
	# players, on the right
	var pr = PanelContainer.new()
	var psb = Look.box(Look.SURFACE, Look.LINE, 1, 0)
	psb.content_margin_left = 12; psb.content_margin_right = 12; psb.content_margin_top = 12; psb.content_margin_bottom = 12
	pr.add_stylebox_override("panel", psb)
	pr.anchor_left = 1; pr.anchor_right = 1; pr.anchor_bottom = 1
	pr.margin_left = -right_w - 16; pr.margin_right = -16; pr.margin_top = 16; pr.margin_bottom = -16
	lb.add_child(pr)
	var pv = VBoxContainer.new()
	pv.add_constant_override("separation", 8)
	pr.add_child(pv)
	l_players_hdr = _lbl("PLAYERS", 13, Look.TEXT_3)
	pv.add_child(l_players_hdr)
	var psc = ScrollContainer.new()
	psc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	psc.scroll_horizontal_enabled = false
	pv.add_child(psc)
	l_players = VBoxContainer.new()
	l_players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_players.add_constant_override("separation", 6)
	psc.add_child(l_players)
	# left column: info, map + rules, actions, chat
	var left = VBoxContainer.new()
	left.anchor_right = 1; left.anchor_bottom = 1
	left.margin_left = 16; left.margin_top = 16; left.margin_right = -right_w - 32; left.margin_bottom = -16
	left.add_constant_override("separation", 10)
	lb.add_child(left)
	l_left = left
	var info = _card(left, 4)
	l_name = _lbl("", 22, Look.TEXT)
	l_name.clip_text = true
	info[1].add_child(l_name)
	var ir = _row(info[1], 10)
	l_sub = _lbl("", 13, Look.TEXT_3)
	l_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_sub.autowrap = true
	ir.add_child(l_sub)
	l_code_btn = _btn("COPY CODE", "_copy_code", [], 120, 32)
	ir.add_child(l_code_btn)
	var mp = _card(left, 6)
	mp[1].add_child(_lbl("MAP", 13, Look.TEXT_3))
	l_map_name = _lbl("", 19, Look.TEXT)
	l_map_name.clip_text = true
	mp[1].add_child(l_map_name)
	l_map_sub = _lbl("", 13, Look.TEXT_2)
	l_map_sub.clip_text = true
	mp[1].add_child(l_map_sub)
	l_map_state = _lbl("", 13, Look.TEXT_2)
	l_map_state.autowrap = true
	mp[1].add_child(l_map_state)
	l_host_row = _row(mp[1], 8)
	l_host_row.add_child(_btn("SELECT MAP", "_pick_begin", [], 150, 38))
	l_host_row.add_child(_btn("-", "_speed", [-0.05], 38, 38))
	l_speed_lbl = _lbl("1.00x", 16, Look.TEXT)
	l_speed_lbl.rect_min_size = Vector2(64, 38)
	l_speed_lbl.align = Label.ALIGN_CENTER
	l_speed_lbl.valign = Label.VALIGN_CENTER
	l_host_row.add_child(l_speed_lbl)
	l_host_row.add_child(_btn("+", "_speed", [0.05], 38, 38))
	l_mods_row = GridContainer.new()
	l_mods_row.columns = 5 if vw > 1200 else 3
	l_mods_row.add_constant_override("hseparation", 6)
	l_mods_row.add_constant_override("vseparation", 6)
	mp[1].add_child(l_mods_row)
	for m in P.HOST_MODS:
		var mb = _btn(m[1], "_mod_toggle", [m[0]], 0, 32, true)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.add_font_override("font", _font(13))
		l_mods_row.add_child(mb)
		l_mod_btns[m[0]] = mb
	l_rules = _lbl("", 13, Look.TEXT_3)
	l_rules.autowrap = true
	mp[1].add_child(l_rules)
	var act = _row(left, 10)
	l_ready_btn = _btn("READY", "_ready_toggle", [], 170, 48, true)
	l_ready_btn.add_font_override("font", _font(18))
	act.add_child(l_ready_btn)
	l_start_btn = _btn("START MATCH", "_start", [], 190, 48)
	l_start_btn.add_font_override("font", _font(18))
	act.add_child(l_start_btn)
	l_abort_btn = _btn("STOP MATCH", "_abort", [], 160, 48)
	act.add_child(l_abort_btn)
	l_settings_btn = _btn("SETTINGS", "_settings_toggle", [], 120, 48, true)
	act.add_child(l_settings_btn)
	l_why = _lbl("", 13, Look.TEXT_3)
	l_why.autowrap = true
	l_why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act.add_child(l_why)
	l_settings_row = _row(left, 8)
	s_name = _edit("lobby name", 160)
	s_name.max_length = P.LOBBY_NAME_MAX
	l_settings_row.add_child(s_name)
	s_pw = _edit("new password (empty = none)", 160)
	s_pw.secret = true
	s_pw.max_length = P.PW_MAX
	l_settings_row.add_child(s_pw)
	l_settings_row.add_child(_btn("-", "_s_max", [-1], 38, 40))
	s_max_lbl = _lbl("8", 16, Look.TEXT)
	s_max_lbl.rect_min_size = Vector2(36, 40)
	s_max_lbl.align = Label.ALIGN_CENTER
	s_max_lbl.valign = Label.VALIGN_CENTER
	l_settings_row.add_child(s_max_lbl)
	l_settings_row.add_child(_btn("+", "_s_max", [1], 38, 40))
	l_settings_row.add_child(_btn("APPLY", "_s_apply", [], 90, 40))
	l_settings_row.visible = false
	var ch = _card(left, 6)
	ch[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	ch[1].add_child(_lbl("CHAT", 13, Look.TEXT_3))
	l_chat_scroll = ScrollContainer.new()
	l_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l_chat_scroll.scroll_horizontal_enabled = false
	l_chat_scroll.rect_min_size.y = 80
	ch[1].add_child(l_chat_scroll)
	l_chat = VBoxContainer.new()
	l_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_chat.add_constant_override("separation", 2)
	l_chat_scroll.add_child(l_chat)
	var cr = _row(ch[1], 8)
	l_chat_in = _edit("message (Enter to send)")
	l_chat_in.max_length = P.CHAT_MAX
	l_chat_in.connect("text_entered", self, "_chat_send")
	cr.add_child(l_chat_in)
	cr.add_child(_btn("SEND", "_chat_send_btn", [], 90, 40))
	# results, over the left column
	l_results = Panel.new()
	l_results.add_stylebox_override("panel", Look.box(Look.SURFACE, Look.LINE_HI, 1, 0))
	l_results.anchor_right = 1; l_results.anchor_bottom = 1
	l_results.margin_left = 16; l_results.margin_top = 16; l_results.margin_right = -right_w - 32; l_results.margin_bottom = -16
	l_results.mouse_filter = Control.MOUSE_FILTER_STOP
	lb.add_child(l_results)
	var rv = VBoxContainer.new()
	rv.anchor_right = 1; rv.anchor_bottom = 1
	rv.margin_left = 20; rv.margin_top = 16; rv.margin_right = -20; rv.margin_bottom = -16
	rv.add_constant_override("separation", 8)
	l_results.add_child(rv)
	r_title = _lbl("MATCH RESULTS", 24, Look.TEXT)
	rv.add_child(r_title)
	r_sub = _lbl("", 13, Look.TEXT_3)
	r_sub.autowrap = true
	rv.add_child(r_sub)
	var rsc = ScrollContainer.new()
	rsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rsc.scroll_horizontal_enabled = false
	rv.add_child(rsc)
	r_list = VBoxContainer.new()
	r_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_list.add_constant_override("separation", 6)
	rsc.add_child(r_list)
	var rb = _row(rv, 10)
	r_again = _btn("PLAY AGAIN", "_r_again", [], 170, 48)
	rb.add_child(r_again)
	rb.add_child(_btn("RETURN TO LOBBY", "_set_results", [false], 200, 48))
	rb.add_child(_btn("LEAVE LOBBY", "_r_leave", [], 160, 48))
	l_results.visible = false

func _copy_code():
	var c = str(client.lobby.get("code", ""))
	var inv = str(client.lobby.get("invite", ""))
	var addr = client.lobby.get("addr", [])
	OS.clipboard = inv if inv != "" else (c if c != "" else (str(addr[0]) if typeof(addr) == TYPE_ARRAY and addr.size() > 0 else ""))
	_notice("Copied: " + OS.clipboard, false)

func _refresh_lobby():
	if screen != "lobby": return
	_refresh_status() # (the room code / tunnel state can change with the lobby)
	var L = client.lobby
	var online = client.online()
	var host = client.is_host()
	l_name.text = str(L.get("name", "...")) if online else ("Joining..." if client.status != "idle" else "Not connected")
	var bits = []
	var code = str(L.get("code", ""))
	if code != "": bits.append(("ONLINE ROOM " if L.get("online", false) else "ROOM CODE ") + code)
	elif L.get("online", false): bits.append("ONLINE ROOM: " + (_tunnel_status().to_lower() if host else "creating..."))
	var addr = L.get("addr", [])
	if typeof(addr) == TYPE_ARRAY and addr.size() > 0: bits.append(PoolStringArray(addr).join("  "))
	if L.get("pw", false): bits.append("password")
	var hn = _name_of(int(L.get("host", 0)))
	if hn != "": bits.append("host: " + hn)
	if !online: bits = [client.status_text]
	l_sub.text = PoolStringArray(bits).join("   /   ")
	l_code_btn.visible = online and (code != "" or (typeof(addr) == TYPE_ARRAY and addr.size() > 0))
	l_code_btn.text = "COPY INVITE" if str(L.get("invite", "")) != "" else "COPY CODE"
	var m = L.get("map", {})
	if typeof(m) != TYPE_DICTIONARY or m.empty():
		l_map_name.text = "No map yet"
		l_map_sub.text = "Pick a map from your library: SELECT MAP." if host else "The host picks one."
		l_map_state.text = ""
	else:
		l_map_name.text = str(m.get("name", m.get("id", "")))
		var diffs = ["Easy", "Medium", "Hard", "Logic", "Tasukete"]
		var dn = int(m.get("diff", -1))
		l_map_sub.text = "by %s   /   %s   /   %d notes   /   %s" % [m.get("creator", "?"), diffs[dn] if dn >= 0 and dn < diffs.size() else "?", int(m.get("notes", 0)), P.fmt_len(float(m.get("len", 0)))]
		var missing = []
		var checking = []
		for p in client.players:
			if p.get("conn") != "ok": continue
			match str(p.get("have", "?")):
				"ok": pass
				"?": checking.append(str(p.name))
				"mismatch": missing.append(str(p.name) + " (different version)")
				_: missing.append(str(p.name))
		var st = ""
		if client.my_have == "missing": st = "You don't have this map. Get it into your library (the same version as the host's), then wait for the host to pick it again."
		elif client.my_have == "mismatch": st = "Your copy of this map is different from the host's (other notes or audio)."
		elif !missing.empty(): st = "Missing the map: " + PoolStringArray(missing).join(", ")
		elif !checking.empty(): st = "Checking the map: " + PoolStringArray(checking).join(", ")
		else: st = "Everyone has this map."
		l_map_state.text = st
		l_map_state.add_color_override("font_color", Look.CRIT.lightened(0.2) if (client.my_have in ["missing", "mismatch"] or !missing.empty()) else Look.TEXT_2)
	var r = P.clean_rules(L.get("rules", {}))
	l_rules.text = "RULES:  " + P.rules_text(r)
	var in_lobby = str(L.get("state", "lobby")) == "lobby"
	l_host_row.visible = host and online
	l_mods_row.visible = host and online
	l_speed_lbl.text = "%.2fx" % float(r.speed)
	for k in l_mod_btns:
		l_mod_btns[k].pressed = k in r.mods
		l_mod_btns[k].disabled = !in_lobby
	for c in l_host_row.get_children():
		if c is Button: c.disabled = !in_lobby
	var meready = bool(client.me().get("ready", false))
	l_ready_btn.visible = online and !host and in_lobby
	l_ready_btn.pressed = meready
	l_ready_btn.text = "READY!" if meready else "READY"
	l_ready_btn.disabled = client.my_have != "ok"
	l_start_btn.visible = online and host and in_lobby
	l_abort_btn.visible = online and host and !in_lobby
	l_settings_btn.visible = online and host
	if !host: l_settings_row.visible = false
	var why = ""
	if online and in_lobby:
		if host:
			var w = _start_blockers()
			l_start_btn.disabled = w != ""
			why = w if w != "" else "Everyone is ready."
		elif typeof(m) != TYPE_DICTIONARY or m.empty(): why = "Waiting for the host to pick a map."
		elif client.my_have != "ok": why = "You need this map to play."
		else: why = "Waiting for the host to start." if meready else "Press READY when you are."
	elif online:
		why = "Match running - No Fail is on for everyone." if client.in_match() or client.phase == "done" else "A match is running - you'll be in the next one."
	l_why.text = why

func _start_blockers() -> String:
	var L = client.lobby
	if typeof(L.get("map")) != TYPE_DICTIONARY or L.map.empty(): return "Pick a map first."
	var nr = []
	var nm = []
	for p in client.players:
		if p.get("conn") != "ok": continue
		if str(p.get("have")) != "ok": nm.append(str(p.name))
		elif int(p.pid) != client.pid and !p.get("ready", false): nr.append(str(p.name))
	if !nm.empty(): return "Missing / checking the map: " + PoolStringArray(nm).join(", ")
	if !nr.empty(): return "Not ready: " + PoolStringArray(nr).join(", ")
	return ""

func _name_of(pid:int) -> String:
	for p in client.players:
		if int(p.pid) == pid: return str(p.name)
	return ""

func _refresh_players():
	if screen != "lobby": return
	for c in l_players.get_children(): c.queue_free()
	var L = client.lobby
	var n = 0
	for p in client.players:
		if p.get("conn") == "ok": n += 1
	l_players_hdr.text = "PLAYERS   %d/%d" % [n, int(L.get("max", 0))]
	var running = str(L.get("state", "lobby")) != "lobby"
	var ranks = {}
	if running:
		var i = 1
		for e in client.board:
			ranks[int(e.pid)] = i
			i += 1
	for p in client.players:
		var pid = int(p.pid)
		var mine = pid == client.pid
		var row = PanelContainer.new()
		var sb = Look.box(Look.SURFACE_HI if mine else Look.BG, Look.accent() if mine else Look.LINE, 1, 0)
		sb.content_margin_left = 10; sb.content_margin_right = 8; sb.content_margin_top = 6; sb.content_margin_bottom = 6
		row.add_stylebox_override("panel", sb)
		var v = VBoxContainer.new()
		v.add_constant_override("separation", 2)
		row.add_child(v)
		var top = HBoxContainer.new()
		top.add_constant_override("separation", 6)
		v.add_child(top)
		var nl = _lbl(str(p.name) + ("  (you)" if mine else ""), 16, Look.TEXT if p.get("conn") == "ok" else Look.TEXT_3)
		nl.clip_text = true
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nl)
		if p.get("host", false): top.add_child(_lbl("HOST", 12, Look.accent()))
		var bits = []
		if p.get("conn") != "ok": bits.append("connection lost")
		elif running and p.get("in_match", false):
			var s = p.get("s", {})
			bits.append((("#%d  " % ranks[pid]) if ranks.has(pid) else "") + _comma(int(s.get("score", 0))))
			bits.append(str(p.get("status", "")))
		elif running: bits.append("waiting for the next match")
		else:
			bits.append("host" if p.get("host", false) else ("READY" if p.get("ready", false) else "not ready"))
			var hv = str(p.get("have", "?"))
			bits.append({"ok": "has the map", "?": "checking map", "missing": "NO MAP", "mismatch": "DIFFERENT MAP"}.get(hv, hv))
		var ping = int(p.get("ping", -1))
		if p.get("conn") == "ok": bits.append(("%d ms" % ping) if ping >= 0 else "-- ms")
		var sl = _lbl(PoolStringArray(bits).join("   /   "), 12, Look.TEXT_2)
		sl.clip_text = true
		v.add_child(sl)
		if client.is_host() and !mine:
			var hr = HBoxContainer.new()
			hr.add_constant_override("separation", 6)
			v.add_child(hr)
			var gh = _btn("MAKE HOST", "_give_host", [pid], 0, 28)
			gh.add_font_override("font", _font(12))
			gh.disabled = p.get("conn") != "ok"
			hr.add_child(gh)
			if pid != int(client.lobby.get("owner", -1)):
				var kb = _btn("KICK", "_kick", [pid], 0, 28)
				kb.add_font_override("font", _font(12))
				hr.add_child(kb)
		l_players.add_child(row)

static func _comma(n:int) -> String:
	var s = str(n)
	var out = ""
	var k = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		k += 1
		if k % 3 == 0 and i > 0: out = "," + out
	return out

func _refresh_chat():
	if screen != "lobby": return
	var sb = l_chat_scroll.get_v_scrollbar()
	var at_end = sb.value + sb.page >= sb.max_value - 8
	for c in l_chat.get_children(): c.queue_free()
	var bias = OS.get_time_zone_info().get("bias", 0)
	for e in client.chat:
		var t = ""
		if int(e.get("ts", 0)) > 0:
			var dt = OS.get_datetime_from_unix_time(int(e.ts) + int(bias) * 60)
			t = "%02d:%02d  " % [dt.hour, dt.minute]
		var text = ""
		var col = Look.TEXT_2
		if e.get("sys", false):
			text = t + "-- " + str(e.text)
			col = Look.TEXT_3
		else:
			text = t + str(e.name) + ":  " + str(e.text)
			if e.get("pending", false):
				text += "   (sending...)"
				col = Look.TEXT_3
			elif str(e.get("failed", "")) != "":
				text += "   (not sent: %s)" % e.failed
				col = Look.CRIT.lightened(0.2)
			elif e.get("mine", false): col = Look.TEXT
		var l = _lbl(text, 14, col)
		l.autowrap = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l_chat.add_child(l)
	if at_end: call_deferred("_chat_to_end")

func _chat_to_end():
	yield(get_tree(), "idle_frame")
	if is_instance_valid(l_chat_scroll): l_chat_scroll.scroll_vertical = int(l_chat_scroll.get_v_scrollbar().max_value)

func _chat_send_btn():
	_chat_send(l_chat_in.text)

func _chat_send(t:String):
	if t.strip_edges() == "": return
	var err = client.send_chat(t)
	if err != "": _notice("Message not sent: " + err, true)
	else: l_chat_in.text = ""

func _ready_toggle(on:bool):
	client.set_ready(on)

func _start():
	var w = _start_blockers()
	if w != "":
		_notice(w, true)
		return
	client.start_match()

func _abort():
	client.abort_match()

func _speed(d:float):
	var r = client.rules_now()
	r.speed = clamp(stepify(r.speed + d, 0.05), P.SPEED_MIN, P.SPEED_MAX)
	client.set_rules(r)

func _mod_toggle(on:bool, m:String):
	var r = client.rules_now()
	if on and !(m in r.mods): r.mods.append(m)
	elif !on: r.mods.erase(m)
	client.set_rules(r)

func _settings_toggle(on:bool):
	l_settings_row.visible = on
	if on:
		s_name.text = str(client.lobby.get("name", ""))
		s_max = int(client.lobby.get("max", 8))
		s_max_lbl.text = str(s_max)
		s_pw.text = ""

func _s_max(d:int):
	s_max = int(clamp(s_max + d, 2, P.MAX_PLAYERS))
	s_max_lbl.text = str(s_max)

func _s_apply():
	client.set_lobby_cfg({name = s_name.text, max = s_max, pw = s_pw.text})
	l_settings_btn.pressed = false
	l_settings_row.visible = false

func _give_host(pid:int):
	client.give_host(pid)

func _kick(pid:int):
	client.kick(pid)

# ---------------------------------------------------------------- results
func _set_results(on:bool):
	results_on = on
	l_results.visible = on and screen == "lobby"
	l_left.visible = !l_results.visible
	if on: _refresh_results()

func _refresh_results():
	if !results_on: return
	for c in r_list.get_children(): c.queue_free()
	var final = client.results_match == client.match_id and !client.results.empty() and client.phase != "playing"
	var list = client.results if final else client.board
	r_title.text = "MATCH RESULTS" if final else "MATCH IN PROGRESS"
	if final:
		r_sub.text = "Session results (not verified records)   /   No Fail was on for everyone"
	else:
		var waiting = []
		for e in client.board:
			if !(str(e.get("status", "")) in ["finished", "quit"]): waiting.append(str(e.name))
		r_sub.text = ("Waiting for: " + PoolStringArray(waiting).join(", ")) if !waiting.empty() else "Waiting for the host..."
	var hdr = _row(r_list, 8)
	for h in [["#", 40], ["PLAYER", 0], ["SCORE", 130], ["ACC", 80], ["COMBO", 80], ["MISS", 60], ["", 120]]:
		var l = _lbl(h[0], 12, Look.TEXT_3)
		l.rect_min_size.x = h[1]
		if h[1] == 0: l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr.add_child(l)
	var i = 0
	for e in list:
		i += 1
		var mine = int(e.get("pid", -1)) == client.pid
		var row = PanelContainer.new()
		var sb = Look.box(Look.SURFACE_HI if mine else Look.SURFACE, Look.accent() if mine else Look.LINE, 1, 0)
		sb.content_margin_left = 8; sb.content_margin_right = 8; sb.content_margin_top = 6; sb.content_margin_bottom = 6
		row.add_stylebox_override("panel", sb)
		var h = HBoxContainer.new()
		h.add_constant_override("separation", 8)
		row.add_child(h)
		var rank = int(e.get("rank", i))
		var cells = [["#%d" % rank, 40, 20 if rank == 1 else 16], [str(e.get("name", "?")) + ("  (you)" if mine else ""), 0, 16],
			[_comma(int(e.get("score", 0))), 130, 16], ["%.2f%%" % float(e.get("acc", 0)), 80, 15],
			["%dx" % int(e.get("mc", 0)), 80, 15], [str(int(e.get("misses", 0))), 60, 15], [str(e.get("status", "")), 120, 13]]
		for c in cells:
			var l = _lbl(c[0], c[2], Look.TEXT if mine or rank == 1 else Look.TEXT_2)
			l.rect_min_size.x = c[1]
			l.clip_text = true
			if c[1] == 0: l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(l)
		r_list.add_child(row)
	r_again.text = "PLAY AGAIN" if client.is_host() else "READY AGAIN"

func _r_again():
	if !client.is_host() and client.my_have == "ok": client.set_ready(true)
	_set_results(false)

func _r_leave():
	client.leave()
	_set_results(false)
	_show("home")

# ---------------------------------------------------------------- picking a map (host)
func _build_pick_bar():
	pick_bar = PanelContainer.new()
	var sb = Look.box(Look.SURFACE_HI, Look.accent(), 1, 0)
	sb.content_margin_left = 16; sb.content_margin_right = 10; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	pick_bar.add_stylebox_override("panel", sb)
	pick_bar.anchor_left = 0.5; pick_bar.anchor_right = 0.5
	pick_bar.margin_left = -380; pick_bar.margin_right = 380; pick_bar.margin_top = 8; pick_bar.margin_bottom = 64
	if ResourceLoader.exists("res://uitheme.tres"): pick_bar.theme = load("res://uitheme.tres")
	add_child(pick_bar)
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 12)
	pick_bar.add_child(h)
	var l = _lbl("PICKING A MAP FOR THE LOBBY - open a map, then press PICK FOR LOBBY", 15, Look.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap = true
	h.add_child(l)
	h.add_child(_btn("CANCEL", "_pick_end", [], 110, 40))
	pick_bar.visible = false

func _pick_begin():
	if !client.is_host(): return
	picking = true
	Engine.set_meta("rr_mp_picking", true)
	root.visible = false
	pick_bar.visible = true
	_cover(false)
	_pick_mode_page(true)

func _pick_end():
	picking = false
	Engine.remove_meta("rr_mp_picking")
	_pick_mode_page(false)
	root.visible = true
	pick_bar.visible = false
	_cover(true)

# the map page shows PICK FOR LOBBY instead of Start while picking (SongInfoScreen.rr_mp_pick_mode)
func _pick_mode_page(on:bool):
	if !menu or !is_instance_valid(menu): return
	var si = load("res://mods/replay/Classic.gd").pick_target(menu)
	if si: si.rr_mp_pick_mode(on)

func pick_done(song):
	if !picking: return
	_pick_end()
	if !song: return
	var err = client.pick_map(song)
	if err != "": _notice(err, true)

# ---------------------------------------------------------------- updates
func _changed(what:String):
	match what:
		"status":
			_refresh_status()
			if client.status == "online" and screen in ["join", "create"]: _show("lobby")
			elif client.status == "idle" and screen == "lobby":
				if picking: _pick_end()
				_set_results(false)
				_show("home")
			elif screen == "join" and client.status == "idle":
				j_btn.disabled = false
				j_status.add_color_override("font_color", Look.CRIT)
				j_status.text = client.status_text
			elif screen == "lobby": _refresh_lobby()
		"lobby":
			_refresh_lobby()
			_refresh_players()
		"players":
			_refresh_players()
			_refresh_lobby()
		"chat": _refresh_chat()
		"board":
			_refresh_players()
			_refresh_results()
		"results":
			if screen == "lobby": _set_results(true)
			_refresh_lobby()
			_refresh_players()
		"match": _refresh_lobby()
		"lan": _refresh_lan()

func _notice(text:String, bad:bool):
	if text == "": return
	toast.text = text
	toast.add_color_override("font_color", Look.CRIT.lightened(0.25) if bad else Look.TEXT)
	toast.modulate.a = 1.0
	_toast_t = 3.5

var _status_t:float = 0.0
func _process(delta):
	if _toast_t > 0:
		_toast_t -= delta
		if _toast_t < 0.5: toast.modulate.a = max(_toast_t / 0.5, 0.0)
	_status_t += delta
	if _status_t > 1.0:
		_status_t = 0.0
		_refresh_status()
	if _leave_armed > 0 and OS.get_ticks_msec() - _leave_armed > 2500 and screen == "lobby":
		_leave_armed = 0
		back_btn.text = "LEAVE LOBBY"

func _input(ev):
	if !(ev is InputEventKey) or !ev.pressed or ev.echo or ev.scancode != KEY_ESCAPE: return
	get_tree().set_input_as_handled()
	if picking:
		_pick_end()
		return
	var fo = root.get_focus_owner()
	if fo is LineEdit:
		fo.release_focus()
		return
	if screen == "lobby":
		if results_on: _set_results(false)
		return
	_back()
