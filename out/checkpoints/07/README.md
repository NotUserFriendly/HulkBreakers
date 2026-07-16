# Checkpoint 7

Generated 2026-07-16T07:56:00Z, by launching the real project (`godot --path .`, Vulkan
Forward+, an NVIDIA RTX 3090 Ti) with `--write-movie` and driving a full battle through the
same public `TacticsController`/`CameraRig` API a player's mouse would use — click own unit,
click enemy to aim, confirm, End Turn, repeat. Not a mockup, not hand-edited footage.

Phase 12 (docs/10, PLAN.md): "a human launches the game, selects a cyborg, queues a move and
an aimed shot, scrolls the dartboard to inspect a target behind the first one, ends the turn,
watches the burst fire and ricochet, and reads the log — repeatedly, until one side is down."
This recording exercises that loop for real: two hand-armed cyborgs (`jerry`, `raider`) trade
pistol fire across several rounds until the script ends. Phase 12.5's terminal shell (real OFL
monospace font, six-color palette, rolling combat log via `UISink`, selected-unit stat block
via `StatBlockView`/`WeaponResolver`, one `Theme` resource) is all visible and live in the
recording.

**`playthrough.mp4`** — the full recording (~20s, converted from Godot's native `.avi` output
via `ffmpeg -c:v libx264` for a ~180KB file instead of the raw 24MB AVI). Watch for:
- The `RESOLUTION` banner (docs/10 Phase 12.4) holding through each turn's playback window,
  then returning to `TACTICS`.
- The combat log panel streaming real events live — `impact`/`PENETRATE`, `turn_end`,
  `turn_start` — as they're emitted, not scripted text.
- Both units alternating turns across multiple rounds (`T0` → `T1` → `T2`...), each actually
  taking damage.

Three stills pulled from the recording for a quick look without playing the video:
- **`frame_first_impact.png`** — the very first shot lands (`PENETRATE on raider_torso`).
- **`frame_round1_exchange.png`** / **`frame_round2_exchange.png`** — the log panel scrolling
  through consecutive rounds of fire, both units alternating turn order correctly.

## What this closes out
- Phase 12.2 (selection/movement), 12.3 (aim UI), 12.4 (resolution playback), and 12.5
  (terminal shell) all wired together and exercised live, not just headlessly.
- docs/08's transparency proof holds at the UI layer, not just the pure-logic layer
  (`test_transparency_proof.gd`): `test/unit/view/test_phase12_transparency.gd` proves the
  stat panel's predicted damage — read through `WeaponResolver`, the same call `AttackAction`
  makes — is exactly what the combat log reports once that shot actually resolves.
- Full suite: 389 tests, all green, `gdlint` clean.

## Known simplifications (flagged, not silent)
- Per-cue tracer/impact visuals during playback are deferred — the timing/locking contract
  (`ResolutionPlayer`/`LogPlayback`) is what Phase 12.4's acceptance actually grades, and
  that's headless-tested on `LogPlayback` directly. Same deferral pattern as `AimView`'s
  ghosting (Phase 12.3) and ragdolls (out of scope for the whole of Phase 12).
- Font: docs/08 names JetBrains Mono/IBM Plex Mono/Share Tech Mono/VT323 as examples of the
  actual criterion (OFL/free, monospace); none of the four ship with this repo and there's no
  network fetch available. Anonymous Pro (OFL, monospace, already vendored under
  `addons/gut/fonts` for GUT's own UI) satisfies the same criterion — copied into
  `res://assets/fonts/` with its `OFL.txt` rather than left pointing into a third-party addon's
  private folder. Swapping in one of the docs-named fonts later is a one-line change in
  `HulkTheme.build()`.
