# PLAN.md — Build Order

**Forward-only.** Sequences *unbuilt* work. Built work → `CHANGELOG.md`; reversals → `SUPERSEDED.md`;
defects → `BUGS.md`.

**Dependency is the only ordering driver.** An item sits where it does because of what it needs — not
because of how big it is, how interesting it is, or when it was written down. A one-line change and a
whole system are peers here: work is single-threaded, so size never affects what comes first.

**QUEUED is grouped under `##` headings, and the grouping carries no order.** A heading says *these
items share a subject and are cheaper read together*; it does not say the group is next, or that its
members must land together. **Order still lives in the sequence, not in the headings** — an item's
position is its schedule whether or not it sits under a heading.

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

### 1. Blockers need a real transform, and the veneer's facing waits on it
**Needs:** nothing — the storage half landed at taskblock-63 Pass D3. **Unblocks:**
ledge veneers facing the edge they hang off; ladders on any side of a cell; any terrain part whose
meaning depends on which way it points.

**Supervisor's call, 2026-08-06: blockers need a real transform** — not quarter-turn rotation baked
into the boxes.

**Reported as a veneer defect**: *"veneers don't respect the facing of the clicked side of a thing.
They also always place on one edge of a top face, and should align their facing to the edge. They're
already getting the 'grow to' height from a piece, so they should face it as well. Ladders may need
this behavior as well."* All true, and the cause is one layer below the veneer.

**A blocker's facing does not survive being placed.** `MapPlacement.facing` is documented *"Surfaces
only: radians... What makes a ramp directional"*, `MapSerializer.to_grid` stores a blocker as
`grid.blockers[cell] = part` with no orientation anywhere, and `BoardView._spawn_blocker` draws it
at facing `0.0`. So a `ledge_veneer` — which authors its box against **+Z** and is a `KIND_BLOCKER`
— can only ever appear on one edge of a cell, whichever edge the author meant.

**The deriving half was built and then reverted, deliberately.** A side click can face the veneer
back at the ledge it hangs from, and a top click can read the struck point to pick the nearest cell
edge — both landed and tested. **They were backed out because the drawing half does not exist**, and
a placement carrying a facing that nothing renders is precisely the visual/logic disagreement this
project spent taskblock-59 removing. *Both halves need to be possible first.* The derivation is
small and can be rebuilt in an afternoon; it is not the work.

- **Why not bake rotation into the boxes**, which is how `size` and `offset` already reach the
  board: a `Box` is axis-aligned, so that buys quarter turns only. Enough for four cell edges and
  wrong as a foundation — the supervisor's answer is a real transform, which also serves a ladder on
  an arbitrary face and anything later that is not axis-aligned.
- ~~**`Grid.blockers` is `Vector2i -> Part`**, so there is nowhere to put an orientation today.~~
  **Built (taskblock-63 Pass D3).** It holds a `Blocker`. *A cell holds one blocker* still wants the
  same entry to become a list, and the two are still cheaper together — but that item now needs a
  container change rather than a record that does not exist.
- **`UnitGeometry.assembly_placements` already takes an orientation** and `RayCaster`, `SightSpans`
  and `PartPicker` all read the boxes it produces — so once a blocker can carry one, geometry,
  picking and sight follow with no further change. It is the storage that is missing, not the maths.

**A blocker's placement context is a dictionary key, and that is the whole defect.** `grid.blockers` is
`Dictionary[Vector2i, Part]`, while a surface is a `Surface(part, height, facing)` record and a body
part receives a full `Transform3D` from the socket-tree walk. **A `Part` is a template; the transform
lives in the placement context** — and blockers are the one kind whose context carries a cell and
nothing else.

**Surfaces got their record in taskblock-38. Blockers never got the equivalent.**

**So this is not "give blockers a transform" — it is give them the record surfaces already have**, and
`MapPlacement` **is** that record: it carries `height`, `size`, `offset` and `facing` today. The work is
`Grid.blockers` holding a record rather than a bare `Part`, the serializer carrying fields it already
has, and `board_view.gd:349` reading them.

**`BR62.05` was the live half and it is closed** (taskblock-63 Pass D3): `Grid.blockers` holds a
`Blocker` record carrying `height`, `size`, `offset` and `facing`, `MapSerializer` carries all four
both directions, and `board_view.gd` reads them. **What is left is exactly the drawing half** —
`BoardView._spawn_blocker` still renders at facing `0.0`, so a placement's facing survives being
saved and does not survive being looked at. That is the visual/logic disagreement taskblock-59 spent
a block removing, and it is stated in `Blocker`'s own header rather than left to be found.

**And the deriving half can be rebuilt now.** A side click facing the veneer back at its ledge and a
top click reading the struck point both landed once and were backed out *because the drawing half did
not exist*. Half of that objection is gone.

**A third fixed generation height (+4, alongside 0 and +1) is what surfaces it.** A floor at +4 sits
above every wall on the board, so an exterior wall must **follow its neighbouring tiles up** — which
becomes *authorable* once a blocker carries a height, rather than needing a rule of its own.

### 2. A confined unit should be legible, not silent
**Needs:** nothing. **Unblocks:** a stranded unit being distinguishable from a hang.

**The last unbuilt bullet of the old *Multi-level cleanup* item**, which taskblock-62 otherwise
closed. Escalate a unit that cannot make progress to an **agitated roam** or **pace** — visibly
restless rather than idle — and after a few turns of no progress, **shut down**.

**This does not fix terrain and must not be logged as though it did.** It stops a stranded unit
from being indistinguishable from a frozen one, which is a legibility problem, not a navigation
one. `can_return` (tb62 Pass D) means the planner now *avoids* stranding itself; this is for when
it happens anyway — knocked into a pit, or spawned somewhere the generator's repair gave up on.

### 3. The destroyed-ladder fall
**Needs:** forced movement. **Unblocks:** terrain destruction meaning something vertically.

**Two of its four dependencies landed at taskblock-62 Pass C2.** *"A unit occupying a position
partway up"* is built — a unit's position is `(cell, height)` and a partial climb rests there — and
*"interrupts firing mid-action"* landed at taskblock-53. What is left is **terrain destruction
affecting whatever stands on or attaches to it** and **falls / throws / knockback as real
movement**, which is the same machinery *Forced movement* and `eject` wait on. Three items, one
dependency.

### 4. Do the tests approximate things the game already defines?
**Needs:** nothing. **Unblocks:** trusting a headless measurement; the class of failure taskblock-61
repeated four times.

**191 test files call `Part.new()` directly; seven build against a real shell template.** Hand-built
stand-ins are the norm and real definitions are the exception — so the question is **not** "find the
cheats", it is **"when is a hand-built fixture correct, and when is it hiding something?"**

**taskblock-61 paid for this directly.** Pass C measured a cost probe against a **one-box torso** where
a real shell is **48 boxes**, concluded the cutout was affordable, and the supervisor's next in-game
session came back at **13 fps**. Passes A through D repeated that shape four times: measure a component
headlessly, infer the system, report a conclusion the next in-game action disproved.

**Three outcomes per fixture**, the same shape as taskblock-54's audit of the 133 hand-built state
files:

- **Hand-built is right.** A test of a pure function over two positions needs no shell, and forcing one
  on it is slower and less focused. Leave it and say so.
- **Hand-built was avoiding something** — usually cost or setup. Move it onto a real definition.
- **Hand-built has drifted from what the game produces**, so the test passes against a unit that could
  not occur. **This is the outcome worth finding**, and it is the one that produced the 13 fps.

**The detector is cheap: put a real chaingunner through every test that simplifies a unit** and see what
breaks. A fixture that only passes with a one-box stand-in is telling you something.

**An audit, not a sweep.** It produces evidence and a list; acting on it is separate, under
`TEST-AUDIT.md`'s cut rule.

# QUEUED


<!-- ------------------------------------------------------------------------ -->
## Going up

### The mag lift's two surfaces should stack in one cell
**Needs:** a way for the planner to value a height change that does not change cell. **Unblocks:**
a lift reading as one object.

**Asked for at taskblock-63 Pass E and deliberately not built** — *"the top and bottom surfaces
should stack, top plate hovering over the bottom one. Not two placements at unrelated heights; the
pad is visibly one object, and the gap is what reads as the lift doing something."*

**The pairing half of that request landed** (`GridPlacement.place_mag_lift_pair`: one constructor,
each pad recorded facing the other, no proximity inference). **The geometry half did not, and the
reason is the planner rather than the drawing.**

- A lift's two pads sit in **two adjacent cells** today, and every measurement the AI can make about
  a ride is a fact about *the partner cell*: `lift_advance` reads `_path_cost_to_target` at the
  partner and compares it with here. **Stack both pads in one cell and that difference is
  identically zero**, because the cell has not changed — the ride's whole value becomes "you are now
  at a height from which the adjacent shelf is a free step", which the pathfinder cannot express at
  all, being cell-to-cell.
- So this is not a rendering change. It needs the planner to be able to value a vertical move within
  a cell, which is the same missing idea a **partial climb** has (a unit resting at `(cell, height)`
  is already representable and still not something a candidate scorer can prefer).
- **Do not build the drawing half alone.** A stacked pad that the AI never rides is a visual/logic
  disagreement, which is the class taskblock-59 spent a block removing.

### `MapGen`'s lift repairs are invisible to the invariant they exist to satisfy
**Needs:** a decision about what "navigable" means. **Unblocks:** `LIFT_SHARE` meaning what it says.

**Found at taskblock-63 Pass D1.** `guarantee_navigability` judges a board with a non-climbing
`Pathfinder`, and **a mag lift is not a `Pathfinder` edge at all** — it is an AP-costing action
(`ride_mag_lift`), so `MapNavigability` cannot see one. A repair that stamps a lift therefore
satisfies nothing the check can measure.

- **It has been getting away with it**: the cell stays listed as stranded, a later pass falls
  through to a ladder, and the board comes out navigable. So the symptom is wasted lifts and wasted
  passes rather than broken boards.
- **`_reach_unreachable_ground` sidesteps it by stamping ladders only**, and says so. The one-way
  path still rolls `LIFT_SHARE`.
- **The real question is a design one and should not be answered by a code fix**: is a board
  "navigable" if crossing it requires spending AP on a lift? If yes, the pathfinder needs to model a
  non-adjacent edge, which is a real change to what an edge is. If no, `LIFT_SHARE` is a texture
  knob that must never be the *only* route to somewhere — which is a generator rule, not a
  pathfinder one.

### `TALL_ROOM_SHARE` wants evidence, not a number
**Needs:** bouts played on maps carrying a +4 shelf. **Unblocks:** nothing; a tuning question that
should not be answered by guessing.

`MapGen.TALL_ROOM_SHARE` is **0.25**, a flagged placeholder — a quarter of the rooms this generator
raises go to +4 rather than +1. **A quarter is the honest "it should appear and it should not be the
norm" default**, chosen so the fixture is not theoretical; measured at **9 of 30 seeds** carrying one.

A tall shelf changes what a turn is: reaching one costs several turns of climbing or an AP ride, and
holding one is a real position. Whether that is a board's centrepiece or its texture is a played
answer, and it sits beside `LIFT_SHARE`'s own open question rather than being decided separately.

### Weight a hop-down against ramps, not just against stranding
**Needs:** taskblock-62 Pass D's `can_return`, which landed. **Unblocks:** units routing through
gentle ground without any rule naming a ramp.

**Deliberately held until after the one-way awareness, and that reasoning held up.** Weight a
candidate cell slightly worse when reaching it means dropping a level, and not at all via a shallow
rise. Units then prefer two-way ground without any rule naming ramps.

**Landing both at once would have hidden which one did the work — and taskblock-62 proved that is
not hypothetical.** `can_return`'s first curve floored a stranding cell at 0.15 and moved
`seeds_to_first_win` from 1 to 7; at 0.85 it reads 2. With two new movement weights in play at once,
that would have been unattributable. **Whatever this item authors, measure it alone.**

### `LIFT_SHARE` wants evidence, not a number
**Needs:** bouts played on maps carrying lifts. **Unblocks:** nothing; this is a tuning question
that should not be answered by guessing.

`MapGen.LIFT_SHARE` is **0.5**, a flagged placeholder — half the routes-up a generator repairs are
mag lifts and half are ladders. It decides how often going up competes with **shooting** (AP) rather
than with **walking** (MP), which is a real texture question and not a cosmetic one.

**An even split is the honest "both should appear" default**, chosen so neither fixture is
theoretical. What it wants is a played answer.

<!-- ------------------------------------------------------------------------ -->
## Aiming and the camera

### Aiming and the third-person camera, rebuilt
**Needs:** nothing. **Unblocks:** closing `BR34.04`; the dartboard scaling correctly; a shot refusal
that says why. **Supersedes the narrower "cut the sniper camera" framing.**

**The supervisor, 2026-08-09:** *"I've realized that I've designed aiming in a strange way, and it's
made a bit of a code mess that needs to be cleaned up or excised."*

**Pull the OTS camera out and replace it rather than fixing it.**

- **A true third-person camera** — behind, up, and to the right of the firing unit, **toggleable to the
  left with `B`**.
- **Simple FOV zoom replaces the sniper view entirely.** `SNIPER_UP_OFFSET`,
  `SNIPER_FRAME_DISTANCE`, `SNIPER_ZOOM_SLACK` and the distance branch in `CameraRig.ease_to_framing`
  all go. **Tuning any of them is work this discards** — which is the trap `BR35.02` sat in for three
  blocks, and why `BR34.04` is `Active` and must not be worked before this.
- **The dartboard goes where the raycast lands, with no guessing about intent.** If something
  interrupts the shot, the dartboard **jumps forward to the interrupter**. No reasoning about what
  *might* be aimed at.
- **Scatter weapons cast a group**, and **the shortest hit places the dartboard.**
- **Do every calculation from static, non-camera objects.** This is the constraint that matters most:
  `BR51.01` was a cell address in a plane-space slot, and three earlier hypotheses all measured real
  camera-related things and none of them was the cause. **A camera-derived quantity in an aiming
  calculation is the defect shape this rebuild exists to remove.**

**It probably subsumes two open entries** — the dartboard not scaling with distance, and the silent
refusal — since both are on the aiming path. Confirm rather than assume.

### Take the camera out of shot processing
**Needs:** nothing. **Unblocks:** `BR61.02`; aiming being a property of the gun rather than of the
view.

**Corrected at tb61: this does NOT unblock `BR51.01`, which it used to claim.** That entry's root
cause turned out to be a cell address returned where a plane point belonged, and it is fixed. The
camera lean is a **separate, smaller, still-live** defect — measured at 1.5 cells of aim-point
movement for a stationary cursor — now filed as `BR61.02`. **Removing the lean was tried and
reverted**: the supervisor wants the flourish disconnected from the result, not deleted.

**The supervisor's specification, recorded against `BR51.01` and lifted here because it is
architecture rather than a bug fix:**

> *"The camera shouldn't be involved in actual shot processing at all. Like you said, it's a
> flourish, so why is it affecting aim? The purpose is for the camera to give a better view of the
> target. The mouse cursor, when clicked, is aimed at a point on a part the player wants to aim at.
> The player camera should not be involved in drawing a line from the shooter's gun to that clicked
> point."*

**The defect it closes.** `CameraRig.aim_at` rotates the real `Camera3D` by up to `MAX_LEAN_DEG`
(5.0) toward the reticle, and `TacticsController` caches that same camera — so every
`project_ray_origin`/`project_ray_normal` casts through a camera turned away from where the player
believes they are sighting. **A rotational offset on the whole ray**, which is exactly the widened
symptom: shots landing left *and* down together, not a sign flip on one axis.

- **The shape is a two-step split.** The camera converts a cursor pixel into **a world point on a
  part** — that much it must do, since the cursor only exists in screen space. The shot is then
  resolved **gun to that point**, with no camera in the expression. Today the second step reuses the
  first step's ray.
- **Un-leaning the projection is NOT the fix**, and was explicitly rejected: it keeps the camera in
  the loop and merely changes its pose.
- **It is a feedback loop today** — the lean is computed *from* the reticle point and the reticle is
  computed by projecting *through* the leaned camera. Establish whether the offset is stable or
  compounds across frames before choosing a fix; that answer changes what a test has to pin.
- **Any new test must compare against the camera pose the player is looking through**, not against
  the other consumer of the same ray. The frame-mismatch measurement came back clean at 0.0000 cells
  precisely because the reticle and the resolver are handed the *same* wrong ray.
- **Its own item rather than a hunt entry** (taskblock-61 Pass A's call): inside a hunt pass it
  would either be half-built or become the whole block.

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

### AI-produced dartboards and an aim beat
**Needs:** nothing mechanical; it's playback and timing work.

Only the player's shot ever draws a dartboard — an AI attack resolves straight from the planner's decision with
no on-screen wind-up. `ShotScatter.for_shot` is now the one place range→radius truth lives, so it's a
ready-made primitive to drive an enemy-side draw. The real work is *when* the beat plays, how long it holds,
and how it interacts with other AI units resolving in the same batch.


### Player-facing LOS/LOF conflation
**Needs:** eyes on the targeting UX first.

tb33 fixed the AI's confusion of "can see" with "can hit," but the player's own attack legality still gates on
`LoS.has_los` rather than the LOF predicate. A different problem from the AI's silent 81%-into-walls case,
because the player sees both the dartboard and the wall and can choose to fire anyway. Swapping it needs a UX
decision first — does the dartboard say "no shot" before the player commits AP? — not a mechanical copy of the
AI fix.


<!-- ------------------------------------------------------------------------ -->
## Blockers, stacking and veneers

### A cell holds one blocker, so nothing stacks vertically
**Needs:** `Grid.blockers` becoming a list per cell, or a placement carrying enough position to be
addressed below another. **Unblocks:** stacking a pillar on a pillar; a wall taller than its part.

taskblock-59 Pass A refused the gesture rather than letting it corrupt the editor: `Grid.blockers` is
`Vector2i -> Part` and `MapPlacement.height` is documented as a surface's field, so a second blocker
on a cell is a thing the format cannot express. The click now says so and the ghost declines to
preview it.

**The author's route to a taller wall is the Scale tool** (Pass C), which is the better verb for it —
one part at a designed size rather than two pretending. What is genuinely missing is *stacking
distinct things*: a crate on a pillar, a barrel on a crate.

- `MapPlacement.offset` (Pass C) already carries a sub-cell displacement, so the **geometry** of a
  stack is expressible today. What is not is the **grid's** idea of it: `blockers[cell]` holds one
  part, and the pathfinder and `Grid.blockers` sweeps ask in whole cells.
- **That limit is already live and is not new here.** A 3 x 3 wall authored by Pass C is one blocker
  on one cell while covering nine, and an offset placement blocks the cell it was authored at
  whatever its geometry overlaps. Stated in `MapPlacement.offset`'s own note rather than left to be
  found.

**Re-asked by the supervisor after taskblock-59 and scoped rather than started** — *"pillars and
other terrain features should stack atop each other. This might be a big ask, so check before
implementing."* It is. **Measured 2026-08-06: `grid.blockers` is read at 84 sites across 28 files**,
41 of them in production logic:

| pattern | sites | difficulty |
|---|---|---|
| `blockers.has(cell)` guards | 14 | mechanical — becomes *"is anything here"* |
| `for cell in blockers` iteration | 14 | mechanical, but it is the ray marcher, sight spans and detonation |
| `blockers[cell] = part` writes | 13 | mostly `MapGen` and `BoutInjector` |
| `blockers[cell]` indexed reads | 5 | **the real decisions** — *which* one? |
| `size`/`erase`/`keys` | 7 | mechanical |

**The count is not the hard part.** Most readers genuinely need **every** blocker rather than the
first — `RayCaster` marches geometry, `SightSpans` derives occlusion, `ShotPlane` projects, `Cover`
and `VisibilityField` ask about blocking — while `DamageResolver` and `Detonation` do *identity*
checks (`blockers[cell] == part`) that need list semantics to stay correct. `Grid.shootable_part_at`
and `cell_of_blocker` both assume one.

**Two cheaper things already work and should be weighed before starting.** A *taller* pillar is
authorable now — Pass C's Scale drag on the top face gives one part at the authored height with
proportional hp, which is better than two parts pretending. And `Grid.field_items` already holds an
ordered array per cell and `BoardView` draws it through `_spawn_blocker`'s own geometry, so several
parts in one cell already **draw**; what they do not do is block, because `Pathfinder` and
`ShotPlane` never read `field_items`. **The open design question is therefore what distinguishes a
blocker from a field item** once a cell can hold several of either — answer that before the
refactor, not during it.

### A veneer grown upward can never snap to anything
**Needs:** a pick that reports **which** surface of a stack was struck, rather than the stack's own
top. **Unblocks:** the anchored half of *"it grows both ways and snaps to what it meets"*.

taskblock-59 Pass D landed the veneer's click and found this while testing it. `LedgeVeneer.span_up`
handles an anchor above and taskblock-58 tested it — but through a click it is unreachable. A
top-face pick strikes the top of whatever is at that cell **by definition**, and the placement lands
on that same cell, so "the nearest surface strictly above the face you struck" is empty every time.
Growing up therefore always takes `UNANCHORED_RISE`.

**Growing down is unaffected and does snap**, to the deck under the landing cell — which is the
common gesture and the one the feature was described by. This is the other half.

Pinned by a named test (`test_growing_up_always_takes_the_default_because_nothing_is_ever_above`) so
it is a recorded limit rather than a rediscovery.

<!-- ------------------------------------------------------------------------ -->
## The test suite

### Boards become an input, not a product — generate once, serialise, hand out
**Needs:** nothing. **Unblocks:** a shard map with no corpus-affinity constraint, and a `Grid`
fixture whose cost does not scale with however many processes want one.

**Measured in taskblock-66 Pass A, on the supervisor's proposal.** Not committed fixtures — those
were evaluated first and the staleness argument sank them. **Build fresh at gate start, serialise,
hand out**, so the boards are exactly as fresh as the generator that made them:

| board | generate | load | round-trip | size |
|---|---:|---:|---:|---:|
| 32×24 | 389 ms | **62.5 ms** | 5/5 faithful | 141 KB |
| 40×30 | 414 ms | **81.6 ms** | 5/5 faithful | 219 KB |

**Loading is 5–6× cheaper than generating and `MapSerializer` round-trips a full signature** — heights,
blocker `height`/`size`/`facing`, surfaces, spawn markers.

**The better shape is a lazy shared disk cache wiped at gate start**, not a prologue. `MapCorpus.read()`
checks a scratch directory, loads if present, generates-and-saves if not. No need to know in advance
which boards the suite wants, **the wipe is the invalidation**, races are benign (identical content,
atomic rename), and the unsharded path is unchanged because the in-process cache short-circuits before
touching disk.

**The invalidation has one hole and it must be closed in the same pass.** The wipe covers the full
gate; a *targeted* run does not wipe, so changing `MapGen` and running one file reads stale boards.
**Wants a generator stamp in the cache key, or a wipe on any run** — a cache that is stale exactly
during the edit loop is the kind people learn to distrust and then work around.

**What it buys, in order.** It removes the `MapCorpus` half of a sharded gate's affinity constraint
entirely — a board that is an *input* costs nothing to share, so the duplicated-fill quantity goes to
zero rather than being subtracted. Plus ~20 s on an unsharded gate.

**What it does not buy: the makespan.** A sharded gate ends when `BoutCorpus`'s draw ends, and that is
missions being *played*, not maps being generated. This makes the other shards cheaper and
unconstrained; it does not shorten the gate.

**It goes after taskblock-66 because that is where the payoff is**, and because the fidelity risk is
correctness work that should not ride on a scheduling block. **`BR62.05` is this bug having already
happened once** — dropped blocker `height`/`size`/`offset`/`facing` that *"round-tripped because both
ends discarded the same things."* Fixed at tb63 D3, and a future `Grid` field added without a
serializer update would silently change what the whole suite sees, where today it is an editor
inconvenience. **Under this design it is cheaply guarded in-run**: the board is generated and loaded in
the same gate, so hashing before save and after load is nearly free. Build that guard with the cache,
not after it.

### What the completion rate measures, and two headers that say otherwise
**Needs:** nothing. **Unblocks:** knowing whether the completion number is a statement about the game
or about the harness.

**`p` is 0.220** — taskblock-66 Pass A, 100 seeds across ten windows spanning the real 0–9999 draw
space, 95% CI **0.139–0.301**. That supersedes every earlier figure, including `BR65.01`'s 0.15 and
every four-draw estimate. **It is a wide interval and it should be quoted as one**; P(no win in nine
seeds) runs 1-in-3.8 to 1-in-25 across it.

**Two file headers state a belief the measurement contradicts.** `completion_sampler.gd:12` and
`bout_corpus.gd:17` both carry the *"pessimistic window"* finding — seeds 0–11 at 41.7% against 12–23
at 66.7% on an identical build — as evidence that the seed space has structure. **Fisher exact on 5/12
against 8/12 gives 0.414**, and Pass A tested it directly: **chi-square across ten scattered windows is
11.42 on 9 df against a 16.92 critical value.** No evidence the windows differ. **taskblock-46's
decision to sample rather than pin is correct regardless and is not reopened** — sampling is the right
method whether or not that particular spread was real. What wants correcting is the claim that the
windows are *known* to differ, which is currently load-bearing in two places.

**And the number is not what its name says.** `run_seed` plays to `TURN_CAP` (100) and counts only
`EXTRACTED`, and **30 of Pass A's 78 losing seeds reached that cap** — 30% of all sampled seeds were
still playing when the clock stopped. **`p` is P(complete within 100 turns)**, not P(complete). Two
consequences:

- **`TURN_CAP` is an unlisted cost lever.** It sets the cost of a losing bout (**61.3 turns measured**),
  and under a sharded gate that cost *is* the makespan. Lowering it is the largest single knob on gate
  length that nobody has listed.
- **`p` and the loser cost are coupled through it**, so arithmetic that re-derives one against the
  other while holding the other fixed is not quite valid — including `BR65.01`'s cap figures.

**Turning the knob is a design decision, not a scheduling one**, which is why it is recorded here rather
than done in taskblock-66: a lower cap makes the completion rate say something different about the game,
and the supervisor has already stated that the rate falling from 72% to ~40% to today's figure was two
deliberate difficulty changes. **Decide what the number is supposed to mean before changing what it
measures.**

**One modelling note for whoever prices this.** taskblock-66's cost model is turns-linear, and the
evidence says there is a per-bout fixed component: Pass A's live draw ran 33 turns in 49.8 s (1.51 s per
turn, outside the 0.77–1.39 band), which solved against the 100-seed run gives roughly **33 s fixed per
bout plus 0.52 s per turn**. At current draw sizes the two models agree within a few seconds — but **a
turn reduction bought against the linear model will over-credit itself**, and that is exactly what
lowering `TURN_CAP` would be.

### `BoutCorpus`'s variable draw is subtracted, but its *bouts* still are not
**Needs:** nothing. **Unblocks:** ratcheting `bouts` and `candidates` the way `turns` now can be.

**The turns half landed in taskblock-65's close-out.** `BoutCorpus.sample()` is clock-seeded and
plays until the first win (`CompletionSampler.seeds_to_first_win`, cap 9), so how much work it does
is a property of the draw — measured at **622 / 786 / 1131 total suite turns across three identical
full gates in one session**. `CompletionSampler.sampled_turns` now counts it and `SuiteBudget`
subtracts the quantity, which is strictly better than the file exclusion it replaces: the cost lands
on whichever `SuiteTier.CORPUS_READERS` file ran first, and failure-history reordering changes which
one that is, so a filename was only ever a proxy.

**`bouts` and `candidates` have the same problem and no equivalent.** The same three runs measured
**80 / 85 / 88 bouts** and **911 200 / 1 292 621 / 1 816 411 candidates**, almost all of it the same
draw. Both are still gated against a single-sample baseline, and `candidates` is not gated at all.
At the measured completion rate — **0.220**, taskblock-66 Pass A — the draw averages **4.06 seeds**
and reaches the cap about one gate in nine, so the swing is real but narrower than `BR65.01`'s 0.15
implied. **The earlier reading, that the sampler routinely plays the full nine, was wrong.**

**The work is the same shape as the turns fix** — count them beside `sampled_turns`, subtract in
`violations()` — and it is small. **taskblock-66 builds the same machinery for `maps` and `floods`**,
which sharding inflates by duplicating corpus fills; if that lands first, this becomes two more
callers of a mechanism that already exists. It is queued rather than done because taskblock-65 fixed the one
counter that had a live flake and stopped there.

### The third corpus is a mounted `BattleScene`, and it is bigger than the first two combined
**Needs:** nothing to *measure* — this is the measurement. **Unblocks:** the largest remaining
block of repeated work in the suite.

**taskblock-65 Pass E swept for the shape that produced `BoutCorpus` (tb48) and `MapCorpus`
(tb50) — N files each redoing the same expensive thing — and found four more.** Measured, with
what each would cost to share and whether it should be:

| shape | measured | verdict |
|---|---|---|
| **A mounted `BattleScene` + `ControlOverlay`** | **1177 ms each**; 41 files, 512 tests, 92 construction sites | the big one — **but not a corpus, see below** |
| `DataLibrary.reset()` + `load_all()` in `before_each` | **15.4 ms**; 97 files, 904 tests = **13.9 s** | shareable, real, hazardous |
| Subprocess spawns of `run_tests.sh` | ~3.7 s each; 10 spawns across 2 files = **36.7 s** | mostly *not* shareable |
| Generated maps | done — taskblock-65 Pass C | — |

**The mount is the headline and the corpus shape is the wrong answer for it.** At one mount per
test the 41 files would be paying **~600 s**; at one per construction site, ~108 s. Either bound
makes it the most expensive repeated thing left. But a `Grid` is read-mostly and a `BoutCorpus`
record is immutable, whereas **a mounted overlay is the thing under test** — tests mutate it on
purpose, so handing out a shared one reintroduces exactly the cross-test corruption `MapCorpus`
needs its `copy()` escape hatch for, against an object far larger and with far more state.

**One file carries a disproportionate share and has a stated trigger.** `test_battle_scene.gd` is
**63.3 s for 6 bouts and 3 turns** across 39 tests in 962 lines — scene-mount cost, not simulation.
taskblock-66 deliberately left it unsplit because under a sharded gate it sits below the corpus shard
and so is not the wall. **The trigger is recorded rather than the work: split it if it ever becomes the
determiner of gate length.** It is also the largest single instance of the shape below.

**The promising cut is narrower and it is a different job: several of these tests assert
*declaration* properties by mounting a scene.** *"Which modules does this mode declare"* is a
question about a `ViewMode` table entry, and answering it currently builds a `CanvasLayer`, a
theme, every module's `Control`s and waits two frames. An assertion path that reads the
declaration without mounting would take those tests to near zero without sharing any mutable
state at all. **That is the item worth doing**, and it is not a corpus.

**`DataLibrary` reloading is real but modest and its hazard is the same shape** — global mutable
state, and the `before_each` exists precisely so a test that authors into the library cannot
leak into the next one. Sharing it means proving no test mutates it, or giving it a
copy-on-write path. 13.9 s is not worth that on its own; it becomes worth it alongside the
mount work, which touches the same `before_each` blocks.

**The subprocess spawns were checked and are mostly honest.** `test_suite_run.gd` (19.6 s) and
`test_run_suite.gd` (17.1 s) spawn ~10 real `run_tests.sh` runs between them, and they genuinely
differ — different targets, different `HB_TEST_ROOT`, different `WRITE_PROFILE`, different
expected exit codes. **Two of them could merge** (the passing-target run and the
profile-refusal run differ only in an environment variable that could be asserted about one
run's output twice), worth ~7 s. The rest are a spawn per claim because the claim *is* about
the spawn. Recorded so nobody re-derives 36 s as a promising target.

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

<!-- ------------------------------------------------------------------------ -->
## Combat log

### Combat log paths are a workflow choice, not a constant
**Needs:** nothing. **Unblocks:** the supervisor and CC working at the same time.

**Filed as `BR61.01`:** headless and non-headless runs write to the same files, so a test run and a
played session stamp on each other and **neither party can work while the other does.**

**Two shapes, and the second is better:**

- **Tag test output as test output.** Minimal, fixes the collision, leaves the path hardcoded.
- **Make the log destination a parameter**, documented, with the game using today's default and tests
  writing wherever they are told. **Then a log landing somewhere odd is a workflow decision rather than
  a code change** — which is what keeps this from recurring the next time something else wants its own
  stream.

**Prefer the second.** The capability survives into later phases where a replay, a server, or a second
observer wants its own destination, and none of those should need a code edit.

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

<!-- ------------------------------------------------------------------------ -->
## Small UI leftovers

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

### The bout launcher spans the screen
**Needs:** nothing. **Unblocks:** nothing.

Full-screen-width after the module collapse. Cosmetic, and the supervisor has said it is **not worth a
pass of its own** — fold it into whatever next touches that surface.

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

### Two unauthored defaults carry a shipped material's whole feel
**Needs:** nothing. **Unblocks:** armour and weapon balance being authored rather than inherited.

**Salvaged from `BR52.13` when that entry closed** (taskblock-60 follow-up), because it is a real
decision and a closed bug report is the wrong place to keep one.

**`steel.tres` authors no `deflect_threshold_deg`**, so it takes `MaterialEntry`'s **30.0**
default — and a representative engagement measured at the time sat at **~31 degrees** incidence,
one degree the wrong side of it. Combined with weapon damage figures that decide penetration
outright (a chaingun's 1.6 effective against steel's `dt` of 6.0 **cannot** penetrate, ever), a
shipped material's entire feel rests on two numbers nobody chose.

- **This is not a bug and was never reported as one.** Re-measured across six real bouts, the
  resolver behaves: 15.5% of 2450 impacts penetrate, 33.5% stop dead, 51.0% deflect. The original
  "nothing ever penetrates" reading came from a sample drawn entirely from a pairing that cannot.
- **What it wants is authoring, not a fix** — a deflect threshold chosen per material, and a look
  at whether the damage-versus-`dt` cliff is meant to be a cliff. **Balance numbers, so not
  invented here.**
- **Worth doing before any armour tuning pass**, or that pass will be tuning against defaults and
  attributing the results to its own changes.

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

<!-- ------------------------------------------------------------------------ -->
## Everything else

### Rename the terrain parts to sort together, and mark them as placeholders

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

### Rework the gizmo as a real CAD tool

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

### Elevated tiles lost their line borders
**Needs:** nothing. **Unblocks:** reading a stepped board by eye.

Grid lines went flat when taskblock-55 deleted the ground quad, and lines-at-tile-height was **passed on
deliberately at the time** — more legible on a stepped board, but co-planar with the tile top, which is
the pairing the ground quad was deleted for. The supervisor now reports elevated tiles as unreadable
without them, so **the judgement call is due for revisiting rather than being a regression.**

If the answer is to draw them, the co-planarity is the problem to solve — a small offset, a different
primitive, or the tile's own edge geometry doing the work.

### Attributes
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

### `BR60.01`'s repair — unreachable raised ground is detected and measured, and nothing repairs it
**Needs:** a decision on which of three repairs is wanted (below). **Unblocks:** closing `BR60.01`,
and generated 40x30 boards that do not hand a fifth of their elevation to nobody.

**The detection half landed in taskblock-61 Pass E2** — `MapNavigability.unreachable_cells` /
`unreachable_regions`, and `test_map_gen_reachability.gd` sweeping the 40x30 board `BattleScene`
actually plays. It reproduces every run: **twelve regions over eight of fifty seeds, five of them
190+ cells.** The sweep is pinned as equality, so the day this is repaired the list goes red and
must shrink.

**The `rooms[0]`-anchor theory was measured rather than assumed, and it is a correlate, not a
cause.** Seven of the eight defective boards have a raised anchor against a base rate of 19 in 50;
twelve raised-anchor boards are clean and one defective board has a flat anchor. So re-anchoring
`_repair_stranded_elevation` at the spawn zones would aim at the right neighbourhood without being
shown to be the mechanism.

**Three repairs, and the choice is a design call about map character, not a code call:**

- **Ladder in.** `guarantee_navigability` already repairs one-way ground by stamping a ladder
  (`_open_a_route_out`), and the symmetric fix is the same call from a *reachable* cell adjacent to
  the region — cheapest, and reuses the mechanism that exists. **But taskblock-61's own one-line
  summary of this entry is *"a large raised region reachable only by ladder"***, so this may build
  exactly what is being complained about.
- **Flatten.** What `_repair_stranded_elevation` already does to ground it cannot reach. On seed 2
  that erases a 232-cell shelf, which is a large change to what generated boards look like.
- **Stair in.** `_connect_with_a_stair` is what the generator already uses to serve a raised room,
  and reads best — but it needs a run of lower cells in a straight line out from the region, which
  a shelf against the board edge may not have.

**Do not pick one silently.** The measurement is in place either way, so whichever lands can be
judged against a number instead of an impression.

### `board_view.gd` sits on `gdlint`'s file-size cap, and every change now pays a tax to fit
**Needs:** nothing. **Unblocks:** changing the board view without first finding something to delete.

**Three times in taskblock-61 alone** a change to `BoardView` came in over the 1000-line cap and had
to buy its way back under: the cutout logger moved out (`src/debug/cutout_log.gd`), marker
construction moved out (`src/view/overlay_markers.gd`), and a third round went to shortening comments
— which is losing recorded reasoning to satisfy a line count, the worst of the available trades.

**The file is not obviously bloated; it is doing several jobs.** Static board geometry (tiles,
blockers, grid lines, empty-cell indicators), the TACTICS overlay (reachable cells, ghost paths,
waypoints, overwatch arcs), and the wall-cutout uniform feed are three separate concerns that happen
to share a node.

**Shape, not chosen:** the cutout feed is the most self-contained of the three — it owns its own
material, its own per-frame projection and its own unit list, and its only tie to the rest is the
`Grid`. Splitting it would leave `BoardView` as "draw the board and its overlays", which is one job.
**Do not do this as part of a bug fix** — that is how the last three extractions happened, and each
was scoped by what would fit rather than by what belonged together.

### A legality check answers a bare boolean, so nothing can report why a shot was refused
**Needs:** nothing. **Unblocks:** any refusal a player can act on.

`CombatAction.is_legal(state) -> bool` is the whole channel. `BurstAction.is_legal` alone has a
dozen gates — dead unit, wrong turn, missing or wounded weapon, no burst in `provides_actions`, not
enough AP, suppressed, out of bounds, nothing at the target cell, out of max range, inside min
range, **no line of sight**, cannot operate — and every one of them reports the same `false`.

**`BR32.07` is what that costs.** A burst at a wall with a pillar between failed its LoS gate; the
view could say only that something refused, and three taskblocks hunted the click path because
nothing could name the gate. CC deliberately did not re-derive the reason in the view: a second
opinion about legality can disagree with the one that actually decided, which is worse than silence.

**Shape, not chosen:** a reason alongside the boolean — an open `StringName` per gate, so a designer
adding a gate adds its reason with it and no enum needs editing. Player-facing text is a separate
question from the diagnostic channel; the diagnostic is what is missing.

### The plan pacer's budget is wall-clock, so a seeded bout is not reproducible
**Needs:** nothing. **Unblocks:** a viewed bout matching a headless one on any machine; any later
change that raises planning cost, without this conversation repeating.

**`PlanPacer.should_abort()` compares `Time.get_ticks_msec()` against a deadline**, so whether a
unit finishes planning depends on the hardware. The viewed path aborts and the headless path does
not, which contradicts the standing rule that the same seed is the same battle, always. **Latent
since taskblock-44** and unobserved while planning stayed under the number; `BR58.01` has the
measurements that made it visible — 412 ms mean per turn at Pass B, 569 ms at Pass C, against a
400 ms budget. **The budget was already being exceeded before taskblock-58.**

**Pace on candidates, not milliseconds.** `note_candidate()` is already called once per scored
candidate at both sites and `should_abort()` is already called immediately before each, so **neither
call site changes** — and both loops sit inside one `begin()` scope, so one per-turn counter covers
them. Same seed, same candidates in the same order, both paths abort identically.

- **The subtlety is the point of it.** `note_candidate()` returns early headless today, so a
  deterministic budget must count **unconditionally** — which means headless bouts start aborting
  too. That reads as a regression and is the fix: **determinism means both paths do the same thing,
  not that neither aborts.**
- **Keep wall-clock as a backstop at a pathological threshold** — seconds, not milliseconds. Set
  where ordinary play cannot reach it, its nondeterminism is unreachable in practice while a runaway
  board still terminates. **Dropping the time stop entirely trades *thinking worse* for *freezing
  longer***, which is the failure `PlanPacer` was built to prevent.
- **The cap wants a measured distribution, not a number.** The suite reports a **~900
  candidates/turn mean over 1 063 turns**, and **a mean is not a cap** — the cap lives in the tail,
  at the value that lets ordinary turns finish and stops pathological ones. Same shape as
  taskblock-50's `SAMPLE_SEEDS` derivation, and it is balance-adjacent, so it must not be invented.
- **Expect golden churn.** Every seeded bout that currently completes headlessly may begin aborting
  mid-plan. **Deliberately unsized** — sizing it is this item's first task, and it cannot be sized
  without running it.
- **Two tests raise the budget out of the way** so they test yielding rather than wall-clock:
  `test_ai_batch_yield` and `test_watched_run`'s watched-vs-headless comparison. **The second one
  was flaky rather than red** — it passed in isolation and failed under full-suite load, which is
  the failure mode to expect elsewhere. Both raises come out when this lands.

### The AI tier table wants a rework, and tb64 patched a regression inside it
**Needs:** nothing. **Unblocks:** a coherent answer to what each tier can do, which several items
here currently work around one at a time.

The supervisor, 2026-08-10: *"AI tiers are due for a rework, but this was a regression so needs to
be fixed, not perfected."* tb64 Pass C did the narrow fix — `burst` gated exactly as `shoot` is, and
`combat_tester_pump_shotgun` moved off `MINDLESS` — and deliberately changed no gate.

**What the rework has to settle**, all of it visible now rather than speculative:
- **`MINDLESS` has no firing action at all**, and that is authored (`docs/11`: `shoot` and
  `take_cover` are Grunt-and-above). It is defensible for a melee rusher and indefensible for
  anything issued a gun, and nothing stops a preset being armed with one — which is exactly what
  `BR63.05`'s MINDLESS half turned out to be.
- **The `overwatch` disagreement below** is the same shape: a table describing one thing and content
  doing another.
- **`suppress` was implemented from a doc line rather than designed.** It kept its `TRAINED` gate at
  tb64 because a suppressive *tactic* is plausibly trained, but nothing has ever played it.

### `burst.tres`'s weights are aligned with `shoot`, not tuned
**Needs:** a played bout where a weapon offers both. **Unblocks:** nothing.

`burst.tres` carries `base_weight = 1.5` and `shoot`'s five considerations verbatim, because
*"aligned with shoot"* was the instruction and inventing a different number would be a balance
decision presented as design (CLAUDE.md). **`auto_shotgun` provides both `shoot` and `burst`**, so
the two tie on base weight and the considerations decide — untested, and the only weapon in the
library where it matters. A burst also costs more AP (`burst_ap_cost` 3–4 against `ap_cost` 2),
which nothing in the scoring currently accounts for.

### Should a ladder blind? 130 of 751 blind pairs say it is worth deciding
**Needs:** a design call. **Unblocks:** nothing; it is a question, not a gap.

tb64 Pass A2's sweep blames `ladder` for **130 blind pairs** inside Chebyshev 3 on seed `642296523`
— 82 of them socketed into a `ship_floor`'s `LEDGE` socket, sitting on the cell boundary at 2.0
tall. A ladder is an open rung structure modelled as a solid 0.1-thick panel, and **tb63 Pass D1
stamps far more of them than any earlier board carried**, so a previously-rare occluder became a
common one without anyone choosing that.

**Not filed as a bug**, because the geometry is doing exactly what it is authored to do. The
question is whether the authoring is right, and it wants a played answer.

### `overwatch` starts at TRAINED, and the tier table says GRUNT
**Needs:** a balance decision. **Unblocks:** nothing; it is a disagreement to resolve, not a gap.

taskblock-59 Pass E found the description and the content disagree. `docs/11`'s table and
taskblock-59's own summary both describe `GRUNT` as *"memory and the shoot/cover/overwatch set"*, but
`data/utility_actions/overwatch.tres` has read `tiers = [TRAINED, ELITE]` since taskblock-45. **The
content is what runs**, so a `GRUNT` today shoots and takes cover and does not overwatch.

Left as authored: which tier gains overwatch is a decision about how capable a second-rung enemy is,
and moving it because a summary table said so would be an invented balance number. Pinned by a named
test so the disagreement stays visible.

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
  **taskblock-60 Pass C found that half of this already exists and is smaller than it looks**:
  `ResolutionPlayer._prime` already holds display state through playback — `_display_cell` and
  `_display_orientation` — so a unit animates from where it *was* while the model has already
  moved it. What has no equivalent is **structure**: which parts exist. `BR54.02` is exactly that
  gap and nothing more, so the narrow fix is a third display dimension rather than a new
  architecture.
- **The seven-entry class this item was expected to dissolve does not exist.** taskblock-60 Pass C
  tested it: only `BR54.02` and `BR27.07` are this shape. `BR52.06` is a membership disagreement
  (`BR60.02`), `BR52.09` is a missing teardown path, `BR51.24` is an undecided rule, `BR30.02` is
  unreproduced, and `BR57.01`/`BR59.02` are already fixed. **This item is still worth doing for its
  own stated reasons** — consistency, and making off-thread work safe later — but not on the
  grounds that it closes seven bugs.
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

### Mangling is replacement, and a mangled thing no longer works as that thing — MAJOR REFIT
**Needs:** nothing. **Unblocks:** `BR60.02`, `BR52.06`, and the `is_mangled` flag stopping being a
membership question. **Flagged as a refit on the supervisor's own instruction (2026-08-07) —
explicitly NOT to be done inside a bug hunt.**

**The rule, from the supervisor:**

> *"All things that 'mangle into' something need a part to mangle into. Mangled parts should block
> shots, just poorly ... a destroyed post-mangle part is just gone."*
>
> *"Some mangled items will need to be passable. What is a mangled wall? It's a wall that no longer
> works as a wall. What is a mangled leg? It's a leg that no longer works as a leg."*

**So mangling is REPLACEMENT, and the replacement is an ordinary part.** A mangled thing becomes a
wreck with its own volume, its own material and its own — lower — DT, so it blocks shots poorly
because it *is* a poor blocker, not because a flag says so. Destroy the wreck and it is gone, under
the plain `hp > 0` rule every other part already obeys. **`is_mangled` stops being a membership
question entirely**, which is what closes `BR60.02`.

**Why it is a refit and not a fix — measured 2026-08-07:**

- **`Part.mangles_into` is declared and read by nothing.** Three occurrences in the tree: the
  `@export` and two doc comments. `docs/01`'s *"on destruction the part is replaced by that item"*
  **was never implemented.** This is a new mechanic, not a repair.
- **`failure_mode` defaults to `&"MANGLE"`**, so every part that authors nothing mangles — which is
  most of the library.
- **Cladding and plates already name a wreck** (`twisted_sheet_metal`, `metal_scraps`) and are
  ready. **Six batteries author `MANGLE` with no `mangles_into`.** **`wall` authors neither.**
- **Every MANGLE part needs a wreck authored, or a different failure mode.** That is content work
  across the library, not a code change.

**The wall is the sharp end, and the supervisor's rule resolves it.** A mangled wall is *a wall
that no longer works as a wall* — passable rubble. That is compatible with `docs/02`'s settled tb31
rule (*"destroy one and its cell clears to fully passable ground"*) only if the rubble is
genuinely passable; if the wreck blocks movement, the two conflict and `docs/02` has to move.
**Decide which before authoring the wreck**, because it is the difference between rubble you walk
over and rubble you walk around.

**A mangled leg is the same question in the body.** *A leg that no longer works as a leg* implies
the wreck contributes no `agility`, no `step_height` and no locomotion — which is close to what
`is_disabled` already means, and the two states may want merging rather than coexisting.

- **Do not start this from a bug entry.** `BR60.02` and `BR52.06` are consequences and will close
  as a side effect; they are not the work.
- **taskblock-61 Pass B tried the small version and it failed**, informatively: making the view
  honour `BodyProjector.projects` resurrected every destroyed wall as a sight blocker.
  `test_membership_disagreement.gd` characterises the current contradiction and will need rewriting
  rather than patching when this lands.

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

### Position is a `Vector3` in a grid's frame; cells become a query
**Needs:** *Floors reference a location* (landed). **Unblocks:** multi-grid, real-time exploration,
and every seam where the current model already leaks.

**Settled 2026-08-10. The lattice stops being where things live.** A unit, a part and a placement all
carry a **`Vector3` parented to a grid**, and a **grid is a coordinate frame** — an offset and an
angle — not an address space.

#### Why the cell model does not survive its own use cases

- **Real-time exploration is coming.** Movement outside combat should be natural and ungridded, so
  three players are not waiting on someone to walk three tiles. **A discretization that only holds
  during combat is not the representation** — it is one mode's rule.
  - **Real-time is player-only.** No AI participates: anything that has to move during it is
    **scripted, not intelligent**. So the mode adds no planning problem, and the scorer's world stays
    turn-based and lattice-enumerated.
- **It already leaks at grid borders.** If a neighbouring grid is offset 0.2, *"move one cell"* needs
  float maths at the seam. So the abstraction fails precisely where it was supposed to earn its
  keep — and you end up carrying float positions *and* a cell address to keep in sync, which is worse
  than either alone.
- **Adjacency was never the question.** `distance_chebyshev(a, b) == 1` is a proxy for **reach**, and
  reach is a real quantity that varies by shell and by what is attached. **A unit with no arms is not
  adjacent to anything in the sense that matters.**
- **The codebase has been voting for three blocks.** taskblock-52 made shots march real geometry;
  taskblock-58 made sight geometric and retired `Grid.opacity`; taskblock-60 replaced ramp-as-category
  with a continuous `step_height`. `Unit.height`, `orientation` and `mp` are already floats. **The
  remaining cell-shaped consumers are LoS stepping and `Cover.is_covered_from`, both already recorded
  as wrongly flat.**

**Rejected: `(grid, cell)`.** Keeping an address *and* a frame is a 2D system deriving 3D coordinates on
demand, and it keeps both costs to buy neither benefit.

#### What a grid is for, once it stops being storage

- **A transform.** Offset and angle. **Transfer between grids is an inverse transform**, and snapping on
  arrival is round-to-lattice. Decimal offsets and skewed angles are what a transform is *for*.
- **A lattice, on request.** Cells become **a query over the frame** rather than where things are
  stored. Authoring still wants them — sections, claims and spawn regions are naturally cell-shaped —
  and so does the player's mental model during combat.
- **A candidate set for the AI**, and this turns out to be cheap. The planner scores roughly 900
  candidates a turn and a lattice hands it a finite enumerable set — **continuous storage does not force
  continuous candidates.** A unit stands at a `Vector3`; the planner enumerates lattice-aligned
  destinations from wherever that is. **The AI never reasons about continuous position**, because it only
  scores in combat and real-time has no scorer in it at all.
  - One consequence rather than a problem: after real-time movement or a knockback a unit's **current**
    position may not sit on the lattice, so *"stay where I am"* is one candidate that is not a lattice
    point. An extra entry in the set, not a sampling rule.

#### Two things to settle before committing

- **Determinism under floats.** *Same seed, same battle* is a hard rule. IEEE754 is deterministic for
  identical operations in identical order, so this holds within a platform; **cross-platform is the open
  question and is worth answering before positions become float, not after.**
- **`CELL_SIZE` is already lying.** `unit_geometry.gd:197` records that something *"quietly dropped the
  `/ CELL_SIZE`, which is right only while a cell happens to be 1.0 across."* Invisible today, and
  **real the moment two grids disagree on cell size** — which is exactly this work. Fix it while it is a
  one-line correction.

#### What this unlocks, restated

**More than one grid.** A ship half is a grid, the other half is another, **and vacuum is a third.**
Offset by decimals, at any angle, with **a 45-degree grid over the 90-degree one** so things a unit
walks inside can be placed prettily.

- **Jump jets between ships** become a frame transfer, not a special-cased animation.
- **Being boarded at a compound angle** — an enemy ship docked skewed and above — stops being a floor
  plan: **you shoot up, and you hide under roofs rather than behind walls.**
- **Vacuum-as-a-grid pays twice**: zero-g movement becomes ordinary movement in a different frame, so
  mag boots, drifting and jump jets reuse the pathfinder.

**Cover is the real dependency and it is flat.** `Cover.is_covered_from` walks `Grid.line` between two
`Vector2i` with no height in it — a threat directly above is, to the AI, in the same cell. **The ray
chain already resolves 3D, so shooting up works today**; it is the AI's cover model that is a floor
plan, and a compound-angle boarding is renderable before it is playable.


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

### The editor's remaining gestures
**Needs:** nothing except where noted. **Unblocks:** authoring a board without knowing what the tools
did not do.

Eight things an author reaches for and does not find. Grouped because they are one session's worth of
work, not because they are one mechanism.

#### Map things need to be visible

**A claim and a spawn marker are invisible or nearly so**, and they are the whole point of Map Thing. **One debug-menu toggle, on in editor view and forced off in player and spectator view** —
these are authoring aids and a player must never see them.

- **Claims get floating letters at half transparency** — `EXT` `INT` `ENT` `EMP` `MER` — over the
  volume they belong to. The colours already distinguish them; the letters make a screenshot readable
  and survive someone being colour-blind.
- **Spawn markers become a coin-shaped primitive on the tile**, with the squad letter stamped on it.
- **`spawn_none` folds into `remove`.** It is an eraser, and there is already an eraser — a marker
  should be placed and removed the way everything else is. That drops the tool count by one and removes
  the only verb whose job was undoing another verb.

#### A chance is a part, not a map thing

**It occupies a cell and stops a unit entering it, which is what a part does.** The only thing unusual
about it is that *at authoring time you do not yet know which part it is* — and that is a property of
the placement, not a different category. It moves out of Map Thing.

**It needs a model that reads as unresolved.** Distinct from a fixed cover *and* from a claim: a
pseudo-wireframe, or a rolling gradient. **Not lime** — vibrant lime is the Interior claim, and the two
greens were deliberately separated once already.

#### Extraction declares a region, not cells

**Extraction cells are not authored and should not be.** They come from `MissionState.team_extraction_
cells`, and taskblock-59 found the editor re-stamping the *previous bout's* markers onto an authored
board every redraw — an authored board has no mission, so it correctly draws none now.

**What is missing is a way to say where they land.** A Map Thing declaring *extraction happens in this
region*, which the mission then resolves into cells at start. That keeps the board authored and the
mission generative, and it is the same shape as the section vocabulary's other declarations — an
authoring-time statement that never survives placement.

#### `New Map`

A button that resets to blank, behind a **"have you saved?"** prompt with continue and cancel. Nothing
else in the editor can lose work; this can.

#### Q and E rotate
**Needs:** *Blockers need a real transform.*

Counter-clockwise and clockwise. **Shown in Unit Resources under editor view, and only while the
selected thing can actually rotate** — a permanently-visible hint for something usually unavailable is
noise.

**Gated deliberately.** taskblock-59 built the veneer's derived facing and reverted it: a placement
carrying a facing nothing renders is exactly the visual/logic disagreement that block spent its time
removing. **Rotation needs the render half to exist first**, or it is the same build-and-revert.

#### Uniform walls, and authored ship weakpoints

**The goal is a hulk that cracks.** A full battle — tanks, commandeered artillery off a shipment —
should be disastrous for the ship it is fought in. Two rules get that, and they pull in opposite
directions on purpose:

- **Every default wall is 1x1, so failure is predictable everywhere.** A wall broken on one side of the
  ship breaks exactly like a wall broken on the other. That uniformity is what makes damage readable
  rather than arbitrary, and **it is why the default height should be short enough that stacking is the
  normal way to build tall** — a full-height wall that can also be stacked says the same thing twice and
  hides the failure points stacking exists to create.
- **An authored weakpoint is one large part**, a *fake* wall at 3 x 5 x 0.2, and it fails **as a single
  piece**. A stray grenade takes the whole thing and the moment reads as *"there's an opening there
  now"* rather than *"one more bit of wall broke, like everywhere else."*

**This is what `MapPlacement.size` and the Scale tool are actually for.** Not "walls can be any size" —
**walls are uniform unless an author deliberately built a failure**, and the scale tool is how that
deliberation is expressed.

**Not the same thing as `Weak points`** below, which is a *part* exposing a vulnerable window under a
condition — a reactor venting heat. This is the *ship's* structural weakness, authored into the board.
Same word, two systems; keep them apart.

#### The veneer cannot snap upward, and there is a fix

**CC's finding:** *a veneer grown upward can never snap — a top-face pick strikes the top of the stack
by definition, so there is never anything above it. Growing down snaps correctly.*

**The proposed fix: a growing veneer is twice as thick, centred on the edge.** It grows until it strikes
something above, then **drops to its real thickness and takes the height of what it struck.** Not
exhaustive — there are edge cases it will not catch — but it handles the common case, and the scale
tool covers the rest.

### Declare a completion standard, then tune to it
**Needs:** *Author the intelligence tiers* (landed, taskblock-59). **Unblocks:** any statement about
whether the AI is good enough.

**Raised as `BR45.03` and removed from the ledger — it was a deviation without a standard.** The entry
read *the planner completes 54.2% of missions where the planner it replaced completed 87.5%*, which
measures a change against a baseline nobody ever declared correct. **87.5% was a number the old planner
happened to produce, not a bar it was meeting.**

**And taskblock-59 inverted the comparison** by authoring the intelligence tiers, so the figure the
entry rested on describes a roster that no longer exists.

**What is actually needed, in order:**

- **A completion standard, stated per tier.** An all-`MINDLESS` squad cannot shoot at all, so its rate
  should be low — *how* low is a design answer, and without one a bad number and a correct one look
  identical. The same question for a mixed roster, which is what a real mission has.
- **`seeds_to_first_win` is the metric**, not a rate. It degrades gracefully where a threshold on a
  small integer count does not — which is what put `MIN_COMPLETION_RATE` a fraction of a seed from red
  and got it lowered rather than investigated.
- **Then tune to the standard**, and only then is a deviation from it a defect worth filing.

**The general rule this came from is in `BUGS.md`'s header:** a number that moved is evidence; a number
that is wrong needs a bar to be wrong against.

### Hunt down the prototype remnants
**Needs:** nothing. **Unblocks:** trusting that a `Vector2` in a 3D game means what it says.

**`Vector2` keeps turning up in strange places**, and the pattern is that they are artifacts of the
**pre-3D flight test** the project was built on top of. `BR51.01` is the worked example: a **cell
address in a slot meaning (lateral offset, world height)**, which nothing clamped and nothing caught.
**The type was right and the coordinate space was wrong.**

**403 uses across 74 files**, concentrated in `damage_resolver` (28), `shot_plane` (21),
`battle_layout` (19), `tactics_controller` (17) and `body_projector` (16). The first two are exactly
where a mix-up is expensive.

**Narrow the question before starting.** The useful audit is not *where is `Vector2`* — it is **which
coordinate space is each one in, and does anything cross spaces without converting?** At least four are
in play: cell coordinates, plane space, screen space and UI pixels.

- **The cheap 80% first:** give the spaces distinct names or type aliases so a mix-up is visible **at
  the call site** rather than found by measurement three blocks later. That may be the entire fix.
- **Then the sweep**, for the ones that survive naming.

**This is one instance of a larger job.** The prototype's assumptions are still load-bearing in places
nobody has looked — flat coordinate spaces, a single grid, `Grid.opacity` (retired taskblock-58), the
2D cover check that is still flat. **Recording it as a hunt rather than a single audit, because the
`Vector2` case is the one that has been noticed and probably not the only one.**

### A pathfinding and scoring overlay — OUTLINE, needs refinement before it is built
**Needs:** nothing technically. **Unblocks:** the supervisor comparing their own judgement against the
AI's; a diagnostic for `BR52.10` and its relatives.

> **This item is an outline, not a spec. Do not implement it from this text.** The supervisor has
> flagged that parts of the framing below run contrary to what they actually want, and will refine it
> before it is picked up. **Everything past the first paragraph is a starting position to argue with.**

**The ask, in the supervisor's words:** *a lightweight version of what the AI is doing, overlaid on a
controlled unit's view with a checkbox — each tile shows a weight, so I can compare what I'd do with
what an AI would do.*

---

Notes toward a refinement, offered as material rather than as decisions:

**Two different numbers exist and they answer different questions.** *MP to reach this cell* is the
accumulated cost from the reachable flood and answers **how far**. *What the AI would pay to stand
here* is the utility score and answers **where would the AI go**. The second is closer to the stated
goal; the first is cheaper and may be what is wanted anyway.

**Most of the data already exists.** `ai_decision_log` records `{label, action_id, cell, score,
offered, trace}` per candidate — a score per cell, a per-consideration trace, and the distinction
between *not offered* and *offered and scored zero*, which its own header calls most of its value.

**The one structural constraint worth carrying into any refinement:** whatever it draws should come
from **running the real scorer** against the unit in preview, not from a second implementation. A
second scorer means the overlay can disagree with the AI it is meant to reveal, and that is the
parallel-systems rule with a display attached.

**Open, and deliberately not settled here:**

- Whether a tile shows one number or a number per utility action. `approach@cell` and `shoot@cell`
  score differently, so a single figure is either an aggregate or a choice of which action to view.
- Whether hovering should expose the trace, or whether that is more than the tool wants to be.
- Whether the AI's own chosen cell should be marked.
- Whether this is a player-view tool, a debug-menu tool, or both.

**Worth knowing regardless of shape: this is CC's diagnostic too.** It is plausibly the thing that would
have shown `BR52.10` — an AI firing a full burst through the ally in front of it — as a cell scoring
high where a squadmate stands, rather than as a battle report nobody could explain.

### Legs must match, and mismatch degrades movement
**Needs:** `step_height` on parts (landed, taskblock-62). **Unblocks:** leg damage meaning something
before the leg is gone; a shell built wrong reading as built wrong.

**Parts that connect a shell to the ground should match**, and the cheapest way to author that is a
**leg length**. Mismatch is then a spectrum rather than a rule: **a slight difference makes a unit limp
and spend MP inefficiently; a major one forces it to a crawl.**

**taskblock-62 already built the first half of this intuition.** `Unit.step_height()` returns **0.0**
for a shell with only one authored leg — *"an offer with nothing to push off"* — so the code already
says a matched pair is what lets you step up. **One leg cannot push off; two mismatched legs can push
off badly.**

#### Reach and cadence are separate, so `MAX` stays right

**A long leg buys reach; matched legs buy rhythm.** One long leg and one short leg lets a unit take a
**taller single step** — the long leg genuinely reaches — and hampers it taking **several in a row**.

So `Unit.step_height()` resolving as **`MAX` across authored offers is correct and does not change.**
The mismatch penalty lands entirely on **cost per step**, a different quantity: **a limping unit is not
stepping lower, it is paying more for each one.**

Two independent axes, and keeping them apart is what makes the model cheap:

| | quantity | resolved by |
|---|---|---|
| **Reach** | how tall a single step can be | the **largest** offer among ground contacts |
| **Cadence** | what a step costs | penalised by the **spread** among them |

**Knock-on worth noting: it interacts with *Momentum* for free.** Momentum accumulates with movement, so
a unit paying more MP per cell covers less ground per turn and arrives with less of it. **A limp costs
you the charge as well as the distance**, with no rule saying so.

#### The spread is across ground contacts, not a pairwise difference

**Not "the difference between leg A and leg B".** A quadruped with three legs at 1.0 and one at 0.6 is
a different animal from one with two at 1.0 and two at 0.6, and a tripod or a single-tracked chassis
has to answer too. **The quantity is the spread among however many ground-contacting parts exist.**

#### Battle damage gets it for free, which is the sign the rule is right

**A leg shot off is the most extreme mismatch there is.** So one rule covers a shell built wrong, a
shell damaged mid-fight, and a shell hastily repaired with whatever was to hand — **and losing a leg
starts mattering before it is gone**, which it currently does not.

#### Two forks to settle before it is built

- **Does leg length replace `step_height` as the authored stat, or sit beside it?** Now that reach and
  cadence are separate the question narrows: **`step_height` is the reach offer, and length feeds the
  spread that sets cadence.** They may genuinely be two quantities — a hip joint decides lift as much as
  length does — in which case both are authored and neither derives. **Cheaper if they are one; do not
  force it if they are not.**
- **Limp and crawl are graded states, and the thresholds are balance numbers.** State them; do not
  invent them. The shape is the surrogate ladder's — a spectrum with named rungs, not a boolean.

**Crawl is a pose**, so `Poses` already carries the mechanism; a limp is an MP multiplier, and `mp` is
already a float. **Neither needs new machinery** — what is new is the spread and what it maps to.

#### A mismatched body needs somewhere to bend, and there is nowhere

**A unit standing on legs of different lengths has to compensate** — a slanted hip, or a bent knee — and
**neither joint exists.** `torso.tres` carries `HIP_L` and `HIP_R` **sockets**, and `leg.tres` attaches
straight to them; a leg's only sockets are `ARMOR` and `CLADDING_LEG`. **There is no articulation
anywhere between torso and foot**, because the torso rolls the hips into itself.

**So this item has a part-tree dependency it did not know about:** either a **hip segment** between
torso and leg that can slant, or **leg segments with a knee**. Both are content plus a socket-vocabulary
addition rather than code.

**This is dangerously close to inverse kinematics**, and worth naming so it is entered deliberately.
The cheap version is a **canned pose per severity rung** — limp and crawl are named states, not a
continuous solve — which is what `Poses` is already for. **Solve for the joint angles only if the canned
poses read badly.**

**Matched legs raising the hip needs none of this**, which is why the standing-height work is separable
and comes first.

### Should a map roll its own chances at load?
**Needs:** nothing. **Unblocks:** deciding what a `MapFile` is before the editor grows more gestures.

**Today a section declares chances and a map does not.** `SectionFile` carries `maximum_clutter`,
`banned_clutter`, `minimum_garrison`, `maximum_garrison` and per-cell clutter chances; `MapFile` carries
placements, spawns and nothing else. The recorded reasoning was *a placed board has a barrel or it does
not; it has no 40% chance of one.*

**The supervisor expected otherwise** — that a full map could also declare a chance, filled on load.
**Worth deciding rather than inheriting**, because it changes what the format is.

- **The reproducibility objection is already solved.** A seeded roll makes `load(map, seed)`
  deterministic, which is the same mechanism `preview_section` uses today.
- **It moves the map/section line somewhere cleaner.** The distinction stops being *declarations versus
  none* and becomes **composability versus none**: a section has edges, claims and join rules; a map does
  not. **A map becomes a template until it is loaded**, which is a more useful thing than a finished
  board.
- **It buys variety without authoring N maps.** An authored board replayed twice is currently identical,
  and a hand-made encounter is exactly the thing that benefits from a little variation.

**The cost to weigh:** *load `proving_ground` and reproduce the bug* stops being unconditional and
becomes *load it at this seed*. That is a real loss for a debugging surface — and it is the same trade
the completion sampler already makes deliberately.

### A pathfinding node is a surface, not a cell
**Needs:** nothing. **Unblocks:** the stacked mag lift; `A cell holds one blocker`; catwalks,
mezzanines and gantries; and it is the first instalment of *Position is a `Vector3` in a grid's frame*.

**`Surface.first_walkable` returns the *first* walkable surface in a cell, and the pathfinder uses only
that.** `Grid.surfaces_at(cell)` is an `Array` — a cell can genuinely hold several walkable heights —
but **to movement a cell has exactly one floor.**

**So the stacked mag lift is not a special case that broke. It is the first thing to make an existing
limitation visible.** A catwalk over a floor, a mezzanine, a gantry above a deck: all unrepresentable
to movement today, because the second walkable surface in a cell cannot be addressed.

taskblock-63 declined to stack the lift's two pads for exactly this reason — *stack both pads in one
cell and the path-cost difference is identically zero, because the cell has not changed.* **True, and
the cause is that a cell has one address and one height.**

#### The change

**A node becomes `(cell, surface)` rather than `cell`** — the standard multi-level formulation, where
nodes are (x, z, level) rather than (x, z).

| | today | needed |
|---|---|---|
| node | `Vector2i` | cell **and which walkable surface** |
| walkability | `first_walkable != null` | per surface |
| neighbours | eight cells | surfaces reachable **from this surface** |
| cost | cell to cell | surface to surface |

**This is a strict subset of *Position is a `Vector3` in a grid's frame*, not a competing design.** That
item makes cells a query over a frame; a node keyed on a surface is the same idea **arriving in the
pathfinder first**, and it is the piece the lift actually needs.

#### Three things to settle when it is picked up

- **A ride becomes an edge, not a teleport.** Two surfaces in one cell with an AP-priced edge between
  them **is** an elevator — a unit ends up vertically displaced *in place*, which is what a lift does.
  **The neighbouring-pad model was a workaround for nodes not existing**, and it should retire with the
  limitation rather than being kept alongside.
- **`lift_advance` gets a real measurement.** Today it compares path cost at the **partner cell**. With
  surface nodes it compares path cost at the **upper surface** — which genuinely differs, because
  reachability from up there is different. The consideration stops being a proxy.
- **Measure the blast radius before committing.** `is_walkable`, `move_cost`, `reachable`, the AI's
  candidate enumeration and `Cover.is_covered_from` all take `Vector2i`. **This is the 360-`.cell`
  question one layer down**, and it wants counting rather than assuming.

### The chaingun dead end — three shapes, and one is a design call
**Needs:** nothing. **Unblocks:** `BR63.04`; any roster armed with a burst-only weapon.

**A chaingun unit cannot fire.** `shoot` wins the selection and `AttackAction.is_legal` then refuses it
on `provides_a_single_pull` — correctly. The three fixes are not equivalent and only one is a repair:

1. **`_find_weapon_id` stops picking a weapon the planner cannot use.** Smallest change. Makes a
   chaingun unit fall back to whatever else it carries — **often nothing**, so the unit still does not
   fight.
2. **A `weapon_provides_this_action` precondition.** Stops the action being *offered*, so the decision
   log stops showing a choice that cannot happen. **Honest, and still gives the unit nothing to do.**
3. **A `burst` utility action offered to `GRUNT`.** The only option that lets a chaingun grunt actually
   fight — **and a design call, not a repair.** It decides whether grunts get automatic fire, and
   `suppress`'s existing `TRAINED`/`ELITE` gate says somebody already decided they should not.

**1 and 2 are both worth taking regardless** — a planner that selects an unusable weapon and an action
offered where it cannot execute are defects on their own terms. **3 is the supervisor's.**

**And the seam is the real finding.** No test crosses between *what a generated bout arms* and *what the
planner can offer*: headless bouts pick presets that provide `shoot` and fired 481 rounds during
taskblock-63's own gate while this was live. **That gap is worth a test more than the fix is.**

### Bout modes
**Needs:** nothing. **Unblocks:** bouts that end for reasons other than extraction; a reason to fight
rather than to leave.

**Three modes, and only the first exists:**

- **Try to Extract** — today's. Both squads race for their extraction points.
- **Deathmatch** — no extraction at all; **the only objective is to destroy the other squad.** The
  cleanest test surface the AI could have, because every non-combat action stops competing.
- **Defend** — **squad 0 has no extraction condition and squad 1 does.** An asymmetric objective, which
  is the shape most real missions have.

**Deathmatch is worth building first for a reason beyond content**: `seeds_to_first_win` and every AI
measurement currently run against a mode where *leaving* is a winning move, so a squad that never fires
can still complete. **A deathmatch bout cannot be won by walking away**, which makes it a far sharper
instrument for exactly the class of defect `BR63.04` and `BR63.05` are.

### Spotting interrupts movement
**Needs:** the mid-move interrupt hook (built — `MoveAction` and `ClimbAction` both check it).
**Unblocks:** a unit not walking blindly past something it just noticed.

**Seeing an enemy for the first time should stop a move, the way overwatch does.** The machinery exists:
`MoveAction` already checks a trigger at each cell it steps onto, and taskblock-53 gave `ClimbAction` the
same. **This is a second trigger on the same hook, not a new mechanism.**

- **First sighting only.** An enemy already known does not re-interrupt every cell.
- **It is a player-facing rule as much as an AI one** — a queued multi-cell move that walks into a
  previously-unseen enemy should stop there rather than completing, which is the same fairness argument
  overwatch rests on.
- **Pairs with the die-roll rule below**: a spotting is information the player did not have when they
  queued, so it is exactly the kind of event that should re-open planning.

### The player wins battles; the design wins the war
**Needs:** the meta layer for the loop it describes. **Unblocks:** knowing what an AI unit is *for*.

**A cornerstone, and it settles a question that keeps coming back as a balance argument.**

**The player's frame is the battle.** They are trying to win this fight, on this hulk, today.

**The design's frame is the war.** An AI squad will rarely beat a competent player outright, and **it
does not need to.** What it needs to do is **cost** — parts, ammo, a matrix's recovery time, a shell
that has to be rebuilt before the next raid. **The more damage a losing squad does, the more the player
has to compensate**, and the next raid is run more carefully or with less.

**So AI competence is measured in attrition, not in wins.** That reframes several open questions:

- **A completion rate is not a difficulty dial.** A squad that always loses but always takes an arm with
  it is doing its job; one that loses cleanly is not.
- **It is why `seeds_to_first_win` is the right shape** and a win rate is not — the interesting number
  is what a fight *costs*, and a binary outcome cannot express it.
- **It is also the argument for the parts economy mattering.** Damage that is free to repair is damage
  that did not happen, and an enemy that only ever costs time is not applying pressure.

**Worth stating because the alternative reads as a bug.** An AI that loses most fights looks like a
broken AI, and by this cornerstone it is the expected shape — **the defect would be losing *cheaply*.**

### Explosions do not interrupt the burst that caused them
**Needs:** *Explosions: three types on one substrate*; `ResolutionPlayer`'s timeline. **Unblocks:** a
burst reading as one continuous action.

**If a barrel detonates mid-burst, the burst keeps firing and the explosion plays over it.** The rounds
do not pause and wait; both play **concurrently**.

**This is a playback rule, not a resolution one.** The shots and the detonation already resolve in a
defined order; what is at stake is whether the *drawing* serialises them. **Today's player plays events
in sequence**, which would show a burst stopping dead while a barrel goes up and then resuming — and a
chaingun visibly pausing mid-magazine is the kind of thing that reads as a hitch rather than as a
consequence.

**It generalises past barrels.** Anything a shot triggers — a cook-off, a collapse, a unit falling —
should overlay the action that caused it rather than queue behind it. **The timeline needs concurrent
tracks**, which is the same machinery animation will want.

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


### Melee against non-unit PART targets
**Needs:** a reach-measurement design call.

`PartPicker`/`HitKind.PART` covers **ranged** weapons only; every motivating example (finish a downed bot,
destroy cover, hole a wall) is naturally ranged. Melee was deliberately left untouched: `is_legal()` calls
`MeleeReach.in_reach(...)`, which needs a real target *Unit* body to measure against. Extending reach to a
bare Part is its own question — does reach measure against the part's own box, or the whole blocker assembly's
AABB? Melee correctly rejects a PART target today; this is the follow-up to make it possible, if wanted.


### Animation, and the promise that what you see is what you get
**Needs:** nothing structural. **Commissioned models are not a prerequisite** — the rig is the socket
tree with per-socket `Transform3D` overrides, and **animating boxes is still animating.** Interpolation,
the clock and pose sequencing are all buildable and testable before any art exists. **Unblocks:** units
reading as inhabited rather than as posed boxes; a ragdoll; anything else that needs motion over time.

**What is missing is time, not structure.** Poses are discrete states applied instantly; animation is
interpolating between them — a `Transform3D` lerp per socket against a clock, and `ResolutionPlayer`
already runs a playback clock for tracers, hit flashes and inter-shot gaps.

**A ragdoll is the cheap first target, and it splits into two builds.** A **canned collapse** — a pose
sequence dropped over some hundreds of milliseconds — is deterministic, needs no physics, and uses only
what exists. A **physics ragdoll** needs `Skeleton3D` and `PhysicalBone3D`, which means the view builds
a *skeleton* from the socket tree rather than today's flat `MeshInstance3D` per box.

**The skeleton question is the one worth deciding deliberately**, because commissioned art arrives as
rigged assets and `Part.mesh_scene` already anticipates them — so the view becomes skeleton-shaped
eventually either way. **The rule that keeps it safe: the socket tree stays the authority and the
skeleton derives from it, one direction only.** A bone that can be posed independently of its socket is
where two representations of one body start disagreeing.

**A ragdoll is also the first thing here that legitimately need not be deterministic.** It happens after
the unit is gone and nothing reads where the limbs land — the *pretty on top of powerful* split arriving
for real. **Worth stating**, because determinism is a hard rule everywhere else and someone will apply
it here reflexively.

**Units get idle movement that depends on their shape and their parts.** A spindly frame sways
differently from a squat one; an arm that is gone does not idle.

**And that collides with the transparency pillar** (`docs/08`, `docs/10`): *what the player sees is what
they get*. If a unit's parts are visibly swaying, then **the frame the player is looking at has to be
the frame the resolver used** — for aiming, for the shot plane's projection, and for detonation
geometry. An idle that moves a torso two inches while the dartboard says otherwise is the doctrine
breaking in the most visible possible way.

- **Not everything needs frame accuracy.** Line-of-sight and similar coarse queries can run against
  **frame 1 or a mid-frame pose** — a stable reference — as long as the choice is stated and the sway
  is small relative to the question being asked. **Aim and detonation cannot**; those resolve against
  what is drawn.
- **Slow-motion while aiming is the reconciliation.** Idles keep playing, the player has time to read
  the pose, and the frame the shot resolves against is one the player actually saw. It makes the
  determinism cost feel like a deliberate effect rather than an impediment.
- **The shot plane already projects from a real pose** — `Poses` and `assembly_placements` are pose-aware
  — so this is a question of *which* pose, not of adding pose-awareness. That is the good news.
- **Animation frames must be addressable and deterministic.** A frame index that advances on wall-clock
  reintroduces exactly the machine-dependence `PlanPacer` is being fixed for.

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
