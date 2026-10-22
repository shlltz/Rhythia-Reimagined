# Multi-instance test launcher: builds the game pck (own or share profile) once per instance with
#  - its own user data folder: the process runs with APPDATA = t/<inst>/appdata, so user:// is
#    t/<inst>/appdata/SoundSpacePlus and a test never reads or writes the real %APPDATA% data,
#  - its own log file t/<inst>/godot.log,
#  - a driver script (res://mods/bench/Driver.gd) added to the root by menu2.gd,
# then starts all instances at once and waits until they exit (driver kills itself) or time out.
# usage: mpbench.py own|share "A=DriverA.gd,B=DriverB.gd" [limit_s] [maps_for_A,...]
# env: RR_KEEP=1 keeps each instance's user data (warm start), RR_NONET=1 turns the game's networking off,
#      RR_THREADMODEL=0|1|2 overrides rendering/threads/thread_model (the game ships 2, multi-threaded),
#      RR_INITPROBE=1 logs init stage texts + long frames (release builds only flush the log on errors)
import sys, os, subprocess, time, shutil, struct, io, contextlib
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')))
import ssp_mod as m
S = os.path.dirname(os.path.abspath(__file__)); T = os.path.join(S, 't'); SP = S.replace(chr(92), '/')
kind = sys.argv[1]
insts = [x.split('=') for x in sys.argv[2].split(',')]
limit = float(sys.argv[3]) if len(sys.argv) > 3 else 240
# maps copied into an instance's library: "A=path|path;B=path" (a bare path list = first instance)
extra_maps = {}
if len(sys.argv) > 4:
    for part in sys.argv[4].split(';'):
        if not part: continue
        if '=' in part and not os.path.exists(part): k, v = part.split('=', 1)
        else: k, v = insts[0][0], part
        extra_maps.setdefault(k, []).extend([x for x in v.split('|') if x])
prof = m.load_profile()
if kind != 'own':
    prof = {k: v for k, v in prof.items() if k not in m.TWEAKS_EXCLUDE}; prof['sharelook'] = {}
with contextlib.redirect_stdout(io.StringIO()): pk = m.build(prof)
p = 'res://mods/replay/menu2.gd'; d = pk.new[p].decode('utf-8')
drv = '\nfunc _bench():\n\tif get_tree().root.has_node("RRTestDriver"): return\n\tvar b = Node.new()\n\tb.name = "RRTestDriver"\n\tb.set_script(load("res://mods/bench/Driver.gd"))\n\tget_tree().root.call_deferred("add_child", b)\n'
assert '\tcall_deferred("_add_osu_screens")\n' in d
d = d.replace('\tcall_deferred("_add_osu_screens")\n', '\tcall_deferred("_add_osu_screens")\n\tcall_deferred("_bench")\n', 1) + drv
pk.new[p] = d.encode('utf-8')
if os.environ.get('RR_INITPROBE'): # startup diagnosis: the intro (alive during init) reports stage texts + long frames as errors (release logs only flush on errors)
    ip = 'res://mods/intro/Intro.gd'; di = pk.new[ip].decode('utf-8')
    assert 'func _process(delta):\n' in di
    di = di.replace('func _process(delta):\n', 'func _process(delta):\n\t_rr_probe()\n', 1) + '''
var _rr_last_us = 0
var _rr_texts = {}
func _rr_probe():
	var u = OS.get_ticks_usec()
	var sc = get_tree().current_scene
	var tag = sc.name if sc else "-"
	if _rr_last_us > 0 and u - _rr_last_us > 500000: push_error("RRPROBE %d ms: frame took %d ms (scene %s)" % [OS.get_ticks_msec(), (u - _rr_last_us) / 1000, tag])
	_rr_last_us = u
	if sc:
		var stack = [sc]
		while !stack.empty():
			var n = stack.pop_back()
			if n is Label and n.is_visible_in_tree() and _rr_texts.get(n.get_path()) != n.text:
				_rr_texts[n.get_path()] = n.text
				push_error("RRPROBE %d ms: %s = %s" % [OS.get_ticks_msec(), n.name, n.text.substr(0, 60)])
			for c in n.get_children(): stack.append(c)
'''
    pk.new[ip] = di.encode('utf-8')
appdata = os.environ['APPDATA']

def set_setting(b, key, payload):
    key = key.encode(); kb = struct.pack('<I', len(key)) + key
    i = b.find(kb)
    if i >= 0:
        j = i + len(kb); vl, = struct.unpack_from('<I', b, j)
        return b[:j] + struct.pack('<I', len(payload)) + payload + b[j + 4 + vl:]
    n, = struct.unpack_from('<I', b, 4)
    return b[:4] + struct.pack('<I', n + 1) + b[8:] + kb + struct.pack('<I', len(payload)) + payload
def s_payload(s):
    e = s.encode(); e2 = e + bytes(-len(e) % 4)
    return struct.pack('<II', 4, len(e)) + e2

base_pb = pk.read('res://project.binary')
procs = []
for name, script in insts:
    root = os.path.join(T, name)
    ud = os.path.join(root, 'appdata', 'SoundSpacePlus')   # the instance runs with APPDATA = t/<inst>/appdata
    if os.environ.get('RR_KEEP') and os.path.isdir(ud): # warm start: keep the instance's user data from the last run
        for fn in os.listdir(root):
            if fn != 'appdata': (shutil.rmtree if os.path.isdir(os.path.join(root, fn)) else os.remove)(os.path.join(root, fn))
    else:
        if os.path.isdir(root): shutil.rmtree(root)
        os.makedirs(os.path.join(ud, 'maps'))
        # answer the stock first-launch "record replays?" prompt (its defaults), so init doesn't wait on it
        open(os.path.join(ud, 'settings.json'), 'w').write('{"record_replays": false, "record_limit": 0}')
        if not os.environ.get('RR_ASK_NAME'): # (the first-start username panel would sit over every test)
            open(os.path.join(ud, 'reimagined.json'), 'w').write('{"player_name": "Tester"}')
    for mp in extra_maps.get(name, []):
        dst = os.path.join(ud, 'maps', os.path.basename(mp))
        if not os.path.exists(dst): shutil.copyfile(mp, dst)
    b = set_setting(base_pb, 'logging/file_logging/log_path', s_payload(root.replace(chr(92), '/') + '/godot.log'))
    if os.environ.get('RR_NONET'): b = set_setting(b, 'application/networking/enabled', struct.pack('<II', 1, 0)) # (bool false)
    if os.environ.get('RR_THREADMODEL'): b = set_setting(b, 'rendering/threads/thread_model', struct.pack('<II', 2, int(os.environ['RR_THREADMODEL']))) # (int: 0 single-unsafe, 1 single-safe, 2 multi-threaded)
    pk.new['res://project.binary'] = b
    src = open(os.path.join(S, script), encoding='utf-8').read()
    src = src.replace('@@S@@', SP).replace('@@OUT@@', root.replace(chr(92), '/')).replace('@@NAME@@', name).replace('@@RWSKIN@@', os.environ.get('RR_RWSKIN', '').replace(chr(92), '/'))
    first = extra_maps.get(insts[0][0], []) # @@MAP1@@ = the first map (in every library), @@MAP2@@ = the second (first instance only)
    src = src.replace('@@MAP1@@', os.path.basename(first[0]) if first else '').replace('@@MAP2@@', os.path.basename(first[1]) if len(first) > 1 else '')
    pk.add('res://mods/bench/Driver.gd', src.encode('utf-8'))
    for f in os.listdir(S): # shared helper scripts for drivers
        if f.startswith('Lib') and f.endswith('.gd'):
            pk.add('res://mods/bench/' + f, open(os.path.join(S, f), encoding='utf-8').read().encode('utf-8'))
    out = os.path.join(root, 'SoundSpacePlus.pck'); pk.fn = out; pk.save(bak=False)
    pk.f = open(m.PCK, 'rb') # (save closes the source pck; the next instance reads it again)
real_sj = os.path.join(appdata, 'SoundSpacePlus', 'settings.json')
before = os.path.getmtime(real_sj) if os.path.exists(real_sj) else None
for i, (name, script) in enumerate(insts):
    root = os.path.join(T, name)
    log = open(os.path.join(root, 'stdout.txt'), 'w')
    args = [os.path.join(m.GAME, 'SoundSpacePlus.exe'), '--main-pack', os.path.join(root, 'SoundSpacePlus.pck'),
            '--windowed', '--resolution', '1280x720', '--position', '%d,%d' % (20 + i * 660, 40 + i * 30)]
    env = dict(os.environ); env['APPDATA'] = os.path.join(root, 'appdata')
    procs.append(subprocess.Popen(args, cwd=m.GAME, stdout=log, stderr=subprocess.STDOUT, env=env))
    time.sleep(float(os.environ.get('RR_STAGGER', '1.0')))
t0 = time.time()
while time.time() - t0 < limit and any(pr.poll() is None for pr in procs): time.sleep(1)
for pr in procs:
    if pr.poll() is None: pr.kill()
for name, script in insts:
    root = os.path.join(T, name)
    txt = ''
    for fn in ('stdout.txt', 'godot.log'): # (the game logs to godot.log; stdout is usually empty)
        if os.path.exists(os.path.join(root, fn)): txt += open(os.path.join(root, fn), encoding='utf-8', errors='replace').read()
    errs = [l for l in txt.splitlines() if 'SCRIPT ERROR' in l or ('ERROR:' in l and 'localization' not in l and 'library' not in l and 'id == 0' not in l and 'File must be opened' not in l and 'arvr' not in l)]
    print('%s: %d error lines (%.0f s)' % (name, len(errs), time.time() - t0))
    rc = procs[[i for i, x in enumerate(insts) if x[0] == name][0]].returncode
    if rc not in (0, None, 1) and rc & 0xffffffff >= 0xc0000000: print('  CRASHED: exit code 0x%08x' % (rc & 0xffffffff))
    for l in errs[:15]: print('  ' + l)
after = os.path.getmtime(real_sj) if os.path.exists(real_sj) else None
print('real settings.json touched:', before != after)
