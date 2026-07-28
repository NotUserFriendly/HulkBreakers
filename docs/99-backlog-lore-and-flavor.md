# 99 — Backlog: Lore, Flavor & Deferred Content

**Nothing in this file is in scope.** It is parked here so it stops cluttering the design
docs. CC must not build any of it. It exists so it isn't lost.

**What belongs here: the unspecified and unqueued.** Lore, character notes, interactions, and ideas
that do not yet have a shape. **If a thing is specified, it belongs in `PLAN.md`; if `PLAN.md` queues
it, it must be specified there. Nothing lives in both files.** A note here that grows a mechanism
graduates out into `PLAN.md`; a `PLAN.md` item that turns out to be a vague wish comes back here.

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

### Artificial muscle vs artificial bone
Distinct stats for the actuator and the structure of a limb, enabling *disabling* an arm
without severing it. **The socket graph already expresses this** — they're sub-parts on
`INTERNAL` sockets (`01`). Deferred as content authoring, not architecture.

### Loot affixes
Randomized affixes and small stat rolls on hulk-found gear, reinforcing the "original pattern
/ prototype" feel (`07`).

### Multiplayer
Raised, never scoped. Recorded so it is not mistaken for an oversight — it is a different game's worth
of work and it has never been costed. Not a taskblock.

### Mental hazards and psychic content
Wis-resisted effects as a hazard category. A premise with no mechanism behind it yet.

### Rampancy as active pressure
`PLAN.md` carries rampancy as a system; this is the separate question of whether it should push on the
player turn to turn rather than sitting as a state. A tuning and design question, not queued work.

### Climbing and grappling large shells
High-mobility units **climb** a shell larger than themselves and **grapple** one their own size — the
interaction is chosen by the *relationship between two shells*, not by either unit's own stats. Bespoke
animations per pairing.

Same principle as the parkour note under *Animation flavour*: select the animation from data the game
already produced rather than authoring a new decision layer on top. The difference is the input is
**relational** — the pathfinder's output describes one unit, this needs a comparison between two.

**Decide "bigger" before anything else here.** No size class exists. Three candidates already in the
codebase: `ShellTemplate.max_mass`, the summed `mass` of placed parts, or `UnitGeometry.bounding_sphere()`
radius (already computed for camera framing). The bounding sphere matches what a player *sees* and comes
free; mass matches what the fiction says and is already authored per-part. They will disagree — a spindly
tall frame and a dense squat one invert between the two — and the choice sets whether the mechanic reads
visually or numerically. Wants melee mature first.

### Melee zone targeting: manipulation and agility
Several distinct **routes to reaching a specific zone**, rather than one roll that either lands where you
wanted or doesn't:

- **Manipulation** — act on the opponent. Force an opposing unit's facing so its back is to you, opening
  whatever its front was covering.
- **Agility** — act on yourself. Jump behind the enemy and reach the same zones by moving instead of by
  forcing.

**Facing already exists** as a real float orientation across ~36 files, mutated through
`BoutInjector.set_facing()` and read by the tactics layer's `aim_facing()`. Manipulation is a mutation of a
value the game already tracks, not a new system.

Pairs with **Weak points**, which graduated to `PLAN.md`: that item supplies *why* a specific zone is
worth reaching, this one
supplies *how you get there*. Neither is worth much alone.

Design tension worth keeping in view when this is picked up: if both routes reach the same zones, the
choice between them has to be about cost and risk rather than outcome, or one of them is dead weight.
Contested manipulation (the target resists) against uncontested but MP-expensive agility is the obvious
first shape to try.

## Deferred systems
- **Ship upgrade tree** and **scanner tiers**.
- **Map selling** to other scavs.
- **Refining chains** and merchant inventories.
- **Surrogate vat** simulation: growth time, appearance from the matrix's preferences.
- **Dialogue / yapping.** The humanizing face is in scope (`04`); the voice is not, yet.
- Claims, faction reputation, local space encounters.

## Animation flavour
- **Parkour-flavoured movement, starting with the hood slide (tb35 review).** When a unit's path
  forces it to move diagonally twice in a row to get around an obstacle, a humanoid shell plays the
  **"car hood slide"** across it rather than walking the corner. The point isn't the one animation —
  it's that *path shape is already a readable signal*, so movement animation can be selected from the
  geometry the pathfinder already produced, with no new data. A double-diagonal is a vault; other
  recognisable shapes open up the rest of a parkour vocabulary. Purely presentational: it changes how
  a move looks, never its cost or legality.

## Presentation & branding
- **Startup logo animation.** A stylized/simplified voidhulk fades in, growing until it's logo-sized.
  The instant it's fully visible, a shell drops from above; a weld-splatter sound plays as a molten-
  metal "V" appears over the voidhulk with the shell seated in the V — reading as the shell cutting the
  voidhulk in half. Pure branding/title flavor; no system depends on it.
