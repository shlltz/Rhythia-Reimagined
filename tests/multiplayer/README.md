# Multiplayer tests

Automated tests for the multiplayer mod (src/replay/MP*.gd). They run real game instances built
from your profile, each with its own user data folder (`t/<name>/appdata`, the process gets
`APPDATA` pointed there), so they never read or write your real `%APPDATA%\SoundSpacePlus`.
Tests use their own pck copies under `t/`; the installed game is untouched.

    py -3 mpbench.py own|share "A=Driver.gd[,B=Driver.gd...]" [time limit s] ["A=map.sspm|map2.sspm;B=map.sspm"]

| driver | instances | what it checks |
|---|---|---|
| MPCoreTest.gd | 1 | protocol helpers, lobby rules (host-only actions, chat relay + rate limit, map check, ready, start, scores validation, results, repeated matches, disconnect / reconnect, kick, invalid messages), then a host + 2 clients over 127.0.0.1 |
| MPUiTest.gd | 1 | every screen, name, bad address / port errors, hosting, picking a map through the map page, rules, leaving |
| MPDrvA.gd + MPDrvB.gd | 2 | host + guest as separate processes: LAN discovery, chat both ways, missing map blocks the start, ready, synchronized start, No Fail enforced (and re-enforced), live scores, results on both, settings restored, second match, guest drop |
| MPDropA.gd + MPDropB.gd | 2 | the host's game dies mid-match: the guest plays on and lands back in the menu with its settings |
| SoloTest.gd | 1 | single player still works (results screen, recent plays, quick retry, no multiplayer) |
| ClassicTest.gd | 1 | classic map selection (oldmenu2): title screen pages, Esc, grid star ratings, song page extras, PICK FOR LOBBY, a run returns to the classic menu |
| SettingsSearchTest.gd | 1 | settings search (name the instance `classic` to run it on the classic menu) |
| PerfBench.gd | 1 | benchmark: startup, idle menu, map switching, load times, a full autoplay run (frame time p50/p95/p99/max, spikes, cost of hit / physics frames, audio desync, MultiMesh resizes), memory over 3 play/quit cycles. MAP1 = dense map, MAP2 = big map. Instance name `diag*` = gameplay only, `*fx*` = every per-note effect on |
| MenuProbe.gd / HandlerProbe.gd | 1 | map switching: frame times with parts switched off / the time of each selection handler |
| HitProbe.gd | 1 | time of each part of a note hit |
| PhxmTest.gd | 1 | .phxm import (the rewrite's maps): run `phxm_fixtures.py map.sspm outdir` first and pass the .sspm then the t_*.phxm files as maps; converted notes must equal the .sspm's (stored / deflated / nested zips, quantum positions, ids, duplicates, broken file, rewrite map folder, map browser install, drag-and-drop on both menus, import screen) |
| StartupProbe.gd | 1 | startup time only (use RR_KEEP=1 for warm starts; set `disable_intro` in the instance's settings.json or the stock 30 s cutscene plays) |

The two-instance tests need one map in both libraries and a second only in A's (any small .sspm,
e.g. from your own maps folder - it is only copied). Results: `t/<name>/*.txt` + screenshots.
The error count comes from `t/<name>/godot.log` (stock lines that always appear: localization.csv,
"File must be opened", particle SHADER ERRORs color_ramp / scale_texture).

Env: `RR_KEEP=1` keeps an instance's user data between runs, `RR_NONET=1` turns the game's networking off
(stock bug: init then hangs at "Check for updates"), `RR_INITPROBE=1` logs init stages with times.
