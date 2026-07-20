# PLAN.md — Forward Build Order (v3.1, keystone-sequenced)

**Forward-only and volatile.** Sequences *unbuilt* work. Built work → `CHANGELOG.md`; reversals →
`SUPERSEDED.md`. Reorder freely — a sequencing tool, not a contract.

Prior build orders (v2.1 and earlier) described the from-scratch foundation and are **fully retired**;
only the two standing rules below survive.

---

## The two standing rules (unchanged)

**1. Enums for engine states. Open `StringName` vocabularies for content.** Anything a designer might
add later must be addable **as data, without a code edit**. Engine states are enums; content (socket
types, tags, materials, perks, statuses, scatter rings — *N rings, never 3*) is open data.

**3. Author everything as parts — including infrastructure, huge objects, and wreck-chassis.** If
the 5000L tank, a combat-tank wreck, a flatbed, and hulk fixtures are all authored as normal parts
(sockets, mass, bulk, salvage, capabilities) from the start, then vehicles/movable-objects later are
just *assembling existing parts* — no retrofit. Design the parts right and they drop onto vehicles
for free.

**4. Human-shaped is versatile; every departure costs you.** This is a robots-built-for-human-tasks
world, so human-shaped units fit human infrastructure (seats, doorways, tools) and weird-shaped ones
don't. A constraint that *generates* gameplay — a seat expects a torso, so a legless ally can still
ride but a mulebot can't sit in the driver's seat. Let shape be a real tradeoff, not just cosmetics.

**2. Checkpoints are hard stops.** Verify view math by reading the real node back, never re-deriving
it in the test.

---

## Structure of the remaining work

A **foundational layer** the rest reads from, then three **keystones** in dependency order, then the
**systems** that hang off them, then **meta** and **backlog**.

---

# FOUNDATION — Attributes (build before Perks; ideally before much else)

*Surfaced mid-planning: willpower/personal_speed/etc. are all facets of one stat layer. Landing it
first means Perks (which mostly modify attributes) build against a stable foundation instead of a
moving target.*

**The six attributes live on the MATRIX, not the shell.** A strong matrix outside a shell gains
nothing; inside, it makes weak bots serviceable and strong bots incredible — an attribute is
*competence at using the body's capability*, not the body's raw capability. The same shell performs
differently under different pilots. This is the matrix-is-the-real-unit premise made mechanical.

- **Start with the D&D six + modifiers** (explicitly provisional names): **Str** (skill applying
  force / carry), **Dex** (reflexes — **personal_speed folds under here**, re-expressed), **Con**
  (durability / endurance), **Int** (logic — hacking), **Wis** (strength of mind — mental-hazard
  resistance, rampancy resistance), **Cha** (face — merchant deals, social/contract outcomes, and
  with Wis, overwriting an enemy mind).
- **Re-express existing stats through attributes** — `personal_speed` (tb18) becomes a Dex facet.
  This touches the resolution-speed system; do it carefully, it's a refactor.
- **Provisional naming** — some may merge/rename (Cha may split social from authority; machine minds
  may want different Wis/Int). Familiar names for velocity; **treat them as placeholders**, nothing
  should be load-bearing on the literal name.

**Acceptance:** the six attributes + modifiers on the matrix; personal_speed reads from Dex with no
behavior change; a stat resolves through `StatResolver` with the attribute as a provenance source; a
shell's performance differs measurably under two different-attribute matrices.

---

# FOUNDATION — Multi-level maps (two coupled systems; first is a live bugfix)

*Surfaced during mission-gen planning. The spatial layer is already 3D geometry **flattened to
y=0** — `body_projector` builds parts in `Vector3` then projects to `Vector2`, discarding height.
That discard is not just a multi-level blocker; it's a **live bug**: vertical scatter collapses, so
spread shots stitch a horizontal line across a body (the "line of impacts across the waist") instead
of spreading up and down. So true-3D resolution is required regardless of maps — multi-level rides
on the fix.*

## Block 1 — True-3D shot resolution (a bugfix that is also the foundation)
Buildable and **verifiable in the current flat game** — no maps needed. De-risks everything: the
scariest piece proven in isolation before any map complexity.
- Stop discarding height in projection; parts project with real vertical position.
- The dartboard scatters in **3D** — shots spread up/down a body, fixing the waist-line bug.
- Firing arcs, grenade lobs, floor-bounces, inter-level shots all become *expressible* (not built
  here, but the plane can now represent them).
- **Acceptance:** a spread burst stitches vertically across a body, not a single-height line;
  same-seed determinism holds; existing flat combat is unchanged except for the corrected vertical
  spread.

## Block 2 — Grid height + movement verbs (on proven 3D resolution)
- **Discrete level for logic, true height for position.** Cells gain an integer level (`Vector2i`
  → height-aware); a unit's actual Y is continuous. 22.5° ramps rise 0.5/tile → two ramps = one
  full level (a unit halfway up a one-tile ramp is at 0.25). Discrete height gates *decisions* (can
  I climb, is this fall lethal, what can I path to); true height drives *position and the shot
  plane*.
- **Vertical movement verbs** — hop-down / climb-up via leading-edge detection; ramps/stairs move
  occupants at true height; height-aware pathfinding.
- **Height needs no special cover/LoS rules** — it falls out of correct 3D projection. Higher →
  better sightline over cover → the dartboard sees more of the target. Skylined on an edge → nothing
  behind you → easier to hit. Emergent from geometry, not bolted-on bonuses. (A dedicated *height
  advantage* like throwing farther waits on a future arc'd-shot handler.)

---

# KEYSTONES

## Phase M — Melee (keystone 1)
*First: the only keystone that's a combat mode; self-contained; un-stubs suppression; unblocks the
deferred AI playstyles.*

- **Melee resolution** — decide: shot-plane projection at reach-1 (reuse the geometry) vs direct
  adjacent-part selection. Reach as a weapon property.
- **The punch** — the baseline melee every unit has (patches "no weapon → nothing" with tb21 flee).
- **Un-stub suppression** — tb19's opportunity attacks resolve as real melee.
- **Melee AI playstyles** — psychotic (prefer melee, never flee) / turtle (flee over melee).
- **Protector playstyle** — positions between enemies and allies, preferring covered spots. A
  COVER_SEEKER variant that scores on *ally* protection (guard the ally's line) rather than self.
  Support behavior the enemy factions want (bodyguard bots). No new machinery — same cover-scoring,
  different subject. (Not melee-gated; can land whenever, listed here with the other playstyles.)
- **Weapon distinctions** — saw vs sword vs fist (the `POWER`/`TRIGGER` capability split).

## Phase S — Status effects & boosts (keystone 2)
*Second: hooks already fire into the void; tb20's wounds need the status→wound threshold; status and
boosts are one system.*

**Burn, bleed, and tesla-charging-allies are the same shape** — a timed, stacking modifier through
`StatResolver`. Buff vs debuff is a sign. Build once.
- **Stack model** — accumulation, decimal stacks preserved, decay-below-half-vanishes, per-turn tick.
- **Consume the live hook** — `status_applied` already fires; make burn/bleed read it.
- **Boosts** — the buff direction (ally-applied).
- **Status → wound threshold** — closes tb20's dangling hook (burn → burnt_electronics).
- **Retire the docs/08 burn fiction.**

## Phase P — Perks (keystone 3)
*Third — and hardest: unblocks the most, but half of all perks modify melee, status, and attributes,
so it builds after those exist.*

**THE CENTRAL CONSTRAINT — framework before perks:**
> **Every perk is data describing a modification, plugged into an existing seam — never bespoke code
> per perk.** If perks are each programmed differently, the system is a maintenance catastrophe.

- **The perk framework** — a perk `.tres` declares *what seam it binds and how*. Seams exist: the
  `StatResolver` mod-sources (incl. attributes), the tb18 speed-bonus hook, the tb20 reaction hook,
  the action-provider model (tb07), the tb20 AP-coaxing hook, rule-override hooks.
- **Categories (each a kind of *binding*, not code):** stat modifiers; action grants (overwatch,
  Fan-the-Hammer); ordering (Quickdraw / Ghost Step / Sixth Sense); reactions (dive-prone,
  shield-turn); rule overrides (dual-weapon inverts `attaches_to`; player-advantage verbs; the
  **matrix-mobility perks** below).
- **Named perk examples to stress-test the framework** (beyond the five classes): *First One's
  Always Perfect* — the first shot of a burst/activation ignores all accuracy modifiers and lands
  dead center, then normal scatter resumes (the inverse of recoil; binds to the dartboard/accuracy
  seam — "force center on first pull"). A clean data-binding, exactly the shape the framework must
  express.
- **The five classes are the acceptance test** — Gunslinger, Hotswapper, Hulk, Cutter, Demolitionist.
  If all five express as data bindings with **zero bespoke perk code**, the framework is right. A
  missing seam → add the seam, not the special case.
- **`Matrix.perks` finally read.**

---

# SYSTEMS (hang off the keystones; sequence by appetite)

## Power + Therms — "the reactor phase"
*Power is partly built (tb20/22 power→AP curve); therms are new. Fold them together — a reactor makes
both power and heat, so simulating one without the other leaves it half-modelled. Refine power to
level with therms while doing this.*

**Therms = a general per-part resource** (literal heat; named *therms* to avoid colliding with the
faction "they're onto you" **heat** system — same word, different meaning, so the thermal one gets
the world-flavoured unit). Modelled like power: parts **generate, transfer, mitigate, and
dissipate** therms, and thresholds trigger poses/failures.

**Conduction = particle leveling, material-rated.** Every part, the ship, the air, and (later) each
tile is a **particle**: a therm counter + a **max-transfer rate**. Therms flow hot→cold between
connected particles, tending toward equilibrium. Transfer is governed by the **lower** of the two
particles' max-transfer (the bottleneck limits flow, bidirectionally) — so a reactor casing at
transfer 0.1 bleeds ~1 therm into the torso over ~10 turns even holding 100. **Insulation is just a
low transfer rate** — casing, cladding-insulation, and flesh all unify under one number; nothing is
a *perfect* insulator, so the reactor always eventually cooks its host, the heatsink just wins most
of the cooling. This keeps the sim cheap: O(connections), resolved **per turn at start-of-turn** (a
flamethrower's therms don't land until the target's next turn — max ~5 units per simultaneous group,
trivial load), which also delays the consequence usefully (see the trigger-signal principle).
- **Sockets bypass cladding for part-to-part** — heat conducts structurally (part→socket→part,
  direct), but *venting to air* must pass through cladding first. So cladding is a **thermal
  liability**: a heavily-clad unit traps its own heat (armor vs cooling — the tank is protected but
  cooks itself).
- **Two sinks:** the **floor** (a unit vents into the ground, unless the tile is on fire) and the
  **air** (an exposed/outer part vents to atmosphere, unless **vacuum**, unless the air is mostly
  fire). This makes environmental hazards *thermal* modifiers, not separate systems: **vacuum
  removes air-cooling → robots overheat** (the robotic inversion of "a human suffocates"); a burning
  room removes cooling and adds therms. Ties decompression + fire into one interacting system. (Tile
  states — spilled kerosene = slick, ignited = hot — are the tile-particle version, later.)
- **Burn → therm conversion by material tier** (ties therms to the status-system burn): **fire-
  resistant** parts convert burn stacks to therms *as they expire* (delayed); **fireproof** parts
  convert burn directly to therms at 50% (immediate, lossy). Fireproofing isn't immunity — it's
  *transmutation*: you don't burn, you heat up, and can still cook your internals. Every departure
  costs you.
- **Therms go negative — cold is a real value, not a floor.** The particle sim already levels
  hot→cold; letting counters go below zero just makes "cold" real. A dead hulk on a moon's dark
  side is a frigid tile (e.g. −50 therms) that *pulls* heat out of anything touching it — same
  leveling math, no new mechanic. Therms are a **deliberate linear simplification** of a non-linear
  thermal reality (legibility over physics — don't "fix" the linearity later).
- **Environment temperature favors different builds** (emergent, zero new systems):
  - A **reactor unit in a frigid hulk is in its element** — cold floor + cold air are huge sinks, so
    it dumps therms fast, runs hot without the heatsink venting, and its weak point barely exposes.
    The same unit in vacuum/heat vents constantly and stays vulnerable. Read the environment, bring
    the right build.
  - **Robots** care only about the *hot* end (overheat), wide tolerance. **Surrogates** suffer at
    *both* extremes — a **wide but bounded band** (engineered flesh: anti-coagulants for freeze/thaw,
    toughened collagen against hot metal — tough, not delicate, but not limitless). Baseline humans
    would be the narrow band surrogates were built to widen. Organic/mechanical thermal split: robots
    robust-one-directional, surrogates tough-but-two-ended.
  - **Life support = a surrogate-socket power→heat converter** (the heatsink inverted: spends power to
    *add* heat). So a surrogate in the cold becomes a power **consumer** — cold environments lower a
    fleshy unit's effective AP via the power surplus math. Clean tie-back to power.
- Fire-resistant parts **accumulate therms instead of burning** — too hot and components fry. Ties
  to the status system's **burn**; cook-off (VOLATILE) and **MELTDOWN** become therm-threshold
  events.
- **Deep sim, shallow surface** — the transfer/mitigation math runs under the hood; the player just
  sees "that's glowing and sticking out, shoot it." Legible without a nuclear-engineering degree.

**Weak points are emergent from this, not a separate system.** The reactor is the defining example:
- Three real parts: **core**, **heatsink**, **insulated cladding**. The reactor is insulated — it
  does NOT leak therms into its sockets, so it can't cook the shell directly. Its **only** cooling
  path is the heatsink — which is *why* the heatsink is the single point of failure.
- **Heat loop (per round):** reactor makes 10 power + 10 therms; heatsink pulls 10 from the reactor,
  mitigates 1/round (net +9 accumulating on the sink); sink > 20 → it **physically juts out of the
  shell** (a pose — part position change, so it now projects into the shot plane and is hittable),
  venting 13/round while extended; hits 0 → retracts that turn.
- **The weak point is a moving part, not an occlusion toggle.** Nothing un-hides; the heatsink is
  always there, but only *reachable* when extended. A high-damage round can still punch the cladding
  DT to the sink anytime (tb20 layered body); the vent just opens a window where a *weak* round
  reaches it too.
- **Usage-driven, self-balancing:** more reactor use → more therms → more/longer venting. A dumb
  unit burning all its AP vents predictably (effectively fixed); a paced unit stays protected. Same
  mechanic, playstyle-differentiated, no special-casing. (Fixed-cycle exposure stays an authored
  option for deliberately-predictable enemies.)
- **Failure cascade:** heatsink extended → shot → **mangled** (existing failure mode) → stops pulling
  therms → reactor climbs unchecked → > 50 → **meltdown**. The attacker isn't hitting a designated
  weakspot — they're *sabotaging the cooling system*.

**General weakness pattern (beyond the reactor):** any part can carry a weakness = an **exposure
condition** (usage-threshold / action-active / fixed-cycle) that moves an internal into reach.
"Something opens up while overwatching or bursting" is the same shape — an action-active exposure.
Duration is part of the condition (while-overwatching lasts as long as the overwatch; vent-on-usage
opens a fixed window then retracts).

**Delayed-lethal consequences need a signal at trigger-time, not death-time (design principle).** In
most games a weak-point hit just explodes the enemy. Here the heatsink shot does nothing *visible*
for a turn or two, then meltdown — unreadable without feedback. So a delayed-fatal state must
announce itself when *triggered*: the future notification system saying, calmly, "Nuclear Runaway
Detected." This applies to any delayed-lethal consequence, not just reactors — signal the cause, not
just the death.

## Matrix mobility
*The matrix-is-the-real-unit premise made tactical. Mostly connects existing systems (welder,
batteries, power, assembly, sockets) plus one new capability: the matrix as a physical object.*

**Premise that sets the stakes:** player logic matrices are **quantum-linked copies** of a shipborne
intelligence matrix. Destroying a logic matrix costs a *resource* (the copy), never a *life* (the
original feels only reverb). So a physical, losable matrix is high-stakes-to-protect but never
unfair.

- **The matrix is a physical object** — targetable, carryable (a cored friend's matrix goes in your
  backpack), installable. It **acts as a battery** (reserve + output, tb22 power curve) — a bodiless
  shell limps on matrix power; burn it for a last stand or conserve it to linger. No special limp
  state; it's just low surplus.
- **Extract and install are separate actions** — a matrix can be caught mid-transfer (where stealing
  happens). A loose matrix is fragile; landing on an ally's tile → they catch it.
- **Ejection is socket-geometry-driven** — a back-mounted socket ejects in a ~30° rear arc (the
  shot-plane/cone math, pointed at launch). Pulling your own matrix without a perk **crumples the
  shell** (it runs the standing-routine it leaves behind).
- **Revive is emergent, not a mechanic** — repair the shell (welder, tb22), power it (battery swap),
  install a matrix. Three separate actions; doing all three "revives" someone. Matrix-rescue and
  shell-repair are fully independent (repair every shell, install no matrix, if you like).
- **Multi-slot shells** (torso / head / dedicated backpacks can carry matrix slots) run a **willpower
  authority roll-off at round-top** — winner takes a full turn, loser none, tie splits AP. Every
  matrix knows before its turn whether it acts. A slot can be **disabled** by someone working the
  shell (strands a matrix — safe transport of captured enemies).
- **Perk-gated advanced cases (→ Phase P):** Master (steal AP + willpower + minor stats), overwrite a
  living bot (Cha+Wis), live-transfer to an enemy matrix, clean self-extraction.

## Rampancy
*A mission-length pressure with counterplay, tied to systems that exist (RAM battles).*

- Logic matrices degrade toward **rampancy** slowly; intelligence matrices never do (the quantum link
  keeps them ship-side, always defragged).
- **Accelerated by conditions** — losing RAM battles, hostile hulk environments, age. A rampant enemy
  is rampant *for a readable reason* (alone, too long, bad place).
- **Counterplay** — defrag on ship, or a **field defragmenter** backpack item for long missions.
  Creates the "extract sooner vs push deeper" tension and gives RAM battles a consequence.
- **Captured enemy matrix → ship defrag → friendly/valuable** (lore-forward; a high-tier matrix you
  can copy a player onto for a boss-tier upgrade, deliver as a quest, or crew). Value resolved in the
  meta layer.

## Mission / voidhulk generation
*The scavenge loop's front end — currently just a loot pool (`loot_table`) + a random flat map
(`MapGen`). Needs to become the system that makes a hulk a real place. **Depends on multi-level
(Foundation) — the tile format must be height-aware from the start, or it encodes flatness
forever.***

**The vision:** a HUGE map generated on load for a new seed — voidhulks house the remnants of
whole civilizations (Rome inside a spaceship). Scale is managed by two features:
- **Fog of war** — veils what the player hasn't seen; gates cell activation.
- **Cells** — a preconfigured enemy group, *placed just before becoming visible* and *activated*
  (instantiated into real units with turns) only once seen. Keeps a Rome-sized map from simulating
  thousands of units — the same "dormant until observed" principle as headless bouts.
- **The docked player ship is a room on the map** (blast-door-separated) — extraction happens there,
  and a scripted ship-boarding fight becomes "get back to your ship," reusing combat on one map.
  The ship-as-space decision paying off spatially.

**Persistence model — generated once, then a stateful evolving place (NOT re-rolled).** A hulk's
map *and* contents are generated one time from the seed; after that **nothing regenerates** — the
hulk only *changes* through causes: player actions (loot taken, holes cut, cargo jettisoned/dumped),
events, and faction behavior (enemies wander, settle, fight). A cleared room stays cleared; left loot
stays left; the too-big-to-haul fuel tank is still there because nothing rolled it away. This true
persistence is what makes the jettison rule, waste-traces, come-back-for-the-tank, and sellable maps
all cohere — they'd break under re-rolling.

**Jettison is a world rule: loose cargo finds its way to a hulk.** Anything jettisoned (waste or
otherwise) drifts into *a* hulk — you can't be sure which, but it's a real, persistent change to
*some* hulk you can later find (by chance, by retracing, or by a heat-origin sensor upgrade). This
one rule closes several loops: it explains where hulk contents partly come from, makes bad disposal
a *recoverable* mistake (go find it, clean it up), and justifies a scanner tier. Conservation of
matter — you can move the mess around, never make it truly gone except by cleaning it.

**Procedural-with-handmade-pieces**, built on a tile system:
- **Tiles connect by doors** — a door on a tile edge is a connection point; an adjacent tile with a
  matching door joins there; no adjacent tile → the door is removed (walled off). Self-describing
  adjacency, no overlaps, arbitrarily convoluted layouts. Proc-gen matches doors to doors.
- Proc-gen is strong for "just make maps"; handmade tiles give quality where it matters.

## Authoring tools (gate mission-gen quality)
- **Tile editor** — author a map tile (height-aware), save it for proc-gen assembly.
- **Map editor** — author/save a full map, run a **test bout** on it. Built on the tile format.
- **Main menu** — roll all in-game tools/utilities into one reachable place (bot builder, bout sim,
  map/tile editors). *Resource Editor excepted* (stays standalone). The wrapper — built last, once
  the tools exist.

## Moving heavy / multi-tile objects (sooner — the system without vehicles)
*The general answer to "how does mass move," forced by the 5000L tank: you rarely take the whole
thing, you decide how to reduce or extract it. Buildable once objects can span tiles (multi-level
Block 2). Vehicles are a later solution layered on top; this is the base.*

- **Two axes, checked separately.** **Heavy** needs *strength* — a strong enough unit, or enough
  total. **Bulky** needs *hands* — multiple units of any strength (moving a couch). Both → strong
  *and* several.
- **The team-lift check** is **average Str × count** (average, not sum, so a **weak link drags the
  lift down** — discourages throwing the whole squad at it, rewards a dedicated strong hauler), and
  **size caps how many can help** (a one-tile object fits maybe two lifters around it — you can't
  brute-force a small heavy thing with a crowd; you need *actual* strength).
- **Reduce ↔ whole is a spectrum, not three options.** Fully reduce (cut to scrap) → partially
  dismantle (split the tank from its mounts → now bulky-but-light, movable) → take whole (needs the
  good methods). The salvage tension: reducing is efficient, extracting whole is the greedy/skilled
  play.
- **The "I want it but lack the right tool" case is the interesting one** — you *can* take it,
  suboptimally. Introduces a **disassembly/assembly-speed** stat and a **mangle-chance on rushed
  disassembly** (the right tool = clean & fast; the wrong tool = slow, with a chance you break a
  piece you wanted). Reuses the mangle system.
- **Bad methods** (drag, personal winch, dollies) vs **good methods** (later: lifter shells,
  flatbeds, gantries — the vehicle layer).

## Vehicles (backlog — designed, built after multi-tile units + matrix-mobility)
**A vehicle is a shell** — parts, sockets, power, a possible matrix slot — shaped for hauling/driving
instead of fighting. Not a new pillar; content + a few capabilities over the shell/matrix/power
systems. The unifications:
- **Piloted / driven / follower = where the controlling matrix lives.** A lifter has its own matrix
  (piloted). A **seat is a socket a torso occupies** — a unit's matrix (in its torso) mounts the
  driver-seat socket = driven; a legless ally can still be stuck in a seat. The mulebot is a
  low-autonomy matrix (follower). All three are "a shell + where's the matrix" = the matrix-mobility
  system.
- **The vehicle's actions become the rider's actions** (action-provider model, tb07) — a bot in the
  driver seat both fires its own Shoot *and* the truck's Drive Forward. No new control system.
- **Wheeled movement needs discrete handling** — a multi-tile wheeled vehicle has turning radius /
  orientation / reverse, not walker-style occupy-adjacent. Its own movement mode. **A truck stuck in
  a hallway is the intended mistake-space** (multi-tile pathing, self-authored, recoverable).
- **Wrecks are pilotable** — a destroyed enemy combat-tank is a huge shell; scrap it, or put a matrix
  in it (matrix-mobility) and drive it.

## Support & remaining combat gaps
Mulebot / follower drones; hacking (Int-based, has a RAM cost already); weak points (poses + failure
modes + aimable joints exist — cheap); voidhulk stability (environmental hazard).

---

# META — the ship & between-missions layer
*Fully mapped this planning session. This is the foundation the economy/progression sit on; it's
one interlocking spine (travel → time → fuel → heat → storage), not a list of screens.*

## The ship is a SPACE, not a menu
Built on the tactical grid — you run your matrix-in-a-shell around it. Two payoffs: it *feels* like
your ship, and **the eventual "ship gets boarded" fight reuses the entire combat system** on a map
you already have. Standing in the airlock = "ready to depart" (commits the downtime).

## Time is "minutes," decoupled from combat and real time
- **Minutes = the duration of the next queued ship action.** "Go to station" hands you ~1200
  minutes; "move to the next docking port" ~60. You spend those minutes on tasks, then commit.
- **A `wait` task** (1 min, front or back of the queue) buys exact slack — so a 1201-minute task
  plan isn't blocked by a 1200-minute leg. Cleaner than a fixed budget.
- **Tasks are location-gated:** scanning a voidhulk needs the ship *at* the hulk, so that task is
  only available during the "sit near hulk" window. Different queued actions expose different tasks.
- **Matrix stats set task cost** — an Int matrix researches faster (fewer minutes for the same
  result). This is where attributes matter *outside* combat (Cha at merchants, etc.).

## Fuel + speed
- **Fuel drains slowly, always** (gentle — ~6000 min per unit idle), so scavenging for fuel is a
  real loop. Not punitive; a floor, not a timer.
- **Ship speed (slow / cruise / fast)** trades three things at once: fuel cost, downtime available,
  heat accrued. Slow = cheap, more downtime, less heat, but slower. A real "what does this leg need"
  decision, not "faster is better."

## Heat — a spendable threat currency, per faction (NOT reputation)
Heat is *"I've done enough that they've found me,"* not *"they like/dislike me."* Keep the hunted
energy.
- Heat **accumulates** from activity (esp. cheesy-profitable activity like waste-hauling).
- **Enemy factions SPEND heat to strike** — a **one-time severe hit that resets the heat**, not a
  ramping tax. So high heat is *baitable*: build a team to counter a faction, provoke the strike,
  crush it with hand-picked counters, and loot is delivered to your door.
- **Per-faction consequences differ by who you angered:** scavs hit you *mid-scavenge* on a hulk;
  space-cops (placeholder) **board you** (the tactical ship-defense fight — heat is *how* you get
  boarded outside story); settlers/merchants **won't buy and gouge you**.

## Quests decay, never fail
Time-sensitive content is authored as **states along a decay curve**, not pass/fail. The governor's
daughter: fast = catch them mid-capture; medium = they've fortified; slow = they've relocated to
base. Same objective, different state/difficulty/location. Speed choice has *narrative* consequences.
Build time-sensitive content this way from the start.

## Storage: you store THINGS, not resources
The backbone of the whole economy — and it's mostly *composition* of built systems (nested
containers tb04/05, mangle tb09, salvage_yield tb04, StatResolver).
- **Store physical things** (parts + substances) nested in containers, tracked by bulk/fill. No
  abstract "5 organic units" — you store the beans; their organic-ness is *drawn on demand*.
- **Things carry a resource CATEGORY + conversion rate.** Kerosene & diesel are both FUEL (diesel
  denser → better rate); iron ore is MINERAL (usable where minerals are needed, NOT where refined
  iron is). A system needing N category-units draws matching things at their rates.
- **Refinement (ore → ingot) is a separate real step;** category-use is instant. Substances are a
  new leaf type in the existing container tree — a container holds a substance OR a part.
- **Substances must always be in a container.** A tin of beans: the tin is a container (metal part,
  has salvage_yield), the beans are a substance inside it.
- **Consumption order:** non-mangling containers drain first (a loose bucket), *then* mangling ones
  open (crack a sealed tin) — so the intact/tradeable goods are preserved automatically. A quick
  popup, best substance pre-selected, names the substance, not the source.
- **Opening = a mangle** (sealed_tin → opened_tin, frees the substance). **Emptying transforms
  nothing** — an empty container is still a (poor) part-container; it never *becomes* a substance, it
  *yields* salvage when actively scrapped. Substances never exist without a container, inviolate.
- **Scrapping is always explicit** — never automatic — *except* a player-set **auto-scrap-by-type**
  policy (default off) so a hundred emptied bean tins isn't a chore. Hoarding empties for storage
  stays possible.
- **Too-big-to-field containers** (a 5000L tank) are still parts — practically stash-only, but they
  can appear in the world (on a machine, as a building-like field object). This **motivates voidhulk
  persistence concretely:** find a huge fuel tank you can't haul in one trip → flag it, come back.

## Rigs — the back slot's modular storage (a design pattern over sockets)
The back slot stays dumb (holds one part); its flexibility comes from **rig parts** — a part that
mounts on BACK and *provides several storage sockets of its own*. All complexity lives in the rig,
none in the slot. A rig has **typed slots** (e.g. two barrel-slots, `attaches_to: barrel`) and
**generic hooks** (`attaches_to: hangable` — a jug, bag, rope coil, anything hangable). So one back
slot carries a heterogeneous, independently-losable set: shoot the rig's jug subtree off and you
lose the jug + its kerosene (severed-joint rule), keep the backpack. A rig can also carry a back-armor
plate (armored rig = a rig with a plate socket). No new machinery — it's the socket + container
systems one nesting level deeper, applied to the back. The *decision* recorded here: back-inventory
flexibility comes from rig-parts, not from special back-slot behavior.

## Stash-management UX (the operations layer)
The inventory *model* is done; large nested stashes need *operations* to be human-usable. Gated by
nothing; sequences right after storage lands (build the clutter-generator, then the tools):
- multi-select; right-click one action → all selected; drag things between containers; auto-scrap
  policy; **fold identical entries into a stack (with count)**.
- **Stacking keys on FULL identity** — same part *and* same state (fill level, wounds, mangle). A
  sealed tin and an opened tin don't fold; a pristine and a mangled plate don't fold. Corollary:
  inventory mess is **always player-authored and explicable** — the system never silently makes an
  unfoldable duplicate, so any messiness has a story the player already knows.

## The rest of the meta layer (sits on the spine above)
Merchants & **contracts** (Cha-driven deals; **waste-haul/deposit jobs** — a merchant pays you to take physical garbage, which you must then dispose of. Disposal downside scales with **number of dump-sites, even within one hulk** — so you must *architect a dump*, not spread mess. Many small sites = minor nuisances (trash creatures, garbage-pickers, easy resolves); the severe stuff is reserved for real heat, not littering. Consolidation is the emergent optimum, not a forbidding rule. A **heat-origin sensor** upgrade lets you track your own traces to clean them. **Recycling is the
third disposal path** — a lossy transformation (fermenter part + minutes, may need ship upgrades):
~10 bags biowaste → 1L biodiesel (FUEL — feeds the ship, the loop closes on itself) + 4L fertilizer
(sells well) + 95L dirt (sells ok, or low-heat landfill). The three disposal paths tax *different*
currencies — jettison costs heat, dumping costs site-count, recycling costs time — so the right
choice depends on what the player is short on. Recycling can't make waste vanish, only downgrade it
to less-bad residue (conservation holds). A big contract (600 bags) self-selects for playstyle: only
a dedicated player parks the ship and works the fermenter across long downtime, via the minutes model
— opt-in and rewarded, never forced tedium. Recycling is the refinement loop (ore→ingot's cousin)
with **multiple outputs from one input**, which the refinement system must support); the **research
tree** (matrices research ship-side, Int-gated, defrags rampancy); **scanner tiers** & the
knowledge/sensor system (reveals tb20 internals — un-stubs the occlusion gate); **mission selection**
(scanners + bought/made maps + contracts point you somewhere); claims; the mission → credits →
upgrade loop; **captured-matrix value** (defrag a rampant boss matrix → friendly/valuable: copy a
player onto it for a boss-tier upgrade, quest delivery, or crew).

# INDEPENDENT TRACKS (gate nothing)
The balance pass (~13 flagged placeholder constants — tune against watched bouts, after melee/status
exist); cosmetics & clutter (part painting, tchotchkes, dyes, bag labels).

---

# LONG BACKLOG (not yet sequenced)
Hacking (Int-based, RAM cost exists); mapping gear + **sellable hulk maps**;
combat revives beyond the emergent model; matrix hotswap edge cases; loot **affixes**; muscle/bone
sub-parts; multiplayer; rampancy-as-active-pressure tuning; mental-hazard / psychic content
(Wis-resisted).

## Content taxonomies (listed in early notes, never filed — author as data when the systems land)
- **Hulk variants** (mission-gen content): settled hulk (claim to buy, safer), **dirthulk** (crashed
  planetside — worse shape, richer deep loot, planet hazards), **gashulk** (caught in a gas giant —
  rapidly abrading away, time-pressured), **organic hulk** (born-or-built creature-ship — gore halls,
  meat as a huge organic payload). Each is a mission-gen flavor + hazard set.
- **Tilesets** (mission-gen visual/hazard skins): **overgrown** (UV lights + leaks → jungle),
  **battleworn** (a fight happened here, bodies suspiciously absent), **pristine** (suspiciously
  move-in-ready). Skin + hazard modifiers over a generated layout.
- **Hazard set** (already in the hazard backlog, itemized for reference): radiation, decompression,
  defense grids, psychic incursion, evolved inhabitants, infestation, pirates, settlement.

## Small mechanical notes (mentioned once, not yet in any system)
- **Double crit** — the crit system's endgame: crit >100% chance rolls a second crit tier (e.g. 125%
  = always crit, 25% chance to *double* crit = bypass armor AND bonus damage). The single-crit
  bypass-or-bonus rule is built; the >100% double tier is the flagged extension.
- **Body-as-cover / bullet-catcher** — body-carry as inert cargo is built; the *tactical use*
  (holding a corpse as a shield to cover a retreat) is not. A carried body should project into the
  shot plane as cover for its carrier.
- **Disposable back items / back-armor as flanking counter** — the "armor your back or wear a
  disposable item on it" counter to flanking. Parts already mount on a BACK socket; this is authoring
  a disposable/sacrificial back item type + the flanking-counter framing (a Phase-P perk or a part).
