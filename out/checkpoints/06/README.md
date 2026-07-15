# Checkpoint 6

Generated 2026-07-15T22:40:00Z, by launching the real project (`godot --path .`, Vulkan
Forward+, an NVIDIA RTX 3090 Ti) and driving `BattleScene`/`CameraRig`/`UnitView` exactly as a
player would, then reading back the rendered frame — not a mockup.

Phase 12.1 (docs/10, PLAN.md): the battle renders. No input yet. `BoardView` draws a ground
plane sized to the grid plus a box per blocker; `UnitView` walks each unit's socket tree via
`UnitGeometry.placements()` and emits one `BoxMesh` per living `Box` at its fully composed
transform — "render is hitbox," so what's on screen is exactly what the shot plane can hit.
Materials render flat/unshaded via `HulkTheme.flat_material()` (docs/08: six colors, no
per-scene styling, no lighting setup needed for a programmer-art pass). `CameraRig` is a
two-pivot orbit rig (yaw around world Y, pitch around its own local X) driven by a pure,
headless-tested `CameraOrbitState` — pitch is clamped to `(-80°, -6°)` so it can never reach a
pole and gimbal-lock.

Look for:
- **`board_wide.png`** — the default seeded battle (seed `20260715`, a 12x10 grid): two
  deep-struck cyborgs at their assigned cells, each rendering as a torso box with whatever
  limbs its random assembly attached (Phase 12.0's mirrored-socket fix is why they don't
  collapse onto each other or onto the same coordinates). The "New Battle" button (top-left)
  is live UI, not a mockup.
- **`cyborg_closeup.png`** — the near cyborg framed close: a torso box with a leg stub
  extending from its own composed `HIP` socket transform, not hand-placed.
- **`twelve_arm_rig.png`** — the acceptance case from PLAN.md Phase 12.0/12.1 made visible: a
  torso (yellow, `steel`) with 12 `SHOULDER` sockets, each hosting a duplicated `arm` template
  (gray, `sheet_steel`), evenly spaced and **not overlapping** — the actual bug this phase
  exists to fix (one arm template, two-plus shoulder sockets, all landing at identical
  coordinates) is gone.

No script errors on launch (checked via stdout on a real `--display-driver x11` run, not
`--headless`, since `--headless` only supports the no-op `dummy` renderer and can't produce a
real frame to screenshot). Headless coverage for everything screenshots can't show — exact box
sizes/transforms, destroyed-part removal, camera clamp math, deterministic reseeding — lives in
`test/unit/logic/test_unit_geometry.gd`, `test/unit/logic/test_camera_orbit_state.gd`, and
`test/unit/view/{test_board_view,test_unit_view,test_camera_rig,test_battle_scene}.gd`.
