# Taskblock 46 Report — Fix the ground, then fix the AI

**Passes A–F landed in order; suite green.** The supervisor cleared the block's own HARD PAUSE
("Send it, ready for E") on a 54% → 60% completion recovery against the old planner's 75%.

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

- **`SAMPLE_SEEDS` is 20, not the 10 the taskblock implied**, raised on your prompt and sized from
  measured cost rather than feel. At the measured 0.54 against a 0.35 floor, **n=10 escalates 1 run in
  9 and n=20 escalates 1 in 38, for four seconds more in expectation** — a run that escalates pays the
  full ~330 s whatever `n` is, so how often that happens is what matters for a suite people wait on,
  not the average. Note 12 is *worse* than 10 (0.126 vs 0.114): the threshold is an integer count, so
  `ceil(0.35 × 12) = 5` demands 41.7% where `ceil(0.35 × 10) = 4` demands 40%. The full table lives in
  `completion_sampler.gd` beside the constant it justifies.

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

- **`item`, `call help`, `bait` and `ambush` are queued, not built.** They are four cells of the tier
  table the taskblock listed under Pass E, framed as "the executors already exist; each addition needs
  preconditions and a consideration set, not new machinery." **That is true of `flank` and `suppress`
  and false of these four** — none has an executor, and `call help` has no *mechanism*: a unit cannot
  influence another unit's plan today, and the batch objective is set by a leader rather than requested
  by a follower. Authoring it would have meant inventing the mechanism it needs.

- **The tb38 flat-bout guard was narrowed rather than re-pinned a fifth time.** Pass E's pool changes
  diverged it again (`239821190` → `1865180114`). All four previous re-pins were deliberate AI changes,
  so the guard had become an AI-change detector that goes red on purpose; its own note said the honest
  move was to narrow it to something with no planner in it. The bout is now a scripted action queue
  through the same `resolve_until`, still guarding movement, per-tile facing, AP accounting, turn
  structure and the log's shape. The alternative was a fifth re-pin, which the file argued against.

- **The in-window runner is a `DebugVerbs` row**, which is the one entry in that table that is not a
  `BoutInjector` call and mutates nothing. The alternative was a bespoke button with its own form
  handling; that table is the only surface that already turns "a thing you can do from the window"
  into typed parameters.

## Tests that failed, then were corrected

**Seven failing before correction, all mine.** Five below; the two omitted are the same shape as #5 —
four batch-objective tests went red because making objective-*setting* Elite-only meant their Trained
leaders correctly set nothing.

1. **The connectivity check was 4-way; the flood is 8-way.** Written orthogonal-only first, it left
   **one crate sunk out of 9,279** across the sweep. Asking "is anything next to this reachable" with a
   different adjacency than the flood that produced the reachable set is simply a different question.
   One cell in nine thousand is exactly the density at which a wrong answer reads as acceptable
   rounding rather than a bug.

2. **My own pit tests were vacuous and the supervisor caught it, not me.** "No cell sits in a pit" is
   free on a flat map, so a change that stopped generating elevation would have turned the whole file
   green while deleting the feature it guards. `test_the_generator_still_authors_raised_rooms` now pins
   30/40 maps and >5% of floored cells raised. **Maps are not forced flat** — the fix removed pits, not
   elevation, and the raised-room count is unchanged from BR40.03's pre-fix measurement.

3. **Two test boards were not the boards their own comments described, and fixing that produced the
   opposite error immediately.** Both built walls with `place_floor` plus a hand-assigned blocker,
   which is cover everything can see straight through — sight is blocked by `Grid.opacity`, and only
   `GridFixture.place_wall` sets it. The lookahead reporting every cell as maximally threatened is what
   exposed it. Then a wall drawn *across* the firing lane hid the enemy outright, every combat action
   fell out of the pool, and all four profiles returned the single verb they had left. **A board that
   cannot express a difference is not evidence that there is none.** Cover beside the lane, never
   across it.

4. **My depth-3 assertion failed because the lookahead was right and I was wrong.** I asserted a cell
   behind cover predicts safer than one in the open. At depth 3 it does not — the enemy walks around
   the cover — and that *is* the capability being built. The test now asserts the transition (0.00 →
   1.00 on the named cell) rather than the property I had assumed, which is a far stronger claim.

5. **The two assertions the taskblock said matter most both failed, and both were real findings rather
   than test bugs.** Elite and Trained had identical action pools — because I was comparing one of
   `docs/11`'s three columns, and Elite's whole difference is in the other two. And `defensive`
   withdrew exactly as readily as `cowardly` because it had **no stated weight** for `seek_extraction`:
   an absent weight is a neutral opinion, and "defensive" is not neutral about retreat.

## `SUPERVISOR`-owned entries moved to `Pending`

- **BR40.03** — cover no longer generates below its room's floor. **0 sunk cover cells in 9,279** over
  the entry's own 40-seed sweep, against 483 of 2,882 before; elevation verified still present, 30/40
  maps. *To see it: look at a generated map with a raised room — no crate should sit in a hole.*
- **BR40.04** — same fix, no ordering change needed. **0 spawn cells with only their own cell
  reachable** (seeds 17, 18 and 38 previously), **0 non-uniform spawn zones** against 8 of 80. *To see
  it: start a generated bout — no unit should spawn in a pit it cannot leave.*
- **BR32.10** — re-tested on concave geometry. The tb33/tb35 Dijkstra branch this entry cites is
  **deleted**; what replaces it is path distance from one flood, so routing around a pocket is ordinary
  scoring rather than a fallback that has to fire. *To see it: this entry's blocker was always that it
  needs a supervised bout. Headless coverage exists; live observation is what is missing.*

**BR45.03 stays `Active` deliberately.** Its closure condition is `MIN_COMPLETION_RATE` back at 0.5 and
it is at 0.35. Its leading hypothesis was right and is fixed, which bought 6 points of the 25 — so the
hole was real and was not the whole regression.

**BR35.06 was closed `Obsolete` by CC**, which is inside my gate (`CC`-owned). `Obsolete` rather than
`Resolved` because the code it describes was deleted by taskblock-45 and nobody verified a fix; I
checked the symptom separately and it does not reproduce.

## Open questions

- **The tier table is built and nothing reaches it, and the sequencing is your call.**
  `Unit.intelligence_tier` defaults to `TRAINED` and nothing authors it — not a preset, not a matrix,
  not a roster entry. So the Mindless, Grunt and Elite rows, the memory and blackboard gates, and the
  entire Elite lookahead are reachable from tests and by hand only, and **every completion rate this
  project has ever measured — including the old planner's 87.5% — is an all-Trained rate.** I put
  authoring it at `PLAN.md` NEXT item 2, *behind* Attributes, because `docs/11` says tier should derive
  from Attributes rather than stay authored and doing it twice is the alternative. The fork: accept a
  built-but-unshipped table until Attributes land, or author tiers onto presets now and re-derive them
  later. Evidence points at waiting — but it means the next block's AI measurements are still
  single-tier, and that is worth saying out loud rather than discovering later.

- **Completion did not move in Pass E, and could not have.** The green run drew 20 random seeds and
  returned **9/20 (45.0%)** — above the 0.35 floor, no escalation, within ordinary variance of the 60%
  the 100-seed escalation measured at Pass C. The tier table cannot have moved it either way for the
  reason above: every unit in that sample is `TRAINED`. Recorded rather than escalated, because
  chasing a 20-seed reading against a 100-seed one is exactly how last block's mid-change 37.5% got
  reported as fact.

- **A post-block finding that matters more than anything in the block: `ROAM` and `HUNT` had no
  memory, and shipped oscillating.** You spotted it in a live bout; the combat log made it
  unambiguous — every unit on both squads decided `roam` every turn and covered two or three cells for
  the whole bout. Distance-from-here is memoryless: the farthest cell from A is B and the farthest from
  B is A. taskblock-46 Pass C had **already written the fix down** in `SearchRoute`'s own comment and
  applied it to `PATROL` alone, because that was the only verb with a route to hang it on. Now a
  published input (`BR46.01`, fixed and `Pending`).

  **It did not move completion**: 56/100 after the fix, against a stale 60/100 that predates Pass E, so
  there is no clean before/after. What it did move is the failure mode — `TERMINATED` 27 → 20,
  `STRANDED` 13 → 24. A 20-seed run showed 70% and I am recording that it was a lucky draw rather than
  the result, because this project has now reported three numbers early.

- **`BR46.02` is open and needs a design call from you.** Chasing the other half of your report —
  "Squad 1 is trapped in a lowered section" — found that **16 of 40 generated maps contain ground a
  unit can walk into and never leave**, worst seed 216 cells. Descent is free; climbing reads a
  `CLIMBER` tag no part carries. A symmetric connectivity check reports these maps as fine (spawn zones
  are mutually reachable on 60 of 60 seeds), which is why it survived this long. Three options, none
  obviously right — author a `CLIMBER` part, constrain `MapGen` to two-way connectivity, or have the
  planner refuse a one-way step. Evidence points at the second as the floor and the first as the
  feature; the third is a mitigation. **Not picked, because it is a balance-and-content call.**

- **What is left in the 40 failures, for whoever picks up `BR45.03`.** 27 `TERMINATED` and 13
  `STRANDED`. The `STRANDED` count **rose** (9 → 13) as a direct consequence of the search verbs: units
  that search find each other, and some of those fights are lost. That is a different problem from the
  one this block fixed — it wants combat quality, not another gate — and it is the reason the remaining
  15 points to the old planner will not come from the same lever twice.

- **The suite is ~1370 s and roughly quadrupled across this block** (~355 s before it). Two causes, both
  deliberate: the completion gate genuinely plays 20 bouts where the pinned window played 12, and the
  search verbs make each bout longer (mean 9.8 → 12.0 turns). I already cut ~230 s by splitting
  `draw_seeds` from `run_seeds`, and moving the escalation out of `run_tests.sh` was your call and
  bounds the worst case. **If this is too slow to live with, the lever I would reach for next is
  `SAMPLE_SEEDS` back to 10** — it costs 4 s in expectation and escalates four times more often
  (1-in-9 rather than 1-in-38), which is the trade in the opposite direction. Flagging rather than
  taking it, since you sized this one.
