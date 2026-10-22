# Godot version assessment

**Recommendation: stay on Godot 3.6.2 for Rhythia Legacy.** Porting to Godot 4 is a rewrite of the
distribution model plus weeks of porting, with no feature a player would notice. New Godot 4 work
fits better in the Rhythia rewrite (`Rhythia/Client`: Godot 4.6, C#), the official successor.

## What we're running on

- Rhythia Legacy / Sound Space Plus nightly is an exported **Godot 3.6.2** game (official release
  template, GLES3). Checked from the executable's own banner: `Godot Engine v3.6.2.stable.official`.
- This project doesn't build the game from a Godot project. `ssp_mod.py` patches the shipped
  `.pck` (Godot 3 pack format) with our GDScript sources: about 32,000 lines across the mods.
- The game's own source is MIT-licensed (`Rhythia/sound-space-plus`, branch `nightly`). It uses
  GDNative plugins: the Discord Game SDK, godot_openvr and nativedialogs.

## What a Godot 4 port would involve

| Area | Godot 3 (now) | Godot 4 | In our mods |
|---|---|---|---|
| Distribution | patch the shipped pck | build and ship the whole game from its source; the pck format changed too | the whole tool |
| Coroutines | `yield(obj, "signal")` | `await` | ~100 uses |
| Arrays | `PoolByteArray` etc. | `PackedByteArray` etc. | ~290 uses |
| Files | `File`, `Directory` | `FileAccess`, `DirAccess` (static, different errors) | ~210 uses |
| Control layout | `rect_size`, `rect_position`, `rect_min_size` | `size`, `position`, `custom_minimum_size` | ~490 uses |
| Signals | `connect("sig", obj, "method", binds)` | `sig.connect(callable.bind())` | ~320 uses |
| Rendering | `VisualServer`, `Spatial`, GLES3 | `RenderingServer`, `Node3D`, Vulkan or Compatibility | a few; shaders need checking |
| Native plugins | GDNative | GDExtension | Discord, VR, native dialogs need replacements or go |
| Android | Godot 3 template | Godot 4 Gradle export | the APK build changes completely |

Godot's 3-to-4 converter handles much of the syntax. It doesn't handle behaviour changes such as
`await` timing, the new `Thread` / `Callable` APIs, Control sizing and theme overrides, and
`AudioStreamSample` becoming `AudioStreamWAV`. The same goes for every stock script the mods
replace: those are edited copies of stock scripts and would need re-porting from the Godot 4
version of the game's source.

## What we'd gain, measured against now

- **Performance:** frames take ~0.6 ms on a desktop and hits under 1 ms (`docs/PERF.md`); the
  game isn't held back by the engine here.
- **Rendering:** Godot 4's renderer could look better. Older Android GPUs that only have GLES3
  would need the Compatibility renderer, which gives up most of those gains.
- **Engine features** the mods miss today are worked around: sample access comes through
  `AudioEffectCapture`, and threads handle the heavy work.

## If it's ever done

Port the stock game source first and keep it playable. Then port the mods one at a time,
starting with the pure modules (they have unit tests) and the gameplay hooks. Port the game tests
too (`tests/multiplayer`), and compare with PerfBench on both versions before switching players
over.
