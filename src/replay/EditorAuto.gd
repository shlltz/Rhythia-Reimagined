extends Reference
# Map editor audio analysis (Rhythia-reimagined): BPM + first-beat offset estimates and onset
# (beat / transient) markers from the editor's own audio capture. The game can't decode mp3 / ogg
# to samples from a script, so the editor plays the song muted at 4x through a bus with a peak meter
# and a spectrum analyser (Editor._wave_*) and keeps, per 25 ms of song time, the peak level and the
# energy in a low (kick / bass) and a high (hats / snares) band. From those:
#   novelty = how much the bands rose since the bin before (rises are where sounds start),
#   onsets  = novelty peaks above a running local threshold, at least MIN_GAP apart,
#   tempo   = the map list's own BPM estimator (StarCache.estimate_bpm) over the onset times,
#   offset  = the beat phase whose beats land on the most novelty (1 ms steps).
# It is an estimate to start from: songs with a free tempo, few drums or a tempo change can come out
# at half / double speed or off; the editor shows the alternatives and lets you nudge both values.
# Pure functions: arrays in, numbers out (tests feed them synthetic beats).

const MIN_GAP = 60.0            # ms between two onsets at least
const WIN = 10                  # bins either side for the running threshold

# per-bin novelty from the three envelopes (all 0..1, same length)
static func novelty(lo:PoolRealArray, hi:PoolRealArray, pk:PoolRealArray) -> PoolRealArray:
	var n = min(lo.size(), min(hi.size(), pk.size()))
	var out = PoolRealArray()
	out.resize(n)
	if n == 0: return out
	out[0] = 0.0
	for i in range(1, n):
		var v = 1.0 * max(0.0, lo[i] - lo[i - 1]) + 0.8 * max(0.0, hi[i] - hi[i - 1]) + 0.5 * max(0.0, pk[i] - pk[i - 1])
		out[i] = v
	var mx = 0.0
	for v in out: mx = max(mx, v)
	if mx > 0:
		for i in n: out[i] = out[i] / mx
	return out

# onset times (ms, sub-bin by parabola through the peak and its neighbours)
static func onsets(nov:PoolRealArray, bin_ms:float) -> Array:
	var out = []
	var n = nov.size()
	if n < 3: return out
	# running mean via prefix sums
	var pre = PoolRealArray()
	pre.resize(n + 1)
	pre[0] = 0.0
	for i in n: pre[i + 1] = pre[i] + nov[i]
	var last = -1e9
	for i in range(1, n - 1):
		var v = nov[i]
		if v <= nov[i - 1] or v < nov[i + 1]: continue
		var a = max(0, i - WIN)
		var b = min(n, i + WIN + 1)
		var mean = (pre[b] - pre[a]) / float(b - a)
		if v < mean * 1.5 + 0.04: continue
		var den = nov[i - 1] - 2.0 * v + nov[i + 1]
		var off = 0.5 * (nov[i - 1] - nov[i + 1]) / den if abs(den) > 1e-6 else 0.0
		var t = (i + clamp(off, -0.5, 0.5)) * bin_ms + bin_ms * 0.5
		if t - last < MIN_GAP: continue
		out.append(t)
		last = t
	return out

# Tempo from the novelty curve. 1) autocorrelation r(L) of the curve for lags up to 4 beats of 60 BPM;
# 2) every BPM 50..320 (0.25 steps) scores r at its beat length and its multiples (weights 1, 1/2, 1/3,
# 1/4: a real beat repeats, a half beat only half of the time), times a soft prior around 140 BPM;
# 3) the best one is refined by folding: the curve is folded onto one beat for each BPM within ±2 of
# it (0.02 steps) and the sharpest fold wins (a wrong period smears the beats over the whole fold).
# Returns [bpm, sharpness] ([0, 0] = no steady beat).
const PRIOR_BPM = 140.0
static func tempo(nov:PoolRealArray, bin_ms:float) -> Array:
	var n = nov.size()
	if n < 80: return [0.0, 0.0]
	var mean = 0.0
	for v in nov: mean += v
	mean /= n
	var c = PoolRealArray() # (mean removed: a flat curve correlates with nothing)
	c.resize(n)
	for i in n: c[i] = nov[i] - mean
	var max_lag = int(min(n - 1, ceil(4.0 * 1200.0 / bin_ms)) + 1)
	var r = PoolRealArray()
	r.resize(max_lag + 2)
	for l in range(0, max_lag + 2):
		var s = 0.0
		if l < n:
			for i in range(0, n - l): s += c[i] * c[i + l]
		r[l] = s
	if r[0] <= 0: return [0.0, 0.0]
	var best = 0.0
	var best_s = -1e20
	var b = 50.0
	while b <= 320.0:
		var lag = 60000.0 / b / bin_ms
		var s = 0.0
		for k in [1, 2, 3, 4]:
			s += _interp(r, lag * k) / k
		var pr = log(b / PRIOR_BPM) / log(2.0) / 0.9
		s *= exp(-0.5 * pr * pr)
		if s > best_s:
			best_s = s
			best = b
		b += 0.25
	if best_s <= 0: return [0.0, 0.0]
	var fine = refine(nov, bin_ms, best, 2.0, 0.02)
	return fine

static func _interp(a:PoolRealArray, x:float) -> float:
	var i = int(floor(x))
	if i < 0 or i + 1 >= a.size(): return 0.0
	var k = x - i
	return a[i] * (1.0 - k) + a[i + 1] * k

# epoch folding around bpm: [best bpm, sharpness of its fold = peak / mean]
static func refine(nov:PoolRealArray, bin_ms:float, bpm:float, span:float, step:float) -> Array:
	var best = bpm
	var best_q = -1.0
	var b = bpm - span
	while b <= bpm + span + 0.0001:
		var q = fold(nov, bin_ms, b)[1]
		if q > best_q:
			best_q = q
			best = b
		b += step
	return [stepify(best, 0.01), best_q]

const FOLD_BINS = 64
# the curve folded onto one beat: [phase of the peak (ms), peak / mean]
static func fold(nov:PoolRealArray, bin_ms:float, bpm:float) -> Array:
	var per = 60000.0 / bpm
	var h = PoolRealArray()
	h.resize(FOLD_BINS)
	for i in FOLD_BINS: h[i] = 0.0
	for i in nov.size():
		var t = i * bin_ms + bin_ms * 0.5
		var f = fposmod(t, per) / per * FOLD_BINS
		var j = int(f)
		var k = f - j
		h[j % FOLD_BINS] += nov[i] * (1.0 - k)
		h[(j + 1) % FOLD_BINS] += nov[i] * k
	var mx = 0.0
	var at = 0
	var tot = 0.0
	for i in FOLD_BINS:
		# (3-bin smoothing: a beat smeared over a bin or two still counts as one peak)
		var v = h[i] + 0.5 * (h[(i + FOLD_BINS - 1) % FOLD_BINS] + h[(i + 1) % FOLD_BINS])
		tot += h[i]
		if v > mx:
			mx = v
			at = i
	var mean = tot / FOLD_BINS
	return [at * per / FOLD_BINS, mx / (2.0 * mean) if mean > 0 else 0.0]

# novelty at a time (linear between bins)
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

# everything the editor shows: {bpm, offset, confidence, candidates: [[bpm, offset, conf], ...],
# onsets: [ms], range: [low, high]}
static func analyse(lo:PoolRealArray, hi:PoolRealArray, pk:PoolRealArray, bin_ms:float) -> Dictionary:
	var nov = novelty(lo, hi, pk)
	var ons = onsets(nov, bin_ms)
	var tp = tempo(nov, bin_ms)
	var out = {"bpm": 0.0, "offset": 0, "confidence": 0.0, "candidates": [], "onsets": ons}
	if tp[0] <= 0 or tp[1] < 1.25: return out # (a fold no sharper than 1.25x its mean: no steady beat)
	for b in [tp[0], tp[0] * 2.0, tp[0] / 2.0]:
		if b < 50 or b > 400: continue
		var ph = phase(nov, bin_ms, b)
		out.candidates.append([stepify(b, 0.01), ph[0], stepify(ph[1], 0.01)])
	var main = out.candidates[0]
	out.bpm = main[0]
	out.offset = main[1]
	out.confidence = main[2]
	return out
