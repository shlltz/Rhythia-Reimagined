# Test-only: the startup intro's frame times only (intro_frames.txt in t/I), no screenshots
# (intro_frames.txt: slowest frames while it animates) in the run folder t/I
D = 'E:/Rhythia/Rhythia Legacy/_modding/tests/multiplayer/t/I/'
SWAPS = [('res://mods/intro/Intro.gd', '\tclock += min(delta, 1.0 / 30.0) # (a late frame slows it a little instead of jumping ahead)\n',
	'\tclock += min(delta, 1.0 / 30.0) # (a late frame slows it a little instead of jumping ahead)\n\t_fr.append(delta * 1000.0)\n\tfor k in []:\n\t\tif clock >= k and !_shots.has(k):\n\t\t\t_shots[k] = true\n\t\t\tvar im = get_viewport().get_texture().get_data()\n\t\t\tim.flip_y()\n\t\t\tim.save_png("' + D + 'intro_%s.png" % str(k))\n'),
	('res://mods/intro/Intro.gd', '\tqueue_free()\n\n# never leave', '\tvar ff = File.new()\n\tff.open("' + D + 'intro_frames.txt", File.WRITE)\n\tvar s = _fr.duplicate()\n\ts.sort()\n\tff.store_line("frames %d, waited %.1f s, slowest %s" % [_fr.size(), wait_t, str(s.slice(max(0, s.size() - 6), s.size() - 1))])\n\tff.close()\n\tqueue_free()\n\n# never leave'),
	('res://mods/intro/Intro.gd', '', '\nvar _shots = {}\nvar _fr = []\n')]
