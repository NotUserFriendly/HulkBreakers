# Taskblock 46 Report — Fix the ground, then fix the AI

**Passes A–F landed.** The supervisor cleared the block's HARD PAUSE ("Send it, ready for E") on a
54% → 60% recovery against the old planner's 75%.

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

- **The lookahead is exposed as a consideration input, not as a search sitting beside the scorer.** The
  taskblock asked for depth 2–3 and named resumability as the hard part; it did not say where the
  result goes. One place to decide is the no-parallel-systems rule.

- **`THREAT_FLOOR` is 0.6 — gentle, and floored rather than allowed to veto.** An Elite unit that has
  walked into a crossfire predicts high threat everywhere it can reach, and an unfloored inversion
  would take every candidate to zero and `Panic`. The smartest tier must not be the one that freezes.
  Flagged as tunable; no balance number was invented to make a test pass.

- **`NO_PREDICTION` is 0.0, not a mid "unknown".** Inverted, 0.0 multiplies out to exactly 1.0, so
  adding the consideration cannot move any tier that does not search. A 0.5 default would have
  re-scored every Grunt and Trained unit in the game because of a capability they do not have.

- **Old playstyles map to profiles by behaviour, not alphabetically.** MARKSMAN and COVER_SEEKER were
  both "hold and shoot from cover" → `defensive`; SKIRMISHER "keep distance, flank" → `cautious`;
  PSYCHOTIC → `aggressive`.

- **The bout maker's default roster is now paired by temperament, and the rationale changed with it.**
  It used to be range-matched because a playstyle carried a preferred range. Standoff is scored against
  the unit's own weapon now, so pairing by weapon would be pairing on a property the profile no longer
  has.

- **The in-window runner is a `DebugVerbs` row**, which is the one entry in that table that is not a
  `BoutInjector` call and mutates nothing. The alternative was a bespoke button with its own form
  handling; that table is the only surface that already turns "a thing you can do from the window"
  into typed parameters.

## Tests that failed, then were corrected

Seven, all mine. Two in Passes A–D, five in Pass E — and the Pass E five are all one kind of mistake,
which is the part worth reading.

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

3. **Two test boards were not the boards their own comments described.** Both built walls with
   `place_floor` plus a hand-assigned blocker, which is cover that everything can see straight
   through — sight is blocked by `Grid.opacity`, and only `GridFixture.place_wall` sets it. The
   lookahead's every-cell-is-maximally-threatened result is what exposed it.

4. **Fixing that produced the opposite error immediately.** A wall drawn *across* the firing lane hid
   the enemy outright, every combat action fell out of the pool, and all four profiles returned the
   single verb they had left — four identical rows reading as four decorative profiles rather than as
   a board with nothing on it to disagree about. **A board that cannot express a difference is not
   evidence that there is none.** Cover beside the lane, never across it.

5. **My depth-3 assertion failed because the lookahead was right and I was wrong.** I asserted that a
   cell behind cover predicts safer than one in the open. At depth 3 it does not — the enemy walks
   around the cover — and that *is* the capability. The test now asserts the transition (0.00 → 1.00
   on the named cell) instead of the property I had assumed, which is a far stronger statement.

6. **Two tier/profile tests failed on the assertions the taskblock said matter most, and both were
   real findings rather than test bugs.** Elite and Trained had identical action pools, because I was
   comparing one of `docs/11`'s three columns; and `defensive` withdrew exactly as readily as
   `cowardly` because it had **no stated weight** for `seek_extraction`. An absent weight is a neutral
   opinion, and "defensive" is not neutral about retreat.

7. **Four batch-objective tests went red on a correct change.** Making objective-*setting* Elite-only
   meant their Trained leaders correctly set nothing. The tests moved to Elite leaders; the two
   Mindless tests already asserted the same gate from the other side.

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

## Passes E and F

**The tier table is filled and it is unreachable.** This is the block's most important result and it is
not a good one: `Unit.intelligence_tier` defaults to `TRAINED` and **nothing authors it** — not a
preset, not a matrix, not a roster entry. So the Mindless, Grunt and Elite rows, the memory and
blackboard gates, and the entire Elite lookahead are reachable from tests and by hand only. Every
completion rate this project has ever measured, including the retired planner's 87.5%, is an
all-Trained rate. It is now `PLAN.md` NEXT item 2, behind Attributes because tier should derive from
them rather than stay authored.

**Four of the table's rows could not be filled by authoring, and I did not build them.** `item`,
`call help`, `bait` and `ambush` have no executor; `call help` has no *mechanism* at all — a unit
cannot influence another unit's plan today, and the batch objective is set by a leader rather than
requested by a follower. Authoring an action for it would mean inventing the mechanism it needs.
Queued in `PLAN.md` with that distinction spelled out, because the rest of Pass E was authoring and
this is building.

**`regroup` needed no action of its own**, which is worth recording as a small win for the design:
`hunt` is offered at every tier and only *does* anything once the tier has memory to hunt toward. The
information gate does the work an action gate would have duplicated.

**The Elite lookahead is a search expressed as an input.** Depth 2 is the enemy's shot from where it
stands — one visibility field per known enemy, reused across every candidate. Depth 3 is the enemy
moving first and then shooting, which inverts the geometry so the flood must be rooted at the candidate
cell; that is paid per cell and therefore runs over a fixed shortlist of the best-scoring ones. Cost is
bounded before it is paid, and `fields_built` is asserted rather than assumed.

I chose the input form over a minimax beside the scorer deliberately: a utility AI has exactly one place
to put "this option is worse than it looks", and giving a unit two ways to decide is the
no-parallel-systems rule broken. The measured demonstration is the one I would show: **a cell in a
wall's shadow predicts 0.00 threat at depth 2 and 1.00 at depth 3**, because the enemy can walk around
the wall. Cover that can be stepped around is not cover.

It costs an extra throwaway scoring pass per Elite turn — the shortlist has to be ordered by something,
and ordering by anything cheaper searches the cells the unit is most likely to reject. Those scores are
discarded rather than reused, because they were taken against a context that did not know about threat.

**Pass F, the bug digest.** BR35.06 is `CC`-owned and closed **`Obsolete`, not `Resolved`** — the code
it describes was deleted by taskblock-45, so nobody verified the defect was fixed; there was nothing
left to reproduce against. I checked the symptom anyway and it does not reproduce, with a test rather
than a paragraph.

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

- **Pass E did not move completion, and the sample says so honestly.** The green run drew 20 random
  seeds and returned **9/20 (45.0%)** — above the 0.35 floor, no escalation, and within ordinary
  variance of the 60% the 100-seed escalation measured at Pass C. **The tier table cannot have moved it
  either way**, because nothing authors `intelligence_tier`: every unit in that sample is `TRAINED`,
  so the Grunt/Elite gates and the lookahead were never reached. Recorded rather than escalated,
  because chasing a 20-seed reading against a 100-seed one is how the mid-block 37.5% got reported as
  fact last block.

- **`SUPERVISOR`-owned entries moved to `Pending` this block — the "here's what I think I fixed" digest:**
  **BR40.03** (cover no longer generates below its room's floor: 0 sunk cells in 9,279 over the reported
  40-seed sweep, and elevation itself verified still present), **BR40.04** (0 spawn cells with only
  their own cell reachable, 0 non-uniform spawn zones against 8 of 80), and **BR32.10** (re-tested on
  concave geometry; the tb33/tb35 Dijkstra branch it cites is deleted, and what replaces it is path
  distance from one flood rather than a fallback that has to fire — still headless only, which was
  always this entry's blocker).
  **BR45.03 stays `Active`**, deliberately: its own closure condition is `MIN_COMPLETION_RATE` back at
  0.5 and it is at 0.35. Its leading hypothesis was right and is fixed, and that bought 6 points of the
  25 — so the hole was real and was not the whole regression.

- **The block's HARD PAUSE is where Passes A–D stopped, and the decision was the supervisor's.** Completion
  against Pass B's fresh baseline: **54% → 60%** over the same 100 seeds, old planner 75%. The floor
  (0.35) holds comfortably. **Whether that counts as "recovered" is the call the pause exists for** —
  it is real progress and it is still 15 points short, and the taskblock's own warning is that
  filling the tier table on a planner that cannot finish a mission buries the regression under a
  hundred new decisions. **Cleared: "Send it, ready for E."**

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

- **The tb38 flat-bout guard wanted a fifth re-pin, and I narrowed it instead.** Pass E's action-pool
  changes diverged it again — `239821190` → `1865180114` — which would have been the fifth re-pin in
  two taskblocks, every one of them a *deliberate* AI change and none of them a finding the guard could
  report. Its own note said the honest move was to narrow it to something with no planner in it; that
  is now done. The bout is a scripted action queue through the same `resolve_until`, so it still guards
  movement, per-tile facing, AP accounting, turn structure and the log's shape — what a block with no
  business touching the AI would actually break — and no longer guards what the AI *decides*, which a
  hash never reported usefully anyway. Diagonals and reversals are in the script on purpose, since a
  straight line shares a coordinate at every step and hides a facing bug. Re-pinned once, to
  `511851792`, with the original "do not re-pin to make a divergence disappear" rule intact for the new
  scope — with no planner in it, a mismatch really is a bug again.
