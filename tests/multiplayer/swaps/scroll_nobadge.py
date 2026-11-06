# Test-only (ScrollProbe ablation): no star badge / focus frame on the map list cards
SWAPS = [('res://mods/stars/v3MapList.gd', '\tbtn.add_child(badge)\n\tbadge.set_song(map, _badge_font(btn))\n', '\tbadge.free()\n'),
	('res://mods/stars/v3MapList.gd', '\tif Look.mono(): # personal build: white focus frame on the selected card\n', '\tif false:\n')]
