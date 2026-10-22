# Library panel (shelved)

The Library panel (duplicates, tags, bulk rename, smart playlists, cleanup, rewrite importer) is out of the builds for now.
`Library.gd` stays in the game (the map list uses its tags and smart playlists). To bring the panel back: move these files
to `src/replay/`, add `'LibraryPanel.gd', 'RewriteImport.gd'` back to the replay file list in `ssp_mod.py`, and run `tests/multiplayer/LibraryTest.gd`.
