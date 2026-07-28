# Taskblock 46 Report — Fix the ground, then fix the AI

**IN PROGRESS — Passes A and B only.** C, D, E and F are not started; `taskblock46.md` is in the tree
and is the authority on what they are. Suite green, 2295/2295.

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

- **Passes C–F remain**, and C is where the regression actually gets addressed: the action-pool hole
  (`BR45.03`) and `approach` scoring straight-line distance where it needs path distance
  (`BR32.10`). The hard pause before Pass E stands.
