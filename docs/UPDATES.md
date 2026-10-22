# Updates

The game checks the project's GitHub releases (Customize > Storage > Updates; optionally
at start, at most once a day). `src/replay/Updater.gd` does the work; `tests/multiplayer/UpdaterTest.gd`
tests it against a local server and a sandbox folder.

## What a release needs

Three assets on the release (tag `vX.Y.Z`):

| Asset | Made by |
|---|---|
| `Rhythia-reimagined-vX.Y.Z.pck` | `py -3 ssp_mod.py manifest --notes "..."` |
| `update.json` | same command: version, notes, the pck's URL, size and SHA-256 |
| `update.json.sig` | same command: RSA / SHA-256 signature of `update.json` |

`manifest` writes all three to `..\update-vX.Y.Z\` and checks the signature against the public key
the game is built with before it finishes.

The signing key is `tools/update_key.pem`. It is git-ignored and must stay private: whoever has it can
publish updates players will install. `py -3 ssp_mod.py updatekey` makes it once; its public half is
`src/replay/update_key.pub`, which is committed and built into the game. Losing the key means
existing installs can't verify new updates: they'd have to download a new version by hand once.

## What the game does

1. It reads the latest release from the GitHub API and downloads `update.json` and its signature.
2. It verifies the signature with the built-in public key. A changed manifest, another key, or a pck
   URL outside this project's releases is refused.
3. **Portable builds only:** INSTALL downloads the pck into `_update/` next to the game and checks
   its size and SHA-256 against the signed manifest. It copies the current pck to
   `_update/backup/SoundSpacePlus-v<old>.pck` and writes `rollback.bat` / `rollback.sh` there.
   Then it writes a small helper script (generated, never downloaded) that waits for the game to
   close, copies the verified pck over, and starts the game again.
4. The new version confirms on its first start, and ROLL BACK becomes available (the same helper
   with the backup). If the new version won't start at all, run `_update/rollback.bat`.
5. Tweaks-patched installs and the Android build are told a new version exists and get the release
   page; they don't replace files.
6. Personal builds ("own" channel) never update themselves.
7. It only replaces the `SoundSpacePlus.pck` the game is actually running from. Each build carries
   a unique build id; the updater compares its own script with the copy inside the pck next to the
   exe. Engine options like `--main-pack` don't show in the game's command line, so they can't be
   checked directly.

Existing installs from before v0.13 have no updater; they need one manual download.
