# PLAN.md — Build Order

**Forward-only.** Sequences *unbuilt* work. Built work → `CHANGELOG.md`; reversals → `SUPERSEDED.md`;
defects → `BUGS.md`.

**Dependency is the only ordering driver.** An item sits where it does because of what it needs — not
because of how big it is, how interesting it is, or when it was written down. A one-line change and a
whole system are peers here: work is single-threaded, so size never affects what comes first.

**Size means nothing here; position means everything.** An item may be a single pass, a whole taskblock,
or several — that is what the flat structure is for, and sizing items to fit a block would just be a
second bucket system wearing a different hat. **An item's position in this file is its schedule.** What
an item owes is a coherent piece of work with its own dependencies, not a particular length.

**Order carries the sequencing, so an item that would simply go better after another belongs after it**
— with the reason in its body. There is no `Wants:` line; a soft preference recorded as a field becomes
another thing to keep true.

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

**New items go as high as their dependencies allow.** A newly recorded item is placed at the earliest
position its **Needs:** line permits — if that is the top of NEXT, that is where it goes, and NEXT's
last item demotes to QUEUED to stay within the cap. **That demotion IS the re-evaluation the bucket
rule above demands, not an exception to it** — the cap is exceeded, so the whole bucket is re-read and
the item that comes out is the one that survives that reading. What the bucket rule forbids is dropping
the bottom item *without* looking; arriving at the same item deliberately is the rule working. **Recency is a signal**: a thing raised now is
usually the thing in view now, and an item that keeps being passed over is telling you something about
its real priority. The consequence is deliberate — **long-standing NEXT items get pushed back by newer
unblocked work**, and an item that has sat near the top for many blocks without being picked up should
be re-read rather than defended.

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

### 1. Rename the terrain parts to sort together, and mark them as placeholders

**Needs:** nothing. **Unblocks:** an author finding a floor in the part list; the tag work below
having something coherent to tag.

**A mechanical rename of the terrain parts**, asked for during the UI review and generalized here
because it is not only the floor: *"`ship_floor` should become `floor_ship_placeholder` so that
alphanumeric sorting puts all the floors together. This should also happen for all the other tile
related items. And placeholder to tag them as needing later tuning or replacement."* **Wall is a
placeholder too**, which is why this is *terrain parts* rather than *tiles*.

**Two things the new name does at once**, and both are the point:

- **A category prefix makes an alphabetical list group itself.** The editor's part list is sorted
  alphabetically now, so `floor_ship_placeholder`, `floor_deck_placeholder` and so on land together
  with no filter at all. That is a real substitute for the tag work while the tag work does not
  exist.
- **`placeholder` in the id says the content is provisional** where a comment in a `.tres` does not
  travel. These are stand-ins for models nobody has made.

**The shape is `<category>_<what>_placeholder`** — `floor_ship_placeholder`, `wall_ship_placeholder`
— but the exact spelling is the supervisor's; what is settled is prefix-by-category and the
placeholder suffix.

**Size it honestly: this is a 524-hit sweep across 49 files**, measured, and it includes authored
`.tres` maps and sections that carry part ids as data. So it is cheap to *do* and it must land on a
full-suite gate rather than a targeted one — which is the only reason it was not done inside the UI
review passes.

**Not a rename of the `walkable` tag or of `GROUND`.** Those are vocabulary the rules read; this is
content identity.

### 2. Rework the gizmo as a real CAD tool

**Needs:** nothing. **Unblocks:** authoring geometry by direct manipulation rather than by typing
numbers into a panel.

**The taskblock-57 Pass H gizmo is not what was wanted, and the supervisor's call is to rebuild it
rather than adjust it.** What shipped satisfies the block's stated acceptance — drag an arrow, get a
snapped 0.3 — but its *shape* is wrong: it is armed by a `gizmo` tool that must be selected before a
click will focus anything, which the supervisor summarised as *"not intended to be a 'click button
to place gizmo'"*.

**What it should be instead:**

- **A select tool, and tools as a real concept.** *"Likely need to put things under actual tools. A
  select tool creates the gizmo on clicked items."* Selecting is the default mode of a CAD surface,
  not one verb among nine — the editor's current `TOOLS` list treats "select something" as a peer of
  "set sight blocking", which is what makes the gizmo feel bolted on.
- **The gizmo appears on whatever was clicked**, and is adjusted there. No separate arming step.
- **Auto-reparenting.** Moving a thing onto or off another changes what it is attached to, rather
  than leaving a placement whose parent is wherever it was authored.
- **A ghost of what is about to be placed.** *"Probably needs a 'ghost' of how something is about to
  be placed."* The editor currently commits on click with no preview, so an author finds out where a
  part went by looking at where it landed.

**What survives the rebuild.** `GizmoDrag` is pure arithmetic — screen delta to axis delta to a
snapped value — and is right regardless of how the gizmo is armed. `Gizmo.resized_box` and the
ray-vs-box handle picking are likewise about geometry rather than about the interaction. **The part
to throw away is the arming and the tool routing**, not the maths.

**Do not let it become a second selection system**, which was taskblock-57 Pass H's own stop
condition and is *more* at risk under this design rather than less: a select tool that creates a
gizmo is very close to a selection of its own. Whatever the editor already treats as "the thing
being pointed at" is what the gizmo must read.

### 3. Retire ramps; introduce `step_height`
**Needs:** nothing. **Unblocks:** step height as a per-unit stat; deletes a subsystem rather than
repairing it. **Read before `BR56.01` is fixed.**

**Settled: ramps as machinery go away, replaced by stairs plus a step height.** A "ramp" becomes two
ordinary tiles at 0.3 and 0.6 — content, not a special traversal case.

**`step_height` does not exist yet, and that is the work.** Today `MAX_CLIMB_LEVELS` is 1.0 and
**capability-gated**: a non-climber cannot go up at all without a ramp or a ladder, so a 0.3 tile is not
walkable-onto by anything in the game. Introducing a free step height is what makes stairs work, and
that one number replaces five separate checks:

| today | under `step_height` |
|---|---|
| `is_ramp_at` in `ClimbAction` — refuse, it is a walk | rise ≤ step height → walk |
| `is_ramp_at` in `HopDownAction` — same on the way down | rise ≤ step height → walk |
| `_is_ramp_surface` in `move_cost` | rise ≤ step height → flat cost |
| `MapGen.RAMP_MAX_RISE` and its generator branch | place tiles at heights |
| `CellKind.RAMP` in `MapGenScratch` | gone |

**Five categorical checks become one continuous comparison**, and it is the better rule: *can this unit
step up that far* rather than *is this thing labelled a ramp*.

**`Surface.facing` never reaches the pathfinder**, so a ramp is already traversable from any direction —
you can walk up its side. The directionality that would be the strongest argument for keeping ramps is
not implemented, which also means **`BR56.01` is a visual defect on a field nothing reads.** Do not fix
it first; it is a facing bug in a subsystem this deletes.

**Step height becomes a per-unit stat**, which a ramp could never express — long legs step higher. Two
consequences:

- **The generator's navigability invariant must run against the lowest step height in play**, not a
  constant. A 0.6 rise being free for some units and not others is the point, and the invariant has to
  assume the worst case.
- **A cosmetic ramp part is fine** — sloped geometry with no special traversal rules. If a two-tile
  stair does not read well visually, the answer is content, not machinery.

**Ramps return later as a genuinely distinct thing.** Once tracked and other legless chassis exist,
"has no step height at all and needs a continuous slope" is a real mechanical category — and it will be
*about the chassis*, not about a cell being labelled. **That is the version worth building, and it is
not this one.**

### 4. Elevated tiles lost their line borders
**Needs:** nothing. **Unblocks:** reading a stepped board by eye.

Grid lines went flat when taskblock-55 deleted the ground quad, and lines-at-tile-height was **passed on
deliberately at the time** — more legible on a stepped board, but co-planar with the tile top, which is
the pairing the ground quad was deleted for. The supervisor now reports elevated tiles as unreadable
without them, so **the judgement call is due for revisiting rather than being a regression.**

If the answer is to draw them, the co-planarity is the problem to solve — a small offset, a different
primitive, or the tile's own edge geometry doing the work.

### 5. Attributes
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

# QUEUED

### Nothing in a BOUT emits an announcement yet

**Needs:** nothing. **Unblocks:** the announcement position doing anything during a battle.

taskblock-57 Pass E built the mechanism end to end — `Announcement`'s priority table,
`AnnouncementFeed` as a `LogSink`, `AnnouncementsModule` at the table's own position, and
`Announcement.tag` as the one way in.

**Pass G2 gave it its first customer, and the item narrowed rather than closing.** The editor's
navigability warnings tag themselves `ALERT` (`EditorLog`), so the position is no longer correct and
empty — it works, in the editor, with a test that drives one warning into both surfaces from one
emit. **No call site in a bout tags anything**, which is the half that is still open.

**That is deliberate, not an omission.** Choosing which battle events shout at the player is a design
decision the taskblock does not make, and inventing a list would be exactly the "never invent balance
numbers and present them as design" failure one category over.

**Worth a supervisor pass over "what should announce"** — unit down, mission outcome, a matrix
ejected, an objective taken. Each is one `Announcement.tag(data, priority)` at an existing emit, with
no new path, and G2's warnings are the worked example of what that costs.

**The priority table's own numbers are the tuning pass's**, not this item's: 3/5/8 seconds and three
`HulkTheme` tiers, ordered rather than tuned, and `EditorLog` picking `ALERT` over `CRITICAL` for an
authoring warning on the grounds that the loudest tier is reserved for what ends a mission.

### Two chromes no shipped mode uses

**Needs:** nothing. **Unblocks:** nothing — this is a "is it dead or is it a spare" question, and it
wants an answer rather than a sweep.

taskblock-57 moved the last two modes off them: Pass C took the player mode to `BATTLE_LAYOUT`, and
Pass G1 took the spectator and the editor there too, because the editor's bar and the spectator's bar
both live in the placement table's action row. **`ModeChrome.PLAYER_COLUMNS` and
`ModeChrome.TOP_LEFT_ROWS` are now named by no `ViewModes` entry.**

**They are not obviously dead**, which is the whole reason this is recorded rather than actioned.
A chrome is *data a mode names*, and both are still reachable, still built, and still exercised —
`test_view_modes.gd` mounts an invented mode against `TOP_LEFT_ROWS`, and `test_three_bars.gd` asserts
that the pacing row still resolves under it. The slot vocabulary they publish (`LEFT_COLUMN`,
`INVENTORY_ROW`, `TOP_RIGHT`, `BOTTOM_RIGHT`, `READOUT_COLUMN`) is likewise named by nothing that
mounts today.

**The failure mode to avoid is the one this project has hit before**: `ClaimVolumeModule` sat correct
and unreachable for a whole block. The difference is that a chrome nobody names costs nothing at
runtime and deleting one is a real reduction in what a future mode can ask for. **Decide, do not
drift** — either they are the spare layouts a fifth mode picks up, and say so in `ModeChrome`'s
header, or they go with their slot names.

### The cursor never shows what is being placed

**Needs:** nothing. **Unblocks:** nothing — the requirement is met by its alternative.

taskblock-57 G2: *"Current tool shows on the cursor — a small icon of what is being placed — **or**
is carried by the action bar's own highlight. Either is fine; neither is not."* **The bar's highlight
is what shipped**, for a stated reason: a cursor icon is a `Control` tracking the mouse over a 3D
board, with its own z-order and hit-testing questions, where the buttons that set the tool are
already on screen and already know which was pressed.

**So this is not an unmet requirement**, and it is recorded only so a later reader does not find the
sentence, look for the icon, and mistake a taken option for a missed one. If the highlight proves too
quiet in practice, the icon is the other half of a specified either-or rather than a new idea.

### "Resolve to Here" has logic and no UI

**Needs:** nothing. **Unblocks:** partial resolution being reachable again.

`BR27.08` moved *Resolve to Here* out of the turn-control column and onto a per-row button in the
queue panel, which was the right shape while there was a queue panel. **taskblock-57 Pass D retired
the panel**, so the rows went and the only way to reach the verb went with them.

**The logic is untouched and still tested** — `SelectionController.keep_queue_suffix`,
`TacticsController.queue_partially_resolved`, and `resolve_until` with a player-placed stop point.
What is missing is an affordance.

**Recorded rather than absorbed into the retirement**, because the taskblock's own stop-and-report
rule names only `queue_panel`'s *confirmation* role as the coverage at risk, and this is a second
thing that went with it. The replacement for confirmation landed (the combat log's queueing
entries); this had no replacement and was not asked for one.

**Where it might go:** waypoints and ghosts are what the taskblock says carry the queue's load now,
so a stop marker on a ghost leg is the obvious home — that is also what `resolve_until` already
takes. Not designed here.

### Player-facing labels for actions that have none

**Needs:** nothing. **Unblocks:** any surface that names an action to a player rather than to a
developer.

`CombatAction.describe()` defaults to a debug shape — `EndTurnAction(unit=0)`, `HoldAction(unit=0)` —
and only `MoveAction` overrides `short_describe()`. That was invisible while the only reader was the
queue panel; **taskblock-57 Pass D moved the same text into the combat log**, where a player reads
`unit 0 queued action: EndTurnAction(unit=0)`.

**No regression** — the retired panel showed the identical string — but the log is a player-facing
surface in a way a debug row was not. The taskblock's own example reads `unit 0 queued action:
burst`, so the shape wanted is a short authored name per action. **Not invented here**: naming is a
design call and `docs/08`'s rule is that the view never births a string.

### The debug menu's drag-resizable height

**Needs:** the debug-menu redesign, which taskblock-57 explicitly excluded (*"It gets a placement
here and nothing more"*). **Unblocks:** nothing.

taskblock-57's placement table says the debug menu has a *"drag-resizable height"*. The placement
landed; the resize did not, because the same block's "Not this block's job" list rules out touching
the menu beyond putting it somewhere. **Recorded so the unmet half of a shipped table row is not
mistaken for an oversight.**

**Also unresolved and worth a measurement rather than a guess:** the table gives the menu a quarter
of the 16:9 safe width — 480 px at 1x — while `DebugControlPanel` carries a 520 px minimum, so it
overhangs its slot by 40. Positioned by the slot and sized by its own content today; either number
can move in the tuning pass.

### Author the intelligence tiers onto units
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
  why this sits behind *Attributes* in NEXT rather than in front of it.

**Acceptance:** a generated bout contains units of at least three tiers; the completion sample reports a
rate per tier; a Mindless unit and an Elite unit on the same seed visibly do different things in the
combat log.

### Multi-level cleanup
**Needs:** nothing. **Unblocks:** vertical movement being as legible and as interruptible as
horizontal movement.

**Most of this item has landed.** `BR46.02` (one-way ground) closed in taskblock-53 Pass D when the
generator took on navigability; ramps-where-missing landed with it; a climb became interruptible in
Pass E; ladders arrived as the route that does not need a capability. **What is left is the tail.**

- **A hop-down cannot be interrupted.** taskblock-53 Pass E made `ClimbAction` check the overwatch hook
  on the cell it steps onto — `HopDownAction` still checks nothing. Half a pass, and the inconsistency
  is the argument: *every real exposure the same* (`docs/09`).
- **The planner does not know a hop-down is one-way.** A unit that drops off a ledge to reach something
  strands itself for the rest of the bout. "Can I get back?" belongs in the decision rather than being
  discovered afterwards. **Stranding is a legitimate outcome** — a player knocking someone into a pit is
  the game working — but a unit choosing it *unknowingly* is not.
- **Prefer access routes: penalise ungated descent, exempt ramps.** Weight a candidate cell *slightly*
  worse when reaching it means dropping a level, and not at all via a ramp. Units then route through
  ramps without any rule naming ramps, and a ramp is two-way. **"Slightly" is load-bearing:** a hop-down
  to reach an otherwise unreachable target must still win when the reason is good enough. It is a
  consideration weight, so it is data. **Deliberately held until after the one-way awareness above** —
  with the generator already guaranteeing a route out, this is a *preference*, and landing both at once
  would hide which one did the work.
- **A confined unit should be legible, not silent.** Escalate to an **agitated roam** or **pace** —
  visibly restless rather than idle — and after a few turns of no progress, **shut down**. This does not
  fix terrain and must not be logged as though it did; it stops a stranded unit from being
  indistinguishable from a hang.

**Not doing: authoring a `CLIMBER` part.** Climbing parts are the exception, not the rule, and **a map
must be navigable without one** — which is what ladders are for. `Shell.can_climb()` reads a tag no part
carries, and that is correct rather than a gap.

**The AI queuing a vertical move is its own item** below, not part of this one.

### Every way of firing announces itself
**Needs:** nothing. **Unblocks:** reading a firefight out of the log without reconstructing it
from impacts; any future analysis of who shot at what.

**`BurstAction` is the only firing path that emits a fire event.** `AttackAction`, `StabAction`,
`SlashAction`, `GrindAction`, `Suppression` and `Overwatch` resolve shots and emit **impacts
only** — one of seven paths announces itself. A single shot that strikes nothing leaves a bare
`miss`; a sniper firing is indistinguishable from a sniper idling until something is hit.

- **`single_shot_fired`, and a framework the rest tag into.** The point is not one more event
  kind — it is that a new way of putting a round in the air announces itself **by construction**
  rather than by whoever adds it remembering to. `burst_fired` becomes one member of the
  vocabulary instead of the exception that happens to have one.
- **`ShotResolution` is the obvious seam.** Six of the seven paths already funnel through
  `resolve_and_log_point`; `Overwatch` reaches `log_impact_result`/`log_miss_result` directly.
  Whatever carries the announcement should sit where they already meet, not in each caller.
- **It has already cost real time.** `BR54.01` needed every sniper and shotgun shot inferred from
  its impacts before the bug could be characterised at all — the measurement existed only because
  the impacts happened to carry origin and hit points.
- **Open, and worth deciding once rather than per caller:** what a melee swing counts as. A stab
  resolves through the same shot path but "fired" is the wrong word for it, so the vocabulary
  probably needs a neutral term with the weapon's own method as data.

### A climb needs a position along it
**Needs:** nothing. **Unblocks:** partial climbs, mid-action terrain destruction, and the
destroyed-ladder fall — see the fourth bullet.

**A climb needs a position along it, and that unlocks four things at once.** taskblock-53 made a climb
interruptible, but a climb is still *atomic in cost*: `ClimbAction` charges the whole rise as one
action, which is why a four-level ladder priced at 16 MP and was unaffordable outright until
`LADDER_COST_SCALE` was corrected. **If a climb can be interrupted midway it should be payable midway
too** — pay what this turn affords, finish next turn.

- **That is the real fix for tall ladders**, not a cheaper scale factor. A tall climb costing several
  turns is correct; a tall climb being unpurchasable is not.
- **It sharpens the intended contrast.** A **ladder is direct but exposed**; a **ramp is indirect but
  safe**. A four-level ladder may be the *only* way up, and paying for it across turns while standing on
  it is exactly the exposure that should cost something. A ramp reaching the same height needs a long
  circuitous route — slower, safer, and a real choice rather than a strictly-worse one.
- **It is the missing piece under the destroyed-ladder fall.** That needs four things this project does
  not have: **terrain destruction affecting whatever stands on or attaches to it**, **a unit occupying a
  position partway up**, **interrupts firing mid-action** (landed, taskblock-53), and **falls / throws /
  knockback as real movement**. Partial climb and mid-action destruction are the same "a climb has a
  position along it" concept — build that and two of the four are one piece of work.
- **Falls, throws and knockback share machinery with *Forced movement* and with `eject`**, which waits
  on the same ballistic motion. Three items, one dependency.

### The AI can queue a vertical move
**Needs:** nothing — `ClimbAction`/`HopDownAction` exist, are interruptible, and ladders are
authored and placed by the generator (tb53 C/D/E). **Unblocks:** vertical maps being played
rather than merely built.

**No AI path has ever queued either action.** The planner moves exclusively via `MoveAction`, so
vertical movement has never happened in a real bout — a fact that survived taskblock-37 building
both actions and taskblock-53 making them safe to be caught in. With ladders now authored and the
generator placing routes, this is the difference between a usable map and a decorative one.

- **The scoring already knows about height.** `UtilityContext._closes_distance` reads PATH
  distance from a flood rooted at the target, and `Pathfinder.move_cost` already prices a climb
  and a ladder edge. What is missing is the **executor**: the step that turns "the best cell is
  up there" into a queued `ClimbAction` instead of a `MoveAction` that cannot make the step.
- **Split from taskblock-53 Pass E deliberately.** The interruption half landed there and is
  self-contained; this half touches `UtilityExecutors` and the planner's action construction,
  which is where a regression would be hardest to attribute. Doing both in one pass would have
  meant a planner change riding along with a movement change.
- **The proving ground is the test surface** — a generated map may or may not produce the
  geometry that exercises this; the authored one is built to.

### Derive plane/picker membership instead of answering it in four places
**Needs:** taskblock-52's ray chain (landed — it is the default resolver now). **Unblocks:** deleting
`ShotPlane` as a resolver, and closing `BR35.01`'s successors honestly.

**The same gap has been found four times from four directions** — `PartPicker` and the plane scanning
different pairs of collections; `InspectPanel`'s non-unit path (`BR51.25`); and `BR52.01`, where the
picker and the renderer disagreed about the *height* of a collection they shared. Nothing structurally
prevents a fifth.

**The shape, worked out in taskblock-52 Pass D and deliberately not built there:** not a new container
and not a per-box `Callable` visitor — the first duplicates state, the second costs an invocation
across ~1300 boxes on the hover hot path, which is the sin the plane was committing. Instead: drop
`RayCaster`'s `CombatState` dependency (it only touches `units`, `grid` and the log) so it takes what
`PartPicker` is already handed; add a `kinds` filter over the open `RayHit.KIND_*` vocabulary, applied
at the source so a caller that must not see floors never pays to test them; then `PartPicker.hit`
becomes a thin call into it, mapping `RayHit` to the dict its callers already expect. `InspectPanel`'s
non-unit path consumes the same.

**Two behaviour changes that want a decision, not an assumption:** the picker would inherit **tie
resolution** (it has none today), and **joints would become pickable** unless filtered off — tb09 D
says a joint is aimable, so the aim UI may want them, but hovering highlighting a joint handle is
visible. Default it off.

**Its own block, because attribution needs it to be.** `PartPicker.hit` runs on every mouse motion and
carries an open perf entry (`BR51.14`); `BR35.01` closed on a re-measured 774 usec against a 214-blocker
board, and that figure needs re-taking either side of this change. Folding it into the block that
replaced the resolver would have made a regression impossible to attribute.

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
- **A `launch test` verb on the debug panel.** Any test that builds a room, fires shots or stages real
  units should be launchable from a list: pick it, the view resets, the test runs under the ordinary
  spectator view. **The general form of the replay work** — taskblock-51 made a *failing* test's fixture
  watchable; this makes any staged test watchable on demand, which turns a test into a scenario the
  supervisor can inspect rather than a result they are handed.
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

### Plan the next AI turn while the current one is playing
**Needs:** a resumable planner (part of *AI v2, part two* — landed taskblock-45) and *Player view and sim
view* below, which is the same architectural idea one layer down. **Unblocks:** the turn-boundary hitch
stops being visible at all rather than merely being survivable.

**Resolution takes longer than planning does.** A resolution is animation time — a unit walking, a shot
resolving, a deflection playing out — and it is dead time for the simulation. A plan is milliseconds.
**So the next AI unit should think during the current unit's resolution**, and by the time the animation
finishes its decision is already made.

The player never waits for planning; they wait for *watching*, which they were going to do anyway.

- **This depends on the two-phase rule being true in practice, not just on paper.** TACTICS queues
  intents and mutates nothing; RESOLUTION executes and owns every mutation (`docs/09`). If nothing in a
  resolution mutates the state a planner reads mid-play, planning against it is safe by construction.
  **Verify that rather than assume it** — the taskblock-51 finding that killing a unit mid-turn left
  selection, overlay and turn state stale is exactly the shape of thing that would break this.
- **Standing rule 5 is untouched.** Units still act one at a time in initiative order. Thinking early is
  not acting early: the plan is computed ahead and *executed* in turn, so nothing resolves concurrently.
- **The unit planning ahead must plan against the state as it will be**, which is the real design
  question. A resolution in flight is about to change the board. Planning against the pre-resolution
  state produces a decision made on stale information — a unit routing through a cell the moving unit is
  about to occupy. Options: plan against the *post*-resolution state (which the queue already knows,
  since intents are queued before they execute), or accept a re-plan when the assumption breaks.
  **Decide this before building it**; it is the difference between a latency trick and a correctness
  bug.
- **Determinism must hold exactly.** A plan computed early and a plan computed on time must be the same
  plan for the same seed. If overlapping ever changes a decision, the overlap is wrong, not the test.
- **It composes with the snapshot split below.** That item lets the view draw from a resolved snapshot
  while the sim works; this one gives the sim something useful to do while the view draws. Same seam,
  opposite direction.

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

### Visible combat artifacts
**Needs:** nothing, but **placed after *Overwatch* and *Explosions*.** The overwatch cone is not worth
drawing while overwatch can still be declared repeatedly (`BR52.15`) and fires only on movement
(`BR52.12`) — you would be drawing a threat that does not behave like one. Explosion visuals want the
HE / fragmentation / hazard split defined first, or they depict a system that is about to change. **Unblocks:** the supervisor being able to judge combat by watching it rather than
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

**Worth weighing against *Attributes* in NEXT before building:** batching one squad of three measured
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

- **"It's High Noon"** — a *Gunslinger*-family action. **The unit cannot convert AP to MP this turn**,
  and **the first shot fired at any given target is free for the rest of the turn.** Rooted in place,
  spending nothing to acquire new targets — a duellist's stance rather than a burst of speed. Stresses
  the framework in two useful ways: a **negative** grant (removing a conversion the unit normally has)
  and a **per-target** cost exemption, which is state the action must carry for the duration of a turn
  rather than a flat modifier. The perk it hangs off is not designed yet.

**Four actions raised 2026-08-04, each stressing something different:**

- **"Parry Protocol"** — disables AP-to-MP conversion and **ends the turn**. Deflects up to
  `1 + (3 x remaining AP)` incoming rounds, at **100% damage retained** and up to **170 degrees**;
  further deflections behave normally. Same shape as *Overwatch: declaring it ends the turn* — remaining
  AP buys quality rather than being discarded — and it leans directly on the deflection machinery the
  ray chain already owns.
- **"Advanced Movement Protocol"** — converts **all** AP to MP at **2x** the normal ratio, and lets the
  unit move *through* enemies by vaulting or slipping past. Grants automatic movement actions
  (*Handspring*, *Slide*). Ending it converts MP back to AP at **half** rate, minimum 1. **The
  round-trip loss is the cost**, which is a cleaner lever than a flat duration.
- **"Donkey Kick"** (*Jitsu* perk) — kick backwards with both legs while **facing away**, knocking the
  target away and prone. **High Dexterity recovers to standing; low Dex lands you prone too.** A rare
  case of an attack whose *precondition* is facing the wrong way.
- **Drop Prone / Dive Prone / Stand up** — see *Momentum*, which they are the first non-attack spender
  of.

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


### Explosions: three types on one substrate
**Needs:** `Detonation` (built, taskblock-51); *Power and therms* for the reactor case. **Unblocks:**
`Weak points`' reactor payoff; napalm and hazard content; a reason for DT to matter against blasts.

**Raised as a bug (`BR51.26`) and withdrawn — this is a design change.** What exists today is one blast
that calls `DamageResolver.apply_damage_to_part`, bare subtraction with **no DT, no armor, no material**
(`damage_resolver.gd:213`). That is not a defect to repair in isolation; it is one of three types not
yet built, and it happens to be the one that *should* respect DT.

**Three types. Most exploding things produce more than one.**

| type | what it does | mitigation |
|---|---|---|
| **HE** | concussive shockwave, everything in radius — today's blast | **mitigated by DT** |
| **Fragmentation** | throws raycast projectiles out of the object | as bullets: damage, deflect, penetrate |
| **Hazard** | throws blobs of floor effects | whatever the effect does on landing |

**They modify each other, and that is the design rather than a flourish.** Higher HE gives fragments
**bonus penetration**; higher HE throws hazard blobs **flatter**, since a blob is a ballistic
projectile. So an explosion is a *vector* of three magnitudes, not a type tag — and the interactions
fall out of magnitudes rather than needing a rules table.

**Three examples, deliberately not three tiers:**
- **A reactor meltdown.** Weak HE, heavy fragmentation — it turns its own casing, and whatever of the
  unit surrounds it, into fragments.
- **A napalm barrel.** Weak HE, no fragments, heavy hazard — blobs of napalm everywhere.
- **A rocket.** Delivers its initial damage as a bullet, then **pure HE**: no fragments, no blobs, very
  high force.

Each example is a different combination, which is what shows the three axes are independent.

**Two things it already leans on:**
- **Fragments are bullets, so they use the shot resolver** — `ShotPlane`, deflection, penetration,
  material. Not a second projectile system. `docs/02` and the one-resolver rule both apply.
- **Hazard blobs are floor effects**, so they want whatever `Status effects and boosts` lands.

**And one it exposes:** `BR34.05` (misses vanish) matters more here, because a fragment that finds
nothing to hit is the same defect multiplied by however many fragments an explosion throws.

### `eject` becomes a real motion once things can be thrown
**Needs:** ballistic motion (grenades, forced movement). **Unblocks:** `eject` meaning what its name
says.

**`eject` currently names a motion the game does not have.** A matrix leaving a destroyed shell is meant
to be *thrown* — an arc, a landing cell some distance away, the same ballistic path grenades and thrown
objects will use. Nothing is thrown yet, so today every ejection is a drop wearing the word.

- **The distinction is shell versus surrogate.** A **shell throws** its matrix clear; a **surrogate just
  drops** it, like any other part falling from a destroyed parent (see `SUPERSEDED.md`). Both keep
  "matrices are never lost" — they differ in motion, not in outcome.
- **When ballistics land, only the shell path grows an arc.** The surrogate path stays a drop
  permanently, which is the point of the distinction rather than an unfinished half.
- **Until then the naming should not lie.** `DamageResolver.eject_matrix_if_needed`'s surrogate branch is
  a drop; calling it an ejection is how the retired design keeps looking current.
- Shares its dependency with *Forced movement — flung, thrown, knocked prone*, and probably its
  implementation: an arc from a cell to a cell, with something to do on landing.

### Overwatch: declaring it ends the turn, and spending buys quality
**Needs:** nothing. **Unblocks:** overwatch reading as a commitment rather than a cheap extra.

**The bug half is `BR52.15`** — `is_legal` never checks whether the unit is already watching, so
overwatch can be declared repeatedly for `AP_COST` each time. This item is the design half.

- **Declaring overwatch ends the turn.** Watching a lane *and* acting is the contradiction; committing
  to watch is the cost.
- **Remaining AP buys a better watch** rather than being discarded. Declaring early spends more and
  watches harder — wider arc, faster reaction, better shot, or more triggers; which axis it scales is
  open. That turns "2 AP left and nothing worth doing" into a decision instead of a rounding error.
- **The cone must be visible** — see *Visible combat artifacts*. An overwatch whose watched region is
  undrawn is a threat the player cannot route around, and scaling its quality by AP means nothing if the
  quality cannot be seen.

### Manipulator variety, starting with the three-pronged claw
**Needs:** nothing; the part framework and `ActionCatalog` already carry this shape. **Unblocks:**
hand-type parts being a choice rather than a uniform prerequisite.

**A three-pronged manipulator** — *trifinger* or *three-jaw gripper* in industrial usage; pick one short
name and use it consistently.

- **Grants a jab action**, with a **vicious jab** as a gated variant.
- **Cannot fire guns, but can support them.** `PartGraph.can_operate` already separates operating a
  weapon from supporting one, so this is a capability-tag combination rather than new code.

**The gating on the second attack is the real question, and the two candidates are different mechanics:**
- **Intelligence-gated** — the unit is smart enough to fight dirty. Ties to the tier table.
- **Perk-gated, "Dirty Fighter"** — an alternate attack across *many* hand-type parts. Better fit for
  `docs/06`'s framework: one perk, an action grant, applying to a class of parts rather than one part.
  Also a natural **perk family** member.

Whichever wins, the part is data and the action already has an executor shape. The point of the item is
that hand-type parts should differ from each other; the claw is where that starts.

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


### The generator is stitching, not carving
**Needs:** *The section format* (landed, tb54), *Map and section editors* (landed, tb56).
**Unblocks:** retiring most of `MapGen`.

**`MapGen` as written is on its way out.** Once sections can be authored, generation becomes *choosing
and joining* authored fragments rather than carving rooms and corridors procedurally.

- **Most of the ramp-versus-ladder decision becomes obsolete.** A section arrives with its vertical
  routes already authored — the generator does not decide where a ladder goes because the section
  already knows. taskblock-53's rise≤2/ramp, higher/ladder rule is a stopgap for the generator that is
  being replaced, and its ladder branch is currently arithmetically dead anyway (`MAX_HOP_DOWN_LEVELS`
  and `RAMP_MAX_RISE` are both 2.0, so a repair's rise never exceeds what a ramp covers).
- **Sections arrive with edges, not with navigability.** taskblock-54's `can_join` decides whether a
  seam is legal; nothing yet decides whether a *board* assembled from legal seams is navigable. The
  asymmetric flood is the check and it does not care how the board was produced, so the generator
  owes it exactly as `MapGen` does today.
- **Navigability stays the generator's obligation**, whatever it is generating. taskblock-53's
  asymmetric flood is the check and it does not care how the map was produced.
- **Do not invest further in the current generator.** Fix invariants; do not extend it.

### Section vocabulary residue
**Needs:** varies per bullet; none blocks the editor. **Unblocks:** nothing on its own.

Four things taskblock-55 landed narrower than the concept, kept because each is a place the
implementation is knowingly smaller than what it models.

- **`is_room` grouping is order-based, not adjacency-based.** A section declaring `is_room` starts a
  room; one that does not joins the room already open. Correct for a pair — with two sections there is
  only one possible adjacency — and it wants a real adjacency graph the moment three exist.
  **Needs:** *The generator is stitching, not carving*.
- **`encounter_types` is consumed by nothing**, deliberately. Authored and validated so sections
  written today need not be revisited. **Needs:** an encounter system, which does not exist.
- **`SectionRoller.part_for_tag` is a flagged hook** — a clutter tag resolves to a part of the same id
  and to nothing otherwise. Choosing which part a *kind* resolves to is a content library's job, and
  the dull rule exists so this does not quietly become where content selection lives.
  **Needs:** a content library.
- **No thin wall part is shipped**, so *two 0.2 walls merge to 0.2, not 0.4* cannot be exercised
  against real content — `wall` is a full-cell 1.0 x 2.4 x 1.0 box. The merge test asserts the
  invariant instead (merged thickness equals one part's own), which holds at any thickness.
  **Resolves itself** when *Wall coatings, and walls that are not cell-wide* authors one.

### Seeing what you authored — three view gaps — **LANDED (taskblock-56 Pass E)**
**Needs:** nothing. **Unblocks:** authoring sections without guessing.

All three landed; detail in `CHANGELOG.md`. What remains open out of it:

- **The dark forest green floor is temporary and its revert is one line**
  (`WorldPalette.TEMPORARY_TILE_TINT = false`). **Revert it when tiles have their own look** — that is
  a real outstanding action, not a note. It belongs with whatever gives tiles a material treatment.
  **Needs:** tiles having a look of their own.
- ~~**Claim volumes are drawn by a module no mode currently mounts.**~~ **Closed by taskblock-56
  Pass F**: the editor mode mounts `ClaimVolumeModule` and authoring a claim draws it. The guard that
  banned it from *every* mode is now "every play mode", with the authoring modes pinned in a
  one-entry list.

### The bout launcher spans the screen
**Needs:** nothing. **Unblocks:** nothing.

Full-screen-width after the module collapse. Cosmetic, and the supervisor has said it is **not worth a
pass of its own** — fold it into whatever next touches that surface.

### Structure supports itself
**Needs:** *Floors reference a location* — **the inversion landed in tb58 B**; a placement carries its
own `cell` and the per-cell dictionary is an index over the store. **Unblocks:** moving decks
(vehicles), a hulk that can be cut apart, collapsing structure.

The larger piece of work the inversion existed to make possible. **None of it is built.**

- **Support is a graph over placements, not cells.** Floor A holds floor B. That is what makes cutting a
  hulk in half produce two *components* rather than a hole, and it is the same connected-component
  question the navigability flood already answers, run over a different graph.
- **There is no privileged component — the observer is the anchor.** A unit's own component is its rest
  frame. Two halves of a severed hulk drifting apart both feel stationary to whoever is standing on
  them, which is correct and cheaper than picking a winner: **a majority rule would have needed a
  tiebreak for an even cut, and this needs none.** A unit on three loose plates in space walks them
  normally, given mag boots or the equivalent.
- **Cantilever is accumulated load, not a distance rule.** Each tile carries everything beyond it, so a
  light catwalk reaching five cells and a heavy ship floor reaching two **falls out of weight** rather
  than being authored per part. It also stays true when someone parks a heavy shell on the end, which a
  distance rule would not.
- **Units load the structure**, and a heavy shell can break the catwalk it is standing on. That makes
  load *dynamic*, which is why it evaluates **every turn** — support cached at load means a weak
  catwalk collapses at an arbitrary later moment rather than when someone steps on it. Cache per turn,
  invalidate on movement.
- **"Falls" implies a down, and whether there is one is a computed property** — see gravity below.
  Inside-the-hull versus outside is not the distinction; a hull breach makes those the same place.

#### Gravity is conducted through the ship's metal

**A `Gravity Generator` is a real, damageable part**, and its field **propagates through the structure**
— which is the *same graph* structural support already builds, flooded from a different source. A unit
has gravity if a grav gen is connected to the plate it stands on, or is near enough (just above, or
directly beside).

Everything useful falls out of that rather than needing rules:

- **Cut the ship, and the half without a generator loses gravity.** No special case for severance.
- **Destroy the generator, and everything it fed loses gravity at once.** It is a part, so it is a
  target.
- **Any combination of gravity and atmosphere is reachable** — grav/no-grav crossed with atmo/no-atmo,
  four states, none of them authored.

**Gravity conducts through metal; atmosphere conducts through space.** Near-inverses sharing one shape:
a sealed room holds air while its plating is irrelevant, and a severed plate loses gravity while its
enclosure is irrelevant. Two fields, two media, one propagation model. **Worth building the first one so
the second is a second source rather than a second system.**

- **Walking without gravity is a capability**, not an impossibility — mag boots or the equivalent, the
  same shape `CLIMBER` has. A unit without it in zero-g is in trouble; a unit with it is not.
- **This is the project's first taste of zero-g**, which arrives properly later. Build it as a computed
  field from the start rather than as an exterior special case, or zero-g becomes a retrofit.
- **Two floods per turn** — support and gravity — over placements, both the shape the navigability
  flood already runs. Budget accordingly; they are not free and they are not new machinery either.

#### The AI knows if it is smart enough — or heavy enough

**Structural awareness is gated twice**, and the second gate is the interesting one:

- **By intelligence**, like everything else in `docs/11` — a Mindless unit does not reason about what it
  is standing on.
- **By weight.** *"I'm a big guy, so I know I'm heavy."* A large shell is inherently aware that things
  give under it, regardless of tier. A genuinely different axis from intelligence and profile, and it
  fits the existing frame: **intelligence gates information, and weight is a second thing that grants
  it.**
- **Whether a unit has gravity is information too.** A unit that does not know it is about to step off
  the gravity field's edge is the same class of mistake as one that does not know the floor will give.

A floor that will collapse under a unit is a **pathfinding cost**, not a walkability flag — the planner
currently reads walkable as binary, and "walkable but it will give way" is the interesting middle.

### Grids are not unbreakable
**Needs:** the placement inversion (landed, tb58 B). **This is happening** — possibly first as an experimental
setting, so it can ship and be played with before everything downstream of it is ready.

**More than one grid.** A ship half is a grid, the other half is another, **and vacuum is a third.**
They may be offset by partial tiles and need not share a rotation — **a 45-degree grid over the
90-degree one** lets things a unit walks inside be placed prettily rather than snapped square.

- **Movement between grids rounds up.** If two grids are within reach, jumping costs the rounded-up MP.
  A simple rule that avoids exact partial-tile arithmetic entirely.
- **Vacuum-as-a-grid pays twice.** Zero-g movement stops being *movement without a grid* and becomes
  ordinary movement on a different one — so mag boots, drifting and jump jets reuse the pathfinder
  rather than needing a parallel one.
- **This is the L1 portal layer** the 2026-07-27 pathfinding consultation proposed, made spatial: a grid
  boundary is a portal, a grid is a cluster. If it lands, it inherits an architecture that was already
  worked out and deferred on measurement.

#### What it is actually for

- **Jump jets between ships.** A unit launches off one hull and lands on another — which is a grid jump,
  not a special-cased animation.
- **Being boarded at a compound angle.** An enemy ship docks skewed and above, and the fight stops being
  a floor plan: **you shoot up, and you hide under roofs rather than behind walls.** That is a different
  game inside the same rules, and it is the scenario that justifies the whole idea.

#### Cover is flat, and that is the real dependency

**`Cover.is_covered_from(candidate_cell, threat_cell, ...)` has no height in it at all.** It walks
`Grid.line()` between two `Vector2i` and checks blockers along the way. A threat directly above is, to
the AI, in the same cell — and therefore not something to take cover from.

**The resolver is already ahead of the AI here.** The ray chain marches real 3D geometry, so *shooting*
up works today; it is the AI's cover model that is a floor plan. **Cover has to become directional in
three dimensions** — a roof is cover from above exactly as a wall is cover from the side — before a
compound-angle boarding is playable rather than merely renderable.

#### What keeps it cheap

Mostly already true. Only **two** places in `src/` do inline cell arithmetic; **thirty-one** go through
`Grid.neighbors()`, `in_bounds()` and `distance_chebyshev()`. **A second grid is a change inside those
functions, not a sweep** — so the rule is to keep it that way:

- **Ask a grid; never compute adjacency from coordinates inline.** That one habit is most of the
  insurance.
- **`Grid.distance_chebyshev(a, b)` is `static` and takes two bare `Vector2i`**, so it assumes a single
  coordinate space in its signature. It is the one thing that needs a frame; worth knowing before it
  acquires more callers.
- **`CombatState.grid` is singular.** Fine today, and it is the field that becomes a collection.

### Vertical cover, and a sight line that shares the shot's origin
**Needs:** *Sight-blocking is geometry* (landed, tb58 C). **Unblocks:** retiring the last
over-inclusion in `VisibilityField`; cover that means something on a catwalk.

**The array is gone and geometry answers.** What is left are the two places the new model is still
answering a flatter question than it could.

- **`Cover.is_covered_from` is still flat.** Its sight half reads the geometry-backed field now, but
  its own blocker/unit walk takes two `Vector2i` and has no height in it. **Same flatness, same
  cause** — a per-cell question about a 3D world. Belongs with the multi-grid work.
- **`VisibilityField` keeps over-inclusion 3 as a safety margin rather than a limit.** A cell at
  another elevation is still reported visible wholesale. The occluder test could answer across bands
  now; what stops it is that the field casts **eye-to-eye** while a shot runs **muzzle-to-aim-point**,
  and a raised arm or a shot over a low wall is where those diverge. **Retire the margin when the
  field and the shot share an origin** — not before, because narrowing it trades the one failure mode
  that matters (under-inclusion) for casts on a once-per-turn build.
- **`LoS.SIGHT_HEIGHT` is a flagged constant**, `UnitGeometry.DEFAULT_MUZZLE_HEIGHT`. The real answer
  is a per-shell sensor height, at which point the constant becomes the fallback.
- **Gases and windows** arrive as volumes carrying a transmission property. Opaque by being there,
  transparent by declaration — the exception running the right way.

### A GROUND placement may share a cell at another height
**Needs:** *Floors reference a location* (landed, tb58 B). **Unblocks:** two decks in one cell without
a catwalk's side-attachment grammar.

**One line, deliberately not taken in tb58 B.** `GROUND` now means "attaches to nothing", and the
refusal it used to express survives as occupancy: `GridPlacement` refuses a second placement on a cell
that already holds one. Loosening it to *"at this height"* is what lets a floor at 0.0 and a floor at
2.0 share a cell.

**It was left alone because Pass B was a storage inversion with no intended behavioural effect**, and
this is a behaviour change wearing a refactor's clothes. Nothing today depends on either reading —
every `GROUND` caller clears the cell first — so it is reversible in both directions, which is exactly
why it should be a decision rather than a side effect.
`test_placement_position.gd::test_ground_still_refuses_a_second_placement_on_an_occupied_cell` pins
the current reading, so the change has to be a deliberate edit to a named test.

### The editor's tool set, reorganised
**Needs:** *The UI layout* (landed). **Unblocks:** authoring without knowing which of ten verbs does
what.

Ten tools become **seven**, grouped by what a click *means* rather than by what it touches.

| tool | a click |
|---|---|
| **Select** | Click to inspect; move with the gizmo. **X and Y movement snap to one-tile increments and auto-connect to the new neighbours.** |
| **Place Terrain** | Walls, floors and anything tagged terrain. **Attaches to the highlighted face** of whatever is aimed at, with a **ghost** so the result is never a surprise. |
| **Scale** | Anything scaleable. The gizmo attaches to the **face clicked** and drags it; a top face scales X and Y **mirrored**. Numeric readout while dragging. |
| **Delete** | Highlights on hover, deletes on click. Works on everything — map things, tiles, parts. |
| **Place Map Thing** | Claims, extract zones, spawn tiles, later scripted tiles. **Everything the player never sees.** |
| **Place Big Part** | Cover and cover spawners — anything that stops a unit entering a cell without being terrain. |
| **Place Part** | Everything else. |

**Retired as verbs:** `spawn_a`/`spawn_b`/`spawn_none` and `chance` fold into *Place Map Thing*;
`sight_blocking` retires with the opacity array above.

**A chance becomes a thing you place**, not a verb — a generic *this could be any cover* item with
defaults, and selecting it lets you change them: which categories, what chance.

**Every Place tool opens a parts list on the right**, in the Inspect slot, toggleable from UI buttons.
**It goes where Inspect goes because while placing you cannot be selecting** — the two are mutually
exclusive by construction, so they can share a slot without a conflict.

#### Faces define connections

**Attachment becomes face-to-face rather than cell-to-cell**, which is what *Place Terrain*'s
face-highlighting needs and what a grid-agnostic world needs anyway. `RayCaster` already solves the
angle of incidence at each hit, so **which face was struck is derivable rather than new** — but it has
to be *reported*, and nothing reads it today.

This composes with the tb58 B placement inversion and *Grids are not unbreakable*: once a thing's
position is its own and grids are plural, **a face is the only thing left that two placements can agree
about.**

### Parts get real dimensions, and HP follows volume
**Needs:** *The editor's tool set* for authoring them. **Unblocks:** designed structural failure.

- **Walls resize on X, Y and Z.** A 3 x 3 x 0.5 wall exists as one part, and **destroying it leaves a
  hole of a designed size** — which is the point: map failure becomes something an author shapes rather
  than something that emerges a cell at a time.
- **HP scales by volume.** The alternative is three walls pretending to be one, and this keeps a big
  wall meaningfully tougher than a small one without authoring a number per size.
- **Support pillar upgrades from cover to a terrain part**, since it holds things up.

#### The ledge veneer

A flat wall attaching to a tile's top edge and sideways to tiles above it. **Name is provisional.**

- **It grows both ways and snaps to what it meets.** Clicking a ledge's side grows it **down**; it can
  also grow **up**; and **if it connects at both ends it snaps to both.**
- **Defaults when it connects to nothing:** growing up from an edge, **0.8** — deliberately odd so it
  reads as a default rather than as intent. Clicking the side of a tile with nothing under it,
  **match the picked floor tile's own height**.
- **HP by volume, like everything above.**

### Wall coatings, and walls that are not cell-wide
**Needs:** *The section authoring vocabulary*. **Unblocks:** rooms that read as different places; shots
that cross a room boundary meaningfully.

**One wall part, two faces that can look nothing alike.** A wallpapered bedroom on one side, a
strut-reinforced furnace room on the other, with a single part underneath. **Coatings** live atop the
wall the way cladding lives atop a part — the noun is not settled (*veneer*, *lining*, *finish* and
*revetment* are the alternatives; *facing* is taken by `Surface.facing` and *cladding* by parts).

This is what makes merge work at the fiction level rather than only the geometry level: merging two
rooms' walls into one part would otherwise mean one of them loses its look.

**Bulkhead walls are centred on a cell and fill it. Interior walls need not be.** A thinner wall should
be placeable **on a cell edge or on its centreline**, which matters more than it sounds:

- A cell-wide wall makes every room boundary a full cell of dead space.
- **A loose shot crossing a thin wall into the next room is a real outcome** — irritating whoever is in
  there, or hitting an ally through it. That only exists if the wall is thin enough that the space
  beyond it is reachable.

#### Sections stack, and that means intervals — not voxels — landed, taskblock-55 Pass D
`ClaimResolver.interval_of` reduces a section to the lowest and highest world Y it occupies, and
`describe_interval_overlap` refuses two sections whose intervals overlap — **except where a `merge`
volume spans the shared band**, which is the shared-wall case and is the common one, not a corner.
`up`/`down` are ordinary sides (two constants and a row in `opposite`); `span_of` answers
`width * rows` for them, since two stacked sections meet over their whole footprint.
`SectionEdge.opening_height` distinguishes a door at ground level from one at the top of a
staircase. Height stayed continuous — no voxels, no storey index.

**Measured while building it:** `ship_floor` is a 0.2 slab hung *below* its placed height, so a deck
resting on a 3.0 ceiling tops out at 3.2. The stacking lift accounts for the deck's own thickness,
which is precisely what a quantized model could not express.


#### Determinism

Every per-cell chance draws from the seeded RNG, in a **stable iteration order**, or the same seed
produces different boards. Same rule as everywhere else, and easier to get wrong here because the
iteration is over a dictionary of cells.

### Map and section editors — **LANDED (taskblock-56 Pass F)**
**Needs:** nothing further. **Unblocks:** *Main menu*.

**The module system's own proof, and it held.** The editor is a `ViewModes` row declaring six
existing modules plus one new `EditorModule` — no subclass, no new chrome, no duplicated panel.
Detail in `CHANGELOG.md`. `ClaimVolumeModule` is mounted and reachable, which closes the second
open item under *Seeing what you authored*.

What remains open out of it:

- **An authoring session still starts on top of a bout.** The editor mode installs over whatever
  `BattleScene` already built, so units already on the board are relocated onto the authored one by
  the same `BoardSwap` a map load uses. Harmless and visibly odd. The fix is an entry point that
  builds a world with no bout in it, which is *Main menu*'s job — so this is a note on that item
  rather than a defect against the editor. **Needs:** *Main menu*.
- **A claim is authored one cell at a time and resized only through the controller.** `add_claim`
  places a one-cell volume from the deck to a flagged 2.4; `resize_claim` takes an arbitrary `Box`
  and is fully tested, but no drag gesture reaches it. Every authored extent is therefore expressible
  and only the rectangular-drag *affordance* is missing. **Needs:** nothing; it is UI work.
- **No section-stitch preview.** The editor authors one section; seeing two joined is
  `SectionSerializer.stitch`'s job and belongs with the generator item below. **Needs:** *The
  generator is stitching, not carving*.

### Main menu
**Needs:** *Map and section editors* (landed, tb56). **Unblocks:** nothing.

Rolls the in-game tools into one reachable place — bot builder, bout sim, map and section editors.
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
**Needs:** nothing, but **design it alongside *The meta layer***, which describes the same economy from
the other end. Settled separately, one will contradict the other. **Unblocks:** stash UX, the meta economy, substance content.

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


### The over-the-shoulder camera
**Needs:** nothing.

Two camera items from taskblock-51's fourth hunt. **The performance suite that shared this item is
built** (taskblock-51; `PerfStats`/`PerfPanel` — see `CHANGELOG.md`).

- **The over-the-shoulder camera needs a broader allowed angle and significantly more damping / edge
  resistance.**
- **A wall cutout attached to the player's camera** would stop the view going solid grey when the
  over-the-shoulder camera ends up behind or inside a wall. Note this is a *different* cutout from the
  unit-centred one `BR32.05` is about, and may be the better shape for both.

### Action-cost affordances, and camera keys
**Needs:** nothing.

Supervisor design notes from taskblock-51's third hunt — neither is a defect, so neither is in
`BUGS.md`.

- **Hovering a hotbar action shows its AP or MP cost**, and *selecting* one makes the matching pips
  pulse: an action costing 3 AP slow-pulses the 4th–6th pip orange; one costing 3 MP pulses 2 MP teal
  and one AP orange, because that is how the conversion actually spends. The cost model already exists
  — `ActionCatalog` knows what a provider authors and `test_ap_mp_pips.gd` already pins that the pip
  row shows exactly what the unit has. This is presentation over facts the game already holds.
- **`WASD` pans the camera in the player view; `Spacebar` toggles play/pause in the spectator.**

### Aiming detaches from unit lock; `Set Cell Level` steps by 0.5
**Needs:** nothing. **Unblocks:** possibly obsoletes `BR33.01`.

Two supervisor design notes from taskblock-51's hunt, recorded here rather than in `BUGS.md` because
neither is a defect.

- **The dartboard should stop being locked to one unit.** Clicking a unit opens the aim view as now,
  but **mousing off it onto anything else targetable cycles the aim to that thing** — targets are
  chosen by pointing rather than by re-entering aim mode. **This may obsolete `BR33.01`** (aim-view
  scroll cycles walls, layer labels read as part names), which the supervisor says is *"not what I
  originally intended, more likely to be obsoleted than fixed"* — so `BR33.01` should not be fixed
  ahead of this decision.
- **Tabs on the debug panel.** Split the existing menu into `Part Manipulation` and `Other` to start.
  More categories are welcome; **do not filter it down too far** — a panel with twelve tabs is a panel
  nobody can find anything in.
- **The panel drags anywhere on screen.** Currently fixed, and it covers exactly the things being
  inspected.
- **Cut the clicks-to-goal on several verbs.** Redundant cells in memory, a button *and* a checkbox
  doing what two buttons would do. These are per-verb ergonomics, not one change — worth a pass through
  `DebugVerbs` with "how many clicks to the common case" as the only question.
- **`UI Element Control` landed in taskblock-51** as a `DebugVerbs`-shaped list entry, so a new
  toggleable element is a table row rather than UI code. The three notes above are what is left of that
  same session's list.
- **`Set Cell Level` should increment by 0.5**, not 1. A one-line step change on the debug panel's
  spin box; noted here so it is not lost between hunts.

### The framerate reads above the display's cap, and the `avg less top 1%` rule
**Needs:** nothing; `PerfStats` is built (taskblock-51). **Unblocks:** trusting the perf panel's fourth
figure.

**Raised as `BR51.17` and withdrawn from the ledger — this is a decision, not a defect.** The metric is
doing exactly what it was specified to do on a distribution the specification did not anticipate.

`avg less top 1%` cuts on **speed**, not on a count of frames: every frame below `0.99 × fastest`. That
is correct and it is what makes the supervisor's worked example read 10.0. It degenerates into the plain
mean when the fast cluster is *wide* — if idle frames spread 200–2000, the cut line sits at 1980 and
trims almost nothing.

**And the fast cluster is wide, which nobody expected:** taskblock-51 measured `avg less top 1%` at
**177–185**, above the display's 160. **The game is not capped at 160 — the monitor is.** Why a
vsynced-looking session reports frames well above the refresh rate is unexplained and is very likely a
Godot presentation behaviour (a frame counted on submission rather than on present), not a game defect.

- **Not urgent.** Too many frames is rarely a problem, and the supervisor's play sessions sit at a
  consistent 160 with dips being the anomalies worth chasing. The 1% low and worst-frame figures are
  unaffected by any of this and are the ones being read.
- **Two things to settle when it is picked up:** what Godot is actually counting, and what rule replaces
  the top-1%-of-speed cut once that is known. Answering the first probably determines the second.
- **Do not tune the constant to make the number look right.** A cut line chosen to produce a pleasing
  figure is a balance number invented to hide a measurement.

### Two aim questions from the seventh hunt
**Needs:** nothing. **Unblocks:** `BR51.01`'s diagnosis, possibly.

Neither is a filed defect; both are conformance questions with short answers that nobody has written
down, and the first bears directly on an open bug.

- ~~**Where does a shot actually aim, and does player control differ from AI control?**~~ **Answered
  (taskblock-56 Pass B), written into `docs/02`.** They agree, and structurally:
  `ActionCatalog.build_firing_action` is the only firing-action construction site in `src/`, and every
  firing action resolves through one expression. The AI leaves the offset at its default; the player has
  a knob. **That removes a suspect from `BR51.01`.** It also turned up that the aim point is the centre
  of the target's *frontmost region* — not the body's centre and not a point on the muzzle-to-target
  axis — which **confirms `BR54.01`'s stated unverified suspect** without accounting for all of it. The
  design question that finding opens (should the aim point be the frontmost region, the centroid, or a
  point on the axis?) is a supervisor call and is recorded in `docs/02` as a finding, not a spec.
- ~~**Is explosion damage affected by DT?**~~ **Answered: no.** `Detonation` calls
  `DamageResolver.apply_damage_to_part` — bare subtraction, no threshold or armor. Not filed as a
  defect: it is the HE type not being built yet, and it belongs to *Explosions: three types on one
  substrate*.

### Keep the rotated combat logs from ballooning
**Needs:** per-session log rotation — **built** (taskblock-52, `FileSink.ARCHIVE_DIR`, `out/logs/`).
**Unblocks:** nothing; this is housekeeping that will otherwise become a chore nobody scheduled.

Every session now leaves a file in `out/logs/`. Nothing removes them, so the directory grows once per
run forever. **The supervisor's own framing is the answer: "it'll probably be the same as the finished
taskblocks."** That is the `reports/` rolling-window rule and the `taskblock_done/` archive — keep a
fixed number of the most recent, delete the rest in the same commit that adds a new one.

- **The obvious shape:** `FileSink` prunes `out/logs/` to the N most recent on rotation, N being a
  flagged constant. Sortable names are already in place (`combat-YYYYMMDD-HHMMSS.log`), so "most
  recent" is a directory listing and a slice, not a stat call per file.
- **Two things to decide rather than assume.** What N is — `reports/` keeps five, which is a
  precedent rather than a reason. And whether pruning belongs in `FileSink` at all: a logger that
  deletes files is doing two jobs, and the alternative is a housekeeping call at startup that
  `BattleScene` makes explicitly.
- **Not urgent.** A session log is tens to hundreds of KB, so this is a real problem at hundreds of
  sessions rather than at ten. Filed now because the growth was introduced deliberately and should not
  be rediscovered later as a mystery.

### Act on the suite audit
**Needs:** the audit index — **built** (taskblock-49, `test/suite_audit.csv`, 2431 rows classified
under 328 rules). **Unblocks:** a suite whose cost is proportional to what it actually guards.

The index exists; **nothing has been cut, by design** — taskblock-49 was scoped to evidence. This item
is the acting-on, under `docs/TEST-AUDIT.md`'s cut rule: *a test may only be cut if breaking the rule it
guards makes a different test fail*, **demonstrated rather than asserted**, with the covering test
recorded beside the cut.

Three specific things the index put on the table, in value order:

**Two of the three findings below have since been acted on, and the third is no longer expensive.**
Recorded corrected rather than deleted, because the *shape* of each is still the thing this item is for.

- ~~**Eight name defects**~~ **— closed, taskblock-50 Pass E3.** The `description` column is empty
  across all 2668 rows. The lesson stands: a filled description is a defect report, and the column
  should stay empty.
- ~~**`test_full_mission::test_bout_completion_rate_meets_the_measured_floor`, a 62.6 s sole guard**~~
  **— retired, taskblock-50 Pass D.** Replaced by `test_seeds_to_first_completion_stays_low`, and
  `test_full_mission.gd` now costs **1.2 s**. It was exactly the row someone proposes cutting on cost
  alone, and it was retired by making the measurement cheaper rather than by cutting the guard.
- **`test_completion_sampler::test_the_in_window_verb_reports_the_same_sample_and_changes_nothing`**
  still exists, but its file is **6.2 s**, not the 102.3 s recorded here. **The corpus lever is no
  longer worth a supervisor call.** Six other tests guard the same rule for ~0.001 s each, so the
  cut-rule question remains open on its merits, at a fraction of the stakes.

**The audit's headline finding was not the predicted one, and that shapes this item.** `TEST-AUDIT.md`
expects expensive rows sharing a rule with cheap ones to be the output. They exist — but in every case
checked the cheap peer guards the rule at *unit* level and the expensive one guards it end-to-end
through a real bout, so breaking bout-level determinism does not redden the cheap peer and the cut rule
correctly refuses the cut. **The real question the index answers is per rule: does this rule need a
bout-level rung at all?** Answering that for the ~10 rules that own a bout-playing test is the work.

### Review pass over the test suite — *the survey half; the index landed in taskblock-49*
**Needs:** nothing.

**Superseded in part.** The per-test index and the rule classification this item asked for are built
(taskblock-49; see `CHANGELOG.md`). What remains here is the *qualitative* half below — tests that pin a
bug as though it were a rule — which the index does not answer, because a test asserting the wrong thing
still classifies cleanly under the rule it claims to defend.

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

---

**Three small items folded in here**, because they are the same surface and none is worth its own entry:

- **Retire `MIN_COMPLETION_RATE`.** **Nothing reads it.** taskblock-50 Pass D replaced the rate with
  `seeds_to_first_win`, and every surviving mention across four files is a *comment about* the constant
  — `test_full_mission.gd` says so in its own header. **It does not need a number picked; it needs
  deleting.** Keep the cautionary story where `suite_budget.gd:10` and `completion_sampler.gd:89`
  already tell it better: a threshold on a small integer count sat less than one seed from red and the
  response was to lower it.
- **The audit's Tier 2 merges** — three clusters that are same-rule *and* same-scope, so the cut rule
  applies rather than correctly refusing. Roughly 35 s and ten tests. **Filed because the CSV they came
  from is deliberately stale, so this finding does not regenerate itself.**

  | rule | rows | cost |
  |---|---:|---:|
  | the run panel reports the real rung and the real verdict | 9 | 20.6 s |
  | the gate's exit code reflects the run's real verdict | 4 | 12.3 s |
  | every spawn zone is walkable and reachable | 8 | 17.0 s |

  Costs are as-measured then and want re-taking; taskblock-50 moved a great deal underneath them.
  **Merged tests keep distinct assertion messages** or a failure stops naming which fact broke.
- **`test_completion_sampler.gd` is no longer the problem it was cited as.** taskblock-47 took it
  437 s → 207 s and taskblock-50's corpus and stubbing work took it to **6.2 s**. What remains is
  genuine — it plays real missions to check the sampler reports them correctly. **Confirm it is right
  and close the question**, rather than cutting.

**A note on cost figures in this file.** Three of the numbers above were stale enough to invert a
conclusion — an item proposing a supervisor decision about a 102-second lever that had become a
six-second one. **A cost recorded here should carry the taskblock that measured it**, or it reads as
current forever.

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

**Prone actions are the first thing that spends momentum on something other than an attack**, which
widens the concept:

- **Dive Prone** consumes momentum to lunge up to two cells and land prone. **Drop Prone** costs nothing
  and simply puts the unit down — and *does* trigger overwatch and reactions, which is what makes the
  free version a real choice rather than a strictly better one.
- **Stand up resets momentum**, and costs MP (4 against the current allowances, so the number moves when
  the economy is tuned). Going down is free; getting back up is the price.
- **That makes momentum a resource with two sinks**, not just a damage multiplier — spend it on the next
  attack, or spend it on distance. The spend-on-next-attack rule above still holds; this is a second
  thing it can buy.

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
**Needs:** nothing mechanically. **Three items wait on this one** — `eject` becoming a real motion, the
destroyed-ladder fall, and knockback as a melee outcome — so doing it early collapses three waiting
entries into one piece of work. Consequences: consequences pair with the deep-fall rules.

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
**Needs:** nothing, but **read `BR27.15` first.** That entry found step-out has *no view affordance at
all* — nothing in `src/view` or `src/debug` reads step-out state, so the safest-first candidates and the
wheel cycling are both invisible. Every controller-state test passes and nothing tests that a player can
see it. The bug is the better-specified half of this item.

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
- **Preferred ally spacing.** Units with the same weapon and playstyle cluster too tightly — identical
  inputs produce identical scores, so identical units converge on the same cells. `ally_proximity`
  exists as a consideration input; what is missing is a **preferred distance** rather than a monotonic
  pull or push, so that too close scores badly for the same reason too far does. Expect interaction with
  cover-seeking, where several units legitimately want the one good cover spot and only one can have it.
  Pairs with the Protector input above — both are ally-relative positioning.
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


### One view, toggleable modules — **LANDED (taskblock-56 Passes C and D)**
**Needs:** nothing. **Unblocks:** the editor's claim that a whole new surface costs almost no view code.

**Kept as a landed summary rather than deleted, because two things it predicted are now measured facts
and one of its premises turned out to be wrong.** The build detail is in `CHANGELOG.md`.

- **The four overlay subclasses are gone.** `SquadControlOverlay` (942), `SpectatorOverlay` (718),
  `GenerateBoutOverlay` (373) and `SingleUnitOverlay` (54) are rows in `ViewModes`; `ControlOverlay` is
  the one surface class. Seventeen `ViewModule`s in `src/view/modules/`.
- **Display and input toggle on separate axes**, which is the axis the spectator view needed and could
  not get from inheritance. Its contract is now `has_unit_input() == false` rather than the absence of
  an inheritance edge.
- **This item's own line counts were wrong**, and it is worth saying so since they were part of the
  argument: it said 527 and 812 where the real figures at the time of the work were **718 and 942**. The
  case was understated, not overstated, but the numbers had aged.

**What it claimed about the bug class did NOT fully hold, and that is the residue.** The item said
landing this "closes them as a class" for `BR27.04`, `BR32.09` and `BR35.02`. The first two were already
`Resolved` before taskblock-56 began. **`BR35.02` did not evaporate**, and the reason is instructive: the
stated shared cause was the spectator re-implementing the player view's panels, which was true of the
other two and never true of it. Its blind `y == 0` plane math was not a second copy of anything done
better elsewhere, so there was nothing to converge on. It stays open, in one module rather than one
overlay, so whatever geometry check it eventually gets lands once.

### The `mouse_filter` sweep
**Needs:** nothing, but **best done with *One view, toggleable modules*** — same files, same class of
defect, and both close a category of UI bug structurally rather than one instance at a time. **Unblocks:** closing a recurring class of UI bug instead of one instance at a time.

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
