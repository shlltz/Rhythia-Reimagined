Discord mod: Discord status shows your own app's name + picture instead of "Rhythia".

Discord always shows "Playing <application name>" and only images uploaded to that
application, so it needs an application you own (one-time setup):

1. https://discord.com/developers/applications -> New Application -> name it "Glitchia".
2. Rich Presence -> Art Assets -> upload glitchia.png (this folder) with the name "glitchia".
   (New assets can take a few minutes to show up.)
3. General Information -> copy the APPLICATION ID.
4. Close the game, then in _modding:   py -3 ssp_mod.py discord --app-id <APPLICATION ID>

Options: --image <asset name> (default glitchia), --text <hover text> (default Glitchia).
Remove: py -3 ssp_mod.py discord --undo
