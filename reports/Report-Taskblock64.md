# Taskblock 64 Report — a bout that produces gunfire

Passes **A** (measure), **B** (the ray-march divergence), **C** (a chaingun unit can fire), **D**
(the library cross-product) and **E** (a bout can be won by fighting) have landed, in that order,
each green on the fast gate. **F and G are not yet done.** The block's headline finding is that its
own premise was wrong: `BR63.05` is titled *"units do not see enemies at one to two cells"*, and at
the decision level, on a bare board, **every preset saw its enemy in all 18 cases**. The silence was
three unrelated things, none of them sight — a tier gate, a missing `burst` action, and a preset
armed with a gun its own tier could never fire. All three combat presets now produce a firing action
at one, two and three cells.

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

**`burst.tres` copies `shoot`'s weights rather than choosing its own.** `base_weight = 1.5` and the
same five considerations, because *"aligned with shoot"* was the instruction and a different number
would be an invented balance decision. **`auto_shotgun` provides both**, so they tie and the
considerations decide — untested, and queued in `PLAN.md` rather than guessed at.

## Tests that failed, then were corrected

**Six, four of them my own instruments reporting the wrong thing.**

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

## `SUPERVISOR`-owned entries moved to `Pending`

- **`BR63.04`** — a chaingun unit has no firing action it can reach. **To see it work:** run an
  all-chaingun roster; it should now produce burst fire rather than 31 silent turns. `burst` is
  gated `GRUNT`/`TRAINED`/`ELITE` exactly as `shoot` is, and `shoot` is now refused to a burst-only
  weapon the way it is already refused to a saw.

`BR63.05` is **left `Active`** rather than moved. Most of what it describes is explained and its
stated cause is corrected in place, but the one observation it was opened on — an `ELITE` choosing
`roam` at two cells — does not reproduce, and marking it `Pending` would assert a verification
nobody performed.

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
