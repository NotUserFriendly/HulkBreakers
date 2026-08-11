# Taskblock 64 Report — a bout that produces gunfire

**Every pass has landed** — A (measure), B (the ray-march divergence), C (a chaingun unit
can fire), D (the library cross-product), E (a bout can be won by fighting), G (the two clocks) and
F (the ladder), in that order, each green on the fast gate. **F went last on purpose** — both its
entries needed design calls rather than repairs, and one of them had the wrong mechanism recorded,
so it was measured, taken to the supervisor, and only then built. The block's headline finding is
that its
own premise was wrong: `BR63.05` is titled *"units do not see enemies at one to two cells"*, and at
the decision level, on a bare board, **every preset saw its enemy in all 18 cases**. The silence was
three unrelated things, none of them sight — a tier gate, a missing `burst` action, and a preset
armed with a gun its own tier could never fire. All three combat presets now produce a firing action
at one, two and three cells.

The block ends with the suite profile rebuilt for the first time since taskblock-56. **That
regeneration turned the fast gate red on three counts, none of them false** — two files were
building bouts inside the fast gate and five work budgets were stale — and almost none of the
overshoot was this block's. Details under *Gate timings and what the audit rebuild cost*.

<!-- Rewrite this opening whenever a later pass moves it. -->

## Decisions made without asking

**Pass A was measured a third time, at a layer the taskblock did not name.** A1 and A2 both asked
`LoS.has_los` — a ray between two cell centres — because the spec and `BR63.05` both frame the
defect as sight. That is not the gate: `AttackAction.is_legal`'s `has_los` check was deleted at
tb61 Pass D, and `WorldView._has_direct_sight` records that it is deliberately `LoS` and not
`LineOfFire`. A3 (`test_close_range_firing_decision.gd`) asks the planner instead, through the real
preset library, on a board with no geometry on it at all. **The alternative was to accept A2's sight
sweep as the answer**, which would have shipped a correct measurement of the wrong thing — the
supervisor's prompt is what redirected it, and the redirect is the reason the block found anything.

**`test_close_range_firing_decision.gd` asserts a library contract, not a tier rule.** The obvious
assertion — *every preset must produce a shot* — contradicts `docs/11`, which gates `shoot` to
Grunt-and-above deliberately. What it asserts instead is that **a preset armed with a weapon must
be able to fire it**, which is violated either way it is repaired and does not encode a design
opinion. Scoped to `profile_family == &"combat_tester"` on the supervisor's call.

**Pass B fixed three causes where one was filed.** `BR64.01` was filed from A2 with a suspected
cause (a height mismatch). That suspicion turned out to be the *second* of three, and fixing only it
would have left 6 of 56 divergences and looked closed. **The alternative was to close on the first
green sweep**; the sweep was re-run on the seed that exposed the defect instead, which is what
surfaced causes two and three.

**`LoS._endpoints` now walks the socket tree.** This widens the endpoint exemption — a ladder bolted
into an endpoint cell's floor no longer blinds the unit standing there. Defensible as stating the
rule the function's own doc comment already claimed (*"every part standing at either endpoint
cell"*), but it **is** a semantic change and it moves real blindness numbers, so it is called out
rather than buried in a refactor.

**Pass E needed a fourth `MissionOutcome`, and that was escalated rather than decided.** `docs/00`
states as a pillar that combat never ends because the enemy is dead, and all three existing outcomes
are written in terms of the *player* squad — so a contest mode had nowhere to record "the other team
is finished". Taken to the supervisor, who added the constraint that bouts are frequently run
AI-vs-AI and asked for a **generalised** `DEBUG_ENDED` rather than a contest-specific value, so later
harness endings can reuse it. `docs/00` and `docs/07` are annotated rather than rewritten: the pillar
still governs every campaign mission.

**`MissionState.team_can_contest` asks reachability, not "is the gun working".** A `GRUNT` holding a
chaingun had a perfectly operable weapon, so a functional-weapon test would have left `BR63.04`'s
bout running to the turn cap — the exact thing the mode exists to stop. The alternative was the
cheaper predicate; it would have made the instrument useless for the case it was built for.

**Pass F was measured first and escalated rather than decided.** `BR63.01`'s *"each should be 1
unit"* meant changing `Surface.LADDER_SEGMENT_RISE`, which `Pathfinder`'s ladder branch and
`Surface.ladder_serves_climb` both read; `BR63.02` turned out to be a **double-draw** rather than
the offset its entry guessed at, so which of the two emissions to stop was a real fork. Both went
to the supervisor with the arithmetic attached, and both came back decided.

**One of those decisions turned out to cost nothing.** "Hold climb cost steady" needed no
compensating constant at all: `Pathfinder.move_cost` prices a ladder edge by **rise**, never by
segment count, so halving the segment moves no balance number. That is asserted rather than argued,
because the claim only survives while the formula stays height-based.

**Pass F's emission rule has a stated limit, not a hidden one.** `UnitGeometry.surface_placements`
stops at sockets, which is safe only because every socket occupant of a surface is independently
placed — measured at 35 occupants across five boards, zero orphans. **A future part socketing a
purely decorative child onto a floor would stop being drawn.** That is written into the function's
own comment rather than left for the next reader to rediscover.

**Pass G stopped at the board clock and did not touch the unit-part one.** `BR54.02` is the same
pairing from the other side, and the entry asks for it to be checked against whatever clock the
teardown now reads. It is a *unit's* part, and unit views refresh **before** playback on purpose
(`ResolutionPlayer._prime` needs that frame). Moving that would reopen `BR51.21`, so it is stated as
untouched rather than attempted.

**`burst.tres` copies `shoot`'s weights rather than choosing its own.** `base_weight = 1.5` and the
same five considerations, because *"aligned with shoot"* was the instruction and a different number
would be an invented balance decision. **`auto_shotgun` provides both**, so they tie and the
considerations decide — untested, and queued in `PLAN.md` rather than guessed at.

## Tests that failed, then were corrected

**Nine, six of them my own instruments reporting the wrong thing.**

1. **`test_close_range_firing_decision.gd` read a working burst as silence.** It detected a shot
   with `action is AttackAction`; `BurstAction` extends `CombatAction` **beside** `AttackAction`,
   not under it. The chaingun was selecting `burst@(6,6)` and building it correctly the whole time.
   **The most useful failure here** — a measuring test that under-reports is exactly what this block
   exists to catch, and it nearly sent me looking for a second executor bug.
2. **The `BR64.01` breadth sweep passed with the bug reintroduced.** Written on seed 4242 at 24x18,
   which contains no ladder socketed into a floor ledge on any swept pair. Caught by deliberately
   reverting the fix and re-running — the check that should be routine and usually is not. Replaced
   as the guard by a hand-built fixture; the sweep stayed, with its limitation written into its own
   doc comment.
3. **Both agreement sweeps re-derived the endpoint exemption from `grid.parts_at`** instead of
   calling `LoS._endpoints`. They therefore could not see the third cause at all, and showed 6
   stubborn disagreements that vanished the moment they asked the real rule. **A test that rebuilds
   the rule it is testing agrees with itself and nothing else** — the same shape as the camera-yaw
   bug in CLAUDE.md.
4. **A1's `test_a_wall_between_two_units_blocks_but_cover_does_not`** asserted a mechanism that is
   false. Not a broken fixture — a correct test of a wrong claim, reversed in `SUPERSEDED.md` and
   rewritten to enumerate `MapGen.COVER_IDS` and assert the real rule.
5. **Pass E's first fixture hung the suite instead of failing it** — nine minutes elapsed against
   one second of CPU. A weapon socketed straight onto a torso with no manipulator and no docked
   matrix is *nearly* a unit, and a bout built on it blocked on an await rather than refusing. Fixed
   by copying `test_bout_runner.gd`'s known-good shape wholesale. **A hang is a worse failure than a
   red test** and it cost more time than everything else in the pass combined.
6. **Two Pass E fixtures were wrong about the board and the API** — units placed at `(6,6)` on a
   12x5 grid (`set_occupant_id` out of bounds), and `BoutRosterEntry.profile_id`, which is actually
   `ai_profile`. Both mechanical, both caught on the first real run.

7. **Six ladder fixtures were pinned to the old 2.0 segment spacing** and broke when Pass F halved
   it — `test_ladder.gd`, `test_vertical_movement.gd`, `test_distance_flood_direction.gd`,
   `test_generation_heights.gd`, `test_vertical_planning.gd`, and my own `BR64.01` control. Every
   one was a fixture assumption rather than a defect: the rises, and therefore every MP figure,
   are unchanged. Two are worth naming:
   - `test_three_stacked_segments_span_three_levels` asserted a reach of **6.0** while calling it
     "three levels" — it was counting in 2.0 segments against a `LEVEL_HEIGHT` of 1.0. The name and
     the number agree now.
   - **`BR64.01`'s control went vacuous rather than red.** It asserted *"a 2.0 ladder across the
     line still blocks"*; a 1.0 ladder tops out below `SIGHT_HEIGHT` and stops blocking for a
     reason unrelated to the exemption under test. It stacks two segments now. **A control that
     silently stops controlling is worse than one that fails.**
8. **A "new" ray-loop disagreement that was a floating-point corner graze.** The sweep reported
   `(21,7)->(24,9) obstructed=false march=forklift` after Pass F. The ray passes through the box's
   **exact corner vertex** — hit point `(21.450001, 2.100000, 7.300000)` against a box ending at
   x 21.45, y 2.10, z 7.30 — and the sweep was handing `cast_geometry` an already-normalised
   direction which it normalised **again**, landing one float ULP away from the `span / length`
   `obstructed` computes. Neither loop is wrong; the query is ill-posed. Passing the raw `span`
   makes the two bit-identical. **Worth the chase**: the alternative was recording a structural
   divergence that does not exist.
9. **My own claim that `BR63.03` was a drawing defect only.** Targeting and cell occupancy did
   already exclude an extracted unit, so "the model is fine" looked right — until the turn-order
   case was actually run and reached the extracted unit. **It was a gameplay defect too**, and the
   entry's suspicion was correct where my first reading was not. The test that caught it is one I
   wrote to confirm the opposite.

## `SUPERVISOR`-owned entries moved to `Pending`

- **`BR63.03`** — extracted units remain on the map. **To see it work:** extract a unit; it should
  vanish from the board, stop being handed turns, and stop blocking selection. Both halves were
  real — the turn-order half is `BR51.04`/`BR51.05` reintroduced through `extract_unit` doing
  `kill_unit`'s job by hand.
- **`BR61.07`** — the destroyed thing's clock. **To see it work:** force a detonation that destroys
  more than one thing. Each should stay until its own explosion has played and then go, rather than
  all of them vanishing at the very end.
- **`BR63.01`** — ladder height. **To see it work:** a one-level rise should be a single piece that
  stops level with the floor it serves, not one standing a level proud of it. Climb costs are
  unchanged and that is asserted, not assumed.
- **`BR63.02`** — the double-draw. **To see it work:** a ladder should be one panel per level on one
  face, with no second panel half a cell away from it.

**`BR63.04` was closed `Resolved` by the supervisor** during this block, after Pass C.

`BR63.05` is **left `Active`** rather than moved. Most of what it describes is explained and its
stated cause is corrected in place, but the one observation it was opened on — an `ELITE` choosing
`roam` at two cells — does not reproduce, and marking it `Pending` would assert a verification
nobody performed.

## Gate timings, and what the audit rebuild cost

**Paired CPU/real figures exist only for the runs at the end of the block.** The per-pass gates were
never wrapped in `/usr/bin/time`, so their CPU time does not exist and is left blank rather than
reconstructed. `suite` is what `run_tests.sh` reports (test execution); `REAL` is the whole process,
engine startup and shutdown included.

| Gate | After | Scripts | Tests | suite | REAL | USER | SYS | CPU |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| fast | A2 | 336 | 3263 | 650.1 s | — | — | — | — |
| fast | A3/C | 336 | 3263 | 660.8 s | — | — | — | — |
| fast | B | 336 | 3266 | 678.9 s | — | — | — | — |
| fast | D | 337 | 3268 | 682.3 s | — | — | — | — |
| fast | E | 337 | 3268 | 681.9 s | — | — | — | — |
| fast | G | 338 | 3277 | 681.9 s | — | — | — | — |
| full | G | 362 | 3534 | 1767.6 s **(1 fail)** | — | — | — | ~27m10s @ 28m35s |
| full | pool fix | 362 | 3534 | 1879.0 s | — | — | — | 29m51s @ 31m15s, ~95% |
| **full + `WRITE_PROFILE=1`** | audit rebuild | 362 | 3534 | 1434.1 s | 1449.8 s | 1375.2 s | 7.0 s | **95%** |
| fast | audit rebuild | 338 | 3277 | 675.8 s **(3 fail)** | 691.0 s | 635.4 s | 5.1 s | **92%** |
| **fast** | registry + budget fix | 336 | 3249 | 664.9 s | 679.7 s | 624.2 s | 5.1 s | **92%** |
| **full** | registry + budget fix | 362 | 3534 | 1443.5 s | 1458.7 s | 1386.1 s | 7.1 s | **95%** |
| fast | Pass F, ladder fixtures red | 336 | — | 420.5 s **(aborted)** | 420.5 s | 374.3 s | 4.5 s | 90% |
| fast | Pass F, corner graze red | 336 | — | 518.5 s **(aborted)** | 518.5 s | 464.3 s | 4.3 s | 90% |
| **full** | **Pass F complete** | 362 | 3538 | 1378.3 s | 1393.7 s | 1318.3 s | 7.5 s | **95%** |

**The full gate's wall-clock is not a stable number**: five runs of the same suite measured
**1767.6, 1879.0, 1434.1, 1443.5 and 1378.3 s** — a 36% spread. `SUITE-PROFILE.md` says so in its own header
(*"wall-clock is the softer number"*), and the spread is why the budget gates work counters and not
seconds. **Compare the counts; do not compare these.** The two runs after the profile was
regenerated agree to within 0.7% of each other, which is suggestive but is two data points, not a
finding — `run_tests.sh` reorders scripts by failure history, so run composition is not identical
between them either.

**Work counters move between runs too, and by more than the profile suggests.** The same green full
gate reported `bouts 77 / turns 970 / candidates 1 313 572` where the profiled run recorded
`76 / 1063 / 1 233 514`. `test_full_mission.gd` draws its seeds from the clock by design
(`SuiteBudget.TURNS_EXCLUDED` documents exactly this), so turn counts downstream of it are not a
controlled quantity — which is why `turns` is excluded per-file for it and why the budget carries
15% headroom.

**Runs over 10% of a gate's own time.** Only one file crosses it, and it is not close: within the
full gate's 1429.1 s of summed test time, `unit/view/overlays/test_ai_batch_yield.gd` is **279.9 s —
19.6%**. Second is `unit/logic/test_watched_run.gd` at 121.9 s (8.5%). Nothing else exceeds 5%.

Of the individual runs I invoked by hand, one is worth recording: **Pass E's first fixture hung for
~10 minutes** before I killed it — 9 minutes elapsed against 1 second of CPU. That ratio is how a
stuck run is told from a slow one, and it cost more wall-clock than any real gate.

**Two aborted fast gates are in the table on purpose.** Both are Pass F: a gate that stops early
reports a *shorter* time and a green-looking exit code from a pipeline, and recording only the
successful runs would make the block look cheaper than it was. Between them they cost ~16 minutes
finding fixtures pinned to the old ladder spacing.

## The suite profile, rebuilt (last regenerated at taskblock-56)

**Totals, and where they come from.** Per-file figures are in `test/SUITE-PROFILE.md`, which is
generated — this is the reading of them.

| counter | total | files | most concentrated |
|---|---:|---:|---|
| bouts | 76 | 19 | `test_bout_setup.gd` 10 (13.2%), `test_per_tier_probe.gd` 9 (11.8%) |
| turns | 1 063 | 48 | `test_ai_batch_yield.gd` 493 — **46.4% of every turn the suite resolves** |
| candidates | 1 233 514 | 26 | `test_ai_batch_yield.gd` 412 366 — **33.4%** |

**One file is a third of the suite's AI work**, and it is also its slowest at 19.6% of wall-clock.
That is the single most actionable thing the rebuild surfaced.

**Regenerating turned the fast gate red, and none of the three failures were false.** All were drift
the eight-block-stale profile had been hiding, since both guards read the *committed* profile:

- **Four files build bouts and were not registered** in `SuiteTier.BOUT_FILES`.
  `test_intelligence_tiers.gd` and `test_step_height.gd` had **no `should_skip_script()` at all** and
  were building bouts *inside the fast gate* — exactly what the list exists to prevent.
  `suite_tier.gd` already carried a note about this happening at tb56 for the identical reason.
- **`test_full_mission.gd` read as a stale entry and is not one.** It reaches the shared corpus
  through `CompletionSampler`, so on a full run another reader always pays first and it measures
  zero bouts while genuinely resolving a 43-turn mission. Moved to `CORPUS_READERS`.
- **Five budget violations, and almost none of them are this block's.** Measured tb64 contribution
  against each overshoot: **bouts +11 over (2 mine), turns +175 (~14 mine), floods +267 (~35 mine),
  ui_builds +545 (0 mine)**. The per-file cap on `test_ai_batch_yield.gd` was 136 turns against 493
  measured, and nothing in tb64 touches that file. Re-ratcheted to measurement.

**The judgement half of the audit is not done.** `suite_audit.csv` is rebuilt — 3534 rows against
3534 declared tests, with **2557 of 2607 hand-filled `rule_guarded` cells carried forward verbatim**
(the 50 lost are tests that no longer exist: `ClimbAction`'s, retired at tb62, and the LoS legality
gate's, removed at tb61). **977 rows carry no rule**, and `test_every_row_carries_a_rule` fails on
exactly that. Per `TEST-AUDIT.md` a failing audit run is a report, not a broken build — this one
reads "977 tests added since taskblock-56 have never been classified".

## Open questions

**The `ELITE`-chose-`roam` observation is still unexplained.** On bare ground the sniper plans,
backs off past its own `min_range`, and fires. `roam` requires `target == null`, so the unit
genuinely knew of no enemy. Two readings, and the evidence does not separate them: it was one of the
**19 genuinely blind Chebyshev-1 / 193 Chebyshev-2 pairs** the sweep measures on a real board, or
there is a knowledge-layer defect above `LoS` that a bare board cannot reach. **Filed as `Suspected`
rather than guessed at** (see below).

**Should a ladder blind?** It blames 101 blind pairs after Pass B — an open rung structure modelled
as a solid 0.1-thick panel, and tb63 Pass D1 stamps far more of them than any earlier board carried.
The geometry is doing what it is authored to do, so this is a design call, queued in `PLAN.md`, not
filed as a bug.

**The AI tier rework** is queued with what tb64 learned written into it. This block deliberately
patched a regression and moved no gate, per the supervisor's *"fixed, not perfected"*.
