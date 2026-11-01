# Performance baseline

Measured with `tests/multiplayer/PerfBench.gd` (own build, v2.0 work on branch `major`,
2026-10-21). Machine: Intel i7-13650HX, GLES3, 144 Hz display, vsync off, uncapped fps.
Map: the 36 s test map (345 notes, ~10 notes/s, peak 30/s), autoplay.

```bash
py -3 tests/multiplayer/mpbench.py own "B=PerfBench.gd" 300 "B=<dense map>|<big map>"
```

An instance name starting with `diag` runs gameplay only. `RR_PERF_PROFILE=low` applies the
Customize > Device low-end profile first; `RR_PERF_SET="rh:key=value;rr:key=value"` sets single
settings (`rh` = the game's, `rr` = Reimagined's).

| Measure | Result |
|---|---|
| Engine start to menu ready | 3.1 s |
| Idle menu frame | p50 0.63 ms, p99 1.25 ms |
| Switching maps every 100 ms | p50 1.58 ms, p99 3.0 ms, worst 9.2 ms |
| Load (songload to notes moving) | 2.1 s |
| Play: frame time | p50 0.6 ms, p95 0.8-0.9 ms, p99 1.0-1.2 ms (1500-1620 fps) |
| Play: frames with a hit | 0.9 ms mean (vs 0.66 ms without) |
| Play: draw calls | 18 (p50) |
| Audio position vs game clock | p50 33 ms, p99 48 ms, no re-seeks |
| Memory over 3 play / quit cycles | objects 6997, 6999, 7001; nodes 2833 each time |

## How to read these

- **A minimized window is paced by Windows** to the display refresh: every frame then
  takes ~7 ms (144.9 fps) whatever the settings. PerfBench now reports `minimized_frames`;
  a run with any minimized frames doesn't measure the game. Several early runs here were like
  that and looked like a big slowdown.
- **Low-end profile:** with the window visible it is within run-to-run noise on this PC
  (1589 and 1685 fps vs 1624 and 1624 fps default; p95 0.74-0.78 vs 0.77-0.84 ms). On a
  fast desktop it neither helps nor hurts. Its effect on slow phones is **untested**: there
  is no Android device or emulator here.
- **Render scale 0.75** made play about 4 % slower here (an extra scaled rendering pass), so
  the profile leaves it alone. On a weak phone GPU it may well help; that's untested.
- The audio vs clock figure is the game's own playback-position reading, which moves in mix
  blocks. It's a baseline to compare against, not a measured offset.

## v2.6.0 optimization pass (2026-10-23)

Same machine, own build, uncapped fps. Probes: `ScreenProbe.gd` (per screen), `DrawProbe.gd`
(draw calls per canvas item), `ListProbe.gd` (map list), `SpikeProbe.gd` (slow frames),
`SwitchProbe.gd` (map switching).

| Measure | Before | After |
|---|---|---|
| Title menu: 2D draw calls / frame | 550, 1.41 ms (p99 2.50) | 99, 1.13 ms (p99 1.39) |
| Map page: 2D draw calls / frame | 806, 1.75 ms | 474, 0.72 ms |
| 10+ star map page | 945, 1.97 ms | 551, 0.89 ms |
| PerfBench idle menu, 102 maps (p50) | 2.00 ms | 0.58-0.62 ms |
| PerfBench map switching (p50 / p99) | 1.87 / 4.24 ms | 0.82 / 3.76 ms |
| Map list rebuild with 2,181 online maps | 64 ms | 20 ms |
| prepare_songs (same library) | 22 ms | 10 ms |
| Worst menu frame as the online maps arrive | 142-147 ms | 51-54 ms |
| Gameplay (p50 / p99) | 0.64 / 1.18 ms | 0.63 / 1.17 ms (unchanged) |

- The spectrum bars (90 around the title logo, 80 around the map cover) were antialiased
  `draw_line`s, which Godot 3 doesn't batch: about five draw calls each. They're now one triangle
  array with a 1px soft edge (`Ring.bars`).
- The map list sorted with GDScript comparators on every rebuild, and `prepare_songs` checked
  each map with `Array.find` (O(n²)). Sorting is now one native sort of ranked integer keys
  (checked against every comparator and flip setting in `ListProbe.gd`), and a set replaces `find`.
- Checked and left alone: per-script frame cost in the menus (no script above noise), map
  switching across the 618-map library (0.6 ms mean in `select_song`, 1 of 120 switches over
  16.7 ms), boot (menu at ~1.7 s; the rest of PerfBench's "startup" is the boot animation),
  memory over repeated runs (stable; one orphan node per run, not identifiable in a release
  build), threads (every one joined). The end-of-map freeze (PassFx) reads the last frame back from
  the GPU (~35 ms); the picture is frozen at that moment by design.

## v2.7.0: Rewrite-inspired pass (2026-11-01)

Public build (`share`), same machine, 1280x720 windowed, vsync off, uncapped. Settings: a saved copy
of a player's own settings (`RR_USER_SETTINGS=<folder>`: approach 37.5, spawn distance 14, smart
cursor trail, classic HUD, hit effects on) and their 360 KB play history. Maps: a 34 notes/s,
75 s map (2,561 notes, 19 stars) and a 17-star map. Before = branch `release` (v2.6.0) built into a
separate worktree with the same test files; before and after alternated, two runs each.

| Measure | Before | After |
|---|---|---|
| Gameplay: average fps | 1,167 / 1,145 | 1,619 / 1,625 (final build: 1,643) |
| Gameplay: 1% low (slowest 1% of frames) | 629 / 636 fps | 846 / 842 fps (final: 858) |
| Gameplay: frame p50 / p99 | 0.82-0.84 / 1.39-1.41 ms | 0.59 / 1.04 ms (final: 0.58 / 1.01) |
| Gameplay: slowest frame of a whole run (`SpikeProbe.gd`, incl. the end of the map) | 46.0 ms (the pass zoom's screen read-back) | 10.3 ms |
| Gameplay: frames with a hit / without (mean) | 1.19 / 0.85 ms | 0.81-0.82 / 0.61 ms |
| Title screen | 1,385 / 1,419 fps | 1,512 / 1,574 fps (final: 1,624) |
| Map page, 19-star map (hype effects) | 690 / 701 fps | 707 / 729 fps (final: 723) |
| Map pick with the 360 KB play history (20 maps) | 14.4 ms inside `select_song`, 11 of 20 picks with a frame over 16.7 ms | 1.4 ms, 1 of 20 (the first pick reads the history once) |
| Slowest frame from the last notes through the pass zoom | 49.1 ms | 17.6 ms |
| Memory over 3 play / quit cycles | objects 7,733, nodes 3,126, 9 orphans | the same (7,760 / 3,139 / 9: the FPS counter and the new HUD hooks) |

How the time was found (all in `tests/multiplayer`):

- `AblateProbe.gd` switches one part of a run off at a time (HUD, HUD viewports only, notes, trail,
  cursor, grid, FPS counter, NoteManager's processing) between control windows.
- `ProfProbe.gd` + `swaps/prof.py` (`RR_SWAPS=`): test-only patches that time every gameplay
  script's `_process` and NoteManager's sections per frame. Start here for script cost.
- `MenuAblate.gd` hides menu items one at a time (`RR_MENU_ROOT=Menu/Main/Maps` to drill down).
- `SwitchProbe.gd` (map picks), `PassZoomTest.gd` (end of a passed map), `SpikeProbe.gd`.
- `HudVpTest.gd` checks the HUD panels never show stale content (below), `FpsCounterTest.gd` the
  counter.

What the Rewrite does (Rhythia/Client @9200e16) and what came of it here:

- **Event-driven HUD** (its panels update labels on `AttemptStatsUpdated`, animations in
  `_PhysicsProcess`). Here: a hit's HUD refresh only touches what changed, and the timer recolours
  on a state change, rebuilds its text once a second and moves its bar in visible steps (34 → 8 us
  a frame). The HUD's 2D viewports now render only on frames where something in them redrew, moved,
  resized or was shown / hidden (signals), when code changes a shader parameter or modulate
  (`HUD.vp_mark`), when a panel comes into view, and at least twice a second; the shining SS grade,
  the pause / give-up meters and the cursor-dance panel keep rendering every frame while shown.
  Hiding the whole HUD saved 0.15 ms a frame before and 0.006 ms after. `HudVpTest.gd` pauses the
  game at random moments, grabs each panel, forces a render and compares: 96 checks per HUD style
  (classic and rewrite) in the densest part of the map, 0 stale.
- **No render-thread round trips on hot paths.** Not a Rewrite technique as such: with the
  multi-threaded renderer, a `VisualServer` read waits for the render thread. The HUD read the
  letter grade's shader parameter back on every hit: 223 us of a 442 us hit (now 64 us). The pass
  zoom read the screen back from the GPU (49 ms); it now draws the paused screen through a
  screen-reading shader, compiled while the loading card is up (this build compiles shaders
  synchronously: the first try put a 116 ms compile on the pass instead).
- **Notes as one MultiMesh** (`NoteRenderer.cs`): Nightly already did this. The per-note loop now
  works out the per-frame values once (MultiMesh references, approach speed and its sign) and does
  its fade step inline.
- **Discord off the frame loop** (the Rewrite's RPC client runs on its own thread): the SDK's
  callbacks are pumped 60 times a second instead of every frame (10 → 5 us a frame).
- **Data read once, looked up per map** (the Rewrite keeps plays in a database): the play history
  is parsed once and again only when the file changes (modified time + size), not on every map
  pick and every finished run.
- **Spectrum** (`AudioSpectrum.cs` samples every frame, in C#): the menu strip now samples and
  redraws at most 240 times a second (title screen +10%).
- **Map list virtualisation** (`MapList.cs` pools buttons): Nightly's list already builds only the
  page on screen.

Measured and left out:

- Batching settings (`item_reordering_lookahead` 8/16, `max_join_item_commands` 32/64): the same
  2D draw calls on every screen (201 map list, ~300-320 map pages, 634 editor) and no frame-time change.
- The map page is ~0.9 ms of a 1.4 ms frame (19-star map) spread over dozens of items (song panel
  0.49, map cards 0.05-0.15 each, filters 0.12, the hype effects 0.06): ~300 2D draw calls with
  no single culprit. Cutting it means rebuilding the page, not tuning it.
- Vsync in menus (the Rewrite's default): Nightly saves the vsync and fps-cap settings from the
  live engine state, so switching them per screen would overwrite the player's saved values.
- A MultiMesh cursor trail (`TrailRenderer.cs`): the trail is off by default; with a short trail
  its cost is script work per piece (~4 us), not draw calls. It would also mean replacing the
  stock compiled `Cursor.gd`.
- C# and the Godot 4 renderer: the engine stays Godot 3.6.2 (GDScript, GLES3).
- Physics at 60 Hz: some HUD animations step per physics tick (they would run at half speed).

The FPS counter (`replay/FpsCounter.gd`, a root CanvasLayer) has no per-frame script: a Timer
reads `Engine.get_frames_drawn()` four times a second. Counter on vs off: within run-to-run noise
on every screen.
