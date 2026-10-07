extends Control
# Monochrome line icons for the Content Manager.
# kind: file, vulnus, pack, zip, folder (rows) / ok, error, wait (result screen).

var kind:String = "file"
var color:Color = Color("#ececf0")
var spin:float = 0.0

func _ready():
	set_process(kind == "wait")

func _process(delta):
	spin = fmod(spin + delta * 5.0, TAU)
	update()

func _draw():
	var s = min(rect_size.x, rect_size.y)
	var o = (rect_size - Vector2(s, s)) / 2
	var c = o + Vector2(s, s) / 2
	var w = 2.0
	match kind:
		"file": # page with a folded corner and text lines
			var l = o.x + s * 0.2; var r = o.x + s * 0.8; var t = o.y + s * 0.08; var b = o.y + s * 0.92
			var f = s * 0.2
			draw_polyline(PoolVector2Array([Vector2(r - f, t), Vector2(l, t), Vector2(l, b), Vector2(r, b), Vector2(r, t + f), Vector2(r - f, t), Vector2(r - f, t + f), Vector2(r, t + f)]), color, w)
			for i in 3:
				var y = t + s * (0.42 + i * 0.13)
				draw_line(Vector2(l + s * 0.12, y), Vector2(r - s * (0.12 if i < 2 else 0.25), y), color, w)
		"vulnus": # V monogram in a square
			var p = o + Vector2(s * 0.1, s * 0.1); var q = s * 0.8
			draw_rect(Rect2(p, Vector2(q, q)), color, false, w)
			draw_polyline(PoolVector2Array([p + Vector2(q * 0.25, q * 0.27), p + Vector2(q * 0.5, q * 0.75), p + Vector2(q * 0.75, q * 0.27)]), color, w * 1.5)
		"pack": # stacked cards
			for i in 3:
				var d = (2 - i) * s * 0.1
				draw_rect(Rect2(o + Vector2(s * 0.12 + d, s * 0.3 - d), Vector2(s * 0.6, s * 0.55)), Color("#16161a") if i == 2 else Color(0,0,0,0), true)
				draw_rect(Rect2(o + Vector2(s * 0.12 + d, s * 0.3 - d), Vector2(s * 0.6, s * 0.55)), color, false, w)
		"zip": # archive box with a zipper down the middle
			var p = o + Vector2(s * 0.15, s * 0.1); var q = Vector2(s * 0.7, s * 0.8)
			draw_rect(Rect2(p, q), color, false, w)
			var x = c.x
			for i in 4:
				var y = p.y + s * (0.08 + i * 0.12)
				draw_line(Vector2(x - s * 0.08, y), Vector2(x, y), color, w)
				draw_line(Vector2(x, y + s * 0.06), Vector2(x + s * 0.08, y + s * 0.06), color, w)
			draw_rect(Rect2(Vector2(x - s * 0.08, p.y + s * 0.56), Vector2(s * 0.16, s * 0.14)), color, false, w)
		"folder": # folder with a tab
			var l = o.x + s * 0.08; var r = o.x + s * 0.92; var t = o.y + s * 0.2; var b = o.y + s * 0.82
			draw_polyline(PoolVector2Array([Vector2(l, b), Vector2(l, t), Vector2(l + s * 0.3, t), Vector2(l + s * 0.38, t + s * 0.1), Vector2(r, t + s * 0.1), Vector2(r, b), Vector2(l, b)]), color, w)
			draw_line(Vector2(l, t + s * 0.24), Vector2(r, t + s * 0.24), color, w)
		"ok": # check in a circle
			draw_arc(c, s * 0.46, 0, TAU, 48, color, w, true)
			draw_polyline(PoolVector2Array([c + Vector2(-s * 0.2, 0), c + Vector2(-s * 0.05, s * 0.15), c + Vector2(s * 0.22, -s * 0.14)]), color, w * 1.5, true)
		"error": # cross in a circle
			draw_arc(c, s * 0.46, 0, TAU, 48, color, w, true)
			var d = s * 0.16
			draw_line(c + Vector2(-d, -d), c + Vector2(d, d), color, w * 1.5, true)
			draw_line(c + Vector2(d, -d), c + Vector2(-d, d), color, w * 1.5, true)
		"wait": # faint ring + spinning arc
			draw_arc(c, s * 0.46, 0, TAU, 48, Color(color.r, color.g, color.b, 0.15), w, true)
			draw_arc(c, s * 0.46, spin, spin + PI * 0.6, 24, color, w, true)
