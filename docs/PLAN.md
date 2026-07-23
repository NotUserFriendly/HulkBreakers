# PLAN.md — Build Order

**Forward-only.** Sequences *unbuilt* work. Built work → `CHANGELOG.md`; reversals → `SUPERSEDED.md`;
defects → `BUGS.md`.

**Dependency is the only ordering driver.** An item sits where it does because of what it needs — not
because of how big it is, how interesting it is, or when it was written down. A one-line change and a
whole system are peers here: work is single-threaded, so size never affects what comes first.

**Everything is levelled.** No phases, no keystones, no topical sections — a flat ordered list of things
that could each be picked up next. Anything deferred, descoped, or spun off from a taskblock lands here
(CLAUDE.md rule 7). "Too small for PLAN" is what let work get dropped before.

**Buckets:**
- **NEXT** — capped at 3–5, ordered, nothing with an unmet dependency. **Exceeding the cap triggers a
  re-evaluation of the whole bucket, not a silent push of the bottom item.**
- **QUEUED** — real work, roughly ordered, no commitment on timing.
- **UNSCHEDULED** — the long tail. Ordered only where dependencies force it.
- **APPENDIX** — recorded findings. Reference, not work.

**Two invariants make the order self-checking.** A violation means the ordering is wrong, not that the
rule needs bending:
1. Nothing in NEXT has an unmet dependency.
2. Nothing in NEXT depends on anything in APPENDIX.

**Bugs are scheduled from `docs/BUGS.md`, not from here.** A taskblock may draw from either; PLAN is not
a claim about what the next taskblock contains.

---

## Standing rules

**1. Enums for engine states. Open `StringName` vocabularies for content.** Anything a designer might add
later must be addable **as data, without a code edit**. Engine states are enums; content (socket types,
tags, materials, perks, statuses, scatter rings — *N rings, never 3*) is open data.

**2. Verify view math by reading the real node back**, never re-deriving it in the test.

**3. Author everything as parts — including infrastructure, huge objects, and wreck-chassis.** If the
5000L tank, a combat-tank wreck, a flatbed, and hulk fixtures are all authored as normal parts (sockets,
mass, bulk, salvage, capabilities) from the start, then vehicles and movable objects later are just
*assembling existing parts* — no retrofit.

**4. Human-shaped is versatile; every departure costs you.** A robots-built-for-human-tasks world, so
human-shaped units fit human infrastructure (seats, doorways, tools) and weird-shaped ones don't. A
constraint that *generates* gameplay — a seat expects a torso, so a legless ally can still ride but a
mulebot can't sit in the driver's seat.

---

# NEXT

### 1. Multi-level maps — grid height and movement verbs
**Needs:** nothing. **Unblocks:** mission generation, authoring tools, moving heavy objects, vehicles.

The highest fan-out item in the plan. True-3D shot resolution shipped (tb23); this is the rest of it.

- **Discrete level for logic, true height for position.** Cells gain an integer level; a unit's actual Y
  is continuous. 22.5° ramps rise 0.5/tile → two ramps make one full level (a unit halfway up a one-tile
  ramp is at 0.25). Discrete height gates *decisions* — can I climb, is this fall lethal, what can I path
  to; true height drives *position and the shot plane*.
- **Vertical movement verbs** — hop-down and climb-up via leading-edge detection; ramps and stairs move
  occupants at true height; height-aware pathfinding.
- **Height needs no special cover or LoS rules** — it falls out of correct 3D projection. Higher → better
  sightline over cover → the dartboard sees more of the target. Skylined on an edge → nothing behind you →
  easier to hit. Emergent from geometry, not bolted-on bonuses. (A dedicated *height advantage* like
  throwing farther waits on a future arc'd-shot handler.)

*Do this before mission generation, or the tile format encodes flatness forever.*

### 2. Attributes
**Needs:** nothing. **Unblocks:** perks, and most content downstream of perks.

**The six attributes live on the MATRIX, not the shell.** A strong matrix outside a shell gains nothing;
inside, it makes weak bots serviceable and strong bots incredible — an attribute is *competence at using
the body's capability*, not the body's raw capability. The same shell performs differently under
different pilots. The matrix-is-the-real-unit premise made mechanical.

- **Start with the D&D six plus modifiers** (explicitly provisional names): **Str** (applying force,
  carry), **Dex** (reflexes — **personal_speed folds under here**, re-expressed), **Con** (durability,
  endurance), **Int** (logic, hacking), **Wis** (strength of mind — mental-hazard and rampancy
  resistance), **Cha** (face — merchant deals, social and contract outcomes, and with Wis, overwriting an
  enemy mind).
- **Re-express existing stats through attributes** — `personal_speed` becomes a Dex facet. This touches
  the resolution-speed system; it's a refactor, do it carefully.
- **Provisional naming** — some may merge or rename. Familiar names for velocity; treat them as
  placeholders, nothing load-bearing on the literal name.

**Acceptance:** six attributes and modifiers on the matrix; personal_speed reads from Dex with no
behaviour change; a stat resolves through `StatResolver` with the attribute as a provenance source; a
shell performs measurably differently under two different-attribute matrices.

### 3. Status effects and boosts
**Needs:** nothing. **Unblocks:** perks, therm conversion, wound thresholds.

**Burn, bleed, and tesla-charging-allies are the same shape** — a timed, stacking modifier through
`StatResolver`. Buff versus debuff is a sign. Build once.

- **Stack model** — accumulation, decimal stacks preserved, decay-below-half-vanishes, per-turn tick.
- **Consume the live hook** — `status_applied` already fires; make burn and bleed read it.
- **Boosts** — the buff direction, ally-applied.
- **Status → wound threshold** — closes tb20's dangling hook (burn → burnt_electronics).
- **Retire the docs/08 burn fiction.**

### 4. Diagnostics — the log becomes the instrument
**Needs:** nothing. **Unblocks:** every future perf or behaviour investigation.

*Extends `docs/09`.* Three separate bugs each survived multiple passes purely because CC cannot observe a
framerate or a decision. Fixing the instrument is worth more than fixing any one of them.

- **Crash-log unification.** The combat log is already structured `LogEvent`s over one stream with
  pluggable sinks and a `session_start` seed line — most of a crash log already. Grow it to capture engine
  and script errors too (a new `kind`, or an error sink on the same stream), so combat events and
  diagnostics share one filterable channel: conflated on purpose, mixed only when we want. **One real
  limit to design around, not paper over:** a *hard* engine crash may die before any GDScript sink
  flushes. Scope what's reachable (caught script errors, assertion failures, abort reasons) versus what
  needs an external wrapper, up front.
- **Deliberately excessive verbosity.** CC greps it cleanly and the in-game view folds it. Log lifecycle
  and view events: bot constructed, part attached, cutout drawn to (x, y), which overlay is active and
  when it turns off. Plus a **bout-build log in the order things actually happen** — placed N walls, N
  void tiles, N units, N cover pieces — recounted in build order, not summarised.
- **Pair "what was sent" with "what happened."** Log the command issued *and* its outcome (a remove-unit
  command was sent; the unit could not be removed, and why), so a dropped or rejected command is visible
  instead of a silent no-op. Mirrors the two-phase turn model, and directly counters the class of bug this
  project keeps producing — actions that silently fail.
- **A live FPS counter drawn on top of the log** — distinct from the logged `fps_dump` events, which exist
  for CC to grep. This one is a continuous readout for the supervisor. Keep it *over* the log, not in it:
  a per-frame FPS line would drown the log it's drawn on. Supervisor note: ~250ms refresh I can't see more
  resolution than that.
- **The log window becomes a window** — a title bar reading "Combat Log," a minimize button, vertical
  resize by dragging the bar. And **hand scrolling back to the camera at the ends**: scrolling while
  hovered scrolls the log, but at the top or bottom of the content it falls through to the camera instead
  of dead-stopping. Pairs with BR34.02 — a titled, resizable panel wants a real background, which answers
  that bug's "visible background versus click-through" question on its own.

### 5. Replace the hand-built full-mission test
**Needs:** nothing. **Unblocks:** trustworthy mission-level coverage.

`test_full_mission.gd` uses a hardcoded seed and its own in-test turn heuristics that were never rehomed
into production AI. Every real mechanics fix reshuffles its RNG timeline and it gets re-seeded by brute
force — five times per its own header. Worse, that seed churn was masking the real AI line-of-fire bug.

**Decided:** the hand-built harness goes, replaced by a thin `BoutSetup`/`DeepStrike`-based mission smoke
test — a bout runs start-to-extraction without erroring, asserted on outcomes rather than a frozen seed.

**Do NOT retire-to-green.** The mission-coverage gap stays *visible* until the replacement exists. Until
then a deliberately-failing placeholder holds the slot with an honest reason, replacing the current
confusing seed/turn-cap failure with a self-documenting one. The work is *writing the replacement*, not
deleting the old file.

---

# QUEUED

### Perks
**Needs:** Attributes, Status. **Unblocks:** most named content.

**THE CENTRAL CONSTRAINT — framework before perks:**
> **Every perk is data describing a modification, plugged into an existing seam — never bespoke code per
> perk.** If perks are each programmed differently, the system is a maintenance catastrophe.

- **The perk framework** — a perk `.tres` declares *what seam it binds and how*. The seams exist already:
  `StatResolver` mod-sources (including attributes), the speed-bonus hook, the reaction hook, the
  action-provider model, the AP-coaxing hook, rule-override hooks.
- **Categories, each a kind of *binding* rather than code:** stat modifiers; action grants (overwatch,
  Fan-the-Hammer); ordering (Quickdraw, Ghost Step, Sixth Sense); reactions (dive-prone, shield-turn);
  rule overrides (dual-weapon inverts `attaches_to`, player-advantage verbs, matrix-mobility perks).
- **The five classes are the acceptance test** — Gunslinger, Hotswapper, Hulk, Cutter, Demolitionist. If
  all five express as data bindings with **zero bespoke perk code**, the framework is right. A missing
  seam means add the seam, not the special case.
- **`Matrix.perks` finally read.**

**Named perks that stress the framework:**
- ***First One's Always Perfect*** — the first shot of a burst or activation ignores all accuracy
  modifiers and lands dead centre, then normal scatter resumes. The inverse of recoil; binds to the
  dartboard/accuracy seam. A clean data-binding, exactly the shape the framework must express.
- ***Nuclear Tuning*** — coaxes **1.5×** power out of a reactor assembly; but once reactor heat passes
  **70%**, the perk **inverts**, instead cutting heat output by **35%**. The best framework test in the
  list: a *conditional sign flip on its own effect*, keyed to a threshold on a live stat. If the data
  model can express "this bonus becomes a different bonus past a threshold" without bespoke code, it's
  right. *Also needs therms.*
- ***Bulk Up*** — an action, not a passive: spend a large chunk of power to **magnetically yank nearby
  scrap and loose parts onto itself**, cladding everything unclad and socketing a "Scrap Armor Plate"
  into every free armour socket. Stresses a different axis — a perk performing a *bulk assembly
  operation* through the normal attachment path (`BodyAssembler` + `DataValidator`), turning battlefield
  debris into armour. Needs the existing field-items model plus one new authored part.

**The see-the-future seam — a derived RNG sub-stream (design settled, nothing built).** Perks are meant to
let a unit break rules, including seeing ahead, so "sampling only at resolution" can't be absolute. The
real invariant is that **TACTICS must not advance the shared bout RNG stream** — if queuing and un-queuing
drew from `state.rng`, the same seed would yield a different battle depending on UI fiddling.
Preview-time sampling is therefore legal *provided it draws from a derived sub-stream*, seeded from the
bout seed plus stable identifiers, never from `state.rng`. Resolution replays the identical draw, so what
the perk showed **is** what happens.
**The trap:** key the sub-stream to something stable (unit + turn + weapon), *never* to queue position.
Keyed to queue index, a player un-queues and re-queues to reroll the prophecy. Stable keying means the
same turn always shows the same future — which is also what makes it read as foresight rather than a slot
machine.

### Power and therms — the reactor phase
**Needs:** Status, for burn → therm conversion. **Unblocks:** Nuclear Tuning, MK II Brutalizer, Hot
Headed, meltdown content.

*Power is partly built (the power→AP curve); therms are new. Fold them together — a reactor makes both
power and heat, so simulating one without the other leaves it half-modelled.*

**Therms = a general per-part resource** (literal heat; named *therms* to avoid colliding with the faction
**heat** system). Parts generate, transfer, mitigate, and dissipate therms, and thresholds trigger poses
and failures.

**Conduction = particle levelling, material-rated.** Every part, the ship, the air, and later each tile is
a **particle**: a therm counter plus a **max-transfer rate**. Therms flow hot→cold between connected
particles toward equilibrium, governed by the **lower** of the two transfer rates — so a reactor casing at
transfer 0.1 bleeds ~1 therm into the torso over ~10 turns even holding 100. **Insulation is just a low
transfer rate** — casing, cladding-insulation, and flesh all unify under one number; nothing is a *perfect*
insulator, so the reactor always eventually cooks its host. Resolved **per turn at start-of-turn**, which
keeps the sim cheap and usefully delays the consequence.

- **Sockets bypass cladding for part-to-part** — heat conducts structurally, but *venting to air* must
  pass through cladding first. So cladding is a **thermal liability**: a heavily-clad unit traps its own
  heat.
- **Two sinks:** the **floor** (unless the tile is on fire) and the **air** (unless **vacuum**, unless the
  air is mostly fire). Environmental hazards become *thermal* modifiers rather than separate systems:
  **vacuum removes air-cooling → robots overheat**, the robotic inversion of suffocation; a burning room
  removes cooling and adds therms. Ties decompression and fire into one interacting system.
- **Burn → therm conversion by material tier:** **fire-resistant** parts convert burn stacks to therms *as
  they expire* (delayed); **fireproof** parts convert burn directly to therms at 50% (immediate, lossy).
  Fireproofing isn't immunity, it's *transmutation* — you don't burn, you heat up, and can still cook your
  internals.
- **Therms go negative — cold is a real value, not a floor.** A dead hulk on a moon's dark side is a
  frigid tile (say −50 therms) that *pulls* heat out of anything touching it. Same levelling maths, no new
  mechanic. Therms are a **deliberate linear simplification** of a non-linear reality — legibility over
  physics; don't "fix" the linearity later.
- **Environment temperature favours different builds**, emergent, with zero new systems. A reactor unit in
  a frigid hulk is in its element — cold floor and air are huge sinks, so it dumps therms fast and its weak
  point barely exposes; the same unit in vacuum vents constantly and stays vulnerable. **Robots** care
  only about the hot end, wide tolerance. **Surrogates** suffer at *both* extremes — a wide but bounded
  band (engineered flesh: anti-coagulants for freeze and thaw, toughened collagen against hot metal).
  Baseline humans would be the narrow band surrogates were built to widen.
- **Life support = a surrogate-socket power→heat converter** (the heatsink inverted: spends power to *add*
  heat). A surrogate in the cold becomes a power **consumer**, so cold environments lower a fleshy unit's
  effective AP through the power surplus maths.
- **Fire-resistant parts accumulate therms instead of burning** — too hot and components fry. **Cook-off
  (VOLATILE) and MELTDOWN become therm-threshold events**, so two existing failure modes stop being
  special cases and fall out of the same counter.
- **Deep sim, shallow surface** — the transfer maths runs under the hood; the player just sees "that's
  glowing and sticking out, shoot it."

**Weak points are emergent from this, not a separate system.** The reactor is the defining example:
- Three real parts: **core**, **heatsink**, **insulated cladding**. The reactor is insulated — it does NOT
  leak therms into its sockets, so it can't cook the shell directly. Its **only** cooling path is the
  heatsink, which is *why* the heatsink is the single point of failure.
- **Heat loop per round:** reactor makes 10 power and 10 therms; heatsink pulls 10, mitigates 1 (net +9
  accumulating); sink over 20 → it **physically juts out of the shell** (a pose, so it now projects into
  the shot plane and is hittable), venting 13/round while extended; hits 0 → retracts.
- **The weak point is a moving part, not an occlusion toggle.** Nothing un-hides; the heatsink is always
  there, but only *reachable* when extended. A high-damage round can punch the cladding DT anytime; the
  vent just opens a window where a *weak* round reaches it too.
- **Usage-driven and self-balancing:** more reactor use → more therms → more venting. A unit burning all
  its AP vents predictably; a paced unit stays protected. Same mechanic, playstyle-differentiated, no
  special-casing.
- **Failure cascade:** heatsink extended → shot → **mangled** → stops pulling therms → reactor climbs
  unchecked → over 50 → **meltdown**. The attacker isn't hitting a designated weakspot, they're
  *sabotaging the cooling system*.

**General weakness pattern beyond the reactor:** any part can carry a weakness as an **exposure condition**
(usage-threshold, action-active, fixed-cycle) that moves an internal into reach. "Something opens up while
overwatching or bursting" is the same shape.

**Delayed-lethal consequences need a signal at trigger-time, not death-time.** The heatsink shot does
nothing visible for a turn or two, then meltdown — unreadable without feedback. A delayed-fatal state must
announce itself when *triggered*: a notification saying, calmly, "Nuclear Runaway Detected." Applies to any
delayed-lethal consequence — signal the cause, not just the death.

### Mission and voidhulk generation
**Needs:** Multi-level. **Unblocks:** hulk variants, tilesets, hazard sets.

*The scavenge loop's front end — currently just a loot pool and a random flat map.*

**The vision:** a huge map generated on load for a new seed — voidhulks house the remnants of whole
civilisations (Rome inside a spaceship). Scale is managed by two features:
- **Fog of war** — veils what the player hasn't seen; gates cell activation.
- **Cells** — a preconfigured enemy group, *placed just before becoming visible* and *activated* into real
  units only once seen. Keeps a Rome-sized map from simulating thousands of units — the same "dormant
  until observed" principle as headless bouts.
- **The docked player ship is a room on the map**, blast-door-separated. Extraction happens there, and a
  scripted boarding fight becomes "get back to your ship," reusing combat on one map.

**Persistence model — generated once, then a stateful evolving place, NOT re-rolled.** A hulk's map and
contents are generated one time from the seed; after that **nothing regenerates** — the hulk only *changes*
through causes: player actions (loot taken, holes cut, cargo dumped), events, and faction behaviour. A
cleared room stays cleared; the too-big-to-haul fuel tank is still there because nothing rolled it away.
This is what makes the jettison rule, waste-traces, come-back-for-the-tank, and sellable maps cohere —
they'd all break under re-rolling.

**Jettison is a world rule: loose cargo finds its way to a hulk.** Anything jettisoned drifts into *a* hulk
— you can't be sure which, but it's a real, persistent change to *some* hulk you can later find, by chance,
by retracing, or by a heat-origin sensor upgrade. One rule closes several loops: it explains where hulk
contents partly come from, makes bad disposal a *recoverable* mistake, and justifies a scanner tier.
Conservation of matter — you can move the mess around, never make it truly gone except by cleaning it.

**Procedural with handmade pieces**, built on a tile system:
- **Tiles connect by doors** — a door on a tile edge is a connection point; an adjacent tile with a matching
  door joins there; no adjacent tile means the door is removed. Self-describing adjacency, no overlaps,
  arbitrarily convoluted layouts.
- Proc-gen is strong for "just make maps"; handmade tiles give quality where it matters.

**Corridor geometry as pacing.** Diagonal tile-based structures *feel* faster to traverse than orthogonal
ones, even though 8-directional movement makes them mathematically equivalent. So corridor shape is a free
pacing lever: a long diagonal corridor reads as shorter than it is; orthogonal reads as longer,
deliberately slowing the sense of progress. Usable both ways — diagonal to compress the feel of distance,
orthogonal to build dread before an arrival. Costs nothing but a generation preference.

### Storage — you store THINGS, not resources
**Needs:** nothing. **Unblocks:** stash UX, the meta economy, substance content.

The backbone of the whole economy, and mostly *composition* of built systems (nested containers, mangle,
salvage_yield, `StatResolver`).

- **Store physical things** — parts and substances — nested in containers, tracked by bulk and fill. No
  abstract "5 organic units"; you store the beans, and their organic-ness is *drawn on demand*.
- **Things carry a resource CATEGORY plus a conversion rate.** Kerosene and diesel are both FUEL (diesel
  denser, better rate); iron ore is MINERAL, usable where minerals are needed, NOT where refined iron is. A
  system needing N category-units draws matching things at their rates.
- **Refinement (ore → ingot) is a separate real step;** category-use is instant. Substances are a new leaf
  type in the existing container tree — a container holds a substance OR a part.
- **Substances must always be in a container.** A tin of beans: the tin is a container (a metal part with
  salvage_yield), the beans are a substance inside it.
- **Consumption order:** non-mangling containers drain first (a loose bucket), *then* mangling ones open
  (crack a sealed tin) — so intact tradeable goods are preserved automatically.
- **Opening = a mangle** (sealed_tin → opened_tin, frees the substance). **Emptying transforms nothing** —
  an empty container is still a (poor) part-container; it never *becomes* a substance, it *yields* salvage
  when actively scrapped. Substances never exist without a container, inviolate.
- **Scrapping is always explicit** — never automatic — *except* a player-set **auto-scrap-by-type** policy
  (default off) so a hundred emptied bean tins isn't a chore. Hoarding empties stays possible.
- **Too-big-to-field containers** (a 5000L tank) are still parts — practically stash-only, but they can
  appear in the world. This **motivates voidhulk persistence concretely:** find a huge fuel tank you can't
  haul in one trip, flag it, come back.

**Containment is a compatibility property, not an exception to the rule.** The motivating scenario: you find
a barrel of {substance}, can't lift it, so you take 10 units into your backpack and walk it to the ship.
With **ammo** that reads as complete; with **oil** it's missing a step — you can't get oil into a backpack
bare-handed, you'd need an empty tin first. A backpack *is* a container, so loose rounds never violate the
inviolate rule. What differs is **which containers can directly hold which substances**: oil needs a
liquid-tight vessel, ammo sits in any general-purpose one. So the new data is a per-substance **containment
requirement** matched against a per-container **containment capability** — exactly the socket-type and
attach-tag pattern used elsewhere, addable as data with no code edit.
Consequences: "can I even pick this up" becomes a real interaction gate, which makes empty containers
genuinely valuable loot rather than salvage filler; and the existing kit design (chaingun, bullets,
magazines) stays correct — a magazine is a *better* ammo container, not a required one.

**Crates, lids, and a crowbar.** A crate is a container part with a **lid**; while lidded, the player
**cannot see what's inside**. Opening needs a crowbar, or presumably any sufficiently violent alternative.
Real information-hiding in the loot layer rather than a labelled box: you decide whether the crate is worth
the action economy before you know what it holds. Pairs with the existing "opening = a mangle" rule — a
pried lid could be a mangle transform, or a reversible state if crates are meant to be re-closable for
transport. That reversibility question is the one design fork.

**Corpse Mince** — a new substance. *"On densely populated planets and remote stations alike, your old
friend's remains make for a valuable resource. As fertilizer, a refining material, or, if you're desperate,
sustenance."* Slots into the existing category-and-rate model without new machinery, and gives the surrogate
economy a grim bottom end. Containment-wise it's clearly vessel-required — the first content test of the
property above.

### Matrix mobility
**Needs:** nothing for the core; advanced cases need Perks. **Unblocks:** vehicles, rampancy payoff.

*The matrix-is-the-real-unit premise made tactical. Mostly connects existing systems — welder, batteries,
power, assembly, sockets — plus one new capability: the matrix as a physical object.*

**Premise that sets the stakes:** player logic matrices are **quantum-linked copies** of a shipborne
intelligence matrix. Destroying a logic matrix costs a *resource*, never a *life*. So a physical, losable
matrix is high-stakes to protect but never unfair.

- **The matrix is a physical object** — targetable, carryable, installable. It **acts as a battery**
  (reserve plus output), so a bodiless shell limps on matrix power; burn it for a last stand or conserve it
  to linger. No special limp state; it's just low surplus.
- **Extract and install are separate actions** — a matrix can be caught mid-transfer, which is where
  stealing happens. A loose matrix is fragile; landing on an ally's tile means they catch it.
- **Ejection is socket-geometry-driven** — a back-mounted socket ejects in a ~30° rear arc. Pulling your own
  matrix without a perk **crumples the shell**.
- **Revive is emergent, not a mechanic** — repair the shell, power it, install a matrix. Three separate
  actions; doing all three "revives" someone. Matrix-rescue and shell-repair are fully independent.
- **Multi-slot shells** run a **willpower authority roll-off at round-top** — winner takes a full turn,
  loser none, tie splits AP. A slot can be **disabled** by someone working the shell, which strands a matrix
  and allows safe transport of captured enemies.
- **Perk-gated advanced cases:** Master (steal AP, willpower, minor stats), overwrite a living bot (Cha+Wis),
  live-transfer to an enemy matrix, clean self-extraction.

### Tester ergonomics — bout inheritance and scenario handoff
**Needs:** nothing.

Two small items that compound, because bouts are the testing surface for everything else.

- **Starting a bout from a bout inherits the previous bout's settings.** Launching a new bout from inside
  one currently starts from defaults; it should come up pre-loaded, so iterating is "tweak one thing and go"
  rather than re-entering the whole configuration. Most bout launches during a review session are the same
  scenario with one value changed.
- **Drag-and-drop scenario handoff** — the missing half of "CC authors, the supervisor watches." CC can
  describe a situation but can't put it on the supervisor's screen; the debug panel put forcing verbs in the
  supervisor's hands but requires clicking each one. Close the loop: **drag a scenario file onto the game
  window and it applies** — a file declaring units, tiles, cover, positions, loadouts, either silently or
  through a small confirm-and-tune dialog. The same authored presets become a transport format, not just a
  bout-menu entry, and CC gains a real way to hand over a reproduction. Every applied scenario is injection,
  so it carries `was_injected` and the usual determinism flagging — a dragged-in bout is not a clean seed
  replay.

### Startup opens a generated bout
**Needs:** nothing.

The game boots into whatever the default scene is, and that generator may be outmoded. Boot instead into a
freshly generated bout via the live bout builder — the same "starter battle folds into the bouts system"
consolidation as the full-mission-test replacement. Small, but it removes a stale entry point that can drift
out of sync with the real generation path.

### Retire the checkpoint machinery
**Needs:** nothing.

Checkpoint *discipline* was retired in the docs; every piece of machinery survives. `checkpoint.sh`,
`tools/checkpoints/checkpoint_{6,7}.gd`, and 636K of committed `out/checkpoints/` output that nothing
references and that describes a game 30-plus blocks out of date.

- **Delete the committed outputs and `checkpoint.sh`.** Git history keeps them; a committed, unreferenced,
  stale record that still looks documentary is the same failure as a stale CHANGELOG entry.
- **Keep `test/checkpoints/test_checkpoint_1–4.gd`** — they still run every suite as ordinary regression
  tests. Rename them out of the checkpoint frame so the name stops implying a retired ritual.
- **Keep the visual harness, repointed.** `tools/checkpoints/run_visual_checkpoint.sh` drives the real
  `BattleScene` with a GPU frame and captures rendered output. It fits the settled policy — CC authors the
  scenario, the supervisor runs it, the frame lands committed. Practical limit: CC reads images poorly, so
  this is a fallback for when a report genuinely can't carry the answer, not a primary channel.

### AI target selection and behaviour
**Needs:** nothing.

Four related gaps in what the AI *chooses* to do, all cheap given the data already exists.

- **AI fixates on the nearest enemy even when it's genuinely unshootable.** `UnitAI._nearest_living_enemy`
  always targets the closest living candidate, with no fallback to a different, actually-reachable target if
  the nearest has no line anywhere. Surfaced re-running the wall-impact measurement: one defender spawns in
  a nook confirmed to have no clean line from any reachable cell, adjacency included. The fallback correctly
  holds rather than firing blind — working as specified — but the squad then never tries either of the other
  two defenders, and the mission stalls for the rest of the turn cap. Re-running the original wall-impact
  measurement against that fixture found **zero impacts in 400 turns** — not a revised percentage, because
  every unit holds every turn. Not a LOF question: target *selection* needs to skip past a genuinely
  unreachable-by-shot enemy toward one that isn't.
- **A "Panic" fallback — the stuck-unit escape hatch, made player-visible.** A last-resort behaviour when a
  unit is stuck with no productive action, forcing it out rather than idling. The approach-fallback is the
  first narrow instance; the general version catches every stuck case. The second half is the interesting
  part: **label it visibly, so the player sees it fire.** Some escapes are necessarily cheats — a unit
  teleporting, extracting off an extraction tile, shutting down — and a player who sees them unlabelled
  learns the wrong rules. "Panic" says *something went wrong here, don't take this as normal.* An escape
  hatch nobody can see is indistinguishable from a bug, and the same signal doubles as a debugging tell.
  Pairs with intent/outcome logging — Panic is the "what happened" line for a unit that had no good "what
  was sent."
- **AI for damaged units — head for the nearest weapon.** A disarmed unit has little to do. Since the sim
  knows where everything is, handing it the location of the nearest weapon on the field — not necessarily a
  *functioning* one — gives it a purposeful action.
- **AI item behaviour per archetype, with a fallback.** Generalises the above: each archetype declares what
  item types it seeks and how it prioritises them (a brawler grabs a dropped melee part, a gunner a
  functioning ranged weapon, a support archetype a welder), plus a **fallback action** for when it holds no
  item it knows how to use, so an archetype never stalls. Sits on the archetype data that already drives
  bout setup.

### Step-out refinements
**Needs:** nothing.

- **Facing returns to its original heading, for free.** After a step-out resolves, facing should revert to
  whatever it was before, at no AP or MP cost — the same "the automation is in assembly, not in cost" logic
  that already makes both movement legs free. Stepping out is a mechanical consequence of taking the shot,
  not a decision about where to look, so it shouldn't silently leave the player facing somewhere they didn't
  choose and eat their next turn's reorientation.
- **Batching — coalesce same-square out-legs.** A unit queuing several attacks that each require stepping
  into the *same* square currently steps out and back per attack. Intended shape: one **step out → resolve
  all → step in**. A resolution-semantics change, not UI: it interacts with the docs/09 re-validation rule —
  if the batch's first shot invalidates a later one the unit is already stepped out, so "stop the instant
  the next thing is illegal" needs to define what happens to the shared return leg. Design the batch boundary
  before coding. If facing-restore is also built, it belongs on the single shared return leg.

### Authoring tools
**Needs:** Multi-level — the tile format must be height-aware.

- **Tile editor** — author a map tile, save it for proc-gen assembly.
- **Map editor** — author and save a full map, run a **test bout** on it. Built on the tile format.
- **Main menu** — roll all in-game tools into one reachable place (bot builder, bout sim, map and tile
  editors). *Resource Editor excepted* — it stays standalone. Built last, once the tools exist.

### Moving heavy and multi-tile objects
**Needs:** Multi-level. **Unblocks:** vehicles.

*The general answer to "how does mass move," forced by the 5000L tank: you rarely take the whole thing, you
decide how to reduce or extract it. Vehicles are a later solution layered on top; this is the base.*

- **Two axes, checked separately.** **Heavy** needs *strength* — a strong enough unit, or enough total.
  **Bulky** needs *hands* — multiple units of any strength. Both means strong *and* several.
- **The team-lift check is average Str × count** — average, not sum, so a **weak link drags the lift down**,
  discouraging throwing the whole squad at it and rewarding a dedicated hauler. **Size caps how many can
  help**: a one-tile object fits maybe two lifters, so you can't brute-force a small heavy thing with a crowd.
- **Reduce ↔ whole is a spectrum.** Fully reduce (cut to scrap) → partially dismantle (split the tank from
  its mounts, now bulky-but-light) → take whole (needs the good methods). Reducing is efficient; extracting
  whole is the greedy, skilled play.
- **The "I want it but lack the right tool" case is the interesting one** — you *can* take it, suboptimally.
  Introduces a **disassembly-speed** stat and a **mangle-chance on rushed disassembly**: the right tool is
  clean and fast, the wrong tool slow with a chance you break a piece you wanted.
- **Bad methods** (drag, personal winch, dollies) versus **good methods** (lifter shells, flatbeds, gantries
  — the vehicle layer).

### Rampancy
**Needs:** nothing hard; pays off best alongside matrix mobility.

*A mission-length pressure with counterplay, tied to systems that exist.*

- Logic matrices degrade toward **rampancy** slowly; intelligence matrices never do — the quantum link keeps
  them ship-side, always defragged.
- **Accelerated by conditions** — losing RAM battles, hostile hulk environments, age. A rampant enemy is
  rampant *for a readable reason*.
- **Counterplay** — defrag on ship, or a **field defragmenter** backpack item for long missions. Creates the
  "extract sooner versus push deeper" tension and gives RAM battles a consequence.
- **Captured enemy matrix → ship defrag → friendly or valuable.** A high-tier matrix you can copy a player
  onto for a boss-tier upgrade, deliver as a quest, or crew.

### Remaining melee pieces
**Needs:** nothing.

- **Protector playstyle** — positions between enemies and allies, preferring covered spots (a COVER_SEEKER
  variant scoring on *ally* protection). Not melee-gated; can land whenever.
- **Weapon distinctions — saw versus sword versus fist** (the `POWER`/`TRIGGER` capability split). A saw-hand
  can't add power to a sword swing.

---

# UNSCHEDULED

### The meta layer — the ship and between-missions spine
**Needs:** Storage for the economy pieces.

One interlocking spine (travel → time → fuel → heat → storage), not a list of screens.

- **The ship is a SPACE, not a menu.** Built on the tactical grid — you run your matrix-in-a-shell around it.
  Two payoffs: it *feels* like your ship, and the eventual "ship gets boarded" fight reuses the entire combat
  system on a map you already have. Standing in the airlock means "ready to depart."
- **Time is "minutes," decoupled from combat and real time.** Minutes are the duration of the next queued
  ship action — "go to station" hands you ~1200, "move to the next docking port" ~60. You spend them on
  tasks, then commit. A **`wait` task** (1 min, either end of the queue) buys exact slack. **Tasks are
  location-gated:** scanning a voidhulk needs the ship *at* the hulk. **Matrix stats set task cost** — an Int
  matrix researches faster, which is where attributes matter outside combat.
- **Fuel and speed.** Fuel drains slowly but always (~6000 min per unit idle), so scavenging for fuel is a
  real loop — a floor, not a timer. **Ship speed** (slow, cruise, fast) trades fuel cost, downtime available,
  and heat accrued all at once. A real "what does this leg need" decision, not "faster is better."
- **Heat — a spendable threat currency, per faction, NOT reputation.** Heat is *"I've done enough that
  they've found me."* It **accumulates** from activity, especially cheesy-profitable activity. **Enemy
  factions SPEND heat to strike** — a one-time severe hit that resets it, not a ramping tax. So high heat is
  *baitable*: build to counter a faction, provoke the strike, crush it, and the loot is delivered to your
  door. **Per-faction consequences differ:** scavs hit you mid-scavenge; space-cops **board you**; settlers
  and merchants won't buy, and gouge you.
  **Heat spent as *subversion*, not just a strike.** Instead of sending a force, a faction spends heat to
  **hack the bots already fighting you** and supercharge them mid-mission. A ladder, cheapest to worst:
  better AI behaviour → perks bolted onto its matrix → rigged to detonate → at the top, **the matrix fully
  overwritten by a boss mind**, so a mook you'd written off becomes an opponent with a complete perk loadout.
  Reuses planned systems rather than adding one — hacking, matrix overwrite, perks, detonation — and gives
  heat a *scary* expenditure that costs the faction nothing to transport: they don't have to reach you, only
  something already standing next to you.
- **Quests decay, never fail.** Time-sensitive content is authored as **states along a decay curve**. The
  governor's daughter: fast means catch them mid-capture; medium, they've fortified; slow, they've relocated
  to base. Same objective, different state, difficulty, and location. Build time-sensitive content this way
  from the start.
- **Rigs — the back slot's modular storage.** The back slot stays dumb (holds one part); flexibility comes
  from **rig parts** that mount on BACK and provide storage sockets of their own. A rig has **typed slots**
  and **generic hooks** (`attaches_to: hangable`), so one back slot carries a heterogeneous,
  independently-losable set: shoot the rig's jug subtree off and you lose the jug plus its kerosene, and keep
  the backpack. No new machinery — the socket and container systems one nesting level deeper.
- **Stash-management UX.** The inventory *model* is done; large nested stashes need *operations*:
  multi-select, right-click one action applying to all selected, drag between containers, auto-scrap policy,
  and **fold identical entries into a stack**. **Stacking keys on FULL identity** — same part *and* same
  state (fill, wounds, mangle). A sealed tin and an opened tin don't fold. Corollary: inventory mess is
  **always player-authored and explicable**.
- **The rest.** Merchants and **contracts** — Cha-driven deals, plus **waste-haul jobs** where a merchant
  pays you to take physical garbage you must then dispose of. Disposal downside scales with **number of
  dump-sites, even within one hulk**, so you must *architect a dump* rather than spread mess. Many small
  sites are minor nuisances — trash creatures, garbage-pickers, easy resolves — and the severe stuff is
  reserved for real heat, not littering. Consolidation is the emergent optimum, not a forbidding rule; a
  **heat-origin sensor** upgrade lets you track your own traces to clean them. **Recycling is
  the third disposal path** — a lossy transformation via a fermenter part and minutes: ~10 bags biowaste → 1L
  biodiesel (FUEL, so the loop closes on itself) + 4L fertilizer + 95L dirt. The three paths tax *different*
  currencies — jettison costs heat, dumping costs site-count, recycling costs time — so the right choice
  depends on what you're short of. Recycling can't make waste vanish, only downgrade it. It's the refinement
  loop's cousin, with **multiple outputs from one input**, which the refinement system must support. Plus the
  **research tree**; **scanner tiers** and the knowledge system (reveals internals, un-stubbing the occlusion
  gate); **mission selection**; claims; the mission → credits → upgrade loop; **captured-matrix value**.

### Vehicles
**Needs:** Moving heavy objects, Matrix mobility.

**A vehicle is a shell** — parts, sockets, power, a possible matrix slot — shaped for hauling and driving
instead of fighting. Not a new pillar; content plus a few capabilities over existing systems.

- **Piloted / driven / follower = where the controlling matrix lives.** A lifter has its own matrix. A **seat
  is a socket a torso occupies**, so a unit's matrix mounts the driver-seat socket. The mulebot is a
  low-autonomy matrix. All three are "a shell plus where's the matrix."
- **The vehicle's actions become the rider's actions** (the action-provider model) — a bot in the driver seat
  fires its own Shoot *and* the truck's Drive Forward. No new control system.
- **Wheeled movement needs discrete handling** — turning radius, orientation, reverse, not walker-style
  occupy-adjacent. **A truck stuck in a hallway is the intended mistake-space.**
- **Wrecks are pilotable** — a destroyed enemy combat-tank is a huge shell; scrap it, or put a matrix in it
  and drive it.

**Open structural question — tiles as anchor-sockets** (resolve when multi-tile objects are concrete; don't
build until then). Unify object-placement with part-attachment: a tile *offers an anchor-socket*; a placeable
object has "goes on a tile" joints, so a 2×2 object has 4. Placement requires **all** joints simultaneously
neighbour a compatible anchor-socket — which is how arbitrarily large objects are kept off small vehicles.
**Direction is fixed to prevent accidental anchoring:** the world is a pure *anchor* (receives, never
attaches); objects attach *downward* only; a vehicle bed is both. New machinery: multi-socket
*simultaneous-match* placement, since sockets are one-to-one today.

### Player-facing LOS/LOF conflation
**Needs:** eyes on the targeting UX first.

tb33 fixed the AI's confusion of "can see" with "can hit," but the player's own attack legality still gates on
`LoS.has_los` rather than the LOF predicate. A different problem from the AI's silent 81%-into-walls case,
because the player sees both the dartboard and the wall and can choose to fire anyway. Swapping it needs a UX
decision first — does the dartboard say "no shot" before the player commits AP? — not a mechanical copy of the
AI fix.

### Melee against non-unit PART targets
**Needs:** a reach-measurement design call.

`PartPicker`/`HitKind.PART` covers **ranged** weapons only; every motivating example (finish a downed bot,
destroy cover, hole a wall) is naturally ranged. Melee was deliberately left untouched: `is_legal()` calls
`MeleeReach.in_reach(...)`, which needs a real target *Unit* body to measure against. Extending reach to a
bare Part is its own question — does reach measure against the part's own box, or the whole blocker assembly's
AABB? Melee correctly rejects a PART target today; this is the follow-up to make it possible, if wanted.

### AI-produced dartboards and an aim beat
**Needs:** nothing mechanical; it's playback and timing work.

Only the player's shot ever draws a dartboard — an AI attack resolves straight from `UnitAI`'s decision with
no on-screen wind-up. `ShotScatter.for_shot` is now the one place range→radius truth lives, so it's a
ready-made primitive to drive an enemy-side draw. The real work is *when* the beat plays, how long it holds,
and how it interacts with other AI units resolving in the same batch.

### Wide scatter passing through a wall seam
**Needs:** a design call among three options.

`ShotPlane.build` projects each wall cell as its own independent rect; adjacent cells' projections aren't
guaranteed to tile edge-to-edge from an arbitrary shooter angle, so a dartboard point far enough off-centre —
a late pull of a long burst, recoil-widened, at range, reproduced at 56/200 empties at a lateral offset of ~8
— threads a real gap in an otherwise enclosed room. There's also **no modelled floor Region anywhere**, so "or
the floor" has nothing to resolve against. Three candidates: merge contiguous same-material blocker cells into
one projected rect at the source; cap dartboard scatter radius at a bound guaranteeing plane coverage (a real
balance number); or add a genuine floor Region. A design call waiting to be made, not a code fix waiting to be
written.

### AI repair
**Needs:** nothing in the plumbing.

`ActionCatalog`-driven repair is already available to the player, and the catalog-derived consideration
scaffold would surface it to the AI for free — but no when-to-repair logic exists. Enemy self-repair is a
design choice deferred, not a gap.

### Support gaps
Mulebot and follower drones; hacking (Int-based, RAM cost already exists); weak points (poses, failure modes,
and aimable joints all exist — cheap); voidhulk stability as an environmental hazard.

### Independent tracks
**Needs:** nothing; gate nothing.

The balance pass — roughly 13 flagged placeholder constants, tuned against watched bouts once melee and status
exist. Cosmetics and clutter: part painting, tchotchkes, dyes, bag labels.

### Long backlog
Mapping gear and **sellable hulk maps**; combat revives beyond the emergent model; matrix hotswap edge cases;
loot **affixes**; muscle and bone sub-parts; multiplayer; rampancy-as-active-pressure tuning; mental-hazard and
psychic content (Wis-resisted).

### Content to author when its system lands
**Needs:** the named parent system in each case.

**Hulk variants** (mission-gen): settled hulk (claim to buy, safer); **dirthulk** (crashed planetside — worse
shape, richer deep loot, planet hazards); **gashulk** (caught in a gas giant — rapidly abrading,
time-pressured); **organic hulk** (born-or-built creature-ship — gore halls, meat as a huge organic payload).

**Tilesets** (mission-gen skins): **overgrown** (UV lights and leaks make a jungle); **battleworn** (a fight
happened here, bodies suspiciously absent); **pristine** (suspiciously move-in-ready).

**Hazard set:** radiation, decompression, defense grids, psychic incursion, evolved inhabitants, infestation,
pirates, settlement.

**Named content:**
- **MK II Brutalizer** (enemy unit) — *"They never made a mark three, this one kept killing the prototypes."*
  Big, fast, heavily armoured, giant blades for forearms; slightly larger torso and longer legs but **stays
  single-tile**. **Dual high-power reactors** — hit a heatsink at the right time and an overheat pops it.
  *Needs* therms.
- **"Hot Headed"** (perk, psychotic logic matrix) — every unit of therms on the shell boosts Dexterity by 1%.
  *Needs* attributes, therms, perks.
- **Suppression Fuse** (part) — breaks itself on reactor-assembly damage; on break the unit loses
  friend-or-foe ID and gains **Reckless Strike**: double damage, but every hit deals 25% of damage dealt back
  to *the part above the used weapon in the tree* — the Brutalizer punches until its own arms fall off.
  *Needs* status and perks; damaging the parent reuses existing joint traversal.
- **Spear cluster** — a **spear** that throws cleanly *and* works in melee; a craftable backslot **Spear
  Quiver** (holds only spears, limited by **bulk not weight** — a count without new machinery; *"Darius, you
  have a problem. —One NufTek executive to another"*); a **spear launcher**; and a perk **"Pinning Shot"**
  that pins an enemy to a surface behind them, pin-distance strength-affected. *Needs* thrown-weapon support,
  which doesn't exist yet, plus perks.

### Small mechanical notes
- **Double crit** — crit above 100% rolls a second tier (125% = always crit, 25% chance to *double* crit:
  bypass armour AND bonus damage). The single-crit rule is built; the >100% tier is the extension.
- **Body-as-cover / bullet-catcher** — body-carry as inert cargo is built; the *tactical* use, holding a corpse
  as a shield to cover a retreat, is not. A carried body should project into the shot plane as cover for its
  carrier.
- **Disposable back items / back-armour as flanking counter** — parts already mount on a BACK socket; this is
  authoring a sacrificial back item plus the flanking-counter framing.
- **"Control system hacked" presentation.** When a player's shell is hacked and the hacker takes a turn with
  it, don't render it as a stat change — render it as *the player losing control of their own interface*:
  actions highlight right before they're cast, clicks do nothing, even a simulated cursor moving on its own.
  Not "your shell was hacked" but "your entire control system was hacked." A presentation treatment for
  hacking and mind-overwrite when they land, not new mechanics — it reads the existing action queue and drives
  the existing overlay in a scripted, locked-out mode.
- **Cover material split for visual reading.** The temporary cover models are all the same gray, making cover
  types hard to tell apart. Since colour is material-derived, split the authoring rather than the models: keep
  `sheet_steel` at the current gray and add `heavy_steel` at a darker gray, **identical stats**. Purely
  legibility, no balance change.
- **Mangle and wreck states for cover and walls.** Walls are destructible cover parts and a destroyed one
  clears to fully passable. The mangle machinery exists (`failure_mode = MANGLE`, `is_mangled`, `mangles_into`)
  but is never authored onto cover. Authoring it turns a destroyed wall or crate into rubble:
  passable-but-higher-cost and still low cover. Data authoring plus a small `move_cost` branch.

---

# APPENDIX — recorded findings

*Not work. Investigations and structural notes that inform the items above.*

### `BodyProjector` has no modelled top or bottom faces
A shot viewed exactly along a tilted part's own local depth axis can still find a degenerate,
near-zero-extent silhouette — a real, pre-existing gap in the 4-face body model.

### Two parallel shot-geometry systems, never unified
The codebase carries two genuinely separate geometry paths: the real 3D muzzle-to-target ray
(`UnitGeometry.muzzle_point` → `AimPlaneGeometry.ray_from_muzzle` → `ShotPlane.resolve_ray`), used only by the
player's aiming reticle and Overwatch's pre-check; and the flat 2D system that actually deals damage
(`AttackAction`/`BurstAction` → `ShotPlane.build(origin: Vector2, …)` + `Dartboard.sample()` →
`DamageResolver.resolve_shot`), whose origin carries no height. Unifying them was ruled out of scope as a
larger change, and the two don't currently disagree in a way players notice — but **the next system needing a
real shared height model (melee reach, multi-level maps) will hit this duality again.**

### The inter-turn FPS hitch — three measured suspects
Headless probes timing real logic and view classes directly found three concrete, additive costs:
1. The combat-log UI sink's full `label.text` reassignment on every event — ~175–180µs per call at a 200-line
   scrollback, and a real 3v3 bout averages 9.9 events per turn (peak 29), so a heavy turn pays ~5ms just
   relaying text nobody scrolled to. `HierarchicalUiSink` inherited the identical pattern, so this is still
   live. *Recommendation:* incremental `append_text` for the new line, plus a different line-cap strategy than
   trim-every-line.
2. `HitVolumeView.refresh()` rebuilds every mesh and material from scratch for the acting unit on every turn
   (~550–600µs on a 27-part unit), even when nothing about its geometry changed. *Recommendation:* skip the
   rebuild when the turn's only events were `turn_start`/`turn_end`/`faced`.
3. Turn-start power recompute re-walks the same unchanged part graph 5–6 times per `_start_turn` (uncached
   `all_parts()`/`operable_parts()`) — smaller (~175µs) but pure waste. *Recommendation:* compute
   `operable_parts()` once and thread it through.

Initiative re-sort was measured and **ruled out** (~40µs per turn across a 12-unit roster).
