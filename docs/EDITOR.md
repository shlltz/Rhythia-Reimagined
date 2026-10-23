# Map editor: layout, mouse, shortcuts, Quantum Editor parity

The in-game map editor (main menu > Editor; `src/replay/Editor.gd`, model `EditorModel.gd`, audio
`EditorCapture.gd` + `EditorAuto.gd`, patterns `EditorPatterns.gd`). Tests:
`tests/multiplayer/EditorInteractionTest.gd`, `EditorStarTest.gd`, `EditorToolsTest.gd`,
`EditorParityTest.gd`, and the model checks in `tests/unit`.

Since 2.5.0 the editor follows the Sound Space Quantum Editor's interaction model, taken from its
source (github.com/Avibah/Sound-Space-Quantum-Editor: `GuiTrack.cs`, `GuiGrid.cs`,
`GuiWindowEditor.cs`, `KeybindManager.cs`, `Timing.cs`, `AllSettings.cs`). The Quantum Editor is
AGPL C#, so none of its code is used: only its behaviour, rebuilt in GDScript.

## Layout

| Where | What |
|---|---|
| Top bar | NEW, OPEN, SAVE, EXPORT, UNDO, REDO, TEST, TEST HERE, messages, KEYS (every shortcut), EXIT |
| Track (under the top bar, full width) | The timeline. The playhead stays at 40 % of the width and the map scrolls under it. Each note is a square whose left edge is its time, with its grid cell drawn inside and its number above. Ruler with times, measure / beat / divisor lines, timing points, bookmarks, the waveform behind. Zoomed far out it shows note density instead. |
| Left | MAP (id, title, mapper, difficulty, audio), TIMING (BPM, offset, tap, hit sound, metronome, timing points, bookmarks), NOTES (note list), AUTO (BPM / offset estimate, patterns, transforms), CHECKS (problems, history) |
| Middle | The 3x3 grid: the notes from the playhead to 0.7 s ahead, each with an approach outline closing in |
| Right | The selection (time, x, y; where the time sits on the beat grid; flip, rotate, nudge, step, snap, duplicate, repeat, delete), snapping (beat divisor, time snap, note position snap, auto-advance), view options |
| Bottom | Play / pause, the playhead time, the seek bar (the whole song: density, bookmarks, timing points, loop, what the track shows), speed, loop, zoom; a status line with the time, hints for what is under the mouse, and the live star rating |

## Mouse

| Where | Action | Result |
|---|---|---|
| Grid | click an empty cell | a note there at the snapped playhead, selected |
| Grid | click a note | select it (a note already in a multi-selection keeps it, so a group can be dragged) |
| Grid, track | Ctrl+click / Shift+click | add or remove it / select the time range from the first selected note |
| Grid | drag a selected note | move the selection by cells (the whole selection stays inside the grid) |
| Track | drag a selected note | move the selection in time, snapped to the grid (Alt: free) |
| Track | drag empty track | scrub (snapped); the song pauses while dragging and plays on after |
| Track | right-drag | box select by time (Ctrl / Shift: add to the selection) |
| Grid, track | right-click a note / empty | delete that note / deselect |
| Track ruler, seek bar | click / drag | jump there (seek bar: a bookmark under the mouse is landed on exactly) |
| Grid, track, seek bar | wheel / Ctrl + wheel / Shift + wheel | one grid step (playback pauses) / zoom the track / beat divisor |

A press only becomes a drag after 4 px, so a click never moves a note. A drag is one undo step,
and Esc cancels it. The note under the mouse is outlined; with no note there the grid shows a ghost
where a click places, and the status line says the time it goes to.

## Shortcuts

| Keys | Action |
|---|---|
| Space | play / pause (from the end: from the start) |
| Left / Right, wheel | one grid step (10 ms with time snap off); held, it repeats |
| Ctrl+Left / Ctrl+Right | one measure |
| Home / End, `,` / `.` | start / end, previous / next note |
| Q W E / A S D / Z X C (or numpad 7 8 9 / 4 5 6 / 1 2 3) | a note on that cell at the snapped playhead |
| Up / Down (Alt+Up / Alt+Down) | move the selection a row (half a row with HALF snap) / nudge 1 ms |
| Delete, Backspace | delete the selection |
| Ctrl+A, Ctrl+C / X / V, Ctrl+D | select all, copy / cut / paste at the playhead, duplicate after itself |
| Ctrl+Z, Ctrl+Y or Ctrl+Shift+Z | undo, redo (they select what they put back) |
| Shift+H / Shift+V | flip the selection left-right / up-down |
| Shift+D | Bezier curve through the selection (its notes are the control points) |
| Ctrl+Shift+1..9 / Shift+1..9 | store the selection in a pattern slot / put the slot at the playhead |
| Ctrl+Q | free note positions ("quantum") on / off |
| Ctrl+T, Ctrl+B | TIMING tab, bookmarks |
| Ctrl+Shift+B | timing point at the playhead; with two notes selected, one on the first whose BPM makes their gap one beat |
| B | bookmark at the playhead |
| L, `[` / `]` | loop on / off, loop start / end |
| Shift+C | pattern cursor on / off |
| Alt (held) | place / drag without time snap |
| Ctrl + `=` / Ctrl + `-` | zoom the track |
| F5, Shift+F5 | test the map, from the playhead |
| Ctrl+S, Ctrl+Alt+E | save, export .phxm |
| Esc | close the shortcut list, cancel a drag, deselect; with nothing of that, leave the editor (the session is kept) |
| ? | the shortcut list |

While a text or number box has the keyboard, its keys stay in it (Backspace, arrows, Space, letters,
Ctrl+Z); only Enter / Esc (leave the box; a number box takes the typed value) and Ctrl+S reach the
editor.

## Data

- A note is `[x, y, ms]` as the .sspm stores it: the time is an integer millisecond, the grid is
  rebuilt from its index on every snap (no drift), and a position only changes when it is moved (to
  4 decimals). `-0` and `0` are the same position.
- A selection moves as one piece: all out, then all in. Moving a stream along itself keeps every
  note; a note landing exactly on an unselected one merges into it (a map cannot hold two equal
  notes), and the message line says how many.
- BPM, offset, timing points and bookmarks are editor aids (Rhythia maps store absolute times); they
  live in the editor's session file. NEW / OPEN ask before dropping unsaved changes; EXIT and TEST
  keep the session.

## Parity with the Sound Space Quantum Editor

Yes = in this editor and tested; partly = a smaller version; no = missing (reason).

| Quantum Editor | Here | Notes |
|---|---|---|
| Track: fixed playhead (cursor position 40 %), map scrolls under it | yes | |
| Track: drag empty = scrub, snapped to the beat; playback paused while dragging, resumed after | yes | |
| Track: click / Ctrl / Shift selection, drag selected notes in time | yes | |
| Track: right-drag box selection | yes | Ctrl / Shift add to the selection (an addition) |
| Track: magnetic snap while dragging (snaps when within about half a grid step, at most 12 px; else free) | partly | snap is strict and Alt gives free time: a drag never lands off the grid by accident |
| Track: note squares with their cell, note numbers / times | yes | the time of the hovered note is in the status line |
| Track: drag timing points | no | timing points are set in the TIMING tab |
| Grid: click empty = note at the playhead, click note = select, drag = move by cells, group kept inside | yes | |
| Grid: holding the button and sweeping over cells places a note on each | no | left out on purpose: a click that slips to the next cell would add a second note |
| Grid: approach squares, grid letters, grid numbers | yes | numbers are a VIEW option |
| Wheel = step, Ctrl + wheel = zoom, Shift + wheel = divisor; wheel pauses playback | yes | |
| Grid keys QWE/ASD/ZXC, numpad option | yes | both layouts at once |
| Move selection with the grid keys option | no | |
| Auto-advance after placing | yes | right panel |
| Beat divisor | yes | 1..16 per beat (the Quantum Editor goes to 32) |
| Quantum (off-grid positions, Ctrl+Q) | yes | FREE position snap (0.01 steps) plus HALF; no separate quantum grid density setting |
| Timing points (Ctrl+T window, Ctrl+Shift+B) | yes | sections restart the beat grid and measures; Ctrl+Shift+B from two notes as in the Quantum Editor |
| Bookmarks (Ctrl+B), timeline bookmarks | yes | clicking one on the seek bar lands on it |
| Undo / redo, copy / cut / paste at the playhead, select all, delete | yes | pasted notes are selected |
| Esc clears the selection | yes | |
| Horizontal / vertical flip (Shift+H / Shift+V) | yes | |
| Rotate, scale | yes | AUTO tab: any angle / factor, about the centre or the selection |
| Pattern store / recall (10 slots) | yes | 9 slots (1..9) |
| Bezier curve (Shift+D) | partly | through the selected notes, one note per grid step; no separate anchor nodes (Shift+A) or curve divisor |
| Waveform | yes | sample-exact capture |
| Metronome, hit sounds, playback speed | yes | 0.25x to 1x, pitch kept |
| Autosave | yes | session recovery |
| Test / playtest (from here) | yes | in this game |
| BPM tapper | yes | plus audio BPM / offset estimate (AUTO tab), which the Quantum Editor doesn't have |
| Export .sspm / .phxm | yes | .phxm keeps the rewrite's effect sections it can't play |
| Select vs place tool split (Tab) | no | the Quantum Editor's default, "both", is the only mode |
| Paste options (reversed, jump, apply-on-paste) | no | |
| Note pushback / adjust notes on BPM change | no | notes stay at their times when the grid changes |
| Modchart / VFX events, video, Novastra export | no | this game can't play them |
| Separate SFX / music / export offsets | no | |
| Map history, recent maps, keybind editor | no | fixed keys (listed above) |
| Note colours | no | monochrome; the selection is red |
