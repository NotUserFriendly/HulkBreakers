# Taskblock 32 Report — View & Targeting

All four passes done, in the taskblock's own stated order (A→B→C→D). 1932/1933 tests green
throughout — the one failure is the pre-existing, deliberately-flagged full-mission smoke test
(`docs/PLAN.md`: kept RED until a `BoutSetup`-based replacement is written; unrelated to this work).

## Pass A — wall occlusion cutout shader

Supersedes tb31 Pass C's per-wall GDScript alpha-blend stopgap (`BoardView.WALL_FADE_ALPHA`/
`_set_wall_alpha`, one focal unit at a time) with a lit, per-fragment dithered `discard`
(`src/view/shaders/wall_cutout.gdshader`) on one shared `ShaderMaterial` for every wall. GDScript's
only job now (`BoardView.update_wall_cutout()`) is projecting every unit in `wall_cutout_units` to a
screen position/depth/tile-derived pixel radius (`WallLegibility.pixel_radius_for_tiles`, new pure
helper, headless-tested) and feeding them as uniforms each frame; the shader decides per-fragment
whether to discard (within radius of any fed unit **and** nearer the camera than it — a wall behind
the unit is never cut). Cuts around every unit at once now, not one focal unit. Player view feeds
`CombatState.units` (live array reference, set once at battle-load); spectator never sets it, so the
cutout simply never fires there (unchanged, flagged as trivial to wire later). This is the first
hand-written shader in this codebase — no existing convention to match beyond docs/10's "real
geometry stays lit" rule, which the shader honors (`ALBEDO`/lighting untouched, no `render_mode
unshaded`). Commit `7cfa1ad`.

## Pass B — friendly-ghost fade when a teammate blocks your own aim

In dartboard/aiming view only, a friendly unit standing between the camera and the active (shooter)
unit now gray-ghosts — heavier alpha than the existing team-colored end-of-move ghost, its own
`_friendly_fade_overlay` container so the two never clobber (the team-colored ghost can be live for
the selected unit at the same moment a *different* friendly needs fading). Reuses Pass A's occlusion
test unchanged (`WallLegibility.occludes_on_screen`/`pixel_radius_for_tiles`) against
`BoardView.aim_active_unit` instead of a wall. Gated to same-squad units only, never the active unit
itself, and only while `tactics.aiming_at != null` — `SquadControlOverlay._on_selection_changed()`
owns exactly when that's set/cleared. `show_unit_ghost()`'s box-building loop was factored into a
shared `_ghost_boxes()` helper so the team-colored and gray-faded paths share the same rendering
technique without sharing a container. New tests split into `test_board_view_occlusion.gd` (tb32 A+B)
to stay under gdlint's `max-public-methods`, matching the existing `test_tactics_controller_*.gd`
split convention. Commit `b6886b3`.

## Pass C — `PartPicker`: target anything, not just enemies

The biggest pass by far — turned out to reach much deeper than "targeting-input only, not
resolution," the taskblock's own framing. Flagged to the supervisor mid-pass and given the go-ahead
for full scope rather than descoping.

A click can now resolve to a specific non-unit Part (`Enums.HitKind.PART`, new): scatter cover, a
wall, a downed bot's shell, a loose field item — not just a live unit's own body (`HitKind.UNIT`,
unchanged) or bare ground (`CELL`). `PartPicker.hit()` generalizes `UnitPicker` (still the unit-ray-
test underneath, via `UnitPicker.ray_box_t` made public) to also ray-test every
`Grid.blockers`/`field_items` Part through the same boxes `BoardView` renders
(`UnitGeometry.assembly_placements`) — reports the cell's own root Part, matching the granularity
`ShotPlane` itself already tags regions with (`region.body`), not a deeper sub-part within an
assembly.

`TacticsController.aiming_at` is now an `AimTarget` (unit-or-part + cell, always populated) instead
of a bare `Unit`, threaded through `aim_state()`, `aim_reticle_at_screen()`, and camera framing:
- `ShotPlane.center_of_part` (new) mirrors `center_of` but matches by `region.body` identity instead
  of a Unit's `shell.all_parts()`.
- `UnitGeometry.bounding_sphere_for_part` (new) mirrors `bounding_sphere` for a bare Part+cell,
  sharing a new `_sphere_from_placements` tail.
- `CameraRig.ease_to_attack_framing` now takes precomputed `{center, radius}` sphere Dictionaries
  instead of raw Units, so it stays fully decoupled from which kind of thing it's framing — a
  mechanical signature change that touched `test_camera_rig.gd` (the docs/10 "read the real node
  back" reference file) but not its actual math/behavior.

This reaches all the way into RESOLUTION, not just the click: `AttackAction`/`BurstAction.is_legal()`
no longer hard-require a live unit at `target_cell` (`Grid.shootable_part_at`, new, is enough);
`apply()` re-derives whichever is actually there and computes the aim point via `center_of_part` when
there's no unit. `ShotPlane`/`BodyProjector`'s own depth-sorted resolution is completely untouched —
this only widens what a queued action is legally allowed to *declare* as its target; what a shot
actually hits along the way was already resolved independently of the declared target.

**Scope decision, recorded in `docs/PLAN.md`:** ranged weapons only this pass (shoot/burst) — every
motivating example (finish a downed bot, destroy cover, decompress a room) is naturally ranged
anyway. `StabAction`/`SlashAction`/`GrindAction` still require a real target Unit
(`MeleeReach.distance_3d` needs one to measure reach against) and correctly reject a PART target
today, same as any other unreachable action's silent no-op. Extending melee reach to a bare Part is
its own design question, not designed here — follow-up note left in PLAN.md.

22 new tests across the logic and view layers (`test_part_picker.gd`, `Grid.shootable_part_at`,
`UnitGeometry.bounding_sphere_for_part`, `ShotPlane.center_of_part`, `AttackAction`/`BurstAction`
PART-target legality+resolution, `TacticsController` click-flow and confirm-shot tests). Commit
`95a39c0`.

## Pass D — turn-controls corner

**BR27.07 (active-turn highlight on the wrong unit → facing-marker-only).** Both parts done.
Design change: `HitVolumeView.set_active_turn()` no longer recolors the ground marker/facing wedge
(`ACTIVE_TURN_COLOR` retired) — it toggles the facing wedge's own visibility instead, so only the
current unit shows a facing marker at all, per the supervisor's own words ("the marker's presence
indicates whose turn it is, not a color"). Ordering bug: `BattleScene.refresh_unit_views()` gained an
`apply_highlight` parameter; `SquadControlOverlay._on_turn_ended()` now defers the flip (via the
newly-public `apply_active_turn_highlight()`) until *after* the resolution animation actually
finishes, instead of before it. `SingleUnitOverlay._on_turn_ended()` now `await`s its `super` call,
closing a compounding race that let it run ahead of the same animation.

**BR27.08 ("Resolve to Here" has never worked).** Re-verified rather than blind-fixed, per the
prior investigation's own suspicion that the ledger was stale. `resolve_to_marker()` traces clean
end-to-end, and `test_tactics_controller_resolve_to.gd` already has a real queue-then-resolve test
(queues two move legs, resolves to the first marker, asserts the unit's own `.cell` actually only
advanced one leg — not a UI-state check that could pass while the real resolve silently no-ops).
Nothing changed; looks like commit `888a25f` already fixed this and the ledger never caught up.

**BR31.01 (turn controls vs. tooltip clicks).** Reproduced before changing anything, per the
taskblock's own instruction. A real synthetic click pushed through the actual `Viewport`
(`test_battle_scene_input.gd`, the one file that routes input through the real Control tree) proved
End Turn still receives the click even with the tooltip visually positioned directly over it —
`TooltipView`/its label both already carry `MOUSE_FILTER_IGNORE`, so mouse_filter was never the
mechanism. The real bug: nothing ever hides a *stale* tooltip left over from hovering the 3D board
once the cursor crosses onto a turn-control button — `TacticsController`'s own hover tracking lives in
`_unhandled_input`, which never fires while a default-`STOP`-filtered `Button` has the cursor
(Godot's GUI layer consumes the motion event first). `QueuePanel`'s tree and `ApMpPipRow`'s AP/MP
containers already needed and got this exact fix for the same reason; the three
`turn_controls_column` buttons never did. Fixed: each button's own `mouse_entered` now hides the
tooltip. Proven both ways in `test_battle_scene_input.gd`.

**Diagnostic note, worth keeping in mind for future Control-tree tests:** anchored Controls
(`turn_controls_column` included) only resolve their real, laid-out `global_rect` after a live frame
actually runs — reading it the same frame the scene was built returns a garbage
`(viewport_size, 0×0)` rect, off-screen by construction. Cost some real time mid-pass (both new
`test_battle_scene_input.gd` tests initially failed for this reason, not the reason under test) —
`await get_tree().process_frame` (twice) before reading `get_global_rect()` fixed it. Worth watching
for in any future test that computes a screen position from a Control's rect rather than a 3D camera
projection.

All three of BR27.07/BR27.08/BR31.01 are `SUPERVISOR`-sourced. Commit `85a7ce7`.

## Supervisor review round (commit `f21dd0c`)

Live testing surfaced corrections to two of the four passes and confirmed a third:

- **BR31.01 — confirmed fixed, promoted to `RESOLVED`.**
- **BR27.07 tweak** — "facing marker" meant the WHOLE disk/facing-pip assembly (ground marker AND
  wedge together), not the wedge alone; the first pass only toggled the wedge. `set_active_turn()`
  now toggles both `_team_marker.visible` and `_facing_wedge.visible`.
- **BR27.08 — still active, reverted from pending back to Active.** The "already fixed, ledger just
  stale" read from last session was wrong. Re-verified the entire click-to-resolution chain (row
  click → marker set → button enabled → button click → real resolve → unit moves) at three levels of
  fidelity (isolated `QueuePanel`, full `SquadControlOverlay`, full click-through via real synthetic
  `InputEventMouseButton`s) and could not reproduce a failure anywhere. Did not blind-fix a second
  time — flagged back to the supervisor for more specific repro detail (what exactly was clicked,
  queue state, sequence) rather than guess again.
- **Pass B redesigned** — the supervisor reported seeing "something happening" but not a clearly
  faded unit. Root cause: the original design drew a *separate* ghost overlay in `BoardView`
  (`_friendly_fade_overlay`), leaving the friendly's own real `HitVolumeView` fully opaque underneath
  it — an extra translucent decoy sitting next to an otherwise-solid unit, not an actual fade of that
  unit. Redesigned to fade the unit's own real body: `HitVolumeView.set_occlusion_faded()` swaps
  every body mesh instance's `material_override` to translucent gray, never touching the ground
  marker/wedge (`set_active_turn()`'s own concern) or `highlight_part()`'s `mesh.material.next_pass`
  chain underneath. The occlusion decision moved to `BattleScene._process()`/`_occluding_friendlies()`
  — the one place holding both the live camera and every `HitVolumeView` — reusing Pass A's
  `occludes_on_screen`/`pixel_radius_for_tiles` unchanged. Also bumped `OCCLUSION_FADE_ALPHA` from
  0.12 (confirmed live to be imperceptible) to 0.3, though the alpha wasn't the primary bug.
  Verified via a real end-to-end scene (real `BattleScene`, real `SquadControlOverlay`, real
  click-to-aim flow, real camera easing) reading the actual `HitVolumeView`'s material back — not a
  hand-positioned synthetic camera, which is exactly the gap that let the first, broken version pass
  its own tests.

**This environment has no Xvfb/GPU** — Godot's `--headless` mode only supports the `dummy` rendering
driver, so no fragment shader ever actually executes here, and no screenshot can be captured from
this end. Everything CC could verify directly was backed by reading real engine state (materials,
node trees, signals, GDScript-side math) through the actual production code path — never a
re-derivation of the same logic under test. But two bugs this taskblock (BR32.02's Y-convention and
its depth source) lived entirely inside the fragment shader itself, invisible to every one of those
verification methods. They were only found and fixed because the supervisor ran the real game,
described what they saw precisely, sent screenshots twice, and tested a sequence of small,
purpose-built diagnostic shader builds CC produced — live collaborative debugging, not something CC
could have reached alone in this session.

## Post-taskblock supervisor review (live-bout testing, same day)

**BR27.07 tweak** — "facing marker" meant the whole disk+wedge assembly, not the wedge alone; both
now toggle together (`HitVolumeView.set_active_turn()`).

**BR27.08** — reverted from "already fixed" back to Active. The supervisor confirmed it's still
broken despite the entire click-to-resolution chain checking out at every level CC could test
automatically (isolated `QueuePanel`, full `SquadControlOverlay`, full synthetic click-through to
real unit movement). Needs specific repro steps — what was clicked, queue state, sequence — before
investigating further; not blind-fixed a second time.

**BR31.01** — confirmed fixed live, promoted to RESOLVED.

**Pass B (friendly-ghost fade) — redesigned.** The original design drew a separate ghost overlay in
`BoardView`, leaving the friendly's own real `HitVolumeView` fully opaque underneath it — confirmed
live to read as "something faint happening," not an actual fade. Redesigned to fade the unit's own
real body (`HitVolumeView.set_occlusion_faded()`), with the occlusion decision moved to
`BattleScene._process()` — the one place holding both the live camera and every `HitVolumeView`.

**BR32.01 (new) — stray wall-cutout hole with no unit present.** An extracted or debug-removed unit
never clears its stale `.cell` and stays in `combat_state.units` forever, feeding a permanent,
unit-less hole into the cutout shader. Fixed by excluding `.extracted` units and units whose
`HitVolumeView` was explicitly destroyed (`BattleScene.remove_unit_view()`) from the occlusion feed.
**BR32.03 (new, temporary `SUSPECTED` tag, explicitly not investigated per instruction):** the
supervisor noticed this same symptom already present on loading into a fresh bout — if BR32.01's
mechanisms were the cause, it happened on a PRIOR bout, meaning something may be surviving a "New
Battle" transition that, on paper, shouldn't be able to (both of BR32.01's own state — `wall_cutout_
units`, `_excluded_from_occlusion` — are reset fresh on every load). Logged only; deferred to the
supervisor's own review pass.

**BR32.02 (new) — wall cutout never visibly appears near real units.** The deepest investigation of
the taskblock, resolved entirely through live, iterative diagnostic builds (each a small, uncommitted,
shader-only change, removed once it answered its question):
1. A documented-but-wrong theory (`FRAGCOORD` matches GLSL's bottom-left-origin `gl_FragCoord`) led to
   a Y-flip that made things visibly WORSE (cutout appeared but detached, drifting/spiraling as the
   camera orbited) rather than better — a real, live-tested correction, not a guess accepted on faith.
2. A real orbiting-camera GDScript test ruled out the feed logic (position/depth/radius) entirely —
   it was already correct and stable at every angle.
3. Two hardcoded-position diagnostic shaders (fixed hole at viewport center, then at a corner)
   settled the Y-convention empirically: `FRAGCOORD` is actually top-left-origin, Y-down — the SAME
   convention `unproject_position()` already uses. No flip was ever needed; the flip was reverted.
4. With the Y-convention resolved, the ORIGINAL complaint (no cutout ever appears near real units)
   was still unexplained. A sequence of further diagnostics (unconditional discard, depth-compare
   disabled, depth-compare direction flipped) narrowed it to the depth VALUE itself: `length(VERTEX)`
   — despite Godot's own documentation saying `VERTEX` already arrives in view space inside
   `fragment()` — did not behave that way here, in either comparison direction. Replaced with true
   view-space depth reconstructed from the hardware depth buffer (`FRAGCOORD.z` +
   `INV_PROJECTION_MATRIX`, Godot's own standard recipe), confirmed live: culling from the correct
   side of a wall (camera and unit on opposite sides) now works as designed.

**Deferred, not a regression from this fix — observations and a candidate cause, per the
supervisor's own request, not yet acted on:** with the camera and unit on the SAME side of a wall
(nothing should occlude at all), the cutout still fires, and does so aggressively — a live screenshot
showed a large, over-sized cut removing a rounded chunk from BOTH walls of a corner/corridor
junction at once, not a small ~2.5-tile porthole. **Candidate cause:** the shader's own occlusion test
is a coarse, single-scalar heuristic — "is this fragment nearer to the camera than the unit's own
reference depth, AND within the unit's screen-space radius" — with no actual 3D ray/line-of-sight
check against the real camera-to-unit line. A wall segment standing immediately adjacent to a unit
(not truly between it and the camera at all) can easily satisfy BOTH conditions purely by geometric
coincidence: its near surface can be nearer to the camera than the unit's own bounding-sphere center
simply because they're close together, not because it's actually in the way, and its screen-space
projection naturally overlaps the unit's own footprint since they're adjacent. This would explain why
MULTIPLE nearby wall segments (not just one) get cut at once in a tight corner — each independently
satisfies the same coincidental-proximity test. Not designed here since it's explicitly deferred, but
directions worth considering at the supervisor's own review pass: an actual per-fragment ray/line-
segment test against the real camera-to-unit line instead of a bare depth compare, or gating on the
ANGLE between the camera-to-wall and camera-to-unit vectors rather than screen-space pixel distance
alone.

## Supervisor bugs moved to PENDING-CONFIRMATION this taskblock

- **BR27.07** — active-turn highlight design change (now the whole marker assembly, per the
  supervisor's own tweak) + ordering bug, both fixed.
- **BR32.01** — stray wall-cutout hole from an extracted/debug-removed unit's stale cell, fixed.
- **BR32.02** — wall cutout Y-convention (a false lead, reverted) and its real cause (the depth
  source), fixed; same-side over-cutting explicitly deferred, not part of this pending mark.

**Resolved (supervisor-confirmed):** BR31.01.

**Still active, needs more detail:** BR27.08 — mechanism re-verified working at every level
automated testing can reach; needs specific repro steps from the supervisor.

**Logged, not investigated (temporary `SUSPECTED` tag, by instruction):** BR32.03 — possible
occlusion-state carryover across a bout transition.

## Post-taskblock cleanup: retroactive living-docs audit (rule 8, applied historically)

Asked to check the last five taskblocks (28-32) against `CHANGELOG.md`/`BUGS.md`/`SUPERSEDED.md` —
a history check, not new work — to catch anything that hadn't landed and any pointer that no longer
points forward correctly. Read every taskblock spec and report in `taskblock_done/` (28-32) plus the
three living docs in full and cross-checked them line by line. tb28/tb29's features and tb30's own
huge bug-pass digest all checked out clean against `BUGS.md`/`CHANGELOG.md` already. What was actually
wrong or missing, all fixed in a docs-only commit:

- **`CHANGELOG.md`'s own banner** still read "current as of taskblock-26," six blocks stale.
- **Two `CHANGELOG.md` paragraphs described superseded/buggy behavior as current.** "Turn indicator"
  (tb27 D2) still described the retired `ACTIVE_TURN_COLOR` recolor with a footnote pointing at
  BR27.07 as open; "AP-gated action bar" (tb27 D3) still carried a "the gate isn't holding" footnote
  pointing at BR27.05 — both bugs were long since fixed (this taskblock's own Pass D, and tb30,
  respectively) by the time this session started. Rewrote both to describe what actually ships now,
  pointing forward instead of reading as still-broken.
- **BR31.01's own fix had no `CHANGELOG.md` entry at all** despite being fixed and closed in `BUGS.md`
  — added.
- **Two real, supervisor-reported bugs from taskblock 31's own live testing were never given a `BR`
  id or a `BUGS.md` entry**, even though they were fixed and written up in `CHANGELOG.md`/that
  taskblock's own report at the time: wall/void generation cascading through solid rock, and wall
  fading never visibly firing (then firing but staying invisible). Backfilled as **BR31.02**/
  **BR31.03**, both `RESOLVED-PENDING-CONFIRMATION` — this session didn't verify either live, so the
  provenance gate stayed conservative rather than write plain `RESOLVED` on someone else's behalf.
- **Four design reversals were landing invisibly** — `CHANGELOG.md` described the new state each time
  but `SUPERSEDED.md` never recorded what it replaced: turn-indicator recolor → marker-visibility
  (BR27.07/tb32 D), per-wall alpha-blend → cutout shader (tb31 C → tb32 A), ghost-overlay friendly
  fade → real-body fade (tb32 B's own same-block redesign), and ranged-attack legality extending to
  non-unit Parts (tb32 C). Backfilled all four rows.

Not fixed, flagged only: taskblocks 28 and 29 never got a `Report-Taskblock*.md` of their own (only
30/31/32 do) — their `CHANGELOG.md`/`BUGS.md` content is accurate regardless, but there's no report
artifact behind them and this session had no basis to reconstruct one with any confidence. No code
changed this pass — docs only. Commit `7ff9127`.

## Post-taskblock: merged a parallel review-chat session's own doc edits

A separate "review chat" session had forked `docs/PLAN.md`/`docs/SUPERSEDED.md` (as `docs/PLAN2.md`/
`docs/SUPERSEDED2.md`) and directly edited `docs/09-checkpoints-and-logging.md` in place, all
documenting that **checkpoint discipline is retired** — the `./checkpoint.sh N` artifact-gate ritual
sat unused for ~30 taskblocks (CC was told early to prefer clean reports over generated artifacts) and
its review job is now done live (supervisor play/bug-hunt + tester-mode) instead. Its fork point
predated both this session's own living-docs audit (above) and had its own genuinely new edits — a
straight overwrite either way would have silently reverted content. Merged by hand: kept every row this
session's own audit had already added to `SUPERSEDED.md`, kept `PLAN.md`'s already-current
tb32-Pass-C-landed wording (the "2" fork still had the pre-landing version), and pulled in only the
fork's own genuinely new edits — the "Standing rules" heading rename, the rule-2 rewrite, and the new
checkpoint-discipline reversal row. Deleted the now-merged `*2.md` scratch files. Commit `96e005a`.

## BR27.08: removed the Tree/marker mechanism, rebuilt on buttons

BR27.08 ("Resolve to Here" never worked) had been investigated repeatedly across tb30/tb32 without a
conclusive root cause — the resolve logic itself always checked out, and every synthetic reproduction
of the reported click worked in this headless environment, including a real `InputEventMouseButton`
pushed through a real `Viewport` against the real, correctly-sized production `Tree`. The supervisor
then reproduced it live, precisely: both overlays, any queue length/mix, any turn state, and — the
load-bearing detail — **the row itself never visibly reacted at all**, ruling out a cosmetic/redraw-
only theory. Asked to put forward a plan to remove the whole mechanism and rebuild it on primitives
already proven reliable in this codebase; plan approved, then implemented:

- `QueuePanel` rewritten: no more `Tree`, no `_marker_index`, no separate global "Resolve to Here"
  button. Each queued action is its own row (`HBoxContainer`: What/AP/MP `Label`s + a dedicated
  "Resolve" `Button`), following `GenerateBoutOverlay._rebuild_team()`/`_entry_row()`'s own established
  clear-and-rebuild-from-an-array convention. A row's own button binds directly to
  `tactics.resolve_to_marker(index)` — one click, no marker state to get stuck.
- `SquadControlOverlay`: `turn_controls_column` drops the old Resolve-to-Here button (End Turn/Reset
  Turn only now, exposed as named `end_turn_button`/`reset_turn_button` fields instead of magic
  `get_child()` indices); the queue `Tree` is replaced by a `ScrollContainer` (horizontal scroll
  disabled — found live: an unbounded `SIZE_EXPAND_FILL` label inside it landed the whole row hundreds
  of pixels past the right edge of a 1920-wide viewport) wrapping the new rows container.
- Verified with a real synthetic click against the full production `BattleScene` — the same
  rigorous technique already established for BR31.01 — plus a bare-`QueuePanel`-fixture suite. Along
  the way, caught and documented a genuine headless-testing-only gotcha (the default GUT viewport is
  64×64; a real click outside that is legitimately outside the viewport's own bounds, not a game bug —
  same class of thing the original `Tree` sizing gotcha already was).
- Marked `RESOLVED-PENDING-CONFIRMATION`, not `RESOLVED` — a replacement, not a confirmed fix of the
  original mechanism, since its root cause was never actually identified. Still needs the supervisor's
  own live click. Commit `a8bc054`.

## BR27.08: two same-day supervisor refinements on the rebuild

1. **"Resolving to an earlier point should keep the later queued items in the queue."**
   `resolve_to_marker()` called `selection.reset_turn()` after a partial resolve, discarding the ENTIRE
   remaining queue, not just the resolved prefix — inherited unchanged from the original taskblock06/07
   design. New `SelectionController.keep_queue_suffix(from_index)` drops only the resolved prefix; the
   surviving suffix replays unmodified against the just-updated real state, safe because every
   `CombatAction` already re-validates itself against whatever `state` it's actually handed (docs/09),
   never a captured reference. A real design reversal, logged in `SUPERSEDED.md`, not just a bug fix.
2. **"The coord info can be an on hover event for the MoveAction term... long paths make the readout
   stretch across the display."** New `CombatAction.short_describe()` (defaults to `describe()`,
   unchanged for every other action type) lets `MoveAction` drop only its own unbounded `path=...` term;
   `SelectionController.queue_entries()` surfaces the full `describe()` as an extra tooltip "Detail" row
   only when it actually differs. First pass cut the label all the way to bare `"Move"` — supervisor
   follow-up ("I'm okay with it saying MoveAction, it's just a stream of coords that look messy")
   corrected it back to `"MoveAction(unit=%d)"`, matching every sibling action's own class-name style;
   only the coordinate stream itself needed to go.

Updated the existing `resolve_to_marker` tests that had the old discard-everything behavior baked in.
Commit `cc40183`.

## BR27.08: hover leak-through, found same session

Supervisor report: "Hovering anywhere in the combat readout gives me the details of things behind it."
Same class of bug as the already-fixed action-bar click case
(`test_a_click_on_an_action_bar_box_never_reaches_the_board_underneath`) — a queue row's own
`MOUSE_FILTER_PASS` correctly fired its own `mouse_entered`/`mouse_exited` (its own tooltip was never
the problem), but PASS never marks a motion event handled, so the same event ALSO reached
`TacticsController._unhandled_input`'s `update_hover()` — a bare 3D ray-cast against the board with no
awareness that a translucent UI panel sits over that screen position. Confirmed directly (a real
`mouse_moved` signal check: fires with `PASS`, silent with `STOP`) before touching anything, matching
this project's own "read the real thing back" standing rule. Fixed the same way the action bar was:
`QueuePanel`'s own row is now `MOUSE_FILTER_STOP`; still gets its own hover (confirmed), no longer
leaks to the board. Widened `test_battle_scene_input.gd`'s own structural "no accidental STOP" check to
also recognize a real `mouse_entered` connection as genuine interactivity, the same way it already
recognized `gui_input` — a Control deliberately wired for hover is exactly as intentional as one wired
for clicks. **Not fixed, flagged only:** `ApMpPipRow`'s own AP/MP pip containers have the identical
`PASS`-only shape and likely the same latent leak; not yet reported there, not touched. Commit
`6ad4409`.

## BR32.04 (new) — flagged only, by instruction

Supervisor, same live-testing pass: "on clicking resolve, cull position moves to the right cell
immediately, while animation plays separately, splitting them. Likely a process change so just flag it
for now." Not investigated — logged with a candidate mechanism for whoever picks it up next: the
wall-cutout shader's own per-frame feed (`BoardView.update_wall_cutout()`, reading live off
`combat_state.units`) likely reads the unit's real, already-resolved `.cell` the instant
`resolve_to_marker()` updates it, while the visual slide (`ResolutionPlayer`) is still animating the
model toward that cell over several more frames — a real position, just the wrong one to read from
mid-animation. Commit `77e6062`.

## Session close

Full `./run_tests.sh` green throughout (1944/1945 at last check) — the one failure is the pre-existing,
already-documented `test_full_mission.gd` limitation (PLAN.md: kept RED until a `BoutSetup`-based
replacement lands), unrelated to any of this session's work. All commits pushed to `origin/master`.

**Supervisor bugs moved to PENDING-CONFIRMATION this session:** BR27.08 (full mechanism replacement).

**Still active, needs a live look:** BR32.04 (resolve-click vs. move-animation desync in the wall
cutout), explicitly not investigated by instruction. `ApMpPipRow`'s own likely hover-leak (same class
as BR27.08's fix) flagged but not filed as its own BR — worth a look if it's ever actually observed
live.
