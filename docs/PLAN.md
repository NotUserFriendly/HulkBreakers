# PLAN.md — Build Order

**Forward-only.** Sequences *unbuilt* work. Built work → `CHANGELOG.md`; reversals → `SUPERSEDED.md`;
defects → `BUGS.md`.

**Dependency is the only ordering driver.** An item sits where it does because of what it needs — not
because of how big it is, how interesting it is, or when it was written down. A one-line change and a
whole system are peers here: work is single-threaded, so size never affects what comes first.

**An item is roughly one taskblock.** Loosely — a block can be large because everything in it is
related, or small because it is a standalone content add. The rule guards granularity in both
directions: an item that would take three blocks is really three items with its dependencies hidden
inside it, and six items that would all land in one block are one item pretending to be a sequence.
When scope changes, resize the item rather than letting it drift. This is about *granularity*, not
ordering — size still never affects what comes first.

**Everything is levelled.** No phases, no keystones, no topical sections — a flat ordered list of things
that could each be picked up next. Anything deferred, descoped, or spun off from a taskblock lands here
(CLAUDE.md rule 7). "Too small for PLAN" is what let work get dropped before.

**The boundary with `docs/99`.** That file holds what is *unspecified and unqueued* — lore, character
notes, ideas without a shape yet. **If a thing is specified, it belongs here; if it is queued here, it
must be specified. Nothing lives in both.** A note that grows a mechanism graduates out of 99 into this
file; an item here that turns out to be a vague wish belongs back in 99. Two homes for one idea is two
places for it to go stale, and the one nobody edits is the one that gets read.

**Buckets:**
- **NEXT** — capped at 3–5, ordered, nothing with an unmet dependency. **Exceeding the cap triggers a
  re-evaluation of the whole bucket, not a silent push of the bottom item.**
- **QUEUED** — everything else that is work, ordered so a dependency appears before the thing needing it.
  No commitment on timing.

*There is deliberately no third work bucket.* "Queued, but further off" isn't a real distinction — an item
that can't be picked up yet says so on its own **Needs:** line, and a bucket repeating that is a second
place for the same fact to live, and therefore a second place for it to go stale.

**One invariant makes the order self-checking:** nothing in NEXT has an unmet dependency. A violation
means the ordering is wrong, not that the rule needs bending.

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

**5. Everything follows turn order.** Units act one at a time, in initiative order, and nothing changes
that — not batching, not parallelism, not any optimization. A batch is an **amortization** device: the
leader's expensive work is computed once and reused by followers who each still take their own turn in
sequence. It is never a device for resolving several units together, and "these units could be decided
at the same time" is not a licence to act them at the same time. A design that saves time by acting on
units concurrently or out of order is wrong regardless of how much time it saves. Parallelism, if it
ever arrives, applies to **pure computation** (visibility fields, reachability against a snapshot) whose
results are then consumed in turn order — never to the acting itself.

---

# NEXT

### 1. Attributes
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

### 2. Author the intelligence tiers onto units
**Needs:** the tier table, which landed as taskblock-46. **Unblocks:** intelligence reading as
character rather than as difficulty; any completion measurement that includes a tier other than Trained.

`Unit.intelligence_tier` defaults to `TRAINED` and **nothing sets it** — no preset, no matrix, no roster
entry. So the Mindless, Grunt and Elite rows of `docs/11`'s table, the memory and blackboard gates, and
the whole Elite lookahead are reachable from tests and by hand only. Every completion rate ever measured
on this game has been an all-Trained rate.

- **Author it where a unit is authored** — `BotPreset`, so a generated bout has a spread of tiers rather
  than one.
- **Then re-measure completion per tier.** The current number describes one row of a four-row table.
- **Tier should derive from Attributes** by the time this lands, rather than staying authored — which is
  why this sits behind item 1 rather than in front of it.

**Acceptance:** a generated bout contains units of at least three tiers; the completion sample reports a
rate per tier; a Mindless unit and an Elite unit on the same seed visibly do different things in the
combat log.

### 3. Multi-level: AI climb/hop-down and interruptible vertical movement
**Needs:** taskblock-37 Passes A–D (landed — `ClimbAction`/`HopDownAction` exist, capability-gated
and cost-correct on their own). **Unblocks:** trusting any AI completion measurement — a unit that
walks into ground it cannot leave is out of the mission while still alive and still taking turns,
which is indistinguishable from the planner failing.

**Promoted from QUEUED to NEXT by CC, on `BR46.02`'s measurement rather than on judgement**: 16 of 40
generated maps at the real bout size contain one-way ground, worst seed 216 cells. It was filed as "a
follow-on refinement, not a dependency of anything else" and that is no longer true — reorder if you
disagree, but the old placement was made before anyone had counted.

Two gaps flagged, not silently dropped, while building `ClimbAction`/`HopDownAction`:
- **No AI path ever queues either action.** The planner still only ever moves via ordinary `MoveAction`
  — a climb-capable unit (once any part ever authors the `CLIMBER` tag) has no way to actually climb
  in a real bout today.
**BR46.02 — 16 of 40 generated maps contain ground a unit can walk into and never leave.** Descent is
free, ascent is `CLIMBER`-gated, and nothing carries the tag. A symmetric connectivity check reports
these maps as fine (spawn zones mutually reachable on 60 of 60 seeds); the defect only appears under
*asymmetric* reachability. Three directions, and the map-generator half is **low priority**:

- **Ramps where they are missing** is the cheap generator fix — any region whose only exits are
  descents gets a ramp — and it should ride along with other map-gen work rather than justifying a
  block.
- **Prefer access routes: penalise ungated descent, exempt ramps.** The cheapest fix and probably the
  right one. Weight a candidate cell *slightly* worse when reaching it means dropping a level, and do
  **not** apply that penalty when the descent is via a ramp. Units then route through ramps by
  preference without any rule naming ramps, and a ramp is two-way — so a unit that takes one can come
  back. **Slightly is doing real work in that sentence:** a hop-down to reach an otherwise unreachable
  target must still win when the reason is good enough, so this is a thumb on the scale, not a
  prohibition. It is a consideration weight, which means it is data.
- **A short-term behavioural mitigation, worth more than it sounds:** a unit that finds itself confined
  escalates to an **agitated roam** or **pace** — visibly restless rather than idle — and after a few
  turns of no progress, **shuts down**. That converts a unit silently absent from the mission into a
  legible outcome the player can see and the log can record. It does not fix the terrain, and it should
  not be mistaken for a fix; it stops a `TERMINATED` bout from being indistinguishable from a hang.
- **Authoring a `CLIMBER` part** is the feature, below.

- **No part anywhere authors `CLIMBER`, so nothing that exists can climb out of anything.**
  `Shell.can_climb()` reads the tag (`shell.gd:105`) and no `.tres` carries it. A **content gap, not a
  pathfinding bug** — the pathfinder correctly reports that a unit which hopped down a ledge cannot get
  back up, and BR40.04 measured the consequence: a unit spawned in a sunk cell has exactly one reachable
  cell. Authoring one `CLIMBER` part closes a whole class of stranding in one file.
  **`BR46.02` measured the wider consequence and it is much bigger than the spawn case:** 16 of 40
  generated maps at the real bout size contain ground a unit can walk INTO and never leave — worst
  seed, 216 such cells. Spawn zones are mutually reachable on 60 of 60 seeds, so a symmetric
  connectivity check reports these maps as fine; the defect only shows under asymmetric reachability —
  flood out from a spawn, then flood back from each cell reached and ask whether the spawn is still in
  the set.
- **Until it exists, the planner must treat a hop-down as one-way.** A unit that drops off a ledge to
  reach something strands itself for the rest of the bout. "Can I get back?" belongs in the decision
  rather than being discovered afterwards.
- **Neither action integrates with `MoveAction`'s own mid-move overwatch-trigger hook.** An ordinary
  move can be interrupted mid-flight; a climb or hop-down currently can't be, which is inconsistent
  with "every real exposure the same" once a raised area is common enough to matter tactically.

# QUEUED

### Replay a handle on demand, and decide the checkpoints' future
**Needs:** taskblock-48 Pass B2 (the replay panel and `ReplayHandle`). **Unblocks:** retiring a third
renderer instead of keeping it alive by inertia.

taskblock-48 landed the surface: the run panel launches any rung, tails it live, and replays the first
few failures that have a visual form as real playing bouts. What it will not do is show you something
**nothing has failed about** — a replay is offered off a failure, so the map-generation sweeps are only
watchable when they break.

- **Replay a handle without a failure.** A list of declared handles with a "show me" button. Small
  addition to the panel, not a new mechanism, and it is the missing piece for everything below.
- **Then decide about `checkpoint_8`/`checkpoint_9`.** A checkpoint is "a visual test whose assertion is
  a human", which is what a replayed handle already is — and `checkpoint_9` drives `load_battle` from a
  `GridFixture`, the same path `ReplayHandle` uses. Once handles are viewable on demand the checkpoints
  are doing nothing the panel cannot, and keeping a third renderer compiling has a cost the parse guard
  only partly hides.
- **Declare handles more widely.** Three files have them. The determinism checks and the remaining
  spatial sweeps are the obvious next ones; a handle is a few lines and self-declaring.
- **Watched and headless must keep agreeing.** That equivalence is the foundation — if a watched seed and
  its headless counterpart ever disagree, every number the sampler has produced is suspect. Asserted
  once; it should stay asserted as this grows.

### The scripted bout, and why 133 files build state by hand
**Needs:** nothing. **Unblocks:** most of the remaining suite cost, and combat tests that exercise the
real path instead of an approximation of it.

**133 test files construct state directly** through `CombatState.new` or `GridFixture` rather than
playing a bout. Some of that is correct and some of it is a workaround, and nobody has drawn the line —
*"they have always been that way"* is not a reason.

**A scripted bout removes the thing they were avoiding.** Preset seed, every action predetermined, no
planner in the loop. That gives a combat or movement test the real resolution path — two-phase turns,
the action queue, the log — without the AI as a failure point. The precedent is in the tree:
`test_work_counters.gd` drives a turn by hand through `CombatState.advance_turn` and asserts that a
scripted turn counts while building no bout, and taskblock-47 Pass E retargeted the tb38 flat-bout guard
from a planner-driven bout to a scripted queue with no loss of coverage.

**Two corpora, for two different questions:**
- **Sampled** — the AI's behaviour *is* the subject. Random seeds, real planning, `test_full_mission`.
- **Scripted** — everything else. One preset playthrough, predetermined actions, many tests asserting
  against it.

**The audit is the valuable half, and it has three outcomes per file**, not two:
- **Hand-built is right.** A test of a pure function over a grid and two positions needs no bout, and
  forcing one on it would be slower and less focused. Leave it and say so.
- **Hand-built was avoiding the AI.** Move it onto the scripted bout — more realistic, and it stops
  every file re-authoring its own setup.
- **Hand-built is quietly wrong** — the fixture has drifted from what the game actually produces, and
  the test passes against a board that could not occur. This is the outcome worth finding.

### The review layer earns its keep
**Needs:** taskblock-48 Pass B2 (replay of failures). **Unblocks:** the supervisor being able to spot
anomalies at all.

The replay currently shows **only failures**, and an anomaly is not identifiable without a reference for
normal. That is the likeliest reason the human-review layer has not yet paid off — it has been showing
exceptions with nothing to compare them against.

- **Queue one representative success per test, not every success.** A passing test contributes one
  arbitrary replay; a failing one contributes its failure. The queue then teaches what right looks like
  in the same sitting as what wrong looks like. Cap it — a representative sample, with an option to sit
  through everything.
- **A chime when the run finishes.** The window is watched intermittently by definition; a run that ends
  silently wastes the gap.
- **Order tests by observed failure frequency.** Most-frequently-failing first, so a red suite goes red
  early instead of at minute nine. Needs a small persisted history of which tests failed how often —
  new data, and the only genuinely new machinery in this item.
- **A failure must not stall the queue.** GUT already runs past a failing test; the gap is on CC's side,
  where a failure at minute two is not actionable until the run ends. Surface failures as they land so
  the fix can start while the rest continues.

**A caution on reordering:** a suite whose order depends on recorded history is a suite whose order is
not reproducible across machines or checkouts. Keep the *ordering* advisory and the *set* fixed — the
same tests always run, only the sequence adapts — or a green run stops meaning the same thing twice.

### Player view and sim view — render a snapshot, stay responsive
**Needs:** a resumable planner (*AI v2, part two*) for the responsiveness half; nothing for the
snapshot half. **Unblocks:** the hitch stops being a freeze even where it is still slow; safe
threading later, if it is ever wanted.

**The strategy is to stop hiding the wait and start making it navigable.** A player who can pan, click,
inspect a unit, and read a panel while a label says *"Unit 2 is thinking…"* is playing a game that is
working. A player staring at a frozen frame is playing a game that has crashed. Those can be the same
number of milliseconds.

- **The view renders a snapshot**, holding state as of the last resolved action while the sim works on
  its own copy; it swaps and animates when planning completes. `refresh_unit_views(touched_ids)` is
  already the explicit sync point and `dup()` already exists for previews, so the seams are present.
  This buys *consistency* — the view can never observe a half-mutated state — and it is what would make
  off-thread work safe later, since a view reading an immutable snapshot cannot race a sim mutating its
  own copy.
- **Responsiveness is a separate problem and needs the planner to yield.** A snapshot does not help if
  the main thread is the busy one; panning still needs that thread to process input and draw. This is
  why part two's resumability constraint is not optional.
- **Name the unit in the indicator: "Unit 2 is thinking…", not "Thinking…".** Once named enemies exist,
  the difference between a mook's turn and a boss's turn becomes legible as *character* rather than as
  lag — the intelligence tiers make a smarter unit genuinely think longer, and the label turns that
  from a defect into a tell. Costs nothing to do now and cannot be retrofitted into a habit later.
- **Time-slice only after the work is small.** Slicing is a smoothness technique, not a speed one:
  applied to work that is too large it converts a freeze into a long responsive wait, which reads as
  the game answering input while nothing happens. Make it fast first, slice the remainder.

**This raises the stakes on the stuck-unit escape hatch.** A visible "thinking" state that never ends is
worse than a freeze, because the player waits *longer* before concluding something is wrong. Panic (see
below) is the exit strategy and should land with or before this.

### Tracers and hit visuals
**Needs:** nothing now. taskblock-44 brought an AI step to ~525ms debug / ~412ms release and made the
wait navigable rather than frozen, so shots can be watched resolve. **Unblocks:** the six bugs it covers.

*Was taskblock-42 Pass F, carried inline here because that spec file is archived and a pointer to it
would dangle.*

Verifying any of these means watching shots resolve, and the turn-boundary hitch is what makes that
unverifiable by eye. taskblock-43 brought an AI step from ~745ms to ~646ms — real, and not enough.

**Treat as one investigation, not six fixes.** The suspicion is that several share a root in how a
shot's endpoint and hop sequence are turned into drawn geometry. All six live in `ResolutionPlayer`
and the tracer-drawing path:

- **BR34.05** — misses vanish instead of striking anything.
- **BR35.04** — a DEFLECT's bounce tracer is a decorative fixed-range projection, not the real path.
- **BR35.07** — `STOP_DEAD` tracers are drawn past their own hit point, reading as penetration.
- **BR34.01** — every penetration/deflection hop replays the full bright hit-flash.
- **BR35.08** — detonations are invisible; nothing is drawn when an explosion resolves.
- **BR27.03** — other shots appear to resolve before an earlier shot's deflect finishes. Ordering
  rather than geometry, but the same player-facing subsystem and worth holding in view while the rest
  is open.

**The rename-only fence is lifted for this work.** taskblock-40 Pass A renamed `void_range` to
`miss_range` under an explicit fence because the supervisor believed the area held a live bug.
**BR34.05 and BR35.04 are that bug.**

### Visible combat artifacts
**Needs:** nothing. **Unblocks:** the supervisor being able to judge combat by watching it rather than
by reading a log.

**If a combat rule has a spatial extent, the player should be able to see that extent.** Several
currently exist only as numbers in the log or as inferences from an outcome:

- **The overwatch cone.** A unit on overwatch is watching a real region; nothing draws it. The player
  cannot tell whether stepping one cell left is safe, which makes overwatch a guess rather than a
  threat to route around.
- **Explosions.** A detonation resolves and nothing is drawn (`BR35.08`). The blast has a radius and a
  falloff that the resolver knows exactly.
- **Then everything else of the same shape** — suppression fields, hazard volumes, the reach of a melee
  action, the projected path of forced movement. The rule is general: **a spatial rule with no drawn
  extent is a rule the player has to learn by dying to it.**

Pairs with *Tracers and hit visuals* above — that item is about shots that already draw drawing
*correctly*; this one is about effects that do not draw at all. Same subsystem, opposite defect, and
worth doing together if either is picked up.

**`08`'s transparency pillar applies unchanged:** whatever is drawn must come from the same computation
the resolver uses, never a second approximation authored to look right.

### Automatic batch assignment in generated missions
**Needs:** taskblock-43 Pass C/D (landed — `Unit.batch_id`, `BatchPlan`, the leader/follower split all
exist and are hand-assignable via the `set_batch` debug verb). **Unblocks:** nothing.

taskblock-43 deliberately built batches as **manual assignment only**; no generated mission assigns
one, so `batch_id` is 0 everywhere in real play and the whole mechanism is currently dormant outside
tests and the debug panel. Turning it on means deciding what a batch *is* in mission terms — a fire
team, a patrol, everything sharing a spawn point — which is a design question, not a follow-up chore.

**Worth weighing against item 2 in NEXT before building:** batching one squad of three measured
~671ms → ~646ms per AI step, so as a *performance* argument this is weak; if it earns its place it
will be as squad behaviour that reads better, not as a speed-up.

### Status effects and boosts
**Needs:** nothing. **Unblocks:** perks, power and therms, wound thresholds.

**Burn, bleed, and tesla-charging-allies are the same shape** — a timed, stacking modifier through
`StatResolver`. Buff versus debuff is a sign. Build once.

- **Stack model** — accumulation, decimal stacks preserved, decay-below-half-vanishes, per-turn tick.
- **Consume the live hook** — `status_applied` already fires; make burn and bleed read it.
- **Boosts** — the buff direction, ally-applied.
- **Status → wound threshold** — closes tb20's dangling hook (burn → burnt_electronics).
- **Retire the docs/08 burn fiction.**

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

**Perk families — one slot, several weapon classes.**
A perk belongs to a **family**, and a family is taken as a unit. *Rapid Fire* consists of *Fan the
Hammer*, *Mag Dump* and *Pump It*, granting attacks to revolvers, rifles and shotguns respectively.

- **This is a capacity mechanic, not a taxonomy.** A matrix holds only so many perks, so the real
  choice is breadth against depth: one slot that does something for whatever you happen to be holding,
  versus one slot that does more for exactly one thing. That trade is what makes families interesting
  rather than merely tidy.
- **It is self-limiting, which is why it can be generous.** A family grants all its members, but a
  member only does anything when you are carrying the weapon it binds to — so a revolver specialist
  taking *Rapid Fire* gets *Fan the Hammer* and two dead entries. The breadth only pays for a build
  that actually switches weapons, and no cap or exclusion rule is needed to enforce that.
- **It costs the framework nothing.** A family `.tres` lists member perks, each already a data binding
  of an existing kind (*Fan the Hammer* is the action-grant example above). No new binding type, no
  bespoke code — which is itself a check that the family concept is the right shape.
- **It gives builds an identity.** "Rapid Fire" reads as a versatile shooter; taking only *Mag Dump*
  reads as a rifle specialist. Same underlying grants, different character.

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

**Gas is the same substrate as therms, in different units — build the diffusion engine once.** The
therm model above is already a diffusion model: particles with a counter and a transfer rate, levelling
toward equilibrium with their neighbours, resolved per turn at start-of-turn. Gas is that, measuring
concentration instead of heat.

- **A gas is an intangible `Part`** — transparent, no hp or sockets, tagged so it neither projects into
  the shot plane nor counts as walkable. It sits in a cell and applies an effect scaled to its own
  concentration.
- **Diffusion runs high-to-low**, which is both how real gases behave and cheap to compute. A cell hands
  half its excess to a lower neighbour on its turn, until concentration levels out and the effect
  reaches zero, at which point it dissipates. *Determinism is still a hard rule* — high-to-low is
  reproducible provided the processing order is stable (sort by concentration with the cell index as
  tiebreak). Mathematical artifacts in a drifting cloud are invisible in play; a bout that doesn't
  replay from its seed is not.
- **Vacuum is a gas part at zero** that voids any gas it touches. So **decompression is emergent**: blow
  a wall, expose the interior, and pressure zeroes over a few chaotic turns before settling to hard
  vacuum — which is a fair model of a real decompression event. This is finally the payoff for tb31's
  destructible walls, which were explicitly built as "the hook decompression will later read."
- **It removes a special case from the therm design above.** Air-cooling is currently a boolean
  ("the air, unless vacuum"). With real concentration it becomes a function of that concentration, and
  vacuum is simply zero — no separate rule.
- **Gases are physical objects, just small ones**, which ties them to the substance model in Storage: a
  hulk full of valuable hydrogen is a container of substance at hulk scale, and an extremely dangerous
  salvage job.
- **Sudden pressure loss flings units** toward the drop — see the forced-movement entry below.

**Therms supply the trigger math for weak points; the weak points themselves are a separate item.**
The reactor is the defining example — a vent cycle is a therm threshold, and the window it opens is
computed here. What that window *looks like* (which pose, which box, where it protrudes) is authored
content with its own rules, and lives in *Weak points* below. This item owes that one a signal, not an
implementation.

**General weakness pattern beyond the reactor:** any part can carry a weakness as an **exposure condition**
(usage-threshold, action-active, fixed-cycle) that moves an internal into reach. "Something opens up while
overwatching or bursting" is the same shape.

**Delayed-lethal consequences need a signal at trigger-time, not death-time.** The heatsink shot does
nothing visible for a turn or two, then meltdown — unreadable without feedback. A delayed-fatal state must
announce itself when *triggered*: a notification saying, calmly, "Nuclear Runaway Detected." Applies to any
delayed-lethal consequence — signal the cause, not just the death.


### Weak points
**Needs:** *Power and therms* for the trigger math; `02`/`03` (landed). **Unblocks:** the reactor vent
window; per-part weaknesses generally; the Cutter and Demolitionist fantasies having something to aim at.

**A major benefit that forces a vulnerability.** A powerful reactor must vent heat every few turns —
vents open, a large heat sink protrudes, and for that window shooting the sink is equivalent to shooting
the reactor directly: coolant leaks, possible meltdown.

**Discrete from the therm math that drives it.** *Power and therms* computes *when* a window is open; this
item is *what is exposed while it is* — poses, box placement, which socket the exposed geometry hangs
off, and how it reads to a player deciding whether the shot is worth taking. The two are separable and
should stay separable: a weakness triggered by a status effect or a firing cycle rather than by heat
needs the same authoring and none of the reactor's arithmetic.

**Architecturally cheap because `02` and `03` already exist.** A weak point is a **volume box that only
projects during certain turns**, plus a damage rule forwarding to its parent. The shot plane already
projects body-space boxes from the shooter's real angle; a conditionally-projecting box is the same
machinery with a predicate. Poses already exist and already swap geometry. No new systems — the work is
the authoring vocabulary and the predicate, not the projection.

**The general pattern beyond the reactor:** any part may carry a weakness as an **exposure condition** —
a box that projects only while some predicate holds. Firing cycles, vent cycles, status effects, pose
transitions. Authored per part, evaluated by one rule.

**Delayed-lethal consequences need a signal at trigger time, not death time.** A heat-sink shot that
starts a meltdown resolves several turns later; the player must learn that the shot *caused* it, or the
mechanic reads as random. Whatever fires the delayed effect emits at the moment of the hit, not at the
moment of the death.

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


### The tile format
**Needs:** nothing — **multi-level landed in taskblock-40 and this item's old blocker is gone.**
**Unblocks:** both editors below, and hand-authored maps as a diagnostic surface.

A saved, height-aware map tile that proc-gen assembles from. Everything else in the authoring chain sits
on this, so it goes first and alone.

**Worth more than it looks.** Every AI diagnosis for the last four blocks has been conducted by hunting
seeds — reading a completion table to find which generated map exposed a defect. A hand-authored map
turns "find a seed that reproduces this" into "build the situation." That is a permanent reduction in
the cost of every future investigation, not a content feature.

### Map and tile editors
**Needs:** *The tile format*. **Unblocks:** *Main menu*.

- **Tile editor** — author a tile, save it for proc-gen assembly.
- **Map editor** — author and save a full map, and **run a test bout on it**. The test-bout half is the
  part that matters; an editor that cannot launch what it authored is a file format with a GUI.

Built on the tile format, and on the bout builder that already exists rather than a second path into
combat.

### Main menu
**Needs:** *Map and tile editors*. **Unblocks:** nothing.

Rolls the in-game tools into one reachable place — bot builder, bout sim, map and tile editors.
***Resource Editor excepted*** — it stays standalone. Built last, once there is something to roll up.

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
- **Every test that builds a fight should be loadable in the bout builder as well as headlessly.** CC
  runs them as tests; the supervisor loads the *same* scenario in the builder and watches the failure.
  That closes the "CC can't see the game" gap for exactly the class it has been worst at — AI
  behaviour and mission stalls, where a headless red tells you *that* it failed and nothing about
  *why*. The inverse of the handoff below: instead of CC authoring a scenario for the supervisor, the
  suite's existing scenarios become loadable. Needs one shared scenario format both paths consume, so
  a test fixture and a builder preset stop being different things.
- **Drag-and-drop scenario handoff** — the missing half of "CC authors, the supervisor watches." CC can
  describe a situation but can't put it on the supervisor's screen; the debug panel put forcing verbs in the
  supervisor's hands but requires clicking each one. Close the loop: **drag a scenario file onto the game
  window and it applies** — a file declaring units, tiles, cover, positions, loadouts, either silently or
  through a small confirm-and-tune dialog. The same authored presets become a transport format, not just a
  bout-menu entry, and CC gains a real way to hand over a reproduction. Every applied scenario is injection,
  so it carries `was_injected` and the usual determinism flagging — a dragged-in bout is not a clean seed
  replay.


### Review pass over the test suite
**Needs:** nothing.

2038 test functions across 214 files run on every change, and the suite has never been audited as a
whole — only ever added to. The suspicion is that a meaningful share is redundant, exercises systems
that have since been retired or reshaped, or asserts an old model's own limitations rather than a real
invariant.

That last category is the dangerous one and it has a proven instance: tb36 found
`test_prone_pose_changes_the_projected_shot_plane_vs_idle` asserting exactly one projected region,
which encoded the four-face model's *gap* as though it were a rule. It passed for fifteen taskblocks
while a prone unit was, in real play, unhittable from the front. **A test that pins a bug is worse than
no test** — it converts a defect into a defended invariant, and every future change that would have
fixed it looks like a regression instead.

Concrete starting signals, not a full audit:
- **`checkpoint` appears in 6 test files** — that ritual is retired (`SUPERSEDED.md`); `test_checkpoint_
  1–4.gd` survive as ordinary regression tests but are still named for a mechanism nobody runs, and the
  rename is already scoped in the checkpoint-machinery item.
- **`vertical_slope` and `grid.height` each still appear in a test file**, both retired in tb36 — worth
  confirming those are deliberate historical references (the `grid.height` one is the rename's own
  guard test, which necessarily quotes the banned string) rather than stragglers.
- **Four files exceed 850 lines** (`test_body_projector`, `test_damage_resolver`,
  `test_resolution_player`, `test_inspect_panel`) — worth checking whether they've accreted overlapping
  coverage of the same paths, since several were split at gdlint's cap rather than along a seam.

**Separate tests that PIN behaviour from tests that SAMPLE a distribution — mixing them is what
creates a re-pick treadmill.** A pinning test fixes its inputs and must go red the instant behaviour
changes; that's its whole job. A sampling test asks a statistical question ("are missions completable
at all?") and should run N cases and assert a *rate*, never a single frozen seed.

`test_full_mission.gd` **was** the worked example, and tb39 Pass A fixed it: it asked an existence
question ("a mission can be completed") but was implemented as a pinned seed, so every real mechanics
change forced a re-pick — six of them, and that churn absorbed a real AI line-of-fire bug as noise
instead of surfacing it. A tb38 investigation of seeds 12373–12383 found only **2 of 11** complete,
with the failures concentrated in AI-stuck behaviour rather than impossible maps. It now samples 12
seeds and asserts a completion rate (`MIN_COMPLETION_RATE`), which needs no re-picking and collapses
visibly when the AI actually regresses.

**The audit's job is to find the others.** One instance is fixed; the confusion it came from is a
suite-wide habit, and any other test asserting an existence or capability claim through a frozen seed
has the same defect. A re-pick in a test's own header is the tell.

**Deliverable is a written audit, not a deletion spree.** Per test or cluster: what it covers, whether
anything else already covers it, and whether it asserts a real invariant or an implementation
accident. **Deleting a redundant test and deleting the only test of a real rule look identical in the
diff** — so a test found genuinely load-bearing is a result worth recording, exactly like the
correct-as-is findings in the tb35 wall audit. Runtime is a secondary benefit; correctness of what the
suite *claims* is the point.

### Review pass over map generation
**Needs:** nothing further — multi-level's view-layer legibility landed in full (taskblock-40,
`CHANGELOG.md`); the supervisor's own confirmation via `./checkpoint.sh 8` is independent of this
item, not a gate on it. **Unblocks:** trusting generated maps as a test surface.

`MapGen` has been reshaped three times in quick succession — tb38 made floor and terrain into parts,
tb39 moved carving into a private `MapGenScratch` that emits real `Surface`s once at the end, and
elevation arrived across tb36–37. Each change was verified against its own acceptance, but nobody has
looked at the *output* as a whole since before any of them.

Deliberately deferred until multi-level is finished, because a review now would audit a shape that is
about to change again.

Starting signals, not a full audit:

- **Are generated maps actually good?** Room count, hallway width, connectivity, and elevation
  distribution across a seed sweep — reported as numbers, not a pass/fail. tb17 Pass A already caught
  one arithmetic cascade that silently collapsed every map to a single room; the guard added then
  proves it splits, not that the result is worth playing.
- **Is elevation being used, or just supported?** `RAISED_ROOM_LEVEL` exists; how often does a
  generated map produce a meaningful height difference, and does the AI ever path through it?
- **Does the scratch/emit split hold under every branch?** The emergency fallback corridor and the
  re-carve paths are the ones that motivated the split; confirm they still produce exactly one
  correctly-typed surface per cell.
- **`MapGenScratch`'s `get_level`/`set_level` are the last survivors of the old vocabulary.** They're
  legitimate — a private carving model — but worth confirming they haven't quietly become a second
  source of elevation truth alongside placed `Surface` height.

### Review pass over the docs
**Needs:** nothing. **Unblocks:** trusting a `docs/NN` citation without opening the file.

Filed when `docs/09` was renamed and `docs/11` added, to record what was already checked and what
was not.

- **The `docs/09` rename is verified clean — do not re-derive this.** `09-checkpoints-and-logging.md`
  became `09-combat-log-and-turn-phases.md`, matching the `# 09 — Combat Log & Turn Phases` heading
  the file already carried. The content is **byte-identical**, all 237 code citations use the bare
  `docs/09` form the conventions prescribe, and **nothing anywhere referenced the old filename**. No
  reference dangles.
- **`docs/11` is new and nothing cites it yet.** taskblock-45 landed the utility planner with long
  architectural doc comments on `UtilityScorer`, `UtilityContext`, `WorldView`, `BatchObjective` and
  `UtilityPlanner` that now restate what `docs/11` says in one place. The convention is to cite
  `docs/NN` rather than restate, so those comments want thinning to the decisions genuinely local to
  each file, pointing at `docs/11` for the model itself. **This is the substantive half of this
  item** — duplicated prose is what goes stale, and it is currently duplicated in five files.
- **Sweep the rest of `docs/` for statements the taskblock-45 retirement made false.** The
  engagement-score planner, its penalty constants and its branch cascade are gone; any doc still
  describing the AI in those terms is describing nothing.

### Startup opens a generated bout
**Needs:** nothing.

The game boots into whatever the default scene is, and that generator may be outmoded. Boot instead into a
freshly generated bout via the live bout builder — the same "starter battle folds into the bouts system"
consolidation as the full-mission-test replacement. Small, but it removes a stale entry point that can drift
out of sync with the real generation path.


### Cut `test_completion_sampler.gd` further, or decide it is right
**Needs:** nothing. **Unblocks:** nothing; a judgement call left open rather than made under a
suite-cost pass.

taskblock-47 Pass E took this file 437 s → 207 s and it is still the most expensive in the suite. What
remains is genuine — it plays real missions to check the sampler reports them correctly, and the bouts
left are the ones its properties actually need.

**Cutting further means deciding the sampler does not need an end-to-end test**, which is a bigger call
than a pass about suite cost should make on its own. The options, if it is ever worth taking: assert the
report shape against a hand-built result dictionary and keep exactly one real sample; or accept the
cost as the price of the one number that says whether the AI can finish a mission.

### The utility actions with no executor behind them
**Needs:** an executor each; `call-for-help` needs a mechanism that does not exist. **Unblocks:**
the four table cells `docs/11` still lists as unbuilt.

taskblock-46 filled every row of the tier table that could be filled by authoring a `.tres` against
machinery that already existed. These four could not, and the distinction is worth keeping straight —
the rest of that work was authoring, and this is building.

- **`use-item`.** `RepairAction` and `PickUpAction` exist and are the player's, so this is the closest to
  ready: it needs preconditions and a consideration set over an input that says whether the unit is
  carrying something worth using, which is not published yet.
- **`bait` and `ambush`.** No executor. Both are also *multi-turn intents* rather than actions — "move
  somewhere visible and wait to be shot at" is not a thing the one-turn scorer can express, so these
  probably need the batch objective to carry them rather than the action pool.
- **`call-for-help`.** **No mechanism at all.** A unit cannot influence another unit's plan today; the
  batch objective is the only thing in the codebase that comes close, and it is set by the leader rather
  than requested by a follower. Authoring an action for this would mean inventing the mechanism it needs,
  which is the thing not to do.

### AI target selection and behaviour
**Needs:** nothing, but read against *AI v2, part two* first — **three of the four bullets below become
action-pool and consideration content for the utility planner rather than separate work.** Target
selection becomes a consideration; nearest-weapon and per-archetype item behaviour become Actions with
preconditions. Only **Panic** is genuinely independent, and the rebuild makes it *more* necessary, since
a scorer can return no positive-utility action at all. Build them here only if the rebuild slips.

Four related gaps in what the AI *chooses* to do, all cheap given the data already exists.

- **AI fixates on the nearest enemy even when it's genuinely unshootable.** `UtilityContext._nearest_known_enemy`
  always targets the closest living candidate, with no fallback to a different, actually-reachable target if
  the nearest has no line anywhere. Surfaced re-running the wall-impact measurement: one defender spawns in
  a nook confirmed to have no clean line from any reachable cell, adjacency included. The fallback correctly
  holds rather than firing blind — working as specified — but the squad then never tries either of the other
  two defenders, and the mission stalls for the rest of the turn cap. Re-running the original wall-impact
  measurement against that fixture found **zero impacts in 400 turns** — not a revised percentage, because
  every unit holds every turn. Not a LOF question: target *selection* needs to skip past a genuinely
  unreachable-by-shot enemy toward one that isn't.
- **AI for damaged units — head for the nearest weapon.** A disarmed unit has little to do. Since the sim
  knows where everything is, handing it the location of the nearest weapon on the field — not necessarily a
  *functioning* one — gives it a purposeful action.
- **AI item behaviour per archetype, with a fallback.** Generalises the above: each archetype declares what
  item types it seeks and how it prioritises them (a brawler grabs a dropped melee part, a gunner a
  functioning ranged weapon, a support archetype a welder), plus a **fallback action** for when it holds no
  item it knows how to use, so an archetype never stalls. Sits on the archetype data that already drives
  bout setup.


### Momentum
**Needs:** Attributes (Dex). **Unblocks:** nothing directly; it's what makes "fast" and "fast-attacking"
different characters instead of the same one.

**Movement in a turn accumulates momentum, and it is spent entirely on the NEXT attack** — not divided
across the turn's attacks. Move two MP and strike once, that strike carries the whole bonus. Move two MP
and strike five times, the first carries it and the other four are normal.

- **That single rule is the whole distinction.** A giant-sword build converts an entire turn of running
  into one hit. A flurry build, running the same distance, dumps the same momentum into its *smallest*
  strike and the rest land normal. Dex feeds both movement and attack speed, so the fast-attacking
  character is usually also a fast character — and gains far less from it. Same attribute, opposite
  payoff shape, no special-casing.
- **Attack ordering becomes tactical for free.** With a mixed loadout, leading with the heavy weapon is
  correct and leading with the light one wastes the charge. Falls straight out of "spent on the next
  attack" — nothing to build for it.
- **It also changes behaviour on interruption.** A unit carrying real momentum shouldn't stop dead when
  something interrupts it mid-move. Same machinery family as *Forced movement* below, and it reads the
  mid-move overwatch-trigger hook `MoveAction` already has.
- **Preserved between turns.** A unit flung to the backline is out of the fight for a few turns, then
  arrives coming in hot. Persistence is what makes that arc exist at all.

**Two forks to settle when this is picked up:**
- **Does forced movement generate momentum, or only self-directed movement?** If being flung builds it,
  decompression and throws *arm* their victim as well as displacing them, and the backline-return arc
  gets much sharper. If only chosen movement counts, the momentum comes from running back rather than
  from being thrown. Both fit the intent; they're different mechanics.
- **Does it decay while stationary?** Persistence with no decay means momentum banks indefinitely — move
  a lot once, sit on it, swing whenever — which inverts the intended fantasy into stockpiling. Decay
  while still is probably what keeps it dynamic, and the rate is a real balance number rather than a
  detail to fill in later.

### Forced movement — flung, thrown, knocked prone
**Needs:** nothing mechanically; consequences pair with the deep-fall rules.

**One family, not three features.** Being flung by decompression, thrown by an attack, and knocked
prone by a fall are the same shape: **an outside actor applies movement and/or a pose to a unit that
didn't choose it.** Nothing like this exists today — every position change in the game is a unit
spending its own MP on its own turn — so this is genuinely new machinery, and worth building once for
all three rather than three times.

- **Movement plus pose, from an external cause.** The mover isn't the moved. A flung unit travels in the
  direction of the pressure drop; a thrown unit along the attack vector; a fallen unit stays put and
  changes pose. Same verb, different arguments.
- **Consequences pair with the deep-fall rules.** Falling past the safe hop-down distance is meant to
  cost damage or a knockdown; that consequence *is* forced movement's output, so design them together
  rather than inventing knockdown twice.
- **Resistance is an attribute roll — later, and not defined yet.** Once attributes land, a unit rolls
  to resist being moved or posed. Perks that avoid the consequence entirely are already sketched under
  Perks. **Do not invent the roll's shape or numbers ahead of that** — leave a flagged hook.
- Standard CRPG vocabulary applies (thrown, knocked prone); no need to invent terms.

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


### Remaining melee pieces
**Needs:** nothing.

- **Protector profile** — positions between enemies and allies, preferring covered spots. Now a
  `UtilityProfile` weighting a not-yet-published *ally protection* input, rather than the
  "COVER_SEEKER variant" this was written as — taskblock-46 retired the playstyle vocabulary, and the
  cover-seeking half is already `take_cover`'s weight in the `defensive` profile. What is actually
  missing is the input. Not melee-gated; can land whenever.
- **Weapon distinctions — saw versus sword versus fist** (the `POWER`/`TRIGGER` capability split). A saw-hand
  can't add power to a sword swing.

---

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


### AI repair
**Needs:** nothing in the plumbing.

`ActionCatalog`-driven repair is already available to the player, and the catalog-derived consideration
scaffold would surface it to the AI for free — but no when-to-repair logic exists. Enemy self-repair is a
design choice deferred, not a gap.


### Mulebot and follower drones
**Needs:** nothing identified. **Unblocks:** carrying capacity beyond a squad's own arms.

Carried over from the old `Support gaps` grouping, unchanged and still unspecified beyond the name. If
it stays this thin through another review it belongs in `docs/99` until it has a shape.

### Hacking
**Needs:** Attributes (Int-based), Status. **Unblocks:** *Rampancy*'s active-pressure framing; the
"control system hacked" presentation note under *Small mechanical notes*.

Int-based, and the RAM cost model it would spend against already exists (`05`). The presentation
treatment is already written down separately — what is missing is the mechanic it would present.

### Voidhulk stability as an environmental hazard
**Needs:** nothing identified. **Unblocks:** nothing.

Carried over from `Support gaps`. A hulk that degrades structurally over a mission, as pressure on
lingering. Unspecified beyond the premise — same caveat as *Mulebot* above.

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


### One view, toggleable modules
**Needs:** nothing. **Unblocks:** closes a recurring bug class structurally, and makes every panel
verifiable in one context instead of several.

`SingleUnitOverlay` is **54 lines** because it inherits `SquadControlOverlay` wholesale — sharing works
fine when inheritance is available. `SpectatorOverlay` is **527 lines** because it *cannot* inherit it:
doing so would drag in `TacticsController` and the entire unit-input path the spectator view is
specifically defined not to have. So it re-implemented the display half separately, and every shared
panel now exists twice. **Inheritance forced the fork.**

taskblock-41 paid for that six times in one block, and its own conclusion is the argument for this item:

> it is used in two layout situations and I kept verifying one … **None of them were logic errors; all
> of them were verification-shape errors.**

**Shape: one view whose modules toggle**, rather than N overlays each assembling their own subset. A
module — combat log, stat block, turn controls, tooltips, unit inspector — is implemented once and
behaves identically wherever it appears. An overlay becomes a *declaration of which modules are on*
rather than a builder of panels. Composition where inheritance couldn't reach: display modules and input
modules toggle on separate axes, which is exactly the axis `SpectatorOverlay` needed and couldn't get.

**Why it earns real work rather than more diligence:** a module with one implementation has one context
to verify. The whole class of defect tb41 hit — correct logic, wrong context — stops being *possible*
instead of being caught more reliably.

- **Inventory what's actually duplicated before designing the boundary.** The 527 and 812 line counts
  include plenty that isn't panels; the module seam should follow real duplication, not the file split.
- **The combat log is the worked example and is already half-converted** (tb41: "Both views share one
  combat log"). That conversion is the template, and its leftover rough edges — bottom-edge pinning on
  resize, flush-to-corner placement — are precisely the kind that stop recurring under this model.
- **Pairs with the `mouse_filter` sweep.** Both close an entire class of UI bug structurally rather than
  one instance at a time, and both are cheap relative to what they prevent.

### The `mouse_filter` sweep
**Needs:** nothing. **Unblocks:** closing a recurring class of UI bug instead of one instance at a time.

Four separate bugs have now been the same defect: a full-rect `Control` whose `mouse_filter` doesn't match
what it actually draws. `BR31.01` (turn controls vs. tooltip), the `TopLeftControls` fix, `BR34.02` (the log
ate clicks through a fully transparent region), `BR30.05` (the debug panel let clicks through a fully opaque
one — the same mistake inverted). Each was found by a human noticing, then fixed alone. `BR30.05` asked for
the sweep by name and was closed without it.

Two rules, both already written down and both now testable:
- **Renders nothing → must not take the mouse.** docs/09 taskblock-07 Pass B4's rule, correct as far as it
  goes.
- **Draws a real background → must take the mouse over what it draws.** `BR34.02`'s own resolution, and the
  half B4 never covered. A panel honest about occupying space is not a bug.

`test_battle_scene_input.gd`'s audit already encodes both and walks `BattleScene`'s live tree — but only what
that scene happens to build. The sweep is: run it over every `Control`-bearing scene, and fix what it names.
Cheap, mechanical, and it converts "someone will notice the fifth one" into a red test.

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

Only the player's shot ever draws a dartboard — an AI attack resolves straight from the planner's decision with
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


### Commission real art
**Needs:** a vocabulary freeze — a stretch of taskblocks in which **no socket type or part kind is
added or renamed**.

Art is commissioned **per part**: every part is a rigged asset (`Part.mesh_scene`). While socket types
and part kinds are still being added and renamed, commissioning buys against a moving target — and
*that* is the waste, not the placeholder boxes. Boxes cost nothing while the vocabulary moves.

**The dependency is a real, checkable condition, not a vibe.** Watch socket types and part kinds across
blocks; when they stop changing, the vocabulary has frozen and art becomes worth money. Until then this
stays here no matter how much the placeholder look grates.

Style constraints when it does land are already settled in `docs/08` (terminal UI: monospace, six
colours, one `Theme` resource; no CRT, scanline, or glow fakery — that's a later shader pass over a
correct flat UI). HL2-era looks, CC0 placeholders in the meantime.


### The balance pass
**Needs:** melee and *Status effects and boosts*, so the numbers are being tuned against a system that
exists. **Unblocks:** every "is this fun" question; the point at which flagged placeholders stop being
flagged.

**Roughly 13 constants are currently marked as placeholders** across the codebase — deliberately, per
CLAUDE.md's rule against inventing balance numbers. This is the item that retires the flags.

- **Tuned against watched bouts, not against a spreadsheet.** The instrument is the supervisor watching
  real fights, with the combat log as the record of what actually happened. The completion sampler and
  the decision log both feed this — a constant that looks wrong in a log is worth more than one that
  looks wrong in isolation.
- **Inventory the flagged constants first**, as a list with what each one governs and what would make it
  right. Half the work is knowing which numbers are actually load-bearing; several are almost certainly
  fine at their placeholder value and can be un-flagged rather than tuned.
- **Done means every flag is either tuned-and-justified or deliberately un-flagged**, with the reasoning
  written down. A constant that stays flagged forever is a decision nobody made.

### Cosmetics and clutter
**Needs:** nothing; gates nothing. **Unblocks:** nothing.

Part painting, tchotchkes, dyes, bag labels. Genuinely independent of everything and safe to pick up
whenever something short is wanted.

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
- **The FPS readout repaints far faster than it changes.** `FpsMeter`'s window is already one second and
  its arithmetic is right (frame count over elapsed time, not the mean of per-frame rates); the churn is
  `CombatLogPanel._process` rebuilding the label every frame. Throttle the *text* to roughly three times a
  second and keep `sample()` on every frame — sampling once a second instead reduces the average to a
  single sample and makes the instantaneous figure meaningless.
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
