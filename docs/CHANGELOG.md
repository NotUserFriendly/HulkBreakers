# CHANGELOG.md — What's Been Built

**The current-state snapshot**, by system, with the taskblock that landed each. Grows as work ships.
For what changed shape along the way see `SUPERSEDED.md`; for what's next see `PLAN.md`.

*Current as of taskblock-26 landed.*

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
the queued out-leg (tb27 B).

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

**Mission & meta** (tb07, docs/07) — no win state (EXTRACTED/TERMINATED/STRANDED); enemy count never
an ending; gather→extract/terminate; asymmetric, whole-squad, visible extraction — the player squad
must get everyone to a team-coded tile, can't self-extract early (tb22 A); bout-setup places each
side's extraction tiles on the *opposing* side, forcing the teams through each other (tb23 E1);
pseudo-persistent hulks; loot overlap; deep strike.

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
extraction tile) no prior fix or test had ever checked. **Turn indicator** (tb27 D2) — the active
unit's own facing wedge and team marker recolor to a distinct `ACTIVE_TURN_COLOR`, driven off
`combat_state.current_unit()` from both `load_battle()` and `refresh_unit_views()`, shared by
either overlay. *(Regressed — see BUGS.md BR27.07: highlight can land on the wrong unit, and the
design is being changed to facing-marker-only. This entry describes what shipped, not the current
intended behavior.)* **AP-gated action bar** (tb27 D3) — a slot the unit can't afford dims and refuses
to arm, reusing `ActionCatalog.provider_for`'s own `ap_cost`. *(Regressed — see BUGS.md BR27.05:
slots are still selectable without enough AP; the gate isn't holding.)* **Camera reset after aiming** (tb27
D4) — `CameraRig` snapshots the pre-aim orbit state and eases back to it once aiming ends, via a
shared `_ease_to()` helper. **Wall tiles non-inspectable** (tb27 D5) — a wall click is a real
no-op, same posture as a miss; `InspectPanel`'s own null-root branch also resets stale isolate-view
state so it can never leak a live-board render slice into a "nothing to show" case regardless of
caller. **Spectator/player parity** (tb27 D1a/D1c) — the spectator log no longer word-wraps
(matching the player log); spectator view gained inspect-on-hover (`UnitPicker.hit()` driven off
mouse motion, mirroring `SquadControlOverlay`'s own highlight wiring but with no "selected unit"
gate, since spectator has no selection concept) — previously it had no hover feedback at all.

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
shipped content (`kitted_chaingun.tres`).

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

## Economy

**Inventory & economy** (docs/05) — mass/bulk/RAM; discount once at the worn layer (body-attached
floor 0.8); rigidity (soft collapse, rigid don't); body-carry as inert cargo; 7 resources;
`salvage_yield` on parts. Field objects (scrap_pile, goo_barrel, crate, pillar, forklift w/ POWER
socket, barrel_pallet) — on-board resource/cover, block movement, project into the shot plane.

## Matrices

**Matrices & surrogates** (docs/04) — logic vs intelligence; base/link split; docks into `MATRIX`
socket; surrogates dock like parts (tier DAG); matrices never lost; `Matrix.playstyle` carries AI
personality. *Frozen — no more depth.*
