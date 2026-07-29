# CHANGELOG.md — What's Been Built

**The current-state snapshot**, by system, with the taskblock that landed each. Grows as work ships.
For what changed shape along the way see `SUPERSEDED.md`; for what's next see `PLAN.md`.

**A changelog logs changes — it is not a code-you're-proud-of log.** Three kinds of entry belong here
that are easy to leave out, and all three are worth more than another success line:
- **Approaches tried and reverted.** "A greedy distance scorer was tried first and reverted, because it
  reproduces the concave-wall freeze" saves the next person from re-trying it. A dead end that isn't
  written down gets walked twice.
- **Partial wins, stated honestly.** "Halved the cost, did not eliminate it — the remainder is real
  per-cell geometry work" is the useful form. Rounding a partial fix up to a complete one is how a
  known-incomplete thing gets treated as done.
- **Audited and found correct.** When a sweep checks N sites and finds them fine, that conclusion is a
  current-state fact and belongs here — it is exactly what stops the next audit re-deriving the same
  ground. Record what was checked and *why* it holds, not just that it passed.

**When a later change overwrites an entry, mark the old one and point forward to the newer entry** —
don't silently leave a description that has stopped being true. A stale entry in a current-state
snapshot is worse than a missing one, because it still reads as authoritative.

*Current as of the post-taskblock-46 search-memory fix — `ROAM`/`HUNT` no longer oscillate between two
cells (`BR46.01`, completion 56% over 100 seeds, unchanged within noise — the fix moved the failure
mode, not the rate), and the hunt for the other half of that report found that **16 of 40 generated maps
contain ground a unit can walk into and never leave** (`BR46.02`, open, a design call). taskblock-46
Passes A–F landed — AI v2 part three: raised rooms no longer punch pits
under cover and spawn tiles (BR40.03/BR40.04), the completion number is a random sample with a
deterministic escalation behind it rather than a pinned pessimistic window, four search verbs give a
unit with nothing in sight something to do, `Panic` names the give-up instead of shrugging silently, and
the `docs/11` tier table is filled in with an Elite depth 2–3 lookahead — **but nothing authors
`intelligence_tier`, so every unit in every measured bout is `TRAINED` and most of that table is
reachable from tests only.** Completion moved 54% → 60% across the block; `BR45.03` is narrowed, not
closed. The playstyle vocabulary is deleted outright and a bout names a `UtilityProfile` id directly.
taskblock-45 Passes A–E landed — AI v2 part two: the engagement-score planner is
deleted and a utility scorer over data-authored actions replaces it. Per-candidate `ShotPlane` casts
are gone outright (29.1 builds per turn → 0.0) and plan cost fell 485ms → 131ms, but **mission
completion fell 87.5% → 54.2% over 24 seeds and `MIN_COMPLETION_RATE` sits at 0.35 rather than its
old 0.5** — a known, characterized regression carried forward as `BR45.03`, and the highest-priority
AI item in `PLAN.md`. taskblock-44 Passes A–D landed — AI v2 part one: the release-vs-debug number
exists (~1.29x, so debug overhead is not the explanation), the line-of-fire query is inverted, the
WorldView information seam is in, and a unit's turn is navigable rather than frozen. taskblock-43
Passes A–D landed — the AI planning-cost block, whose most useful result is that the candidate search
it attacks is only ~25% of a planning turn and the LOF prefilter scan is the rest (see "AI planning
cost" below). taskblock-42 Passes A–E landed (F and G held — see below). taskblock-41 Passes A–F —
"Diagnostics: the log becomes the instrument" is closed, and so is "Checkpoints return as an ordinary
tool." The combat log now carries engine and script errors, pairs every command with its outcome and
a reason, narrates a bout build in construction order, and draws itself as a real window with a live
framerate on it. Checkpoints are a tool again rather than a gate, guarded in CI by parsing what
cannot be rendered. See `PLAN.md`.*

---

## Combat core

**Part graph** (tb01–02, docs/01/01a) — inverted attachment (parts declare `attaches_to`, sockets
declare `socket_type`); socket ids; socket transforms (sockets = joints, parts = bones); limb
decomposition; capability tags (`TRIGGER`/`SUPPORT`/`GRIP`/`POWER`) + weapon `requires`; keyed
cladding vs generic plates. Bot builder debug scene over the real `BodyAssembler`.

**Geometry & targeting** (tb02/06/07/23, docs/02) — continuous projection, no exposure table,
retaining each part's real vertical position (tb23 A: a head projects higher than a waist, no
longer flattened to one height plane); depth-sorted shot plane with gap fall-through (the sniper
thread); dartboard scatters isotropically in both the lateral and vertical axes (tb23 B);
`resolve_ray(muzzle, dir)` the resolution seam, now a true 3D ray — a shot can pass over a short
part into a taller one behind it, and a ricochet branches vertically as well as horizontally
(tb23 C); `READING`/`RESOLVES` never conflated. **Muzzle-anchor fix** (tb27 A1) — every attack
action now builds its shot-plane `origin` from the SAME shouldered-muzzle point as its `direction`
(previously `direction` used the shooter's cell, `origin` its own muzzle — the mismatch could
resolve a target at negative depth relative to the ray, animating as the burst firing backward).
Shot/deflect impacts also now hold a deliberate beat (`DEFLECT_BEAT_MS`) between the primary hit
and its own deflect tracer (tb27 A2), instead of both resolving in the same instant.

**One geometry: the 2D/3D shot-plane split closed, and the first slice of multi-level (tb36,
docs/02/PLAN.md)** — tb23 gave rays a real vertical component; the surfaces they resolved against
stayed 2D for three more taskblocks. Four passes, each re-running a seeded full-mission bout (seed
12354) and diffing its combat-log event stream byte-for-byte against the pass before it — every
pass landed with **zero observable change** to that bout, the standing proof that none of this
altered a single level shot.
- **Pass A** — `BodyProjector.project`/`project_assembly`/`project_part`/`_project_box` and
  `ShotPlane.build` widen to `Vector3` origins/directions; every existing caller wraps its flat
  `Vector2` with `y == 0.0`. Pure plumbing, provably inert.
- **Pass B** — `_FACE_NORMALS`/`_FACE_CORNERS` grow from four side faces to six (`+/-X`, `+/-Z`,
  `+/-Y`), each carrying its own real 4 local corners instead of the old 2-corner-plus-tilt-
  widening encoding. The visibility test is fully 3D now — a face's real world normal (including
  its vertical component) against the ray's own real 3D direction, not the horizontal slice alone.
  **Fixes the headline bug:** a part tilted so its local up is horizontal (`Poses.aiming()`'s own
  -45° shoulder tilt, taken further — `Poses.prone()`'s 90° tilt hits this exactly, and
  `test_prone_pose_changes_the_projected_shot_plane_vs_idle` now correctly shows a SECOND real face
  where the old four-face model only ever showed one) used to go edge-on on all four old faces
  simultaneously and vanish; it now projects a real region. A face genuinely facing the shooter
  registers even with a degenerate-height rect (an untilted horizontal face's own true property in
  this plane model — see the multi-level note below); the hollow far-face rule (tb20 C3) still
  emits exactly the entering/exiting pair, not the four extra faces six candidates could otherwise
  leak.
- **Pass C** — `ShotPlane.build` does its own height reconciliation once, at the source: a
  `_shear` step converts every region's `rect.position.y` from absolute world height into height
  relative to the ray's own real path, providing "height relative to here" — the two-path
  duality (`resolve_ray`'s own real-3D-ray path vs. `build`'s ground-heading-only path) never
  fully unified because `build`'s own `(lateral, real world height) x depth-along-ground` plane
  basis is deliberately not a full pinhole camera; `resolve_ray`'s own separate `muzzle.y +
  vertical_slope * depth` reconstruction is gone, replaced by reading a plane already built that
  way. Provably a no-op for every caller except `resolve_ray` (`origin.y`/`direction.y` both
  `0.0` everywhere else, still true after this pass). The dead-vertical bail stays — an honest
  `null`, not an arbitrary basis that would silently rotate the dartboard's own scatter axes.
  **Audited and found correct as scoped:** `DamageResolver`'s own separate `vertical_slope`/
  `_find_next` mechanism (ricochet flights only, `origin_height`/`vertical_slope` both `0.0` for
  every real first-hop caller today) is a genuinely different, self-contained value, not a
  duplicate of the gap this pass retired — flagged as a candidate to reconcile once Pass D's own
  elevation reaches a first-hop shot, not this pass's to touch.
- **Pass D** — `Grid.height` (row count) renamed `Grid.rows` in the same commit that adds
  `Grid.level` (a per-cell integer, defaulting to 0, alongside `terrain`/`opacity`) — the first
  real slice of multi-level maps (docs/PLAN.md). `Unit.level` (cached, synced from the grid at
  `CombatState.add_unit`) drives `UnitGeometry`'s own root-transform Y translation
  (`LEVEL_HEIGHT = 1.0`, docs/PLAN.md's own "two ramps make one full level" math, not a number
  invented here) and a matching raise in `ShotPlane.build` (`BodyProjector` composes a body in
  body-local space and has no notion of cell/level at all — elevation only enters where a cell's
  world position already gets composed in). Deliberately inert in normal play: `MapGen` writes
  nothing (the array's own default is already 0), and `Pathfinder` never reads `level` at all.
  `BoutInjector.set_cell_level` (+ a matching debug-panel entry) is the only way a nonzero level
  exists today — exactly the tool this needs before any movement verb can force a real scenario to
  watch. **Surfaced, not a bug:** an UNTILTED box's own top face is height-DEGENERATE in this
  plane's `(lateral, world-height)` basis — a single point, not a range (`Rect2.has_point` never
  contains any point when `size.y == 0`, confirmed live) — so a shooter standing above a target
  correctly produces a real top-face `Region` (proven in `test_multi_level_geometry.gd` by reading
  the produced Region back, per this file's own testing convention — never re-deriving the
  formula), but "resolving" onto that exact single point via `resolve_ray`'s own query would mean
  solving for one exact slope, not aiming. Only a genuinely TILTED face (this pass's own headline
  case) gains real height extent. **Out of this slice, staying that way:** vertical movement verbs
  (climb/hop-down/ramps/stairs), height-aware pathfinding, fall damage, height-derived combat
  bonuses — the rest of docs/PLAN.md's own multi-level item. **Superseded by tb37 below** — every
  item in that "out of this slice" list except fall damage/height-derived bonuses (deliberately
  still out) is now built.
- **Pass E (in progress, supervisor-driven)** — the view catches up to elevation. `ResolutionPlayer.
  _world_anchor` reads `UnitGeometry.true_height_for_cell` instead of hardcoding Y=0.0, and the new
  `&"climbed"`/`&"hopped_down"` log events (both now carrying the same `"path"` shape a `move` event
  does) route through the exact same `_play_slide` machinery — a climb or hop-down plays as a real
  vertical slide with no dedicated animation code. `HitVolumeView`'s team marker and facing wedge
  offset by `unit.height`. `BoutInjector.force_climb`/`force_hop_down` (+ matching debug-panel
  verbs) let the supervisor trigger either action live — no AI path queues them yet.
  **Root-caused and fixed a "no visual change on raise" bug:** `BoardView`'s ground was one flat
  `PlaneMesh` for the whole grid, never reading `Grid.level` at all. Replaced with `_build_terrain`
  — one flat top quad per cell at its own real height, plus vertical riser quads between
  differently-elevated orthogonal neighbors, a stepped XCOM-style terrace (supervisor's own call
  over a smooth heightmap). `_build_grid_lines` got the same per-cell treatment as a follow-up
  (it was still one flat mesh at a single world height even after the ground itself went per-cell)
  — each cell now draws its own complete border at its own height, so a riser boundary frames each
  side's own step instead of one line cutting through it.
  **Level precision widened, supervisor's explicit choice over two smaller alternatives:**
  `Grid.level`/`Unit.level` go from `int` to `float` — genuinely arbitrary elevation, not just whole
  levels plus a ramp's own fixed `+0.5`. `Pathfinder.MAX_CLIMB_LEVELS`/`MAX_HOP_DOWN_LEVELS` become
  real height caps; climb cost scales proportionally to rise (`CLIMB_COST * rise / LEVEL_HEIGHT`)
  instead of a flat per-level charge. `HopDownAction`'s drop-distance check now goes through
  `Unit.height`/`true_height_for_cell` (ramp-aware) instead of raw levels, converging with
  `ClimbAction`'s own convention. **Real bug found during the level-precision audit, not just
  plumbing:** `ShotPlane.build`'s cover/blocker projection used `grid.get_level(cell) *
  LEVEL_HEIGHT` directly, missing a RAMP tile's own `+0.5` rest offset that `BoardView._spawn_
  blocker` already rendered cover at — a hit on ramp-standing cover could land somewhere the
  rendered box never occupied. Fixed to read `UnitGeometry.true_height_for_cell` like the unit
  projection just above it already did.
  **Cell picking fixed too, a pre-existing gap the terracing exposed rather than caused:**
  `BoardPicker.cell_at_ray`/`plane_hit_t` (taskblock03 D1, predates multi-level entirely) always
  intersected a fixed `y == 0` plane — correct until a cell's own real top face could move off world
  0. Supervisor: "mousing over a cell requires you to mouse over the base of the terrain, not the
  top." Both now take an optional `grid` and iteratively resolve against the real terrain (guess a
  height, find the crossing, look up that candidate cell's own real height, repeat, capped at 4
  passes so a ray skimming a riser boundary still terminates); `grid` defaults to null, so every
  flat-board caller is unaffected. `TacticsController`/`SpectatorOverlay` thread their real grid
  through at every hover/click/debug-panel-pick call site.
  **Still open, per `PLAN.md`:** the camera at height and the wall cutout against elevation, both
  needing the supervisor's own eyes, not headless-verifiable.

**Multi-level: elevation reaches the game (tb37, docs/PLAN.md)** — tb36 built the geometry and left
it wired to nothing; four passes make level mean something. Same "one seeded full-mission bout,
diffed byte-for-byte" proof as tb36 for Passes A–C (an all-level-0 bout can't observe any of this);
Pass D's own `MapGen` change necessarily reshuffles the bout's own generated map, so its seed was
re-picked (12369→12373) instead — the test file's own established convention for exactly this kind
of change, documented five times over in its own header before this one.
- **Pass A** — real muzzle height and vertical direction threaded through all six `ShotPlane.build`
  callers (`AttackAction`/`BurstAction`/`LineOfFire`/`Overwatch`/`Suppression`/`TacticsController`),
  replacing each one's own hardcoded flat `Vector3(x, 0.0, y)`. New `ShotPlane.elevation_for()` is
  the one shared helper every caller now builds its plane from (real level DELTA between origin and
  target cells, never a shooter's raw muzzle height against a target's raw ground height — the
  former cancels correctly under a uniform raise, the latter would double-count the shooter's own
  above-ground muzzle offset). `ShotPlane.build`'s tb36 `_shear` step is now opt-in (a new `shear:
  bool` param, only `resolve_ray` sets it) — it was silently correct only because no other caller
  ever passed real elevation before this pass; once they did, unconditional shear broke every
  caller besides `resolve_ray`. **Real bug found and fixed, not just plumbing:** `DamageResolver.
  _find_next`/`resolve_shot`/`_resolve_slide` assumed a dartboard aim point's height was always
  anchored at depth zero (true only for a ricochet's own fresh continuation plane) — a first hop's
  aim point sits at the TARGET's own real depth instead, so every elevated first-hop shot silently
  resolved to nothing at all until a new `point_depth` anchor was threaded through the whole chain.
- **Pass B (BR36.01)** — fixed at the source: new `PartGraph.walk_with_joints()`/`Shell.
  all_parts_with_joints()` (NOT a change to `walk()`/`all_parts()` themselves — those back
  `living_parts()`'s hp>0 filter, and a joint handle's own hp defaults to 1 and is never touched by
  joint damage, so repurposing them would make every unit's own joints read as permanently-living
  parts). Used by all six self-exclusion call sites and by `DamageResolver._body_of`'s own ricochet
  continuation exclusion. **Live-fire finding:** the seeded bout diverged after this pass alone,
  isolated to the ricochet fix — a shot that deflects off a body could previously re-hit that SAME
  body's own joint region at point-blank range instead of continuing its flight, reachable at level
  0 all along, not an elevation-specific bug.
- **Pass C** — `Pathfinder.move_cost` becomes an edge cost (`from`, `to`), not a per-destination one:
  a new `Enums.TerrainType.RAMP` is ordinary pathing regardless of level delta (1 MP, no special-
  casing); climbing up with no ramp is capability-gated (new `Shell.can_climb()`, an open `CLIMBER`
  tag nothing authors yet) at 4 MP, capped at 1 level; dropping down with no ramp is always legal up
  to 2 levels at a flat 1 MP, no capability gate — the deliberate asymmetry makes one-way routes for
  free. Threaded through every construction site tied to a specific mover; `MapGen`'s own internal
  connectivity check stays at the default (cannot climb) on purpose. tb36's own "Pathfinder ignores
  level" acceptance test is deliberately now false, replaced.
- **Pass D** — new `Unit.height: float`, the real continuous world height (`UnitGeometry.
  true_height_for_cell`: `level * LEVEL_HEIGHT`, plus a fixed `+0.5` on a `RAMP` tile — a ramp's own
  `Grid.level` is authored at its LOWER endpoint, so resting on it is genuinely partway up) —
  `Unit.level` stays the discrete int gating decisions only. New `ClimbAction` (capability-gated,
  4 MP/level or 2 MP/half — the half case is a climb launched from a ramp tile) and `HopDownAction`
  (no capability gate, flat 1 MP, legal to 2 levels) as real queued actions. `MapGen` authors real
  elevation for the first time: a seeded fraction of rooms raised one level, each connected to the
  surrounding network by exactly one `RAMP` tile, backstopped by a general `_repair_stranded_
  elevation` flood-and-flatten pass (a raised room's single ramp can still get sealed by ordinary
  scattered cover landing on its approach tile, or by a wide corridor serving two OTHER rooms
  crossing through it — rather than chase every such topology by hand, anything a non-climbing
  `Pathfinder` can't reach from a real anchor gets flattened back to level 0). No deliberate
  climb-only pockets authored this pass. Height-derived combat bonuses deliberately NOT added — the
  "a shot from higher ground resolves against more of the target" claim is read back and asserted
  (`test_a_shot_from_higher_ground_resolves_against_more_of_the_target`), confirming it's already
  emergent from Pass A's own geometry, matching the taskblock's own explicit instruction not to
  author a bonus on top of it. **Out of this slice, staying that way:** fall damage/knockdown on
  deep drops, parts/perks raising the climb cap, ladders as authored content, arc'd shots and
  thrown-weapon height advantage, no AI path yet queues `ClimbAction`/`HopDownAction` and neither
  integrates with `MoveAction`'s own mid-move overwatch hook, view-layer elevation correctness
  (Pass E, fenced for the supervisor, not started).

**Floor and terrain become parts (tb38, docs/PLAN.md)** — the tb31 wall move, generalised: everything
walkable is a placed `Part` now, not a terrain code. Same "one seeded flat bout (all level 0, no
ramps), diffed byte-for-byte after every pass" guard as tb36/37; ramp-carrying content is
deliberately excluded from that guard and covered by its own dedicated fixture instead.
- **Pass A** — the placement model, consumed by nothing. New `Surface` (part + real world height +
  facing) and `Grid.surfaces` (`Vector2i -> Array[Surface]`, the same container shape
  `field_items` already established) sit alongside `terrain`/`level`, which stay authoritative. New
  `GridPlacement` is the attachment grammar: a part attaches downward (`GROUND` in its own
  `attaches_to`) only to a cell with no surface yet, or sideways to a free, type-matching `Socket` on
  an orthogonal neighbour's own surface — reusing `PartGraph.is_legal_attachment`/`attach` verbatim,
  never a parallel legality check.
- **Pass B** — `MapGen` authors two flyweight floor parts (`ship_floor`, `ramp`) onto every non-VOID
  cell, derived from the just-finished grid rather than rewriting the carve/ramp/repair machinery's
  own internals (the BSP carve legitimately re-visits the same cell more than once, which the
  attachment grammar correctly refuses a second time — `_author_surfaces` runs once, last, mirroring
  the finished terrain/level instead). A `VOID` cell gets no surface at all — "unfloored," not a
  terrain code.
- **Pass C** — height and pathfinding now read a cell's own placed surface, not `Grid.level`/terrain
  directly (`UnitGeometry.true_height_for_cell`, `Pathfinder`'s walkability/move-cost gate). Ramps
  become a real two-tile, 22.5° profile (`+0.5` level per tile, replacing tb37's one-tile 45° rise) —
  `MapGen._connect_with_a_ramp` places an inner (room-bordering) and outer tile with a shared facing;
  new `RampGeometry` pins the settled low/high/lateral edge heights (0 / +0.5 / +0.25), built and
  tested even though nothing renders it yet. Partial climb MP rounds up (a 1.2 MP climb charges 2).
  **Real bug found and fixed:** `_repair_stranded_elevation` never flattened a stranded `RAMP` tile,
  only a stranded `OPEN` cell — invisible under tb37's model (a ramp's own authored level was always
  0), exposed once the corrected model gives the room-bordering tile a genuinely non-zero level; now
  reverts a stranded ramp fully to plain ground. `test_full_mission.gd`'s seed re-picked
  (12373→12383) — the two-tile ramp reshapes which rooms get ramped, the same established pattern as
  every prior generator-reshaping re-pick.
- **Pass D** — scope revised by the supervisor mid-taskblock: not the `Grid.level`/`TerrainType`
  retirement itself (confirmed blast radius: 14–17 production files, 36–37 test files still read the
  pre-placement model directly), but making that retirement safe to run as its own follow-up block.
  New `GridLegacyBridge` consolidates three previously-scattered `surfaces.is_empty()` fallback checks
  into one instrumented seam; a full-suite run tallies **4,318,367** hits across three call sites
  (`Pathfinder._base_cost`/`move_cost`, `UnitGeometry.true_height_for_cell`) via a GUT post-run hook
  (`tools/legacy_grid_bridge_burndown.gd`) — the retirement block's own real acceptance test is this
  counter reading zero, not a grep. **Out of this taskblock, staying that way:** the actual
  `Grid.level`/`TerrainType.{OPEN,WALL,RAMP,VOID}` deletion and the void→lore-only vocabulary sweep
  (both the named follow-up block, `PLAN.md`); catwalks/bridges as authored content; floors
  projecting into the shot plane (BR34.05 stays open — would break this block's own byte-identical
  guard).

**Legacy grid model retired (tb39, docs/PLAN.md)** — the follow-up block tb38 Pass D split out:
deletes `Grid.level`, `Enums.TerrainType`, and `GridLegacyBridge` outright, migrating every
remaining direct reader and fixture onto the real placement model. Full suite ends at 2120/2120,
`GridLegacyBridge`'s own burn-down counter at zero (down from tb38's 4,318,367 hits), and a
grep finds no surviving `Grid.level`/retired `TerrainType` value/`GridLegacyBridge` reference
anywhere, tests included.
- **Pass A** — replaces the old pinned-seed "does THIS scripted mission reach extraction" harness
  (`docs/SUPERSEDED.md` — six re-picks, every one a legitimate mechanics change absorbed as noise
  instead of a signal) with a completion-RATE sampling test (`test_full_mission.gd`) built on the
  same `BoutSetup`/`DeepStrike`/`BoutRunner` path a real "Simulate Bout" menu uses, never a
  hand-rolled turn loop. Measured baseline: 12 seeds at a 100-turn cap, 1-vs-1 AGGRESSIVE
  `a_brand_laborer` bouts, ~80% EXTRACTED; `MIN_COMPLETION_RATE` set to 0.5, well below the
  observed rate but low enough to catch a real collapse — flagged as a tunable, not a design
  number.
- **Pass B** — `MapGen` carves into a private `MapGenScratch` (its own local `terrain`/`level`
  arrays, never `Grid`'s public surfaces API) and emits real `Surface`s once, at the very end
  (`_emit`), rather than authoring onto a real `Grid` mid-carve the way tb38 Pass B did — carving
  legitimately re-visits the same cell many times (splitting rooms, re-cutting corridors, the
  emergency fallback corridor), which `Grid.surfaces`'s attachment grammar correctly refuses a
  second `GROUND` placement onto; scratch has no grammar to fight at all. `MapGenScratch.
  place_surface` is the one shared formula both `as_temporary_grid()`'s mid-generation
  reachability grids and `_emit`'s real final authoring use, so the two can never drift apart.
- **Pass C** — the three legacy-bridge readers (`Pathfinder._base_cost`/`move_cost`,
  `UnitGeometry.true_height_for_cell`) read real placed surfaces unconditionally now, no fallback;
  `GridLegacyBridge`'s counter confirmed at zero across the full suite before deletion. New
  `test/support/grid_fixture.gd` (`GridFixture.flat`/`place_floor`/`place_ramp`/`place_wall`)
  builds real placed `Surface`s for a fixture instead of hand-set terrain arrays — the single
  mechanism used to migrate roughly 55 test files off the legacy model, each proven to still fail
  for its own reason (anti-vacuity) after migration. `Pathfinder._terrain_costs`/`_min_possible_
  cost` and `CombatState.terrain_costs` retired outright as dead weight (only ever read inside the
  now-deleted legacy-bridge branch); `Pathfinder.new(grid, can_climb)` drops the parameter. New
  `Surface.is_ramp_at(grid, cell)` de-duplicates a ramp check `Pathfinder`/`ClimbAction`/
  `HopDownAction` each held their own private copy of. **Two real bugs found via migration, not
  cosmetic swaps:** `test_climb_action.gd`'s ramp-climb test was pinned against
  `GridLegacyBridge`'s superseded flat `+0.5` ramp offset (tb37) — migrating onto a real placed
  ramp `Surface` changed the asserted cost from 2 MP to 3 MP, matching `RampGeometry.
  STANDING_OFFSET` (tb38 Pass C's already-corrected value); the test itself was stale, not the
  game. `test_squad_control_overlay.gd`'s real-raycast click test broke once a wall got real 3D
  geometry — `PartPicker.hit()` can report a closer blocker hit than a unit hit, so a wall on the
  shooter/enemy's shared view-axis column could occlude a click; fixed by reorienting the fixture
  perpendicular to the camera's default view axis, not by weakening the click test.
- **Pass D** — full rename, not a partial one (explicit call): `Enums.TerrainType`
  (`OPEN`/`WALL`/`SPAWN_A`/`SPAWN_B`/`VOID`/`RAMP`) → `Enums.SpawnMarker`
  (`NONE`/`SPAWN_A`/`SPAWN_B`, an explicit `NONE = 0` sentinel since a fresh `Grid.spawn_marker`
  array already defaults every cell to `0`); `Grid.terrain`/`get_terrain`/`set_terrain` →
  `Grid.spawn_marker`/`get_spawn_marker`/`set_spawn_marker`; `Grid.level`/`get_level`/`set_level`
  deleted outright, no replacement field. `MapGenScratch` gets its own local `CellKind` enum
  (`UNCARVED`/`OPEN`/`RAMP`/`EMPTY`) — never reuses `Enums.SpawnMarker`. `TileInspection` gets its
  own local `PhysicalState` enum (`EMPTY`/`OPEN`/`RAMP`) for its tooltip classification, since
  `Grid`'s enum no longer represents any physical fact at all. `GridLegacyBridge` and
  `tools/legacy_grid_bridge_burndown.gd` deleted outright. Vocabulary sweep: "void" retired for
  the physical-absence state everywhere in code/comments (lore-only from here on, e.g. the ship
  setting); "empty"/"unfloored" instead — `MapGenScratch.CellKind.EMPTY`, `AsciiRender.
  CHAR_EMPTY`, `BoardView.EMPTY_BORDER_COLOR`/`EMPTY_FILL_COLOR`/`_build_empty_indicators`,
  `TileInspection.PhysicalState.EMPTY`. **Checked and found correct:** `MapGenScratch` never
  reaches for `Grid`'s public spawn-marker/blocker API outside `as_temporary_grid()`'s documented
  blocker pass-through; `map_gen.gd` touches `Grid.spawn_marker` only inside
  `_place_spawn_zones`/`_mark_zone`, confirmed by the file's own source-scanning acceptance test
  (`test_map_gen_touches_grids_spawn_marker_api_only_in_spawn_marking`). One test-suite-only bug
  found during the final full-run verification: `test_determinism_check.gd`'s own custom compare
  lambda still read `a.terrain`/`b.terrain` post-rename, a stale reference with no production
  impact (caught by the very first full-suite run after the rename, not shipped).

**"Void" retired from code entirely (tb40 Pass A, docs/PLAN.md)** — tb39 Pass D's vocabulary sweep
left the word alive in ~44 identifiers/comments and left open whether the rule was prose-level or
grep-strict; settled grep-strict, since "voidhulk" is the game's own lore term and a future grep for
it needs to return lore only. Four distinct categories, not one find-and-replace: `WorldPalette.VOID`
(the 3D environment's background color, not tile coloring) → `WorldPalette.BACKDROP`, naming the role
rather than the value; `MapGen._finalize_walls_and_void` → `_finalize_walls_and_empty` (and every
citing comment); the miss-tracer cluster in `ShotResolution`/`ResolutionPlayer` (`void_range`, "void
ray"/"void tracer"/"void endpoint") → `miss_range`/"miss ray"/"miss tracer"/"miss endpoint" — a
distinct concept from physical absence (how far a missed shot's tracer draws), renamed without
touching miss-tracer behavior, ranges, or the deflect path; ordinary-English "void" in comments
("floating in a void", historical quotes of retired spec language) rewritten in current terms, tbNN
provenance tags kept. New repo-wide guard test (`test_void_vocabulary_guard.gd`, modeled on tb39's
own `test_map_gen_touches_grids_spawn_marker_api_only_in_spawn_marking` file-scan pattern) walks
`src/`/`test/`/`tools/` and fails on any `\bvoid\b` outside a literal `-> void` return annotation —
the acceptance grep as a real test, not a one-off shell command. Full suite: 2121/2121.

**Camera framing across height deltas measured, found sound (tb40 Pass B, docs/PLAN.md)** — "measure
before changing anything," not a blind fix. A height-delta matrix (target displaced ±1/±3/±6 levels
from the shooter, real solver internals — `CameraOrbitState._solve_back`/`_both_fit`, not a
reconstruction from the returned {yaw, pitch, zoom} via trig round-trip, which loses enough precision
right at the fit boundary the solver deliberately lands on to read as a false failure that was never
real) printed as a table and checked against every hard invariant the pass named: both bodies fit at
every delta including ±6, the camera never sits below the lower of the two bodies (it's pinned at
`shooter.y + ATTACK_UP_OFFSET` regardless of target height, so it's structurally always at or above
the shooter), and the solved framing is continuous across the delta-crosses-zero seam (no explicit
height branch in `attack_framing`'s own algebra to discontinue at). The one real number: vertical look
angle grows from ~7° at the same level to ~25–34° at a 6-level delta on a 3-cell horizontal separation
— real, but bounded by the fit search itself, not runaway. **No code change** — per the pass's own
explicit instruction not to assume a defect exists because a pass is named for it; the tilt-angle
number is handed to Pass D as something for the supervisor's own eyes to judge, not fixed on
spec. `sniper_framing` centers the target at any height by construction (`pan_offset = target.center`,
no shooter dependency at all) — checked across the same matrix rather than assumed from the structural
argument alone. New pinned regression guard locks today's same-level solve exactly, so a future height-
anchoring change (if the supervisor ever wants Pass B4's midpoint-anchor idea) is provably a no-op on
a flat map. Full suite: 2125/2125.

**Wall cutout under elevation diagnosed, not fixed (tb40 Pass C, BR32.05)** — reasoned from
`wall_cutout.gdshader`/`WallLegibility.pixel_radius_for_tiles` source against two named cases, no
shader run (headless rendering never executes a fragment shader). Same root cause BR32.05 already
names (no real ray/line-of-sight test), but elevation opens a genuinely new way for the coarse
heuristic to misfire: the Euclidean-depth gate has always doubled as a correct "is this wall really
between camera and unit" proxy specifically because a flat map makes "behind the unit" and "farther
from camera" the same condition — elevation breaks that equivalence (an elevated wall can be
Euclidean-nearer to the camera than a low unit even while sitting horizontally behind it on the
ground plane). No new `docs/BUGS.md` entry opened — same fix BR32.05 already wants (a real ray test or
an angle-based gate) covers this case too; finding appended to BR32.05 instead.

**Checkpoint 8: a loadable multi-level scenario (tb40 Pass D, closes taskblock-37 Pass E)** — "hand
the supervisor a loadable scenario, not a description." Three hand-built scenarios (target above the
shooter, target below, a same-level control), one shared grid shape (`GridFixture` — the same call
`MapGen._emit` makes — a ground floor, a real 3x3 elevated platform, one real destructible wall
between them), loaded through the real `BattleScene.load_battle()` entry point and framed through the
real `CameraRig.ease_to_framing()` "entering aim" call (tb34 Pass D) — never a mock, never a
re-derived formula. `./checkpoint.sh 8` regenerates it; `tools/checkpoints/checkpoint_8.gd` is the
driver, following checkpoint 6's stills-only pattern (`run_visual_checkpoint.sh` case 8). A yes/no
checklist ships in the generated README, folding in Pass B's own measured numbers and Pass C's
finding as something to confirm, not hunt.

Fixed a real bug found wiring this up: `DeepStrike.assemble_reference_humanoid`/`assemble_from_preset`
never set `unit.height` themselves (every assembly path leaves that to the placer — same convention
`BoutInjector.set_cell_level` already follows) — `checkpoint_8.gd` reads it back from the real placed
`Surface` via `UnitGeometry.true_height_for_cell`, never assumed from the level passed to the grid
builder. Also caught and fixed a `BoutRunner` "squad controller(s) never assigned" error on load —
`CombatState.assign_all_to_human()` (tb31 Pass B's own "Control All Squads" shortcut) for a static
viewing scenario nothing should auto-advance.

**A real render surfaced BR40.01, a genuinely new camera-solver limitation no headless matrix could
have caught** — Pass B's own height-delta matrix only checks two bounding SPHERES against the FOV
cone, with no scene geometry in the harness at all to occlude against. Rendering the "target below"
scenario for real showed almost nothing: the solved camera position sits *past the far edge of the
platform the shooter is standing on*, because `_solve_back` pushes the camera backward far enough to
fit both bodies' angular footprint with no awareness that "backward" can walk it off a small stand's
own edge — the platform's own solid mass ends up between the camera and everything else. Filed as
`BR40.01` (`Active`, owner `CC`, since CC found and root-caused it, source not yet promoted), not
fixed — out of both Pass D's own scope (build a scenario, not fix the rig) and Pass B's own fence (a
missing occlusion check, not an anchor-height problem B4 would have touched). The checkpoint's own
"target below" screenshot doubles as this bug's live repro rather than being reshot to hide it.

Incidental: restored `out/checkpoints/06/` (`board_wide.png`/`cyborg_closeup.png`/
`twelve_arm_rig.png`/`README.md`) after an exploratory `rm -rf` clobbered them mid-session while
confirming this sandbox's GPU/X11 setup could run a visual checkpoint at all (`git checkout --`
recovered them byte-identical; flagged here since CLAUDE.md's own safety protocol is "run `git
status` before any command that could discard uncommitted work" and this one skipped that step).
Also found, in the process: both existing visual checkpoint scripts (`checkpoint_6.gd`/
`checkpoint_7.gd`) crash outright (`Identifier "UnitView" not declared`) — `UnitView` was renamed to
`HitVolumeView` in an earlier taskblock and neither script was updated, since visual checkpoints
aren't part of `run_tests.sh` and nobody had re-run them since. **Not fixed** — out of this pass's own
scope; `checkpoint_8.gd` uses the current `HitVolumeView`/`load_battle()` path throughout, so it
isn't affected, but 6 and 7 need their own follow-up pass before they'll run again.

**Failure model & joints** (tb09, joint depth tb26 D) — five failure modes: `MANGLE` (¼ residual
DT, stays attached), `DISABLE` (inert, attached), `DETONATE` (replaces cook-off), `FRAGMENT`,
`MELTDOWN`. Child-owned joint HP, no modes; depleting one drops the intact subtree. Joints aimable
(the precise-elbow shot). Spill-through: penetration damages the plate fully, spills
`damage − effective_dt` onward. **Joint HP default raised 1→3** (tb26 D) — a weaken-then-sever
gradient instead of any hit reaching a joint severing it outright; per-part overrides still win.
**Joint cladding** (`Socket.joint_cladding`, tb26 D) — an optional Part authored directly on the
socket owning the joint it protects; `BodyProjector` projects it as an ordinary Region in front of
the joint's own region, so it absorbs/deflects through the existing part/DT/spill machinery (tb20's
layered-body cladding model, reused verbatim) rather than a new damage mechanism.

**Armor, damage & weapons** (tb09/10/13/23) — DT from a `dt_curve` table; penetrate/stop-dead/
deflect by real geometry, incidence/reflection read a region's real 3D surface normal (tb23 C, not
a flattened one); ricochet retention `lerp(0.90,0.25,bend)`; crits bypass-or-bonus; bonus-pen as a
DT-discount (penetration only, negative for buckshot). Ammo owns the payload (`AmmoDef`); gun is a
modifier (`WeaponDef`). Cartridge chambering (family + length). Two scatters: dartboard (aim) vs
spread pattern (mechanical). Burst = N independent pulls, recoil accumulates. Recoil computed.
**Audited (tb19 H): burst-fire-sometimes-produces-no-shots** — the suspected cause (`is_legal`/
`apply` reading different `burst_size` sources) never existed; a 200-seed sweep against the real
`chaingun.tres` confirmed every pull always fires — the reported symptom is the chaingun's own wide,
outer-weighted scatter genuinely missing often, even on pull 0 before any recoil (a data/balance
fact, confirmed with the project owner, not silently retuned). New `&"burst_pull"` combat-log events
(hit/miss + running `landed_so_far` tally) make "did all N pulls execute" directly observable.

**Layered bodies & power** (tb20/22) — bodies as cladding/skeleton/organs; knowledge-gated occlusion
of internals (source stubbed to "known"); penetration traversal (DT attenuation, overpen = 0°
deflect, `hollow` flag, lodged-inside wounds); **wounds** as non-terminal repairable per-part state;
penetration-driven deflection resistance (closed the angle-lock stalemate); power drives AP through
an authored diminishing curve (tb20 F, revised tb22 B) with coring; the reaction window
(perk-gated, default none). A unit that can neither move nor act may voluntarily **shut down** —
inert, still occupying its cell/occluding the shot plane, excluded from turn order (tb22 C).

**Range** (tb19) — effective / max / min with a linear sub-1 accuracy band in the effective→max
range; discrete min-range failure (explosive duds); AI movement is range-aware. Internal-targeting
shots (tb20 B) were audited against this pipeline (tb20 G, confirm-only — no separate code path) and
confirmed to run through it unchanged: an internal aim just shifts `AttackAction`'s dartboard center,
so it inherits the same effective→max accuracy band and never bypasses range banding.

**Repair** (tb22 E) — `RepairResolver`/`RepairAction`, five authored battery parts + the Arc Welder,
repair-with-scrap (1:1, up to 3 HP per use, 4 AP; scrap's own resource id is the damaged part's
`material` field). Reachable via a right-click "Repair with Scrap" item and an action-bar Repair
button. **Partial**: logically complete and tested, but not yet reachable in natural gameplay — no
existing part's `salvage_yield` produces the `material`-field scrap namespace repair reads, since
that's a new id space kept deliberately separate from the existing `salvage_yield` categories
(`metals`/`organics`/`reactives`). A follow-up authoring pass is needed before a scavenged scrap pile
actually feeds a welder.

## Melee (tb25, keystone 1)

**Delivery** (tb25 A) — reach = `weapon_def.weapon_length` (free, no exposure) +
`Shell.shell_reach` (leanable exposure budget). A strike needing shell lean poses the torso
forward (`Poses.lean`, the same `ROOT_SOCKET_ID` seam `Poses.down()`/`prone()` already use) — no
melee-specific exposure system, the existing overwatch torso check fires against the leaned
geometry unchanged. Beyond `shell_reach + weapon_length`, a reach-gated step-in
(`MeleeDelivery.find_step_in_cell`) reuses `StepOutPlanner`'s own move-assembly structure.

**Resolution reuse** (tb25 B) — `StabAction`, a point-payload strike sharing
`ShotResolution.resolve_and_log_point`/`DamageResolver`/`ShotPlane`/`RangeModel`/`Dartboard`
verbatim with `AttackAction` (structurally a sibling, never a parallel resolver). Legality is
reach-gated (`MeleeReach.in_reach`, a real 3D distance via `UnitGeometry.bounding_sphere` — a
sword can't hit someone 1 up, a polearm hits at √2) instead of range/LoS-gated. The ranged
accuracy pipeline is reused unchanged — melee's own tight dartboard is point-blank range through
the existing curve, not a special rule.

**Three payloads, one deflect seam** (tb25 C) — `DamageResolver.resolve_shot` gained an additive
`deflect_mode` (default `&"ricochet"`, every prior caller unchanged): `&"slide"` (stab) retries
once against a laterally-nudged point on the same plane instead of ricocheting; `&"none"`
(slash/hold, per point) stops outright, no bounce. `SlashAction` — a line payload
(`MeleeLine.sample`, horizontal/vertical/45°, `slash_length` long) hitting everything along it; a
vertical line spreads along `Region.rect`'s own real-height axis (tb23) for free. `GrindAction`
(armed as action id `&"hold"`; the class name avoids colliding with tb19's own "defer to next
ally" `HoldAction`) — `weapon.burst` doubles as hit count, each hit's `bonus_pen` stacks raw and
uncapped (`base * i`), `DamageResolver`'s own existing PENETRATE spill cascade already gives
"continues through cladding" for free.

**Spherecast** (tb25 D) — `ShotPlane.disc_overlaps_rect` (radius ≤ 0.0 is exactly
`rect.has_point`, every point-only caller unchanged): a stab's own `weapon_def.stab_width` disc
can't thread a gap narrower than it, the same sniper gap-fall-through inverted. A stepping stone
to a real shapecast — the shape math lives in exactly one place.

**Suppression un-stubbed** (tb25 E) — `Suppression.resolve_opportunity_attacks` fires the
attacker's own real melee weapon (`ActionCatalog.provider_for(attacker, &"stab")`) through the
identical `ShotResolution` pipeline `StabAction` itself uses, replacing the flat unarmored stub
hit; gated on `state.is_preview` now that the outcome is RNG-driven, matching `AttackAction`.

**AI** (tb25 F) — PSYCHOTIC (prefers melee, closes to minimize distance, never flees) and TURTLE
(flees rather than melee — `Suppression.is_suppressed`-gated, otherwise an ordinary
cover-weighting planner) fold into `UnitAI`'s existing dispatch; `_preferred_firing_action_id` now
also recognizes `&"stab"` (purely additive), so AI weapon choice reads the same
`ActionCatalog` seam every other firing pick already does. The baseline "punch" (a POWER-capable
part providing its own `&"stab"`, no weapon needed) is proven at the engine level; authoring it
onto shipped content (and a real `shell_reach` per shell template) is unauthored balance work, not
invented here.

## Combat structure & AI

**Turn structure** (tb06, docs/09) — TACTICS/RESOLUTION re-entrant loop; `resolve_until →
COMPLETED|STOPPED(reason,refund)`, interrupt when the next action is illegal; overwatch (torso gate,
visible as a 30° slice, tb19) — the AI can now genuinely weigh and hold it, not just react to it
(tb24 C); one-stream combat log, folded into hierarchical action-level summaries at render time
(tb22 F). **Combat-log shot geometry in text, not just data** (tb28 C) — `ShotResolution`'s own
impact/miss logging (made public: `log_impact_result`/`log_miss_result`, were `_log_impact`/
`_log_miss`) folds the real origin/hit geometry `data` already carried (tb22/23) into `text` too, so
`out/combat.log` shows it directly — `LogEvent._to_string()` only ever rendered `text`, so the
geometry was invisible outside a live playback or a `data` inspection until this. `Overwatch._fire`'s
own separate, hand-rolled `&"impact"` event (no geometry, no crit/wound/destroy/salvage cascade at
all) now routes through the same shared path every other firing action uses — no parallel logging
system, and overwatch misses are logged for the first time. **Per-tile move facing** (tb16 A) —
`MoveAction.apply_stepwise` faces before each step, not once at the end (`FaceAction.face_for_free`
per tile, free); a curved or interrupted path faces correctly mid-move, and an interrupted move is
left facing its actual direction of travel at the interrupt point, not its start facing. **Round**
(tb17-1 A, audited and already correct — no code change needed) — `CombatState.round_number`,
incremented exactly when turn order wraps back to the front, not once per unit's turn; the boundary
future per-round effects and the Hold action (tb19 F) key off. **Hold action** (tb19 F) —
`HoldAction` defers a unit's turn to after the next ally acts, still within the same round; carries
all held AP/MP forward, regenerates none; available to AI and player — the AI holds instead of
taking a clearly bad action (e.g., facing uselessly when its own ally blocks the firing line).

**Resolution speed** (tb18) — `Matrix.personal_speed` (flat bonus to everything); unified
resolution-speed formula (lower resolves first); re-validating ordered resolver; initiative;
equal-speed simultaneity (`CombatState.simultaneous_group()` — a logic-level grouping query only;
turn order/`advance_turn()` still hand back one unit at a time, and skipping the inter-turn pause
during playback for a simultaneous group is a flagged `BoutRunner`/`ResolutionPlayer` follow-up, not
yet built); **Step Out** (auto-assembled orthogonal move/fire/return through the
resolver, dies-exposed on interrupt). Both legs are free — `MoveAction.free` costs no MP/AP either
direction, for the AI's own `StepOutPlanner` usage and the player alike (tb27 B2, docs/SUPERSEDED.md
— previously a deliberate "real cost, no discount" choice). The player's own Step Out flow now
matches the intended sequence: confirming a cell queues only the free out-leg and opens ordinary
aim mode from the stepped-out position (camera/dartboard follow the queued move for free via the
existing preview machinery); firing appends the free return leg; canceling aim mid-step-out undoes
the queued out-leg (tb27 B). **Queue panel** (`QueuePanel`, rebuilt BR27.08 — `docs/SUPERSEDED.md`)
— the in-turn readout of a unit's own queued actions; each entry is a real row (What/AP/MP labels)
carrying its own "Resolve" button, wired directly to `TacticsController.resolve_to_marker(index)` —
resolves the queue's prefix through exactly that entry on press, no separate select-a-row-then-press-
a-global-button step and no persisted marker state. Rebuilt this way after the prior `Tree`-based
mechanism (click a row to set a marker, a separate global button to fire) could never be made to
reproduce a real, supervisor-confirmed "nothing happens at all" failure in this environment — replaced
with the same primitives every other reliable click surface in this codebase already uses.
**Resolving to an earlier point keeps what's queued after it** (supervisor follow-up,
`docs/SUPERSEDED.md`) — `SelectionController.keep_queue_suffix()` replaces the old `reset_turn()` call
`resolve_to_marker()` used to make after a partial resolve, which discarded the entire remaining queue
along with the prefix that actually resolved. The same queued `CombatAction` objects replay unmodified
against the just-updated real state — safe because every action already re-validates itself against
whatever `state` it's actually handed (docs/09), not a captured reference. **A `MoveAction`'s own row
text drops its unbounded path** — `CombatAction.short_describe()` (new, defaults to `describe()`
unchanged for every other action) is what a queue row actually shows; `MoveAction` overrides it to keep
everything `describe()` already says except the `path=...` term (`"MoveAction(unit=%d)"`, matching every
sibling action's own `ClassName(unit=%d, ...)` style), since that term alone — not the row's format in
general — was what stretched the readout across the whole display. The full path still reaches the
hover tooltip, as an extra "Detail" row (`TooltipBuilder.for_queue_entry()`).

**AI** (tb14/16/17-1/24) — `UnitAI.plan_turn`, deterministic, human & AI emit the same queue,
firing derived from the same `ActionCatalog.build_firing_action` seam a weapon's own
`provides_actions` governs for both (tb24 A/B — `is_legal` enforces it as an engine rule, not a UI
convention); the AI can weigh other provided, non-firing actions the same way, overwatch the first
consumer (tb24 C). Playstyles: AGGRESSIVE (never holds overwatch), COVER_SEEKER (only from cover),
SKIRMISHER (~5), MARKSMAN (~7+, prefers it), PSYCHOTIC (prefers melee, closes to minimize
distance, never flees), TURTLE (flees rather than melee — tb25 F). Line-of-fire safety (won't
shoot through allies); reachability-aware targeting. **Suppression** (tb19 E, un-stubbed tb25 E) — a
`two_handed` weapon is illegal to fire while its wielder is adjacent to a living enemy
(`Suppression.blocks_weapon`), and leaving an adjacent tile draws a free melee attack
(`resolve_opportunity_attacks`, a flagged stub hit until tb25 E gave it a real weapon); this alone
keeps the AI from crowding into face-to-face range with no melee system built. **Engagement
positioning** (tb27 C1) — when no reachable cell has real line
of sight this turn, `_engagement_score` now scores primarily on `LoS.obstruction_count` (opaque
cells between a candidate cell and the enemy), which strictly decreases as a unit works around a
corner even while raw distance plateaus — a real, measured improvement (a 60-real-map sweep's
never-reaches-LOS seed count dropped 16/60 → 8/60), not a complete fix: a corridor requiring
temporary backward movement before a gap appears can still trap this per-turn greedy scorer.
**Line of fire, not line of sight** (tb33, `docs/SUPERSEDED.md`) — fixed the corridor case above and
closed BR30.10's own 81%-into-walls finding in one stroke: `LineOfFire.has_clear_line_of_fire`
(new, `src/logic/line_of_fire.gd`) resolves the exact same `ShotPlane` a real shot fires through
(sharing one first-hit resolution with the refactored `_ally_in_firing_line`), rather than trusting
`LoS.has_los` — opacity-only by design, and blind to the cover-Part walls became (tb31 C). Threaded
through `_plan_ranged`'s fire gate (`clear_from_here`/`final_blocked`) and `_engagement_score`'s own
line check (`any_reachable_has_los` → `_has_lof`, `NO_LOS_PENALTY` → `NO_LOF_PENALTY`); a
weapon-range prefilter (`_any_reachable_has_lof`) keeps the added `ShotPlane.build`-per-cell cost off
cells that can't fire anyway (BR26.02). **Closes BR32.10** (AI stuck on U-shaped/concave maps): when
nothing reachable this turn has a shot, `LineOfFire.approach_path` Dijkstra-floods (new
`Pathfinder.nearest_matching`) to the nearest cell that would, truncated to this turn's own MP budget
(new `Pathfinder.truncate_to_budget`) — the fallback re-fires turn over turn until a reachable cell
genuinely has one, unsticking the exact "moves away before it gets closer" detour a per-turn greedy
scorer structurally can't make. `LoS`/`LoS.obstruction_count` are unchanged and still opacity-based —
only the AI's own fire/standoff *gate* moved from sight to fire; genuinely sight-based questions
(`is_covered_from`) still read `LoS`.

**Depth floor on shot resolution** (tb35 Pass B, BR34.06/BR27.02) — `ShotPlane.build`'s own
depth-sort has no floor at zero, by design (a region behind the ray's own origin is legitimately
present, the aim window reads it) — but `LineOfFire._first_hit_excluding`, `ShotPlane.
resolve_projectile`, and `DamageResolver._find_next` are three independent "walk the depth-sorted
plane, return the first match" implementations that all inherited that same unfloored sort with no
floor of their own, so a wall many tiles behind the shooter (still in the plane on purpose) could
sort first and win almost every resolution. This was BR27.02's own logged 12/12-chaingun-pulls-
DEFLECT-on-a-wall-behind-the-shooter case, and — post tb31's dense walls — the same defect made
`has_clear_line_of_fire` read "no clear line" almost everywhere, which was BR34.06 (the AI passing
every turn in bouts). Fixed by flooring the RESOLVING path only, opt-in (`resolve_projectile` gained
a `floor_at_zero` parameter, default false — every raw/body-local-plane caller is unaffected;
`self_obstruction`/`region_at` opt in; `resolve_ray` and `_find_next`, always fed a real
shooter-anchored plane, floor unconditionally) — `ShotPlane.build`'s own sort and the aim window's
`window_depth` reading are untouched. **Second, distinct fix once LOF was genuinely correct:**
`LineOfFire.approach_path` (tb33 Pass B) is capped at `weapon.max_range + APPROACH_MARGIN`, so a unit
starting genuinely far from the nearest real LOF cell still found nothing and held. New
`LineOfFire.closing_path` — real A* toward a cell next to the enemy, no LOF requirement — is the
fallback for that case; deliberately not a greedy per-turn distance scorer (reproduces BR32.10's own
concave-wall freeze; real A* just routes around).

**AI decision log** (tb35 Pass A1) — `plan_turn` was unwatchable: "the AI is broken" and "the game is
slow" were supervisor adjudications, not greppable evidence. New `AiDecisionLog.emit` (`src/logic/ai/
ai_decision_log.gd`, kept out of `unit_ai.gd` itself to stay under its own file-length cap) writes one
`&"ai_decision"` event per unit-turn through the ordinary `CombatState.combat_log` — which branch
`_plan_ranged` took (`fired_in_place`/`repositioned`/`approach_fallback`/`closing_fallback`/
`no_lof_no_route`/`stepped_out`/`overwatch`), whether it fired, and if it held, why
(`no_weapon`/`ally_in_line`/`no_clear_lof`/`out_of_range`/`other`) — read back off a `MemorySink` in
tests, the same convention `test_combat_log.gd` already uses. A diagnostic side-channel only, never
read back by any planner, so `plan_turn`'s own purity/determinism contract is untouched.

**Two framerate dumps, in the combat log** (tb35 Pass A1, BR26.02) — "the reason this bug has
survived three passes is that CC cannot see a framerate" gets an actual fix: **Aim FPS**
(`TacticsController._dump_aim_fps()`, once per `_enter_aim_mode()` transition, 200ms later, past the
entry transient) and **Turn FPS** (new `FpsDumpSink`, watching `combat_state.combat_log` for
`&"turn_start"`, wired in `BattleScene.load_battle()` alongside `file_sink` so every bout gets one
regardless of overlay) both emit `&"fps_dump"` events with a `context` tag, greppable straight out of
`out/combat.log`. `Engine.get_frames_per_second()` only means something inside a real running client,
so the headless coverage here only proves the plumbing fires on schedule — the actual before/after
numbers still want a live session.

**Per-turn LOF memoisation** (tb35 Pass A3, BR27.09) — `_any_reachable_has_lof` and
`_engagement_score` each independently resolved `LineOfFire.first_hit` for the same (unit, enemy,
cell), doubling the real `ShotPlane.build` cost of every reposition-or-hold turn. New
`LineOfFire.cached_first_hit` (opt-in `Variant` cache param, `null` default — every other caller
unaffected) backs one per-turn `Dictionary` threaded through `_plan_ranged` →
`_any_reachable_has_lof`/`_pick_engagement_position`/`_engagement_score`/`_ally_in_firing_line`, so
each cell resolves once. Measured on a real 60-turn bout: average reposition/hold-turn cost dropped
2023ms → 974ms. Not a full fix for BR27.09 — the remaining per-cell `ShotPlane.build` cost is real and
this memoisation can't remove it further without a bigger algorithmic change.

**The `body is Unit` / `Grid.blockers` assumption audit** (tb35 Pass C) — tb31 C turned walls into
full-height, dense `Grid.blockers` Parts; this pass checked every place written for the old
sparse/small-cover shape. **Audited and found correct as-is** (the `is Unit` distinction in each case
does exactly what it should regardless of wall density): `attack_action.gd`/`burst_action.gd`/
`stab_action.gd`'s own muzzle self-obstruction redirect (a static obstruction, cover or wall, should
redirect aim onto it; an ally blocking should not — that's the player's own informed risk, not this
codebase's call); `shot_resolution.gd`'s `target_unit_id` falling to -1 for a non-Unit body (every
consumer already treats -1 as "no unit hit," unaffected by what kind of non-unit thing it was);
`UnitAI._ally_in_firing_line`'s own `region.body is Unit` check (asks specifically "is an ally
blocking," correctly false for a wall — wall-blocking is `has_clear_line_of_fire`'s own separate,
already-correct concern); `Pathfinder.move_cost` (an O(1) dict lookup, density-proof by construction);
`tile_inspection.gd` (a single-key lookup, same reason); `los.gd`/`inspect_panel.gd`/
`world_palette.gd` (no `grid.blockers` reads at all).

**Fixed:** a destroyed wall (or any blocker) never cleared `grid.opacity` — `Pathfinder` already
treated a destroyed blocker as passable (its own `hp > 0` check), but `LoS.has_los` kept reading the
same cell as permanently opaque forever, since nothing at combat time ever touched the `opacity` array
map-gen set once. New `Grid.cell_of_blocker(part)` (a reverse lookup, only ever run on the rare
destruction event, never per-frame) backs a new clear in `DamageResolver.
_resolve_destruction_consequences` — a no-op for ordinary destructible cover, whose own cell was never
opacity-flagged to begin with. **Fixed:** `BoardView._build_wall_indicators`'s own flat gray-tile-plus-
cross marker checked `TerrainType.WALL`, a condition confirmed (via a real generated bout) to never
match any cell on a live map anymore — `MapGen._finalize_walls_and_void` gives every real, exposed
wall cell `OPEN` terrain plus a genuine blocker Part instead. Not a live-game bug (the wall's own mesh
already makes "can't walk here" obvious), but the loop's own doc comment was stale and the condition
could still double-draw on a hand-authored/debug grid that sets `TerrainType.WALL` directly — guarded
against that narrow case and corrected the comment.

**Re-derived, not fixed: BR32.07** ("burst cannot aim at a wall"). Traced the full aim-entry chain
(`TacticsController.click_cell` → `PartPicker.hit` → `_enter_aim_mode` → `aim_state()` →
`AimController.resolve()` → `ShotScatter.for_shot()`) end to end — every step is generic over action
id, and a new regression (`test_tactics_controller.gd::
test_arming_burst_and_clicking_a_wall_enters_aim_mode`) confirms arming burst and clicking a real wall
cell correctly enters aim mode headlessly. No code-level break found; recommends a live re-check
before further digging (the same class of headless-vs-live gap BR27.08 hit).

**Found, not fixed — logged as BR35.01/02/03:** `PartPicker.hit()` scans every `grid.blockers`/
`field_items` entry on every mouse-move hover, not just cells near the ray (real perf cost, now that
blockers number in the hundreds); `SpectatorOverlay`'s tile-inspect click resolves via ground-plane
math alone, with no check for an intervening wall — a click can silently inspect a cell hidden behind
one; every debug-panel verb application triggers a full `sync_board_view()` rebuild, not just ones
that can touch `blockers`/`field_items`. All three have a clear fix shape but real risk if rushed
(geometry correctness for the first two, an exact debug-verb-id list for the third) — left open rather
than guessed at.

**BR33.01 left untouched** — no supervisor policy call has been made yet on the aim-scroll-cycles-
walls question; per the taskblock's own instruction, not guessed at.

**Fixed: the wall-cutout feed-refresh boundary (tb35 Pass D, BR32.01/03)** — `BoardView.
wall_cutout_units` was set in exactly one place in the whole codebase, `SquadControlOverlay._on_
battle_loaded()`; `SpectatorOverlay` (the default overlay every fresh bout starts in) had no handler
that ever touched it, and `BattleScene.load_battle()` itself never re-pointed it either. Starting or
reloading a bout while staying in Spectator mode left the feed pointing at whatever it held before —
null on first launch, the previous bout's own orphaned units on any later one — exactly "a stray
cutout with no unit there" (BR32.01) and "carried over from a previous bout" (BR32.03, the same
defect, not a separate one). Also explains why clicking "Assume Control" always fixed it: that's the
only path that ever installs a real `SquadControlOverlay`, the only code that ever set the feed.
Fixed by moving the assignment into `BattleScene.load_battle()` itself, once, for every overlay.
**Root-caused, not fixed: BR32.04** (cutout snaps to the destination ahead of the move animation) —
confirmed `ResolutionPlayer._play_slide` animates a unit's own `HitVolumeView.position` directly every
tween tick, while `update_wall_cutout()` recomputes from the model's own already-resolved `unit.cell`,
never reading the view's own current transform. Fix direction is clear (a per-unit "current display
position" `Dictionary` written by the tween, read before falling back to the logical cell) but
correctly scoping its own lifecycle wants a dedicated pass, not a rushed one here.

**Mission & meta** (tb07, docs/07) — no win state (EXTRACTED/TERMINATED/STRANDED); enemy count never
an ending; gather→extract/terminate; asymmetric, whole-squad, visible extraction — the player squad
must get everyone to a team-coded tile, can't self-extract early (tb22 A); bout-setup places each
side's extraction tiles on the *opposing* side, forcing the teams through each other (tb23 E1);
pseudo-persistent hulks; loot overlap; deep strike.

**Squad control gets an `UNASSIGNED` state** (tb31 B) — `SquadController` was a hard `{HUMAN, AI}`
binary, so `CombatState.controller_for()`'s fallback had to silently pick a side (BR30.09's root
cause). `UNASSIGNED` is now the zero-default; `BoutRunner._init()` hard-errors if any squad on the
board is still unassigned when a runner is built, so an ill-defined bout can't run at all.
`assign_all_to_human()` / `assign_rest_to_ai(human_squads)` are the visible authoring shortcuts that
replaced the old hidden HUMAN default; `_seed_battle` assigns explicitly.

**Every action arms from the bar the same way** (tb31 D) — `ActionDef.requires_target: bool` (two
shapes) became `Enums.TargetingMode` (`BOARD`/`NONE`/`PART_PICKER`); `ActionBar` dispatches by mode, so
overwatch (`NONE`, its first real UI call site) and repair (`PART_PICKER`) reach the bar directly
instead of bolted-on `SquadControlOverlay` buttons. `ActionCatalog.ap_cost_for` extended to
overwatch/repair — each had the same fixed-cost-vs-part-cost drift BR30.11 fixed for burst, caught on
first wiring.

**Wall occlusion cutout shader** (tb32 A, supersedes tb31 C — `docs/SUPERSEDED.md`) — replaces tb31 C's
one-wall-at-a-time GDScript alpha-blend
(`BoardView.WALL_FADE_ALPHA`/`_set_wall_alpha`) with a lit, per-fragment dithered `discard`
(`wall_cutout.gdshader`, one shared `ShaderMaterial` for every wall). `BoardView.update_wall_cutout()`
projects every unit in `wall_cutout_units` to a screen position/depth/tile-derived pixel radius
(`WallLegibility.pixel_radius_for_tiles`, new pure helper) and feeds them as uniforms each frame; the
shader decides per-fragment whether to discard. Cuts around every unit at once now, not one focal unit;
spectator never feeds any units, so the cutout simply never fires there (unchanged, flagged as trivial
to wire later). **Friendly fade in aiming view** (tb32 B, redesigned after live testing —
`docs/SUPERSEDED.md`) — a friendly
standing between the camera and the active (shooter) unit fades gray. The first version drew a
separate ghost overlay in `BoardView`, leaving the friendly's own real `HitVolumeView` fully opaque
underneath it — confirmed live to read as "something faint happening," not an actual fade. Redesigned
to fade the friendly's own real body instead: `HitVolumeView.set_occlusion_faded()` swaps every body
mesh instance's `material_override` to a translucent gray (never touching the ground marker/facing
wedge, `set_active_turn()`'s own concern, or `highlight_part()`'s `mesh.material.next_pass` chain,
which lives underneath, untouched). The occlusion decision itself moved to `BattleScene._process()`
(the one place holding both the live camera and every `HitVolumeView`), reusing Pass A's
`occludes_on_screen`/`pixel_radius_for_tiles` unchanged against `BoardView.aim_active_unit`; friendly-
only, never the active unit, only while `tactics.aiming_at != null`.

**`PartPicker`: target anything, not just enemies** (tb32 C) — a click can now resolve to a non-unit
Part (`Enums.HitKind.PART`, new): scatter cover, a wall, a downed bot's shell, a loose field item, not
just a live unit's own body (`Enums.HitKind.UNIT`, unchanged) or bare ground (`CELL`). `PartPicker.hit()`
generalizes `UnitPicker` (still the unit-ray-test path underneath) to also ray-test every
`Grid.blockers`/`field_items` Part via the same boxes `BoardView` renders
(`UnitGeometry.assembly_placements`); `TacticsController.aiming_at` is now an `AimTarget` (unit-or-part
+ cell, `ShotPlane.center_of_part`/`UnitGeometry.bounding_sphere_for_part`/`CameraRig.
ease_to_attack_framing`'s new sphere-Dictionary signature all branch on it) so the dartboard/camera
frame a Part exactly like a Unit. This reaches all the way into RESOLUTION, not just the click: `Attack
Action`/`BurstAction.is_legal()` no longer hard-require a live unit at `target_cell` — a blocker/field-
item Part (`Grid.shootable_part_at`) is enough — `apply()` re-derives whichever is actually there and
computes the aim point via `center_of_part` when there's no unit. Ranged weapons only this pass;
`Stab`/`Slash`/`GrindAction` still require a real target Unit (`MeleeReach.distance_3d` needs one) — see
PLAN.md's own follow-up note.

## Tooling, data & view

**Data layer** (tb10/11) — all definitions in `.tres`; `DataLibrary` (res:// builtin + user://
override, user wins); `DataValidator` (named errors, shared editor-save + game-load). Resource
Editor: standalone-scene tuning tool, survives reboots, writes user://, tree-table with
sort/filter/dropdowns/undo/rotating preview. (Layout/resize/column/preview bugs fixed
2026-07-18 in 713f411/1bff29b/944d019 — see BUGS.md; landed outside the taskblock cadence, logged
here retroactively.)

**Test suite** (tb12) — audited for over-granularity (1,026 funcs, 38% single-assert) by measuring
directly rather than assuming: only 3 genuine same-setup clusters existed
(`test_grid`/`test_map_gen`/`test_selection_controller`, 7→3 funcs, 0 asserts lost) — the taskblock's
own ~394→~120 merge estimate did not hold at this suite's actual granularity, and the remaining
single-assert funcs are correctly-scoped distinct scenarios, left untouched rather than force-merged
to chase the estimate. **Audited and found current:** `test_body_projector.gd`/`test_damage_resolver.gd`
(~25% of test LOC, covering systems rebuilt box→per-face→ray and exposure-table→DT→failure-modes)
read test-by-test against the live projector/damage model — no dead-shape test survived from a
replaced model; one redundant pair folded into its survivor instead of deleted.
`test_data_migration_losslessness.gd`'s hand-typed `EXPECTED_PARTS`/`EXPECTED_MATERIALS` fixtures
(previously checked only against themselves) re-verified against the real pre-migration
`DeepStrike.default_part_pool()`/`MaterialTable.default_table()` output, restored from git history —
0 mismatches across 22 parts/8 materials. Assert count unchanged throughout (2333→2333).

**View** (tb15/22, docs/10/10a) — 3D HL2-era; render is hitbox; two palettes; attack camera solves
framing (orbits target); poses = socket overrides; `HitVolumeView` permanent; per-part `mesh_scene`
(mixed assemblies). One `BattleScene` + swappable control overlays. Found and fixed a real ordering
bug in the merge (tb15 A): `BattleScene._ready()` used to call `new_battle()` (which emits the
session-start log line) before any overlay — and its log sink — existed to catch it, silently
dropping the first on-screen log line; fixed by installing the overlay first and having it react to
a new `battle_loaded` signal, which `load_battle()` now emits synchronously before session-start.
**Fix: two playback perf hitches (tb19 I)** — `ResolutionPlayer`'s per-frame tween callback re-ran a
full linear-scan unit/view lookup on EVERY FRAME of every slide/facing animation, now resolved once
per event; `refresh_unit_views()` rebuilt every unit's entire mesh subtree on every turn advance, and
`SquadControlOverlay._on_turn_ended()` called it three times per player turn (one fully redundant) —
new `LogPlayback.affected_unit_ids()` narrows the rebuild to just the units a turn's events actually
named. Playback animation
(slide/facing/shot-fade-to-tracer), animation-gated in the view only, tunable timings; every shot
and ricochet hop draws its own tracer at its real, fully 3D logged position, not one guessed
segment pinned to a constant height (tb22 D, real height tb23 D). **Ground-overlay height ladder**
(tb27 C2) — team marker / extraction tile / overwatch arc / facing wedge each hold a distinct,
deliberately-ordered depth band (`0.010 → 0.06 → 0.09 → 0.17`) instead of one marker bumped in
isolation per report; found and fixed a real, previously unreported co-planar pair (team marker vs.
extraction tile) no prior fix or test had ever checked. **Turn indicator** (tb27 D2, redesigned tb32 D
per BR27.07 — `docs/SUPERSEDED.md`) — originally recolored the active unit's facing wedge/team marker
to a distinct `ACTIVE_TURN_COLOR`; retired once the highlight was found landing on the wrong unit.
`HitVolumeView.set_active_turn()` now shows/hides the whole marker assembly instead — team marker AND
facing wedge together (the supervisor's own correction: "facing marker" meant the whole disk+wedge,
not the wedge alone) — for the active unit only, no recolor at all; presence, not color, indicates
whose turn it is. `BattleScene.refresh_unit_views()`'s `apply_highlight` parameter defers the flip
until after the resolution animation actually finishes (the ordering half of BR27.07 — the highlight
used to jump to the next unit mid-animation). **AP-gated action bar** (tb27 D3, fixed tb30 by BR27.05's
own fix below) — a slot the unit can't afford dims and refuses
to arm, reusing `ActionCatalog.provider_for`'s own `ap_cost`. **Camera reset after aiming** (tb27
D4) — `CameraRig` snapshots the pre-aim orbit state and eases back to it once aiming ends, via a
shared `_ease_to()` helper. **Wall tiles non-inspectable** (tb27 D5) — a wall click is a real
no-op, same posture as a miss; `InspectPanel`'s own null-root branch also resets stale isolate-view
state so it can never leak a live-board render slice into a "nothing to show" case regardless of
caller. **Spectator/player parity** (tb27 D1a/D1c) — the spectator log no longer word-wraps
(matching the player log); spectator view gained inspect-on-hover (`UnitPicker.hit()` driven off
mouse motion, mirroring `SquadControlOverlay`'s own highlight wiring but with no "selected unit"
gate, since spectator has no selection concept) — previously it had no hover feedback at all.
**Fix: turn controls swallowed clicks behind a stale tooltip** (BR31.01) — a tooltip left over from
hovering the 3D board right before the cursor crossed onto a `turn_controls_column` button never
cleared, since `TacticsController`'s own hover tracking lives in `_unhandled_input`, which a
`MOUSE_FILTER_STOP` `Button` never lets fire while the cursor sits over it. Each turn-control button's
own `mouse_entered` now hides the stale tooltip first — the same fix `QueuePanel`/`ApMpPipRow` already
needed for the identical reason.

**Bouts** (tb14) — watchable AI-vs-AI with pacing controls, a seed, a bout-setup menu. The
verification rig. **Bout roster as an expanding list** (tb16 E, tb17 D) — no count field, list
length *is* the count; each row is `[Bot ▾][AI ▾][D][-]` — a per-bot AI dropdown (moved from
per-team to per-bot), a `[D]` duplicate (copies preset + AI choice, inserted below its source), `[-]`
to remove; `BoutSetup.build_bout` takes an `Array[BoutRosterEntry]` (preset + AI choice) per
team. **The `[AI ▾]` menu listed playstyles until taskblock-46 Pass E below, which retired that
vocabulary — it now lists the `UtilityProfile` `.tres` files themselves, so a new profile is a file
and no code edit.** **Map generation** (tb16 C, grid-size fix tb17 A) — BSP room/hallway split with tunable knobs
(`MIN_ROOM_SIZE`, `MIN_LEAF_SIZE`/`MIN_CHILD_SIZE`, `CORRIDOR_WIDTH_MIN`/`MAX`, grid width/height);
rooms ≥ 7 on their min dimension, hallways 3–5 wide, deterministic per seed. `BattleScene`/
`BoutSetup` grid sizes (40×30 / 32×24) are derived off `MapGen.MIN_LEAF_SIZE` so the BSP reliably
splits 2–3 times per axis — tb16 raised `MIN_ROOM_SIZE` without raising these, silently collapsing
every real battle/bout to a single room with no hallways until tb17 A caught it (`BR17.01`,
`docs/BUGS-ARCHIVE.md`); new tests pin each caller's grid constants against `MapGen.MIN_LEAF_SIZE *
2` so a future threshold raise fails loudly instead of collapsing every map again. **Audited (tb19
J): headless vs. watched bouts already share one path** — found the taskblock-14/15 split already
correct: one `BoutRunner` drives every path, `ResolutionPlayer`/`refresh_unit_views()` only ever read
`combat_state`, never mutate it — no merge needed. Locked in with a direct regression test asserting
playback never mutates a unit's own real fields. **Seeded variant generation** (tb28 A) — `VariantFamily`
(DataLibrary-loaded: `variation_amount`, `omittable_sockets`, `swap_pool`, open StringName data, no
per-family code) + `VariantGenerator` produce structurally different bots from one base `BotPreset`,
deterministic per seed; `BodyAssembler` gained a `&""` Loadout-override sentinel ("leave this socket
bare") variant generation uses to omit armor/cladding without erroring. `JunkBot` ships as real
content — a small template with independently addressable per-limb ARMOR/CLADDING sockets (the
reference humanoid's own arm/leg sockets share generic ids across L/R by design, so per-limb variation
needed new content, not a retrofit). **Kits & instant equip** (tb28 B) — `BotPreset.kit` (null =
unchanged pre-existing behavior) names a container socket, what's stocked into it, and the weapon that
equips out of it into a grip socket via the existing `Inventory`/`PartGraph` ops, no parallel attach
path; chambers ammo through `WeaponResolver.try_chamber` like any other load. `KitEquipper.equip` reads
an `Enums.EquipMode` defaulting to `INSTANT` — `VISIBLE` is declared as the seam a future "watch them
arm up" mode slots into, no behavior behind it yet. `BoutSetup._spawn_squad` runs it for any kitted
roster entry right after assembly — a bout of kitted units starts fully armed at turn 1, proven against
shipped content (`kitted_chaingun.tres`). **Bout injection** (tb29, `src/debug/bout_injector.gd`) — the
debug scalpel: `BoutInjector` mutates a LIVE `CombatState` from outside the turn loop so a specific
scenario can be forced and watched. Every verb goes through one gate — reject outright while
`CombatState.is_resolving` (true only for the synchronous span of an active `resolve_until()` call, a
mid-resolution mutation is forbidden, docs/09's own two-phase-turn discipline applied to the debug
channel); otherwise mark `CombatState.was_injected` (set for good, never cleared — an injected bout is a
deliberate determinism break) and log a distinct `&"inject"` event before anything else runs. Verbs:
`spawn_unit`/`set_position`/`hand_weapon`/`equip_from_kit` (the tb28 self-arming path, forced mid-bout)/
`set_part_hp`/`inflict_wound` (reuses the inspect panel's own `WoundEffects.apply_if_status_crosses_
threshold`)/`set_ap`/`set_mp`/`set_facing`/`set_pose`/`force_current_unit`/`force_overwatch_arm`/
`force_action` (`CombatState.try_apply` — reuses the real legality check, never bypasses it);
`set_therms` is a flagged stub (therms aren't built). RNG needs (a spawned unit's matrix id) draw from
the bout's own `rng`, so the same injections in the same order on the same seed stay reproducible-given-
the-injections. **Tooling misstep, tried and reverted (tb30)** — investigating BR27.06 by reproducing
it outside the headless suite, a raw `SceneTree` driver script (`tools/investigate_br27_06.gd`,
copied from the pre-tb28/29 `checkpoint_6/7.gd` pattern of hand-rebuilding `BattleScene` internals and
driving `TacticsController` programmatically) crashed Godot outright — it referenced `UnitView`, a
class renamed to `HitVolumeView` since `checkpoint_7.gd` was written, and the resulting parse error
dropped Godot into its interactive script debugger, which then SIGSEGV'd under a real Vulkan/X11
context with no stdin attached. No lasting damage; the script was deleted, not reworked. Two things
were missed before writing it: `BoutInjector` is deliberately hard-gated out of player-controlled
bouts (tb29 Pass C) — Step Out is a `SquadControlOverlay`/player-input mechanic, so reaching for
injection here was a category error before any script got written; and the intended division of
labor is "CC scripts/forces, the supervisor watches" — for a player-input-only bug, the correct
non-headless step is the real game with the supervisor at the wheel, not a bespoke driver script
reinventing what the overlay system and `BoutInjector` already provide. **Injection reaches a
player-controlled bout too (tb30)** — `bout_injector` moved up to
`BattleScene` itself (built once per `load_battle()`, survives a spectator ↔ player overlay swap via
`toggle_blue_control()`, since `CombatState` was always the one shared source of truth regardless of
which overlay is installed). Both `SpectatorOverlay` (hover-targeted — spectator has no selection
concept) and `SquadControlOverlay` (selection-targeted — a player bout has a real one) offer the same
`[*]` Inject menu (`InjectMenu`, one shared item list/dispatch — no parallel copies of "what does
Inject do"), calling the exact same API programmatic use does. The real safety property — no
*ordinary* click/action can ever trigger injection — now lives at `TacticsController`/`ActionBar` (the
actual gameplay-input classes, a source-level routing test proves neither references `BoutInjector` at
all), not at "which overlay happens to be installed"; `SquadControlOverlay`'s own Inject button is
additionally gated behind a real `OS.is_debug_build()` check (never even constructed in a release
export), not just the `[*]` naming convention every other debug menu in this codebase still only has.
**Debug control panel (tb30, rolled in from a planned tb31)** — three more `BoutInjector` verbs
(`attach_part`, general case behind `hand_weapon`'s existing `_attach` helper; `remove_unit`, wraps
`CombatState.kill_unit`; and tile edits `place_cover`/`clear_cover`/`set_passable`, real
`Grid.blockers`/`set_terrain`/`set_opacity` writes, no parallel spatial model). `InjectMenu` (one
shared item list/dispatch) is retired, replaced by **`DebugControlPanel`** — a generic,
data-driven click-to-force UI: `DebugVerbSpec` (id/label/typed params/apply `Callable`) rows,
`DebugVerbs.all()` the full table, `DebugControlPanel` builds its form from that table alone, so a
new verb is a new row, never new panel code (deliberately excludes `force_action`/`equip_from_kit`/
`set_therms` — no generic widget can build an arbitrary `CombatAction` or authored `Kit`, and therms
aren't built). A "Pick" button next to a Unit/Cell field arms a one-shot board-click capture via a
new duck-typed `board_clicked` signal / `input_capture_mode` flag on both `TacticsController` and
`SpectatorOverlay` — same shape on both, so "Pick on Board" works identically in a player bout and
spectator, and neither gameplay-input class needs to import the panel or `BoutInjector` to expose
it (the source-routing test from the tb29 paragraph above still holds against both). Both overlays'
Inject button now opens/closes this one shared panel instead of a per-target popup menu.
**Fix: debug panel had no anchor, sat on top of the pre-existing top-left HUD (tb30 follow-up)** — a
freshly opened `DebugControlPanel` defaulted to the top-left corner with no anchor set at all,
landing directly on top of `controls`/`tunables` (both already anchored there in both overlays). New
`_center_top()` (horizontal center, a fixed `TOP_MARGIN` from the top) runs once after `setup()`'s
layout settles and again on every `get_viewport().size_changed`, so a mid-session window resize
doesn't leave it off-center; `test_debug_control_panel.gd` pins the real node's `position` back
rather than re-deriving the centering formula.
**Active-target memory + move-object (tb30 follow-up)** — the panel now keeps an "active target":
every board click while it's open (not just a field's own "Pick") updates it and a label above the
panel's own control column shows it, via the same `board_clicked`/`input_capture_mode` hook, now
armed/disarmed against the panel's own visibility instead of per-pick. `BoutInjector.move_object
(target, to_cell)` generalizes `set_position` (unit-only) to move whatever a hit-shaped `{kind, unit,
cell}` dict points at — a unit (delegates to a shared `_move_unit` helper `set_position` also fronts,
the same split `_attach` already uses, logged under its own verb name), or a cell's `Grid.blockers`/
`Grid.field_items` contents (a real dictionary re-key, preserving the Part's own state, never a fresh
duplicate). A new `DebugVerbSpec.ParamType.OBJECT` always resolves from the active target, never a
manual-entry widget. Move Object keeps its `to_cell` param's ordinary manual X/Y entry and adds a
"Move On Next Click" button — snapshots the active target, then applies the move the instant the next
board click lands, no separate Apply press. The verb picker itself is now a scrolling `ItemList` on
the panel's left side; selecting a verb populates a "control panel" column on the right with that
verb's own param rows, Apply, and status — the panel's whole layout, not just its verb table, stays
data-driven off `DebugVerbs.all()`.
**Fix: a debug-spawned unit rendered nothing (tb30 follow-up)** — `BattleScene.unit_views` was only
ever populated once, in `load_battle()`'s own build loop; `BoutInjector.spawn_unit` adds straight into
`combat_state.units` with no view ever constructed for it. New `BattleScene.sync_unit_views()` diffs
the two and builds the missing `HitVolumeView`(s), mirroring `load_battle()`'s own construction; both
overlays' `_on_debug_panel_applied` call it before `refresh_unit_views()`. Confirmed fixed by the
supervisor. (An initial theory that a reported "move also doesn't visually work" was the same bug,
tested against an already-invisible just-spawned unit, was WRONG — the supervisor had tested move
first, separately; still open, see docs/BUGS.md/the taskblock report.)

**Fix: debug `remove_unit` never actually looked dead (tb30 follow-up)** — `HitVolumeView.is_downed()`
(the one thing `refresh()` checks to pick the DOWN pose) reads `Unit.resolve_matrix() == null`, never
`alive` directly — the same thing a REAL kill leaves behind (`DamageResolver.eject_matrix_if_needed`
nulls the hosting part's own `hosted_matrix`, drops it as a loose `Grid.field_items` entry, THEN calls
`kill_unit`). `remove_unit` only ever did the `kill_unit` half, so `resolve_matrix()` kept finding the
still-docked matrix and the view never changed. Now ejects the matrix the same way first — a debug
removal reads exactly like a real kill instead of a flag flip nothing checks.
**Renamed `kill`; `spawn_object`/`remove_object` generalize the rest (tb30, same-day follow-up)** —
the supervisor split debug removal into two distinct verbs: `kill` (this fix above, unchanged
behavior, renamed) is a REAL narratively true death; new `remove_object(target)` is debug-only
cleanup that makes whatever the active target is — a unit, cover, or a loose item — vanish ENTIRELY,
no corpse, via the same hit-shaped `{kind, unit, cell}` dict `move_object` already consumes. A unit
hit calls `CombatState.kill_unit` (bare, no matrix ejection); a cell hit erases both `Grid.blockers`
and `Grid.field_items` there at once. `BattleScene.remove_unit_view()` is the view-layer half
(`BoutInjector` itself can't touch the SceneTree) — destroys the unit's `HitVolumeView` and tracks its
id in `_removed_unit_ids` so a LATER debug verb's own `sync_unit_views()` pass never resurrects it
(reset on every `load_battle()`). New `spawn_object(cell, part_id, pool, as_cover)` generalizes
`place_cover` to also cover the loose-item half of `Grid` (`field_items`) — `place_cover`/`clear_cover`
refactored into shared raw `_place_cover`/`_clear_cover`/`_spawn_field_item` helpers (no parallel
logic), still directly callable, just no longer separate panel rows next to their own generalization.

**Fix: `Grid.field_items` had zero visual representation anywhere (tb30 follow-up)** — a real,
pre-existing `Grid` concept (loose dropped Parts/Matrices — a real kill's own matrix ejection, a
severed limb, or now a debug `spawn_object` loose-item drop) that nothing ever drew, in debug tooling
OR real gameplay. `BoardView.build()` now also iterates `grid.field_items`: a loose Part reuses
`_spawn_blocker`'s own box geometry (same "render is hitbox" contract, just never registered as a
movement/LoS obstruction); a loose Matrix (no `volume`) gets a flat placeholder marker. `board_view.
build()` was also only ever called once, at `load_battle()` — the exact same gap `sync_unit_views()`
already closed for units, unnoticed for cover. New `BattleScene.sync_board_view()` re-triggers
`build()` (already a correct full clear-and-rebuild) after any debug verb touching blockers/
field_items, called from both overlays' `_on_debug_panel_applied` alongside `sync_unit_views()`.

**Fix: action-bar affordability read the raw unit, not the queue preview (BR27.05)** —
`ActionBar.refresh()`/`_on_box_gui_input()` both compared against `tactics.selection.selected_unit.ap`
directly. Per docs/09's own "queuing mutates nothing," `unit.ap` never drops for an action that's
merely queued this turn, only once it resolves — so an action already committed to the queue (e.g. a
move that burned AP once MP ran out) was invisible to a LATER slot's own affordability check, which
kept reading the unit's full starting AP and stayed clickable regardless. Both call sites now read
`tactics.selection.previewed_unit()` instead — the same source `reachable_cells()` already uses for
the identical reason.

**Fix: Step Out evaluated cover from the shooter's stale pre-move cell (BR27.06)** — same bug class as
BR27.05, one file over. `TacticsController._enter_aim_or_step_out_mode` read `selection.selected_unit`
directly; per docs/09's "queuing mutates nothing," that stays at the shooter's turn-start cell until
the queue resolves, so a player who moved toward/into cover and THEN armed a shot had cover evaluated
from the stale pre-move position — silently falling through to ordinary aim mode instead of the
step-out the shooter's real, about-to-be-true position warranted. Root-caused by first disproving a
standing hypothesis from this taskblock's own earlier BR27.06 investigation ("the trigger condition
may just be too rare on real maps"): a 60-seed sweep of real `MapGen` maps driven through full
AI-vs-AI bouts found ~1850 genuine covered-with-a-candidate encounters, and `MapGen._scatter_cover`
never sets `grid.opacity`, so most of those are plainly visible/clickable too — not rare, and not an
LOS edge case. Swapped to `selection.previewed_unit()`, the same fix shape as BR27.05.

**Pass D: audit of `selected_unit` staleness across the rest of tactics-phase view code (BR30.07/
BR30.08)** — BR27.05 and BR27.06 turned out to be the same bug in two places, so tb30 audited every
other `selection.selected_unit` read that feeds position/AP-dependent state (not identity) per a
supervisor-authored suspect list. `TacticsController._confirm_step_out()` computed its outbound path
via `Pathfinder.astar(shooter.cell, firing_cell)` off the raw cell — `MoveAction.is_legal()` requires
`path[0] == actual.cell` against the unit's real (previewed) position, so a move queued before
triggering step-out silently failed to enqueue and fell through to `cancel_step_out()`, invisibly.
`TooltipController.refresh()` passed the raw unit into `TileInspection.inspect()`, whose
`visible_from_selected` field runs a real LOS check from the selected cell directly — stuck showing
visibility from the turn-start position after a move was queued. Both swapped to `previewed_unit()`,
each verified failing without the fix and passing with it first. `step_out_exposure()`/
`_refresh_overlay()`'s own `Overwatch` calls were ALSO flagged as suspects but, after tracing (and an
empirical probe), turned out not to matter — `would_trigger_at()`'s general-case branch always
re-resolves the mover by id and relocates to the candidate cell regardless of the passed reference's
own stale `.cell`, so no fix was needed there.

**Fix: shots resolved straight through walls (BR30.10)** — `LoS.has_los()` and `ShotPlane.build()` read
entirely disjoint data: `LoS` reads only `grid.opacity` (correctly opaque for wall cells, gating
tactical aim/step-out decisions), while `ShotPlane.build()` only ever projects `state.units` and
`state.grid.blockers` — never `opacity`. `MapGen` never wrote a `blockers` entry for WALL cells (only
scattered cover got one), so a real wall had an opacity flag but no Part, no mesh, nothing in the shot
plane — invisible to actual hit resolution even though it correctly gated the UI. `MapGen` first gave
every exposed WALL cell a `blockers` Part so a wall registered in the shot plane at all (BR30.10).
**tb31 C then reworked the model** (`docs/SUPERSEDED.md`): a wall is now a **destructible** high-DT
cover `Part` (`data/parts/wall.tres`) on an otherwise-passable `OPEN` tile — not an indestructible
terrain flag — and the negative space past a wall's ring is a new `Enums.TerrainType.VOID`
(non-navigable, opacity 0, no Part: a shot passes into it, nothing to hit). `Pathfinder.move_cost()`
now clears a **destroyed** blocker (`hp <= 0`), so a blown wall — or any dead scatter cover — opens its
tile to movement, one mechanism for both (mangle/rubble states deferred, `docs/PLAN.md`).
`MapGen._finalize_walls_and_void()` resolves this in two passes (classify every cell's exposure
against the untouched grid, then mutate) so exposure can't cascade through solid rock. **Wall
legibility** (`WallLegibility`, `BoardView`) fades a wall occluding the player's selected unit —
screen-space projection (`unproject_position` + depth), real alpha blend kept lit — so walls stop
hiding the action without vanishing; VOID cells render black with a dark-gray border.

**Fix: burst shown as affordable without enough AP; step-out silently dropped the shot (BR30.11)** —
`ActionBar._can_afford()` compared AP against the providing weapon's plain `ap_cost` for every action
id, but `BurstAction` has always charged its own, usually-higher `weapon_def.burst_ap_cost` when
authored. A unit with enough AP for the plain cost but not the real burst cost saw (and could arm)
BURST as affordable, only to have the shot silently rejected at `enqueue()` time — including after a
free step-out move, which read as "step out doesn't work with burst" even though step-out's own entry
logic is genuinely action-id-agnostic (verified directly, no fix needed there). New
`ActionCatalog.ap_cost_for(action_id, provider)` is the one seam both `ActionBar._can_afford()` and
`BurstAction._ap_cost()` (now a one-line delegate) read, closing the drift.

**Inspect panel** (tb21/22/23/26) — the current inspect surface: rotating bot viewer, matrix area,
sorted inventory tree (weapons→containers→parts), info panel + item viewer, status/wound column,
dead-zone hold, right-click debug menu (debug-only items `[*]`-prefixed; inflict-status/create-part
submenus, tb22 G). The one inventory surface in player view too — `InventoryPanel` retired (tb22 I).
Click-to-pause-inspect in spectator, id+squad+variant in the header (tb26 C3). The isolate camera
(single-unit preview) shows the model standing on real ground, correctly lit, not floating in a
void (tb23 E2). **Tile/object inspector** (tb26 E) — `InspectPanel.open_tile(cell, root)` wraps a
tile's blocker Part (or null, a bare tile) in a matrixless, shell-only synthetic Unit and drives it
through the same display path a real unit uses, no parallel inspector; spectator's click-to-inspect
falls through to `BoardPicker.cell_at_ray` when a click misses every unit's own body.

**Transparency** (docs/08) — one `StatResolver`, provenance on every value, tooltip == damage from
one call.

**Control-surface consolidation** (tb31 A) — `TopLeftControls` (a shared `HBoxContainer`) is the one
construction path for Inject / New Battle / Watch across `SpectatorOverlay` and `SquadControlOverlay`,
where each overlay previously built its own copy; grouped top-left, clear of the debug panel's anchor.
The keybindings display now defaults off, toggled by a `Keybindings` button alongside the existing
H-key. Fixed a latent click-passthrough bug found while wiring it (the shared container's
`mouse_filter` defaulted STOP, swallowing clicks in the gaps between buttons).

**Aim view: truth & legibility** (tb34) — the dartboard was quietly lying: `AimController.resolve`
(the drawn board) called `Dartboard.resolve_scatter` with no range multiplier while every real shot
(`AttackAction`/`BurstAction`/`StabAction`) correctly widened with distance, so the board shown was
always the weapon's best-case accuracy and understated spread more the farther you fired. New
`ShotScatter.for_shot` is the one place `range_cells → RangeModel.dartboard_radius_scale →
Dartboard.resolve_scatter` gets assembled now — every consumer calls it, so the drawn and fired boards
can't independently drift again. Fixed the cache landmine this creates: `AimView._rings_match` now
keys on ring-to-outer-ring ratio instead of absolute radius, so a pure range change resizes the decal
instead of rebuilding the 128x128 ring image pixel-by-pixel every frame (`DartboardTexture.build`
already normalizes by `outer_radius`, so a uniform rescale is byte-identical). Two previously-invisible
spread sources now draw: a burst's later pulls widen the board cumulatively
(`RecoilResolver.widen`), but only pull 0 ever showed — `AimController.recoil_bound_radius` draws the
widest pull's own bound as a crisp outline, baked into the same texture (its ratio to the outer ring is
weapon-constant, so the cache invariant survives); a pellet round's mechanical spread pattern
(`SpreadPattern.pattern_radius`, made public) doesn't scale with range, so it's drawn as a genuinely
separate, un-cached overlay circle (`DartboardTexture.build_solid_dot`) rather than baked in. **Part
tooltips in aim view** — new `TacticsController.update_aim_hover` maps the cursor to an aim-plane point
and finds the Region there (`ShotPlane.region_at`, a thin public alias for the internal
`resolve_projectile`), writing only `aim_hovered_part`, never the reticle or `resolves` — hovering
reads, it never re-aims, split into its own function so that's structural, not just documented.
`AimView` renders the hit part's tooltip in-world via a `Label3D` coplanar with the aim window
(`TooltipView.to_plain_text`, a third host for the same `TooltipData` shape `to_bbcode` already
renders, since `Label3D` has no BBCode support). **Sniper framing** — beyond
`CameraOrbitState.SNIPER_FRAME_DISTANCE` (5 cells, a tunable), the attack camera frames the target
alone (`sniper_framing`) instead of shooter-over-shoulder (`attack_framing`): this rig's own topology
(the camera always faces its own pivot) means panning directly onto the target's center puts it
dead-center on screen at any yaw/pitch, so no dual-sphere BACK solve is needed, just a closed-form
single-sphere zoom. Both framings ease through the same shared tween
(`CameraRig.ease_to_framing`/`_ease_to`). **Fix: BR26.02, low framerate while aiming** — two real costs
removed: the cache-invalidation fix above, and a redundant `AimView._process()` override (found
2026-07-21, applied here) that unconditionally called `refresh()` every single frame while aiming even
though `refresh()` was already fully wired to `tactics.aim_changed`; deleted outright once every
mutation path was re-confirmed to emit it. `docs/BUGS.md`'s own scroll-layer-cycles-walls finding
(BR33.01) is deliberately still open — a policy call, not a mechanism one, left for the supervisor to
decide having now seen this block's finished aim view.


### Diagnostics: the log becomes the instrument (tb41 Passes A–D, F, docs/09)
**Render coalescing (Pass A, BR27.09 cost #1).** `emit()` updates the model and marks dirty; the
`RichTextLabel` draw happens at most once per frame, driven from `ControlOverlay._process`. New shared
`UiLogSink` base; both `UISink` and `HierarchicalUiSink` extend it. **BR27.09's own prescribed fix —
incremental `append_text` — was overridden with the supervisor's approval and NOT taken**: it fits the
flat sink but cannot fit the folding one, where a new event routinely rewrites an existing group's
summary rather than appending a row. Coalescing is correct for both, and its real value is that render
cost stops scaling with event count *at all*, which is what makes Pass D affordable.
Measured on BR27.09's own scenario (200-line scrollback, 3v3, peak 29 events), real classes against a
real label in a real tree: `UISink` 4845µs → 225µs on a peak turn, `HierarchicalUiSink` 10058µs →
870µs. **`HierarchicalUiSink` had never actually been measured and is ~2× the sink that had been** —
~10ms on a peak turn in the sink both live overlays use, not the ~5ms BR27.09 estimated from the flat
one. Headless and a real x11 display agreed within ~2%. **The several-second hitch survives, as
expected** — its mechanism is the synchronous AI batch, untouched here; BR27.09 stays `Active`.

**Engine and script errors on the same stream (Pass B).** `EngineErrorTap` is a real Godot `Logger`
(`OS.add_logger`); every error becomes a `LogEvent` of kind `diagnostic` on whichever `CombatLog` is
current. `LogSink.wants()` is the opt-out, checked once in `CombatLog.emit()`. **The reachable set was
observed, not assumed**: `push_error`/`push_warning`, GDScript runtime errors *with the real script
file and line*, and engine-internal C++ `ERR_FAIL_*` all reach it; **a hard crash never will**, and
that boundary is stated in docs/09 rather than left implied. One engine failure can produce several
callbacks as the C++ chain unwinds — reported faithfully, not deduplicated. `_log_message` is
deliberately not hooked (`print()` routes through it and `StdoutSink` prints every event — an
unbounded loop).

**Commands paired with outcomes (Pass C).** `CommandLog` emits a `command` event before every attempt
and a `command_outcome` after, carrying a machine-readable `reason`. Pass B covered every rejection
that already went through `push_error`; this covered the remainder — **~40 bare `return false` paths in
`BoutInjector` that were silent even to the console**, each now naming its cause. Shared helpers stopped
answering only "no": `_move_unit`/`_place_cover`/`_clear_cover`/`_spawn_field_item` return a reason and
`_attach` returns `{part, reason}`, because three different failures collapsing into one null left
callers unable to say which happened. A refusal while queueing and a refusal at resolution read
differently. `try_apply` no longer refuses silently and `resolution_stopped` names the action that
could not run. **Reverses tb29's "a rejected call is a true no-op (no log entry)"** — the mutation and
RNG halves stand, the silence does not (`SUPERSEDED.md`). **Not done:** a per-action legality *reason*
would mean changing `is_legal`'s signature across every action; deliberately out of scope, so
`try_apply` reports `action_illegal` plus the action's own `describe()`.

**Deliberate verbosity and the bout-build log (Pass D).** `BoardView.build()` narrates itself in
construction order — terrain, grid lines, empty tiles, extraction tiles, walls, cover, field items —
each with its own count and a running index, counted where they are built rather than re-derived from
the grid. Plus `unit_assembled` (listing parts in socket-tree order) and `overlay_activated`/
`overlay_deactivated`. **"bot constructed, part attached" is logged where a unit ENTERS the world**, not
inside `DeepStrike`/`BodyAssembler`/`PartGraph.attach`: those are pure static logic with no `CombatLog`
in reach, and threading one down would push a diagnostic concern into the deepest layer for a per-socket
event nobody asked for. **The wall cutout is deliberately NOT logged per frame** — it runs every frame
on every wall while the camera orbits and `FileSink` flushes per line, so it logs only when the cut set
meaningfully changes. `LogFold` folds the new high-volume kinds into one counted row per run;
`diagnostic` is pointedly excluded, because collapsing an error into a quiet counted row is the
opposite of what an error is for.
*Fixed a regression this pass caused:* the build log displaced `session_start` from the log file's
first line, breaking docs/09's "replayable from its own log file alone". `load_battle` now takes an
optional header event emitted between attaching the sinks and building anything, and the active
overlay's log sink attaches explicitly at that point (`ControlOverlay.attach_log_sink`) instead of as a
side effect of `battle_loaded`, which fires at the *end* of the load and missed everything.

**The log becomes a window (Pass F).** `CombatLogPanel`: title bar, minimize, drag-to-resize, a real
background, scroll hand-off at the content's ends, and a live FPS readout in the title bar.
`FpsMeter` and `LogScrollHandoff` hold the real rules and are headlessly tested; the chrome is
plumbing, deliberately untested, and this pass is **a session opener, not a definition of done**.
docs/09 now records that `FpsDumpSink` and this readout are *supposed* to disagree and must not be
reconciled — the gap between them is the only signal separating BR26.02 from BR27.09. **BR34.02 is
answered structurally (the panel has a real background) but NOT closed** — it is `SUPERVISOR`-owned.
*Two layout bugs were found by rendering, not by testing*: a `PanelContainer` sizes every child to
fill, so the readout stacked under the log instead of overlaying it; and `PRESET_TOP_RIGHT` bakes
offsets from a zero-width Label, so it grew off the panel and over the board. Neither was visible to
any headless assertion. `SpectatorOverlay` still uses its own bare label — converting it belongs to the
live iteration this pass opens.
*Supervisor follow-up, same block:* panel widened to a self-declared 520px (it previously inherited
~260px from the surrounding column, which cut most lines off), and **the scroll hand-off was fixed —
it had never actually worked.** `LogScrollHandoff` was correct and unit-tested throughout; the rule was
simply never consulted, because Godot marks a mouse event handled whenever it reaches a
`MOUSE_FILTER_STOP` control under the cursor, whether or not that control calls `accept_event()`. The
`RichTextLabel` consumed the wheel before `_gui_input` on the panel ever ran. Handing off therefore
**`BR34.02` closed `Resolved` by the supervisor** — the panel's real background was one of the two
changes that entry asked for; the `mouse_filter` sweep it also wanted is still outstanding.
*Then the scroll behaviour was reversed outright on supervisor correction*, and the reversal is the
more useful record: Pass F's spec said the wheel should fall through to the camera at the content's
ends, **which is the behaviour `BR30.05` already reports as a bug** for the debug panel — so building
it as written reproduced a known defect somewhere new. The log now absorbs the wheel whenever the
cursor is over it. Two implementation attempts were wrong before the third worked, both because
`MOUSE_FILTER_STOP` does less than it appears to: it consumes clicks (which is why left/middle/right
always behaved) but a wheel still reaches `_unhandled_input`, and `RichTextLabel` scrolls without
consuming. The panel now scrolls explicitly in `_input` and calls `set_input_as_handled()`.
`LogScrollHandoff` and its unit tests are deleted — the rule they encoded no longer exists. **A
cautionary case worth keeping:** that class was correct and green throughout, while the feature it
served did nothing at all, because nothing ever asked it. Only a spy at the real input stage showed
it (`test_combat_log_panel.gd`), and that test carries a deliberate control case so it cannot pass
vacuously.

**`BR30.05` — the same two defects in the debug panel, fixed (`Pending`, `SUPERVISOR`-owned).**
Clicks: `DebugControlPanel` was `MOUSE_FILTER_IGNORE` on taskblock-07 Pass B4's "a plain container
has no click of its own" rule — but it is a `PanelContainer` with an opaque `HulkTheme` background,
so the rule does not fit it; scoped to genuinely invisible containers and this panel set to `STOP`
(`SUPERSEDED.md`). Scroll: the 2021 diagnosis blamed `ItemList` not marking the wheel handled *once
it can't scroll further* — the real fact is broader and was measured, **`MOUSE_FILTER_STOP` never
blocks a wheel from `_unhandled_input` at any scroll position**. The panel consumes it explicitly.
The wheel is **forwarded before being consumed** rather than swallowed: consuming wholesale would
have silently deleted `SpinBox`'s wheel-to-adjust, which several verb forms use, so the event routes
to whatever is under the cursor first (verb list scrolls, `Range` steps) and only then is marked
handled. The forwarding hit-tests by position rather than reading
`Viewport.gui_get_hovered_control()`, because hover is only bookkept from real mouse *motion* and is
null whenever a wheel arrives without one — caught by the `SpinBox` test failing against the hover
version. The entry's own request for a repo-wide `mouse_filter` sweep is **not** covered.

### Checkpoints return as an ordinary tool (tb41 Pass E, docs/09)
The **gate** was retired, not the capability: no hard stop, no permission step. `./checkpoint.sh N`
runs `tools/checkpoints/checkpoint_N.gd` against a real display; the driver is generic and **the
scenario owns its own README and checklist**, so the description cannot drift from the code (three
heredocs were ~200 of the driver's 224 lines).
**The parse guard is the load-bearing piece.** Visual checkpoints sit outside the headless gate by
necessity, so nothing re-runs them — which is how a `UnitView` rename orphaned two scripts for ~15
taskblocks with nothing going red (`BR40.02`). Rendering can't happen in CI; parsing can.
`tools/checkpoints/parse_guard.gd` fails the build on a parse error or a script that stopped being a
`SceneTree` entry point. **It is a script, not a GUT test, and that was found the hard way:** written
as a test first, it worked — but `run_tests.sh` runs GUT with `-d`, and under the debugger a parse
error raises a break that *waits for input*, so the guard would have hung the build instead of failing
it. It now runs without `-d`, ahead of GUT. Proven both ways by reintroducing BR40.02's exact
`UnitView` reference and watching each behave.
`checkpoint_{6,7}.gd` **deleted** rather than repaired — updating two dead scripts so they could then
be removed is work with no product. `BR40.02` closed as **`Obsolete`, not `Resolved`**: nobody
verified a fix, because there was no fix. `out/checkpoints/` is local-only now (`.gitignore` plus
`git rm -r --cached`; the ignore alone does not untrack), with `out/checkpoints-kept/` tracked so
keeping an image is a copy rather than a forgotten `git add -f`. **The durable artifact is the answers,
not the images** — they go in `reports/`. The old GUT-based checkpoints 1–5 left `checkpoint.sh`
entirely: they were never checkpoints, just regression tests, and now live under `test/baselines/` with
names that say so.

### Both views share one combat log (supervisor request, post-tb41)
`SpectatorOverlay`'s bare `RichTextLabel` is retired for the same `CombatLogPanel` the player view
uses, so the title bar, drag-to-resize, `[-]`/`[+]` minimize, real background, wheel absorption and
FPS readout stop being a player-view-only privilege — two views with two log widgets is how they
drift apart every time one is improved.

The panel writes its height through **both** `custom_minimum_size.y` and `size.y`. The overlays lay
it out completely differently — a column child in the player view, absolutely positioned against the
bottom-left corner in the spectator view — and each situation respects only one of those, so writing
one leaves drag-to-resize silently inert in whichever view the author wasn't looking at.

**`fps_dump` joined `LogFold.PLUMBING_KINDS` off the back of it, and that was a real bug nobody had
reported.** Rendering the converted spectator log showed eleven identical `Turn FPS ... 74.0` rows
filling the panel and pushing every combat event out of view: `FpsDumpSink` emits one per turn, and
Pass D never added the kind to the fold list. Folded, not dropped — `out/combat.log` is unaffected,
folding being presentation only (tb22 F2). **The same flooding was live in the player view**; the
spectator view only made it obvious because it runs turns continuously.

Checkpoint 9 (`./checkpoint.sh 9`) authored for the conversion under Pass E's own no-permission
policy — and it earned the parse guard its keep immediately: the first draft called a
`DataLibrary.bot_presets()` that does not exist, and the guard failed the run and named the file
before anything rendered.

### Bug hunt: the turn-boundary hitch, measured (tb42 Passes A–E, BR27.09/BR26.02)
**Partial by design; F and G are not started.** The block's result is a diagnosis, not a fix.

**Pass A — the instrument.** BR26.02's 2026-07-23 revision, unbuilt since. Two dumps per turn:
`turn_boundary` at **0ms** (the boundary cost itself — the number BR27.09 is about, which did not
previously exist at any offset) and `turn_settled` at **2000ms**. The boundary dump is emitted
**synchronously**: any await would push it past the transient it exists to catch. The aim-entry dump
moved to the same delay and reads the shared constant.

**Passes B–C — costs #2 and #3 cut, and they are small.** `HitVolumeView.refresh()` freed and
re-instanced every child even when only a transform changed: 858µs → **351µs** on the move path,
795µs → **267µs** on the aim path. The cheap path **refuses** on any node-set difference rather than
enumerating safe cases. Turn start walked the socket tree five separate times (instrumented and
confirmed — BR27.09's "5–6" was right): 118µs → **40µs**, threaded rather than cached, because a
stale power reading is a silent wrong number. **Both together are under 1% of one AI step.**

**Pass D — the batch yields, and the hitch survives.** `advance_ai_turns` had no `await` at all; it
now yields a frame between units, so input stays alive and each unit's move is visible instead of the
opposing team teleporting. **But a single `BoutRunner.step()` costs ~1672ms** — 24 steps of a real
3v3 bout is 40.1 seconds of pure planning. Yielding between steps buys one responsive frame every
~1.7s. **The several-second hitch is ONE `UnitAI.plan_turn` call, not an accumulation**, so this
relocates the bug rather than fixing it: the remaining work is per-candidate-cell pathfinding/LOS/
cover scoring in `unit_ai.gd`, which tb35 Pass A3 halved once and which has grown back.
**⇒ SUPERSEDED in part by "AI planning cost" (tb43) below — that naming of the remainder was right
about the file and wrong about the function.** The candidate scoring is ~25% of a planning turn;
`_any_reachable_has_lof`'s prefilter scan over the whole reachable set is ~70%. Determinism
verified — a seeded bout is identical through the yielding path and a tight no-yield loop.
Coalescing fork settled as "refresh only the units that step touched", which is proportional to what
changed rather than tb19 I2's measured whole-board waste.

**Pass E — the debug path.** Every debug verb triggered a full `BoardView.build()`, including the ~20
that touch one unit's AP or facing; `DebugVerbs.affects_board()` is now the one authority both
overlays read (BR35.03, `Pending`). Also fixed: `BoutInjector._move_unit` set `unit.cell` without
re-deriving `unit.height`, so a debug move onto a raised cell rendered at the old elevation —
invisible on a flat map, which is why every flat fixture missed it. **Not a fix for BR30.02**, whose
symptom still does not reproduce. `BR35.01` deliberately untouched and said so.

### AI planning cost: cut the search, and find out the search was not the cost (tb43 Passes A–D, BR27.09)

**The block did what it set out to do and disproved its own premise doing it.** It is scoped as
"attack the candidate count and the work per candidate", on the standing assumption — carried by
tb35, tb42 and this block alike — that `UnitAI._pick_engagement_position` is where an AI turn's
seconds go. Passes A, B and D all attack it. **It is about a quarter of a planning turn.** The
measurement that says so is in Pass D below, and it retargets BR27.09.

**The instrument first.** `tools/bench_ai_planning.gd` — 5 seeds x 12 steps of a 3v3, headless and
repeatable, reporting ms per AI step, the Pass B difference rate, a per-role cost split, a branch
census, and a `--profile` breakdown of one turn. Every number here comes from it. **The earlier
~1672ms/~1498ms figures in this bug came from a bench nobody kept and are not part of this series** —
this one starts at ~745ms for the same work, and only differences within it mean anything.

**Pass A — exact early-out in the scorer** (landed in a prior session, `8ebca0e`). Every term in
`_engagement_score` is a non-negative penalty except `cover_bonus`, which is bounded by
`COVER_SCORE_BONUS`, so a cell whose cheap terms already put its ceiling at or below the best
complete score cannot win and skips both line walks whole. `<=` rather than `<` because selection is
strict `>`: a cell that can at best tie never wins. Acceptance was identical output, not speed.
**~1672ms → ~1498ms on the old bench (~10%).**

**Pass B — the candidate rectangle** (`src/logic/ai/engagement_rect.gd`). Scores only the reachable
cells inside a box with two corners on the unit and its target, padded 2 laterally and, on the far
side beyond the unit, by the weapon's own standoff distance. **The asymmetric half is the load-bearing
half**: a unit that wants to back off finds its cells behind itself, exactly where a symmetric pad is
thinnest, and `MIN_COMPLETION_RATE` would very likely still pass while the optimisation shoved
long-range units into knife fights. **~745ms → ~674ms (~9%), keeping 64.9% of candidates
(95.7 → 62.1 per decision), chosen cell differing in 7 of 60 decisions (11.7%)** — much of that being
cells that *tie*, since on open ground a whole arc sits at the standoff distance and scores
identically. The LOF prefilter deliberately still sees the **whole** reachable set: culling before it
would flip which branch runs, not just which cell wins inside one.

**Pass C — batch plumbing.** `Unit.batch_id` (0 = independent, and every generated mission leaves it
there), a `set_batch` injector verb and debug-panel row, a round-scoped `BatchPlan` on `CombatState`,
and a board badge (`B2`, `B2*` for the leader) whose text is decided by a headless logic-layer
function so what it says is testable without a screen. Explicitly **not** `squad_id`: that is the
team, and overloading it would make every batch a second team.

**Pass D — leaders plan, followers follow.** First member of a batch to take a turn claims the lead
and pays for the full search; later members that round read its destination and scan the ≤9 cells
around it. Leadership is **derived, never stored** — no `leader_id`, no promotion logic, nothing to
desync; a leader dying mid-round leaves its record intact so the squad finishes the manoeuvre and
reorganises next round when the record ages out.

**Pass D's own acceptance is NOT met, and that is the block's most valuable output.** It asks for a
follower to be dramatically cheaper and says that if it isn't, the local scan is too wide. Measured:
**leader ~330ms, follower ~317ms, about 4%** — and the scan cannot be narrowed below radius 1. So the
turn was profiled rather than the constant tuned, and per repositioning turn (means over 60):

| | ms |
|---|---|
| `_any_reachable_has_lof` | **271.9** |
| `_pick_engagement_position` | 98.3 |
| `_nearest_living_enemy` | 15.0 |
| `Pathfinder.reachable` | 2.5 |

**The LOF prefilter scan over the whole reachable set is the real remaining cost**, and it is paid by
leader and follower alike. Branch census over the same 60 turns — `repositioned` 23,
`no_lof_no_route` 15, `followed_leader` 10, `closing_fallback` 4, `fired_in_place` 5, `stepped_out` 2
— shows **19 turns in 60 end with no reachable cell having a line at all**, each having scanned every
reachable cell to find out. The cheapest exact attack is ordering that scan nearest-the-target first,
since it early-returns on the first hit and currently walks BFS-from-the-unit order. **Deliberately
not built**: this block is triage with a stated scope. It is in `PLAN.md` and on BR27.09.

Whole-bout effect of batching one squad of three: **~671ms → ~646ms per AI step.** BR27.09 stays
`Active`; nothing here closes it.

### AI v2, part one: measure, invert, seam (tb44 Passes A–D, BR27.09/BR44.01)

**Every performance figure this project had ever recorded came from a tools binary**, and nobody had
checked how much of the hitch was GDScript's debug per-line overhead. Now measured, on the same bench
and seeds throughout: `editor_debug` ~686–712ms → `exported_release` ~530–554ms per AI step,
**~1.29×**. Roughly 78% of the cost survives into a real player build, so the planning cost is
genuine. `src/debug/build_identity.gd` classifies the running build and is stamped into the bench's
first line and every `fps_dump` event, so a number never again needs its provenance explained in
prose. `tools/bench_release.sh` runs both builds and refuses to report unless the binary itself
declares `build=exported_release`.

**Getting that number required fixing BR44.01, and it is the more consequential find: the first-ever
export of this project loaded no data at all** — no parts, ammo, presets, materials or variant
families. `DataLibrary._load_dir` filtered on `ends_with(".tres")`, true in the editor and false in
every export, since `convert_text_resources_to_binary` ships `crab.res` + `crab.tres.remap`. It
presented as a bare SIGFPE with no message, because an empty pool makes `i % pool.size()` an integer
modulo by zero that a release build traps at the CPU. Two structural consequences: an export template
**ignores `-s res://...`** (confirmed by passing a nonexistent script and getting the identical
crash), so the bench needed a main-scene entry point behind a `bench` feature tag; and the bench body
moved to `AiPlanningBench` so the debug and release entry points cannot drift.

**The line-of-fire query is inverted** (`src/logic/visibility_field.gd`). One `VisibilityField` per
target per turn, `PackedInt64Array`, flat `i = x + y*W + z*W*H`; each candidate's question becomes a
bit test. **~700ms → ~525ms per AI step (~24%)**, ~412ms release. It is a conservative **prefilter** —
one obligation, never report "no line" where one exists — and `ShotPlane` stays final, so acceptance
was identical output. It deliberately over-includes on cover, on units, and across elevations. The
occluder test is opacity **and** a blocker the plane would actually resolve against
(`BodyProjector.projects`, extracted so there is one answer): opacity alone is *wrong*, not coarse,
because `Grid.opacity` is never cleared when a wall dies. The all-negative case — 19 of 60 turns in
taskblock-43's census — now costs **exactly zero** `ShotPlane` builds.

**Where the cost went, which is the pass's real output.** `any_lof_scan` 271.9 → 77.8ms, new
`field_build` 4.2ms, but `engagement_search` 98.3 → **251.2ms**. The scorer did not get slower; it was
being subsidised by a scan that built a plane for nearly every reachable cell and left them in the
per-turn memo. The remaining cost is per-candidate casts inside `_engagement_score`.

**The `WorldView` seam** is the planner's entry point; `CombatState` reaches it only through
`canonical_state_for_resolvers()`. Today it returns everything — a pass-through with a doorway in it,
byte-identical across a seeded bout. **The boundary is not `CombatState` versus not-`CombatState`: it
is knowledge-about-units versus everything else, and that line runs THROUGH `Grid` and THROUGH
`BatchPlan`.** Geometry is free; occupancy is not geometry (`Grid.occupant_id` would leak every unit's
position past the filter, so the guard forbids it); the team blackboard is a Trained-and-above tier
capability, so batch plans are observer-gated on both read and write. The resolver door may appear
only as a bare argument, never followed by a dot — greppable, and enforced, because a prose rule with
no enforcement is what BR40.02 was. Restriction is stubbed behind a disabled flag with staleness
derived rather than maintained, and an anti-vacuity test proves a restricted view changes what a unit
decides.

**A unit's turn is now navigable rather than frozen.** The planner yields mid-plan every `chunk`
candidates and the acting unit is named on screen while it thinks. This makes nothing faster and is
not meant to: taskblock-42 Pass D yielded *between* steps, which bought nothing, because one step is
the entire think. The chain became coroutines because GDScript rejects a conditional-await single
implementation at parse time and a second planner would be two paths deciding one thing. A hard turn
budget backs the label, since a thinking state that never ends is worse than a freeze; aborting is
safe at any iteration because the incumbent is the unit's own cell until strictly beaten. Frame
boundaries do not change decisions, asserted directly.

### AI v2, part two: the utility planner replaces the branch cascade (tb45 Passes A–E, docs/PLAN.md)

**The engagement-score planner is deleted.** `src/logic/ai/unit_ai.gd` — 1369 lines, eight
`max-file-lines` bumps, every one justified by "part two replaces this file" — is gone, and the
linter cap is back at its default 1000. `test/unit/test_retired_planner_sweep.gd` greps `src/`,
`test/` and `tools/` for the retired name and asserts the 1000 directly, so neither can drift back
silently. Full retirement note, including the measured before/after, in `SUPERSEDED.md`.

**The model** (Pass A). `ResponseCurve` / `ConsiderationDef` / `UtilityActionDef` / `UtilityProfile`
as data; `UtilityScorer` as the maths. Considerations MULTIPLY, so one zero vetoes outright; the
IAUS compensation factor keeps a 5-consideration action comparable to a 2-consideration one at equal
quality. **The compensation is not exact and the residual is documented rather than hidden** — it
shrinks the dimensional penalty from "five inputs retain 51%" to "89%", and the remaining ~11% is an
accepted cost, not a tuning problem.

**Selection over the existing action layer** (Pass B). `UtilityActionDef.executor_id` names one of
the twenty tested classes in `src/logic/actions/` through `UtilityExecutors`; nothing was
reimplemented. `UtilityContext` is the seam that turns a candidate cell into the `{input_id: 0–1}`
dictionary the scorer consumes — and is the only place in the planner that knows what a grid, a
weapon or a line of fire is.

**Actions and profiles are `.tres` files**, under `res://data/utility_actions/`,
`res://data/utility_profiles/` and `res://data/batch_objectives/`, loaded by `DataLibrary` like every
other content type. `PLAN.md`'s claim that the rest of the tier table "needs preconditions and a
consideration set, not new machinery" is now literal. `tools/author_taskblock45_ai.gd` authors them.

**Intelligence gates information, and the gate is load-bearing.** `WorldView.MEMORY_TIERS` makes
remembered sightings a tier capability: `MINDLESS` sees only what its own eyes currently reach and
stops knowing an enemy exists the moment line of sight breaks, where `TRAINED` acts on what it wrote
down. The two tiers decide differently on the same board and the two profiles decide differently with
tier held constant — both asserted directly, because a tier that silently does nothing is the failure
this design is most exposed to.

**A floor is not a preference — the most consequential authoring lesson of the block.** In a product
model, a consideration whose curve can reach 0.0 does not express "prefer this", it expresses
"refuse everything else". A plain linear `standoff_match` therefore meant "refuse to act more than
eight cells off the preferred distance", which would stop a rifleman with a thirty-cell weapon ever
taking a long shot, and nothing about the arithmetic announces it. Every consideration expressing a
preference is now floored; only `line_of_fire`, which expresses a genuine impossibility, can reach
zero.

**The batch objective, built dormant** (Pass C). A leader runs one coarse utility pass over four
authored objectives and the answer is injected as a consideration input for every follower — squad
coordination without a squad planner, replacing taskblock-43 Pass D's copied destination. Standing
rule 5 is untouched: the objective is computed once per batch per round and reused, never a licence
to resolve units together. **Dormant publishes an all-ones neutral vector, never all-zeros** — zeros
would veto through the product and every `batch_id == 0` unit, which is every unit in play today,
would stop acting.

**The objective damping floor had to be lowered to do anything, and that was found by testing rather
than by reading.** At 0.5 the batch had an objective, the log recorded it, every follower read it,
and **not one decision changed** — `shoot` carries a higher base weight and is served by `hold`
alone, so `advance` and `withdraw` damped it identically. At 0.25 the three cases separate. A
mechanism that is wired end to end and still inert is exactly the "silently does nothing" failure,
arriving on the batch axis instead of the tier one.

**Head to head, then the flip** (Pass D). The same seeds through both planners, 24 of them, re-taken
at the end of the block from one standalone probe with the old planner run from a worktree:

| | old | new |
|---|---|---|
| seeds 0–11 | 9/12 (75.0%) | 5/12 (41.7%) |
| seeds 12–23 | 12/12 (100%) | 8/12 (66.7%) |
| **combined** | **21/24 (87.5%)** | **13/24 (54.2%)** |
| mean turns to complete | 23.6 | **10.6** |
| per-unit plan cost, mission bout | 139.90 ms | **86.51 ms** |
| per-unit plan cost, 3v3 combat bout | 485.16 ms | **131.25 ms** |
| `ShotPlane` builds per turn | 29.1 | **0.0** |

**The speed win is large and the play regression is real but smaller than it first looked.**
`ShotPlane` builds per turn falling to exactly zero is the structural claim, not a speed tweak — line
of fire is a bit test against one `VisibilityField` per target per turn, and the canonical resolver is
consulted only when an action is actually enqueued.

**It is not uniformly worse: when it finishes, it finishes in less than half the turns.** The dominant
failure is `TERMINATED`, the turn cap running out — mostly not losing fights, failing to finish. Two
structural causes were tested and ruled out: the information restriction (identical 33.3% with the
view forced unrestricted) and the candidate-set cull (no change). **Seeds 1, 2 and 6 fail under both
planners**, so three of the eleven failures predate this block and the incremental regression is
eight seeds.

**`MIN_COMPLETION_RATE` went 0.5 → 0.25 → 0.35.** It was landed at 0.25 against a mid-block reading of
37.5%; re-measuring at the end put the real figure at 54.2% and the floor came back up to one seed
below the window the test actually samples. **This is the block's most repeatable lesson: a
measurement taken once, mid-change, is not evidence.** Three numbers here were reported before they
were true, and re-taking them cost minutes and moved the headline by seventeen points.

**A combat-only pool cannot finish a mission, and the head-to-head is what made that concrete.** The
first measurement returned **0% completion** against the old planner's 75% — not because the planner
played worse, but because completion means EXTRACTED and nothing in the Pass B pool could gather an
objective or walk to an extraction tile. The fix was four more `.tres` rows (`seek_objective`,
`gather`, `seek_extraction`) plus the mission inputs to score them over. It also exposed a real
defect the tests had not: candidate cells were computed only when an enemy was known, so a unit with
nothing in sight could not move anywhere at all.

**Three real planner defects, all found by reading the decision log rather than the code.** Each had
survived a green test suite, and each is the kind that a completion rate alone reports only as a
number:
- **A candidate is a (cell, action) pair, and the planner only moved to the cell when the action was
  itself a move.** So `shoot@(3,0)` — chosen because (3,0) sits at a good standoff — was fired from
  wherever the unit already stood. Two units traded shots across a corridor forever, neither closing.
  The log is what exposed it: every entry read `shoot@(3,0)` while the unit sat at (1,0), and the
  mismatch between those two coordinates is the whole bug in one line.
- **A unit standing on its destination scored every OTHER cell as a perfect approach.** `_closes_to`
  returned a flat 1.0 when the distance-to-target was already zero, so a unit that reached its
  extraction tile walked off it and back, every turn, forever — two units alternating onto one tile
  for a whole turn cap, neither ever standing still long enough for the hold to mature.
- **A refused action ended the turn instead of falling through.** `ActionQueue.enqueue` is the only
  thing that knows what a unit can afford from where it will actually be standing, so "the scorer
  wanted this and the executor said no" is ordinary. Stopping there meant a marksman whose own shot
  was unaffordable picked `shoot`, had it refused, and ended its turn — never reaching the overwatch
  it should have held, because overwatch was simply never scored again.

**Holding turned out to be the hardest single action to author, and it broke three different
things.** `HoldAction` keeps the unit CURRENT — that is what deferring means — so anything that lets
it win by default livelocks a bout:
- **It was offered after the unit had already acted.** A unit that spent its whole turn on six shots
  then "held", which is a contradiction: holding is a substitute for acting, not a coda to it. Only
  offered while the turn is still empty.
- **The planner appended `EndTurnAction` behind it.** Hold means *do not end my turn yet*; ending it
  anyway threw the deferral away. `UtilityActionDef.ends_turn` marks the actions nothing may be
  queued behind — data, not an `is HoldAction` branch, for the same reason `repeatable` is.
- **It won by forfeit whenever the candidate scan was short.** The retired planner only held when the
  shot was genuinely blocked; offered unconditionally, hold is what is left when everything else is
  out of range or out of reach. **The view's own `PlanPacer` budget shortens the scan**, so a watched
  bout could livelock where a headless one did not — the worst kind of difference. `lof_blocked` is
  published as an explicit inverse predicate (preconditions are an all-must-hold list with no
  negation) and hold now requires it.

**A missing `await` in the view, exposed rather than caused by this block.**
`SquadControlOverlay._on_turn_ended` called `advance_ai_turns(battle)` fire-and-forget. It is a
coroutine, so the handler returned the instant the planner first suspended and the AI batch completed
some frames later, unobserved. It had no visible effect while the old planner happened never to
suspend on small boards; the utility planner yields through `PlanPacer` on any real candidate set, and
the batch then ran after whatever came next had already read the turn state. Both call sites are
awaited now.

**`hold_position` needed `enemy_known`, which is subtler than it looks.** Holding means "defer to the
next ally, who may open a line" — a combat reason. Offered with no enemy known it broke extraction
outright: `HoldAction` ends the turn itself, so a unit on its extraction tile that chose to hold never
reached the trailing `EndTurnAction` whose hold-check is what matures a hold into a real extraction.
It sat on the tile holding, correctly, forever.

**The candidate rectangle is drawn toward the enemy, and a unit has somewhere else to be.** Culled
alone, a unit that could see an enemy could not consider a single cell toward its resource node or
extraction tile — it could fight or travel, never both. The cells that genuinely close on a mission
destination are added back, at most one per destination.

**Precedence became a weight instead of a branch.** The old planner had a hard "combat first"
ordering above a non-combat branch. Every combat action requires `enemy_known`, so with nothing in
sight the mission actions are the only ones offered and win by default; with an enemy in sight both
compete and the authored weights decide.

**Shots per turn are decided by AP, not by a constant.** `MAX_SHOTS_PER_TURN = 3` is gone; `shoot`
is authored `repeatable` and a turn fires until `ActionQueue.enqueue` refuses the shot it cannot pay
for. `MAX_SELECTIONS` is a backstop deliberately set ABOVE the AP ceiling — it sat exactly at it for
one commit, where the two were indistinguishable, and a test now keeps them apart.

**Moved out of the planner so they could outlive it**: `Cover.is_covered_from` (read by
`StepOutPlanner` and `TacticsController` for the player's own step-out affordance),
`ActionCatalog.preferred_firing_action_id`/`provided_firing_action_id` (a question about the weapon,
not the plan), and `AiPlanner.PLAYSTYLES` (the vocabulary outlives the planner; retiring it is still
`PLAN.md`'s). **~~`AiPlanner.PLAYSTYLES`~~ — overwritten by taskblock-46 Pass E below: the vocabulary
is deleted outright and a bout names a `UtilityProfile` id directly.** `EngagementRect` survived untouched — it was always pure candidate-set geometry with no
planner state in it, which is why it separated cleanly in taskblock-43 and cost nothing here.

**Found and fixed on the way: the AI planning bench had been unable to compile since taskblock-44**
(BR45.02). taskblock-44 Pass C changed the planner's helpers to take a `WorldView` and Pass D made
`_pick_engagement_position` a coroutine; the bench called all of them and was updated for neither.
Nobody found out until Pass D tried to use it. **This is BR40.02's failure mode one directory over**,
so the fix is the class rather than the instance: `tools/checkpoints/parse_guard.gd` now parses every
`tools/*.gd`, not only `tools/checkpoints/checkpoint_*.gd`.

**The guard was wrong before it was right, and the wrongness is the point.** `load()` returns a
`GDScript` object for a script that failed to COMPILE — the resource loads and the compile fails, and
they are separate events — so the widened guard reported "16 script(s) OK" with a deliberate syntax
error sitting in the tree. It checks `reload() == OK` now, and it is verified in both directions:
a deliberate break makes it fail, removing the break makes it pass. `tools/migrate_data.gd` carries
an `@retired-tool` marker — it is a taskblock-10 migration whose own doc comment records that the
generators it walks were deleted by the pass that landed its output, so it can never parse again and
reporting it every build would be noise.

### Search verbs get a memory; one-way ground found underneath them (post-tb46, BR46.01/BR46.02)

**`ROAM` and `HUNT` oscillated between two cells for a whole mission, and it shipped.** Both score
`travel_fraction` — go as far as you can — which is memoryless: the farthest reachable cell from A is
B, and the farthest from B is A. A unit with no enemy in sight walked to the edge of its reach and then
shuttled between two tiles until the turn cap. Found in a supervisor's real combat log, where **every
unit on both squads decided `roam` on every turn and covered two or three distinct cells for the entire
bout**; reproduced on an open board as 6 distinct cells in 14 turns with ten of those turns spent
alternating between `(19,23)` and `(31,23)`.

**taskblock-46 Pass C had already written the fix down and applied it to one verb only.**
`SearchRoute`'s own comment says oldest-visit-wins "cannot ping-pong between two while a third is
ignored" — true, and `PATROL` was the only verb with a route to hang that on. `Unit.recent_cells` now
generalises it: a bounded trail (`RECENT_CELLS` = 8, flagged) written for **every** unit every turn,
not only while searching, because a unit that fought across a room and then lost its target must not
treat that room as unexplored. `UtilityContext.INPUT_UNVISITED` grades it by recency rather than as a
binary visited/not — a binary makes every cell outside the trail identical and permits the same
oscillation with a longer period.

`roam` and `hunt` score it unfloored, so ground just left can reach zero; **`putter` scores it floored
(0.5) on purpose**, because puttering is meant to stay local and an unfloored memory would quietly turn
it into a slow roam. After the fix the same probe covers 15 distinct cells in 14 turns. Regression-
tested as ground covered *and* as an explicit A-B-A-B alternation count, since "it moved a lot" and "it
stopped looping" are different claims and only the second is the defect.

**It did not improve completion, and the 20-seed reading that suggested it had was a lucky draw.** The
deterministic 100-seed escalation after the fix returns **56/100 (56.0%)**; a sample run had shown
14/20 (70%). There is no clean before/after at this sample size — the last 100-seed reading was 60% and
predates Pass E, so it measures a different action pool, and comparing the two would be comparing
builds rather than behaviours. **What the fix demonstrably changed is the failure mode:** `TERMINATED`
— bouts that simply never end, the oscillation's own signature — fell **27 → 20**, while `STRANDED`
rose **13 → 24**. Units that cover ground find each other and some of those fights are lost. The fix is
justified by the behaviour being correct, not by the completion rate, and the remaining gap points at
combat quality rather than at another search gate.

**The escalation also got slower**: it now exceeds 900 s where it used to fit, because bouts run longer
when units actually travel. Mean turns to complete went 19.1 → 26.8.

**Chasing the other half of the same report turned up a bigger, separate problem: 16 of 40 generated
maps contain ground a unit can walk into and never leave** (`BR46.02`, open). Descent is free; climbing
reads a `CLIMBER` part tag that **no part in the repo carries**, so every lowered region is a one-way
door for every unit that exists. Worst seed has 216 such cells.

**A symmetric connectivity check cannot see this, which is why it was never caught** — spawn zones are
mutually reachable on 60 of 60 seeds, so the maps read as fine. The defect only appears under
*asymmetric* reachability: flood out from a spawn, then flood back from each cell reached and ask
whether the spawn is still in the set. Deliberately not fixed here: the direction is a design call
between authoring a `CLIMBER` part, constraining `MapGen` to guarantee two-way connectivity, and having
the planner refuse a one-way step. Recorded with the measurement and the options rather than picked.

**BR32.10 had been misattributed twice and is now split.** "The AI is stuck on a concave map" is a
symptom with at least three unrelated causes: no path to a firing cell (the original, fixed in tb46
Pass C), no memory of where it has been (`BR46.01`), and no way back out of where it went
(`BR46.02`). The combat log distinguishes them; the screen does not.

**BR40.03 and BR40.04 closed `Resolved` by the supervisor.** Worth stating what that does *not* cover:
the sweep behind them measured pit *depth*, not *escapability*. No pits, and still somewhere to get
stuck.

### AI v2, part three: the tier table filled, and the playstyle vocabulary retired (tb46 Passes A–F, docs/11)

**Pass A — nothing sinks into a raised room's floor (BR40.03/BR40.04).** One cause, two entries.
`MapGen._repair_stranded_elevation` floods with a real `Pathfinder` and flattens every unreached `OPEN`
cell to level 0, and `Pathfinder._base_cost` returns `-1.0` for any cell carrying a live blocker — so a
cell a scattered crate had just landed on was **unreachable by construction** and got flattened
regardless of whether anything about it was stranded. For spawn cells the flatten fired and then
`_mark_zone` erased the blocker, leaving a correctly-marked tile a full `LEVEL_HEIGHT` below its own
room; since no part in the repo carries `CLIMBER`, a unit spawned there had exactly one reachable cell
and spent the battle in it. Blocker cells are now deferred out of the flatten and levelled against their
neighbours afterwards.

**The fix was wrong once first, and the miss is the useful part:** the deferred pass checked only
orthogonal neighbours while the flood is 8-way, which left **1 sunk crate out of 9,279** — a single
cell across a 40-seed sweep, invisible to anything but a total count.

**And the tests were vacuous until they were told not to be.** Every assertion in the file is free on a
flat map ("no cell sits in a pit" is trivially true if nothing is ever raised), so a change that quietly
stopped generating elevation would have turned the whole file green while deleting the feature it
guards. `test_the_generator_still_authors_raised_rooms` pins the other side: 30/40 maps still author a
raised room, 3,996 of 22,938 floored cells sit above level 0.

**Pass B — the completion number became re-takeable.** `test_full_mission.gd` sampled seeds 0–11 every
run, which was the *pessimistic* window: 41.7% there against 66.7% on seeds 12–23 on the identical
build, a 25-point spread the test could not see. `CompletionSampler` draws `SAMPLE_SEEDS` random seeds
per run and prints every one, so a run is reproducible after the fact; on a dip it reports the exact
command for the deterministic 100-seed escalation rather than running it automatically.

`SAMPLE_SEEDS` is **sized from the measured escalation cost, not by feel** — at a 0.54 rate against a
0.35 floor, n=10 escalates 1 run in 9 and n=20 escalates 1 in 38 for four seconds more in expectation.
Note the non-monotonicity that makes intuition useless here: n=12 is *worse* than n=10 (0.126 vs 0.114),
because the threshold is an integer count and `ceil(0.35 × 12) = 5` demands 41.7% where
`ceil(0.35 × 10) = 4` demands 40%.

**Pass C — the search verbs, and a bug fixed twice in the same place.** Four behaviours (`ROAM`,
`PATROL`, `HUNT`, `PUTTER`) for a unit with nothing in sight, plus `SearchRoute` for the one verb with
state. Routes are derived lazily from wherever the unit stands, deterministically and without an RNG,
and scheduled by **oldest-visit-wins** — no authored order, no index to advance, so every point gets
visited, it cannot ping-pong between two while a third is ignored, and an unreachable point ages out of
contention on its own with no detect-and-remove step.

`LineOfFire.approach_path`/`closing_path` were deleted here (see `SUPERSEDED.md`); what replaces them is
not a branch at all but path distance from one flood rooted at the target.

**The candidate-cell early-out was wrong for the second time.** `UtilityContext.build` gated computing
candidate cells on having something to move toward, which taskblock-45 Pass D had already found wrong
for the mission actions and this pass found wrong again for the search verbs — for which "nothing in
sight" is the entire trigger. Whatever the list of reasons to move is, it is never complete, and a unit
whose reason is missing from it silently gets a candidate set of one cell. The gate is gone rather than
extended.

**Pass D — `Panic`, the named give-up.** A utility planner can genuinely rate every option at or below
the veto floor, which the branch cascade it replaced could not even express. Panic emits a named event
with a **reason**: `nothing_offered` says the pool has a hole in it for this unit, `all_vetoed` says the
pool covered it and every option scored zero, `budget_aborted` says the clock ran out. Those want
different fixes and used to be the same silent shrug — "the AI just stood there" and "the AI panicked"
look identical from outside.

**It re-broke a guard the retired planner had carried with a comment saying it had been caught live:**
a unit holding its own extraction tile looks identical to a stalled one from the scorer's side, and
panicking it into a shutdown takes a unit that was about to extract cleanly out of the mission.
`EndTurnAction.is_holding_position` is checked first now, and
`test_a_winning_bout_runs_to_a_terminal_state` caught it again — which is the argument for that test
existing rather than for trusting the reasoning.

**Pass E — the tier table, and the playstyle enum retired.**

- **Tier gates.** `shoot` and `take_cover` at Grunt-and-above; `overwatch`, `flank` and `suppress` at
  Trained-and-above. `flank` and `suppress` were the only two tier-table rows whose executors already
  existed — `item`, `call help`, `bait` and `ambush` are **not built**, and `call help` has no mechanism
  at all (a unit cannot influence another unit's plan today). They are `PLAN.md` items, not authoring.
- **Setting a batch objective is Elite-only**, where reading one stays Trained-and-above
  (`WorldView.OBJECTIVE_SETTING_TIERS`). A Trained batch is a real configuration; it just has nobody in
  it who makes the call.
- **`UtilityLookahead` — Elite's depth 2–3 search.** Depth 2 is the enemy's shot from where it stands
  (one visibility field per known enemy, reused across every cell); depth 3 is the enemy moving first
  and then shooting (one field per cell, so it runs over a fixed shortlist of the best-scoring cells).
  It is expressed as **one normalized input** rather than as a minimax beside the scorer, because a
  utility AI has one place to put "this option is worse than it looks" and two ways to decide is the
  no-parallel-systems rule broken. Measured on the reference board: a cell in a wall's shadow predicts
  0.00 threat at depth 2 and 1.00 at depth 3, because the enemy can walk around the wall — cover that
  can be stepped around is not cover, and that is the whole behavioural difference between Elite and
  Trained.
- **The playstyle vocabulary is deleted, bridge and all.** See `SUPERSEDED.md` for what it was; the
  short version is that six names selected between two profiles, five of them landing on the same one.

**Four rows of the table played identically before they were made not to, and both causes were
methodological rather than mechanical.** Elite and Trained had the same action pool, so the comparison —
which read only the pool — declared Elite decorative when its entire difference was in the world-model
and depth columns. And `defensive` withdrew exactly as readily as `cowardly` because it had **no stated
weight** for `seek_extraction`: an absent weight is a neutral opinion, and "defensive" is not neutral
about retreat.

**Two test boards were not the boards their comments described.** Both used `place_floor` plus a
hand-assigned blocker, which is cover that everything can see straight through — sight is blocked by
`Grid.opacity`, which only `GridFixture.place_wall` sets. Fixing that then exposed the opposite error:
a wall drawn *across* the firing lane hid the enemy outright, every combat action fell out of the pool,
and all four profiles returned the single verb they had left. **A board that cannot express a difference
is not evidence that there is none.**

**Completion across the block**, all measured after the fact rather than quoted from a prior pass:
taskblock-45 end 54% → Pass A/B re-baseline 50% (24 seeds) / 54% (100 seeds) → Pass C 60% → Pass D 60%.
The retired branch planner sat at 75% on 24 seeds of fixed ground, so `BR45.03` is narrowed, not closed.

**The one thing this block did NOT establish, stated plainly:** `Unit.intelligence_tier` defaults to
`TRAINED` and **nothing authors it** — not a preset, not a matrix, not a roster entry. Every rate above
is an all-Trained rate, and the Mindless, Grunt and Elite rows, the memory and blackboard gates, and the
entire Elite lookahead are reachable from tests and by hand only. The tier table is built and unshipped;
authoring tiers onto units is `PLAN.md` NEXT item 2.

## Economy

**Inventory & economy** (docs/05) — mass/bulk/RAM; discount once at the worn layer (body-attached
floor 0.8); rigidity (soft collapse, rigid don't); body-carry as inert cargo; 7 resources;
`salvage_yield` on parts. Field objects (scrap_pile, goo_barrel, crate, pillar, forklift w/ POWER
socket, barrel_pallet) — on-board resource/cover, block movement, project into the shot plane.

## Matrices

**Matrices & surrogates** (docs/04) — logic vs intelligence; base/link split; docks into `MATRIX`
socket; surrogates dock like parts (tier DAG); matrices never lost; `Matrix.ai_profile` carries AI
personality (**was `Matrix.playstyle` — renamed by taskblock-46 Pass E, which retired the playstyle
vocabulary; it now names a `UtilityProfile` id**). *Frozen — no more depth.*
