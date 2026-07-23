# Taskblock 36 Report — One geometry: 3D shot resolution end to end

All four passes landed in order (A→B→C→D), each committed separately, full suite green throughout:
2038/2038 at the end (started at 2022). The seeded full-mission bout (seed 12354) was captured after
Pass A and diffed byte-for-byte against every subsequent pass — zero divergence, all the way through.

## Decisions made without asking

- **Pass C's own scope, narrowed from the taskblock's literal wording.** The spec says "once the
  plane is built perpendicular to the real 3D direction, a Region's height is simply its own
  position in the plane" — read literally, that could mean rebuilding the whole plane around a true
  camera-perpendicular basis (depth = true 3D ray distance, height = distance from the ray's own
  line), which would change `Region.rect.position.y`'s meaning for EVERY consumer, not just
  `resolve_ray`, and directly contradicts `region.gd`'s own documented invariant ("real world
  height"). Instead: `ShotPlane.build` gained a `_shear` step that subtracts the ray's own real
  height-at-depth from every region, provably a no-op whenever `origin.y`/`direction.y` are `0.0`
  (every caller except `resolve_ray`, unchanged). Smaller, contained, and satisfies the same test
  list the taskblock names — but it is a narrower reading of that one sentence, flagged here rather
  than assumed silently equivalent.
- **`LEVEL_HEIGHT = 1.0`**, not invented — derived from `docs/PLAN.md`'s own already-stated multi-
  level math ("22.5° ramps rise 0.5/tile → two ramps make one full level").
- **`Unit.level` is a cached field, synced from the grid at `CombatState.add_unit`**, rather than
  threading a `Grid` reference through `UnitGeometry`/`BodyProjector` everywhere `unit.cell` is
  already read. Mirrors how `cell` itself already works; kept the blast radius of Pass D to `Unit`
  + `CombatState` + `ShotPlane` instead of every placement call site.
- **Deliberately did not wire real elevation into `AttackAction`/`BurstAction`/melee actions' own
  flat `Vector2` origin/direction, or into `Overwatch`/`LineOfFire`/`Suppression`/
  `TacticsController`.** The taskblock's own scope fence ("nothing consumes it for movement yet")
  reads as covering first-hop damage resolution too, since no real caller can currently put two
  units on different levels anyway. Flagged explicitly in `docs/PLAN.md`'s own multi-level item so
  it isn't silently forgotten once movement verbs land.
- **`DamageResolver`'s own separate `vertical_slope`/`_find_next` mechanism (ricochet flights) left
  untouched** — audited and confirmed it's not a duplicate of the gap Pass C retired (every real
  first-hop caller passes `0.0` for both `origin_height` and `vertical_slope` today), but flagged
  inline as a candidate to reconcile with `build`'s own new shear once first-hop elevation exists.
- **`BoutInjector.set_cell_level` also resyncs any unit already standing on the forced cell**, not
  just the grid — the supervisor forces a scenario onto whatever bout is already running, not only
  onto units spawned after the call.

## Tests that failed, then were corrected

Five, none a real regression outside this taskblock's own new work:

1. Two new Pass B tests (tilted-part-viewed-along-its-own-rotated-axis; shot-from-directly-above)
   asserted exact `Vector3` equality against face normals carrying floating-point residue from a
   `PI / 2.0` rotation and a `0.001` heading nudge. Both failed on first run. Corrected to
   `is_equal_approx`, which is what the codebase's own convention already uses elsewhere for exactly
   this reason.
2. `test_prone_pose_changes_the_projected_shot_plane_vs_idle` (pre-existing, taskblock-20) asserted
   exactly one projected region for `Poses.prone()`'s own 90° tilt. Broke once Pass B's six-face
   model landed — `PRONE`'s tilt is this pass's own headline scenario (a face's local up rotating
   into the view axis), and now correctly reveals a second real face the old four-face model had no
   slot to show. Not a regression: the old assertion encoded the old model's own limitation, not a
   real invariant. Corrected to expect two regions, both height-shifted from the idle case.
3. The "shooter above a target resolves against its top face" test failed repeatedly (multiple
   slope/aim-point attempts, all miss or wrong-face) before the real cause was found: an UNTILTED
   box's own top face is height-DEGENERATE in this plane's `(lateral, world-height)` basis — a
   single point, not a range (`Rect2.has_point` never contains any point when `size.y == 0`,
   confirmed live with a throwaway script) — so hitting it via `resolve_ray`'s exact-zero query
   means solving for one exact slope, not "aiming steeply." Redesigned to call `ShotPlane.build`
   directly and read the produced Region back (this file's own established convention), rather than
   solving for an aim direction.
4. `test_grid_height_no_longer_exists_anywhere`'s own scanner matched itself — the file necessarily
   quotes the banned string literally, in the line that checks for it. Fixed with a self-exclusion,
   the same pattern `test_resolve_projectile_is_called_only_from_shot_plane_itself` already uses.
5. Not a test failure but a gate failure: `gdlint`'s `max-public-methods` tripped on
   `test_bout_injector.gd` once four new `set_cell_level` tests were added (the file was already at
   its own raised cap of 37). Moved the new tests to `test_bout_injector_set_cell_level.gd` instead
   of raising the limit again — matching the file's own established one-file-per-verb-family split
   (`_move_object.gd`, `_kill.gd`, `_spawn_object.gd`, `_remove_object.gd` already exist).

## `SUPERVISOR`-owned entries moved to `Pending`

None — this taskblock didn't touch `docs/BUGS.md`; nothing here closes a tracked defect.

## Open questions

- **When movement verbs land, does first-hop damage resolution get real elevation, or does it wait
  for a further pass?** The geometry underneath (`ShotPlane.build`/`resolve_ray`) already resolves a
  genuinely tilted shot correctly — only the action layer's own flat `Vector2` construction is
  missing it. Flagged in `docs/PLAN.md`, not decided here.
- **Should `DamageResolver`'s own `vertical_slope`/`_find_next` eventually share `ShotPlane.build`'s
  new `_shear`?** They're independent today (ricochet-only vs. resolve_ray), but once first-hop
  elevation exists they'd both be reconstructing the same kind of height-at-depth. Not urgent while
  neither carries real data for a first hop.
