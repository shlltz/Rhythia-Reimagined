r"""Rhythia-reimagined: Rhythia Legacy (Sound Space Plus nightly, Godot 3.6.2) mod tool. Close the game, then:  py -3 ssp_mod.py <command>

Every change rebuilds SoundSpacePlus.pck from the original game files + the mods listed in profile.json,
so removed mods leave nothing behind. The previous game file is kept in backup/SoundSpacePlus.pck.

  status                                     show installed mods
  rebuild                                    rebuild the game file from profile.json
  <mod> [--undo]                             install / remove a mod (list below)
  font FILE [--target hud,mono|all|res://..] replace UI fonts
  theme [--width 2] [--undo]                 monochrome, square, outline-only UI
  bigsettings [--scale 1.2] [--hints] [--plain] [--undo]   bigger, friendlier settings page
  border IMAGE.png|.texdata [--opacity X]    play-area border art (PNG needs Pillow; .texdata doesn't)
  opacity X                                  border opacity only
  restore                                    remove every mod (original game)
  package [--out ZIP]                        shareable no-Python patch (replay + stars), default ..\..\Rhythia-reimagined-lite-vX.Y.Z.zip
  portable [--out ZIP]                       ready-to-play zip: game exe + DLLs + pck with the share build (with map browser)
  apk APK [--out FILE]                       Rhythia Legacy Android: mods written into the APK (unsigned; sign before installing)
  tweaks [--without browser]                 full share zip ..\..\Rhythia-reimagined-vX.Y.Z.zip
  version [X.Y.Z]                            show / set the version (version.txt; zip names, README, title screen)

Mods:
  replay      replay browser + viewer (seek/speed/pause/H-hide), menu animations, parallax, topo background,
              Alt+wheel volume, audio visualizer, loading screen, FPS tweaks, hides Rewrite button/version
  stars       star ratings (Steam Rhythia formula) + star sort + Content Manager restyle
  fixes       map cache fix (newer-editor maps broke map_cache.json)
  browser     "Browse" sidebar button: search/sort/download maps from rhythia.com (needs replay)
  discord     Discord status from your own Discord app: discord --app-id ID [--image glitchia] [--text Glitchia]
  autodelete  imported map files go to the Recycle Bin
  intro       osu!-style startup intro (logo zoom + sound)
  results     osu-style results panel
  lang        Vietnamese (in the Polish slot)
"""
import struct, os, re, io, sys, json, shutil, zipfile, argparse
if hasattr(sys.stdout, "reconfigure"): sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))           # ...\Rhythia Legacy\_modding
GAME = os.path.dirname(HERE)
PCK = os.path.join(GAME, 'SoundSpacePlus.pck')
BAK = os.path.join(HERE, 'originals.bin')                   # original copies of every game file a mod changed - keep it
SRC = os.path.join(HERE, 'src')
PROFILE = os.path.join(HERE, 'profile.json')
BACKUP = os.path.join(HERE, 'backup', 'SoundSpacePlus.pck')
TEX = 'res://.import/grid_outer.png-f4c8cab69e18562aa33960a360e387d6.s3tc.stex'
SCN = 'res://scenes/song.tscn'

# ---------- pck ----------
class Pck:
    def __init__(s, fn):
        s.fn = fn; f = s.f = open(fn, 'rb')
        s.head = f.read(84); assert s.head[:4] == b'GDPC'
        n, = struct.unpack('<I', f.read(4)); s.ents = []
        for _ in range(n):
            l, = struct.unpack('<I', f.read(4)); raw = f.read(l)
            off, size = struct.unpack('<QQ', f.read(16)); md5 = f.read(16)
            s.ents.append([raw, off, size, md5])
        s.by = {e[0].rstrip(b'\0').decode(): e for e in s.ents}
        s.new = {}; s.bak = load_bak()
    def drop(s, p):                                       # remove an added file again
        e = s.by.pop(p); s.ents.remove(e); s.new.pop(p, None)
    def read(s, p):
        if p in s.new: return s.new[p]
        e = s.by[p]; s.f.seek(e[1]); return s.f.read(e[2])
    def add(s, p, data):                                  # new file (not in the original pck)
        if p not in s.by:
            raw = p.encode(); raw += bytes(-len(raw) % 4)
            e = [raw, 0, 0, bytes(16)]; s.ents.append(e); s.by[p] = e
        s.new[p] = data
    def write(s, p, data):
        if p not in s.bak: s.bak[p] = s.read(p)          # remember the original once
        s.new[p] = data
    def save(s, bak=True):
        if bak: save_bak(s.bak)
        tmp = s.fn + '.tmp'; idx_len = 88 + sum(4 + len(e[0]) + 32 for e in s.ents)
        pos = (idx_len + 15) // 16 * 16; place = {}
        for e in sorted(s.ents, key=lambda e: e[1]):
            p = e[0].rstrip(b'\0').decode(); size = len(s.new[p]) if p in s.new else e[2]
            place[p] = (pos, size); pos = (pos + size + 15) // 16 * 16
        with open(tmp, 'wb') as o:
            o.write(s.head); o.write(struct.pack('<I', len(s.ents)))
            for e in s.ents:
                p = e[0].rstrip(b'\0').decode(); off, size = place[p]
                o.write(struct.pack('<I', len(e[0])) + e[0] + struct.pack('<QQ', off, size) + e[3])
            for e in sorted(s.ents, key=lambda e: place[e[0].rstrip(b'\0').decode()][0]):
                p = e[0].rstrip(b'\0').decode(); off, size = place[p]
                o.write(b'\0' * (off - o.tell())); o.write(s.read(p))
        s.f.close(); os.replace(tmp, s.fn)

def load_bak():
    d = {}
    if os.path.exists(BAK):
        b = open(BAK, 'rb').read(); i = 0
        while i < len(b):
            l, n = struct.unpack('<II', b[i:i + 8]); i += 8
            d[b[i:i + l].decode()] = b[i + l:i + l + n]; i += l + n
    return d
def save_bak(d):
    with open(BAK, 'wb') as o:
        for p, data in d.items():
            k = p.encode(); o.write(struct.pack('<II', len(k), len(data)) + k + data)

# ---------- border ----------
def border(pk, png, opacity=None):
    if png and png.endswith('.texdata'):
        d = pk.read(TEX); raw = open(png, 'rb').read(); assert len(raw) == len(d) - 20, 'texdata size mismatch'
        pk.write(TEX, d[:20] + raw); print('border image set (pre-encoded)')
    elif png:
        from PIL import Image
        d = pk.read(TEX); w, _, h, _ = struct.unpack('<HHHH', d[4:12])
        im = Image.open(png).convert('RGBA').rotate(90, expand=True).resize((w, h), Image.LANCZOS)   # game shows the texture turned 90 deg clockwise; pre-rotate so it appears upright
        if im.getchannel('A').getextrema() == (255, 255):
            print('warning: image has no transparency - it will cover the play area')
        out = b''; mw, mh = w, h
        while True:
            lvl = im if (mw, mh) == (w, h) else im.resize((mw, mh), Image.LANCZOS)
            pw, ph = (mw + 3) // 4 * 4, (mh + 3) // 4 * 4
            if (pw, ph) != (mw, mh): pad = Image.new('RGBA', (pw, ph)); pad.paste(lvl); lvl = pad
            b = io.BytesIO(); lvl.save(b, 'DDS', pixel_format='DXT5')
            out += b.getvalue()[128:128 + (pw // 4) * (ph // 4) * 16]
            if mw == 1 and mh == 1: break
            mw, mh = max(1, mw // 2), max(1, mh // 2)
        assert len(out) == len(d) - 20
        pk.write(TEX, d[:20] + out); print('border image set')
        open(os.path.splitext(png)[0] + '.texdata', 'wb').write(out)   # reusable without Pillow
    if opacity is not None:
        s = pk.read(SCN); i = s.find(b'[sub_resource type="SpatialMaterial" id=31]')
        key = b'albedo_color = Color( 1, 1, 1, '; j = s.find(key, i) + len(key); k = s.find(b' )', j)
        pk.write(SCN, s[:j] + ('%g' % max(0, min(1, opacity))).encode() + s[k:]); print('border opacity', opacity)

# ---------- font ----------
FONTS = {'hud': ['Lato/Lato-Regular.ttf', 'Lato/Lato-Bold.ttf', 'Lato/Lato-Light.ttf', 'Lato/Lato-Black.ttf'],
         'mono': ['UbuntuMono/Regular.ttf']}
FONTS['all'] = FONTS['hud'] + FONTS['mono'] + ['Roboto/Regular.ttf', 'Roboto/Medium.ttf', 'Lato/Lato-Italic.ttf']
def font(pk, fn, target):
    data = open(fn, 'rb').read(); assert data[:4] in (b'\0\1\0\0', b'OTTO', b'true'), 'not a ttf/otf'
    ts = []
    for t in target.split(','): ts += [t] if t.startswith('res://') else ['res://assets/font/' + p for p in FONTS[t]]
    for t in ts: pk.write(t, data); print('font', t)

# ---------- theme ----------
KEEP_FILL = {'fg', 'grabber', 'grabber_highlight', 'grabber_pressed', 'grabber_area', 'grabber_area_highlight', 'slider', 'scroll', 'scroll_focus', 'fill'}
SKIP = ('res://assets/worlds/', SCN)
T3D = ('SpatialMaterial', 'ShaderMaterial', 'Environment', 'ParticlesMaterial', 'Shader', 'ArrayMesh', 'Gradient', 'GradientTexture')
COL = re.compile(r'Color\( *([-\d.e]+), *([-\d.e]+), *([-\d.e]+), *([-\d.e]+) *\)')
luma = lambda r, g, b: 0.299 * r + 0.587 * g + 0.114 * b
# keep these original colours (results / end-of-song stats)
KEEP_PATH = ('EndInfo',)
# difficulty colours: original -> clearer, brighter, easy to tell apart
DIFF = {'EASY': ((0, 1, 0), (0.3, 1, 0.45)), 'MEDIUM': ((1, 0.72549, 0), (1, 0.85, 0.15)),
        'HARD': ((1, 0, 0), (1, 0.25, 0.25)), 'LOGIC': ((0.843137, 0.415686, 1), (0.75, 0.4, 1)),
        'TASUKETE': ((0.211765, 0.188235, 0.309804), (0.211765, 0.188235, 0.309804)), 'AMOGUS': ((0.211765, 0.188235, 0.309804), (0.211765, 0.188235, 0.309804))}
def C(l, al): return 'Color( %s, %s, %s, %s )' % tuple('%g' % round(v, 6) for v in (l, l, l, al))
def theme_text(t, width, mono=True, edge=None):
    # mono: square + greyscale (own look); mono=False keeps corners and colours, edge(L) gives the outline colour
    keep = {m.group(2) for m in re.finditer(r'([\w/]+) = SubResource\( (\d+) \)', t) if m.group(1).split('/')[-1] in KEEP_FILL}
    def txt(m):
        r, g, b, al = (float(x) for x in m.groups()[1:]); L = luma(r, g, b)
        return '%s = %s' % (m.group(1), C(1 - L if L < 0.35 else L, al))
    res = []
    for blk in re.split(r'(?m)^(?=\[)', t):
        h = re.match(r'\[sub_resource type="(\w+)" id=(\d+)\]', blk)
        if h and h.group(1) in T3D: res.append(blk); continue
        nd = re.match(r'\[node name="([^"]*)"([^\]]*)\]', blk)
        par = re.search(r'parent="([^"]*)"', nd.group(2)) if nd else None
        path = ((par.group(1) if par else '') + '/' + nd.group(1)).split('/') if nd else []
        if any(k in seg for seg in path for k in KEEP_PATH): res.append(blk); continue
        for seg in path:
            if seg in DIFF:
                (o, n) = DIFF[seg]
                def dsub(m, o=o, n=n):
                    v = [float(x) for x in m.groups()]
                    if all(abs(a - b) < 0.002 for a, b in zip(v[:3], o)):
                        return 'KEEPCOL( %s, %s, %s, %s )' % tuple('%g' % x for x in (*n, v[3]))
                    return m.group(0)
                blk = COL.sub(dsub, blk)
        if h and h.group(1) == 'StyleBoxFlat':
            if mono: blk = re.sub(r'(?m)^corner_(radius_\w+|detail) = .*\n', '', blk)
            elif 'corner_radius_' not in blk:          # share: round the (square) stock boxes
                blk = blk.rstrip('\n') + '\n' + ''.join('corner_radius_%s = 6\n' % c for c in ('top_left', 'top_right', 'bottom_right', 'bottom_left')) + 'corner_detail = 5\nanti_aliasing = true\n\n'
            bg = re.search(r'(?m)^bg_color = ' + COL.pattern, blk)
            r, g, b, al = (float(x) for x in bg.groups()) if bg else (0.6, 0.6, 0.6, 1); L = luma(r, g, b)
            if 'draw_center = false' not in blk and h.group(2) not in keep and al > 0.3 and L >= 0.3:
                blk = blk.rstrip('\n') + '\ndraw_center = false\n'
                if 'border_width_' not in blk:
                    blk += ''.join('border_width_%s = %d\n' % (x, width) for x in ('left', 'top', 'right', 'bottom'))
                blk = re.sub(r'(?m)^border_color = .*\n', '', blk) + 'border_color = %s\n\n' % (C(min(1, 0.55 + 0.45 * L), 1) if mono else edge(L))
        blk = re.sub(r'(?m)^([\w/]*(?:font_color(?!_shadow)\w*|cursor_color|clear_button_color\w*)) = ' + COL.pattern, txt, blk)
        if mono: blk = COL.sub(lambda m: C(luma(*(float(x) for x in m.groups()[:3])), float(m.group(4))), blk)
        res.append(blk.replace('KEEPCOL(', 'Color('))
    return ''.join(res)
def theme(pk, width, mono=True, edge=None, current=False):
    n = 0
    for p in list(pk.by):
        if not p.endswith(('.tscn', '.tres')) or p.startswith(SKIP): continue
        raw = pk.read(p) if current else (pk.bak.get(p) or pk.read(p))   # own theme: from the original; share: on top of the other mods
        if not raw.startswith(b'[gd_'): continue
        t = raw.decode('utf-8'); nt = theme_text(t, width, mono, edge)
        if nt.encode('utf-8') != pk.read(p): pk.write(p, nt.encode('utf-8')); n += 1
    print('theme applied to', n, 'files')

# ---------- osu-style results layout ----------
MENU = 'res://scenes/menu/menu2.tscn'
EI = 'Main/Maps/Results/Results/RS/H2/EndInfo'
def set_props(t, header, props, drop=()):
    i = t.find(header); assert i >= 0, header
    j = t.find('\n[', i + 1); j = len(t) if j < 0 else j
    blk = t[i:j]; lines = blk.split('\n'); head, body = lines[0], lines[1:]
    body = [l for l in body if l.split(' = ')[0] not in props and l.split(' = ')[0] not in drop]
    while body and body[-1] == '': body.pop()
    body = ['%s = %s' % kv for kv in props.items()] + body
    return t[:i] + '\n'.join([head] + body) + '\n\n' + t[j + 1:].lstrip('\n') if j < len(t) else t[:i] + '\n'.join([head] + body) + '\n'
def font_size(t, rid, size):
    return re.sub(r'(\[sub_resource type="DynamicFont" id=%d\]\n)(size = \d+\n)?' % rid, lambda m: m.group(1) + 'size = %d\n' % size, t)
def results(pk):
    t = pk.read(MENU).decode('utf-8')
    N = lambda name, parent=EI: '[node name="%s" type="Label" parent="%s"]' % (name, parent)
    M = lambda l, tp, r, b: {'margin_left': '%.1f' % l, 'margin_top': '%.1f' % tp, 'margin_right': '%.1f' % r, 'margin_bottom': '%.1f' % b}
    ANCH = ('anchor_left', 'anchor_top', 'anchor_right', 'anchor_bottom')
    # header line ("Personal Best" / "New best!") left aligned
    t = set_props(t, N('Result'), {**M(5, 0, 273, 36), 'align': '0'})
    # big grade on the right, like osu ranking
    t = set_props(t, N('LetterGrade'), {**M(140, 34, 274, 230), 'align': '1', 'valign': '1'}, drop=('visible',))
    t = font_size(t, 127, 150)
    # stat column on the left: small title above, value under it
    rows = [('Misses', 60, 32), ('FullCombo', 60, 32), ('Pauses', 112, 32), ('NoPauses', 112, 32),
            ('Progress', 164, 48), ('Accuracy', 232, 48), ('MaxCombo', 300, 48)]
    for name, y, h in rows:
        t = set_props(t, N(name), {**M(5, y, 150, y + h), 'align': '0', 'valign': '0'})
        t = set_props(t, N('Title', EI + '/' + name), {**M(0, -17, 145, -1), 'align': '0', 'valign': '1'}, drop=ANCH)
    t = font_size(t, 105, 26); t = font_size(t, 108, 20); t = font_size(t, 106, 14)
    pk.write(MENU, t.encode('utf-8')); print('osu-style results layout applied')

# ---------- language pack (Vietnamese replaces the Polish slot) ----------
LOC = 'res://localization/localization.%s.translation'
def _rs(d, i):
    n, = struct.unpack('<I', d[i:i + 4]); return d[i + 4:i + 4 + n].rstrip(b'\0').decode('utf8'), i + 4 + n
def _ws(s):
    b = s.encode('utf8') + b'\0'; return struct.pack('<I', len(b)) + b
def phash_h(d, s):
    d = d or 0x1000193
    for b in s.encode('utf8'):
        if b >= 128: b |= 0xFFFFFF00
        d = ((d * 0x1000193) & 0xFFFFFFFF) ^ b
    return d
class PHash:
    def __init__(s, d):
        assert d[:4] == b'RSRC'; i = 24; s.type, i = _rs(d, i); i += 64; s.head = d[:i]
        n, = struct.unpack('<I', d[i:i + 4]); i += 4; names = []
        for _ in range(n): x, i = _rs(d, i); names.append(x)
        i += 8; _, i = _rs(d, i); off, = struct.unpack('<Q', d[i:i + 8]); i = off
        s.rtype, i = _rs(d, i); pc, = struct.unpack('<I', d[i:i + 4]); i += 4; s.p = {}
        for _ in range(pc):
            ni, vt = struct.unpack('<II', d[i:i + 8]); i += 8
            if vt == 32: c, = struct.unpack('<I', d[i:i + 4]); v = list(struct.unpack('<%di' % c, d[i + 4:i + 4 + 4 * c])); i += 4 + 4 * c
            elif vt == 31: c, = struct.unpack('<I', d[i:i + 4]); v = bytearray(d[i + 4:i + 4 + c]); i += 4 + c + (-c % 4)
            elif vt == 5: v, i = _rs(d, i)
            else: raise ValueError('unsupported variant %d' % vt)
            s.p[names[ni]] = v
    def set(s, key, val):
        ht, bt = s.p['hash_table'], s.p['bucket_table']
        idx = ht[phash_h(0, key) % len(ht)]
        if idx == -1: return False
        size, func = bt[idx], bt[idx + 1] & 0xFFFFFFFF; hk = phash_h(func, key)
        for e in range(size):
            j = idx + 2 + e * 4
            if bt[j] & 0xFFFFFFFF == hk:
                b = val.encode('utf8') + b'\0'; off = len(s.p['strings']); s.p['strings'] += b
                bt[j + 1], bt[j + 2], bt[j + 3] = off, len(b), len(b); return True
        return False
    def dump(s):
        names = ['hash_table', 'bucket_table', 'strings', 'locale']
        body = _ws(s.rtype) + struct.pack('<I', 4)
        ht = s.p['hash_table']; bt = [x if x < 2**31 else x - 2**32 for x in s.p['bucket_table']]; st = bytes(s.p['strings'])
        body += struct.pack('<II', 0, 32) + struct.pack('<I%di' % len(ht), len(ht), *ht)
        body += struct.pack('<II', 1, 32) + struct.pack('<I%di' % len(bt), len(bt), *bt)
        body += struct.pack('<II', 2, 31) + struct.pack('<I', len(st)) + st + b'\0' * (-len(st) % 4)
        body += struct.pack('<II', 3, 5) + _ws(s.p.get('locale', 'en'))
        pre = s.head + struct.pack('<I', len(names)) + b''.join(_ws(n) for n in names) + struct.pack('<I', 0) + struct.pack('<I', 1) + _ws('local://1')
        off = len(pre) + 8
        return pre + struct.pack('<Q', off) + body + b'RSRC'
def lang(pk):
    import json
    vi = json.load(open(os.path.join(SRC, 'lang', 'vi.json'), encoding='utf8'))
    src = pk.bak.get(LOC % 'en') or pk.read(LOC % 'en')
    t = PHash(src); t.p['locale'] = 'pl'; n = sum(t.set(k, v) for k, v in vi.items())
    pk.write(LOC % 'pl', t.dump()); print('Vietnamese: %d strings (in the Polish slot)' % n)
    for code in ('en', 'fr', 'ja', 'es', 'it'):
        o = PHash(pk.bak.get(LOC % code) or pk.read(LOC % code))
        if code != 'en': o.p.setdefault('locale', code)
        o.set('POLISH', 'Tiếng Việt'); pk.write(LOC % code, o.dump())
    print('language menu now lists "Tiếng Việt" instead of Polish')

# ---------- bigger settings page ----------
SETTINGS = 'res://prefabs/menu/settings_page.tscn'
def bigsettings(pk, scale, friendly=True, hints=False):
    t = (pk.bak.get(SETTINGS) or pk.read(SETTINGS)).decode('utf-8')     # fresh from the original (+ theme when it is installed)
    if THEMED: t = theme_text(t, 2)
    def fsz(m):
        blk = m.group(0); cur = re.search(r'(?m)^size = (\d+)', blk); n = int(cur.group(1)) if cur else 16
        new = 'size = %d\n' % round(n * scale)
        return re.sub(r'(?m)^size = \d+\n', new, blk) if cur else blk.replace(']\n', ']\n' + new, 1)
    t = re.sub(r'\[sub_resource type="DynamicFont" id=\d+\]\n(?:[^\[\n][^\n]*\n)*', fsz, t)
    font = re.search(r'\[sub_resource type="DynamicFont" id=(\d+)\]\nsize = \d+\nuse_filter = true\nfont_data = ExtResource\( 2 \)\nfallback/0 = ExtResource\( 3 \)\n', t).group(1)
    out = []
    for blk in re.split(r'(?m)^(?=\[)', t):
        h = re.match(r'\[node name="[^"]*" type="(\w+)"', blk)
        if h and h.group(1) in ('CheckBox', 'SpinBox', 'ColorPickerButton', 'Button', 'MenuButton', 'OptionButton'):
            ms = re.search(r'(?m)^rect_min_size = Vector2\( ([-\d.]+), ([-\d.]+) \)', blk)
            if ms:
                x, y = float(ms.group(1)), float(ms.group(2)) or 26.0
                blk = blk.replace(ms.group(0), 'rect_min_size = Vector2( %g, %g )' % (x, round(y * scale)))
            else:
                blk = blk.rstrip('\n') + '\nrect_min_size = Vector2( 0, %d )\n\n' % round(26 * scale)
            if h.group(1) in ('Button', 'MenuButton', 'OptionButton') and 'custom_fonts/font' not in blk:
                blk = blk.rstrip('\n') + '\ncustom_fonts/font = SubResource( %s )\n\n' % font
        out.append(blk)
    t = ''.join(out)
    if friendly: t = friendly_settings(t, scale, hints)
    pk.write(SETTINGS, t.encode('utf-8')); print('settings page scaled x%g%s' % (scale, ' + friendly layout' if friendly else ''))

SECTION_TITLES = {'UI': 'Interface', 'UIColor': 'Colors'}
def friendly_settings(t, scale, hints=False):
    ids = [int(x) for x in re.findall(r'\[(?:sub|ext)_resource [^\]]*id=(\d+)', t)]; nid = max(ids) + 1
    R = {}
    def sub(kind, body):
        nonlocal nid
        R[nid] = '[sub_resource type="%s" id=%d]\n%s\n' % (kind, nid, body); nid += 1; return nid - 1
    card = sub('StyleBoxFlat', 'bg_color = Color( 1, 1, 1, 0.035 )\nborder_width_left = 1\nborder_width_top = 1\nborder_width_right = 1\nborder_width_bottom = 1\nborder_color = Color( 1, 1, 1, 0.22 )\nexpand_margin_left = 16.0\nexpand_margin_right = 16.0\nexpand_margin_top = 12.0\nexpand_margin_bottom = 12.0')
    hfont = sub('DynamicFont', 'size = %d\nuse_filter = true\nfont_data = ExtResource( 40 )\nfallback/0 = ExtResource( 3 )' % round(24 * scale))
    hline = sub('StyleBoxLine', 'color = Color( 1, 1, 1, 0.45 )\nthickness = 2')
    nosep = sub('StyleBoxEmpty', '')
    dfont = sub('DynamicFont', 'size = %d\nuse_filter = true\nfont_data = ExtResource( 2 )\nfallback/0 = ExtResource( 3 )' % round(13 * scale))
    hover = sub('StyleBoxFlat', 'bg_color = Color( 1, 1, 1, 0.09 )')
    tfg = sub('StyleBoxFlat', 'content_margin_left = 18.0\ncontent_margin_right = 18.0\ncontent_margin_top = 8.0\ncontent_margin_bottom = 8.0\nbg_color = Color( 1, 1, 1, 0.14 )\nborder_width_bottom = 3\nborder_color = Color( 1, 1, 1, 1 )')
    tbg = sub('StyleBoxFlat', 'content_margin_left = 18.0\ncontent_margin_right = 18.0\ncontent_margin_top = 8.0\ncontent_margin_bottom = 8.0\ndraw_center = false\nborder_width_bottom = 1\nborder_color = Color( 1, 1, 1, 0.25 )')
    tfont = sub('DynamicFont', 'size = %d\nuse_filter = true\nfont_data = ExtResource( 40 )\nfallback/0 = ExtResource( 3 )' % round(18 * scale))
    blocks = re.split(r'(?m)^(?=\[)', t)
    first_node = next(i for i, b in enumerate(blocks) if b.startswith('[node'))
    blocks = blocks[:first_node] + [R[k] + '\n' for k in sorted(R)] + blocks[first_node:]
    def info(b):
        m = re.match(r'\[node name="([^"]*)" type="(\w+)"(?: parent="([^"]*)")?', b)
        if not m: return None
        par = m.group(3); path = m.group(1) if par is None else (m.group(1) if par == '.' else par + '/' + m.group(1))
        return m.group(1), m.group(2), par, path
    def addp(b, props):
        b = b.rstrip('\n'); lines = b.split('\n')
        keys = {k for k in props}; lines = [lines[0]] + [l for l in lines[1:] if l.split(' = ')[0] not in keys]
        return '\n'.join(lines + ['%s = %s' % kv for kv in props.items()]) + '\n\n'
    tabs = 'TabContainer'; out = []; pending = None; nhint = 0
    for b in blocks:
        inf = info(b)
        if pending and (inf is None or not (inf[2] or '').startswith(pending[0])):
            out.append(pending[1]); pending = None
        if not inf: out.append(b); continue
        name, typ, par, path = inf
        depth = path.count('/')
        if path == tabs:
            b = addp(b, {'custom_styles/tab_fg': 'SubResource( %d )' % tfg, 'custom_styles/tab_bg': 'SubResource( %d )' % tbg,
                         'custom_fonts/font': 'SubResource( %d )' % tfont, 'custom_colors/font_color_fg': 'Color( 1, 1, 1, 1 )',
                         'custom_colors/font_color_bg': 'Color( 0.62, 0.62, 0.62, 1 )'})
            out.append(b); continue
        if typ == 'HSeparator' and par and par.startswith(tabs + '/') and depth == 2:      # separators between sections
            out.append(addp(b, {'custom_styles/separator': 'SubResource( %d )' % nosep, 'custom_constants/separation': '34'})); continue
        if typ == 'VBoxContainer' and par and par.startswith(tabs + '/') and depth == 2 and ('[node name="Group" type="MarginContainer" parent="%s"]' % path) in t:
            out.append(addp(b, {'custom_constants/separation': '10'}))
            title = SECTION_TITLES.get(name, name)
            out.append('[node name="SectionTitle" type="Label" parent="%s"]\ncustom_fonts/font = SubResource( %d )\ncustom_colors/font_color = Color( 1, 1, 1, 1 )\ntext = "%s"\n\n' % (path, hfont, title))
            out.append('[node name="SectionLine" type="HSeparator" parent="%s"]\nrect_min_size = Vector2( 0, 6 )\ncustom_styles/separator = SubResource( %d )\n\n' % (path, hline))
            continue
        if name == 'Group' and typ == 'MarginContainer' and par and par.startswith(tabs + '/'):
            out.append(addp(b, {'custom_constants/margin_left': '40', 'custom_constants/margin_right': '60', 'custom_constants/margin_top': '16', 'custom_constants/margin_bottom': '16'}))
            out.append('[node name="Card" type="Panel" parent="%s"]\nmouse_filter = 2\ncustom_styles/panel = SubResource( %d )\n\n' % (path, card))
            continue
        if name == 'H' and typ == 'GridContainer' and par and par.endswith('/Group'):
            out.append(addp(b, {'custom_constants/vseparation': '8'})); continue
        if par and par.endswith('/Group/H') and typ in ('CheckBox', 'HBoxContainer'):
            if typ == 'HBoxContainer': b = addp(b, {'custom_constants/separation': '14'})
            else: b = addp(b, {'flat': 'false', 'custom_styles/normal': 'SubResource( %d )' % nosep, 'custom_styles/pressed': 'SubResource( %d )' % nosep,
                                'custom_styles/focus': 'SubResource( %d )' % nosep, 'custom_styles/disabled': 'SubResource( %d )' % nosep,
                                'custom_styles/hover': 'SubResource( %d )' % hover, 'custom_styles/hover_pressed': 'SubResource( %d )' % hover})
            tip = re.search(r'(?m)^hint_tooltip = ("(?:[^"\\]|\\.)*")$', b)
            out.append(b)
            shown_desc = re.search(r'\[node name="Desc" type="Label" parent="%s"\]\n(?!visible = false)' % re.escape(path), t)
            if hints and tip and len(tip.group(1)) > 2 and not re.search(r'(?m)^visible = false$', b) and not shown_desc:
                nhint += 1
                pending = (path + '/', '[node name="Hint%d" type="Label" parent="%s"]\nrect_min_size = Vector2( 900, 0 )\nmouse_filter = 2\ncustom_fonts/font = SubResource( %d )\ncustom_colors/font_color = Color( 0.6, 0.6, 0.6, 1 )\ntext = %s\nautowrap = true\n\n' % (nhint, par, dfont, tip.group(1)))
            continue
        if name == 'Label' and typ == 'Label' and par and '/Group/H/' in par and par.count('/') == 5:
            b = addp(b, {'rect_min_size': 'Vector2( %d, 0 )' % round(220 * scale), 'align': '0'})
        out.append(b)
    if pending: out.append(pending[1])
    return ''.join(out)

# ---------- script mods: text scripts added under res://mods/<dir>/, game scripts repointed to them ----------
# name: (pck dir, {source file: game script it replaces}, [extra files])
SCRIPT_MODS = {
    'fixes': ('fixes', {'Song.gd': 'res://scripts/content/game/Song.gd'}, []),
    'stars': ('stars', {'SongInfoScreen.gd': 'res://scripts/ui/menu/SongInfoScreen.gd',
                        'v3MapList.gd': 'res://scripts/ui/menu/buttons/v3MapList.gd',
                        'StartOffset.gd': 'res://scripts/ui/menu/StartOffset.gd',
                        'contentmgr.gd': 'res://scripts/ui/cmgr/contentmgr.gd'},
              ['StarRating.gd', 'StarCache.gd', 'StarBadge.gd', 'CMIcon.gd', 'CMStyle.gd', 'RecentPlays.gd', 'IconGlyph.gd']),
    'replay': ('replay', {'Replay.gd': 'res://scripts/content/game/Replay.gd', 'NoteManager.gd': 'res://scripts/game/NoteManager.gd',
                          'Game.gd': 'res://scripts/game/Game.gd', 'menu2.gd': 'res://scripts/ui/menu/menu2.gd',
                          'HUD.gd': 'res://scripts/game/HUD.gd', 'CursorTrail.gd': 'res://scripts/game/CursorTrail.gd',
                          'songload.gd': 'res://scripts/loaders/songload.gd', 'EndInfo.gd': 'res://scripts/ui/menu/buttons/EndInfo.gd'},
               ['ReplayViewer.gd', 'ReplayBrowser.gd', 'UIAnim.gd', 'VolumeOverlay.gd', 'LoadScreen.gd', 'AudioVisualizer.gd', 'PauseMenu.gd', 'UIJuice.gd', 'OsuSfx.gd', 'TitleMenu.gd', 'ResultsScreen.gd',
                'Reimagined.gd', 'ReimaginedPanel.gd', 'OsuTrail.gd', 'SettingsStyle.gd', 'MusicPause.gd', 'TouchScroll.gd', 'Icons.gd', 'Ring.gd',
                'icons/uicons-solid-rounded.woff', 'icons/Flaticon-license.txt']),
    'browser': ('browser', {}, ['MapBrowser.gd']),
    'hype': ('hype', {}, ['Hype.gd', 'PassFx.gd']),     # cover visualizer, 7+/10+ star glow / quake / lightning, pass glow + zoom
    'osuskin': ('osuskin', {}, sorted(os.listdir(os.path.join(SRC, 'osuskin'))) if os.path.isdir(os.path.join(SRC, 'osuskin')) else []),  # osu! skin sounds/images (raw files)
    'discord': ('discord', {'discord.gd': 'res://addons/discord_game_sdk/discord.gd'}, []),
    'autodelete': ('import', {'AddSong.gd': 'res://scripts/ui/cmgr/AddSong.gd',
                              'RunMapButton.gd': 'res://scripts/ui/menu/buttons/RunMapButton.gd'}, ['ImportCleanup.gd']),
}
VERSION_FILE = os.path.join(HERE, 'version.txt')
def version(): return open(VERSION_FILE).read().strip() if os.path.exists(VERSION_FILE) else '0.0.0'
def src(*p):
    with open(os.path.join(SRC, *p), 'rb') as f: return f.read()
def script_mod(pk, name, opts=None):
    pdir, swap, extra = SCRIPT_MODS[name]
    def data(f):                                                    # @@KEY@@ in a source = option 'key' from profile.json
        d = src(name, f)
        for k, v in (opts or {}).items(): d = d.replace(('@@%s@@' % k.upper()).encode(), str(v).encode())
        d = d.replace(b'@@VERSION@@', version().encode())
        if ACCENT and f.endswith('.gd'): d = d.replace(MOD_ACCENT, b'#' + ACCENT.encode())
        assert not f.endswith('.gd') or b'@@' not in d, '%s/%s has an unfilled @@option@@' % (name, f)
        return d
    for f, orig in swap.items():
        target = 'res://mods/%s/%s' % (pdir, f)
        pk.add(target, data(f)); pk.write(orig + '.remap', ('[remap]\n\npath="%s"\n' % target).encode())
    for f in extra: pk.add('res://mods/%s/%s' % (pdir, f), data(f))

# ---------- share look: Exo 2 font + colours matching the logo (share zip only, never your own game) ----------
SHARE_ACCENT = 'ff3d64'                     # the logo's pink-red
MOD_ACCENT = b'#8a6cff'                     # our mods' purple accent, swapped for SHARE_ACCENT in the share build
ACCENT = None                               # set by build() when 'sharelook' is in the profile
SHARE_FONTS = {'Lato/Lato-Regular.ttf': 'Exo2-Medium.ttf', 'Lato/Lato-Bold.ttf': 'Exo2-Bold.ttf', 'Lato/Lato-Light.ttf': 'Exo2-Regular.ttf',
               'Lato/Lato-Black.ttf': 'Exo2-ExtraBold.ttf', 'Lato/Lato-Italic.ttf': 'Exo2-Medium.ttf',
               'Roboto/Regular.ttf': 'Exo2-Regular.ttf', 'Roboto/Medium.ttf': 'Exo2-Medium.ttf'}
UITHEME = 'res://uitheme.tres'
def sharelook(pk, o):
    import colorsys
    for t, f in SHARE_FONTS.items(): pk.write('res://assets/font/' + t, src('sharelook', f))
    hue = colorsys.rgb_to_hsv(*(int(SHARE_ACCENT[i:i + 2], 16) / 255 for i in (0, 2, 4)))[0]
    # outline-only buttons and boxes with white text (like the own theme), but rounded and in the accent colour
    def edge(L):
        r, g, b = colorsys.hsv_to_rgb(hue, 0.62, min(1.0, 0.8 + 0.2 * L))
        return 'Color( %g, %g, %g, 1 )' % (round(r, 6), round(g, 6), round(b, 6))
    theme(pk, 2, mono=False, edge=edge, current=True)
    # every coloured (not grey) theme colour -> the logo's hue, kept easy on the eyes: fills become
    # dark, low-saturation rose (bright crimson input boxes were glaring), outlines carry the accent
    def rec(key, r, g, b, a):
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        if s < 0.12: return None
        if key == 'border_color': s, v, a = 0.7, 0.85, max(a, 0.55)
        elif key == 'bg_color' and s > 0.6 and v > 0.9: s, v = 0.5, 0.42      # selected / pressed
        elif key in ('bg_color', 'color'): s, v = 0.4, 0.3 + 0.26 * v       # rose fills, bright enough not to read as brown
        else: s, v = max(s, 0.45), v
        r, g, b = colorsys.hsv_to_rgb(hue, s, v)
        return 'Color( %g, %g, %g, %g )' % (round(r, 6), round(g, 6), round(b, 6), a)
    def line(l):
        m = re.match(r'(\s*(\w+) = )Color\( ([\d.e-]+), ([\d.e-]+), ([\d.e-]+), ([\d.e-]+) \)\s*$', l)
        if not m: return l
        c = rec(m.group(2), *(float(x) for x in m.groups()[2:]))
        return m.group(1) + c if c else l
    t = pk.read(UITHEME).decode('utf-8')
    pk.write(UITHEME, chr(10).join(line(l) for l in t.split(chr(10))).encode('utf-8'))
    print('share look: Exo 2 font, colours -> #' + SHARE_ACCENT)

# ---------- startup intro (node injected into init.tscn) ----------
INIT = 'res://scenes/init.tscn'
def intro(pk):
    t = (pk.bak.get(INIT) or pk.read(INIT)).decode('utf-8')
    for f in ('Intro.gd', 'intro.mp3'): pk.add('res://mods/intro/' + f, src('intro', f))
    end = t.index('\n', t.rfind('[ext_resource')) + 1
    t = t[:end] + '[ext_resource path="res://mods/intro/Intro.gd" type="Script" id=90]\n' + t[end:]
    pk.write(INIT, (t.rstrip('\n') + '\n\n[node name="Intro" type="CanvasLayer" parent="."]\nscript = ExtResource( 90 )\n').encode('utf-8'))

# ---------- profile + rebuild ----------
ORDER = ['font', 'theme', 'results', 'bigsettings', 'lang', 'border', 'sharelook', 'fixes', 'stars', 'replay', 'osuskin', 'browser', 'hype', 'discord', 'autodelete', 'intro']
def load_profile(): return json.load(open(PROFILE, encoding='utf-8')) if os.path.exists(PROFILE) else {}
def save_profile(p): json.dump({k: p[k] for k in ORDER if k in p}, open(PROFILE, 'w', encoding='utf-8'), indent=2)
def path_arg(p): return p if os.path.isabs(p) else os.path.join(HERE, p)
def apply(pk, name, o):
    if name == 'font': font(pk, path_arg(o['file']), o.get('target', 'hud'))
    elif name == 'theme': theme(pk, o.get('width', 2))
    elif name == 'results': results(pk)
    elif name == 'bigsettings': bigsettings(pk, o.get('scale', 1.2), o.get('friendly', True), o.get('hints', False))
    elif name == 'lang': lang(pk)
    elif name == 'border': border(pk, path_arg(o['image']) if o.get('image') else None, o.get('opacity'))
    elif name == 'intro': intro(pk)
    elif name == 'sharelook': sharelook(pk, o)
    else: script_mod(pk, name, o)
def game_running():
    import subprocess
    r = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq SoundSpacePlus.exe', '/NH'], capture_output=True, text=True)
    return 'SoundSpacePlus.exe' in r.stdout
THEMED = True
def build(profile):
    global THEMED, ACCENT
    THEMED = 'theme' in profile
    ACCENT = SHARE_ACCENT if 'sharelook' in profile else None
    pk = Pck(PCK)
    for p, d in pk.bak.items(): pk.new[p] = d                       # start from the original game files
    for p in [p for p in pk.by if p.startswith('res://mods/')]: pk.drop(p)
    for name in ORDER:
        if name in profile: apply(pk, name, profile[name])
    return pk
def rebuild(profile, out=None):
    if not out and game_running(): sys.exit('close the game first (SoundSpacePlus.exe is running) - nothing was changed')
    pk = build(profile)
    if out:                                                         # build to another file (verification)
        pk.fn = out; pk.save(bak=False); return
    os.makedirs(os.path.dirname(BACKUP), exist_ok=True); shutil.copyfile(PCK, BACKUP)
    pk.save(); print('game file rebuilt:', ', '.join(n for n in ORDER if n in profile) or 'no mods (original game)')

# ---------- full shareable patch: every installed mod except EXCLUDE, shipped as finished game files ----------
TWEAKS_EXCLUDE = ['theme', 'osuskin', 'font', 'border']  # personal look (theme / font / border art) + someone else's osu! skin files
# one zip, one installer folder per variant: (folder, mods left out)
VARIANTS = [('With-Browser', ()), ('No-Browser', ('browser',))]
def package_tweaks(out, variants=VARIANTS):
    top = os.path.splitext(os.path.basename(out))[0] + '/'
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        if len(variants) > 1: z.writestr(top + 'READ ME FIRST.txt', src('share', 'README_first.txt').replace(b'@@VERSION@@', version().encode()))
        for folder, without in variants:
            root = top + (folder + '/' if len(variants) > 1 else '')
            prof = {k: v for k, v in load_profile().items() if k not in TWEAKS_EXCLUDE and k not in without}
            prof['sharelook'] = {}                                    # friends get the logo-coloured look + Exo 2
            pk = build(prof); rows = []
            for p in sorted(pk.new):
                data = pk.new[p]; added = p.startswith('res://mods/') and p not in pk.bak
                if not added and data == pk.bak.get(p): continue          # unchanged vs stock
                zp = 'files/' + p[len('res://'):]
                z.writestr(root + zp, data)
                rows.append("    @('%s', '%s', '%s')" % (zp, p, '' if added else pk.by[p][3].hex()))
            ps = src('share', 'patcher_tweaks.ps1').decode('utf-8').replace('@@FILES@@', ',\n'.join(rows))
            z.writestr(root + 'patcher.ps1', ps)
            for f in ('Install.bat', 'Uninstall.bat'): z.writestr(root + f, src('share', f))
            z.writestr(root + 'Exo2-font-license.txt', src('sharelook', 'OFL.txt'))
            z.writestr(root + 'Flaticon-license.txt', src('replay', 'icons', 'Flaticon-license.txt'))
            readme = _readme_without(src('share', 'README_tweaks.txt'), without)
            z.writestr(root + 'README.txt', readme.replace(b'@@VERSION@@', version().encode()).replace(b'@@FOLDER@@', root[:-1].replace('/', '\\').encode()))
            print('  %s: %d game files (%s)' % (folder, len(rows), ', '.join(n for n in ORDER if n in prof)))
    print('%s written' % out)

# drop the "WHAT YOU GET" sections of mods left out (section line = 2-space indent + name)
README_SECTION = {'browser': 'Browse', 'replay': 'Replays', 'intro': 'Startup', 'lang': 'Language', 'discord': 'Discord'}
def _readme_without(data, without):
    drop = {README_SECTION[m] for m in without if m in README_SECTION}; out = []; skip = False
    for line in data.decode('utf-8').splitlines(True):
        if line.startswith('  ') and line[2:3] != ' ': skip = line.split()[0] in drop
        elif not line.startswith('  '): skip = False
        if not skip: out.append(line)
    return ''.join(out).encode('utf-8')

# ---------- shareable patch (PowerShell, no Python needed) ----------
SHARE = ['replay', 'stars']
# ready-to-play folder: the original exe + DLLs + a pck with the share build (map browser included) baked in
PORTABLE_FILES = ['SoundSpacePlus.exe', 'discord-game-sdk-godot.dll', 'discord_game_sdk.dll',
                  'libgodot_openvr.dll', 'libnativedialogs.dll', 'openvr_api.dll']
def portable(out):
    prof = {k: v for k, v in load_profile().items() if k not in TWEAKS_EXCLUDE}
    prof['sharelook'] = {}
    pk = build(prof)
    tmp = out + '.pck.tmp'; pk.fn = tmp; pk.save(bak=False)
    root = os.path.splitext(os.path.basename(out))[0] + '/'
    try:
        with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
            for f in PORTABLE_FILES: z.write(os.path.join(GAME, f), root + f)
            z.write(tmp, root + 'SoundSpacePlus.pck')
            v = version().encode()
            z.writestr(root + 'README.txt', src('share', 'README_portable.txt').replace(b'@@VERSION@@', v))
            mods = src('share', 'README_tweaks.txt')
            mods = mods[mods.index(b'WHAT YOU GET'):]                 # (no install / uninstall steps)
            z.writestr(root + 'README-mods.txt', b'RHYTHIA-REIMAGINED v' + v + bytes([13, 10, 13, 10]) + mods)
            z.writestr(root + 'LICENSE_SoundSpacePlus.txt', src('share', 'LICENSE_SoundSpacePlus.txt'))
            z.writestr(root + 'Exo2-font-license.txt', src('sharelook', 'OFL.txt'))
            z.writestr(root + 'Flaticon-license.txt', src('replay', 'icons', 'Flaticon-license.txt'))
    finally:
        if os.path.exists(tmp): os.remove(tmp)
    print('%s written (%s)' % (out, ', '.join(n for n in ORDER if n in prof)))

# Rhythia Legacy Android (com.rhythialegacy.net, same Godot 3.6.2 build): the APK keeps the game
# files loose under assets/, so the mods are written straight in. Windows-only mods are left out.
# The result is UNSIGNED - sign it (zipalign + apksigner, e.g. uber-apk-signer) before installing.
APK_SKIP = ['discord', 'autodelete']   # Discord DLL / PowerShell recycle bin (the browser unzips .rhm itself)
def apk(src_apk, out):
    prof = {k: v for k, v in load_profile().items() if k not in TWEAKS_EXCLUDE and k not in APK_SKIP}
    prof['sharelook'] = {}
    pk = build(prof)
    files = {}
    for p in pk.by:
        if p not in pk.new: continue
        if p in pk.bak and pk.new[p] == pk.bak[p]: continue               # untouched game file
        files['assets/' + p[len('res://'):]] = pk.new[p]
    zin = zipfile.ZipFile(src_apk)
    with zipfile.ZipFile(out, 'w') as zo:
        for i in zin.infolist():
            if i.filename.startswith('META-INF/') or i.filename in files: continue   # old signature / replaced
            zo.writestr(i, zin.read(i.filename), compress_type=i.compress_type)
        for f, d in sorted(files.items()):
            zo.writestr(zipfile.ZipInfo(f, (2026, 1, 1, 0, 0, 0)), d, compress_type=zipfile.ZIP_DEFLATED)
    print('%s written (unsigned): %d game files (%s)' % (out, len(files), ', '.join(n for n in ORDER if n in prof)))
    _sign_apk(out)

# sign with tools/rr-release.jks (keep it: Android only installs updates signed with the same key)
def _sign_apk(unsigned):
    import glob, subprocess
    t = os.path.join(HERE, 'tools'); jar = os.path.join(t, 'uber-apk-signer.jar'); ks = os.path.join(t, 'rr-release.jks')
    java = (glob.glob(os.path.join(os.environ.get('ProgramFiles', 'C:/Program Files'), 'Eclipse Adoptium', 'jre-*', 'bin', 'java.exe')) or [shutil.which('java')])[0]
    if not (java and os.path.exists(jar) and os.path.exists(ks)): return print('not signed (needs Java + tools/uber-apk-signer.jar + tools/rr-release.jks)')
    pw = open(os.path.join(t, 'rr-release.pass')).read().strip(); tmp = unsigned + '.signdir'
    subprocess.run([java, '-jar', jar, '-a', unsigned, '-o', tmp, '--ks', ks, '--ksAlias', 'rhythiareimagined',
                    '--ksPass', pw, '--ksKeyPass', pw], check=True, capture_output=True)
    signed = [f for f in os.listdir(tmp) if f.endswith('.apk')][0]
    final = unsigned.replace('-unsigned.apk', '.apk')
    os.replace(os.path.join(tmp, signed), final); shutil.rmtree(tmp); os.remove(unsigned)
    print('signed:', final)

def package(out):
    pk = Pck(PCK); swap, new = [], []
    for name in SHARE:
        pdir, sw, extra = SCRIPT_MODS[name]
        for f, orig in sw.items():
            swap.append("    '%s/%s' = @('%s', '%s')" % (pdir, f, orig, pk.by[orig[:-3] + '.gdc'][3].hex()))
        new += ["'%s/%s'" % (pdir, f) for f in extra]
    ps = src('share', 'patcher.ps1').decode('utf-8').replace('@@SWAP@@', '\n'.join(swap)).replace('@@NEW@@', ', '.join(new))
    ps = ps.replace('@@MODDIRS@@', ', '.join("'res://mods/%s/'" % SCRIPT_MODS[n][0] for n in SHARE))
    root = os.path.splitext(os.path.basename(out))[0] + '/'
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr(root + 'patcher.ps1', ps)
        for f in ('Install.bat', 'Uninstall.bat', 'README.txt'): z.writestr(root + f, src('share', f).replace(b'@@VERSION@@', version().encode()))
        z.writestr(root + 'Flaticon-license.txt', src('replay', 'icons', 'Flaticon-license.txt'))
        for name in SHARE:
            pdir, sw, extra = SCRIPT_MODS[name]
            for f in list(sw) + extra: z.writestr(root + 'files/%s/%s' % (pdir, f), src(name, f).replace(MOD_ACCENT, b'#' + SHARE_ACCENT.encode()))
    print('share patch written:', out)

# ---------- main ----------
if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest='cmd', required=True)
    for n in ('replay', 'osuskin', 'stars', 'browser', 'fixes', 'autodelete', 'intro', 'results', 'lang'): sp.add_parser(n).add_argument('--undo', action='store_true')
    b = sp.add_parser('border'); b.add_argument('image'); b.add_argument('--opacity', type=float)
    sp.add_parser('opacity').add_argument('value', type=float)
    f = sp.add_parser('font'); f.add_argument('file'); f.add_argument('--target', default='hud'); f.add_argument('--undo', action='store_true')
    t = sp.add_parser('theme'); t.add_argument('--width', type=int, default=2); t.add_argument('--undo', action='store_true')
    b2 = sp.add_parser('bigsettings'); b2.add_argument('--scale', type=float, default=1.2); b2.add_argument('--plain', action='store_true')
    b2.add_argument('--hints', action='store_true'); b2.add_argument('--undo', action='store_true')
    dc = sp.add_parser('discord'); dc.add_argument('--app-id', type=int); dc.add_argument('--image', default='glitchia')
    dc.add_argument('--text', default='Glitchia'); dc.add_argument('--undo', action='store_true')
    tw = sp.add_parser('tweaks'); tw.add_argument('--out')
    tw.add_argument('--without', default='', help='comma list of mods to leave out, e.g. browser')
    pkg = sp.add_parser('package'); pkg.add_argument('--out')
    pt = sp.add_parser('portable'); pt.add_argument('--out')
    ak = sp.add_parser('apk'); ak.add_argument('apk'); ak.add_argument('--out')
    sp.add_parser('version').add_argument('value', nargs='?')
    for n in ('status', 'rebuild', 'restore'): sp.add_parser(n)
    a = ap.parse_args(); prof = load_profile()
    if a.cmd == 'status':
        for n in ORDER: print(('  [x] ' if n in prof else '  [ ] ') + n + ('  ' + json.dumps(prof[n]) if prof.get(n) else ''))
        sys.exit()
    if a.cmd == 'version':
        if a.value:
            assert re.fullmatch(r'\d+\.\d+\.\d+', a.value), 'version must look like 0.1.2'
            open(VERSION_FILE, 'w').write(a.value + '\n')
        print('Rhythia-reimagined v' + version()); sys.exit()
    if a.cmd == 'apk': apk(a.apk, a.out or os.path.join(os.path.dirname(GAME), 'Rhythia-reimagined-android-v%s-unsigned.apk' % version())); sys.exit()
    if a.cmd == 'portable': portable(a.out or os.path.join(os.path.dirname(GAME), 'Rhythia-reimagined-portable-v%s.zip' % version())); sys.exit()
    if a.cmd == 'package': package(a.out or os.path.join(os.path.dirname(GAME), 'Rhythia-reimagined-lite-v%s.zip' % version())); sys.exit()
    if a.cmd == 'tweaks':
        wo = [m for m in a.without.split(',') if m]               # --without = a single-variant zip
        name = 'Rhythia-reimagined-v%s' % version() + ''.join('_No' + m.capitalize() for m in wo) + '.zip'
        package_tweaks(a.out or os.path.join(os.path.dirname(GAME), name), [('', tuple(wo))] if wo else VARIANTS); sys.exit()
    if a.cmd == 'restore': prof = {}
    elif getattr(a, 'undo', False): prof.pop(a.cmd, None)
    elif a.cmd == 'border': prof['border'] = {'image': os.path.abspath(a.image), 'opacity': a.opacity if a.opacity is not None else prof.get('border', {}).get('opacity')}
    elif a.cmd == 'opacity': prof.setdefault('border', {})['opacity'] = a.value
    elif a.cmd == 'font': prof['font'] = {'file': os.path.abspath(a.file), 'target': a.target}
    elif a.cmd == 'discord':
        o = prof.get('discord', {}); app = a.app_id or o.get('app_id')
        if not app: sys.exit('discord needs --app-id <your Discord application ID> (see src/discord/README.txt)')
        prof['discord'] = {'app_id': app, 'image': a.image, 'text': a.text}
    elif a.cmd == 'theme': prof['theme'] = {'width': a.width}
    elif a.cmd == 'bigsettings': prof['bigsettings'] = {'scale': a.scale, 'friendly': not a.plain, 'hints': a.hints}
    elif a.cmd != 'rebuild': prof[a.cmd] = {}
    rebuild(prof); save_profile(prof)
