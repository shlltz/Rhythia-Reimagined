"""Reference check for src/replay/RewriteAuto.gd: a straight Python port of the rewrite's
AutoplayHandler.cs (Rhythia/Client), run on the notes AutoProbe.gd dumped, compared with the cursor
positions the game sampled.  py -3 tests/autoplay_ref.py <dir with auto_notes.txt + auto_samples.txt>"""
import math, sys, os

HB = 0.5 + 0.07
BOUNDS = 3.0 / 2 - 0.2625 / 2


def chk(n, c, size):
    return max(abs(n[0] - c[0]), abs(n[1] - c[1])) < size


def cr(p0, p1, p2, p3, u, t0, t1, t2, t3):
    a, ten = 0.4, -1.0
    t01 = max(abs(t0 - t1), 1) ** a
    t12 = max(abs(t1 - t2), 1) ** a
    t23 = max(abs(t2 - t3), 1) ** a
    m1 = (1 - ten) * (p2 - p1 + t12 * ((p1 - p0) / t01 - (p2 - p0) / (t01 + t12)))
    m2 = (1 - ten) * (p2 - p1 + t12 * ((p3 - p2) / t23 - (p3 - p1) / (t12 + t23)))
    u2 = u * u
    return (2 * (p1 - p2) + m1 + m2) * u2 * u + (-3 * (p1 - p2) - m1 - m1 - m2) * u2 + m1 * u + p1


def spline(n0, n1, n2, n3, t):
    d = n2[2] - n1[2]
    if d <= 0 or (n1[0], n1[1]) == (n2[0], n2[1]):
        return (n1[0], n1[1])
    u = min(max((t - n1[2]) / d, 0), 1)
    return (cr(n0[0], n1[0], n2[0], n3[0], u, n0[2], n1[2], n2[2], n3[2]),
            cr(n0[1], n1[1], n2[1], n3[1], u, n0[2], n1[2], n2[2], n3[2]))


def clampb(p):
    return (min(max(p[0], -BOUNDS), BOUNDS), min(max(p[1], -BOUNDS), BOUNDS))


def from_notes(a, t):
    j = 0
    while j + 1 < len(a) and a[j + 1][2] <= t:
        j += 1
    L = len(a) - 1
    return clampb(spline(a[max(j - 1, 0)], a[j], a[min(j + 1, L)], a[min(j + 2, L)], t))


def norm(v):
    l = math.hypot(*v)
    return (v[0] / l, v[1] / l) if l > 0 else (0.0, 0.0)


def build(notes):
    notes = sorted(notes, key=lambda n: n[2])
    merged, i = [], 0
    while i < len(notes):
        f = notes[i]; i += 1
        x, y, c = f[0], f[1], 1
        while i < len(notes) and notes[i][2] == f[2]:
            x += notes[i][0]; y += notes[i][1]; c += 1; i += 1
        merged.append((x / c, y / c, f[2]))
    notes = merged
    pre, i = [], 0
    while i < len(notes):
        note = notes[i]; i += 1
        col = [note]
        while i < len(notes) and abs(notes[i][2] - note[2]) <= 5 and chk(note, notes[i], HB * 0.9):
            col.append(notes[i]); i += 1
        ax = sum(c[0] for c in col) / len(col)
        ay = sum(c[1] for c in col) / len(col)
        if pre:
            pv = pre[-1]
            te = abs(pv[2] - note[2]) / 1000.0
            if te > 0:
                sp = math.hypot(ax - pv[0], ay - pv[1]) / (te * 100)
                k = 0.8 + (1 / (1 + math.exp(-sp * 5)) - 0.5) * 2 * 0.2
                ax *= k; ay *= k
            if i > 2 and len(pre) >= 2:
                d1 = norm((pv[0] - pre[-2][0], pv[1] - pre[-2][1]))
                d2 = norm((ax - pv[0], ay - pv[1]))
                k = 1 + max(-(d1[0] * d2[0] + d1[1] * d2[1]) - 0.5, 0) * (1 / (te * 20 + 1))
                ax *= k; ay *= k
        nn = (ax, ay, note[2])
        pn = notes[max(i - 2, 0)]
        if len(col) == 1 and note[0] == pn[0] and note[1] == pn[1] and pre:
            nn = (pre[-1][0], pre[-1][1], note[2])
        pre.append(nn)
    sec = [n for k, n in enumerate(pre)
           if not (0 < k < len(pre) - 1 and pre[k - 1][:2] == n[:2] and pre[k + 1][:2] == n[:2])]
    out, lim, m = [], HB * 0.25, len(sec)
    for i in range(m - 1):
        n0, n1, n2, n3, n4 = sec[max(i - 2, 0)], sec[max(i - 1, 0)], sec[i], sec[i + 1], sec[min(i + 2, m - 1)]
        if n1[:2] == n2[:2] or n2[:2] == n3[:2]:
            out.append(n2); continue
        p = spline(n0, n1, n3, n4, n2[2])
        sx, sy = p[0] - n2[0], p[1] - n2[1]
        if sx == 0 or sy == 0:
            sx, sy = min(max(sx, -lim), lim), min(max(sy, -lim), lim)
        else:
            k = min(max(sx, -lim), lim) / sx; sx *= k; sy *= k
            k = min(max(sy, -lim), lim) / sy; sx *= k; sy *= k
        sh = (n2[0] + sx, n2[1] + sy, n2[2])
        val = out[-3:] + [sh] + sec[i + 1:i + 4]
        lo, hi = val[min(2, len(val) - 1)][2], val[max(0, len(val) - 3)][2]
        ok = True
        for note in notes:
            if note[2] < lo: continue
            if note[2] > hi: break
            if not (chk(note, from_notes(val, note[2] + 1), HB * 0.9) or chk(note, from_notes(val, note[2] + 5), HB * 0.9)):
                ok = False; break
        out.append(sh if ok else n2)
    out.append(pre[-1])
    return out


def main(d):
    notes = [tuple(float(v) for v in l.split()) for l in open(os.path.join(d, 'auto_notes.txt'))]
    notes = [(x - 1, y - 1, t) for x, y, t in notes]
    data = build(notes)
    worst = 0.0
    for l in open(os.path.join(d, 'auto_samples.txt')):
        t, x, y = (float(v) for v in l.split())
        p = from_notes(data, t)
        worst = max(worst, abs(p[0] + 1 - x), abs(p[1] + 1 - y))
    ok = worst < 0.01
    print(('PASS' if ok else 'FAIL') + '  matches an independent port of the rewrite autoplay (worst difference %.5f units)' % worst)
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
