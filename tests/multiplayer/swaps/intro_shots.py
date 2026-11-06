# Test-only: the startup intro saves the screen at points of its timeline (intro_<s>.png in the run folder)
SWAPS = [('res://mods/intro/Intro.gd', '\tclock += delta\n', '\tclock += delta\n\tfor k in [0.5, 0.8, 1.1, 1.5, 1.85, 2.2]:\n\t\tif clock >= k and !_shots.has(k):\n\t\t\t_shots[k] = true\n\t\t\tget_viewport().get_texture().get_data().save_png("E:/Rhythia/Rhythia Legacy/_modding/tests/multiplayer/t/I/intro_%s.png" % str(k))\n'),
	('res://mods/intro/Intro.gd', '', '\nvar _shots = {}\n')]
