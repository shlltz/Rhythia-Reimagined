extends Reference
# Map editor audio analysis (Rhythia-reimagined): BPM + first-beat offset estimates and onset
# (beat / transient) markers from the editor's audio capture (EditorCapture.gd: per bin of song
# time, the peak of a low band (kick / bass), a high band (snares / hats) and the whole signal, in
# dB scaled 0..1; a bin's time is its centre). From those:
#   novelty  = how much the bands rose since the bin before (rises are where sounds start),
#   onsets   = novelty peaks above a running local threshold, at least MIN_GAP apart,
#   tempo    = 1) autocorrelation of the smoothed novelty over a minute of the song: every BPM
#              50..320 scores its beat length and multiples (a real beat repeats) plus its half
#              (music in 2 / 4 has something between beats; a 3-eighths period has not), times a
#              soft prior around 140 BPM - this gets within a few % (or an octave);
#              2) refined on the onsets of the whole song: the BPM within +-5 % whose beats (and half
#              / quarter beats) the onsets line up with best (a comb, in steps fine enough that the
#              beats can't drift a quarter beat over the song between two steps);
#   offset   = the beat phase (1 ms steps) whose beats land on the most low-band-weighted novelty.
#   no beat  = the novelty's autocorrelation at the beat is under MIN_PERIODIC of its energy (noise
#              and free-tempo audio stay near 0.05; drums are far above, a dense mix ~0.1).
# It is an estimate to start from: songs with a free tempo, few drums or a tempo change can come out
# at half / double speed or off; the editor shows the alternatives and lets you nudge both values.
# Pure functions: arrays in, numbers out (tests feed them synthetic beats).

const MIN_GAP = 60.0            # ms between two onsets at least
const WIN_MS = 250.0            # running threshold: mean novelty this far either side
const MAX_ONSETS = 400          # strongest onsets the comb uses (keeps long songs fast)
const MIN_PERIODIC = 0.075
const PRIOR_BPM = 140.0

# per-bin novelty from the three envelopes (all 0..1, same length); w = weights of the rises
static func novelty(lo:PoolRealArray, hi:PoolRealArray, pk:PoolRealArray, w:Array = [1.0, 0.8, 0.5]) -> PoolRealArray:
	var n = min(lo.size(), min(hi.size(), pk.size()))
	var out = PoolRealArray()
	out.resize(n)
	if n == 0: return out
	out[0] = 0.0
	for i in range(1, n):
		out[i] = w[0] * max(0.0, lo[i] - lo[i - 1]) + w[1] * max(0.0, hi[i] - hi[i - 1]) + w[2] * max(0.0, pk[i] - pk[i - 1])
	var mx = 0.0
	for v in out: mx = max(mx, v)
	if mx > 0:
		for i in n: out[i] = out[i] / mx
	return out

# triangular smoothing about `ms` wide (a beat smeared over a bin or two still correlates with itself)
static func smooth(nov:PoolRealArray, bin_ms:float, ms:float = 30.0) -> PoolRealArray:
	var h = max(1, int(round(ms / bin_ms / 2.0)))
	var n = nov.size()
	var out = PoolRealArray()
	out.resize(n)
	var ks = float((h + 1) * (h + 1))
	for i in n:
		var s = 0.0
		for j in range(-h, h + 1):
			if i + j >= 0 and i + j < n: s += (h + 1 - abs(j)) * nov[i + j]
		out[i] = s / ks
	return out

# onset peaks: [times ms (sub-bin by parabola), strengths (height over the local mean)]
static func peaks(nov:PoolRealArray, bin_ms:float) -> Array:
	var ts = PoolRealArray()
	var ss = PoolRealArray()
	var n = nov.size()
	if n < 3: return [ts, ss]
	var pre = PoolRealArray() # running mean via prefix sums
	pre.resize(n + 1)
	pre[0] = 0.0
	for i in n: pre[i + 1] = pre[i] + nov[i]
	var win = int(WIN_MS / bin_ms)
	for i in range(1, n - 1):
		var v = nov[i]
		if v <= nov[i - 1] or v < nov[i + 1]: continue
		var a = max(0, i - win)
		var b = min(n, i + win + 1)
		var mean = (pre[b] - pre[a]) / float(b - a)
		if v < mean * 1.2 + 0.02: continue
		var den = nov[i - 1] - 2.0 * v + nov[i + 1]
		var off = 0.5 * (nov[i - 1] - nov[i + 1]) / den if abs(den) > 1e-6 else 0.0
		var t = (i + clamp(off, -0.5, 0.5) + 0.5) * bin_ms
		var s = v - mean
		var k = ts.size()
		if k > 0 and t - ts[k - 1] < MIN_GAP:
			if s > ss[k - 1]:
				ts[k - 1] = t
				ss[k - 1] = s
			continue
		ts.append(t)
		ss.append(s)
	return [ts, ss]

static func onsets(nov:PoolRealArray, bin_ms:float) -> Array:
	return Array(peaks(nov, bin_ms)[0])

# the strongest `count` onsets, still in time order
static func strongest(p:Array, count:int) -> Array:
	var ts = p[0]
	var ss = p[1]
	if ts.size() <= count: return p
	var srt = Array(ss)
	srt.sort()
	var th = srt[srt.size() - count]
	var t2 = PoolRealArray()
	var s2 = PoolRealArray()
	for i in ts.size():
		if ss[i] >= th and t2.size() < count:
			t2.append(ts[i])
			s2.append(ss[i])
	return [t2, s2]

# coarse BPM from the autocorrelation of the smoothed novelty (a minute from the middle, 20 ms bins)
static func coarse(sm:PoolRealArray, bin_ms:float) -> float:
	var k = max(1, int(round(20.0 / bin_ms)))
	var d = bin_ms * k
	var dec = PoolRealArray()
	var i = 0
	while i + k <= sm.size():
		var s = 0.0
		for j in k: s += sm[i + j]
		dec.append(s)
		i += k
	var m = int(60000.0 / d)
	var s0 = 0
	var n = dec.size()
	if n > m:
		s0 = (n - m) / 2
		n = m
	if n < 40: return 0.0
	var mean = 0.0
	for j in n: mean += dec[s0 + j]
	mean /= n
	var c = PoolRealArray()
	c.resize(n)
	for j in n: c[j] = dec[s0 + j] - mean
	var ml = int(min(n - 2, 4.0 * 1200.0 / d + 2))
	var r = PoolRealArray()
	r.resize(ml + 2)
	for l in ml + 2:
		var s = 0.0
		for j in range(0, n - l): s += c[j] * c[j + l]
		r[l] = s
	var best = 0.0
	var best_s = -1e20
	var b = 50.0
	while b <= 320.0:
		var lag = 60000.0 / b / d
		var s = 0.5 * _interp(r, lag / 2.0)
		for h in [1, 2, 3, 4]: s += _interp(r, lag * h) / h
		var pr = log(b / PRIOR_BPM) / log(2.0) / 0.9
		s *= exp(-0.5 * pr * pr)
		if s > best_s:
			best_s = s
			best = b
		b += 0.25
	return best if best_s > 0 else 0.0

static func _interp(a:PoolRealArray, x:float) -> float:
	var i = int(floor(x))
	if i < 0 or i + 1 >= a.size(): return 0.0
	var f = x - i
	return a[i] * (1.0 - f) + a[i + 1] * f

# autocorrelation of the novelty at one beat, over its energy (0 = no repetition at that period)
static func periodicity(sm:PoolRealArray, bin_ms:float, bpm:float) -> float:
	var n = sm.size()
	if n < 4 or bpm <= 0: return 0.0
	var mean = 0.0
	for v in sm: mean += v
	mean /= n
	var r0 = 0.0
	for v in sm: r0 += (v - mean) * (v - mean)
	if r0 <= 0: return 0.0
	var lag = int(60000.0 / bpm / bin_ms)
	var best = -1e20
	for l in [lag, lag + 1]:
		if l >= n: continue
		var s = 0.0
		for i in range(0, n - l): s += (sm[i] - mean) * (sm[i + l] - mean)
		best = max(best, s)
	return best / r0

# how well onsets line up with a beat of `bpm` and its divisions ks = [[division, weight], ...]
static func comb(ts:PoolRealArray, ss:PoolRealArray, bpm:float, ks:Array) -> float:
	var per = 60000.0 / bpm
	var tot = 0.0
	for s in ss: tot += s
	if tot <= 0: return 0.0
	var out = 0.0
	for kw in ks:
		var zr = 0.0
		var zi = 0.0
		var f = kw[0] / per
		for i in ts.size():
			var a = TAU * fposmod(ts[i] * f, 1.0)
			zr += ss[i] * cos(a)
			zi += ss[i] * sin(a)
		out += kw[1] * sqrt(zr * zr + zi * zi) / tot
	return out

const K_COARSE = [[1, 1.0], [2, 0.7]]
const K_FINE = [[1, 1.0], [2, 0.7], [4, 0.5]]
# best BPM within +-5 % of b0 by the comb: [bpm, score]
static func refine(p:Array, b0:float) -> Array:
	var ts = p[0]
	var ss = p[1]
	if ts.size() < 2 or b0 <= 0: return [b0, 0.0]
	var dur = max(1000.0, ts[ts.size() - 1] - ts[0])
	var width = b0 * (60000.0 / b0) / (4.0 * dur) # (BPM error that drifts a quarter beat over the song)
	var st = clamp(width / 3.0, 0.005, 0.25)
	var best = b0
	var best_s = -1.0
	var b = b0 * 0.95
	while b <= b0 * 1.05:
		var s = comb(ts, ss, b, K_COARSE)
		if s > best_s:
			best_s = s
			best = b
		b += st
	var b1 = best
	best_s = -1.0
	b = b1 - st
	while b <= b1 + st + 0.00001:
		var s = comb(ts, ss, b, K_FINE)
		if s > best_s:
			best_s = s
			best = b
		b += st / 10.0
	return [best, best_s]

# novelty at a time (linear between bin centres)
static func at(nov:PoolRealArray, t:float, bin_ms:float) -> float:
	var f = t / bin_ms - 0.5
	var i = int(floor(f))
	if i < 0 or i + 1 >= nov.size(): return 0.0
	var k = f - i
	return nov[i] * (1.0 - k) + nov[i + 1] * k

# [offset ms (first beat at or after 0), confidence = best phase score / mean phase score]
static func phase(nov:PoolRealArray, bin_ms:float, bpm:float) -> Array:
	if bpm <= 0 or nov.size() < 4: return [0, 0.0]
	var period = 60000.0 / bpm
	var span = nov.size() * bin_ms
	var best = -1.0
	var best_off = 0.0
	var total = 0.0
	var count = 0
	var off = 0.0
	while off < period:
		var s = 0.0
		var t = off
		while t < span:
			s += at(nov, t, bin_ms)
			t += period
		if s > best:
			best = s
			best_off = off
		total += s
		count += 1
		off += 1.0
	var mean = total / max(1, count)
	return [int(round(best_off)), best / mean if mean > 0 else 0.0]

# everything the editor shows: {bpm, offset, confidence, periodicity, candidates: [[bpm, offset,
# conf], ...] (best first, then double / half), onsets: [ms]}
static func analyse(lo:PoolRealArray, hi:PoolRealArray, pk:PoolRealArray, bin_ms:float) -> Dictionary:
	var nov = novelty(lo, hi, pk)
	var pks = peaks(nov, bin_ms)
	var out = {"bpm": 0.0, "offset": 0, "confidence": 0.0, "periodicity": 0.0, "candidates": [], "onsets": Array(pks[0])}
	if pks[0].size() < 8: return out
	var sm = smooth(nov, bin_ms)
	var b0 = coarse(sm, bin_ms)
	if b0 <= 0: return out
	var bpm = refine(strongest(pks, MAX_ONSETS), b0)[0]
	out.periodicity = stepify(periodicity(sm, bin_ms, bpm), 0.001)
	if out.periodicity < MIN_PERIODIC: return out
	var nph = novelty(lo, hi, pk, [1.0, 0.3, 0.3]) # (the beat is where the kicks are)
	for b in [bpm, bpm * 2.0, bpm / 2.0]:
		if b < 50 or b > 400: continue
		var ph = phase(nph, bin_ms, b)
		out.candidates.append([stepify(b, 0.01), ph[0], stepify(ph[1], 0.01)])
	var main = out.candidates[0]
	out.bpm = main[0]
	out.offset = main[1]
	out.confidence = main[2]
	return out
