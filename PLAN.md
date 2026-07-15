# PLAN.md — v2.1 Build Order

Read `docs/` first. **`docs/02` (projection & shot plane), `docs/08` (transparency pipeline)
and `docs/09` (turn phases, log, checkpoints) govern everything downstream** — read all three
before writing any code.

Work phases **in order**. Each ends green (`./run_tests.sh` exits 0) and committed.
"Acceptance" = the GUT tests you must write and pass.

**Checkpoints are hard stops.** At a checkpoint, run `./checkpoint.sh N`, commit the
artifacts, and **wait for a go before proceeding.** Five of them, at `docs/09`.

---

## Open-endedness: the standing rule
> **Enums for engine states. Open `StringName` vocabularies for content.**

CC will not be around to maintain this game. Anything a designer might add later must be
addable **as data, without a code edit**.

| Enum is correct | Must be open data |
|---|---|
| `Phase {TACTICS, RESOLUTION}` | socket types, attach tags, capability tags |
| `Outcome {PENETRATE, STOP_DEAD, DEFLECT}` | materials + DT + ricochet curve |
| `RecoveryState` | resource ids, part tags, perk ids |
| | surrogate tiers (ordered data ladder) |
| | scatter rings (**N rings, never 3**) |
| | AP costs, tunables, balance numbers |

If a test needs a specific list, the test authors that list as a fixture. Production code
must not know it exists.

---

## What survives from v1
| Verdict | Files |
|---|---|
| **Keep as-is** | `grid.gd`, `pathfinder.gd`, `map_gen.gd`, `combat_action.gd`, GUT harness |
| **Keep, extend** | `los.gd`, `combat_state.gd`, `inventory.gd`, actions |
| **Rewrite** | `part.gd`/`chassis.gd` → socket graph (`01`); `cover.gd` → a region in the shot plane (`02`); `run_state.gd` → mission loop (`07`) |
| **DELETE** | `Enums.SlotType`, `Part.slot_type`, `Part.exposure_weight`, `Targeting._weighted_choice`, `CoverInfo.profile` — the exposure table is obsolete (`02`) |

---

## Phase 0 — Harness, eyes & log
**Goal:** CC can see spatial state, and you can watch it. Nothing later is verifiable without
this.
**Build:**
- **Fix the v1 bug:** `los.gd::visible_cells` names its param `range`, shadowing the builtin
  `range()` it calls. Rename to `radius`.
- `src/debug/ascii_render.gd`: `grid_to_text()`, `plane_to_text()`, `overlay_impacts()`.
- `src/logic/combat_log.gd`: structured `LogEvent` + **pluggable sinks** (Memory, Stdout,
  File → `out/combat.log`). See `docs/09`.
- `checkpoint.sh N` → writes `out/checkpoints/NN/` with a `README.md` + artifacts.
- Add `gdlint src test` to `run_tests.sh` as a pre-test gate (`pip install gdtoolkit`).
- `test/determinism/`: helper asserting same-seed → identical output for any generator.
**Acceptance:** suite green; an ASCII grid prints in test output; a `FileSink` log appears at
`out/combat.log`; lint gate fails the build on a deliberate violation.
### ▶ CHECKPOINT 1 — ASCII maps across several seeds. **Stop for review.**

---

## Phase 1 — Part graph (`docs/01`)
**Goal:** inverted, tag-matched attachment.
**Build:** `Socket` (`socket_type`, `occupant`); `Part` (`attaches_to`, `sockets`,
`capabilities`, `material`, `volume: Array[Box]`, `ram_cost`, `mass`, `bulk`, `tags`,
container fields); `Frame` (`root: Part`, `max_mass`, `max_ram`, tree walks,
`aggregate_stats()`).
**Acceptance:**
- A torso with 12 `SHOULDER` sockets hosts 12 arms.
- A part tagged `attaches_to: [SHOULDER]` mounts on *any* shoulder, any frame, no
  parent-specific code.
- Deep tree: shoulder → upper arm → forearm → hand → pistol; a forearm sword blocks neither
  the upper-arm plate nor the shoulder pod.
- A drill on `WRIST` exposes no `GRIP` → pistol attach fails, **with no rule written for it**.
- **Capabilities:** a rifle requiring `{TRIGGER:1, SUPPORT:1}` is usable by a
  hand+saw cyborg; a pistol requiring `{TRIGGER:1}` is not usable by the saw; a saw adds no
  `POWER` to a melee swing.
- **Destroying a part drops its subtree as ONE intact assembly**, sockets still populated —
  not a pile of bits.
- No cycles; one occupant per socket; save/load round-trips a full tree.

---

## Phase 2 — Modifier pipeline & provenance (`docs/08`)
**Goal:** one resolver, recorded sources. Build **before** weapons — everything downstream must
be born inside it. Retrofitting means touching every system twice.
**Build:** `StatValue {base, current, sources}`, `ModSource {source_name, source_kind, op,
delta}`, `StatResolver.resolve(stat_id, context)`. Pure, deterministic. `DescriptionBuilder`
renders a resolved block to text, marking changed values.
**Acceptance:** a stat fed by part + perk + ammo resolves once and `sources` names all three;
the rendered description marks exactly the changed numbers; **nothing outside the resolver
computes a final stat** (grep test).

---

## Phase 3 — Body space & the shot plane (`docs/02`)
**Goal:** the spatial core. No facings — continuous projection.
**Build:** `Box` volumes in unit-local space; `project(unit, view_dir) -> Array[Region]`
(`rect`, `depth`, `part`, `surface_normal`); `ShotPlane.build(origin, dir, world)` projecting
**every** unit, cover object and obstacle along the line of fire into one depth-sorted plane;
`resolve_projectile(plane, point)` → frontmost region, or null.
**Acceptance:**
- Rotating the view angle continuously produces continuously-changing rects — **no
  discontinuities, no facing snap**.
- A rear ammo rack is occluded from the front, frontmost from behind, purely by depth.
- A plate over a part returns the plate; a point in a gap returns null.
- A shield authored as boxes-around-a-hole: a point in the hole returns the part behind.
- **Layered targets:** a near unit and a far unit in one plane — a point missing the near
  unit's boxes resolves to the far unit's. Same code path as a gap.
- Cover is just a region; destroying it removes its regions.
- ASCII plane dumps of all of the above in the test log.
### ▶ CHECKPOINT 2 — shot plane swept across 8+ angles. **Stop for review.**

---

## Phase 4 — Weapons & the dartboard (`docs/02`)
**Build:** weapon stats (`damage`, `burst`, `recoil`, `scatter: Array[Ring]`, `range`,
`ap_cost`, `requires`) — **all through the Phase 2 resolver**. `Dartboard.sample(aim_point,
scatter, rng, count)`. Radii scale with range (linear to start, tunable).
**Acceptance:** same seed → identical impact points; **an N-ring weapon works with N ∈ {1,2,3,5}**
(no code assumes 3); ring weights hold over many samples; a tight-inner-ring sniper hits a
named small region, a chaingun cannot; "Spin Up" shrinks a ring **via the resolver** and shows
up in `sources`.

---

## Phase 5 — Armor, DT & ricochet (`docs/03`)
**Build:** material table **as a Resource** (`dt`, `deflect_threshold`, ricochet curve).
`resolve_impact()`: penetrate / stop-dead / deflect, decided by real geometry — `bend_angle`
between incoming vector and the hit box's `surface_normal`. Deflection spawns a ricochet
travelling the world.
**Damage retention:** `retained = lerp(0.90, 0.25, clamp(bend_angle / MAX_BEND, 0, 1))` —
endpoints and curve live in the material table, not in code. Cap ricochet depth (default 2) +
damage floor; **the sim must terminate**. Crits: bypass armor if armored, bonus damage if not;
crit chance is a float, >100% enables double crit. `VOLATILE` parts cook off.
**Acceptance:**
- A chaingun burst under DT fails to penetrate steel; a rifle round over DT damages plate
  **and** the part behind.
- Stop-dead damages the plate; deflect does not.
- **A graze retains ~90% and can kill someone behind; a near-right-angle bounce retains ~25%.**
- Ricochets terminate; a seeded burst replays identically and can be shown tagging a third party.
- Double crit fires at 125% and applies both effects. Ammo rack destruction cooks off.
### ▶ CHECKPOINT 3 — seeded burst into armor: deflections, paths, retained damage. **Stop.**

---

## Phase 6 — Tactics/Resolution & combat integration (`docs/09`, `docs/03`, `docs/05`)
**Goal:** the two-phase turn. Structural — do not defer it.
**Build:** `Phase {TACTICS, RESOLUTION}`; `ActionQueue` per unit; queue-time validation against
a **speculative** state copy (previews only, **no authoritative mutation in TACTICS**);
`resolve_turn()` executing all queues deterministically with **re-validation** — an action made
illegal by the moving world aborts, **logs a reason**, and the queue continues.
Rebuild actions against the socket model: `MoveAction` (AP→MP economy unchanged, 6 AP
baseline), `AttackAction` (aim point → dartboard → shot plane → impact), `SwapPartAction`,
`ModifyAssemblyAction` (strip a dropped assembly, costs AP), `PickUpAction`, `CarryBodyAction`
(→ `BACK` socket, `INERT`: contributes mass + volume boxes only — no stats, no weapons, no RAM,
and blocks a backpack), `EndTurnAction`.
**Acceptance:** queuing mutates nothing; a queued attack on a target that dies earlier in
resolution aborts with a logged reason and the rest of the queue proceeds; a carried body eats
rounds aimed at the carrier's back via the projection alone; flanking exposes rear regions; the
turn replays identically from a seed.

---

## Phase 7 — Matrices, surrogates & deep strike (`docs/04`, `docs/00`)
**Goal:** the mind layer — and the randomization stress test.
**Build:** base/link matrix split; `effective_level = base.level * link.tier_ratio`;
`perk_slots` from link tier, player-chosen. Surrogate tier as an **ordered data ladder** with
damage-driven demotion and a turn clock decaying exposed organics. Ejection from the
`MATRIX`-socket part. Recovery states: PILOTING, CARRIED, LEFT_BEHIND, LINK_KILLED.
**Deep strike:** insert matrices with **no loadout**; assemble cyborgs from whatever frames the
hulk has; force enemy matrices out of occupied frames.
**Acceptance:** link destruction flags death feedback on the base; a low-tier link caps
effective level but carries the base's top perks; a torso chewed to SPINAL still functions;
exposed organics decay per turn; **matrices are never lost on any path**.
**Fuzz test (the real point):** generate N random valid cyborgs from a part pool across many
seeds — every one must satisfy socket/mass/bulk/RAM invariants, project a sane shot plane, and
either be armed or be knowably unarmed. No crashes, no malformed assemblies.
### ▶ CHECKPOINT 4 — 20 random deep-strike cyborgs, ASCII + stat blocks. **Stop for review.**

---

## Phase 8 — RAM, inventory & loot (`docs/05`, `docs/07`)
**Build:** `max_ram`/`ram_cost` checked alongside mass and bulk — three independent
constraints. Encumbrance rules from v1 **unchanged**. Loot tables: `merchant_pool` and
`hulk_pool` **mostly exclusive with a deliberate small overlap** — shared designs appear as
`standard` from merchants and `original_pattern` / `prototype` from hulks, minor but visible
differences. Tool tiers priced in AP against the 6 AP baseline.
**Acceptance:** a weightless drone swarm fails on RAM while passing mass; v1 mass/bulk tests
pass verbatim; the overlap set is small, intentional, and variant-tagged rather than
duplicated.

---

## Phase 9 — Mission loop (`docs/07`)
**Build:** `MissionState`: objectives, `extract()` (keep loot), `terminate()` (lose loot,
matrices return). `RunState` v2: roster, stash, resource counters (**data-driven ids**),
credits, seed. Hulk pseudo-persistence: map fixed by seed, population re-rolled per visit.
**Acceptance:** extract banks loot; terminate loses loot and returns every matrix; revisiting a
seed yields an identical map with a different population; save/load round-trips.

---

## Phase 10 — Terminal UI & the transparency proof (`docs/08`)
**Build:** `RichTextLabel`/BBCode terminal panels; a `Theme` resource (6 colors, one mono
font); stat block rendering with changed-value highlighting and drill-down to `sources`;
burn-stack decimal rule + explainer; **the rolling combat log panel** as a `UISink` (`09`);
stat panels for **partially obscured targets deeper in the shot plane**, not just the nearest.
**Acceptance — the headline test:**
```
for every (loadout, target, seed):
    assert tooltip_predicted_damage(...) == simulate_damage(..., seed)
```

---

## Phase 11 — Headless full mission (integration)
**Build:** `test/integration/test_full_mission.gd`: seed → hulk → insert (both modes) →
deterministic AI queuing multi-action turns → gather objective → extract. Full `combat.log`.
**Acceptance:** terminates within a turn cap; exercises shot plane + dartboard + DT/ricochet +
cook-off + RAM + surrogate decay + tactics/resolution + extraction, zero errors.
**This is the definition of done.**
### ▶ CHECKPOINT 5 — full mission combat log. **Stop for review.**

---

## Phase 12 — 3D view (bonus / next session) (`docs/08`)
HL2-era budgets, CC0 placeholders. Grid render, unit markers, click-to-select, click-to-move.
Third-person zoom on attack showing the dartboard over the target; plain click = default burst.
**Acceptance:** a human plays one mission end to end.

---

## Appendix — standing rules
- **Determinism:** never call `randi()`/`randf()` in logic. Pass a seeded
  `RandomNumberGenerator`. Mapgen, scatter, crits, ricochet, AI tie-breaks — all reproducible.
  Deflection angle is **geometry, not a roll**.
- **Terminology:** matrix / surrogate / frame / cyborg / bot. **"Robot" is retired** (`docs/00`).
- **Out of scope:** co-op/netcode (keep `CombatState` serializable and action-queue-driven,
  build nothing), and everything in `docs/99`.
- **Ask, don't invent:** if a formula isn't specified (`mp_per_ap`, tier ratios, the
  LEFT_BEHIND penalty), use the stated default or leave a flagged hook. Never invent balance
  numbers and present them as design.
