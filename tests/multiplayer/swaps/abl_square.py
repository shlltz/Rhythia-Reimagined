# Test-only ablation: title ring instead of the square frame
SWAPS = [('res://mods/replay/TitleMenu.gd', '\tif mono:\n\t\t_draw_square(vis)\n', '\tif false:\n\t\t_draw_square(vis)\n')]
