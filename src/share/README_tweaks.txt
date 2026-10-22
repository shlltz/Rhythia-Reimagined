RHYTHIA-REIMAGINED v@@VERSION@@ - mod pack for Rhythia Legacy / Sound Space Plus nightly (Godot 3.6.2 build)

INSTALL
  1. Close the game.
  2. Extract this zip INTO your game folder (the one with SoundSpacePlus.exe),
     so you get  <game folder>\@@FOLDER@@\Install.bat
  3. Double-click Install.bat.
  The original game file is backed up as SoundSpacePlus.pck.tweaks-backup.
  If your game is a different version, the installer stops and changes nothing.

UPDATE
  Close the game and run the new version's Install.bat - the old version is undone
  automatically (no need to uninstall first).

UNINSTALL
  Double-click Uninstall.bat (puts the backed-up game file back).

WHAT YOU GET
  Startup     osu!-style intro (logo zoom + sound)
  Menu        osu!-style springy buttons (hover / press / pop), smooth parallax, sidebar icons centred, moving topographic background, mouse parallax, slide/fade animations,
              audio visualizer along the bottom, pause-all-music button (top left), zoom-in transition + loading screen card,
              Alt + mouse wheel volume rings (hover Music/Effects; SHIFT = 1%)
  Maps        star rating + estimated BPM on every map (a range like 150-180 when the tempo changes;
              speed mods raise / lower both, animated), Start + buttons under the MODS bar,
              S---- speed (x0.69, the reverse of S++++) left of the <<< button,
              mods menu that wipes up, restyled Content Manager,
              sort by stars / name / mapper / last played / date added / length / BPM (Filters),
              osu!-style search: every word must match (title, mapper, difficulty; "quotes" keep
              words together) + filters stars>10  bpm<=180  length<2:30  notes>3000  mapper=name,
              imported map files go to the Recycle Bin after a successful import,
              .phxm maps (the Rhythia rewrite's format) import too: drag and drop, Content
              Manager > Sound Space Plus Map, or a rewrite map folder (converted to .sspm),
              map cache fix (faster library loading)
  Browse      "Browse" (sidebar or title screen): online map browser that slides up
              from the bottom - search rhythia.com, Any / Ranked / Approved / Unranked, sort
              by stars / newest / plays / length, cards with cover, artist, mapper, status,
              stars and difficulty, one-click download; maps you have get "Go to map" (selects it);
              pages load in parallel and results are remembered (reopening is instant)
  Title menu  osu!-style main menu (beating logo + spectrum ring, rain / snow / wavey background (Customize > Interface),
              Play / Settings / Browse / Exit); ESC on map selection opens it
  Customize   F1, the sliders sidebar button or Customize on the settings page:
              - cursor trail: game / osu!-style / off, colour, opacity, length, size (live preview)
              - HUD layout editor: drag / scroll / right-click the side panels (accuracy, score,
                timer, health) to move, scale or hide them
              - skin: replace the play-area border, grid, trail dot, title logo and sidebar
                icons with your own images (Choose... / Reset)
              - collections (map packs): "Add to collection..." in a map's ... menu, filter by
                collection under Filters; sort the map list (stars / name / mapper / played / added /
                length / BPM)
              - hide the "Default hitboxes, default hitwindow" line and the in-game HIT WINDOW /
                HITBOX panel (on by default)
              - storage (Windows): move your user folder (maps, replays, scores, settings) to
                another drive; the game closes, copies, checks the copy, links the old place
                to the new one and starts again
  Settings    redesigned settings page (tab column + big card, like Customize); ESC = title screen;
              "Half Ghost Fade" (25-300%) right under Fade Length in the Notes tab
              "Rewrite Feel" in the Gameplay tab: maps play with the Rhythia rewrite's default look
              (approach 30 / 15, FoV 70, camera sway, its note fade + pushback); your own settings
              stay as they are and apply again when it's off
  Map FX      the cover art is a visualizer: hits on the map's beats, spectrum bars around it;
              7+ stars: glowing screen sides, 10+ stars: cover and Start quake, lightning on
              select, hovering Start dims everything else; speed mods count the stars up;
              10+ stars also get glitch + chromatic aberration (toggle: Customize > Interface)
  Pass        green glow around the screen once every note is done, zoom into the results
  Results     osu!-style results screen (layout from Rhythia's rewrite): counting score, grade,
              PASSED / DISQUALIFIED / FAILED, Back / Retry (`) / Watch replay / Analyse;
              after a fail, "From fail point" restarts from the last checkpoint before it with
              score, combo and health as they were (marked as resumed: no personal best, no replay)
  Pause       osu!-style pause screen: ESC pauses (any time, even in the lead-in; Continue / Retry / Quit, ESC again = continue,
              counts back in by itself); SPACE only skips intros. A paused run is disqualified
              (no personal best). Quick retry: hold ` (left of 1) during a run - the screen fades
              out and the map restarts.
  Replays     "Replays" sidebar button; while watching: SPACE pause | LEFT/RIGHT seek 5s
              (SHIFT 1s, CTRL 15s) | UP/DOWN speed 0.25x-2x | , . frame step | drag the bar
              | H hide UI (twice = whole HUD) | K keybind panel | ESC leave;
              misses show as red ticks on the replay bar
  Studio      "Studio" in the replay browser, "Analyse" on the results screen: accuracy, combo and
              cursor speed over the song, cursor heatmap, aim against the hitbox, hit delay per note,
              miss list (N / SHIFT+N), compare with another replay or your best on the map,
              WATCH FROM any moment, and 3-10 s clips as GIF (MP4 with sound if ffmpeg is installed)
  Library     "Library" sidebar button: duplicate finder (same notes, even from another editor),
              tags (search tag=name), bulk rename with undo, smart playlists (stars, played,
              failed / added in N days, favourites, tags...) in the collection filter, statistics,
              cache cleanup, and an importer for the Rhythia rewrite's map library
  Skins       Customize > Skin > Skin editor: notes (shape, own .obj, colours, size, spin, image),
              cursor + trail, hit / miss effects and sounds, HUD font and colours; live preview,
              several profiles, .rrskin files to share them
  Colorsets   Settings > Notes > Note Colors: a "+" cell after the last colorset opens the Colorset
              Maker (name, colours with a picker, add / remove / reorder, mirror, load an existing
              set, Save / Save & Use). Saved as colorsets/<name>.txt like hand-made ones.
  Editor      "Editor" title card + sidebar button, EDIT on the map page: edits real .sspm maps
              (new map from an mp3 / ogg / wav, or any library map). 3x3 field + timeline with
              waveform, snapping (BPM / offset / 1/1..1/16 grid are editor aids, not stored in the
              map), select / move / copy / paste / duplicate / mirror / rotate / repeat, undo / redo,
              bookmarks, loop, hit sounds + metronome, checks, autosave + recovery, SAVE (.sspm in
              your library, old file backed up first), EXPORT (verified copy + .txt), TEST (F5) runs
              the real game and returns to the same session. SPACE play | LEFT/RIGHT step | B bookmark
              | L loop | CTRL+Z/Y/C/V/D/A/S | ESC leave. Original library maps are never overwritten
              (built-in / online maps open as a *_edit copy).
              AUTO tab: BPM + offset from the song itself, beat markers, pattern tools (streams,
              jumps, circles, spirals, rotate / scale / mirror, slots 1-9). Quantum Editor keys:
              QWE / ASD / ZXC grid, SHIFT+H / V flips, timing points, Bezier curves (SHIFT+D).
              Live star rating while you map; EXPORT writes .phxm too (map page ... menu as well).
  Multiplayer "Multiplayer" title card + sidebar button. Create a lobby (your game hosts it while
              you play - no server needed) or join one: LAN lobbies are found automatically, or
              type the address / room code shown in the lobby. The host picks the map (SELECT MAP,
              then PICK FOR LOBBY on the map page), speed and mods; everyone needs the same map
              (checked: same notes + audio), presses READY, and the host starts. All games start
              together, No Fail is always on, live scores on the left, ranked results after,
              chat, kick / make host, reconnect after a short drop. Your own mods / settings come
              back after each match. Session results only: no personal bests, replays or recent plays.
              Same network: nothing to set up. Internet: HOST ONLINE goes through a relay server -
              no port forwarding, VPN or IP addresses; share the room code or the invite link and
              friends paste it into JOIN. It needs a relay address: none is built in, so use one your
              community runs or run your own (relay/ folder in the source, docs/RELAY.md). Without a
              relay: the host forwards TCP port 47320 (or everyone uses Tailscale / ZeroTier /
              Radmin VPN). Allow SoundSpacePlus.exe in the firewall (TCP 47320, UDP 47321 for LAN).
  Look        Exo 2 font, colours matching the Rhythia logo, Flaticon icons, osu-style results panel,
              bigger settings page
  Language    Vietnamese (pick "Tieng Viet" in the language menu, in place of Polish)
  Discord     status shows "Playing Glitchia"
  FPS         small performance tweaks (visuals unchanged); Customize > Device has a low-end
              profile (with RESTORE)
  Updates     portable version: Customize > Storage checks GitHub for a new release; updates are
              signed and checked before they're installed, and ROLL BACK undoes one

CREDITS
  Rhythia|Reimagined
    Owner / vibecoder: @acetinium1
    MVP: Claude Opus 5.5
    Testers: WorstGhostPlayer, Naki, Starlie
    Mobile tester / bug hunter: @starlieu
  Icons: Uicons by Flaticon (www.flaticon.com) - Flaticon-license.txt
  Font: Exo 2 (SIL Open Font License) - Exo2-font-license.txt
