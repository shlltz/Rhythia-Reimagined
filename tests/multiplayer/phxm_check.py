# Checks .phxm files written by the game (PhxmTest.gd exports x_*.phxm) with Python's own zip
# reader (CRCs, sizes) and decodes them the way the Rhythia rewrite does (MapParser.cs
# PHXMFolder / DecodePHXMO): metadata keys and types, note count, positions in range.
# usage: py -3 phxm_check.py dir_or_files...
import glob, json, os, struct, sys, zipfile

KEYS = {'ID': str, 'Artist': str, 'ArtistLink': str, 'ArtistPlatform': str, 'Title': str, 'Rating': (int, float),
        'Mappers': list, 'Difficulty': int, 'DifficultyName': str, 'Length': int, 'HasAudio': bool, 'HasCover': bool,
        'HasVideo': bool, 'AudioExt': str}

def check(path):
    z = zipfile.ZipFile(path)
    bad = z.testzip()
    assert bad is None, 'CRC / size error in ' + bad
    names = set(z.namelist())
    md = json.loads(z.read('metadata.json'))
    for k, t in KEYS.items():
        assert k in md, 'missing ' + k
        assert isinstance(md[k], t), '%s is %s' % (k, type(md[k]).__name__)
    assert set(md) == set(KEYS), 'extra keys %s' % (set(md) - set(KEYS))
    assert 0 <= md['Difficulty'] <= 5
    assert ('audio.' + md['AudioExt']) in names, 'no audio.' + md['AudioExt']
    assert md['HasCover'] == ('cover.png' in names)
    b = z.read('objects.phxmo')
    _, n = struct.unpack_from('<II', b, 0)
    p, last = 8, -1
    for _ in range(n):
        ms, q = struct.unpack_from('<IB', b, p); p += 5
        if q: x, y = struct.unpack_from('<ff', b, p); p += 8
        else: x, y = b[p] - 1, b[p + 1] - 1; p += 2
        assert ms >= last, 'notes out of order'
        last = ms
        assert -10 < x < 10 and -10 < y < 10, 'position out of range'
    sections = len(b) - p
    return '%s: ok, %d notes, %d bytes of effect sections, %s' % (os.path.basename(path), n, sections, sorted(names))

files = []
for a in sys.argv[1:]:
    files += sorted(glob.glob(os.path.join(a, 'x_*.phxm'))) if os.path.isdir(a) else [a]
fails = 0
for f in files:
    try: print(check(f))
    except Exception as e:
        fails += 1
        print('%s: FAIL %s' % (os.path.basename(f), e))
print('== %d files, %d failed' % (len(files), fails))
sys.exit(1 if fails or not files else 0)
