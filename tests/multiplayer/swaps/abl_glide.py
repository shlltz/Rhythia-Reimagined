# Test-only ablation: no map list glide step per frame
SWAPS = [('res://mods/stars/v3MapList.gd', '\tif !sliding: _rr_glide(delta)\n', '\tpass\n')]
