# Testing

Two kinds of tests. Neither touches your real user folder or your installed game file.

## Unit tests (no game needed)

```bash
py -3 tests/unit/run.py path/to/godot-3.6.2
```

`run.py` copies the pure scripts into `tests/unit/mods/replay/` with the build stamps, then runs
`UnitRunner.gd` with `-s`. It covers the editor model, patterns, audio tempo / offset, the GIF writer
(decoded by a decoder in the test) and the updater's signature checks. CI (`.github/workflows/checks.yml`)
runs it with the official Godot 3.6.2 headless build. Locally, a copy of the game's own
`SoundSpacePlus.exe` works too, as long as no `.pck` sits next to the copy.

## Relay tests (no game needed)

```bash
py -3 relay/test_relay.py
```

Real sockets on 127.0.0.1 against the relay in `relay/rr_relay.py`: forwarding, refusals, limits,
expiry, malformed frames, 100 rooms at once, TLS. CI runs it.

## Game tests (tests/multiplayer)

```bash
py -3 tests/multiplayer/mpbench.py own|share "NAME=Driver.gd" [seconds] ["NAME=map.sspm|map2.sspm"]
```

`mpbench.py` builds the game (`own` = your profile, `share` = the public build) once per
instance into `t/<NAME>/`, sets `APPDATA` to `t/<NAME>/appdata`, and starts your game exe on that
pck. It copies the maps into the instance's library and replaces `@@MAP1@@`, `@@OUT@@` and `@@S@@`
in the driver. Results land in `t/<NAME>/*.txt`, plus screenshots and `godot.log`.
`RR_KEEP=1` keeps an instance's data for the next run.

Every feature test should pass on both `own` and `share`. The newer drivers:

| Driver | What it checks |
|---|---|
| `EditorInteractionTest.gd` | real mouse / key input: placing, hover, selection (click, Ctrl, Shift, box), grid and track drags, scrub, seek bar, wheel, clipboard, undo / redo chains, moves across notes, Esc and text-box focus, save / reload, missing audio, audio sync, a 20k-note map, five window sizes, a test play |
| `EditorToolsTest.gd` | audio capture + BPM / offset (click tracks through the real capture, a real song against its notes), patterns, slots, undo selection |
| `EditorParityTest.gd` | grid keys, flips, Ctrl+Q / T / B, timing points, Bezier curves |
| `EditorStarTest.gd` | live star rating in the editor |
| `ReplayStudioTest.gd` | a real recorded run analysed offline (score / combo / misses equal the game's, aim + delay reconstruction), Studio UI, compare, watch from, GIF + MP4 clip |
| `GifTest.gd` | GIF writer decoded by ffmpeg |
| `DeviceTest.gd` | low-end profile + restore, gyroscope cursor (fed through a test hook), touch-sized buttons |
| `UpdaterTest.gd` | updates against a local server + sandbox: refusals, install, confirm, rollback; a real openssl-signed manifest |
| `relay_e2e.py` (`MPRelayA/B/C.gd`, `MPRelayTls.gd`) | online lobbies (multiplayer is shelved: `src/shelved/multiplayer/README.md`) |
| `MapScreensTest.gd` | title cards, map page backdrop, start zoom, loading screen (muffle, logo, no black), results card, no-cover look |
| `CheckpointTest.gd` | retry from the fail point |
| `LibraryTest.gd`, `PhxmTest.gd`, `SkinTest.gd` | library tools, `.phxm`, skins |
| `PerfBench.gd` | performance (`docs/PERF.md`) |

The older multiplayer drivers are listed in `tests/multiplayer/README.md`.

## Things that trip tests up

- **A minimized test window isn't drawn.** Screenshots then show an old frame and
  `frame_post_draw` never fires; PerfBench frame times become the display's refresh. Take
  screenshots after `yield(VisualServer, "frame_post_draw")` and check `OS.window_minimized`.
- **Stock log lines that always appear** don't count as failures: `localization.csv`, "File must
  be opened", the particle `SHADER ERROR`s for `color_ramp` / `scale_texture`.
- **The game exe is shared** between instances, and between tests and your own game. A test
  must never write next to the exe (see `Updater.target()`).
