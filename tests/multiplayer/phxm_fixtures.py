# .phxm test files for PhxmTest.gd, made from a .sspm (v2) the way the Rhythia rewrite writes them
# (Rhythia/Client scripts/map/MapParser.cs ExportEncode + Map.EncodeMeta).
# usage: py -3 phxm_fixtures.py map.sspm outdir
import json, os, struct, sys, zipfile, zlib

def sspm2(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'SS+m' and struct.unpack_from('<H', b, 4)[0] == 2, 'needs an .sspm v2'
    diff = b[0x2a]
    has_audio, has_cover = b[0x2d], b[0x2e]
    (cd_off, cd_len, a_off, a_len, c_off, c_len, md_off, md_len, m_off, m_len) = struct.unpack_from('<10Q', b, 0x30)
    p = 0x80
    def s16():
        nonlocal p
        n, = struct.unpack_from('<H', b, p); p += 2
        v = b[p:p + n].decode('utf-8'); p += n
        return v
    mid, name, _song = s16(), s16(), s16()
    n_m, = struct.unpack_from('<H', b, p); p += 2
    mappers = [s16() for _ in range(n_m)]
    # marker definitions: only ssp_note (one position value) is expected
    p = md_off
    assert b[p] == 1, 'only ssp_note markers supported'
    p += 1; s16(); assert b[p] == 1 and b[p + 1] == 7
    notes = []
    p = m_off
    while p < m_off + m_len:
        ms, typ = struct.unpack_from('<IB', b, p); p += 5
        q = b[p]; p += 1
        if q: x, y = struct.unpack_from('<ff', b, p); p += 8
        else: x, y = b[p], b[p + 1]; p += 2
        notes.append((ms, x, y))
    audio = b[a_off:a_off + a_len] if has_audio else None
    cover = b[c_off:c_off + c_len] if has_cover else None
    artist, title = (name.split(' - ', 1) + [''])[:2] if ' - ' in name else ('', name)
    return dict(id=mid, artist=artist.strip(), title=(title or name).strip(), mappers=mappers, diff=diff, notes=notes, audio=audio, cover=cover)

def phxmo(notes, tail=None):  # notes as rewrite coordinates (ms, X, Y); tail = the effect sections
    o = struct.pack('<II', 12, len(notes))
    for ms, x, y in notes:
        quantum = int(x) != x or int(y) != y or x < -1 or x > 1 or y < -1 or y > 1
        o += struct.pack('<IB', ms, int(quantum))
        o += struct.pack('<ff', x, y) if quantum else struct.pack('<BB', int(x + 1), int(y + 1))
    return o + (tail if tail is not None else struct.pack('<11i', *[0] * 11))

# effect sections in the order of the rewrite's writer comments, object layouts from the Quantum
# Editor's reader: 1 brightness (ms, duration, style, direction, intensity) + 1 text (ms, duration,
# u16-prefixed string, u8); timing points are left empty (no layout is defined anywhere)
def fx_tail():
    t = struct.pack('<i', 0)                                         # timing points
    t += struct.pack('<i', 1) + struct.pack('<IIBBf', 1000, 500, 1, 2, 0.5)   # brightness
    t += struct.pack('<4i', 0, 0, 0, 0)                              # contrast, saturation, blur, fov
    t += struct.pack('<3i', 0, 0, 0)                                 # tint, position, rotation
    t += struct.pack('<i', 0)                                        # ar factor
    s = 'hello'.encode()
    t += struct.pack('<i', 1) + struct.pack('<IIH', 2000, 300, len(s)) + s + b'\x01'   # text
    return t

def tp_tail():  # one timing point: no known layout (8 bytes of something), then the rest
    return struct.pack('<i', 1) + struct.pack('<If', 0, 120.0) + struct.pack('<10i', *[0] * 10)

def png(w, h):
    raw = b''.join(b'\0' + b''.join(bytes((x * 4 % 256, y * 4 % 256, 128)) for x in range(w)) for y in range(h))
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')

def meta(m, mid, diff_name=None):
    return json.dumps({'ID': mid, 'Artist': m['artist'], 'ArtistLink': '', 'ArtistPlatform': '', 'Title': m['title'], 'Rating': 0,
                       'Mappers': m['mappers'], 'Difficulty': m['diff'], 'DifficultyName': diff_name or ['N/A', 'Easy', 'Medium', 'Hard', 'Insane', 'Illogical'][m['diff']],
                       'Length': m['notes'][-1][0], 'HasAudio': True, 'HasCover': m['cover'] is not None, 'HasVideo': False,
                       'AudioExt': 'ogg' if m['audio'][:4] == b'OggS' else 'mp3'}, indent='\t')

def write(path, m, mid, notes=None, deflate=False, prefix='', diff_name=None, video=False, tail=None, extra_meta=None):
    comp = zipfile.ZIP_DEFLATED if deflate else zipfile.ZIP_STORED
    rw = notes if notes is not None else [(ms, x - 1, 1 - y) for ms, x, y in m['notes']]  # .sspm -> rewrite (MapParser.sspmV2)
    md = meta(m, mid, diff_name)
    if extra_meta:
        d = json.loads(md)
        d.update(extra_meta)
        md = json.dumps(d, indent='\t')
    with zipfile.ZipFile(path, 'w', comp) as z:
        z.writestr(prefix + 'metadata.json', md)
        z.writestr(prefix + 'objects.phxmo', phxmo(rw, tail))
        z.writestr(prefix + 'audio.' + ('ogg' if m['audio'][:4] == b'OggS' else 'mp3'), m['audio'])
        if m['cover']: z.writestr(prefix + 'cover.png', m['cover'])
        if video: z.writestr(prefix + 'video.mp4', os.urandom(1 << 20))

m = sspm2(sys.argv[1])
out = sys.argv[2]
os.makedirs(out, exist_ok=True)
m['cover'] = png(64, 48)
write(os.path.join(out, 't_stored.phxm'), m, 'phxm_test_stored')
write(os.path.join(out, 't_deflate.phxm'), m, 'Roach Deflate!', deflate=True, prefix='Roach/', diff_name='Expert+', video=True)
write(os.path.join(out, 't_quantum.phxm'), m, 'phxm_test_quantum', notes=[(1000, 0.5, -0.25), (1500, 1, 1), (2000, -1, -1), (2500, 0.3333, 0.75)])
write(os.path.join(out, 't_jp.phxm'), m, 'ロード')
write(os.path.join(out, 't_dup.phxm'), m, m['id'])
for n in ('drop', 'drop2', 'dialog'): write(os.path.join(out, 't_%s.phxm' % n), m, 'phxm_test_' + n)
# round trips: effects + extra metadata a .sspm can't hold; a timing point of unknown layout
write(os.path.join(out, 't_fx.phxm'), m, 'phxm_test_fx', tail=fx_tail(), diff_name='Expert+',
      extra_meta={'Rating': 4.5, 'ArtistLink': 'https://example.com/artist', 'ArtistPlatform': 'YouTube', 'Mappers': ['BatBrice', 'Second Mapper']})
write(os.path.join(out, 't_tp.phxm'), m, 'phxm_test_tp', tail=tp_tail())
write(os.path.join(out, 't_rtq.phxm'), m, 'phxm_test_rtq', notes=[(1000, 0.5, -0.25), (1500, 1, 1), (2000, -1, -1), (2500, 0.3333, 0.75), (3000, 1.5, 0)])
open(os.path.join(out, 't_broken.phxm'), 'wb').write(os.urandom(5000))
print('notes %d, diff %d, id %s, artist %r, title %r, mappers %r' % (len(m['notes']), m['diff'], m['id'], m['artist'], m['title'], m['mappers']))
