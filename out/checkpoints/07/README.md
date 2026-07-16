# Checkpoint 7

Generated 2026-07-16T12:25:50Z, by launching the real project (`godot --path .`, a real GPU frame via `--display-driver x11`) and driving `BattleScene`/`TacticsController`/`CameraRig` exactly as a player would, then reading back the rendered frame — not a mockup. Recorded with `--write-movie`, converted from Godot's
native `.avi` output via `ffmpeg -c:v libx264` for a small file instead of the raw AVI.

Phase 12 (docs/10, PLAN.md): "a human launches the game, selects a cyborg, queues a move and an
aimed shot... ends the turn, watches the burst fire and ricochet, and reads the log —
repeatedly, until one side is down." This recording exercises that loop for real: two
`DeepStrike.assemble_reference_humanoid()` cyborgs (docs/01 "The Reference Humanoid" — full
skeleton, head/arms/legs/plates/ammo rack, a pistol in each hand, deterministic and guaranteed
armed, unlike the default battle's `assemble_random` loadouts) trade pistol fire across several
rounds until one side is down or the script ends. Phase 12.5's terminal shell (real OFL
monospace font, six-color palette, rolling combat log via `UISink`, selected-unit stat block
via `StatBlockView`/`WeaponResolver`, one `Theme` resource) is visible and live throughout.

**`playthrough.mp4`** — the full recording. Watch for:
- The `RESOLUTION` banner (docs/10 Phase 12.4) holding through each turn's playback window,
  during which a muzzle-to-impact tracer fires for every "impact" cue, then returning to
  `TACTICS`.
- The combat log panel streaming real events live — `impact`/`PENETRATE`, `turn_end`,
  `turn_start` — as they're emitted, not scripted text.
- Both units alternating turns across multiple rounds, each actually taking damage.

Three stills pulled from the same run for a quick look without playing the video:
- **`frame_first_impact.png`** — captured `RESOLVE_LEAD_IN` after the very first shot, while
  its tracer is on screen.
- **`frame_round1_exchange.png`** / **`frame_round2_exchange.png`** — the log panel after the
  2nd and 4th turns, both units alternating turn order correctly.

Regenerate with `./checkpoint.sh 7` — see `tools/checkpoints/checkpoint_7.gd` for the driver
script and `run.log` for its stdout (checked for script errors on launch).

## What this closes out
- Phase 12.2 (selection/movement), 12.3 (aim UI), 12.4 (resolution playback, including the
  per-cue tracer visuals — no longer deferred), and 12.5 (terminal shell) all wired together and
  exercised live, not just headlessly.
- docs/08's transparency proof holds at the UI layer, not just the pure-logic layer
  (`test_transparency_proof.gd`): `test/unit/view/test_phase12_transparency.gd` proves the
  stat panel's predicted damage — read through `WeaponResolver`, the same call `AttackAction`
  makes — is exactly what the combat log reports once that shot actually resolves.

## Known simplifications (flagged, not silent)
- Font: docs/08 names JetBrains Mono/IBM Plex Mono/Share Tech Mono/VT323 as examples of the
  actual criterion (OFL/free, monospace); none of the four ship with this repo and there's no
  network fetch available. Anonymous Pro (OFL, monospace, already vendored under
  `addons/gut/fonts` for GUT's own UI) satisfies the same criterion — copied into
  `res://assets/fonts/` with its `OFL.txt` rather than left pointing into a third-party addon's
  private folder. Swapping in one of the docs-named fonts later is a one-line change in
  `HulkTheme.build()`.
