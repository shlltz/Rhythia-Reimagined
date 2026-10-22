# Contributing

Rhythia-reimagined is a set of mods for Rhythia Legacy (Sound Space Plus nightly, Godot 3.6.2).
They're patched into the game's `.pck` by `ssp_mod.py`; there is no Godot project to open.

## Set up

1. Install Python 3 and a Sound Space Plus nightly 3.6.2 build. Back up its folder first.
2. Clone this repo into a folder inside the game folder: the tool expects `..\SoundSpacePlus.pck`.
3. `copy profile.example.json profile.json`: this lists which mods get built in.
4. Add the two files the repo can't redistribute (see README: the Flaticon UIcons font, an intro
   sound). Without them the build still works, minus the icon font and the intro sound.
5. Close the game, then `py -3 ssp_mod.py rebuild`. The original pck is kept in `backup/`;
   `py -3 ssp_mod.py restore` brings it back.

## Where things are

- `ssp_mod.py`: the mod tool (build, package, sign updates). `docs/ARCHITECTURE.md` explains how it patches the game.
- `src/<mod>/`: each mod's scripts. Most features live in `src/replay/`.
- `tests/unit/`: pure script tests, no game needed (CI runs these).
- `tests/multiplayer/`: tests that run the real game (`docs/TESTING.md`).
- `relay/`: the multiplayer relay service (Python, standard library) + its tests and deployment files.
- `docs/`: `EDITOR.md`, `UPDATES.md`, `RELAY.md`, `PERF.md`, `GODOT.md`, `RELEASE.md`, `ROADMAP.md`.

## Rules for changes

- **Godot 3.6.2 GDScript only.** Check the 3.x docs, not 4.x (`yield`, `PoolByteArray`, `File`, `rect_size`).
- **Never touch the player's user data without asking.** Tests run with `APPDATA` pointed at
  `tests/multiplayer/t/<instance>/appdata`; keep it that way. Delete to the recycle bin, never for good.
- **Don't fake results.** A feature isn't done until a test shows it working on the `own` and
  `share` builds; say what couldn't be tested (e.g. no Android device).
- **Keep what the game can't do honest in the UI.** If something is estimated or partial, the
  label says so.
- **Match the code around you:** short comments that explain why, no new dependencies, no
  networking or file writes outside the mod's own `user://rr_*` files unless that's the feature.
- Engine traps that cost hours before: `Array.sort()` on an Array of Arrays crashes the engine (use
  `sort_custom`); calling a method on `null` in a release build crashes instead of erroring;
  `PoolByteArray.subarray(a, b)` includes `b`; `Thread.is_active()` stays true until
  `wait_to_finish()`; `OS.execute` quotes arguments itself.

## Pull requests

Fill in the template: what changed, how it was tested, and confirm no files from your own install
or user folder are included. Run `py -3 tests/unit/run.py <godot 3.6.2 binary>` before you push.
