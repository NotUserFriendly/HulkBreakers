# Taskblock 45 — AI v2, part two: the utility planner

*Advances `PLAN.md` NEXT item 2's successor, *AI v2, part two*. Depends on taskblock-44 (the
`WorldView` seam, the visibility field, the coroutine planner chain).*

taskblock-44 made the hitch survivable. **This block is the one that makes it obsolete.** The
remaining 251.2ms per repositioning turn is per-candidate `ShotPlane` casts inside
`_engagement_score` — code this block deletes rather than optimizes.

Two things carry over as constraints rather than goals:

- **Standing rule 5.** Units act one at a time in initiative order. Nothing here changes that; the
  batch objective is amortization, never concurrency.
- **`unit_ai.gd` is at 1400 lines after eight cap bumps**, every one justified by "part two replaces
  this file." This is part two. **The `max-file-lines` limit returning to 1000 is Pass E's acceptance**
  — if it can't come back down, the replacement didn't happen.

Decisions are allowed to change. "Different" still has to be *characterized*, which is Pass D's job.

---

# PASS A — The framework, and the log that makes it debuggable

## A1. The model

| Concept | Implementation |
|---|---|
| Action | Resource: preconditions, considerations, executor |
| Consideration | Normalized 0–1 input × response curve (linear / quad / logistic / step) |
| Score | Product of considerations × base weight × profile multiplier, plus a compensation factor |

**The executors already exist.** `src/logic/actions/` holds twenty tested action classes — attack,
burst, move, climb, overwatch, extract, slash, stab, hold, repair. This block builds a **selection
layer over an existing action layer**, not both. An Action resource names an existing executor; it
does not reimplement one.

**Product, not sum.** A single zero vetoes the action outright, so "unreachable" kills a candidate
rather than merely lowering it. Include the compensation factor from the start — without it, every
action with more considerations scores systematically lower than one with fewer, which looks like a
tuning problem and isn't.

## A2. Two constraints that are cheaper now than ever again

**Resumable from the first line.** taskblock-44 Pass D already made the planner chain coroutines and
the parser enumerated every call site, so the shape exists — build into it rather than around it. A
scorer walking N candidates yields every K with a cursor. Do not write a synchronous scorer intending
to make it resumable later; a conditional `await` is a parse error in GDScript, so "later" means
converting the whole chain again.

**An explicit deterministic tiebreak, decided once and written down.** taskblock-43 hit this already:
two cells scored *identically* and iteration order silently picked the winner. On open ground a whole
arc sits at exactly the standoff distance, so ties are common rather than exotic. Lowest cell index.
State it at the seam.

## A3. The decision log is designed in, not added when something goes wrong

A behaviour tree fails legibly — it took a branch, you can see which. **A scorer produces a number and
you reconstruct why afterward, or you can't.** BR26.02 sat in exactly that hole for three passes of
reasoned-but-unmeasured fixes.

`ai_decision_log.gd` records, per decision:

- every candidate considered, and its final score
- **per consideration: the normalized input and the curve output** — not just the product. A veto is
  invisible in a product; "which consideration returned zero" is the question that gets asked.
- the acting unit's tier, its profile, and what it could see
- the winning candidate and the margin over second place

**TESTS:** the compensation factor makes a 2-consideration and a 5-consideration action comparable at
equal quality; a zero in any consideration vetoes regardless of the others; the tiebreak is stable
across repeated runs and across a reordered candidate source; a decision's log entry is sufficient to
reproduce its score by hand.

---

# PASS B — A small pool, two tiers, two profiles — behind a flag

Deliberately minimal. **A tier that silently does nothing is the failure this design is most exposed
to**, and that is far easier to catch on four actions than on twenty.

- **Four actions**, each wrapping an existing executor: approach, shoot, take cover, hold.
- **Two tiers at opposite ends of the axis** — `MINDLESS` and `TRAINED`. `WorldView` already names
  them; `BLACKBOARD_TIERS` already contains `TRAINED`. The gap between them is the whole point: one
  sees current sight only, the other gets remembered sightings and the blackboard.
- **Two profiles** — aggressive and cautious, as weight vectors over shared considerations, never as
  code paths.

**Behind a flag, with the old planner as default.** Both alive for this block only. This is the first
real exercise of taskblock-44's restriction flag and of the tier gating, and it needs to be A/B-able
against the bench before it becomes the default in Pass D.

**TESTS, and the first two matter more than the rest:**
- **The two tiers decide differently on the same seed.** If `MINDLESS` and `TRAINED` produce identical
  play, the information gating is decorative and everything downstream is built on nothing.
- **The two profiles decide differently on the same seed**, with tier held constant. Same argument on
  the other axis.
- A `MINDLESS` unit acts on a remembered position that is now wrong, and does so *plausibly* — moving
  to engage where the enemy was. Wrong, not random: that is the behaviour the tier exists to produce.
- Every action's preconditions actually gate it (an action with no valid precondition is never
  selected).
- The flag off is byte-identical to today.

---

# PASS C — The batch objective, built dormant

**The supervisor's requirement: this should stand up on its own the moment bouts assign batches.** Not
a later addition — built now, exercised by tests, and inert in play until `batch_id` is non-zero.

- A coarse batch-level utility pass on the leader picks **one objective** — advance, hold, withdraw,
  flank.
- That objective is injected as **a consideration input for every follower**, not as a destination to
  copy. Squad coordination without a squad planner, and followers keep individual agency.
- **This replaces taskblock-43 Pass D's follower planner**, whose acceptance went unmet — a follower
  that wasn't dramatically cheaper. The answer is a better follower, not a differently-sized local
  scan. Pass C's plumbing carries forward unchanged: `Unit.batch_id`, `BatchPlan`, `claim_batch_lead`,
  `batch_plan_for`, the `set_batch` verb, the board badge.
- **Standing rule 5 applies unchanged.** Leader acts, then follower one, then follower two, each on
  their own turn in initiative order. The objective is computed once and *reused*; it is never a
  licence to resolve several units together.
- **Blackboard access is tier-gated** — `MINDLESS` units get no objective and plan for themselves.
  That is correct, not a gap.

**TESTS:** with every `batch_id == 0`, behaviour is identical to Pass B (the dormancy is the claim, so
assert it); assigning a batch through the injector verb makes the objective flow to followers with **no
other change** — that test is what "stands up on its own" means; a follower's decision differs measurably
with and without an objective; a `MINDLESS` follower ignores the blackboard; leader death mid-round
leaves followers on the round's objective and the next-fastest living member leads next round.

---

# PASS D — Head to head, then flip the default

Decisions are allowed to change, so "not broken" is not the bar. **Characterize the difference.**

Extend the bench to run the same seeds through both planners and report side by side:

| | old | new |
|---|---|---|
| completion rate | | |
| turns to complete | | |
| per-unit plan cost (ms) | | |
| `ShotPlane` builds per turn | | |

- **`MIN_COMPLETION_RATE` holds.** It is the floor, not the goal.
- **Report against `exported_release`, not just `editor_debug`** — taskblock-44 built
  `bench_release.sh` and `BuildIdentity` precisely so this number means something. The release figure
  is the one that describes the game.
- **If the new planner is faster but plays visibly worse, say so and stop.** That is a supervisor
  call, and the head-to-head exists so it can be made on evidence.

Then make the new planner the default and the flag the exception.

---

# PASS E — Delete the old planner, and prove it

**The supervisor's explicit requirement: cleared out completely, no hanging references.**

- Delete `unit_ai.gd` and the old planning path.
- **Sweep for references** — a greppable acceptance in the shape of taskblock-40's `void` sweep:
  nothing in `src/`, `test/`, or `tools/` names the retired planner, its helpers, or its flag.
  Comments and doc-comments included; a stale comment describing a deleted system is what
  `SUPERSEDED.md` exists to prevent.
- **Return `max-file-lines` to 1000** in `run_tests.sh` and delete the accumulated bump rationale. It
  has been raised eight times, every time for this one file, every time on the promise this block is
  now keeping. **The limit coming back down is the objective proof the file is gone** — if it can't,
  something survived and this pass isn't finished.
- Record the retirement in `SUPERSEDED.md`: what the engagement-score planner was, why the utility
  scorer replaced it, and the measured before/after.

**TESTS:** a guard test asserting the sweep is clean, so a later reference can't creep back in silently.

---

# Not this block's job

- **The middle tiers, the rest of the action pool, the rest of the profile table.** `PLAN.md`'s *AI v2
  — fill in the tier table*, deliberately unpinned to a block.
- **Retiring the playstyle enum.** It migrates with the profile table, not with the framework.
- **The view/sim snapshot split and Panic.** Both in `PLAN.md`. A utility scorer *can* return no
  positive-utility action at all, which makes Panic more necessary than it was — but this block only
  needs the turn budget taskblock-44 Pass D already built.
- **Automatic batch assignment in bouts.** Pass C builds the consumer; assignment stays manual.
- **Sensors as parts, fog of war.** The seam receives them; nothing here.
- **Closing BR27.09.** Append the numbers; the supervisor closes it.
