# Rhythia-Reimagined

A mod pack for **Rhythia Legacy / Sound Space Plus nightly** (the Godot 3.6.2 build). It patches the game's `SoundSpacePlus.pck` with GDScript mods. You don't need Godot or the game's source code.

> [!WARNING]
> **This project is vibecoded.** Almost all of the code was written by an AI (Claude) from my descriptions, then tested by playing.
> It works on my machine and I've tried to test it, but nobody has reviewed the code line by line. Expect bugs and rough edges.
> Back up `%APPDATA%\SoundSpacePlus` if your maps and scores matter to you, and report problems in [Issues](../../issues).

**Just want to play?** Get a zip from the [Releases](../../releases) page:
- **portable**: unzip it and run `SoundSpacePlus.exe`.
- **patch**: unzip it into your game folder and run `Install.bat`.

## Features

| | |
|---|---|
| **Title menu** | osu!-style main menu with a beating logo and spectrum ring. The background is rain, snow or topographic waves. ESC opens it. |
| **Maps** | Star rating that matches rhythia.com, and an estimated BPM (a range when the tempo changes). Speed mods raise or lower both, with a count-up animation. Sort by stars, name or mapper. Collections (map packs). |
| **Map page** | The cover art works as a visualizer: it hits on the map's own notes and has spectrum bars around it. Maps over 7★ get glowing screen sides. Maps over 10★ make the cover and Start quake, a lightning bolt strikes when you select one, and hovering Start dims everything else. The mods menu wipes up. |
| **Browse** | Search and download maps from rhythia.com inside the game, in a panel that slides up. |
| **Replays** | A replay browser and viewer. You can seek, change speed, pause, step frame by frame and hide the UI. Misses show as red ticks on the timeline. |
| **Customize** (F1) | Cursor trail: the game's own trail, an osu!-style trail, or off, with colour, opacity, length and size. A drag-and-drop HUD layout editor. Skins for the border, grid, trail, logo and sidebar icons. Interface toggles. |
| **Gameplay** | osu!-style pause screen and results screen. A green glow when you pass a map, then a zoom into the results. Adjustable half-ghost fade. |
| **Menu** | Springy buttons, animations, audio visualizer, Alt + mouse wheel volume, and a pause-all-music button. Icons are Flaticon UIcons. |
| **Other** | Vietnamese translation, Discord status, imported map files go to the Recycle Bin, map cache fix, small FPS tweaks. |

## Building it yourself

You need **Python 3** and a Rhythia Legacy / Sound Space Plus nightly install, version 3.6.2.

1. Put this repo in a folder inside the game folder. The tool looks for `..\SoundSpacePlus.pck`.
2. Copy `profile.example.json` to `profile.json`. This file lists which mods get built in.
3. Add the two files this repo can't redistribute:
   - `src/replay/icons/uicons-solid-rounded.woff`: Flaticon UIcons, solid rounded. Get it from npm `@flaticon/flaticon-uicons` (`css/uicons-solid-rounded-*.woff`).
   - `src/intro/intro.mp3`: any short intro sound.
4. Close the game, then run:

```
py -3 ssp_mod.py rebuild     # patch your game (the original is backed up)
py -3 ssp_mod.py restore     # back to the original game
py -3 ssp_mod.py tweaks      # build the share zip (With-Browser / No-Browser installers)
py -3 ssp_mod.py portable    # build the ready-to-play zip
```

Run `py -3 ssp_mod.py --help` to see every command.

## How it works

`ssp_mod.py` reads the game's `.pck` and starts again from the original files each time. It adds the mod scripts under `res://mods/<mod>/`, then points the game's own scripts at the modded copies through `.gd.remap`. Because every build starts from the original files, removing a mod leaves nothing behind. The source for each mod is in `src/<mod>/`.

## Credits

**Rhythia|Reimagined**
- Owner / vibecoder: @acetinium1
- MVP: Claude Opus 5.5
- Testers: WorstGhostPlayer, Naki, Starlie
- Mobile tester / bug hunter: @starlieu

- **Sound Space Plus**: MIT License, [Rhythia/sound-space-plus](https://github.com/Rhythia/sound-space-plus).
- **Icons**: [Uicons by Flaticon](https://www.flaticon.com/uicons).
- **Font** (share look): Exo 2, SIL Open Font License.

This is not affiliated with Rhythia or CAPO Games. Don't submit scores to online leaderboards from modded builds.
