# CHANGELOG.md — What's Been Built

**The current-state snapshot**, by system, with the taskblock that landed each. Grows as work ships.
For what changed shape along the way see `SUPERSEDED.md`; for what's next see `PLAN.md`.

*Current as of taskblock-32 landed.*

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

**Layered bodies & power** (tb20/22) — bodies as cladding/skeleton/organs; knowledge-gated occlusion
of internals (source stubbed to "known"); penetration traversal (DT attenuation, overpen = 0°
deflect, `hollow` flag, lodged-inside wounds); **wounds** as non-terminal repairable per-part state;
penetration-driven deflection resistance (closed the angle-lock stalemate); power drives AP through
an authored diminishing curve (tb20 F, revised tb22 B) with coring; the reaction window
(perk-gated, default none). A unit that can neither move nor act may voluntarily **shut down** —
inert, still occupying its cell/occluding the shot plane, excluded from turn order (tb22 C).

**Range** (tb19) — effective / max / min with a linear sub-1 accuracy band in the effective→max
range; discrete min-range failure (explosive duds); AI movement is range-aware.

**Repair** (tb22 E) — `RepairResolver`/`RepairAction`, five authored battery parts + the Arc Welder,
repair-with-scrap (1:1, up to 3 HP per use, 4 AP; scrap's own resource id is the damaged part's
`material` field). Reachable via a right-click "Repair with Scrap" item and an action-bar Repair
button.

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
also recognizes `&"stab"` (purely additive), so playstyle weapon choice reads the same
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
system, and overwatch misses are logged for the first time.

**Resolution speed** (tb18) — `Matrix.personal_speed` (flat bonus to everything); unified
resolution-speed formula (lower resolves first); re-validating ordered resolver; initiative;
equal-speed simultaneity; **Step Out** (auto-assembled orthogonal move/fire/return through the
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
shoot through allies); reachability-aware targeting. Suppression + real melee opportunity attacks
(tb25 E, was stubbed). **Engagement positioning** (tb27 C1) — when no reachable cell has real line
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

**View** (tb15/22, docs/10/10a) — 3D HL2-era; render is hitbox; two palettes; attack camera solves
framing (orbits target); poses = socket overrides; `HitVolumeView` permanent; per-part `mesh_scene`
(mixed assemblies). One `BattleScene` + swappable control overlays. Playback animation
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

**Bouts** (tb14) — watchable AI-vs-AI with pacing controls, a seed, a bout-setup menu (expanding-list
teams). The verification rig. **Seeded variant generation** (tb28 A) — `VariantFamily`
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
the-injections. **Injection reaches a player-controlled bout too (tb30)** — `bout_injector` moved up to
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

## Economy

**Inventory & economy** (docs/05) — mass/bulk/RAM; discount once at the worn layer (body-attached
floor 0.8); rigidity (soft collapse, rigid don't); body-carry as inert cargo; 7 resources;
`salvage_yield` on parts. Field objects (scrap_pile, goo_barrel, crate, pillar, forklift w/ POWER
socket, barrel_pallet) — on-board resource/cover, block movement, project into the shot plane.

## Matrices

**Matrices & surrogates** (docs/04) — logic vs intelligence; base/link split; docks into `MATRIX`
socket; surrogates dock like parts (tier DAG); matrices never lost; `Matrix.playstyle` carries AI
personality. *Frozen — no more depth.*
