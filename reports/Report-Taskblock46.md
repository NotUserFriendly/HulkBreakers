# Taskblock 46 Report — Fix the ground, then fix the AI

**IN PROGRESS — Passes A, B, C and D landed; stopped at the block's own HARD PAUSE.** E and F are not
started; `taskblock46.md` is the authority on what they are.

**The rolling-five window is NOT rolled yet.** `Report-Taskblock41.md` stays until this block
finishes.

## Decisions made without asking

- **Passes A and B landed as one commit.** They are coupled by construction: A changes what every
  seed generates, which invalidates the floor B re-derives, so A alone leaves the suite red against a
  constant calibrated on the old maps. Two commits from one green run would have been fiction.

- **BR40.03 offered two candidate fixes and named neither as chosen; I took option (a).** A blocker
  cell is excluded from the flatten decision and answered from its surroundings instead. It preserves
  the sealed-room case the pass exists for — a room behind a blocker is still unreachable and still
  flattens, taking its cover down with it — where option (b) (flatten by region) would have needed a
  region model the generator does not have.

- **A blocker cell keeps its own authored level rather than adopting a reachable neighbour's**, which
  is what BR40.03's option (a) literally described. Copying the neighbour is wrong at a room boundary:
  a crate on the edge of a raised room sits next to a ground-level corridor cell, and adopting that
  height punches the same hole from the other side.

- **`SAMPLE_SEEDS` is 20, not the 10 the taskblock implied.** Sized from measured cost — see below.

- **The in-window runner is a `DebugVerbs` row**, which is the one entry in that table that is not a
  `BoutInjector` call and mutates nothing. The alternative was a bespoke button with its own form
  handling; that table is the only surface that already turns "a thing you can do from the window"
  into typed parameters.

## Tests that failed, then were corrected

Two, both mine, both caught before commit.

1. **The connectivity check was 4-way; the flood is 8-way.** Written orthogonal-only first, it left
   **one crate sunk out of 9,279** across the sweep. Asking "is anything next to this reachable" with
   a different adjacency than the flood that produced the reachable set is simply a different
   question. One cell in nine thousand is exactly the density at which a wrong answer reads as
   acceptable rounding rather than a bug.

2. **My own pit tests were vacuous and the supervisor caught it, not me.** "No cell sits in a pit" is
   free on a flat map, so a change that stopped generating elevation would have turned the whole file
   green while deleting the feature it guards. `test_the_generator_still_authors_raised_rooms` now
   pins 30/40 maps and >5% of floored cells raised. **Maps are not forced flat** — the fix removed
   pits, not elevation, and the raised-room count is unchanged from BR40.03's pre-fix measurement.

## Passes C and D

**C filled the hole and it worked.** Completion **54% → 60%** over 100 seeds, and the breakdown shows
the intended mechanism rather than a coincidence: **`TERMINATED` 37 → 27** — bouts that never ended
now end — with `STRANDED` 9 → 13, because units that search actually find each other. The gap to the
old planner narrows **25 → 15 points**.

Four search verbs, each a `.tres` gated on `Unit.search_behaviour` as a precondition, so exactly one
is offered to any unit. **Roam, hunt and putter are one published input under three curves** — three
behaviours with no code between them, which is the clearest thing in the pool for what the model is
for. Patrol owns the only state, so it is its own class; points are derived from the map with no RNG,
and "visited longest ago wins" buys every-point-visited, no ping-ponging, and unreachable-points-age-
out with nothing to detect or remove.

**C3 confirmed the taskblock's guess rather than assuming it.** `Pathfinder.reachable` already built a
full cost map and discarded it, so `closes_distance` now reads real path distance from one flood
rooted at the target. Measured on the case: **against the wall 0.500 vs toward the opening 0.667**,
though the wall cell is nearer as the crow flies. `LineOfFire.approach_path`/`closing_path` deleted
with their tests — what replaces them is not a branch at all.

**D named the state the cascade could not express.** A panic emits a reason, and the reason is the
diagnostic: `nothing_offered` says the pool has a hole for this unit, `all_vetoed` says it looked and
wanted none of it, `budget_aborted` says the clock ran out and no verdict was reached. Panic did not
move completion (60% before and after), which is the expected result — it fires only when nothing is
offered, and C made that rare.

## Open questions

- **The suite got slower and it is worth knowing why.** ~355 s before this block; **~600 s on an
  ordinary run and ~1035 s on a run that escalates.** The sampler is most of it: `test_full_mission`
  plays 20 bouts, `test_completion_sampler` a few more, and the raised-room sweep generates 40 maps
  five times over. I cut ~230 s by splitting `draw_seeds` from `run_seeds` — checking that a draw
  repeats no seed does not need twenty missions — but the gate is genuinely more expensive than the
  pinned window it replaced.

- **The escalation fired on the very first n=20 run, and vindicated the planner.** The sample drew
  **5/20 (25.0%)**, well under the floor; the deterministic 100-seed escalation returned **54.0%** and
  passed. That is the whole design working in one run: a pinned window would simply have gone red on
  25% and someone would have lowered the constant again. It cost ~300 s to find that out, which is
  the trade being made.

- **I suspected the sampler and the escalation were measuring different populations, and checked
  rather than redesigning.** The sample draws from seeds 0–9999 while the escalation is fixed at
  0–99, so a harder wide space would have made the gate incoherent — the sample would escalate
  constantly and the escalation would always disagree. Measured: seeds 0–99 give **54%**, seeds
  1000–1099 give **55%**. The space is homogeneous, the escalation is a valid authority, and that
  25% draw was ordinary 1-in-38 variance landing first time out. Recorded so the next person who
  notices the mismatch does not have to re-derive it.

- **`SAMPLE_SEEDS` was raised 10 → 20 on the supervisor's prompt, and the numbers back it.** At the
  measured 0.54 against a 0.35 floor, ~3 s per seed and ~300 s per escalation:

  | n | P(escalate) | ~1 run in | expected cost |
  |---|---|---|---|
  | 10 | 0.114 | 9 | 64 s |
  | 15 | 0.089 | 11 | 72 s |
  | **20** | **0.027** | **38** | **68 s** |
  | 30 | 0.018 | 55 | 95 s |

  **Twenty costs four seconds more in expectation and escalates four times less often.** Expected
  cost is the wrong axis alone — a run that escalates pays the full ~330 s whatever `n` is, so what
  matters for a suite people wait on is how often that happens. Note 12 is *worse* than 10 (0.126):
  the threshold is an integer count, so `ceil(0.35 × 12) = 5` demands 41.7% where `ceil(0.35 × 10) = 4`
  demands 40%. Sizing this by intuition walks into that.

- **The AI regression is smaller than taskblock-45 reported, and for a reason that was guessed
  wrong.** 87.5%/54.2% became **75.0%/50.0%** on level ground — the gap narrowed from 33 points to
  25. But taskblock-46's hypothesis was that the three shared-failure seeds were map-gen all along;
  **only seed 6 was.** Seeds 1 and 2 still fail under both planners, so that component is something
  else. True rate is **54%** over 100 seeds.

- **The block's HARD PAUSE is where this stops, and the decision is the supervisor's.** Completion
  against Pass B's fresh baseline: **54% → 60%** over the same 100 seeds, old planner 75%. The floor
  (0.35) holds comfortably. **Whether that counts as "recovered" is the call the pause exists for** —
  it is real progress and it is still 15 points short, and the taskblock's own warning is that
  filling the tier table on a planner that cannot finish a mission buries the regression under a
  hundred new decisions.

- **What is left in the 40 failures, for whoever picks this up.** 27 `TERMINATED` and 13 `STRANDED`.
  The `STRANDED` count ROSE (9 → 13) as a direct consequence of C: units that search find each other,
  and some of those fights are lost. That is a different problem from the one this block fixed, and
  it wants combat quality rather than another gate.

- **Two lessons re-learned the hard way, both already written down somewhere.** The candidate-cell
  early-out was wrong for the *second* time (it gates on having a reason to move, and that list is
  never complete); and Panic shut down a unit holding its extraction tile, which the retired planner
  had a guard for and a comment saying it had been caught live. Both were caught by tests rather than
  by review.

- **The suite is ~1290 s and Pass C is why.** Search verbs make bouts longer (mean 9.8 → 12.0 turns),
  so every bout-running test costs more. Moving the escalation out of `run_tests.sh` (supervisor's
  call) keeps the worst case bounded, but the base cost roughly doubled across this block.

- **The tb38 flat-bout guard has been re-pinned four times in two taskblocks.** It was written for a
  block that promised not to change flat play; it is now in practice an AI-behaviour change detector,
  because its two weaponless units are exactly the case the AI work keeps changing. Flagged in the
  file itself: if AI blocks keep re-pinning it, narrow it to something with no planner in it rather
  than keep re-pinning.
