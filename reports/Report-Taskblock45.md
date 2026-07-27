# Taskblock 45 Report — AI v2, part two: the utility planner

**IN PROGRESS — Pass A only.** B, C, D and E are not started. `taskblock45.md` is in the tree and is
the authority on what they are; this file records what actually landed.

**The rolling-five window is NOT rolled yet.** `Report-Taskblock40.md` stays until this block
finishes; rolling it for a one-pass record would trade a complete record for an incomplete one.

Suite 2325/2325 at Pass A. Commit `8115d4e`.

## Carried in from taskblock 44

- **The suite is slower and it is `test_plan_pacer.gd`'s fault, and the fix is already scheduled by
  the supervisor for later — do not fix it inside this block.** The numbers, so the scheduled work has
  them: 2223 tests / 282.1s (taskblock-43 baseline) → **2325 tests / 350.2s** now, with
  `test_plan_pacer.gd` alone accounting for **33.9s** — one file, 14 tests, ~10% of total runtime for
  0.6% of the tests. The cause is three of its cases setting `chunk = 1`, so a single plan suspends
  once per candidate cell (~90 real frames) when the assertion only needs "more than one". Shrinking
  the board in its `_field()` and raising `chunk` keeps every claim intact.
- **The `SurrogateLadder.demote` warning volume was not a taskblock-44 regression** and was
  investigated rather than assumed: the warning has fired since taskblock-03 Pass A2, and
  `run_tests.sh` has not changed since taskblock-43. taskblock-44 only added tests that run real
  seeded bouts, so more combat resolves and the existing warning fires more often. It became audible,
  not newly wrong. Filed as **`BR45.01`, `CC`-owned** at the supervisor's direction.

## What Pass A built

A **selection layer over the existing action layer**, which is the framing that keeps it small:
`src/logic/actions/` already holds twenty tested executors, and `UtilityActionDef` names one through
the same `ActionCatalog` seam the player's action bar reads rather than reimplementing any of them.

| file | what it is |
|---|---|
| `src/data/response_curve.gd` | linear / quadratic / logistic / step, clamped 0–1 at both ends |
| `src/data/consideration_def.gd` | a named normalized input plus a curve |
| `src/data/utility_profile.gd` | weight vectors over actions and considerations |
| `src/data/utility_action_def.gd` | executor id, preconditions, considerations, base weight |
| `src/logic/ai/utility_scorer.gd` | the product-with-veto maths, compensation, tiebreak, trace |
| `src/logic/ai/ai_decision_log.gd` | `emit_utility_decision` — A3's record |

## Decisions made without asking

- **The compensation factor is the IAUS form, and its residual bias is documented rather than hidden.**
  See the correction below — this is the one a reviewer might have decided differently, because a
  geometric mean *would* equalise the dimensional penalty exactly. It was rejected because it turns
  one terrible consideration into a mild average, losing the sharpness that makes a product model
  worth having over a sum. The ~11% residual is the accepted cost and is stated at the seam.
- **Every consideration is evaluated even after a zero appears** — no short-circuit. It is slower, and
  it is what lets the log answer "which consideration vetoed", which is the question actually asked
  when a decision looks wrong. A veto is invisible in a product; only the individual factors carry it.
- **A missing `input_id` resolves to 0.0 and therefore vetoes**, rather than reading as neutral. A typo
  that merely lowered a score would be nearly impossible to spot; one that stops the action being
  chosen shows up in the first decision log you read.
- **Preconditions are a separate list from considerations**, not considerations that happen to return
  zero. That is what lets the log distinguish "not offered" from "offered and scored zero" — different
  answers to "why didn't it do that" — and it means an impossible action costs one boolean rather than
  a full curve evaluation.
- **`ResponseCurve.shape` is an open `StringName` that is honestly a closed set.** A new shape needs a
  new arm in the maths, not just new data, so this is the one place in the AI data model where
  "addable as data" does not fully hold. Flagged at the seam rather than pretended otherwise; an
  unrecognised value falls back to linear rather than erroring, matching the playstyle dispatch.
- **`ConsiderationDef.weight` is the authored baseline and the profile is the deviation.** Profiles
  multiply rather than replace, so an empty profile is legitimately fully neutral.

## Tests that failed, then were corrected

One, and **the error was in my documentation before it was in the test** — which is the part worth
recording.

1. **I wrote that the compensation factor "exactly cancels the dimensional penalty", and asserted that
   equality in a test.** It does not cancel it; it shrinks it. At every consideration sitting at 0.8:

   | | two considerations | five | five retains |
   |---|---|---|---|
   | uncompensated | 0.64 | 0.328 | 51% |
   | compensated | 0.774 | 0.688 | **89%** |

   The test now asserts the *shrink*, with the uncompensated arithmetic as an explicit control so it
   is demonstrably guarding against something real, and the scorer's doc comment states the residual
   plainly along with why the exact-equalising alternative was rejected. Had the test agreed with my
   comment, both would have been wrong together and the ~11% bias would eventually have been
   misdiagnosed as a tuning problem — which is precisely what the comment now warns it is not.

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** Nothing in Pass A touches a `SUPERVISOR`-owned entry. `BR45.01` was filed this block and is
`CC`-owned by the supervisor's direction; it remains `Active` and untouched by this pass.

## What the next session needs before starting Pass B

- **Pass B is where the design is proved or isn't, and its first two tests matter more than the rest.**
  `MINDLESS` and `TRAINED` must decide *differently* on the same seed, and the two profiles must decide
  differently with tier held constant. If either produces identical play, the information gating is
  decorative and Passes C–E are built on nothing. Write those two first, not last.
- **`WorldView` already names the tiers.** `BLACKBOARD_TIERS` contains `TRAINED`, `Unit.intelligence_tier`
  defaults to `TRAINED` so today's behaviour is unchanged, and the restriction flag exists disabled with
  an anti-vacuity test behind it. Pass B is the first real exercise of all three.
- **Build resumable from the first line.** taskblock-44 Pass D already made the planner chain coroutines
  and the parser enumerated every call site, so the shape exists. A conditional `await` is a parse error
  in GDScript, so "make it resumable later" means converting the whole chain again — this was measured,
  not assumed (`tools/` probe, taskblock-44).
- **The scorer is ready to drive; what does not exist yet is the context that publishes inputs.** Pass B
  needs something that turns a candidate cell into the `{input_id: 0.0–1.0}` dictionary
  `UtilityScorer.score` consumes, plus the `{predicate: bool}` dictionary preconditions read. That seam
  is the actual work of Pass B, not the scoring.
- **Pass E's acceptance is objective and should be checked early, not at the end.** `max-file-lines`
  returning to 1000 is the proof `unit_ai.gd` is gone. It is at **1400 after eight bumps**; if Pass B
  starts adding to that file rather than beside it, E cannot land.

## Open questions

- **Nothing is blocked.** Pass A is self-contained and green, and Pass B has everything it needs.
- **The residual compensation bias (~11%) is a knowingly accepted cost.** If the tier or profile tables
  later show actions with many considerations being systematically under-chosen, that number is the
  first place to look — and the fix is a different aggregation, not re-weighting.
