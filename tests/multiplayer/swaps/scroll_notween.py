# Test-only (ScrollProbe ablation): map list cards get their final size at once (no height tweens, no width easing)
SWAPS = [('res://mods/stars/v3MapList.gd', '\ttween_length(delta)\n', '\tpass\n'),
	('res://mods/stars/v3MapList.gd', '\ttween.tween_property(p, "rect_min_size", Vector2(size_x - (page_size/2) * 10, 0), 0.2)\n', '\ttween.tween_property(p, "rect_min_size", Vector2(size_x - (page_size/2) * 10, 0), 0.0)\n'),
	('res://mods/stars/v3MapList.gd', '\ttween.tween_property(p, "rect_min_size", Vector2(size_x - (next_index() - prev_index())/2 * 10, 90), 0.2)\n', '\tp.rect_min_size = Vector2(size_x - (next_index() - prev_index())/2 * 10, 90)\n\ttween.kill()\n')]
