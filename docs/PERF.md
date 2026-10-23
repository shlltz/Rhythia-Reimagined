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
