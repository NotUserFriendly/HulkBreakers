# CHANGELOG.md — What's Been Built

**The current-state snapshot**, by system, with the taskblock that landed each. Grows as work ships.
For what changed shape along the way see `SUPERSEDED.md`; for what's next see `PLAN.md`.

*Current as of taskblock-24 landed.*

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
(tb23 C); `READING`/`RESOLVES` never conflated.

**Failure model & joints** (tb09) — five failure modes: `MANGLE` (¼ residual DT, stays attached),
`DISABLE` (inert, attached), `DETONATE` (replaces cook-off), `FRAGMENT`, `MELTDOWN`. Child-owned
joint HP, no modes; depleting one drops the intact subtree. Joints aimable (the precise-elbow shot).
Spill-through: penetration damages the plate fully, spills `damage − effective_dt` onward.

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

## Combat structure & AI

**Turn structure** (tb06, docs/09) — TACTICS/RESOLUTION re-entrant loop; `resolve_until →
COMPLETED|STOPPED(reason,refund)`, interrupt when the next action is illegal; overwatch (torso gate,
visible as a 30° slice, tb19) — the AI can now genuinely weigh and hold it, not just react to it
(tb24 C); one-stream combat log, folded into hierarchical action-level summaries at render time
(tb22 F).

**Resolution speed** (tb18) — `Matrix.personal_speed` (flat bonus to everything); unified
resolution-speed formula (lower resolves first); re-validating ordered resolver; initiative;
equal-speed simultaneity; **Step Out** (auto-assembled orthogonal move/fire/return through the
resolver, dies-exposed on interrupt).

**AI** (tb14/16/17-1/24) — `UnitAI.plan_turn`, deterministic, human & AI emit the same queue,
firing derived from the same `ActionCatalog.build_firing_action` seam a weapon's own
`provides_actions` governs for both (tb24 A/B — `is_legal` enforces it as an engine rule, not a UI
convention); the AI can weigh other provided, non-firing actions the same way, overwatch the first
consumer (tb24 C). Playstyles: AGGRESSIVE (never holds overwatch), COVER_SEEKER (only from cover),
SKIRMISHER (~5), MARKSMAN (~7+, prefers it). Line-of-fire safety (won't shoot through allies);
reachability-aware targeting. Suppression + stubbed opportunity attacks (await melee).

**Mission & meta** (tb07, docs/07) — no win state (EXTRACTED/TERMINATED/STRANDED); enemy count never
an ending; gather→extract/terminate; asymmetric, whole-squad, visible extraction — the player squad
must get everyone to a team-coded tile, can't self-extract early (tb22 A); bout-setup places each
side's extraction tiles on the *opposing* side, forcing the teams through each other (tb23 E1);
pseudo-persistent hulks; loot overlap; deep strike.

## Tooling, data & view

**Data layer** (tb10/11) — all definitions in `.tres`; `DataLibrary` (res:// builtin + user://
override, user wins); `DataValidator` (named errors, shared editor-save + game-load). Resource
Editor: standalone-scene tuning tool, survives reboots, writes user://, tree-table with
sort/filter/dropdowns/undo/rotating preview.

**View** (tb15/22, docs/10/10a) — 3D HL2-era; render is hitbox; two palettes; attack camera solves
framing (orbits target); poses = socket overrides; `HitVolumeView` permanent; per-part `mesh_scene`
(mixed assemblies). One `BattleScene` + swappable control overlays. Playback animation
(slide/facing/shot-fade-to-tracer), animation-gated in the view only, tunable timings; every shot
and ricochet hop draws its own tracer at its real, fully 3D logged position, not one guessed
segment pinned to a constant height (tb22 D, real height tb23 D).

**Bouts** (tb14) — watchable AI-vs-AI with pacing controls, a seed, a bout-setup menu (expanding-list
teams). The verification rig.

**Inspect panel** (tb21/22/23) — the current inspect surface: rotating bot viewer, matrix area,
sorted inventory tree (weapons→containers→parts), info panel + item viewer, status/wound column,
dead-zone hold, right-click debug menu (debug-only items `[*]`-prefixed; inflict-status/create-part
submenus, tb22 G). The one inventory surface in player view too — `InventoryPanel` retired (tb22 I).
Click-to-pause-inspect in spectator. The isolate camera (single-unit preview) shows the model
standing on real ground, correctly lit, not floating in a void (tb23 E2).

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
