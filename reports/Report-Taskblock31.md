# Taskblock 31 Report — View & Control Consolidation

Pre-work review (before any pass started) is preserved in `tempnotes.md` at the repo root — three
findings from cross-checking the original tb30-sourced spec against the actual code (Pass A's
`ControlsOverlay` H-key toggle already existing, Pass C's `Pathfinder`/`hp` passability gap, Pass D's
`arm_action` architecture tension). The supervisor refined `taskblock31.md` directly in response
before work started; all three are reflected in the current spec.

## Pass B — give squad control a real UNASSIGNED state

**Done.** `SquadController` was a hard binary `{HUMAN, AI}`, so `CombatState.controller_for()`'s
`.get(squad_id, HUMAN)` fallback had to pick a side — and the bout path that assigns nothing
(`_seed_battle`) silently inherited it wrong (BR30.09's root cause).

- `UNASSIGNED` added as the zero-default (first enum value), annotated to stay consistent with
  `enums.gd`'s own "no third way to take a turn" comment — it's a setup-time state, not a way to
  take a turn.
- `BoutRunner._init()` is the one validation point: `CombatState.all_squads_assigned()` (new,
  checks every squad actually present on the board) must be true, or it `push_error()`s (loudly,
  `assert_push_error`-testable) and marks itself `finished` immediately — an ill-defined bout can
  never actually run.
- `_seed_battle()` ("New Battle") now calls `state.assign_rest_to_ai([0])` explicitly — squad 0
  (the player's own squad, same seam `toggle_blue_control()` flips) HUMAN, the rest AI.
  `bout_setup.gd`'s existing explicit `set_squad_controller` calls needed no change — already
  explicit, outcome unchanged.
- `bout_runner.gd`'s own `step()` fallback: `!= AI` (which used to also silently catch an
  unassigned squad) replaced with an explicit `== HUMAN` check — UNASSIGNED can't reach that line
  at all now (refused at construction).
- New `CombatState` authoring convenience: `assign_all_to_human()` ("Control All Squads," a visible
  call now) and `assign_rest_to_ai(human_squads)` (the "mostly AI" shortcut).
- Docs updated: `enums.gd`'s own `SquadController` comment, `docs/10-view-and-input.md`'s "Manual
  control of both sides" section.

**Blast radius, found by running the full suite rather than grepping every fixture by hand:** four
existing tests built a `CombatState` relying on the old implicit HUMAN default (never calling
`set_squad_controller` at all) and broke against the new hard validation —
`test_single_unit_overlay.gd` (3, `SingleUnitOverlay.wants_turn_for` doesn't consult squad
controllers at all, but `BoutRunner._init()` still validates the underlying state regardless) and
`test_battle_scene.gd`'s repair-button test (1, `SquadControlOverlay`'s `battle_loaded` reactivity
ran `advance_ai_turns()`, and thus a `BoutRunner`, before the test's own manual repair steps). All
four fixed with an explicit `assign_all_to_human()`/`set_squad_controller` call.

Tests: `test_combat_state.gd` (UNASSIGNED default, `assign_all_to_human`/`assign_rest_to_ai`,
`all_squads_assigned`), `test_bout_runner.gd` (hard construction error via `assert_push_error`,
human-controlled-squad fixture updated to assign explicitly). 1872/1873 green — the one remaining
failure is the already-known, out-of-scope `test_full_mission.gd` (PLAN.md: decided-retire).

Commit `03c19b2`.

## Pass A — control-surface audit (deliverable, before any refactor)

Read all four overlays' `_build_ui()` in full. `SingleUnitOverlay extends SquadControlOverlay` and
builds no UI of its own — it inherits the whole thing verbatim, so it isn't a separate row below.

| Control | SpectatorOverlay | SquadControlOverlay (+ SingleUnitOverlay) | GenerateBoutOverlay |
|---|---|---|---|
| Inject... + DebugControlPanel | yes — top-left `controls` row, debug-gated | yes — `left_layout` (inventory column), debug-gated | no |
| New Battle | **no** | yes — top-right | no |
| Watch / Assume Control | yes, labelled **"Assume Control"** — top-left `controls` row | yes, labelled **"Watch"** — top-right | no (has its own "Assume Control of Squad A" checkbox — unrelated, pre-bout config, not this toggle) |
| Play / Step / Speed | yes — top-left `controls` row | no (a human paces their own turns) | no |
| Tunables (slide/bullet ms, tracer count) | yes — top-left `tunables` row | no | no |
| Keybindings (`ControlsOverlay`) | **no instance exists at all today** | yes — top-right, under New Battle/Watch, always-visible label, H-key toggle already wired (`label.visible`) | no |
| Inspect / Repair | no | yes — `left_layout` | no |
| Resolve to Here / End Turn / Reset Turn | no | yes — bottom-right `turn_controls_column` | no |
| Action bar / AP-MP pips / queue panel / weapon panel / readout | no | yes — mode-specific tactical HUD | no |
| Roster rows, seed field, Start Bout | no | no | yes — entirely mode-specific pre-bout setup |

**What consolidates:** Inject (both have it, identical shape, only the `bout_injector`/
`input_owner` wiring differs), Watch/Assume Control (literally the same `toggle_blue_control()`
call in both — only the hardcoded label differs by which direction you're toggling FROM), New
Battle (SquadControlOverlay-only today, no reason Spectator would want it — a spectated bout has
no "New Battle" concept of its own, stays where it is). All three, once shared, land in the
**top-left** corner — where SpectatorOverlay's own cluster already sits (`(16, 16)`); the SAME
corner `DebugControlPanel`'s own `_center_top` fix was originally guarding *against* colliding with
(the panel used to spawn with no anchor at all, right on top of this exact row — its own test file
header documents this). SquadControlOverlay's own copies (Inject in the left inventory column,
New Battle/Watch top-right) physically MOVE to top-left to match.

**What's genuinely mode-specific, stays local:** Play/Step/Speed/tunables (Spectator-only pacing
controls — a human player doesn't need a speed dial for their own turn); Inspect/Repair/turn
buttons/action bar/readouts (the whole tactical HUD, SquadControlOverlay-only); everything in
GenerateBoutOverlay (a pre-bout setup screen, no overlap with the in-battle cluster at all).

**Keybindings toggle:** only `SquadControlOverlay` has a `ControlsOverlay` instance today —
Spectator never had one. Scope fence says "no genuinely new control the overlays don't already
have," so the `Keybindings` button is added only where the display already exists
(`SquadControlOverlay`/`SingleUnitOverlay`), not newly invented for `SpectatorOverlay`.

## Pass A — implementation

**Done.** New `src/view/top_left_controls.gd` (`TopLeftControls extends HBoxContainer`) is the one
shared construction path for Inject/New Battle/Watch, matching the `DebugControlPanel`/
`InspectPanel` "shared class + setup()" convention already used everywhere else:

- `setup(battle, on_inject_pressed, include_new_battle, watch_label)` — `on_inject_pressed` stays
  each overlay's OWN existing handler method (passed in, not reimplemented): `_build_ui()` runs
  BEFORE `battle.bout_injector` necessarily exists (only built inside `load_battle()`), so baking
  either overlay's `bout_injector` reference in at `setup()` time would go stale; reading it live at
  click time (as both overlays' own pre-existing handlers already did) sidesteps that entirely.
  `watch_label` stays a plain caller string too ("Watch" / "Assume Control") for the same reason —
  deriving it from `controller_for(0)` at build time isn't safe when `battle.combat_state` may not
  exist yet.
- `SquadControlOverlay`: Inject moved out of the inventory column, New Battle/Watch moved out of
  the top-right corner — all three now anchor together, top-left, self-positioned (no pre-existing
  row to nest into). Field aliases (`inject_button`/`new_battle_button`/`watch_button`) kept
  pointing straight into the shared instance so every existing external reference/test kept working
  unchanged.
- `SpectatorOverlay`: Inject/Assume-Control now build through the same shared class, added as a
  plain (unanchored) child of the overlay's own pre-existing top-left `controls` row (alongside
  Play/Step/Speed) rather than a second independently-anchored group — `include_new_battle = false`.
- Found and fixed a real bug while wiring this: `TopLeftControls`'s own `_init()` first set its
  `mouse_filter` to STOP (copying `SpectatorOverlay`'s own pre-existing `controls` row, which
  apparently already had this same latent issue, just never scanned by the one test that would have
  caught it — `SquadControlOverlay` is the DEFAULT overlay that test builds). Fixed to IGNORE,
  matching the established, correct convention (`left_layout`/`top_right` in
  `squad_control_overlay.gd`): the wrapping container passes clicks through in the gaps between
  buttons; each `Button` child already defaults to STOP on its own, which is what actually needs to
  catch a click ON one of them.
- `Keybindings` button (`SquadControlOverlay`/`SingleUnitOverlay` only, per the audit) toggles the
  exact same `ControlsOverlay.label.visible` the H-key already flips — `ControlsOverlay.setup()` now
  defaults that label to `false` (was implicitly `true`, Control's own default).

**Test/source updates required by the move:**
- `test_bout_injector_determinism.gd`'s own static source-scan for "Inject gated behind
  `OS.is_debug_build()`" used to check both overlay files directly; retargeted to
  `top_left_controls.gd` — the ONE place that construction lives now, a stronger single-source-of-
  truth guarantee than the old duplicated-per-overlay version.
  `test_bout_injector_is_referenced_by_both_overlays` (a separate, still-valid test — checks the
  string `bout_injector` appears in each overlay file, not the button construction itself) needed no
  change: both overlays still legitimately reference `bout_injector`/`debug_panel` in their own
  `_on_inject_pressed` handlers.
- `test_battle_scene_input.gd`'s existing recursive STOP-filter scanner caught the
  `TopLeftControls` mouse-filter bug above directly — no test change needed, it did its job.
- `test_controls_overlay.gd`'s default-visibility tests flipped to match the new OFF default.

**New tests:** `test_squad_control_overlay.gd` (shared-cluster field aliasing; a real geometric
overlap check between the top-left cluster's rect and the debug panel's own centered rect, both
read back from real nodes per docs/10 standing rule 2 — no "existing" overlap test was literally
found to extend, despite the taskblock's own wording, so this is a new one covering that intent;
the Keybindings button toggling the same label the H-key does), `test_spectator_overlay.gd` (the
shared cluster correctly omits New Battle and labels the toggle "Assume Control" from this side).

1876/1877 green — the one remaining failure is the already-known, out-of-scope `test_full_mission.gd`.

## Pass C — wall = destructible cover part; void = the fill

**Done.** Retired BR30.10's indestructible-wall-terrain model entirely, replacing it with the
settled one from the refined spec.

- **`Enums.TerrainType.VOID`** added (appended, not inserted mid-enum — no renumbering risk for
  anything that might store a raw int). `WALL` stays in the enum (hand-built test fixtures still
  legitimately construct it directly) but is now vestigial as of `MapGen.generate()`'s own output —
  every real generated map resolves it away.
- **`MapGen._finalize_walls_and_void()`** (replacing BR30.10's `_stamp_wall_geometry`) is the one
  place `WALL` (only ever a scratch "not yet carved" marker while `_split_and_carve` runs) gets
  resolved into its final form, run last: a WALL cell bordering at least one non-WALL cell becomes
  ordinary `OPEN` ground carrying a wall `Part` blocker (opacity left at the `1.0` the initial
  full-grid fill already gave it — an intact wall must keep blocking LoS/tactical-cover checks
  exactly as before; only the terrain/blocker REPRESENTATION changed here). A WALL cell buried in
  solid, unreachable rock (no non-WALL neighbor) becomes `VOID` instead — non-navigable, opacity 0,
  no Part — same perf reasoning BR30.10 already established for skipping it (never the nearest hit
  along any real ray).
- **`data/parts/wall.tres`** re-authored destructible: `is_destructible` removed (default `true`),
  `hp`/`max_hp` dropped from the old placeholder `999` to `60` — flagged, tunable "very-high-DT," not
  a real balance number (CLAUDE.md: never invent one and present it as final). Added a modest
  `salvage_yield` matching every other destructible field object's own convention.
  `ShotPlane`/`BodyProjector` needed no change at all — they already treat a wall exactly like any
  other blocker Part, and already skip a 0-hp Part when resolving a shot.
- **Shared `Pathfinder.move_cost()` fix** (found while implementing this, exactly the concern raised
  in pre-work review): it only ever checked `blockers.has(cell)`, never the blocker's own `hp` — so a
  DESTROYED blocker (a dead crate, same as a destroyed wall) walled off its own tile forever, even
  though `ShotPlane` already correctly let a shot pass through it. Now reads `hp > 0` too — a
  destroyed blocker clears to fully passable, wall or ordinary scatter cover alike, one mechanism for
  both. Mangle/wreck states (a destroyed blocker leaving passable-but-difficult rubble instead of
  fully clear ground) are explicitly deferred to a future authoring pass (filed in `docs/PLAN.md`) —
  this pass's own contract is exactly "clears to fully passable," nothing partial.
- `CombatState.terrain_costs`'s own default gained `VOID: -1.0` alongside the existing `WALL: -1.0` —
  a freshly generated map's negative space needs to read as impassable at runtime same as WALL always
  did. `AsciiRender` gained a `VOID` glyph (a blank space — "nothing there"); a MapGen-produced wall
  needed no new glyph at all, since it's OPEN ground with a full-height blocker, already caught by
  the existing cover-height fallthrough branch.
- **`docs/02-projection-and-targeting.md`** revised per the taskblock's own instruction — the old
  "terrain is a Part flagged indestructible" line replaced with the settled model: a wall is high-DT
  destructible cover on an otherwise-passable tile; what's actually indestructible is the void past
  it (no Part, nothing to hit or destroy).

**Render legibility** (the other half of Pass C, "land even if the model above slips" — didn't
slip, landed together): new `src/logic/wall_legibility.gd` (`WallLegibility.occludes(camera_position,
focal_position, wall_position, radius)`) is pure geometry — camera/focal/wall positions as plain
`Vector3`s, zero SceneTree dependency, headless-tested directly (`test_wall_legibility.gd`, 7 cases:
directly-between, behind-focal, behind-camera, off-sightline-past-radius, just-inside-radius,
AT-the-focal-point-itself, camera-coincident-with-focal). `BoardView` tracks its own wall meshes
separately from ordinary cover (`_wall_mesh_instances`, populated in `_spawn_blocker` when
`part.id == &"wall"`), gained a settable `focal_unit: Unit` (null = nothing to protect, every wall
sits opaque), and re-evaluates every frame (`_process` — camera drag-to-orbit has no signal of its
own to react to) via `update_wall_legibility(camera)`, split out from `_process` specifically so a
test can drive it against a real, deliberately positioned `Camera3D` (docs/10 standing rule 2 — 3
tests in `test_board_view.gd`: fades a wall genuinely in the way, leaves walls opaque with no focal
unit set, leaves an unrelated off-sightline wall opaque). Chose FADE (`GeometryInstance3D.
transparency`, a flagged `0.75`) over cull/dither — the wall's own presence (still real, shootable
geometry) shouldn't vanish outright, only stop hiding what's behind it. Wired from
`SquadControlOverlay._on_selection_changed()` (`board_view.focal_unit = selected`) — the one overlay
where "protect the player's read of their own selected unit" has an obvious, unambiguous target;
`SpectatorOverlay`/`GenerateBoutOverlay` never set it, so fading simply never runs there (no clear
single focal unit in either mode).

**Test/source updates required by the model change:** `test_map_gen.gd`'s own BR30.10 tests
(`test_exposed_wall_cells_carry_a_blocking_part_interior_walls_do_not`,
`test_walls_are_opaque_and_open_cells_are_not`) assumed a WALL-terrain-survives-generation model
that no longer holds — rewritten as
`test_generate_resolves_every_wall_cell_into_a_destructible_part_or_void` and
`test_opaque_exactly_where_a_wall_part_sits_transparent_everywhere_else`. `test_cover_density_
within_target_band` was silently counting every wall-Part cell as "scattered cover" once walls
stopped being WALL-terrain (density jumped to 50-60%, way out of its 8-30% band) — fixed to exclude
both VOID and wall-Part cells from the measurement, restoring its original meaning ("how much of the
real walkable floor got a scattered cover roll").

**New tests beyond the model-change fixes:** `test_pathfinder.gd` (a destroyed field object clears
to passable — the shared fix, generically; VOID is impassable; a real `wall.tres` blocks movement
intact and clears once destroyed), `test_los.gd` (VOID never blocks LoS, mirroring the existing
cover-doesn't-block-LoS test), `test_shot_plane.gd` (destroying a wall removes its region from the
plane, mirroring the existing destroyed-cover test).

1891/1892 green — the one remaining failure is the already-known, out-of-scope `test_full_mission.gd`
(now failing on turn-cap/extraction instead of survivor-count, consistent with missions running
longer under correct wall-blocking — no new information, same known gap).

## Pass D — every action on the bar the same way (targeting mode, not a bool)

**Done.** `ActionDef.requires_target: bool` only ever expressed two shapes when there were three —
this promoted it to a real `Enums.TargetingMode` (`BOARD`/`NONE`/`PART_PICKER`), and both overwatch
and repair now reach the bar directly instead of being bolted onto `SquadControlOverlay` as
one-off buttons.

- **`Enums.TargetingMode`** — closed engine state (CLAUDE.md: enums for engine states, not content),
  same home as `SquadController`/`TerrainType`. `ActionDef.targeting_mode` replaces
  `requires_target` outright (not kept alongside it — the two-shapes-in-a-bool debt the taskblock
  itself called out).
- **`ActionCatalog.build_untargeted_action(action_id, unit, weapon_id)`** — the `NONE`-mode
  counterpart to `build_firing_action`, today just `&"overwatch"` -> `OverwatchAction.new(...)`. Same
  "one seam, never invents an action for an id it doesn't recognize" posture.
- **`ActionBar._on_box_gui_input()`** now dispatches by `def.targeting_mode` in one closed match, no
  per-action-id branching: `BOARD` -> `tactics.arm_action()` (unchanged); `NONE` ->
  `tactics.queue_untargeted_action()` (new — builds via the catalog above, enqueues immediately);
  `PART_PICKER` -> `tactics.picker_action_requested.emit(action_id)` (new signal). `arm_action()`
  itself now refuses anything that isn't `BOARD` (was `not requires_target`) — the same invariant,
  restated honestly instead of via a bool that only ever meant "board or not."
- **`SquadControlOverlay`** connects `picker_action_requested` to a small dispatcher
  (`_on_picker_action_requested`, currently a one-arm match since repair is the only `PART_PICKER`
  action) that calls the SAME pre-existing `_on_repair_pressed()` — its popup logic is completely
  unchanged, just reached from the action bar's own repair slot instead of a standalone button,
  which is now retired (`repair_button` field and construction removed). The popup's own anchor point
  moved from the retired button's screen position to the current mouse position (`InspectPanel`'s
  own debug-menu "at_position" convention) since there's no button left to anchor on.
- **Overwatch's own first real UI call site.** It had no button, bolted-on or otherwise, before this
  (`action_def.gd`'s own long-standing comment: "still has no UI call site at all") — `NONE` mode is
  simply the first time it's reachable at all, via the bar.
- **Two BR30.11-shaped AP-cost mismatches found and fixed while wiring both actions up for the first
  time**, extending `ActionCatalog.ap_cost_for()`: `OverwatchAction` always charges a fixed
  `AP_COST = 1`, never the weapon's own `ap_cost`; `RepairAction` always charges the fixed
  `RepairResolver.REPAIR_AP_COST = 4`, never the welder's own `ap_cost` (unauthored on the real
  `arc_welder.tres`, silently falling back to `Part.gd`'s bare default of `1` — 4x too cheap by the
  bar's own old reckoning). Neither was player-visible before, since neither action had a bar slot at
  all until this pass — but wiring them up without this fix would have shipped the exact same class
  of bug BR30.11 just fixed for burst, on day one.

**Test/source updates required by the rename:** every `requires_target` reference across
`test_action_catalog.gd`/`test_tactics_controller_arm.gd` updated to the new enum (repair's own test
renamed `test_repair_def_is_a_part_picker`, checking `targeting_mode == PART_PICKER` directly instead
of a bare bool).

**New tests:** `test_action_catalog.gd` (overwatch's own `targeting_mode == NONE`), `test_action_bar.gd`
(a `NONE` click queues immediately and never arms — asserts a real `OverwatchAction` lands in the
queue; the new repair/overwatch AP-cost mismatches, mirroring burst's own regression test shape),
`test_squad_control_overlay.gd` (a real click on the action bar's own repair slot opens the same
popup `test_battle_scene.gd`'s own end-to-end repair test already proves resolves correctly — the
other half of "one path, no parallel logic").

1895/1896 green — the one remaining failure is the already-known, out-of-scope `test_full_mission.gd`.

## Pass C — two real bugs found in live play, after the fact

Supervisor report, live play: "walls are generating where voids should [be]... there should be a
single layer of walls," and "I can't see wall fading doing anything." Both real, both fixed.

**Wall/void classification cascaded through solid rock.** `MapGen._finalize_walls_and_void`
classified AND mutated each WALL cell in the same scan pass — converting an exposed cell to `OPEN`
made it read as a non-WALL neighbor for whatever WALL cell got scanned next, so exposure cascaded
outward from every real opening through however much solid rock the scan order happened to reach.
A real ASCII dump (seed 2, 40x30 — `BattleScene`'s own defaults) confirmed it: walls many tiles
thick, effectively zero `VOID` anywhere on the map. Fixed by splitting into two passes — classify
every WALL cell's exposure against the grid's own untouched layout first, then apply every mutation
in a second pass. Re-dumped the same seed: clean single-tile wall rings with real void space.
Commit `9909d73`.

**Wall fading never actually triggered.** The occlusion check was WORLD-space: "is this wall within
1 unit of the straight 3D line from camera to the focal unit." The tactical camera sits well above
and back from the board (`CameraOrbitState.DEFAULT_PITCH`/`DEFAULT_ZOOM`), so that line spends
almost its entire length far above wall height — the check essentially never fired for any wall
more than a cell or two from the unit, which is exactly the case that matters. Rewrote
`WallLegibility.occludes()` -> `occludes_on_screen()`: project both the wall and the focal unit
through the real camera (`Camera3D.unproject_position()`), compare 2D screen distance, and require
the wall to be nearer in depth — the question a player would actually answer by eye, independent of
camera angle. `BoardView.update_wall_legibility()` updated to match (`WALL_FADE_RADIUS` in cells ->
`WALL_FADE_SCREEN_RADIUS` in pixels), guarding both wall and focal position against
`camera.is_position_behind()` (nonsense screen coords for anything not actually in view).
`test_wall_legibility.gd`/`test_board_view.gd` rewritten for screen-space geometry (the board-view
tests use a real `Camera3D.look_at()` on the focal unit, not a hand-picked world position, so the
wall's own projected screen position is genuinely derived from the real camera, not assumed).

1894/1895 green (the one remaining failure is `test_full_mission.gd`, unrelated, already known).

## Pass C — follow-up: real alpha blending, and void tile visuals

Supervisor report, live play again: "the wall fading is still not occurring, is it drawing between
the camera and the orbited point, or is it something else?" Traced the WHOLE pipeline end to end
through the real production path (not just unit tests) to answer precisely: built a real
`BattleScene`/`SquadControlOverlay`, selected a unit via the real `click_cell()` path, centered the
real `CameraRig` on it, and read every intermediate value back — `focal_unit` wiring, `Camera3D`
ownership (`current`/viewport match), `unproject_position()`/depth math, all confirmed correct. Found
one real mistake along the way (my own diagnostic forgot to set `focal_unit` before calling
`update_wall_legibility()` directly, making early throwaway checks read as "never fades" — a false
lead, not a game bug) — once corrected, the pipeline genuinely flips `transparency` to `0.75` for a
real wall between a real camera and a real selected unit.

That confirmed the ONE link never directly verified: whether `GeometryInstance3D.transparency` alone
renders a visible effect against an otherwise-opaque, `SHADING_MODE_PER_PIXEL` material. Real
geometry must stay lit (docs/10) — this file's own unshaded `WorldPalette.translucent_material()`
(what `show_unit_ghost()`/`show_overwatch_arc()` use) isn't an option for a wall. Switched to real
alpha blending instead: `BaseMaterial3D.TRANSPARENCY_ALPHA` + a real `albedo_color.a` value, the
exact mechanism `show_unit_ghost()` already proves renders correctly in this project, just kept lit.
`BoardView._set_wall_alpha()` (new) is the one place this happens; `WALL_FADE_ALPHA := 0.25` replaces
`WALL_FADE_TRANSPARENCY`. Tests updated to read the real material's alpha back
(`test_board_view.gd::_wall_alpha()`), not a `GeometryInstance3D` property. Commit `dda90d4`.

**Void tile visuals.** "Make void tiles black with a dark gray border so they read as void" — the
exact "non-navigable terrain needs a real marker" convention `WALL_INDICATOR_COLOR`/`WALL_CROSS_COLOR`
already established for WALL cells, extended to VOID: `_build_void_indicators()` (new, mirrors
`_build_wall_indicators()`) draws a near-full-cell dark-gray border marker plus a smaller black fill
marker per VOID cell — border+fill instead of marker+cross, since void isn't an obstruction to cross
out, it's the absence of anything at all. `_marker()` gained an optional `size` parameter (defaults to
`OVERLAY_SIZE`, every existing call site unchanged) so the border/fill pair can use two different
footprints. Slotted into the file's own documented ground-overlay height ladder (between the wall
indicator and the wall cross) per its own stated convention, even though void never actually coexists
with any of the other rungs on the same cell.

1896/1897 green (the one remaining failure is `test_full_mission.gd`, unrelated, already known).

## Taskblock 31 — closing summary (2026-07-21)

All four passes done, tested, committed, confirmed working in player view. `./run_tests.sh` is green
(1896/1897) except the one known, decided-to-retire `test_full_mission.gd` failure (PLAN.md) —
unrelated, unchanged all block.

**Pass B — squad control gets a real `UNASSIGNED` state.** `SquadController` was a hard binary
`{HUMAN, AI}`, so `controller_for()`'s own fallback had to silently pick a side — the exact silent
inheritance that caused BR30.09. `UNASSIGNED` is now the zero-default; `BoutRunner._init()` hard-
errors (loudly, testably via `assert_push_error`) if any squad on the board is still unset when a
runner is actually constructed, making that whole bug class structurally impossible. New
`CombatState.assign_all_to_human()`/`assign_rest_to_ai()` are the visible authoring-layer shortcuts
replacing the old hidden getter default. Commit `03c19b2`.

**Pass A — one control surface instead of four.** New shared `TopLeftControls` class is the single
construction path both `SpectatorOverlay` and `SquadControlOverlay` call into for Inject/New Battle/
Watch (previously each built its own copy independently). Found and fixed a real latent click-
passthrough bug along the way (the shared container's own `mouse_filter` defaulted to STOP, copying
an issue that was already present in `SpectatorOverlay`'s pre-existing row but never caught since
nothing had scanned that overlay's tree before). Keybindings display now defaults off (reference, not
chrome) with a button alongside the existing H-key toggle. Commit `f21d889`.

**Pass C — walls are destructible cover, not indestructible terrain; void is the fill.** Retired
BR30.10's indestructible-wall-terrain model: a wall is now a blocker `Part` (like any scatter-cover
item, just high-DT) sitting on an otherwise-passable tile, and a new `VOID` terrain type is the
negative-space fill past a wall's own ring. Found and fixed a shared `Pathfinder` bug in the process —
destroyed blockers (walls *and* ordinary cover) had always blocked movement forever, since `move_cost`
only checked a blocker's presence, never its `hp`. Added camera-relative wall fading so walls don't
block the player's read of the action behind them. Commits `4efa5b9`, `8f8d9e5`.

Two more real bugs surfaced once this actually ran in player view, both found and fixed same-day:
- **Wall/void classification cascaded through solid rock** — `_finalize_walls_and_void` classified
  and mutated each cell in the same scan pass, so converting a cell to `OPEN` made the NEXT cell
  scanned see it as an opening too, cascading outward through however much solid rock the scan order
  reached. Real maps showed walls many tiles thick, void nearly absent. Fixed with a two-pass
  classify-then-mutate split; verified against a real generated map's own ASCII dump. Commit `9909d73`.
- **Wall fading never actually fired, then fired but stayed invisible.** First found: the occlusion
  check was world-space (distance from a wall to the straight 3D camera-to-focal line), but the
  tactical camera sits well above/back from the board, so that line spends almost its whole length
  far above wall height — rewrote as screen-space (`camera.unproject_position()` + depth ordering,
  commit `662e8d2`). Then found: even with correct occlusion math, `GeometryInstance3D.transparency`
  wasn't rendering a visible effect against an otherwise-opaque, `SHADING_MODE_PER_PIXEL` (lit) wall
  material — switched to real alpha blending (`BaseMaterial3D.TRANSPARENCY_ALPHA` + `albedo_color.a`),
  the same technique `show_unit_ghost()` already proves works in this project (commit `dda90d4`).
  Confirmed working in player view.

Also added, on request: void tiles now render black with a dark gray border (commit `9c06e09`),
matching the existing wall-indicator convention.

**Pass D — every action arms from the bar the same way.** `ActionDef.requires_target: bool` only
ever expressed two shapes when there were three; promoted to a real `Enums.TargetingMode`
(`BOARD`/`NONE`/`PART_PICKER`). Overwatch (`NONE`) and repair (`PART_PICKER`) now reach the action
bar directly instead of being bolted onto `SquadControlOverlay` as one-off buttons — overwatch's
first real UI call site ever. Found and fixed two more BR30.11-shaped AP-cost mismatches while wiring
both up for the first time (`OverwatchAction`/`RepairAction` each always charge their own fixed cost,
never the providing part's `ap_cost` field). Commit `a48c157`.

**Open for next session, per the supervisor's own note:** wall fading/legibility works correctly in
player view now, but may want a refactor pass — to be scoped in review chat, not yet a concrete task.
