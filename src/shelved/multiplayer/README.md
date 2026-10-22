# Multiplayer (shelved)

Multiplayer is taken out of the builds for now. The code is kept here as it was, so it can come back
without being rewritten. While these files aren't in the build, every hook in the game switches itself
off: they all check `ResourceLoader.exists("res://mods/replay/MPMenu.gd")` or look for the
`RRMultiplayer` node. That covers the title card, the sidebar button, the Customize switch, the
lobby pick on the map page, the in-game overlay, and No Fail / settings restore.

| File | What it is |
|---|---|
| `MPProto.gd` | protocol constants, message framing, sanitising, room codes |
| `MPLobby.gd` | host rules (pure state machine) |
| `MPHost.gd` | the host's TCP server (+ relay tunnel streams) |
| `MPClient.gd` | every player's connection, match flow, settings snapshot / restore |
| `MPMenu.gd`, `MPOverlay.gd` | lobby screens, in-game board |
| `MPRelay.gd` | online lobbies through the relay (`relay/`, `docs/RELAY.md`) |

## Putting it back

1. `git mv src/shelved/multiplayer/MP*.gd src/replay/`
2. In `ssp_mod.py`, add `'MPProto.gd', 'MPLobby.gd', 'MPHost.gd', 'MPClient.gd', 'MPMenu.gd', 'MPOverlay.gd', 'MPRelay.gd'`
   back to the `replay` mod's file list (next to `'RewriteFeel.gd'`).
3. In `tests/unit/run.py`, add `'MPProto.gd', 'MPRelay.gd'` back to `FILES`, and un-comment `_relay()` in
   `tests/unit/UnitRunner.gd`.
4. Run the multiplayer tests before shipping: `MPCoreTest` + `MPUiTest`, `MPDrvA/B`, `MPDropA/B`,
   `relay_e2e.py` (+ `--tls`), all in `tests/multiplayer/` (`docs/TESTING.md`).

The relay service (`relay/`) is independent of the game build and keeps its own tests (`relay/test_relay.py`, run by CI).
