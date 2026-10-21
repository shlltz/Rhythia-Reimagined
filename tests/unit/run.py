"""Unit tests in Godot 3.6.2 without the game: copies the pure scripts into tests/unit/mods/replay/
(with the build stamps ssp_mod.py would put in) and runs UnitRunner.gd. Exit code 0 = all passed.

usage: py -3 tests/unit/run.py [path to a Godot 3.6.2 binary]      (default: $GODOT, else "godot")
       A copy of the game's own SoundSpacePlus.exe works too, as long as no .pck sits next to it.
"""
import os, re, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, '..', '..', 'src', 'replay'))
FILES = ['EditorModel.gd', 'EditorPatterns.gd', 'EditorAuto.gd', 'GifWriter.gd', 'Updater.gd', 'update_key.pub']
STAMPS = {b'@@VERSION@@': b'0.0.0', b'@@CHANNEL@@': b'own', b'@@BUILD_ID@@': b'unit'}

def main():
    dst = os.path.join(HERE, 'mods', 'replay')
    os.makedirs(dst, exist_ok=True)
    for f in FILES:
        data = open(os.path.join(SRC, f), 'rb').read()
        for k, v in STAMPS.items(): data = data.replace(k, v)
        open(os.path.join(dst, f), 'wb').write(data)
    godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('GODOT', 'godot')
    r = subprocess.run([godot, '--no-window', '--path', HERE, '-s', 'UnitRunner.gd'], capture_output=True, text=True, timeout=600)
    out = r.stdout + r.stderr
    print(out[-20000:])
    m = re.search(r'== totals: (\d+) passed, (\d+) failed', out)
    if not m: sys.exit('no totals line: the runner did not finish (exit %d)' % r.returncode)
    sys.exit(0 if int(m.group(2)) == 0 and int(m.group(1)) > 0 else 1)

if __name__ == '__main__': main()
