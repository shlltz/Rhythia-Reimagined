extends Reference
# HUD font (Customize > Interface, or drop a .ttf / .otf on the game): the typeface of the run's HUD
# (side panels, timer, combo). Labels keep their sizes and outlines; only the face changes, with
# the HUD's own font behind it for any character the new one lacks. Wins over a skin's HUD font.
# Reimagined hud_font: "" = the HUD's own | bold | mono | pixel | own (user://rr_hud_font.ttf/.otf)

const R = preload("res://mods/replay/Reimagined.gd")
const OWN = "user://rr_hud_font"
const FONTS = {"bold": "res://assets/font/Lato/Lato-Black.ttf", "mono": "res://assets/font/UbuntuMono/Bold.ttf",
	"pixel": "res://assets/font/main.ttf"}
const CHOICES = [["", "THEME"], ["bold", "BOLD"], ["mono", "MONO"], ["pixel", "PIXEL"], ["own", "YOUR FONT"]]

static func own_path() -> String:
	var f = File.new()
	for ext in ["ttf", "otf"]:
		if f.file_exists(Globals.p(OWN + "." + ext)): return Globals.p(OWN + "." + ext)
	return ""

static func data(which:String):
	if which == "own":
		var p = own_path()
		if p == "": return null
		var d = DynamicFontData.new()
		d.font_path = p
		return d
	if FONTS.has(which) and ResourceLoader.exists(FONTS[which]): return load(FONTS[which])
	return null

# keeps a copy of a .ttf / .otf as the player's own HUD font; "" or what went wrong
static func set_own(src:String) -> String:
	var ext = src.get_extension().to_lower()
	if !(ext in ["ttf", "otf"]): return "only .ttf and .otf fonts work"
	var f = File.new()
	if f.open(src, File.READ) != OK: return "couldn't read that file"
	var magic = f.get_buffer(4)
	f.close()
	# (TrueType 00 01 00 00 / "true", OpenType "OTTO")
	if !(magic.hex_encode() in ["00010000", "74727565", "4f54544f"]): return "that file isn't a TrueType / OpenType font"
	var dir = Directory.new()
	for e in ["ttf", "otf"]:
		if dir.file_exists(Globals.p(OWN + "." + e)): dir.remove(Globals.p(OWN + "." + e))
	if dir.copy(src, Globals.p(OWN + "." + ext)) != OK: return "couldn't copy the font into the user folder"
	R.set_val("hud_font", "own")
	return ""

# a font like `like` (size, outline) in the chosen face, the old face as fallback
static func font_like(like:Font, d) -> Font:
	if !(like is DynamicFont): return like
	var nf = like.duplicate()
	nf.font_data = d
	if like.font_data: nf.add_fallback(like.font_data) # (after the copied fallbacks: missing glyphs)
	return nf

# every label under root (the HUD node) gets the chosen face
static func apply(root:Node, which = null):
	if which == null: which = str(R.val("hud_font"))
	if which == "": return
	var d = data(which)
	if !d: return
	var made = {}
	var stack = [root]
	while !stack.empty():
		var n = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if !(n is Label): continue
		var old = n.get_font("font")
		if !(old is DynamicFont): continue
		if !made.has(old): made[old] = font_like(old, d)
		n.add_font_override("font", made[old])
