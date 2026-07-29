# Taskblock 47 Report — The suite: measure it, tier it, watch it, cut it

**Passes A–E landed in order; suite green.** Full gate **1493 s → 537 s**, turns resolved
**4545 → 1578**, and a fast gate at **119 s** for the per-change loop. Pass A also turned up a broken
profile id that had been silently disabling AI profile weights since taskblock-46 — see *Open
questions*, it re-frames `BR45.03`.

## Decisions made without asking

- **`candidates` and `shot_planes` are measured and reported but not gated.** They move with how the
  planner *scores*, not with how much the suite asks of it, so an AI change that legitimately scores
  differently would fail a test about suite cost. That false positive is what gets budgets deleted, and
  a budget nobody trusts is worse than none. Bouts, turns and floods are the ones the suite controls.

- **The budget reads the committed profile rather than measuring the live run.** It therefore catches a
  regression when the profile is regenerated, not the instant it lands — stated in the file rather than
  hidden. The alternative is measuring the whole suite from inside the suite, which is either circular
  or expensive, and the profile is regenerated per taskblock, which is the cadence the numbers move at.

- **`HEADROOM` is 15%**, sized from what it has to catch: taskblock-46's search-memory change raised
  turns 40% across every bout test at once, so headroom has to sit well under that; a new bout test
  costs ~0.7% of the turn baseline, so 15% leaves room for about twenty before anyone has to think.

- **`SAMPLE_SEEDS` re-derived to 8, not adjusted.** The taskblock asked for "a smaller `n`" and to
  re-derive rather than pick. At the re-measured rate against the 0.35 floor, n=8 costs 98 s and asks
  for an escalation about one run in thirteen, against 244 s at n=20. **The non-monotonicity is worse
  than taskblock-46 found it**: n=6 is three times likelier to escalate than n=8 *despite being
  smaller*, because `ceil(0.35 × 6) = 3` demands 50% where `ceil(0.35 × 8) = 3` demands 37.5%. A round
  number would have been actively worse than a bigger one.

- **The tier is an explicit file list, not a directory rule.** Eleven of the twelve bout-building files
  live outside `test/integration/`, including the most expensive file in the suite, so "skip
  integration/" would have declared the fast gate bout-free while it played nearly every bout in the
  suite. The
  list is checked against the profile's own bout counter every run.

- **`MIN_COMPLETION_RATE` left at 0.35 despite measuring 72%.** The taskblock excludes that constant,
  and moving a floor on the same day the number moved is how this project got into trouble with it
  before. It is yours to raise and it now has a lot of room.

- **The watched run records nothing.** A seed is already a complete reproduction handle, so each bout
  is rebuilt rather than replayed. Any capture format would be a second source of truth about what a
  bout was.

## Tests that failed, then were corrected

**Four failing before correction.** The first three are all the same shape: a mechanism that fails
*silently* in the direction of doing less work, which is the worst possible failure mode for this
particular block.

1. **The profiler reported minus 1,272,441 candidates.** Four test files zero these counters in their
   own `before_each` — they were diagnostics long before they were budgets — and GUT fires `start_test`
   **before** `before_each`, so the reset lands inside the measurement window. The negative then
   subtracted from the suite totals, making every number in the file wrong rather than one row. A drop
   can only mean a reset, so it is read as one now.

2. **Script totals measured the wrong window.** `test_work_counters.gd` reported 0 bouts while plainly
   playing several, because the outer script window spans every `before_each` and its last test ends on
   a deliberate reset. Script counts are the sum of their tests' windows now, which are short enough
   for the reset handling to be exact.

3. **Returning `""` from `should_skip_script()` silently removed every bout file from the FULL
   gate.** GUT skips on *any* String, empty included; only `bool false` means "run me". The suite went
   green with 11 fewer files in it. Related: GUT declares the method untyped, so an override adding
   `-> Variant` is a signature mismatch, and the script then fails to parse while GUT reports "does not
   extend GutTest" — a long way from the cause. The hooks are untyped against this project's
   static-typing rule, with the reason at each site.

4. **My own tier test switched the fast gate off mid-run.** It set `HULK_FAST_GATE` and then cleared it
   to `""`. `OS.set_environment` is process-wide, so every file GUT had not reached yet stopped being
   skipped — exactly the three bout files sorting after it ran their bouts anyway. The fast gate
   silently stopped being fast partway through: the precise failure this pass exists to prevent,
   introduced by the test written to prevent it. It restores the prior value now.

## `SUPERVISOR`-owned entries moved to `Pending`

None this block. `BR45.03` stays `Active` and gained a substantial correction — see below.

## Open questions

- **Every completion number since taskblock-46 Pass E was measured with the AI's profile weights
  switched off, and nobody could have known.** `CompletionSampler` was still passing `&"AGGRESSIVE"` as
  its profile id — a playstyle Pass E retired. `DataLibrary.get_utility_profile` returns null for an
  unknown id and `UtilityScorer` falls back to unweighted scoring without complaint.

  | | rate | mean turns |
  |---|---|---|
  | unweighted (what was reported) | 56/100 | 26.8 |
  | weighted (what it actually does) | **72/100** | **13.5** |

  Against the retired planner's 75% on level ground, **the gap is 3 points, not 19.** That re-frames
  most of `BR45.03`, and it means the 60% → 56% comparison I reported last block was measuring two
  different things.

  The guard for this existed and was one line short: `test_every_authored_default_names_a_profile_that_exists`
  checked `Matrix`, `BoutRosterEntry` and the bout maker's roster, but not the sampler — the one that
  decides what every measured number means. **The fix is a one-word change; the lesson is that a
  silent fallback on an open vocabulary needs a test per consumer, not per vocabulary.**

- **Where the time went, by pass.** Reported as turns because seconds move with the machine — two runs
  of identical work measured 1286 s and 1493 s during Pass A, which is the whole argument for gating on
  counts.

  | after | bouts | turns | why |
  |---|---|---|---|
  | A (baseline) | 136 | 4545 | — |
  | C | 76 | 2171 | `SAMPLE_SEEDS` 20 → 8 |
  | D | 79 | 2651 | **rose**: the watched-run tests build bouts, and weighted profiles changed bout shape |
  | E | 62 | 1578 | retarget, merge, cut |

  **C and E did the work; D is an honest increase** and is left visible rather than netted out.

- **The fast gate is 119 s against the full gate's 537 s**, and I have not changed which one anyone is
  told to run before committing — that is still the full one. The fast gate is for the edit-run-edit
  loop. If it turns out people land work on `fast` alone, the tier list is the thing to revisit, not
  the rule.

- **`test_completion_sampler.gd` is still the most expensive file at 207 s**, down from 437 s. What is
  left is genuine: it plays real missions to check the sampler reports them correctly, and the
  remaining bouts are the ones the properties actually need. Cutting further means deciding the sampler
  does not need an end-to-end test, which is a bigger call than a suite-cost pass should make.
