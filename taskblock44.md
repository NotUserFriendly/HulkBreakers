# Taskblock 44 — AI v2, part one: measure, invert, seam

*Supersedes `PLAN.md` NEXT item 2 (ordering the LOF scan nearest-target-first) — the inversion below
replaces it rather than refining it. Record that in `SUPERSEDED.md`.*

First block of the AI rebuild. It deliberately contains **no new decision-making**: the utility scorer,
the intelligence tiers, and the profile table all come next block. This one establishes the numbers the
rebuild will be judged against, replaces the single most expensive query with a fundamentally cheaper
one, and puts in the structural seam that everything after depends on.

Three passes, and the order is the point. taskblock-35, taskblock-42 and taskblock-43 each optimized a
function nobody had profiled; taskblock-43's bench finally settled which function actually costs. The
same discipline applies to the rebuild — **measure, then change one thing, then measure again**, with
each change landing under the *existing* planner so its effect is separable from the rewrite's.

---

# PASS A — What build are we even measuring?

Every performance number this project has ever recorded — BR26.02, BR27.09, tb35's 2023ms→974ms,
tb43's bench — came from a debug run. GDScript carries real per-line overhead in a debug build, and
nobody has checked how much of the hitch is the game versus the harness.

- **Run `tools/bench_ai_planning.gd` against an exported release build** and against the current debug
  path, same seeds, same steps. Report both and the ratio.
- **If export templates aren't available in your environment, say so and stop** — do not substitute a
  proxy measurement and present it as the answer. Write up the exact procedure so the supervisor can
  run it locally, the same way visual checkpoints already hand work back.
- **Make the bench record which build produced its numbers**, in its own output. taskblock-43's report
  had to explain at length why its figures weren't continuous with the historical series. That should
  never need explaining again — the number should carry its own provenance.

This pass may make the rest of the rebuild less urgent, or confirm it's worse than measured. Either is
worth knowing before committing to an architecture.

**TESTS:** the bench's output includes a build identifier; a run in either mode is self-describing.

---

# PASS B — Invert the line-of-fire query

## B1. The shape

The planner currently casts from N candidate cells to one target. Invert it: one symmetric shadowcast
**from the target** produces a visibility set over the map, after which every candidate cell's query is
a bit test.

- **Bitboards.** `PackedInt64Array`, flat indexing `i = x + y*W + z*W*H`. Never `Dictionary[Vector3i]`
  in this path.
- **3D from the start.** The game is 3D and multi-level has landed; a per-level structure with a bolted
  cross-level path would be rewritten within a block or two. Build the field over the full volume.
- **One field per target, reused by every shooter.** This is where the asymptotic win lives — cost stops
  scaling with unit count. Compute per target per turn, not per shooter.
- The tactical query becomes set algebra: `shoot_from = reachable & vis[target] & range_mask`.

## B2. The field is a prefilter. `ShotPlane` is final.

**This is the pass's governing constraint and it is not negotiable.** This project has one canonical
shot resolver, and `docs/02` and `docs/08` govern everything downstream of it. A second visibility
system that can *disagree* with `ShotPlane` is a two-sources-of-truth problem, and it would disagree —
different rounding, different partial-cover handling, different level-transition behaviour.

So the field carries exactly one correctness obligation:

> **It must never report "no line" for a cell that actually has one.**

Over-inclusion is safe. Under-inclusion is a bug. That is a far weaker burden than being exactly right,
and it is directly testable.

Given that, both halves of the win survive:

| Case | Behaviour |
|---|---|
| No reachable cell has a line — **19 of 60 turns** per tb43's branch census | `reachable & vis[target] == 0` is **conclusive**. One AND, one zero test, zero `ShotPlane` builds. The expensive case collapses. |
| Some cell has a line | The field narrows the candidates; `ShotPlane` confirms the survivors. Far fewer casts, identical answer. |

The negative case is the one taskblock-43 flagged as "real work, not a follow-up," and it is fully
solved here **without the field ever needing to be exact.**

## B3. Land it under the existing planner

`_any_reachable_has_lof` and the scorer's line checks read the field; **no planner logic changes.**

Building this into new code instead would make it permanently impossible to separate what the inversion
bought from what the rewrite bought — which is exactly the mistake the last three blocks made. Under the
current planner it is a clean A/B against a bench that now exists.

**Acceptance is identical output**, same as tb43 Pass A: because the field only prefilters and
`ShotPlane` confirms, every decision must be unchanged. The speedup is the side effect.

**TESTS:**
- **The conservative property, directly:** across seeded scenarios, for every cell where `ShotPlane`
  reports a clear line, that cell is set in the field. A one-directional containment check — the field
  is a superset of truth. This is the pass's real acceptance.
- **Anti-vacuity:** the field actually eliminates candidates. Assert on the count of avoided `ShotPlane`
  builds; a field that sets every bit passes the containment test and does nothing.
- A seeded bout produces a byte-identical action sequence before and after.
- The all-negative case (`reachable & vis == 0`) performs **zero** `ShotPlane` builds — assert the count
  is exactly zero, since this is the case the pass exists for.
- Cross-level: a target one level up, and one level down, both produce correct containment.
- Bench numbers before and after, in the report.

---

# PASS C — The `WorldView` seam, stubbed

The rebuild's tiers gate *information*, not just actions — a dumb unit runs the same scorer against a
degraded world model and produces plausible-but-wrong decisions rather than random ones. That only works
if information access is a chokepoint. Retrofitting "this unit doesn't get to know that" onto a planner
that already reads global state touches everything, so the seam goes in **now**, while the planner is
still the old one and nothing depends on it.

## C1. Pass a view, never the state

The planner's entry point takes a `WorldView`. **`CombatState` is not reachable from it.** Leakage stops
being a discipline problem and becomes something that doesn't compile.

**Today the view returns everything.** No filtering, no behaviour change, no tiers. It is a pass-through
with a doorway in it.

## C2. Stub the sensor gating behind a flag

Filtering may be a while away, and the guideline should exist before the thing it guides:

- A disabled-by-default flag that restricts the view, with the intended shape documented at the seam:
  **a per-unit view over a team pool**, not a flat per-unit memory. Sharing is already the tier
  table's "team blackboard" column — Trained has it and Grunt doesn't — so pooling isn't a later
  bolt-on, it's the same axis, and building per-unit-only now would force a restructure.
- **Derive staleness; do not maintain it.** Store `{unit_id: {cell, round_seen}}` and compute staleness
  on read against the current round. Same trick tb43's `BatchPlan` used, and for the same reason CC
  gave there: no invalidation hook at a round boundary is no invalidation hook to miss. It also avoids
  the incremental-update bugs that eat perception systems.
- **Write the rule at the seam in prose**: what a restricted view is allowed to hide, and that
  `ShotPlane` remains final regardless of what a unit believes.

## C3. Intelligence is hardcoded for now

An authored constant per unit, not derived. It wants to read from Attributes, which hasn't landed —
note that at the seam and move on. **This block does not use the tier for anything**; it only needs to
be somewhere the next block can find it.

**TESTS:**
- **The chokepoint holds, structurally.** A guard test asserting the planner path does not reference
  `CombatState` directly — a grep guard in the shape of taskblock-40's spawn-marker test and
  taskblock-41's checkpoint parse guard. A prose rule with no enforcement is what BR40.02 was.
- **The seam is load-bearing.** With the flag on and a deliberately restricted view, a unit makes a
  *different* decision than it does with the full view. If restriction changes nothing, the seam is
  decorative and the test goes red. This is the anti-vacuity check, and it matters more than the others
  because everything in the next block is built on the assumption that this works.
- Flag off is byte-identical to today across a seeded bout.
- `WorldView` survives `dup()` consistently with whatever `dup()` does about planner memos — and if it
  is deliberately not carried, that gets the same explicit comment `is_resolving` has. (`batch_plans` is
  currently neither copied nor commented; fix that here while the convention is in view.)

---

# Not this block's job

- **The utility scorer, the tier table, the profile weights.** Next block. This one ships no new
  decision-making.
- **Sensors as parts, fog of war, player-side information sharing.** The seam is being built to receive
  them; none of them are built here.
- **Threading.** It is step 7 of the reference build order for a reason, it is unmeasurable before real
  unit counts, and the determinism requirement makes it more expensive here than it is generically.
- **Flow fields, JPS, HPA\*, reservation tables.** Pathfinding measured at 2.5ms against the LOF scan's
  271.9ms; it is not the problem.
- **Retiring the playstyle enum.** AGGRESSIVE/SKIRMISHER/MARKSMAN/COVER_SEEKER dissolve into profile
  weights when the scorer lands, not before.
- **Closing BR27.09.** Append the numbers; the supervisor closes it.
