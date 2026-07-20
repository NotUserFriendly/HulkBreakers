# CHANGELOG.md — What's Been Built

**The current-state snapshot**, by system, with the taskblock that landed each. Grows as work ships.
For what changed shape along the way see `SUPERSEDED.md`; for what's next see `PLAN.md`.

*Current as of taskblock-21 landed; tb22 written, in progress.*

---

## Combat core

**Part graph** (tb01–02, docs/01/01a) — inverted attachment (parts declare `attaches_to`, sockets
declare `socket_type`); socket ids; socket transforms (sockets = joints, parts = bones); limb
decomposition; capability tags (`TRIGGER`/`SUPPORT`/`GRIP`/`POWER`) + weapon `requires`; keyed
cladding vs generic plates. Bot builder debug scene over the real `BodyAssembler`.

**Geometry & targeting** (tb02/06/07, docs/02) — continuous projection, no exposure table;
depth-sorted shot plane with gap fall-through (the sniper thread); dartboard (N rings, seeded);
`resolve_ray(muzzle, dir)` the resolution seam; `READING`/`RESOLVES` never conflated.

**Failure model & joints** (tb09) — five failure modes: `MANGLE` (¼ residual DT, stays attached),
`DISABLE` (inert, attached), `DETONATE` (replaces cook-off), `FRAGMENT`, `MELTDOWN`. Child-owned
joint HP, no modes; depleting one drops the intact subtree. Joints aimable (the precise-elbow shot).
Spill-through: penetration damages the plate fully, spills `damage − effective_dt` onward.

**Armor, damage & weapons** (tb09/10/13) — DT from a `dt_curve` table; penetrate/stop-dead/deflect by
real geometry; ricochet retention `lerp(0.90,0.25,bend)`; crits bypass-or-bonus; bonus-pen as a
DT-discount (penetration only, negative for buckshot). Ammo owns the payload (`AmmoDef`); gun is a
modifier (`WeaponDef`). Cartridge chambering (family + length). Two scatters: dartboard (aim) vs
spread pattern (mechanical). Burst = N independent pulls, recoil accumulates. Recoil computed.

**Layered bodies & power** (tb20) — bodies as cladding/skeleton/organs; knowledge-gated occlusion of
internals (source stubbed to "known"); penetration traversal (DT attenuation, overpen = 0° deflect,
`hollow` flag, lodged-inside wounds); **wounds** as non-terminal repairable per-part state;
penetration-driven deflection resistance (closed the angle-lock stalemate); power-drives-AP with
coring; the reaction window (perk-gated, default none).

**Range** (tb19) — effective / max / min with a linear sub-1 accuracy band in the effective→max
range; discrete min-range failure (explosive duds); AI movement is range-aware.

## Combat structure & AI

**Turn structure** (tb06, docs/09) — TACTICS/RESOLUTION re-entrant loop; `resolve_until →
COMPLETED|STOPPED(reason,refund)`, interrupt when the next action is illegal; overwatch (torso gate,
now visible as a 30° slice, tb19); one-stream combat log.

**Resolution speed** (tb18) — `Matrix.personal_speed` (flat bonus to everything); unified
resolution-speed formula (lower resolves first); re-validating ordered resolver; initiative;
equal-speed simultaneity; **Step Out** (auto-assembled orthogonal move/fire/return through the
resolver, dies-exposed on interrupt).

**AI** (tb14/16/17-1) — `UnitAI.plan_turn`, deterministic, human & AI emit the same queue. Playstyles:
AGGRESSIVE, COVER_SEEKER, SKIRMISHER (~5), MARKSMAN (~7+). Line-of-fire safety (won't shoot through
allies); reachability-aware targeting. Suppression + stubbed opportunity attacks (await melee).

**Mission & meta** (tb07, docs/07) — no win state (EXTRACTED/TERMINATED/STRANDED); enemy count never
an ending; gather→extract/terminate; pseudo-persistent hulks; loot overlap; deep strike.

## Tooling, data & view

**Data layer** (tb10/11) — all definitions in `.tres`; `DataLibrary` (res:// builtin + user://
override, user wins); `DataValidator` (named errors, shared editor-save + game-load). Resource
Editor: standalone-scene tuning tool, survives reboots, writes user://, tree-table with
sort/filter/dropdowns/undo/rotating preview.

**View** (tb15, docs/10/10a) — 3D HL2-era; render is hitbox; two palettes; attack camera solves
framing (orbits target); poses = socket overrides; `HitVolumeView` permanent; per-part `mesh_scene`
(mixed assemblies). One `BattleScene` + swappable control overlays. Playback animation
(slide/facing/shot-fade-to-tracer), animation-gated in the view only, tunable timings.

**Bouts** (tb14) — watchable AI-vs-AI with pacing controls, a seed, a bout-setup menu (expanding-list
teams). The verification rig.

**Inspect panel** (tb21) — the current inspect surface: rotating bot viewer, matrix area, sorted
inventory tree (weapons→containers→parts), info panel + item viewer, status/wound column, dead-zone
hold, right-click debug menu. Click-to-pause-inspect in spectator.

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

---

## In progress
**tb22** — asymmetric whole-squad extraction; power→AP diminishing curve; shutdown; every-shot/hop
tracer visibility; repair subsystem (batteries + Arc Welder + repair-with-scrap); hierarchical
folding combat log; inspect-panel fixes; shouldered guns; new panel in player view.
