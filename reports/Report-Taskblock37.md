# Taskblock 37 Report — Multi-level: elevation reaches the game

Passes A–D landed in order, each committed separately, full suite green throughout: 2080/2080 at the
end. Pass E is fenced for the supervisor per the taskblock's own instruction; it is now in progress,
run live with the supervisor rather than headless — see the Pass E section below. 2094/2094 at the
end of the work recorded here.

## Decisions made without asking

- **Pass A's `_find_next` `point_depth` anchor fix.** Threading real elevation into the six `build`
  callers exposed a genuine bug, not just plumbing: `_find_next`/`resolve_shot`'s own
  `region_height`/`hit_height` math assumed the dartboard aim point's height was always anchored at
  depth zero — true only for a ricochet's own fresh continuation plane, false for a first hop (the
  aim point sits at the TARGET's own real depth). Fixed by threading a `point_depth` parameter
  through the whole chain, verified provably backward-compatible for every ricochet caller (their own
  `point_depth` is always `0.0` by construction). Flagged as bordering on "new math" per the
  taskblock's own warning, but proceeded since the fix was rigorously derived from the ricochet
  recursion's own existing values, not guessed.
- **Pass B: a new method, not a change to `walk()`/`all_parts()`.** The taskblock's own text reads as
  open to either "walk includes joint handles" or "a dedicated own-regions helper." Repurposing
  `all_parts()` directly would have made a joint's synthetic `hp` (defaults to 1, never touched by
  joint damage) read as a permanently-living part, breaking every `living_parts().is_empty()` kill
  check in the game. Went with the dedicated helper (`PartGraph.walk_with_joints`/`Shell.
  all_parts_with_joints`), touching six call sites instead of `walk`'s many structural ones.
- **Pass C: ramp/climb/hop-down as an EDGE property, not a per-cell one.** `Pathfinder.move_cost`
  became `move_cost(from, to)` — a real signature change, not additive — threading a mover's own
  `can_climb()` capability through every construction site tied to a specific unit. `MapGen`'s own
  internal connectivity check was deliberately left at the default (cannot climb), so baseline map
  reachability never assumes a capability most units don't have.
- **Pass D's ramp height model — asked, not invented.** Whether a ramp's true rest height reads from
  its own `Grid.level` as the lower or upper endpoint was a genuine fork with no single correct
  answer in the taskblock text; asked the supervisor rather than picking one. Confirmed: authored at
  the LOWER endpoint, true height `level + 0.5`.
- **Pass D: `Unit.height: float`, a new field alongside `Unit.level: int`.** `UnitGeometry`'s
  placement math (and `ShotPlane.build`'s own unit-elevation line) needed a real, ramp-aware
  continuous height; `Unit.level` stays the discrete int gating climb/hop/pathing decisions only.
  Synced everywhere `level` already was, plus `MoveAction`'s own per-step update — `level` was never
  re-synced after spawn before this pass, a latent gap only exposed once a unit could genuinely change
  level.
- **Pass D: `RAISED_ROOM_PROBABILITY = 0.35` and the `CLIMBER` tag, both flagged placeholders.**
  Neither is a tuned balance number — the probability is "enough rooms to prove elevation is real
  across many seeds," and no part authors `CLIMBER` this pass (nothing can climb yet, matching the
  taskblock's own scope fence).
- **Pass D: two MapGen connectivity bugs fixed as part of "ramp-reachable," not deferred.** Found by
  running the ramp-reachability test across 50 seeds rather than trusting a handful: `_ensure_spawns_
  connected`'s emergency fallback never reset `Grid.level` when force-opening a corridor (so a forced
  "fix" crossing a raised room stayed climb-gated and fixed nothing), and `_connect_with_a_ramp`'s own
  ring-scan accepted any OPEN-terrain neighbor without checking it was genuinely at a lower level (a
  neighbor that was actually part of a DIFFERENT raised room still reads as plain OPEN, since raising
  a room changes only its level, never its terrain). Both fixed at the source rather than working
  around the specific seeds that exposed them.
- **Pass D: a general `_repair_stranded_elevation` safety net, not another hand-chased special case.**
  Even with both fixes above, a single point-of-failure ramp per room is fragile — `_scatter_cover`
  runs after ramp placement and can land cover on the one ordinary corridor tile leading into a room's
  ramp, sealing the whole room behind it. Rather than chase every such topology by hand, added a
  general flood-and-flatten pass: any `OPEN` cell unreachable from a real anchor via a non-climbing
  `Pathfinder` gets flattened back to level 0. "Ramps couldn't fix it" becomes "don't raise it after
  all," never a silently broken island.
- **Pass D: `test_full_mission.gd`'s seed re-picked (12369 → 12373).** `MapGen` authoring real
  elevation reshuffles the generated layout outright — the exact "adding real content reshuffles a
  fixed seed's whole draw sequence" pattern this file's own header already documents five times over
  for unrelated generator/AI changes. Re-picked by the same brute-force search over nearby seeds the
  file's own convention already uses.
- **Pass D: `ClimbAction`/`HopDownAction` don't integrate with `MoveAction`'s mid-move overwatch hook,
  and no AI path queues either action.** Neither was in the taskblock's own TESTS list for this pass;
  both actions exist, are capability-gated and cost-correct, and are ready for a future pass to wire
  into interruption/AI decision-making. Flagged below, not silently dropped.

## Pass E (supervisor-driven, in progress)

Run live with the supervisor per the taskblock's own fence, not headless. Two rounds so far:

- **The view reads `unit.level`/`unit.height`.** `ResolutionPlayer._world_anchor` reads real cell
  height instead of hardcoding Y=0.0; new `&"climbed"`/`&"hopped_down"` log events carry the same
  `"path"` shape a `move` event does and route through the existing `_play_slide` machinery, so a
  climb/hop-down plays as a real vertical slide with no dedicated animation code; `HitVolumeView`'s
  team marker and facing wedge offset by `unit.height`; `BoutInjector.force_climb`/`force_hop_down`
  (+ debug-panel verbs) let the supervisor trigger either action live.
- **Supervisor's bug report: "Injected states that it raised the level, but no visual change takes
  place."** Root cause: `BoardView`'s ground was one flat `PlaneMesh` for the whole grid — it never
  read `Grid.level` at all, so nothing above could have made the raise visible regardless of how
  correct it was. Asked the supervisor to choose between a smooth heightmap mesh and stepped tiles
  with riser faces; **the supervisor chose stepped/XCOM-style terracing.** Built as `_build_terrain`
  (one flat top quad per cell at its own real height, plus vertical riser quads between differently-
  elevated orthogonal neighbors) and confirmed working live, including on pregen `MapGen` maps.
  Follow-up requested in the same message: `_build_grid_lines` traced the OLD flat plane underneath
  the new terraced floor — given the same per-cell treatment, each cell now drawing its own complete
  border at its own height.
- **Supervisor's question: "Are levels stuck as integers? ... at least half heights."** Ramps already
  give a `+0.5` half-height with no data-model change. Presented three options (ramp-only halves;
  a cosmetic-only float offset layered on top of the integer level; or making `Grid.level` itself
  continuous) with tradeoffs stated up front, including that the third touches `Pathfinder`'s caps,
  `MapGen` authoring, and every existing `level=int` read site. **The supervisor picked the third,
  most invasive option over the recommended smaller one.** `Grid.level`/`Unit.level` are now `float`;
  `Pathfinder.MAX_CLIMB_LEVELS`/`MAX_HOP_DOWN_LEVELS` became real height caps; climb cost scales
  proportionally to rise instead of a flat per-level charge; `HopDownAction`'s drop-distance check
  now goes through `Unit.height`/`true_height_for_cell` (ramp-aware), converging with `ClimbAction`'s
  own convention. **Real bug found during the level-precision audit, not just plumbing:**
  `ShotPlane.build`'s cover/blocker projection used `grid.get_level(cell) * LEVEL_HEIGHT` directly,
  missing a RAMP tile's own `+0.5` offset that `BoardView._spawn_blocker` already rendered cover at —
  a hit on ramp-standing cover could land somewhere the rendered box never occupied. Fixed to read
  `UnitGeometry.true_height_for_cell`, matching the unit projection line just above it.

Still open, per `PLAN.md`: the camera at height and the wall cutout against elevation, neither
exercised live yet.

## Tests that failed, then were corrected

Six across the four passes, three of them deliberate acceptance-test updates (the taskblock's own
"expect to change that test, don't treat its failure as a regression"), three real bugs the test
itself surfaced:

1. **`_find_next`'s `hit_height` formula** (Pass A) — a hand-built elevated-shot debug scenario kept
   logging an impossible height (4.31 world units against a target box spanning 2.0–3.0) before any
   test was even written. Root cause was the same `point_depth` anchor bug described above, present
   in a SECOND spot (`resolve_shot`'s own `region_height` line and `_resolve_slide`'s nudge/lookup)
   that the first fix hadn't reached yet. Fixed in both places; the elevated-target regression test
   added afterward pins the corrected number.
2. **`test_astar_ignores_cell_level_entirely`** (Pass C) — tb36's own acceptance test claimed
   `Pathfinder` ignores level; this pass exists to make that false. Replaced with a uniform-shift test
   (still a no-op — no edge ever tilts) and a genuine-ledge test proving the pathfinder now reacts.
3. **`test_a_fresh_generated_map_is_entirely_level_zero`** (Pass D) — same shape, tb36's own claim
   that `MapGen` writes 0 everywhere. Replaced with "contains more than one level across a spread of
   seeds" plus a dedicated ramp-reachability test.
4. **`test_every_raised_area_is_ramp_reachable_across_many_seeds`, first draft** (Pass D) — an
   over-strict first version asserted every individual raised CELL was reachable, which fails
   whenever ordinary scattered cover (an existing, unrelated risk on ANY room, raised or not) happens
   to land on one tile inside an otherwise-fine room. Rewritten to group raised cells into contiguous
   regions and require at least one reachable entry point per region — the actual claim the taskblock
   makes ("every raised AREA"), not a stronger one about cover interactions the base generator never
   promised either.
5. **The same test, seeds 36/46/49** — three real failures once the region-level version ran across
   50 seeds, each traced to one of the two `MapGen` connectivity bugs above (not test bugs — genuine
   stranded rooms). Fixed at the source; described in the decisions section.
6. **`test_full_mission_seed_to_extraction`** — failed outright once `_author_levels` landed (seed
   12369's map changed). Not a regression: a legitimate, expected seed re-pick per this file's own
   established convention.

## `SUPERVISOR`-owned entries moved to `Pending`

None. `BR36.01` (found during tb36, fixed this taskblock's Pass B) was `CC`-owned — closed directly,
moved to `docs/BUGS-ARCHIVE.md` in its own commit.

## Open questions

- **Pass E's remaining two items** — camera-at-height behavior and wall-cutout interaction against
  elevation. Needs the supervisor watching, per the taskblock's own explicit fence; not yet
  exercised live.
- **No AI path queues `ClimbAction`/`HopDownAction` yet**, and neither integrates with `MoveAction`'s
  own mid-move overwatch-trigger hook. Both actions are real, tested, and capability-correct on their
  own — whether an AI-driven unit should ever choose to climb, and whether climbing/hopping should be
  interruptible the same way an ordinary move is, are follow-on design questions this taskblock's own
  TESTS list didn't require answering.
- **`RAISED_ROOM_PROBABILITY = 0.35`** is a flagged, tunable placeholder — how much of a generated map
  should actually be elevated is a real design question, not decided here.
