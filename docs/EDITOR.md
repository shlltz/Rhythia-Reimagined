# Map editor: features, shortcuts, Quantum Editor parity

The in-game map editor (main menu > Editor; `src/replay/Editor.gd`, model `EditorModel.gd`, audio
`EditorCapture.gd` + `EditorAuto.gd`, patterns `EditorPatterns.gd`). Tests:
`tests/multiplayer/EditorStarTest.gd`, `EditorToolsTest.gd`, `EditorParityTest.gd`.

## Shortcuts

| Keys | Action |
|---|---|
| Q W E / A S D / Z X C (or numpad 7 8 9 / 4 5 6 / 1 2 3) | note on that grid cell at the (snapped) playhead |
| Click a cell / right-click a note | place / delete |
| Space | play / pause |
| Left / Right, mouse wheel | one grid step (10 ms with time snap off) |
| Ctrl+Left / Ctrl+Right | one measure |
| Home / End, `,` / `.` | start / end, previous / next note |
| Up / Down (Alt+Up / Alt+Down) | move the selection a row (half a row with HALF snap) / nudge 1 ms |
| Delete, Backspace | delete the selection |
| Ctrl+A, Ctrl+C / X / V, Ctrl+D | select all, copy / cut / paste at the playhead, duplicate after itself |
| Ctrl+Z, Ctrl+Y or Ctrl+Shift+Z | undo, redo (they select what they put back) |
| Shift+H / Shift+V | flip the selection left-right / up-down |
| Shift+D | Bezier curve through the selection (its notes are the control points) |
| Ctrl+Shift+1..9 / Shift+1..9 | store the selection in a pattern slot / put the slot at the playhead |
| Ctrl+Q | free note positions ("quantum") on / off |
| Ctrl+T, Ctrl+B | TIMING tab, bookmarks |
| Ctrl+Shift+B | timing point (BPM change) at the playhead |
| B | bookmark at the playhead |
| L, `[` / `]` | loop on / off, loop start / end |
| Shift+C | pattern cursor on / off |
| Alt (held) | place / drag without time snap |
| F5, Shift+F5 | test the map, from the playhead |
| Ctrl+S, Esc | save, exit |

## Parity with the Sound Space Quantum Editor

Checked against the Quantum Editor's own default settings and keybinds
(`Editor/New SSQE/Preferences/AllSettings.cs` in github.com/Avibah/Sound-Space-Quantum-Editor).
Yes = in this editor and tested; partly = a smaller version; no = missing (reason).

| Quantum Editor | Here | Notes |
|---|---|---|
| Grid keys QWE/ASD/ZXC, numpad option | yes | both layouts at once; letters drawn in the cells |
| Auto-advance after placing | yes | TIMING tab checkbox |
| Beat divisor | yes | 1..16 per beat, presets 1/3 .. 1/12 |
| Quantum (off-grid positions, Ctrl+Q) | yes | FREE position snap (0.01 steps) plus HALF; no separate quantum grid density setting |
| Timing points (Ctrl+T window, Ctrl+Shift+B) | yes | sections restart the beat grid and measures; editor-only (Rhythia maps store absolute times) |
| Bookmarks (Ctrl+B) | yes | list in TIMING |
| Undo / redo, copy / cut / paste, select all, delete | yes | |
| Horizontal / vertical flip (Shift+H / Shift+V) | yes | |
| Rotate, scale | yes | AUTO tab: any angle / factor, about the centre or the selection |
| Pattern store / recall (10 slots) | yes | 9 slots (1..9) |
| Bezier curve (Shift+D) | partly | through the selected notes, one note per grid step; no separate anchor nodes (Shift+A) or curve divisor |
| Waveform | yes | sample-exact capture |
| Metronome, hit sounds, playback speed | yes | |
| Autosave | yes | session recovery |
| Approach preview of the next notes | yes | field preview |
| Test / playtest (from here) | yes | in this game |
| BPM tapper | yes | plus audio BPM / offset estimate (AUTO tab), which the Quantum Editor doesn't have |
| Export .sspm / .phxm | yes | .phxm keeps the rewrite's effect sections it can't play |
| Select vs place tool split (Tab) | no | click on empty cell places, on a note selects |
| Paste options (reversed, jump, apply-on-paste) | no | |
| Note pushback / adjust notes on BPM change | no | notes stay at their times when the grid changes |
| Modchart / VFX events, video, Novastra export | no | this game can't play them |
| Separate SFX / music / export offsets | no | |
| Map history, recent maps, keybind editor | no | fixed keys (listed above) |
