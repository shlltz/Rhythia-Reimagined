# Release checklist

1. **Tests:** unit tests pass, and the game tests for everything that changed pass on `own` and `share`.
2. **Version:** `py -3 ssp_mod.py version X.Y.Z` (it goes into the title screen, Customize, zip names and the updater).
3. **Builds** (close the game first):

   ```bash
   py -3 ssp_mod.py rebuild
   py -3 ssp_mod.py tweaks
   py -3 ssp_mod.py portable
   py -3 ssp_mod.py linux
   py -3 ssp_mod.py manifest --notes "one line about the release"
   ```

   `manifest` builds the release pck and signs `update.json` with `tools/update_key.pem`.
   The Android version is no longer made (from 2.3.6 on): `apk` is still in `ssp_mod.py` but isn't part of a release.
4. **Check what goes public:** open each zip and make sure nothing personal or excluded is
   inside: no personal-look mods, no third-party files we can't redistribute, no keys, no logs, no
   user folder files. The private signing keys (`tools/`) are never uploaded.
5. **Publish** a GitHub release tagged `vX.Y.Z` with:
   - the zips,
   - `Rhythia-reimagined-vX.Y.Z.pck`, `update.json` and `update.json.sig` from `..\update-vX.Y.Z\`
     (without these, installed copies won't see the update).
6. **Clean up** the previous version's build files (to the recycle bin).

The updater reads the **latest** release. If a release goes out without its update files, the
updater reports "the latest release has no update manifest" and changes nothing.
