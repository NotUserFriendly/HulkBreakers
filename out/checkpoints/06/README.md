# Checkpoint 6

Generated 2026-07-16T12:22:52Z, by launching the real project (`godot --path .`, a real GPU frame via `--display-driver x11`) and driving `BattleScene`/`TacticsController`/`CameraRig` exactly as a player would, then reading back the rendered frame — not a mockup.

Phase 12.1 (docs/10, PLAN.md): the battle renders. `BoardView` draws a ground plane sized to
the grid plus a box per blocker; `UnitView` walks each unit's socket tree via
`UnitGeometry.placements()` and emits one `BoxMesh` per living `Box` at its fully composed
transform — "render is hitbox," so what's on screen is exactly what the shot plane can hit.
`CameraRig` is a two-pivot orbit rig (yaw around world Y, pitch around its own local X) driven
by a pure, headless-tested `CameraOrbitState` — pitch is clamped to `(-80°, -6°)` so it can
never reach a pole and gimbal-lock.

Look for:
- **`board_wide.png`** — the default seeded battle (seed `20260715`, a 12x10 grid): two
  deep-struck cyborgs at their assigned cells, each rendering as a torso box with whatever limbs
  its random assembly attached. The "New Battle" button (top-left) is live UI, not a mockup.
- **`cyborg_closeup.png`** — the near cyborg framed close: whatever limbs its own composed
  socket transforms placed there, not hand-placed.
- **`twelve_arm_rig.png`** — the acceptance case from PLAN.md Phase 12.0/12.1 made visible: a
  `steel` torso with 12 `SHOULDER` sockets, each hosting a duplicated `arm` template
  (`sheet_steel`), evenly spaced and **not overlapping** — the bug this phase exists to fix
  (one arm template, two-plus shoulder sockets, all landing at identical coordinates) is gone.

Regenerate with `./checkpoint.sh 6` — see `tools/checkpoints/checkpoint_6.gd` for the driver
script and `run.log` for its stdout (checked for script errors on launch).

Headless coverage for everything screenshots can't show — exact box sizes/transforms,
destroyed-part removal, camera clamp math, deterministic reseeding — lives in
`test/unit/logic/test_unit_geometry.gd`, `test/unit/logic/test_camera_orbit_state.gd`, and
`test/unit/view/{test_board_view,test_unit_view,test_camera_rig,test_battle_scene}.gd`.
