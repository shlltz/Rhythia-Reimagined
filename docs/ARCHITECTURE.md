# Architecture

## How the mods get into the game

There is no Godot project. `ssp_mod.py` reads the game's `SoundSpacePlus.pck` (Godot 3 pack: an
84-byte header, an index of paths with offsets and sizes, then the files) and writes a new one.

1. **Start from the original files.** The first build saves the stock files it replaces in
   `originals.bin`. Every build starts from those, so a removed mod leaves nothing behind.
2. **Add mod files** under `res://mods/<dir>/`. `SCRIPT_MODS` in `ssp_mod.py` lists, per mod, the
   stock scripts it replaces and its extra files.
3. **Redirect stock scripts.** A replaced stock script gets a `.gd.remap` pointing at the modded
   copy, which is a full edited copy of the stock script, so the game loads ours instead.
4. **Fill build stamps** in mod sources: `@@VERSION@@`, `@@CHANNEL@@` (own / portable / tweaks /
   android), `@@BUILD_ID@@` (new each build), plus per-mod options from `profile.json` (`@@KEY@@`).
5. Non-script mods (font, theme, border, bigsettings, results, intro, lang, sharelook) edit
   resources (fonts, theme, textures, translations) directly.

`ORDER` fixes the order mods are applied in. Builds:

| Command | What it builds |
|---|---|
| `rebuild` | your own game, from `profile.json` (channel `own`) |
| `tweaks` | a share zip that patches a friend's install (PowerShell, checks stock file hashes) |
| `portable` / `linux` | a ready-to-play folder: stock exe + libraries + our pck (same pck on both) |
| `apk APK` | Android: the mod files written into the APK's `assets/`, signed with `tools/` keys |
| `manifest` | the signed update files for a release (`docs/UPDATES.md`) |

The share builds leave out personal-look mods (`TWEAKS_EXCLUDE`) and use the share look.

## Runtime structure

- **Stock autoloads** the mods lean on: `Rhythia` (settings, selected song, replay state),
  `Globals` (constants, notifications, `p()` for user paths), `SFXManager`, `Online`.
- **Settings of our own** are in `user://reimagined.json` (`Reimagined.gd`: `val`, `set_val`, `DEFAULTS`).
  The game's own settings stay in `settings.json` and go through `Rhythia.save_settings()`.
- **Cross-scene state** uses `Engine` metas, prefixed `rr_`, e.g. `rr_replay_seek` (Studio to
  viewer) and `rr_clip` (clip request). Metas don't touch the game's own objects.
- **Pure modules** (no nodes, testable without the game): `EditorModel`, `EditorPatterns`,
  `EditorAuto`, `GifWriter`, `ReplayStats`, and the static parts of `Updater` and `Device`.
- **Worker threads** for anything slow (library scans, imports, audio analysis, replay analysis,
  GIF / PNG writing). They never touch nodes or `Song` objects; data goes in and results come
  back via `call_deferred`.

## Main features and their files (`src/replay/` unless noted)

| Feature | Files |
|---|---|
| Menu, sidebar, results | `menu2.gd`, `ResultsScreen.gd`, `TitleMenu.gd`, `Look.gd`, `UIAnim.gd` |
| Customize panel | `ReimaginedPanel.gd` (tabs), `Reimagined.gd` (settings) |
| Map editor | `Editor.gd`, `EditorModel.gd`, `EditorCapture.gd`, `EditorAuto.gd`, `EditorPatterns.gd` |
| Replays | `Replay.gd` (format), `ReplayViewer.gd`, `ReplayBrowser.gd`, `ReplayStats.gd`, `ReplayStudio.gd`, `ClipRecorder.gd`, `ClipExport.gd`, `GifWriter.gd` |
| Gameplay hooks | `Game.gd`, `NoteManager.gd`, `HUD.gd`, `Checkpoint.gd` (retry from the fail point) |
| Library | `Library.gd`, `LibraryPanel.gd`, `RewriteImport.gd`; `.phxm` in `src/fixes/Phxm.gd` |
| Skins | `Skins.gd`, `SkinPanel.gd` |
| Device / updates | `Device.gd`, `GyroCursor.gd`, `Updater.gd` |
| Star ratings | `src/stars/` |
| Multiplayer (shelved) | `src/shelved/multiplayer/` (not in builds; how to bring it back is in its README); relay service in `relay/` |

## Files a mod writes in the user folder

`reimagined.json`, `rr_tags.json`, `rr_smart.json`, `rr_library/` (note-hash cache, rename
journal), `rr_phxm_extra/`, `rr_skins/`, `rr_update.json`, `recent_plays.json`,
`star_ratings_v2.json`, `map_bpm_v2.json`, `clips/`, `logs/`, plus the game's own
`replays/`, `maps/` and `settings.json`.
