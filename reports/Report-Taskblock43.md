# Taskblock 43 Report — AI planning cost: cut the search, not the smarts

Passes A–D landed in order (A in a prior session, B–D in this one). Suite green at every pass,
2261/2261 at D.

**Read the last section first if you read only one.** The block's stated target — the candidate
search — turned out to be about a quarter of the cost it was assumed to be, and the measurement that
says so is the most useful thing here. Pass D's own acceptance is not met, and the reason is the
finding, not an excuse.

## Decisions made without asking

- **Built a committed bench (`tools/bench_ai_planning.gd`) rather than measuring ad hoc.** Every
  per-pass number this bug has ever carried came from a throwaway script, which is why "~1672ms →
  ~1498ms" cannot be compared with anything I could produce. The bench is fixed at 5 seeds × 12 steps
  of a 3v3 and reports ms/step, the Pass B difference rate, a per-role split, a branch census and a
  `--profile` breakdown. **Consequence to be aware of: my numbers start at ~745ms for the same work,
  not ~1498ms.** They are internally consistent and not continuous with the earlier ones; I said so
  in the ledger rather than quietly presenting one series.

- **Pass B's far-side pad is unconditional.** The alternative was to extend the rect only when the
  unit actually wants to retreat (standoff distance > current distance). A superset is always sound;
  a predicate re-deriving retreat intent is a second place for the scorer's judgement to live and
  drift from. It costs candidate count on units that will never back off.

- **Pass B does not cull the LOF prefilter's input, only the scorer's.** Culling earlier would let a
  discarded cell flip which *branch* runs (engagement vs. the approach fallback) rather than which
  cell wins inside one — a much larger behaviour change than the pass is scoped to. In hindsight this
  is also why Pass B bought less than it might have: the scan it left alone is the expensive one.

- **Pass C's `BatchPlan` lives on `CombatState` and Pass D writes to it during planning.** A leader
  records on its turn and a follower reads on a later turn in the same round, so it needs per-bout
  lifetime and there is nowhere else with one. It is a planner memo — nothing in resolution reads it —
  but it *is* a write from `plan_turn`, so it is worth knowing about given the TACTICS-mutates-nothing
  rule. Round-scoped staleness is answered by comparing the recorded round on every read rather than
  by clearing at a round boundary, so there is no invalidation hook that can be missed.

- **The batch badge's text is decided in the logic layer, not the view.** `BatchPlan.badge_for`
  returns a string and `HitVolumeView` assigns it to a label. I cannot see the screen, so a
  view-resident decision would be unverifiable; this way what the badge *says* is a headless test and
  the view half has nothing in it that could be subtly wrong.

- **Three new files instead of a sixth `max-file-lines` bump — and then a bump anyway.** Pass B's cull
  went to `engagement_rect.gd`, Pass C's store to `batch_plan.gd`, and Pass D moved its two batch
  queries onto `BatchPlan`. What remained was the follower's local scan, which calls the private
  `_engagement_score` and can only leave by making that public or threading a scorer `Callable`
  through — both worse than 100 lines of headroom. 1200 → 1300, reasoning in `run_tests.sh`.

- **Scope held after the Pass D finding.** Once the profile showed `_any_reachable_has_lof` is the
  real cost, the tempting move was a fifth pass reordering that scan — it is exact, localised and
  probably the largest single win available. I did not build it. The block names its own scope and
  says it is triage; an unrequested pass on the newly discovered cause is how a scope fence stops
  meaning anything. It is written up in `PLAN.md` as NEXT item 2 with an acceptance.

## Tests that failed, then were corrected

Four, and all four premises were mine rather than the code's.

1. **Pass B: I asserted the culled choice equalled the un-culled choice.** It did not — the two cells
   scored identically. On open ground a whole arc sits at exactly the standoff distance, so which one
   wins is decided by iteration order, and dropping any of them changes the cell without changing the
   decision. Pinning the cell would have pinned that accident. Rewritten to assert the two choices
   *score* the same, which is the property the asymmetric pad actually has to guarantee, with a
   distance assert so it cannot pass vacuously.

2. **Pass D: the fixture planned turns for units whose turn it was not.** Every action's `is_legal`
   starts with `state.current_unit() != actual`, so every enqueue was silently refused, leaving a
   lone `EndTurnAction` that `plan_turn`'s stalled-unit check then swapped for a `ShutdownAction` —
   producing empty queues that read as "the follower decided to do nothing." `force_current_unit` is
   now in the helper with a note saying why it is load-bearing.

3. **Pass D: a walled fixture sent units down the wrong branch.** I built a wall so units would have
   a reason to move; it made them take the no-line approach fallback, which never consults a batch
   plan at all — so the search-count assertions passed for entirely the wrong reason. Replaced with
   open ground and an enemy inside the standoff distance, plus a `_branch_taken` helper that reads
   the decision log, so a test can no longer pass because some *other* cheap branch ran.

4. **Pass D: a follower 2 cells from its target could never fire in place.** MARKSMAN's standoff is
   7, so `far_enough` was false and the "keeps the cheap fire-from-here check" test was asserting
   something the planner is not supposed to do. Moved the follower to 9 cells out.

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** `BR27.09` gained three appends (Pass B, Passes C+D, and the retargeting finding) and its
status is untouched, per the block's own instruction. Nothing here closes it and the per-step figure
has not moved by anything like the order of magnitude that would.

## Open questions

- **BR27.09 has been re-aimed and wants your call on the next block.** Measured per repositioning
  turn: `_any_reachable_has_lof` **271.9ms**, `_pick_engagement_position` **98.3ms**,
  `_nearest_living_enemy` 15.0ms, `Pathfinder.reachable` 2.5ms. Passes A, B and D all attacked the
  98ms. The evidence points at ordering the LOF scan nearest-target-first (exact, cheap, and it
  early-returns) — but the branch census shows **19 of 60 turns end with no reachable cell having a
  line at all**, and ordering does nothing for those; they need a cheap negative test that rules out
  a region without a per-cell query. That second half is real work, not a follow-up.

- **Whether Pass B earned its behavioural risk is genuinely arguable.** It buys ~9% and changes the
  chosen cell in 11.7% of decisions (much of that being ties). `MIN_COMPLETION_RATE` holds. If you
  would rather the AI be exactly what it was, Pass B is the one pass here that is safe to revert on
  its own — A is exact, C is inert, D only activates on a hand-assigned batch.

- **Batches are dormant in real play.** No generated mission assigns one, so the whole Pass C/D
  mechanism only runs in tests and via the debug panel. Automatic assignment is in `PLAN.md` under
  QUEUED, and I have flagged there that as a *performance* argument it is weak (~671ms → ~646ms for a
  batched squad of three) — if it earns its place it will be as squad behaviour that reads better.

- **Pass D's acceptance is unmet and I did not tune around it.** The block says a follower that is
  not dramatically cheaper means the local scan is too wide. The scan is radius 1, at most 9 cells;
  widening or narrowing it is not the lever, and the 4% gap is the shared prologue. Flagging rather
  than hacking, per the workflow rule.
