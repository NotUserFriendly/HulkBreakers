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
either be armed or be knowably unarmed. No crashes, no malformed assemblies. Every assembly must
project a **non-degenerate** shot plane — not just a root box floating alone — and every living
part must actually appear in it; a part with `hp > 0` and no `volume` is a
`validate_assembly()` violation, not a silent gap in the plane.
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

## Phase 12 — 3D view (`docs/10`)
Read `docs/10` first. Phase 12 is a **view over** the simulation: it reads, RESOLUTION
writes, and no number is born in a UI script (`docs/10`, three laws).

One battle. No mission loop. The goal is something a human can see, play, and show off.

**Sub-phases are sequential.** 12.0 is a hard prerequisite and is fully headless — it goes
green before any scene exists. Checkpoints 6 and 7 are hard stops.

### Phase 12.0 — Socket transforms (headless, do first)
**Goal:** make modularity geometrically real. Without this the 3D view is a lie.

Today `Socket` is `{socket_type, occupant}` and `Part.volume` is authored in absolute
unit-local coordinates; `BodyProjector` never consults sockets. So a torso with 12 `SHOULDER`
sockets hosting 12 arms places **all twelve arms at identical coordinates**. The `docs/01`
modularity pillar isn't expressible in geometry, and the shot plane is only correct for
single-box bodies.

**Build:**
- `Socket.transform: Transform3D` — the attachment frame, in the **host part's** local space.
- `Part.volume` boxes become relative to the **part's own** origin, not the unit's.
- `BodyProjector`: compose transforms down the socket tree (`world = parent ∘ socket ∘ local`)
  before projecting. Cache per projection call; don't recompute per box.
- Migrate every existing fixture to part-local coordinates.

**Acceptance:**
- A torso with 2 `SHOULDER` sockets at mirrored transforms, hosting **the same arm Part
  resource twice**, projects **two arms in two different places**.
- Scale it: 12 sockets → 12 non-overlapping arms.
- The same weapon Part attached to a left vs right shoulder projects at different x.
- Deep chain (shoulder → upper arm → forearm → hand → pistol) composes: rotating the shoulder
  socket moves the pistol.
- **Regression:** every Phase 3/5 test still passes — union invariant, graze/right-angle
  spread, layered targets, continuity sweep. Silhouettes must not change shape for
  single-box fixtures.
- Checkpoint 2's angle sweep still shows no discontinuity.

### Phase 12.1 — Board, bodies, camera
**Goal:** the battle renders. No input yet.
**Build:** `res://src/view/` — `BattleScene` root; `BoardView` (grid → tiles, blockers →
meshes); `UnitView` (walks the socket tree, emits a `BoxMesh` per `Box` at its composed
transform — **render is hitbox**, `docs/10`); material→colour from `HulkTheme`; `CameraRig`
with orbit/pan/zoom. `project.godot` main scene set. A "New Battle" button seeds a fight.
**Acceptance:** launches via `godot --path .`; a seeded battle draws; every unit's visible
geometry matches its `volume` boxes exactly; destroyed parts disappear; camera orbits without
gimbal weirdness.
### ▶ CHECKPOINT 6 — screenshots: the board, a cyborg close-up, a 12-arm test rig. **Stop.**

### Phase 12.2 — Selection & queued movement (TACTICS)
**Build:** `SelectionController` (pure): click → unit; `Pathfinder.reachable(cell, mp)` →
highlight set. Click a reachable cell → **queue** a `MoveAction` against the speculative
clone (`docs/09`), draw a ghost path. Multiple queued actions stack visibly. `End Turn`
button. **Nothing mutates authoritative state in TACTICS** — that's a test.
**Acceptance:** reachable highlight matches `Pathfinder.reachable` exactly (assert the
controller, not pixels); queuing two moves shows two ghosts; a headless test proves
`CombatState` is byte-identical before and after queuing.

### Phase 12.3 — The aim UI (the signature screen)
**Build:** per `docs/10`. `AimController` (pure, testable): `(plane, reticle, layer_index) →
{layers, reading, resolves, rings}`.
- Group the shot plane's regions by owning body → ordered layers, nearest first.
- **Scroll steps the layer index; it never moves the reticle.** The aim point is fixed in
  plane coords, shared across layers.
- Draw: layer N solid + highlighted; layers < N ghosted (the occlusion you'd thread); scatter
  rings around the reticle from the resolved `Array[Ring]` — **read the array's size, never
  assume 3**.
- Readout shows **both**, never conflated:
  `READING: enemy_b (layer 2 of 3)` and `RESOLVES: enemy_a / torso_plate`.
  `RESOLVES` is always `resolve_projectile(whole_plane, reticle)` — frontmost-first against
  the entire plane. Scrolling must not change it.
- Confirm → queue an `AttackAction` carrying the reticle's `aim_offset`.
- Plain click on an enemy with no interaction → default burst at centre.
**Acceptance (all on the controller, headless):**
- Scrolling changes `reading` and **never** changes `resolves` — the load-bearing test.
- With a near body fully occluding a far one, no reticle position resolves to the far body.
- Punch a gap in the near body → a reticle in that gap resolves to the far body while
  `reading` can still be either. **That's the sniper thread, asserted.**
- A 1-ring and a 5-ring weapon both render correct ring counts.
- Layer count matches the number of distinct bodies in the plane.

### Phase 12.4 — Resolution playback
**Build:** `LogPlayback` (pure): `Array[LogEvent] → ordered [{time, cue}]`. The view **replays
the log** — it does not drive the sim (`docs/10`). Sequence: banner + lock input → wait
`RESOLVE_LEAD_IN` (~1.0s) → play cues, projectiles staggered `PROJECTILE_STAGGER` (~40ms),
tracers may be raycast fakes (muzzle→impact line is enough) → wait `RESOLVE_TAIL` (~1.0s) →
banner TACTICS + unlock. All timings are constants in one place. Destroyed parts hide — **no
ragdolls this phase**.
**Acceptance:** `LogPlayback` maps a known event stream to the expected cue list with expected
offsets (headless); replaying the same seed twice produces an identical cue list; input is
locked for the whole of RESOLUTION.

### Phase 12.5 — Terminal shell
**Build:** real OFL monospace font into `HulkTheme` (one-line swap from the built-in
default); rolling combat log panel fed by the existing `UISink`; selected-unit stat block via
`StatBlockView` with `docs/08` drill-down; the aim readout panel. Six colours, one `Theme`,
no per-scene styling. **No CRT/scanline/glow** — later shader pass.
**Acceptance:** the log panel streams during playback; a stat block drill-down shows
`sources`; the transparency proof still holds — the tooltip's predicted damage equals what
the log reports for that shot.
### ▶ CHECKPOINT 7 — a recorded playthrough of one full battle. **Stop for review.**

### Definition of done for Phase 12
A human launches the game, selects a cyborg, queues a move and an aimed shot, scrolls the
dartboard to inspect a target behind the first one, ends the turn, watches the burst fire and
ricochet, and reads the log — repeatedly, until one side is down.

### Out of scope for Phase 12
Mission loop, gather/extract UI, roster/meta screens, ragdolls, real meshes, sound, the ship,
deep-strike UI, height levels, giant units. All later — none of them are blocked by anything
here except the grid's height component.

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
