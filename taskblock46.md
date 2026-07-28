# Taskblock 46 — Fix the ground, then fix the AI

*Closes `PLAN.md` QUEUED *Raised rooms generate at level 0* and NEXT item 2 *The AI action pool*.
Depends on taskblock-45.*

Two bodies of work that are discrete in code and **coupled in measurement**. The map fix changes what
every seed generates, and the AI work is judged by a completion rate measured across seeds. Landing
them in the wrong order produces a headline number that cannot be interpreted — the exact failure
taskblock-45 spent three readings learning.

So: **fix the ground, re-baseline on it, then change the AI.**

**Vocabulary, because two things are called "action".** An **executor** (`src/logic/actions/*.gd`) is
the thing enqueued and run through the resolver, and it is shared — player and AI emit the same ones.
A **utility action** (`UtilityActionDef`, `data/utility_actions/*.tres`) is the AI-side wrapper:
preconditions, considerations, and an `executor_id` naming an executor. **Everything this block adds is
a utility action.** No new player verbs, and nothing here reaches the action bar — `ActionCatalog` is
what the player is *offered*, and `utility_executors.gd` delegates to it rather than duplicating it.
See `docs/11`.

**Standing rule 5 applies throughout.** Units act one at a time in initiative order. Nothing here is a
licence to resolve several together.

---

# PASS A — Raised rooms generate at level 0

**BR40.03** (scattered cover) and **BR40.04** (extraction and spawn tiles) are one cause: `MapGen`
places objects without reading the containing room's level, so they sink to the bottom of a raised
room.

BR40.04 is not cosmetic. Across a 40-seed sweep, **8 of 80 spawn zones (10%) come out with
non-uniform floor heights**, and 4 of those 8 sank a cell a two-unit roster would occupy. A unit
spawning on a sunk cell has **exactly one reachable cell** — climbing is gated on `Shell.can_climb()`
→ the `CLIMBER` part tag, and **no part in the repo carries it**. Seeds 17, 18 and 38 confirmed at
one reachable cell; seed 32 at two.

BR40.04's own note says a fix at BR40.03 very likely closes it too; if it does not, the narrower
option recorded there is ordering — running `_place_spawn_zones` before whatever flattens.

**Do not author a `CLIMBER` part to work around this.** That is a real gap with its own PLAN entry and
its own consequences for hop-down reversibility; using it to paper over a map-gen defect would hide
both.

**TESTS:** across a seed sweep, no cover, extraction tile or spawn tile sits below the floor of the
room containing it; every spawn cell in every zone has a uniform floor height; a unit placed on any
spawn cell of any zone reaches more than one cell.

---

# PASS B — The sampler, and a fresh baseline on the fixed ground

## B1. Why the old number is now unusable

taskblock-45's 87.5% / 54.2% table was measured on maps that sometimes sealed a unit in a pit before
the AI made a single decision. **Pass A changes what every seed generates** — seed 5 is now a
different map carrying the same number. Comparing anything later in this block against 54.2% compares
two different worlds.

**Take both numbers again on the fixed generator before touching the AI.** The old planner still runs
from a worktree at `107af1e`, which is how the original table was taken, so this costs one probe run
per planner.

**This is also the cleanest test of the correlation.** taskblock-45 found seeds 1, 2 and 6
`TERMINATE` under *both* planners — 12.5% of 24 — against a spawn defect that strands a unit in
roughly 5% of zones across two squads per bout. If those three stop failing once spawns are level,
that failure was map-gen all along and the AI regression is materially smaller than 33 points. Report
which of the three shared-failure seeds survive Pass A.

## B2. The sampler replaces the pinned window

`test_full_mission.gd` samples seeds 0–11 — the pessimistic window (41.7% against 66.7% on 12–23) —
against a 0.35 floor. At 5/12 it sits **less than one seed from red**, and 4/12 is 33.3%. A threshold
between two adjacent integers is a tripwire, and the usual response to a flapping test is to lower
the constant again.

- **Ten random seeds per run, printing the seeds it drew.** Random so the sample moves across the
  space over time rather than re-asking the same twelve questions. The print is what makes a failure
  reproducible.
- **On failure, escalate to a fixed 100-seed run.** The sampler only has to notice; the escalation is
  the measurement, and it is deterministic where the sampler is not.
- **Report the escalation rate as a metric in its own right.** At a healthy completion rate the
  sampler almost never escalates; at 54% it would escalate roughly one run in nine. Frequent
  escalation says the planner is marginal regardless of what any single run concluded.
- **Runnable from the game window**, showing the seed list and per-seed outcomes, not a bare rate.
  This is the piece worth the most: it makes the number re-takeable without a CC session, and
  BR45.03's whole lesson was that an aggregate hid which seeds mattered.

**TESTS:** the sampler prints every seed it drew; a forced failure triggers the 100-seed run; the
100-seed run is byte-identical across invocations; the in-window view reports the same numbers as the
headless path.

---

# PASS C — Search and idle behaviour, one verb per unit

## C1. The hole

The eight authored utility actions partition into two gates with **nothing in neither**:

| gate | actions |
|---|---|
| `enemy_known` | approach, shoot, take_cover, overwatch, hold_position |
| `is_player_squad` | seek_objective, gather, seek_extraction |

A non-player squad that has seen nobody fails both and is offered nothing — observed as `nothing over
488 candidates` on turns 0 and 1, then a shot the moment the other squad came into view. A squad that
never moves never closes, and the bout runs to the cap. That is the `TERMINATED` shape.

## C2. Four verbs, one per unit, gated by precondition

Each is an ordinary utility action — a `.tres` plus a published input. **A unit's assigned search behaviour is
a precondition on the utility action**, so exactly one of the four ever passes for a given unit. No mode flag, no special
case, and the framework is unchanged.

- **Roam** — cover ground steadily, below top speed. The default.
- **Hunt** — roam at speed. Weighted up by a recent sighting or a squadmate's contact.
- **Putter** — stay local without idling. For a unit with reason to hold a place.
- **Patrol** — generate two or three points and move between them. **Choose the next point by oldest
  visit time.** That cycles all points with no authored order, never bounces between two while a third
  goes unvisited, and lets an unreachable point age out of contention on its own.

**One verb per unit is the diagnostic, not just a scoping choice.** If patrol is broken, only
patrolling units misbehave, and the failure is attributable to a verb rather than to "the search
behaviour." Tests must preserve that: a failing verb should be identifiable without bisecting the
other three.

## C3. `approach` cannot find its way around anything — fix it here

**BR32.10** (AI stuck on concave/U-shaped maps) is not a separate bug from this pass. The retired
planner had `LineOfFire.approach_path`, a Dijkstra flood toward a cell with a line; **it survived
taskblock-45 as code but nothing calls it** — that planner was its only caller, and the sole remaining
references are in `test_line_of_fire.gd`.

What replaced it is not a fallback at all. `approach` scores `closes_distance`, and
`_closes_distance(distance)` takes a **scalar straight-line distance**. On concave geometry the cell
on the wrong side of the wall scores highest, so a unit walks into the wall between itself and its
target and stays there. Being stuck is now a **scoring outcome**, not a branch that failed to fire.

The likely fix is that the consideration reads **path** distance rather than straight-line — the
pathfinder already computes it while establishing reachability, so the number is in hand. Confirm that
before assuming it; if the cost is real, `approach_path`'s flood is still in the tree and can be
revived as an input rather than a branch.

Either way, **decide what happens to `LineOfFire.approach_path`.** Revived as a consideration input, or
deleted with its tests. A function with no callers and a doc comment describing a branch that no longer
runs is exactly what `SUPERSEDED.md` exists to prevent.

**TESTS:** a unit that has seen nobody has at least one action available (assert the candidate count is
non-zero, since `nothing over N candidates` was the observed symptom); each verb is selected only by
units assigned it; patrol visits all of its points across enough turns and never alternates two while a
third is unvisited; **a unit behind concave geometry reaches a cell with a line to its target** — the
BR32.10 case, stated as behaviour rather than as a distance metric.

---

# PASS D — Panic

The case where the scorer returns **no positive-utility action at all**, which the previous planner
could not express. The approach-fallback was the first narrow instance; this is the general one.

- **Label it visibly so the player sees it fire.** Some escapes are necessarily cheats — teleporting,
  extracting off an extraction tile, shutting down — and a player who sees one unlabelled learns the
  wrong rules. An escape hatch nobody can see is indistinguishable from a bug, and the label doubles as
  a debugging tell.
- **A hard turn budget belongs here.** Whatever the planner is doing, the turn ends rather than the
  plan running longer. That is what makes "Unit 2 is thinking…" a promise rather than a hope.

**TESTS:** a unit with every utility action vetoed produces a Panic rather than an empty turn; Panic is visible
in the combat log with a reason; the turn budget fires and ends the turn rather than extending it.

---

# ⏸ HARD PAUSE — measure before filling the table

**Stop and report.** Run the sampler and the 100-seed escalation, and give the completion rate against
Pass B's fresh baseline, not against 54.2%.

**If completion has not recovered, do not continue to Pass E.** Filling the tier table on a planner
that cannot finish a mission buries the regression under a hundred new decisions, and every later
measurement inherits the doubt. Report and divert.

---

# PASS E — Fill in the tier table, and retire the playstyle enum

- **The middle tiers.** Grunt adds cover, ranged and regroup against last-known positions; Elite adds
  bait, ambush and setting the batch objective, with full team knowledge and predicted moves at depth
  2–3. **Elite's lookahead is the one piece with real structural weight** — it tests the resumability
  constraint hardest, since a recursive search is the hard thing to suspend and resume.
- **The rest of the utility action pool.** The executors already exist in `src/logic/actions/` and are
  the player's too; each addition needs preconditions and a consideration set, not new machinery. Flank, suppress, use-item,
  call-for-help.
- **The rest of the profile table**, as weight vectors over shared considerations.
- **Retire the playstyle enum here, not separately.** `AGGRESSIVE`/`SKIRMISHER`/`MARKSMAN`/
  `COVER_SEEKER` mixes profile with role and range; standoff and cover-seeking both become
  consideration weights. Every test keyed to those playstyles migrates with it, which is why doing it
  as its own item would mean touching the same tests twice.

**TESTS, and these two matter most:** every tier decides differently from its neighbours on the same
seed; every profile decides differently with tier held constant. A table where two rows play
identically has a bug in it, and no completion metric will catch it.

---

# PASS F — Verify the bug state this block claims

**Narrow, not a sweep.** The wide sweep is the taskblock-51 bug hunt. Confirm only the entries this
block touched are in the state it says:

| Entry | Expected |
|---|---|
| BR40.03 | Cover no longer generates below its room's floor |
| BR40.04 | Spawn/extraction tiles level with their room; no one-reachable-cell spawn across the sweep |
| BR45.03 | Completion measured against Pass B's baseline, with the shared-failure seeds re-checked |
| BR32.10 | Behaviour re-tested on concave geometry, with the new mechanism named |
| BR35.06 | Re-verified against the utility planner |

**On BR35.06 specifically:** `hold_position` requires all four of `enemy_known`, `cell_is_current`,
`can_defer_turn` and `lof_blocked`, carries base weight 0.3 against `shoot`'s 1.5, and is `ends_turn` —
which the planner refuses once the turn has committed. Since `lof_blocked` is the exact negation of
`shoot`'s own gate, a hold while a shot existed should be **impossible by construction**. If it still
reproduces, the question is which predicate disagreed with reality, not why the weights came out that
way. Close it `Obsolete` or rewrite it; do not carry the old description forward.

**23 of the 33 live entries are `SUPERVISOR`-owned**, including BR40.03, BR40.04, BR45.03 and BR32.10.
Append findings and mark `Pending` where a fix is complete; **do not close them.** The output of this
pass is a digest for the supervisor, not a cleaned ledger.

---

# Living docs

**`docs/11` is the AI authority now** and this block changes it substantially — a fifth and sixth
utility-action gate, four search verbs, the tier table filled in, the playstyle enum gone. Update it, and keep
the code comments thinned against it rather than restating it.

`PLAN.md` loses NEXT item 2 and the raised-rooms item; `CHANGELOG.md` gains both, including the
re-baseline numbers. If `approach_path` is deleted, `SUPERSEDED.md` records what it was and what
replaced it.

# Not this block's job

- **Authoring a `CLIMBER` part**, or the one-way hop-down planner rule. Own PLAN item.
- **The wide bug sweep.** taskblock-51.
- **The spectator/player divergence trio** (BR27.04, BR32.09, BR35.02). The *One view* refactor
  dissolves them; fixing an instance is discarded work.
- **The view/sim snapshot split** and the thinking indicator. Own PLAN item, and Pass D only needs the
  turn budget.
- **Closing BR27.09.** Append the numbers; the supervisor closes it.
