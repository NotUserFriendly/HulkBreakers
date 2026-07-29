# 11 — AI: World Model, Utility & Tiers

How a unit that isn't being driven by a player decides what to do. Landed taskblock-44 (the seam and
the visibility field) and taskblock-45 (the scorer), replacing a branch-cascade planner that is gone
and should not be reasoned from — see `SUPERSEDED.md`.

---

## The world model is a chokepoint, not a convention

**A planner takes a `WorldView`. It never touches `CombatState`.** The view is the only channel through
which a unit learns anything, and that is what makes intelligence tiers possible at all: retrofitting
"this unit doesn't get to know that" onto a planner already reading global state touches everything.

### The boundary runs through objects, not around them

The line is **knowledge about units** versus everything else. It is *not* `CombatState` versus
not-`CombatState`, and two of the obvious pass-throughs sit on the wrong side of it:

- **`Grid` is not pure geometry.** It carries `occupant_id` alongside `blockers` and `surfaces`. Handing
  a planner a raw grid leaks the position of every unit on the board, including ones the view just
  filtered out. Occupancy reaches a planner **only** through `units_visible_to(observer)`.
- **`BatchPlan` is team knowledge, not infrastructure.** The blackboard is a tier capability
  (`BLACKBOARD_TIERS`), so batch plans are observer-parameterized like visible units are — and the
  *write* is gated too, since a unit that can set a plan it cannot read back is worse than one planning
  alone.

Static geometry is never gated. A unit standing in a room knows where its walls are; what it doesn't
know is who is behind them.

### The resolver door

`canonical_state_for_resolvers()` hands the real state to `ShotPlane` and friends, because geometry
must resolve objectively no matter what a unit believes. **It may be passed as an argument and never
dereferenced** — `view.canonical_state_for_resolvers().units` defeats the entire seam, and it is a hole
rather than a door if nothing enforces that.

Three guard tests hold this, plus one that checks the guards are reading a planner that actually uses
the view — a guard whose subject is absent passes forever.

A unit planning against a *remembered* enemy position asks the resolver about geometry to a cell. The
resolver answers correctly; the unit's error is in choosing the cell. **Degraded knowledge never means
degraded geometry.**

---

## `ShotPlane` is final; the visibility field is a prefilter

Line-of-fire is answered from **one symmetric shadowcast per target**, stored as `PackedInt64Array`
bitboards over the volume, so a candidate cell's query is a bit test rather than a cast. One field
serves every shooter, so cost stops scaling with unit count.

The field carries exactly one correctness obligation:

> **It never reports "no line" for a cell that actually has one.**

Over-inclusion is safe; under-inclusion is a bug. That is a far weaker burden than exactness, and it is
what keeps the field from becoming a second visibility system able to disagree with the canonical
resolver (`02`, `08`). The field narrows candidates; `ShotPlane` confirms the survivors.

The payoff is asymmetric and deliberate: when *no* reachable cell has a line, `reachable & vis[target]
== 0` settles it in one word operation with zero `ShotPlane` builds. Proving a negative used to cost
more than finding a positive.

---

## Scoring

### Two things are called "action" — keep them apart

| | What it is | Who uses it |
|---|---|---|
| **Executor** (`src/logic/actions/*.gd`) | `AttackAction`, `MoveAction`, `OverwatchAction`. The thing enqueued and run through the resolver. | **Player and AI** |
| **Utility action** (`UtilityActionDef`, `data/utility_actions/*.tres`) | Preconditions, considerations, `base_weight`, and an `executor_id` naming one of the above. | **AI only** |

Bare "action" in this document means the **executor**. The AI-side wrapper is always a **utility
action**. Getting this backwards is how a selection concept ends up on the player's action bar.

`utility_executors.gd` is the single seam between the two, and it **reimplements nothing** — an
`executor_id` resolves by delegating to `ActionCatalog`, the same registry the player's action bar
reads. That is what keeps "no parallel systems" true: the AI still derives what it can do from what
parts provide.

Four ids resolve locally instead, because `ActionCatalog` has no entry for them and **should not** —
that registry is what the player is *offered*, and these are not buttons. `hold_position` is the
worked example: "stand still so a shot clears an ally" is a selection outcome, not a verb anyone
presses. Note the live collision it sits next to — `ActionCatalog`'s `&"hold"` is **`GrindAction`**,
the many-hit melee, an entirely different thing from the AI's `&"hold_position"`.

### The model

| Concept | Implementation |
|---|---|
| Utility action | Resource: preconditions, considerations, `executor_id` |
| Consideration | Normalized 0–1 input × response curve |
| Score | Product of considerations × base weight × profile multiplier, with a compensation factor |

**Utility actions, profiles and batch objectives are `.tres` under `res://data/`**, not code — the same
rule as every other content vocabulary. Adding a behaviour is a resource plus a published input, never
a code edit. The scorer is a *selection* layer over executors that already exist, not a second
implementation of them.

**The product is not a sum.** A single zero vetoes that utility action outright, so "unreachable" kills a
candidate rather than merely lowering it. The compensation factor exists because otherwise a utility action
with more considerations always scores below one with fewer — a bias that looks like a tuning problem
and isn't.

**Ties need an explicit tiebreak.** On open ground a whole arc sits at exactly the standoff distance, so
equal scores are common rather than exotic. Serial iteration order is stable and hides it; any
reordering exposes it. Lowest cell index, decided once.

**The planner is resumable.** Candidate scanning yields and keeps a cursor, so a long plan does not
block input and the view can say which unit is thinking. Frame boundaries must never change a decision.
GDScript makes this structural rather than incremental — a conditional `await` is a parse error, so a
synchronous scorer written "to be made resumable later" means converting the whole chain again.

---

## Intelligence gates information, not just the action pool

**This is the load-bearing idea.** Gating actions alone produces a smart unit with fewer options, and it
still plays those options optimally — which reads as *limited*, not dumb. Gating the world model makes
it make real mistakes: firing at where someone was, walking into a flank it had no way to see.
Plausible-but-wrong rather than random.

It also aligns cost with design, which is rare: a degraded world model is genuinely cheaper to compute,
so **cheap units are cheap because they are dumb, not despite it.**

| Tier | Actions added | World model | Depth |
|---|---|---|---|
| Mindless | approach, flee, idle | current sight only | 0 |
| Grunt | cover, ranged, regroup | + last-known positions | 0 |
| Trained | flank, suppress, item, call help | + team blackboard, threat map | 1 |
| Elite | bait, ambush, set batch objective | + full team knowledge, predicted moves | 2–3 |

**What of that table is real, as of taskblock-46:**

- **Actions.** `shoot` and `take_cover` are gated to Grunt-and-above, `overwatch`, `flank` and
  `suppress` to Trained-and-above. `regroup` needs no action of its own — `hunt` is offered at every
  tier and only *does* anything once the tier has memory to hunt toward, which is the information gate
  doing the work the action gate would have duplicated. **`item`, `call help`, `bait` and `ambush` are
  not built**: none of them has an executor, and `call help` additionally has no mechanism — a unit
  cannot signal another unit's plan today, and the batch objective is the nearest thing that exists.
- **World model.** `MEMORY_TIERS`, `BLACKBOARD_TIERS` and `OBJECTIVE_SETTING_TIERS` in `WorldView` are
  the authored gates. Reading a batch objective and *setting* one are separate capabilities: Trained
  follows a plan, Elite makes one.
- **Depth.** `UtilityLookahead` is Elite's search. Depth 2 is the enemy's shot from where it stands;
  depth 3 is the enemy moving first and then shooting. It is expressed as **one normalized input**
  (`predicted_threat`, the share of known enemies that can bring fire on a cell) rather than as a
  separate minimax beside the scorer — a utility AI has one place to put "this option is worse than it
  looks", and giving a unit two ways to decide is the no-parallel-systems rule applied to the AI.
  Cost is bounded before it is paid: depth 2 costs one visibility field per known enemy and answers
  every cell; depth 3 costs one per cell and therefore runs over a fixed-size shortlist of the
  best-scoring cells.

`Unit.intelligence_tier` is a `StringName`, authored per unit; it should derive from Attributes once
those land. **Nothing authors it yet** — every unit defaults to `TRAINED`, so the Mindless, Grunt and
Elite rows (and therefore the whole lookahead) are exercised by tests and by hand only, and no measured
completion rate has ever included them. A capability nothing reaches is not shipped.

**Profiles are a separate axis** — weight vectors over shared considerations, never code paths.
Intelligence says *what a unit can know and do*; profile says *what it wants*.

A bout names a profile id directly (`Matrix.ai_profile`, `BoutRosterEntry.ai_profile`). The
`AGGRESSIVE`/`SKIRMISHER`/`MARKSMAN`/`COVER_SEEKER`/`PSYCHOTIC`/`TURTLE` playstyle vocabulary that used
to sit in front of it is retired: it mixed a temperament, a role and a preferred range into one word,
so it could not express "cautious but close-quarters" without a seventh name that would have mixed them
again — and all three axes are weights over shared considerations now, with standoff scored against the
unit's own weapon range. There is no list of profiles in code; the `.tres` files under
`res://data/utility_profiles/` are the list, and the bout maker's menu reads them.

**An unstated weight is a neutral opinion, and that is rarely what was meant.** `defensive` omitted
`seek_extraction` and therefore withdrew exactly as readily as `cowardly`, whose entire character is
wanting out — two rows of the table playing identically, which is the bug named below. A profile has to
state what it does *not* want as well as what it does.

**Every tier and every profile must decide differently from its neighbours on the same seed.** A table
where two rows play identically has a bug in it, and no completion metric will catch it. This is the
acceptance that matters most whenever the table grows.

---

## Batches amortize; they never act together

Units act one at a time in initiative order, and batching does not change that. A batch is a device for
computing the leader's expensive work **once** and reusing it — never for resolving several units
together. "These units could be decided at the same time" is not a licence to act them at the same time.

**The leader is derived, not stored:** it is whichever member of a batch acts first this round. That
makes leader death free — the next-fastest living member is simply first next round — with no promotion
logic and nothing that can desync. Do not add a `leader_id`.

The leader's coarse utility pass picks one objective (`advance`, `hold`, `withdraw`, `flank`), which is
injected as **a consideration input** for every follower rather than a destination to copy. Followers
keep their own judgement; they just share a direction. Blackboard access is tier-gated, so a `MINDLESS`
member plans alone — correctly, not as a gap.

---

## The decision log is the instrument

A behaviour tree fails legibly: it took a branch and you can see which. **A scorer produces a number,
and you reconstruct why afterwards or not at all.**

`ai_decision_log.gd` records, per decision: every candidate and its score, **each consideration's
normalized input and curve output** (a veto is invisible in a product — "which consideration returned
zero" is the question that gets asked), the acting tier and profile, what the unit could see, and the
margin over second place.

Every planner defect found in taskblock-45 came out of reading this, not out of reading the code. It is
the first place to look, not the last.

---

## Two failure modes worth naming

**A utility action pool can have a hole in it.** Predicates partition the pool, and a unit matching none of
them is offered nothing at all and idles. This has happened: every action was gated behind either
`enemy_known` or `is_player_squad`, so a non-player squad that had seen nobody had no action available,
and bouts ran to the turn cap with nothing wrong in any individual rule. **When adding a gated utility action,
ask what a unit that fails every gate does instead.**

**A tier or restriction that does nothing passes every test that asserts what it should do.** The
companion assertion — that turning it off changes the outcome — is the one that catches it.

Two corollaries, both learned the hard way in taskblock-46:

- **Compare the whole capability, not the column you happened to think of.** Elite and Trained were
  briefly indistinguishable because the comparison read the action pool and Elite's entire difference
  was in the other two columns. A tier is actions *plus* world model *plus* depth; comparing one third
  of it declares two rows identical that are not.
- **A board that cannot express a difference is not evidence there is none.** The profile comparison ran
  on a board with no mission, so the profile that wants to leave had nowhere to go and read as identical
  to one that merely likes cover. Before concluding two rows play the same, check that the fixture
  offers both of them what they want.
