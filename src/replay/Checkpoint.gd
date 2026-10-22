extends Node
# Retry from the failure point (Rhythia-reimagined). An instance ("RRCheckpoint", added by Game.gd
# to live single-player runs) takes snapshots of the run state - score, combo, combo level and
# progress, hits, misses, judged notes, health, max combo - but only at EXACT points: in a gap
# between two notes longer than the hit window, once the note before it is judged. A note can only
# be judged inside [its time, its time + hit window] (NoteManager), so at such a point every earlier
# note is final and no later one has been touched.
#
# On a fail, the last snapshot at least REWIND_MS of map time before the fail is offered on the
# results screen. Retrying from it starts the map at the snapshot's next note through the game's own
# Start From (Rhythia.start_offset: notes before it aren't spawned, the music is seeked by the game,
# with its usual lead-in) and Game.gd puts the snapshot's state back before the first note, so the
# score / combo / health go on from exactly where they were. Not the same as the full run: it is
# marked RESUMED, can't set a personal best (the game itself refuses PBs with a start offset too)
# and records no replay (a replay can't start mid-map). The Chaos mod's random offsets come from a
# generator that only advances for played notes, so with Chaos the later notes sit elsewhere.

const REWIND_MS = 2000.0          # map time between the resume point and the fail
const MIN_GAP_MS = 250.0          # snapshots at most this often (map time)
const KEEP = 4000

var game:Node
var spawn:Node
var snaps:Array = []
var ck_i:int = 0                  # first spawned note after the clock
var last_at:float = -1e9

func _ready():
	name = "RRCheckpoint"
	game = get_parent()
	spawn = game.get_node_or_null("Spawn")
	if game.has_meta("rr_resumed"): # (a resumed run can always go back to where it started)
		var o = game.get_meta("rr_resumed")
		snaps.append(o.snap)
		last_at = o.snap.at

func _process(_d):
	if !spawn or !spawn.get("notes") or game.ending: return
	var notes = spawn.notes
	var ms = spawn.ms
	while ck_i < notes.size() and notes[ck_i][1] <= ms: ck_i += 1
	if ck_i == 0 or ck_i >= notes.size(): return
	var prev = notes[ck_i - 1]
	var hw = spawn.hit_window
	# (prev judged and its window over; the next note not reachable yet)
	if prev[2] == Globals.NSTATE_ACTIVE or ms <= prev[1] + hw: return
	var at = float(notes[ck_i][1])
	if at - last_at < MIN_GAP_MS: return
	last_at = at
	snaps.append(snapshot(at))
	if snaps.size() > KEEP: snaps.pop_front()

func snapshot(at:float) -> Dictionary:
	return {"at": at, "score": game.score, "combo": game.combo, "combo_level": game.combo_level,
		"lvl_progress": game.lvl_progress, "hits": game.hits, "misses": game.misses, "total": game.total_notes,
		"energy": game.energy, "max_combo": game.max_combo}

# the snapshot to resume from for a fail at fail_ms, or null (failed before the first checkpoint)
func pick(fail_ms:float):
	var best = null
	for s in snaps:
		if s.at <= fail_ms - REWIND_MS: best = s
	return best

# ------------------------------------------------------------------ static side (results screen, Game.gd)
# Game.end on a fail: what the results screen can offer
static func offer_for(game:Node, fail_ms:float):
	var ck = game.get_node_or_null("RRCheckpoint")
	if !ck: return null
	var s = ck.pick(fail_ms)
	if s == null: return null
	var prev = Engine.get_meta("rr_resume_prev_offset") if Engine.has_meta("rr_resume_prev_offset") else Rhythia.start_offset # (a resumed run failing again: still the player's own value)
	return {"song": Rhythia.selected_song.id, "snap": s, "fail_ms": fail_ms, "prev_offset": prev}

# results screen "Retry from fail point"
static func start(offer:Dictionary):
	if !Engine.has_meta("rr_resume_prev_offset"): Engine.set_meta("rr_resume_prev_offset", offer.get("prev_offset", Rhythia.start_offset))
	Engine.set_meta("rr_resume", offer)
	Rhythia.start_offset = offer.snap.at

# Game._ready: puts the snapshot's state back (true when this run is a resumed one)
static func apply(game:Node) -> bool:
	if !Engine.has_meta("rr_resume"): return false
	var o = Engine.get_meta("rr_resume")
	Engine.remove_meta("rr_resume")
	if !Rhythia.selected_song or o.song != Rhythia.selected_song.id: return false
	var s = o.snap
	game.score = int(s.score)
	game.combo = int(s.combo)
	game.combo_level = int(s.combo_level)
	game.lvl_progress = int(s.lvl_progress)
	game.hits = float(s.hits)
	game.misses = float(s.misses)
	game.total_notes = float(s.total)
	game.energy = clamp(float(s.energy), 0.0, game.max_energy)
	game.max_combo = int(s.max_combo)
	game.set_meta("rr_resumed", o)
	Engine.set_meta("rr_resumed_run", true) # (results / EndInfo: no personal best)
	game.update_hud()
	return true

# a resumed run restarted mid-run (pause menu Retry, hold-` quick retry: they reload song.tscn):
# the restart resumes from the same snapshot again
func _exit_tree():
	if game and game.has_meta("rr_resumed") and !game.ending: Engine.set_meta("rr_resume", game.get_meta("rr_resumed"))

# back in the menu after a resumed run: the player's own Start From value again
static func restore_offset():
	if Engine.has_meta("rr_resume_prev_offset"):
		Rhythia.start_offset = Engine.get_meta("rr_resume_prev_offset")
		Engine.remove_meta("rr_resume_prev_offset")
