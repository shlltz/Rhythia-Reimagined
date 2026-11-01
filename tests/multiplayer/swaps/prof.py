# Test-only timing patches (mpbench RR_SWAPS): every gameplay script's _process is wrapped with a
# timer, and NoteManager's per-frame sections are timed one by one. Totals go to Engine meta
# "rr_prof" {key: [usec, calls]} (only while a driver has created it; ProfProbe.gd reads it).
ACC = '''
func _rr_acc(k, t0):
	if !Engine.has_meta("rr_prof"): return
	var d = Engine.get_meta("rr_prof")
	var dt = OS.get_ticks_usec() - t0
	if d.has(k):
		d[k][0] += dt
		d[k][1] += 1
	else: d[k] = [dt, 1]
'''
def wrap(path, line, key, arg='delta'):
    real = line.replace('func _process(', 'func _rr_real_process(')
    return [(path, line + '\n', real + '\n'),
            (path, '', ACC + '\nfunc _process(%s):\n\tvar _rr_t = OS.get_ticks_usec()\n\t_rr_real_process(%s)\n\t_rr_acc("%s", _rr_t)\n' % (arg, arg, key))]
def timed(path, text, key, indent):
    # times the given (unique) block of lines
    return [(path, text, '%svar _rr_%s = OS.get_ticks_usec()\n%s%s_rr_acc("%s", _rr_%s)\n' % (indent, key.replace('.', '_'), text, indent, key, key.replace('.', '_')))]

R = 'res://mods/replay/'
NM = R + 'NoteManager.gd'
SWAPS = []
SWAPS += timed(NM, '\tif Rhythia.vr: do_vr_cursor()\n\telif Rhythia.get("cam_unlock"): do_spin()\n\telse: do_half_lock()\n', 'nm.camlock', '\t')
SWAPS += timed(NM, '\t\temit_signal("timer_update",ms,can_skip)\n', 'nm.timer_update', '\t\t')
SWAPS += timed(NM, '\t\t\tms += delta * 1000 * speed_multi\n\t\t\temit_signal("ms_change",ms)\n', 'nm.ms_change', '\t\t\t')
SWAPS += timed(NM, '\t\tvar rn_res:bool = reposition_notes()\n', 'nm.reposition', '\t\t')
SWAPS += timed(NM, '\t\t\t\tvar score:int = get_parent().hit(notes[i][3])\n', 'nm.game_hit', '\t\t\t\t')
SWAPS += timed(NM, '\t\t\t\temit_signal("hit",notes[i][3])\n', 'nm.hit_signal', '\t\t\t\t')
SWAPS += timed(NM, '\t\t\t\t\tSFXManager.play_hitsfx(notes[i][5])\n', 'nm.hitsound', '\t\t\t\t\t')
SWAPS += timed(NM, '\t\tif Rhythia.replaying:\n\t\t\treplay_sig = Rhythia.replay.get_signals(rms)\n\t\t\t_replay_music_watch()\n', 'nm.replay_sig', '\t\t')
SWAPS += wrap(NM, 'func _process(delta:float):', 'NoteManager')
SWAPS += wrap(R + 'HUD.gd', 'func _process(delta:float):', 'HUD')
SWAPS += wrap(R + 'RewriteHud.gd', 'func _process(delta:float):', 'RewriteHud')
SWAPS += wrap(R + 'Game.gd', 'func _process(delta):', 'Game')
SWAPS += wrap(R + 'CursorTrail.gd', 'func _process(delta):', 'CursorTrail')
SWAPS += wrap(R + 'QuickRetry.gd', 'func _process(delta):', 'QuickRetry')
SWAPS += wrap(R + 'CrashWatch.gd', 'func _process(delta):', 'CrashWatch')
SWAPS += wrap(R + 'VolumeOverlay.gd', 'func _process(delta):', 'VolumeOverlay')
SWAPS += wrap(R + 'Checkpoint.gd', 'func _process(_d):', 'Checkpoint', '_d')
SWAPS += wrap(R + 'GyroCursor.gd', 'func _process(dt):', 'GyroCursor', 'dt')
SWAPS += wrap(R + 'OsuTrail.gd', 'func _process(delta):', 'OsuTrail')
SWAPS += wrap('res://mods/hype/PassFx.gd', 'func _process(delta):', 'PassFx')
SWAPS += wrap('res://mods/discord/discord.gd', 'func _process(delta:float) -> void:', 'discord')
G = R + 'Game.gd'
SWAPS += timed(G, '\temit_signal("hit",col)\n\thits += 1\n', 'game.hit_signal', '\t')
SWAPS += timed(G, '\tupdate_hud()\n\t\n', 'game.update_hud', '\t')
