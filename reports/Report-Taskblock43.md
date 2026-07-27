# Taskblock 43 Report — AI planning cost: cut the search, not the smarts

**IN PROGRESS — Pass A only.** B, C and D are not started. `taskblock43.md` is in the tree and is
still the authority for what they are; this file records what A actually did and what the next
session needs in hand before touching B.

**The rolling-five window is deliberately NOT rolled yet.** `Report-Taskblock38.md` stays until this
block finishes — deleting it for a one-pass stub would trade a complete record for an incomplete one.
Roll it when the block closes.

Suite 2223/2223 at Pass A. Commit `8ebca0e`.

## Where the number stands

| | per AI step |
|---|---|
| after taskblock-42 | ~1672ms |
| **after Pass A** | **~1498ms** (~10%, exact, 203 candidates skipped over 12 steps) |

Pass A alone was never going to carry this, and didn't. The remaining cost is still the per-candidate
line work; B cuts the candidate count, D removes the search entirely for followers.

## Decisions made without asking

- **Pass A's bound enumeration, in full** — this is the pass's stated real risk and the answer is
  written at the branch in `unit_ai.gd` as well as here. Every term in `_engagement_score` is a
  **non-negative penalty subtracted** from the total: distance, obstruction, ally-blocked, min-range,
  suppression, opportunity, no-LOF. **Exactly one term can raise the score** — `cover_bonus`, bounded
  by `COVER_SCORE_BONUS`, and zero when `weight_cover` is false. **No term needed excluding for being
  unbounded.** Dropping every not-yet-computed penalty therefore gives a true upper bound.
- **The skip covers more than the two walks the pass named.** Because the early-out returns whole
  rather than skipping selectively, it also avoids the suppression, opportunity, LOF and obstruction
  queries. Sound for the same reason — all are penalties.
- **`<=` rather than `<`.** Selection is strict `score > best_score`, so a cell that can at best tie
  never wins and skipping it cannot change the choice. This is what makes the pass exact rather than
  approximate; using `<` would leave measurable work on the table for no correctness gain.
- **A `candidates_skipped` counter lives in production code.** An identical-output test passes
  trivially if the fast path never runs, so the test needs to prove the skip fires. Reset by tests,
  never read by planning.
- **`gdlintrc` `max-file-lines` 1150 → 1200**, reasoning in `run_tests.sh` beside every prior bump for
  this file. The enumeration belongs next to the code it constrains; a future term added without
  joining `ceiling` silently changes which cell the AI picks, and that warning is worth more than the
  lines it costs.

## Tests that failed, then were corrected

One, and the premise was mine rather than the code's:

1. I asserted a cell 9 cells from the target with `preferred_range` 0 would be skipped against an
   incumbent of `0.0`. Its ceiling is `COVER_SCORE_BONUS - 9 = 1.0`, which beats `0.0`, so scoring it
   was correct. Rewrote the case against an incumbent of `5.0` and documented the arithmetic in the
   test, since the next reader will do the same sum.

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** `BR27.09` gained the Pass A measurement and enumeration; status untouched, per the block's
own instruction.

## What the next session needs before touching Pass B

- **B is not identical-output, and that is the whole difficulty.** Its acceptance is behavioural:
  `test_full_mission.gd`'s `MIN_COMPLETION_RATE` must hold, and the report must state **how often the
  chosen cell differs from the pre-cull choice across a seed sweep**. That comparison needs capturing
  the pre-cull choice first — take it before writing the cull, or it is unrecoverable without a
  revert.
- **The asymmetric pad is the part most likely to be got wrong.** A unit whose
  `_target_distance(weapon, preferred_range)` exceeds its current distance wants to move *away* from
  the target, and those cells sit behind it — outside a symmetric rect, in the direction the pad is
  thinnest. Without extending the far side by the weapon's preferred range, the optimisation quietly
  shoves long-range units into knife fights, and `MIN_COMPLETION_RATE` may well still pass while it
  does.
- **Always retain the unit's own cell** regardless of the rect; several branches assume it is present,
  and `_pick_engagement_position` seeds `best_cell` with it.
- **Measure per pass, not at the end.** taskblock-35 already demonstrated that a single end-of-block
  number lets a regrowth hide, and taskblock-42 confirmed the same shape.
- **The instrument exists**: `FpsDumpSink` emits `turn_boundary` (0ms) and `turn_settled` (2000ms),
  and `UnitAI.candidates_skipped` counts early-outs. The per-unit planning figure is the one this
  block is actually moving; the turn-boundary dump is the one BR27.09 is written against.

## Open questions

- **Whether Pass B earns its behavioural risk at all** is genuinely open until the seed-sweep
  difference rate exists. If the rect changes the chosen cell often, the honest outcome is to keep A,
  skip B, and go straight to D — the block's own framing is "the measurements decide whether the last
  one is needed", and the same logic applies to B.
- **BR27.09 cannot close on this block alone** unless D lands and the per-step figure comes down by
  an order of magnitude rather than a tenth.
