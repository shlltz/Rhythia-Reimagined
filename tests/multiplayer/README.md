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

The two-instance tests need one map in both libraries and a second only in A's (any small .sspm,
e.g. from your own maps folder - it is only copied). Results: `t/<name>/*.txt` + screenshots.
