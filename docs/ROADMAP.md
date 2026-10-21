# Major update roadmap (v0.13 line)

Status of the big feature request, kept honest: `[x]` done and tested, `[~]` partly done (what is
missing is written next to it), `[ ]` not started, `[!]` blocked (reason given).

## Audit summary

| area | what exists | where |
|---|---|---|
| engine | Godot **3.6.2** (GDScript), stock Sound Space Plus nightly; the mod pack patches the game's `.pck` (text `.gd` under `res://mods/<mod>/`, stock `.gdc` remapped) | `ssp_mod.py`, `src/` |
| map format | `.sspm` v1/v2 read + v2 write (stock `Song.gd`, our fixes copy) | `src/fixes/Song.gd` |
| `.phxm` | import (zip + unpacked folder), browser downloads, drag-and-drop | `src/fixes/Phxm.gd` |
| editor | 3x3 field, timeline, waveform (muted 4x capture), BPM grid + snapping, tap BPM, undo/redo commands, clipboard, save as `.sspm`, test play | `src/replay/Editor.gd`, `EditorModel.gd` |
| replays | stock `.sspre` v4: settings header, then a stream of cursor (ms, x, y) / hit (note id) / miss (note id) / pause / give-up records; viewer with pause, seek (re-simulation), speed, frame step | `src/replay/Replay.gd`, `ReplayViewer.gd`, `ReplayBrowser.gd` |
| skins | stock: `user://cursor`, `trail`, `touch` images, `user://hit`, `miss`, `fail`, `new_best`, `menu` sounds, `user://meshes/*.obj`, `user://colorsets/*.txt`, settings (mesh, colorset, cursor colour / scale / spin / trail, note size / opacity / spin, hit / miss effects); ours: Customize panel (trail, HUD layout, skin image slots), colorset maker, osu! sounds (own build) | stock `Rhythia.gd`, `src/replay/Reimagined*.gd`, `ColorsetMaker.gd` |
| difficulty | star rating (rhythia.com formula), BPM estimate, worker-thread cache | `src/stars/StarRating.gd`, `StarCache.gd` |
| history | every finished run: time, score, accuracy, misses, combo, passed, pauses, speed | `src/stars/RecentPlays.gd` (`user://recent_plays.json`) |
| library | collections, search syntax, sorts, map browser | `Reimagined.gd`, `v3MapList.gd`, `src/browser` |
| mobile | Android APK (same files as PC), touch speed pad, touch scroll | `ssp_mod.py apk`, `SpeedPad.gd`, `TouchScroll.gd` |
| tests | real game instances with isolated user data | `tests/multiplayer/mpbench.py` + drivers |

External code:

- **Rhythia rewrite** (`Rhythia/Client`, C#, Godot 4, AGPL-3.0). Only file formats are taken
  from it (formats are interoperability facts). Its `.phxm` writer
  (`MapParser.cs ExportEncode`) writes the version (12), the notes, then **11 empty sections**
  (timing points, brightness, contrast, saturation, blur, fov, tint, position, rotation,
  ar factor, text). Its reader reads the notes only.
- **Sound Space Quantum Editor** (`Avibah/Sound-Space-Quantum-Editor`, C#, AGPL-3.0). Used as a
  workflow reference only: no code is copied, because this pack is MIT. Its `.phxm` export also
  writes the 11 sections empty. Its reader has per-object layouts for brightness through text,
  but none for timing points.
- **Godot 4 / "Godot project"**: the game already is a Godot 3.6.2 project
  (`Rhythia/sound-space-plus`, branch `nightly`). See [GODOT.md](GODOT.md).

## Dependency map

```
Phxm.gd (zip read) ──> .phxm export (zip write + CRC32) ──> round-trip tests
        └─────────────> Rewrite library importer (thread, preview, duplicates) ─┐
StarRating ──> live star preview (editor)                                       │
RecentPlays + StarCache ──> smart playlists ──┐                                 │
note hash (Song notes) ──> duplicate finder ──┴─> Library tools panel <─────────┘
Replay.gd parser (offline) ──> Replay Studio (timeline, stats, heatmap) ──> compare ──> clip export
NoteManager ──> retry from the failure moment
Editor waveform capture ──> onset envelope ──> BPM / offset estimate ──> beat markers
EditorModel ──> pattern tools (streams, jumps, spirals, mirror, repeat, transforms)
Rhythia skin settings + user:// asset slots ──> skin profiles ──> skin editor + preview
GitHub releases + signed manifest ──> updater (download, verify, back up, swap, roll back)
```

## Phases and checklist

### Phase 1: foundation
- [x] audit (this file)
- [x] branch `major` off `perf`
- [ ] contributor docs (CONTRIBUTING, architecture, testing, release), issue / PR templates
- [ ] CI: Python checks of the mod tool + pure GDScript unit tests in headless Godot 3.6.2
- [ ] baseline performance numbers (PerfBench) recorded

### Phase 2: core features
- [x] `.phxm` export (zip writer, CRC-32 from the native gzip trailer, the rewrite's metadata keys and note rule); map page "..." menu on both menus
- [x] `.phxm` effect sections: counted where a layout is known, kept byte for byte (`user://rr_phxm_extra`), reported as not playable; rating / artist link / platform / mapper list / artist-title split kept too
- [x] `.phxm` round-trip tests: PhxmTest.gd (59 checks, own + share), phxm_check.py (Python zip reader + rewrite-style decode); a real rewrite map round-trips byte-identical (objects, audio, cover, metadata)
- [x] Rewrite library importer (Library > Import from rewrite): finds the rewrite's user folder (incl. its moved-folder pointer), scans maps/<set>/*.phxm + cache/maps/<id>/ (merged), installed / possible duplicate / new, converts on a worker (frames < 10 ms while importing; one ~65 ms list refresh at the end), report of skipped / failed
- [x] live star rating in the editor (worker, 0.4 s debounce, skipped when the notes didn't change; same numbers as the map list; + average / peak nps)
- [x] retry from the failure moment: exact checkpoints (gaps longer than the hit window), "From fail point" on the failed results, state restored; resumed runs are marked, record no replay, can't set a PB. Chaos mod: later notes sit elsewhere (its generator only advances for played notes)
- [x] duplicate finder: exact = note fingerprint (works across editors), possible = same title + length within 2 s; also files the library hides (same id inside); recycle by path after a confirmation
- [x] tags (+ `tag=` search) + bulk rename of the name stored in the map (templates, preview, renumbering on collisions, journal with file copies, undo byte-identical). Files are not renamed: their name is the map id that scores / replays / collections use
- [x] smart playlists (rules: stars, played / unplayed, failed in N days, added in N days, favourites, untagged, tag, sort, limit) in the map list's collection filter
- [x] library statistics + cleanup preview (caches / leftovers only, to the recycle bin after a confirmation)
- [x] skin profiles + skin editor (Customize > Skin > Skin editor): notes (shape incl. own .obj, colour set or own colours, size, opacity, spin, note image), cursor (image, size, colour mode, spin, game / osu! trail, trail + touch images), effects (hit / miss effect, show, at cursor, miss flash), sounds (hit / miss mp3 / ogg, on / off, play), HUD (font, miss / score text colours); live preview from the game's own materials / meshes / effect scenes; save / duplicate / rename / delete (recycle bin) / reset group / revert; .rrskin import (validated in a temp folder) / export; the setup before skins kept as a profile; applied through a menu reload (the stock settings controls write their values back otherwise); survives restarts. Not skinnable here: HUD layout / grid / border / icons (already in Customize), WAV sounds (the game's loader can't read WAV files)

### Phase 3: editor
- [x] BPM / offset estimate, beat markers, preview grid, USE (AUTO tab). The song is captured sample-exact (EditorCapture.gd: AudioEffectCapture on a muted 4x bus; the old per-frame peak meter was ~70 ms of song per value). Click tracks through the real capture: exact tempo, offset within 1 ms; synthetic envelopes within 5 ms; noise: no tempo claimed. Real test song: 150.08 BPM (its notes: 150 / 300), notes 11 ms from the estimated grid (EditorToolsTest.gd, own + share)
- [x] snap override: hold Alt = no time snap
- [x] pattern tools (EditorPatterns.gd: stream paths, jumps, circle, spiral, rotate / scale / reverse, mirror section, repeat rotating, slots 1-9), one undo step each; undo / redo now select what they put back (EditorToolsTest.gd)
- [x] Quantum Editor parity (docs/EDITOR.md, checked against its own default keybinds): grid keys QWE/ASD/ZXC + numpad, Shift+H / Shift+V flips, Ctrl+Q free positions, Ctrl+T / Ctrl+B, timing points (BPM changes; Ctrl+Shift+B), Bezier curve through the selection (Shift+D). Not done, with reasons, listed there (EditorParityTest.gd 29/29 own + share)

### Phase 4: Replay Studio
- [ ] offline replay parser + per-note timing / judgement timeline
- [ ] accuracy / combo / score graphs, miss markers, cursor heatmap, speed graph
- [ ] jump to event, playback controls (existing viewer)
- [ ] side-by-side comparison (best vs latest)
- [ ] clip export (GIF built in; video through ffmpeg when it is installed)

### Phase 5: platform and distribution
- [ ] mobile: touch targets, gyro / drag cursor modes (where the device has a gyroscope), performance profile
- [!] Android device testing: no device or emulator here
- [ ] auto-update: signed manifest on GitHub releases, verify, back up, swap with a helper after exit, roll back
- [ ] packaging + release validation
