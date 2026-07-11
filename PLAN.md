# PLAN.md — Build Order

Work phases in order. Each phase ends **green** (`./run_tests.sh` exits 0) and
**committed** before the next begins. "Acceptance" = the GUT tests you must write
and pass for that phase.

---

## Phase 0 — Test harness & GUT
**Goal:** a working headless test loop.
**Build:**
- Clone GUT 9.x and copy its `addons/gut` into `res://addons/gut`:
  `git clone --depth 1 https://github.com/bitwes/Gut /tmp/gut && cp -r /tmp/gut/addons/gut addons/gut`
- Create `res://test/unit/test_smoke.gd` extending `GutTest` with one passing assert.
**Acceptance:** `./run_tests.sh` exits 0 and reports ≥1 passing test.

---

## Phase 1 — Data models (Resources)
**Goal:** the modular part/chassis/matrix data layer.
**Build (in `res://src/data/`):**
- `enums.gd` — `SlotType` (HEAD, TORSO, CORE, L_ARM, R_ARM, LEGS, ...) and
  `PartType` (WEAPON, ARMOR, SENSOR, MOBILITY, STORAGE, ...).
- `Part` (`Resource`): `id, display_name, part_type, slot_type, hp, max_hp,`
  `mass: float, volume: float, exposure_weight: float, stat_mods: Dictionary,`
  `is_container: bool, max_volume: float, mass_multiplier: float (default 1.0),`
  `contents: Array[Part]`.
  (`exposure_weight` drives hit location — see Appendix C. `max_volume` /
  `mass_multiplier` drive encumbrance — see Appendix D.)
- `Chassis` (`Resource`): `slots: Dictionary` (SlotType→Part), `max_mass: float`;
  methods `install(part), remove(slot_type), aggregate_stats() -> Dictionary`,
  `carried_mass() -> float`, `living_parts() -> Array[Part]`.
- `Matrix` (`Resource`): `id, display_name, level, xp, perks: Array[StringName]`.
  Persistent; carries no chassis reference in saved data.
**Acceptance:**
- Installing parts fills slots; `aggregate_stats()` sums `stat_mods` across installed parts.
- Removing a part removes its stat contribution.
- `ResourceSaver`/`ResourceLoader` round-trips a chassis-with-parts (including nested
  container `contents`, `volume`, `mass`, `max_volume`, `mass_multiplier`) and a matrix intact.

---

## Phase 2 — Grid & coordinates
**Goal:** the abstract tactical grid.
**Build (`res://src/logic/`):**
- `Grid` (`RefCounted`): `width, height`, per-cell data (`terrain`, `opacity`,
  `cover_value`, `occupant_id`). `Vector2i` coords.
- Helpers: `in_bounds()`, `neighbors()`, `distance_chebyshev()`, `distance_manhattan()`,
  `line(a, b)` (supercover/Bresenham cell list).
**Acceptance:** distance, neighbor, and line tests on fixed small grids.

---

## Phase 3 — Pathfinding & movement
**Goal:** movement within a Movement-Point (MP) budget.
**Build:** `Pathfinder` over walkable cells with per-cell move cost (in MP); `astar(a, b)`;
`reachable(origin, mp) -> Array[Vector2i]`. MP is the movement currency; AP converts
into MP in combat (see Phase 7 / Appendix E). Pathfinding itself only knows MP.
**Acceptance:** known-map path length (summed per-tile MP cost) is correct; `reachable`
excludes blocked cells and respects the MP budget exactly.

---

## Phase 4 — Procedural map generation
**Goal:** seeded, connected battle maps with cover.
**Build:** `MapGen`: `generate(seed, width, height) -> Grid`. Rooms + corridors
(BSP or drunkard's walk), scatter half/full cover, place two opposing spawn zones.
Guarantee spawn zones are path-connected.
**Acceptance:**
- For 50 seeds, both spawn zones are reachable from each other.
- Same seed → byte-identical grid (determinism).
- Cover density falls within a target band.

---

## Phase 5 — Line of sight & visibility
**Goal:** who can see whom.
**Build:** `LoS.has_los(grid, a, b)` via `grid.line` + cell opacity;
`visible_cells(grid, origin, range)`. Fixed, consistent corner-blocking rule.
**Acceptance:** LoS is symmetric on open ground; walls block; known-geometry fixtures pass.

---

## Phase 6 — Cover
**Goal:** none / half / full cover, destructible and terrain.
**Build:** `Cover.between(grid, from, to) -> CoverInfo` where `CoverInfo` has
`level: {NONE, HALF, FULL}`, `profile: Array[SlotType]` (which slots this cover
protects), and `object` (the covering blocker, or null). Derived from blockers
adjacent to the target along the incoming LoS. Distinguish **destructible cover**
(an object/Part with `hp` on the cell) from **terrain** (permanent).
Default profiles (per-cover-object, tunable): HALF → `[LEGS]`; FULL → all slots.
Destroying a destructible cover object mutates the grid and downgrades its level.
**Acceptance:** cover-level + profile fixtures pass; destructible cover at hp 0
downgrades the cover level and empties its profile; terrain never downgrades.

---

## Phase 7 — Combat state machine
**Goal:** turns, AP, and validated actions.
**Build:**
- `Unit` (runtime): matrix ref, chassis ref, `cell`, `ap`, `mp` (movement pool),
  `mp_per_ap` (derived from agility/speed via `aggregate_stats()`), `alive`.
- `CombatState`: squads, turn order, per-turn AP reset, action log.
- Action objects: `MoveAction`, `AttackAction`, `SwapPartAction`, `PickUpAction`,
  `ImplantAction`, `EndTurnAction`, each with `is_legal(state)` and `apply(state)`.
  - `MoveAction` follows the AP→MP economy in **Appendix E**: movement spends MP per
    tile; when MP is short the unit burns 1 AP for `+mp_per_ap` MP (repeat while AP
    remains); leftover MP is discarded at end of turn.
  - `PickUpAction` collects a field item (dropped part, salvage, or an ejected
    `MatrixCore`) from an adjacent cell into a container the unit is carrying.
  - `ImplantAction` installs a held `MatrixCore` into an available empty chassis,
    spawning a new active `Unit` mid-combat (chassis source — reserve vs field — is a
    Phase 10 detail).
**Acceptance:** a scripted turn sequence yields the expected action log; illegal
actions are rejected; turn order advances correctly. Moving a path costs the right MP,
burns AP in `mp_per_ap` chunks when the pool is short, fails when AP runs out mid-path,
and discards leftover MP at end of turn.

---

## Phase 8 — Targeting & body-part damage
**Goal:** shots that land on specific parts.
**Build:** `Targeting.resolve_hit(attacker, target, grid, rng) -> HitResult` per the
algorithm in **Appendix C** — exposure-weighted roll picks a living part FIRST, then
cover interception reroutes the hit to the covering object (destructible) or absorbs it
(terrain). `HitResult` carries one of: `part`, `cover_object`, or `blocked`.
`DamageResolver.apply(hit, amount)`:
- part → damage the part; on `hp <= 0` destroy it: remove its `stat_mods`, drop
  container `contents` onto adjacent cells / into salvage.
- cover_object → damage the cover; on `hp <= 0` destroy it (Phase 6 downgrade).
- blocked → no effect (terrain soaked the shot).
Destroying the CORE disables the chassis and **ejects the matrix as a `MatrixCore`
field item**: place it on the free cell adjacent to the disabled chassis that is
nearest the closest living ally (ties broken by lowest `Vector2i` index for
determinism). An ally can retrieve it via `PickUpAction`. The matrix itself persists
regardless (Phase 10) — recovery is a tactical layer, not a survival condition.
**Acceptance:**
- Seeded rolls → deterministic part selection; distribution over many rolls tracks
  `exposure_weight` ratios.
- A part in the cover's `profile` routes the hit to the cover object (destructible) or
  to `blocked` (terrain); a part NOT in the profile is hit directly even under cover.
- Chipping a destructible cover to hp 0 removes its protection, so previously-covered
  parts become hittable on subsequent rolls.
- Destroying a weapon part removes its attack. Destroying the core disables the chassis,
  spawns a `MatrixCore` item on the deterministic cell toward the nearest ally, and
  leaves the matrix flagged alive; an adjacent ally's `PickUpAction` recovers it.

---

## Phase 9 — Inventory & mid-combat part swapping
**Goal:** the nesting inventory and hot-swapping.
**Build:** container-tree ops on `Part.contents`, per **Appendix D**:
- `attach(part, into)` — rejects if it would exceed the container's `max_volume`
  (by direct children's external `volume`) or push the chassis over `max_mass`
  (by nested effective mass). Enforce no cycles.
- `detach(part)`, `walk()`, `flatten()`.
- `Chassis.carried_mass()` — recursive, applies each container's `mass_multiplier`
  to everything strictly inside it (multipliers compose through nesting).
Wire `SwapPartAction`: detach a slot part ↔ attach one from a container, costs AP.
**Acceptance:**
- Nesting invariants hold: no cycles; a container's direct contents' volume ≤ `max_volume`;
  a nested container occupies its parent by its own external `volume`, not its contents.
- `carried_mass()` matches Appendix D: 50kg in a directly-worn ×0.5 backpack → 25kg;
  a ×0.8 pouch nested inside that backpack does NOT apply its 0.8 — its contents are
  flat-summed and discounted only by the backpack's 0.5 (10kg → 5kg). The backpack's
  own mass counts full. Worn directly, the pouch's 0.8 applies.
- Over-volume or over-mass `attach` is rejected; a swap changes `aggregate_stats()`
  mid-combat and deducts AP.

---

## Phase 10 — Roguelike run / meta layer
**Goal:** persistence rules across fights.
**Build:** `RunState`: `roster: Array[Matrix]` (persistent), stash of parts/chassis,
salvage/credits, seed. `resolve_defeat()` — strip all parts from surviving matrices'
chassis, keep the matrices (+XP), lose the parts. `resolve_victory()` — matrices gain
XP, enemy parts salvaged into the stash. `apply_perk(matrix, perk)`.

Matrix recovery at battle end — set a `recovery_state` per matrix that was ejected as a
`MatrixCore` during the fight:
- **RECOVERED** — the core was picked up, re-implanted (Phase 7 `ImplantAction`), or
  still piloting at end. Extracts clean, no penalty.
- **LEFT_BEHIND** — the core was still on the field at battle end. The matrix still
  returns to the roster (roguelike rule is absolute), but gets flagged
  `pending_return_penalty = true`. The penalty mechanic itself is TBD — set the flag
  only; do not invent numbers or effects.
Matrices that never ejected are RECOVERED by default.
**Acceptance:** simulated defeat → matrices persist with XP, parts gone; simulated
victory → parts salvaged; an ejected-and-recovered matrix ends RECOVERED with no flag;
an ejected-and-abandoned matrix ends LEFT_BEHIND with `pending_return_penalty` set yet
still present in the roster; `RunState` save/load round-trips (including `recovery_state`).

---

## Phase 11 — Headless sample combat (integration)
**Goal:** prove the whole logic stack works end to end, no rendering.
**Build:** `res://test/integration/test_sample_battle.gd`: `seed → MapGen →` spawn two
squads of assembled chassis+matrices → run a simple deterministic AI (approach, take
cover, attack best target, swap in a spare weapon when one is destroyed) until one
squad is down. Log each turn to stdout.
**Acceptance:** runs under `./run_tests.sh`, terminates within a turn cap, produces a
winner, and exercises LoS + cover + body-part damage + swap + defeat with zero errors.

---

## Phase 12 — Thin view layer (the human finally looks)
**Goal:** a playable sample battle.
**Build (`res://src/view/`):** `TileMapLayer` render of a `Grid`, unit markers,
click-to-select, click-to-move with reachable-cell highlight, click-to-attack showing
hit location + cover, and a minimal panel: selected unit's parts/HP/AP + a swap control.
A "New Battle" button calls `MapGen` and spawns squads. Programmer-primitive visuals only.
**Acceptance:** launches via `godot --path .`; a human can play a full sample battle
end to end.

---

## Appendix A — determinism rules
- Never call `randi()`/`randf()` directly in logic. Pass an `RandomNumberGenerator`
  seeded from `RunState.seed` (or a per-battle seed) into any code that rolls.
- Map generation, hit-location rolls, and AI tie-breaks must all be reproducible from a seed.

## Appendix B — out of scope (leave hooks, build nothing)
- **Co-op / netcode.** Keep `CombatState` fully serializable and all mutations flowing
  through Action objects, so a future authoritative-host layer could replay actions.
  Do not add multiplayer, RPCs, or `MultiplayerAPI` usage.

## Appendix C — hit resolution
Exposure-weighted part selection first, then cover interception.

```
resolve_hit(attacker, target, grid, rng) -> HitResult:
    parts = target.living_parts()              # destroyed parts are not selectable
    part  = weighted_choice(parts, key = exposure_weight, rng)   # roll the location

    cov = Cover.between(grid, attacker.cell, target.cell)        # CoverInfo, Phase 6
    if cov.object != null and part.slot_type in cov.profile:
        if cov.object.is_destructible:
            return HitResult(cover_object = cov.object)   # cover eats the shot; chip it down
        else:
            return HitResult(blocked = true)              # terrain soaks it → no damage
    return HitResult(part = part)                         # clean hit on the part
```

Notes:
- `exposure_weight` is per-part data. Default starting table (tune later):
  TORSO 40, LEGS 26, L_ARM 12, R_ARM 12, HEAD 10. Zero-weight or missing/destroyed
  parts are excluded from the roll.
- Cover does NOT reweight the roll; it reroutes the outcome. This is what makes a
  covered target soak fire into its cover until the cover breaks, at which point the
  protected slots re-open on later rolls. Reweighting by stance is a later tunable.
- `weighted_choice` must draw from the passed `rng` so results are seed-reproducible.

## Appendix D — encumbrance (volume + felt mass)
Two independent constraints.

**Volume — per container, non-composing.** Each container checks the sum of its
*direct* children's external `volume` against its own `max_volume`. A nested container
occupies its parent by its own `volume` only — its contents do not bulge the exterior.

**Mass — discount applies ONCE, only at the directly-worn layer.** "Felt weight" is
only reduced by a container the character wears/installs directly. A container nested
inside another container contributes NOTHING of its own `mass_multiplier`; it and all
its contents are summed flat and then discounted by the single worn container above them.
Multipliers never compose.

```
# Effective (felt) mass a chassis carries, checked against chassis.max_mass.
carried_mass(chassis) -> float:
    total = 0.0
    for part in chassis.slots.values():
        total += part.mass                          # worn/installed part, full weight
        if part.is_container:
            # everything inside the worn container, summed flat, discounted ONCE:
            total += _flat_contents(part) * part.mass_multiplier
    return total

_flat_contents(container) -> float:                 # ignore nested multipliers entirely
    total = 0.0
    for child in container.contents:
        total += child.mass                         # flat, no discount
        if child.is_container:
            total += _flat_contents(child)          # still flat, recurse for mass only
    return total
```

Worked example: backpack (own mass 2kg, `mass_multiplier` 0.5) directly worn, holding
50kg of loose gear → contributes 2 (bag, full) + 50×0.5 = 27kg. Now put a pouch
(own mass 1kg, `mass_multiplier` 0.8) holding a 10kg item *inside* that backpack: the
pouch is not directly worn, so its 0.8 is ignored — the pouch's 1kg and the 10kg are
flat-summed (11kg) and discounted only by the backpack's 0.5 → the 10kg becomes 5kg.
Worn the pouch directly instead and its 0.8 would apply: 1 (pouch, full) + 10×0.8 = 9kg.

(If you meant a *flat* subtractive offset instead of a proportional multiplier, swap
`child.mass * mult` for a clamped `max(0, child.mass - offset)` and drop composition —
but the multiplier model above is the default.)

## Appendix E — movement economy (AP → MP)
AP is the turn currency; movement runs on a separate Movement-Point pool that AP feeds.

- Each unit has `mp_per_ap`, derived from its agility/speed stat (from
  `aggregate_stats()`). Formula is a later tunable — start simple, e.g.
  `mp_per_ap = base_mp + agility`.
- Movement spends MP: each tile stepped costs `move_cost(cell)` MP.
- When the MP pool can't cover the next tile, the unit burns **1 AP** to add
  `mp_per_ap` MP. Repeat while AP remains. A `MoveAction` for a path does this
  automatically and fails if AP runs out before the path completes.
- Leftover MP is **discarded at end of turn** (does not bank across turns). Tunable.
- Within a turn, the farthest a unit can reach = `reachable(origin, current_mp +
  remaining_ap * mp_per_ap)` in MP terms (Phase 3).

## Session definition of done
Phase 11 green (headless sample battle passes) is the minimum bar. Phase 12 is a bonus
if time remains.
