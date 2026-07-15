# 99 — Backlog: Lore, Flavor & Deferred Content

**Nothing in this file is in scope.** It is parked here so it stops cluttering the design
docs. CC must not build any of it. It exists so it isn't lost.

---

## Story (deliberately nebulous)
No plot is committed. Candidate hooks, pick later:
- Something is **reactivating** the voidhulks.
- Something **very large** is eating them.

Tone anchor: **not post-apocalyptic.** The world is dangerous but has safe places — your crew
simply isn't the type to stay in them.

## Crew types beyond Intelligence Matrices
Later you may find uses for:
- Unaugmented humans
- Non-Intelligence-Matrix bots (plain Logic Matrix units)
- **Aliens**, if you choose to risk it

## Hazards (flavor + future systems)
| Hazard | Sketch |
|---|---|
| **Radiation** | Old-school nuclear engines still cooking. |
| **Decompression** | Hulks hold atmosphere well — until you start cutting. |
| **Defense grids** | Remnant turrets, automated bots, indiscriminate traps. Colony ship or star destroyer, something's still armed. |
| **Psychic incursion** | Large pools of death and suffering invite strange, violent visitors. |
| **Evolved inhabitants** | A hulk had a crew once. Who says they left? |
| **Infestation** | Things from the deep dark came for the biomass a millennium ago. Their descendants live here now. |
| **Pirates** | Mostly too scared to delve deep, but they make the surface and local space dangerous. |

## Hulk variants
| Variant | Sketch |
|---|---|
| **Settled** | Someone claims the whole hulk; buy a claim or don't cut. Safer than unknown hulks. |
| **Planetside / dirthulk** | Crashed. Worse shape, plus planetary hazards. Light on easy loot; deep loot far more valuable. |
| **Gashulk** | Caught in a gas giant's storm. Not long for the world — airborne dust abrades it away fast. |
| **Organic hulk** | Born or built? Halls of gore, fluid underfoot that's blood or near enough. A gold mine if you can store the meat — one could feed a colony for decades. Don't tell them where it came from. |

## Tilesets
| Set | Look |
|---|---|
| **Overgrown** | UV lights, leaky pipes, dirt everywhere → vines and broad jungle leaves. |
| **Battleworn** | A violent confrontation happened here. And there. And everywhere. Few bodies, though. Did the victors take them, or eat them? |
| **Pristine** | Suspiciously move-in ready. |

## Deferred mechanics (raised, deliberately postponed)

### Weak points
A **major benefit that forces a vulnerability**. Example: a powerful reactor that must vent
heat every few turns — vents open, a large heat sink protrudes, and for that window shooting
the sink is equivalent to shooting the reactor directly: coolant leaks, possible meltdown.

Architecturally cheap once `02`/`03` exist: a weak point is a **volume box that only projects
during certain turns**, plus a damage rule that forwards to its parent. No new systems. Purely
a scope call — postponed.

### Artificial muscle vs artificial bone
Distinct stats for the actuator and the structure of a limb, enabling *disabling* an arm
without severing it. **The socket graph already expresses this** — they're sub-parts on
`INTERNAL` sockets (`01`). Deferred as content authoring, not architecture.

### Loot affixes
Randomized affixes and small stat rolls on hulk-found gear, reinforcing the "original pattern
/ prototype" feel (`07`).

## Deferred systems
- **Ship upgrade tree** and **scanner tiers**.
- **Map selling** to other scavs.
- **Refining chains** and merchant inventories.
- **Surrogate vat** simulation: growth time, appearance from the matrix's preferences.
- **Dialogue / yapping.** The humanizing face is in scope (`04`); the voice is not, yet.
- Claims, faction reputation, local space encounters.
