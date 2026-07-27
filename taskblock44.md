# Taskblock 44 — AI v2, part one: measure, invert, seam

*Rewritten mid-block. Pass A has landed (`c7d6afe`); it is recorded below rather than restated as work.
Passes B–D are the remaining scope, and Pass D is new since the original spec.*

*Supersedes `PLAN.md`'s previous NEXT item 2 (ordering the LOF prefilter scan nearest-target-first) —
see `SUPERSEDED.md`.*

First block of the AI rebuild, and it deliberately contains **no new decision-making**: the utility
scorer, the intelligence tiers and the profile table are all part two. This block establishes the
numbers the rebuild is judged against, replaces the single most expensive query, and puts in the seam
everything after depends on.

**The order is the point.** taskblock-35, taskblock-42 and taskblock-43 each optimized a function
nobody had profiled. Measure, change one thing, measure again — and land each change **under the
existing planner**, so its effect is separable from the rewrite's.

---

# PASS A — Landed, one half handed back

**Built:** `src/debug/build_identity.gd` classifies the running build as `editor_debug` /
`exported_debug` / `exported_release` and answers whether it is representative of play. Stamped into
`bench_ai_planning.gd`'s first output line (with a warning when the build isn't representative) and
merged into every `fps_dump` event, since that sink's output is read straight out of `out/combat.log`
by a human.

**Blocked, correctly:** the release-versus-debug comparison. Export templates are absent and there is
no `export_presets.cfg`. CC stopped rather than substituting a proxy, per the pass's own instruction.

**Outstanding, supervisor-side:** run the bench against an exported release build. **Nothing later in
this block depends on it** — Pass B's A/B comparisons hold regardless, because both sides share a
build. What is unverified is the *absolute severity* of the hitch: every performance figure in this
project's history was taken on an editor/tools binary carrying GDScript's per-line debug overhead by an
unmeasured factor.

---

# PASS B — Invert the line-of-fire query

## B1. The shape

The planner casts from N candidate cells to one target. Invert it: one symmetric shadowcast **from the
target** yields a visibility set over the volume, after which every candidate cell's query is a bit
test.

- **Bitboards.** `PackedInt64Array`, flat `i = x + y*W + z*W*H`. Never `Dictionary[Vector3i]` here.
- **3D from the start.** The game is 3D and multi-level has landed; a per-level structure with a bolted
  cross-level path gets rewritten within a block or two.
- **One field per target, reused by every shooter.** This is where the asymptotic win is — cost stops
  scaling with unit count. Compute per target per turn, not per shooter.
- **The flat-array representation is load-bearing beyond speed.** Handing a worker thread a
  `CombatState`/`Grid`/`Unit` object graph is the fragile version of every future parallelism idea;
  snapshotting to packed arrays is the robust one. That makes this pass a prerequisite for any later
  off-thread work rather than an alternative to it — worth knowing while choosing the representation.

## B2. The field is a prefilter. `ShotPlane` is final.

**Governing constraint, not negotiable.** This project has one canonical shot resolver and `docs/02`
and `docs/08` govern everything downstream. A second visibility system permitted to *disagree* with it
is a two-sources-of-truth problem, and it would disagree — different rounding, different partial-cover
handling, different level-transition behaviour.

One correctness obligation:

> **Never report "no line" for a cell that actually has one.**

Over-inclusion safe, under-inclusion a bug. A far weaker burden than exactness, and directly testable.

| Case | Behaviour |
|---|---|
| No reachable cell has a line — **19 of 60 turns** per tb43's census | `reachable & vis[target] == 0` is conclusive. One AND, one zero test, **zero** `ShotPlane` builds. |
| Some cell has a line | Field narrows candidates, `ShotPlane` confirms survivors. Far fewer casts, identical answer. |

The negative case is the one taskblock-43 called "real work, not a follow-up," and it is solved here
**without the field ever needing to be exact.**

## B3. Under the existing planner

`_any_reachable_has_lof` and the scorer's line checks read the field; **no planner logic changes.**
Building it into new code would make it permanently impossible to separate what the inversion bought
from what the rewrite bought.

**Acceptance is identical output.** Because the field only prefilters and `ShotPlane` confirms, every
decision must be unchanged. The speedup is the side effect.

**TESTS:**
- **Containment, directly:** across seeded scenarios, every cell where `ShotPlane` reports a clear line
  is set in the field. A one-directional superset check — this is the real acceptance.
- **Anti-vacuity:** assert on the count of avoided `ShotPlane` builds. A field with every bit set passes
  containment and does nothing.
- A seeded bout produces a byte-identical action sequence before and after.
- The all-negative case performs **exactly zero** `ShotPlane` builds — this is the case the pass exists
  for, so assert the number rather than a bound.
- Cross-level containment: target one level up, and one level down.
- Bench numbers before and after, in the report, with Pass A's build stamp attached.

## B4. Re-measure the per-unit plan, because Pass D depends on the answer

After the inversion, report `bench_ai_planning.gd --profile`'s per-unit planning cost.
`_any_reachable_has_lof` was 271.9ms of it and stops being a loop at all; what remains decides whether
Pass D is needed. **Report this before starting Pass D.**

---

# PASS C — The `WorldView` seam, stubbed

The rebuild's tiers gate *information*, not just actions — a dumb unit runs the same scorer against a
degraded world model and produces plausible-but-wrong decisions rather than random ones. That only
works if information access is a chokepoint. Retrofitting "this unit doesn't get to know that" onto a
planner already reading global state touches everything, so the doorway goes in **now**, while the
planner is still the old one and nothing depends on it.

## C1. Pass a view, never the state

The planner's entry point takes a `WorldView`. **`CombatState` is not reachable from it** — leakage
stops being a discipline problem and becomes something that doesn't compile.

**Today the view returns everything.** No filtering, no behaviour change, no tiers. A pass-through with
a doorway in it.

## C2. Stub the restriction behind a disabled flag

The guideline should exist before the thing it governs:

- A disabled-by-default flag that restricts the view, with the intended shape documented at the seam:
  **a per-unit view over a team pool**, not a flat per-unit memory. Sharing is already the tier table's
  "team blackboard" column — Trained has it, Grunt doesn't — so pooling is the same axis, and
  per-unit-only now would force a restructure.
- **Derive staleness; do not maintain it.** Store `{unit_id: {cell, round_seen}}` and compute staleness
  on read against the current round — taskblock-43's `BatchPlan` trick, for CC's own stated reason: no
  invalidation hook at a round boundary is no invalidation hook to miss. It also avoids the
  incremental-update bugs that eat perception systems.
- **Write the rule at the seam in prose:** what a restricted view may hide, and that `ShotPlane` stays
  final regardless of what a unit believes.

## C3. Intelligence is hardcoded

An authored constant per unit. It wants to derive from Attributes, which hasn't landed — note that at
the seam and move on. **This block uses the tier for nothing**; it only needs to be findable by part
two.

**TESTS:**
- **The chokepoint holds, structurally.** A guard test asserting the planner path doesn't reference
  `CombatState` directly — the shape of taskblock-40's spawn-marker guard and taskblock-41's checkpoint
  parse guard. A prose rule with no enforcement is what BR40.02 was.
- **The seam is load-bearing.** Flag on, view deliberately restricted, unit makes a **different**
  decision than with the full view. If restriction changes nothing the seam is decorative and the test
  goes red. This matters more than the rest — everything in part two assumes it works.
- Flag off is byte-identical to today across a seeded bout.
- `WorldView`'s treatment by `dup()` is either carried or explicitly commented, matching the convention
  `is_resolving` already sets in that function. (`batch_plans` is currently neither — fix that here,
  while the convention is in view.)

---

# PASS D — "Unit 2 is thinking…", gated on B4's number

**Do not start this pass until Pass B4's measurement is reported.**

A player who can pan, click, and inspect while a label reads *"Unit 2 is thinking…"* is playing a game
that is working. A player staring at a frozen frame is playing one that has crashed. Those can be the
same number of milliseconds.

## D1. The indicator and the yield are one item

A blocked main thread cannot paint the label either. The indicator is only meaningful once the planner
yields **mid-plan** — taskblock-42 Pass D's `await get_tree().process_frame` sits *between*
`runner.step()` calls, and one step is the entire think.

## D2. Whether to build it is a measurement, not a judgement

`_any_reachable_has_lof` was 271.9ms and after Pass B is a bitboard AND with no loop in it. If the
remaining per-unit plan is small enough, there is nothing to cover and this pass is unnecessary.

- **Under ~100ms per unit:** report that slicing isn't warranted and stop; build the indicator only if
  it is free. A freeze that short does not need explaining.
- **Above that:** slice the remaining loop — `_pick_engagement_position` walks candidates, so yield
  every K with a cursor — and show the label while it runs.

**Keep it cheap either way.** The current planner is replaced by part two, so anything built here
against its internals is throwaway. Resumability as a *structural* property belongs to the new planner
and is recorded in `PLAN.md` as a constraint on part two, not built here.

## D3. Name the unit

**"Unit 2 is thinking…", never "Thinking…".** Once named enemies exist, the difference between a
mook's turn and a boss's turn becomes legible as *character* rather than as lag — the intelligence
tiers make a smarter unit genuinely think longer, and the label turns that from a defect into a tell.
Costs nothing now and can't be retrofitted into a habit later.

## D4. It needs a guaranteed end

A visible "thinking" state that never terminates is **worse** than a freeze, because the player waits
longer before concluding something is wrong. The full escape hatch is `PLAN.md`'s *Panic* item and is
not this block's job — but if this pass builds the label, it also needs a hard turn budget behind it:
exceed it and the turn ends rather than the plan running longer.

**TESTS:** input is processed during a single unit's plan, not merely between units; the label names the
acting unit; the turn budget fires and ends the turn rather than extending it; a seeded bout is
byte-identical with and without slicing — **frame boundaries must not change decisions.**

---

# Not this block's job

- **The utility scorer, tier table, profile weights.** Part two. No new decision-making here.
- **Structural resumability, the view/sim snapshot split, Panic.** All three are in `PLAN.md`. Pass D
  builds the visible half against the planner that exists, not the architecture that replaces it.
- **Sensors as parts, fog of war, player-side information sharing.** The seam receives them; none are
  built here.
- **Threading.** Unmeasurable before real unit counts, and standing rule 5 constrains what it could
  ever apply to: pure computation consumed in turn order, never concurrent acting.
- **Flow fields, JPS, HPA\*, reservation tables.** Pathfinding measured 2.5ms against the LOF scan's
  271.9ms.
- **Retiring the playstyle enum.** It dissolves into profile weights when the scorer lands.
- **Closing BR27.09.** Append the numbers; the supervisor closes it.
