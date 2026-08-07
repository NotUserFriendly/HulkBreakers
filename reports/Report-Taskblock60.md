# Taskblock 60 Report — prep for the bug hunt: delete two, instrument four, dissolve seven

All four passes landed in order, plus a supervisor-directed follow-up. **A retired ramps and
introduced `step_height`; B gave all seven firing paths an announcement; C stopped and reported
rather than building, because its premise did not hold; D sorted the ledger; the follow-up
corrected the step height to 0.4 and re-investigated all five `Suspected` entries.**
**Full gate green: 341 scripts, 3345 tests, 0 failures.** **No bug was fixed**, which is the
block's own rule. **The ledger went from 46 open to 45** — three closed (`BR56.01`, `BR51.12`,
`BR52.13`), two filed (`BR60.01`, `BR60.02`), one promoted `Suspected` → `Active` (`BR32.08`).

## Decisions made without asking

**`BASE_STEP_HEIGHT` — I shipped 0.3 without asking, and it was wrong.** Corrected to the
supervisor's 0.4 on 2026-08-07. **The error is worth reading because the design document reads as
though it says 0.3:** `PLAN`'s *"two ordinary tiles at 0.3 and 0.6"* names tile **heights**, and
that flight's steps are 0.3, 0.3 and **0.4** — the largest is the last one, so the example requires
0.4 to be walkable at all. I read tile heights as step sizes and produced a number smaller than the
design's own worked example needs, then presented it as the stated default. **The general lesson is
that "the number the doc names" and "the number the doc's example requires" are different things,
and I checked only the first.**

**It changes the pass's headline finding.** At 0.4 the generator produces **15.7% raised ground and
0 stranded cells**, against the retired ramps' 15.8% — so **the ramp retirement costs essentially
no elevation**, and the 12.8% I reported as its honest cost was an artefact of the wrong constant.
Three fixtures now derive their rise from `BASE_STEP_HEIGHT` rather than writing it as a literal,
because that assertion has now been invalidated twice.

**The repair path lost its ramp branch entirely and always builds a ladder now.** The alternative
was to keep a shallow-repair case. I dropped it because there is nothing left for a one-cell repair
to do: a ramp made a rise free by relabelling a cell, and under `step_height` a rise the repair is
looking at is by definition one no unit could step. A stair needs a run of free cells nobody can
promise at an arbitrary stranded cell; a ladder needs one. This inverted
`test_the_generators_ladder_branch_cannot_currently_fire`, which is what that test's own note asked
for rather than deletion.

**The retired-ramp guard bans three identifiers, not the word `ramp`.** A total ban would be the
wrong instrument — a cosmetic ramp part, `Surface.RAMP_TAG` and sloped `RampGeometry` rendering all
survive on purpose, and a ban cannot tell a correct use from an incorrect one.

**The firing announcement's event kind is `weapon_used`, neutral, with the delivery method as open
data.** The taskblock left this open (*"the term is probably neutral with the weapon's method as
data"*) and I settled it that way. `fired` was the alternative and is wrong for a stab resolving
through the same path. Suppression announces as a **thrust**, because it reaches for a `stab`
provider — the method follows the weapon that delivers, not the rule that triggered it.

**One announcement per trigger pull, not per projectile.** A shotgun's nine pellets read as one
shot; a three-round burst reads as three. Granularity is expressed by how many announcements a
caller builds rather than by a flag, and `burst_fired` is untouched because it answers a different
question and `LogFold` reads it.

**Pass C built nothing.** The taskblock offered *"either the snapshot split lands, or the
seven-entry class is documented as one root with a reason it did not."* I did neither exactly: the
seven are **not** one root, and I documented what each actually is. A half-built snapshot split is
worse than none by the taskblock's own rule, and a grouping that asserts a shared cause I had
tested and disproved would have been worse still.

**Behavioural coverage in Pass B is three paths of seven, deliberately.** `AttackAction`,
`BurstAction` and `StabAction` are driven as real actions — one announcement, several, and the
neutral-vocabulary case, which are the three shapes that fail differently. The other four are
covered by the structural sweep plus their own files. Driving all seven would have duplicated five
existing fixtures. **Written into the test file's header** rather than left to be discovered.

**`BR52.13` closed `Obsolete`, not `Resolved`, and `BR52.14` deliberately left open.** Both are
`CC`-owned so either word was available to me. `BR52.13` does not reproduce — 380 of 2450 impacts
penetrate across six real bouts, against its recorded zero of 156 — but **nobody fixed anything**,
so `Resolved` would assert a verification that never happened. `BR52.14` has gone 98 consecutive
runs clean (3 fails in 236, last at run 138), and I closed nothing on that: ninety-eight clean runs
is not a fix and the entry's own requirement, a captured failure, is unmet.

**`BR32.08` promoted `Suspected` → `Active` on a `SUPERVISOR`-owned entry.** Not a closure —
`Active` is open — but it is a status change on an entry that is not mine, so it is flagged here.
The entry is no longer a vague lead: the mechanism is confirmed in code and described. **Say so if
you would rather I had left the word alone.**

**A regression of mine, fixed rather than pinned — and the distinction is the point.** Shorter
stairs put one seed's spawn zone across a full-level ledge, breaking `BR40.04`. I measured both
sides first (zero non-uniform zones before this block, one after) precisely because I had just used
the pinning mechanism legitimately for a pre-existing defect, and using it for my own regression
would have been the same gesture meaning the opposite thing. **Two attempts, and the first was
worse than the bug it fixed**: see the failure list below.

**`BR60.01`'s pin is kept even though the list ended up empty.** It reproduced at 32x24 for one
build and vanished when the spawn fix landed; at 40x30 it is unchanged across every variation
tried. `KNOWN_UNREACHABLE` is asserted as **equality**, not `is_empty()`, so a reappearance is a
red test rather than a silent pass. **The real fix is to run that sweep at the bout board size**,
where it reproduces every time — recorded in the entry as taskblock-61's.

**The armour-balance observation inside `BR52.13` was moved to `PLAN.md` rather than archived with
it.** `steel.tres` leans on an unauthored 30.0 deflect default against a measured ~31 degree
engagement. That is a decision someone should make, and a closed bug report is where decisions go
to be lost.

## Tests that failed, then were corrected

**Fifteen failing before correction, across six files** — nine in the passes, four when the step
height moved to 0.4, and two more from the spawn-zone regression that move exposed. Almost all were
fixtures holding an assumption the work deliberately reversed, which is the useful kind. **The
exception is item 6, which was mine.**

1. **`test_continuous_height_and_escapes.gd` — the most important one.** It pinned *"a 0.3 rise is
   pathable at the rounded-up partial climb cost"* and *"a non-climber still cannot cross it"*, and
   its own comment recorded that **taskblock-54 tried a free-step threshold and rejected it** as
   contradicting `PLAN.md`'s settled *partial MP costs round up*. So this pass re-introduces a
   previously rejected idea. Corrected by reversing both pins and recording the reversal in
   `SUPERSEDED.md` with the distinction that makes it right this time: step height is not a
   discount on climbing, it is the boundary between walking and climbing, and round-up still
   governs everything above it. A fresh assertion pins that a rise just above the step height
   still rounds up — **derived from the constant, not written as a literal**, because this same
   assertion was then invalidated a second time when the step height moved to 0.4.

2. **`test_map_gen.gd::..._at_most_one_correctly_typed_floor_surface` — the assertion was counting
   the wrong thing all along.** It counted *every* surface at a cell, not every walkable one. A
   ladder is a placed surface too, so a repair ladder sharing a cell with its floor failed it — but
   only once ladders became the only repair. `BR51.12`'s own note predicted exactly this
   ("if that test passes while this reproduces, the assertion is narrower than its name").

3. **`test_map_gen.gd::..._every_raised_area_is_ramp_reachable` — six failures at 0.3, and none was
   elevation becoming unreachable. At 0.4 it failed again, and that one WAS real.** `_raised_regions` counted cells carrying a live blocker as
   raised ground; a blocker cell is unreachable by construction and no unit could stand there. The
   caller's own doc already excused this in prose and the code never implemented it. Measured
   before changing it: the old generator produced **zero** such regions at that board size and the
   new one produces **six, every one exactly one cell with exactly one blocker.** Then the step
   height moved to 0.4 and a genuine 45-cell unreachable region appeared on seed 29 — `BR60.01`
   reproducing inside the suite for the first time, because a shorter stair leaves more rooms
   raised and therefore more of them exposed to a defect that was always there. Pinned by name
   rather than tolerated.

4. **`test_pathfinder.gd` — four failures, all fixtures asserting ramp privilege.** Rewritten as
   step-height and stair claims. One became the inversion that states the whole pass: a ramp-tagged
   surface now buys no traversal the geometry did not earn, asserted against a plain floor at the
   same height behaving identically.

5. **`test_every_firing_path_announces_itself.gd` — my own fixture was wrong, and finding out was
   worth more than the test.** It set a shooter 90° off its target and asserted the announcement
   would record that. It went red because **`AttackAction.apply` free-faces the shooter at the
   target before firing.** See Open questions.

6. **`test_map_gen_raised_rooms.gd::..._uniform_floor_height` — my regression, and my first two
   fixes for it were both wrong.** Shorter stairs at 0.4 left more rooms raised, and seed 30's
   spawn zone ended up across a full-level ledge. **Fix attempt one read heights from
   `UnitGeometry.true_height_for_cell`** — which answers 0.0 for every cell here, because
   `_mark_zone` runs before `_emit` and `grid.surfaces` is still empty. A filter matching
   everything, and the only thing that caught it was the sweep staying red rather than turning
   green. **Fix attempt two anchored on `room.position`**, which happened to be the single low cell
   beside a raised shelf: the zone collapsed from four cells to one and the three discarded cells
   were the board's only way up, turning a spawn defect into a 95-cell unreachable region. The
   third attempt keeps the block's **majority** level. **The lesson is that a filter which passes
   everything and a filter that is correct look identical from a green test** — only the red one
   told me anything.

Two further self-inflicted ones worth naming because they cost real time: the burst fixture
authored `Part.burst` where `BurstAction` gates on `WeaponDef.burst_size`; and a test helper called
`apply()` on an illegal action, which under `-d` raises a debugger break that **waits for input and
hangs the whole run** instead of failing it — the helper now returns early.

## `SUPERVISOR`-owned entries moved to `Pending`

**None this block.** Nothing was fixed, so nothing became pending.

Two `SUPERVISOR`-owned entries were closed as **`Obsolete`** under your explicit authorisation over
the owner gate, on the record that you reopen them if you meet the behaviour again:

- **`BR56.01`** (repair ramps stamped at 45°) — the code it describes is deleted. **No generated
  surface carries a facing at all now**, which is what makes it unverifiable rather than fixed.
- **`BR51.12`** (ramps stacked facing opposite ways) — ramps cannot generate at all. Its interesting
  half was answered rather than deleted: the assertion it pointed at really was narrower than its
  name (see item 2 above).

Three entries remain `Pending` from **prior** sessions and still need your eyes — `BR57.01`,
`BR59.01`, `BR59.02`. I did not touch their status; a pending mark from another session is a claim
to re-check, not a closure to trust.

## Open questions

**1. Which step height ships.** 0.3 (12.8% raised ground) or 0.5 (15.8%, matching the old ramps
exactly), or something else. Navigability holds at every value measured. Queued in `PLAN.md` with
the table.

**2. `BR54.01` is not a stale-facing bug, and that narrows it.** `AttackAction` free-faces at its
target before firing, so a queued attack leaves with facing ≈ travel and reads near-zero
`off_facing`. The 43° cannot be the unit pointing the wrong way. This matches `docs/02`'s own
measurement that the aim point is **the frontmost region's centre** — a pistol or a raised arm — 
which swings off-axis as range shrinks without the unit turning at all, reaching 20.1° at one cell.
**Whether the aim point should be that, the body's centroid, or a point on the muzzle-to-target
axis is a design call**, and it is the same question `BR51.01` and `BR52.07` are probably asking.
Pass B's log now carries the number, so taskblock-61 can read it instead of reconstructing it.

**3. `BR60.02` — which side of the render/hitbox disagreement is wrong.** A mangled or disabled part
at 0 hp projects (occludes, hittable) and draws nothing. Either the view should draw what projects
— a mangled limb is *visibly* wrecked, which is what `docs/03`'s mangle state implies, and my
weakly-held preference — or `projects()` is too generous and a mangled part should stop stopping
rounds. **They must not be decided separately.** This is the fourth time one membership question has
had two answers, so it belongs with `PLAN.md`'s *Derive plane/picker membership* item rather than as
a fifth local patch. It is very likely `BR52.06`; confirming needs one observation from you — **is
the invisible leg still hittable?** If it is not, this is not its cause.

**4. `BR60.01` — a navigability invariant that cannot see half the problem.** `MapNavigability` asks
*"can you get out"*, so a raised region you can never get **into** is invisible to it: 12 such
regions across 60 seeds at 40×30, largest 235 cells, reproducing identically before and after this
block. **The sweep that should catch it runs at 32×24, where it does not reproduce, while the bout
board is 40×30** — that mismatch is worth fixing whatever the cause turns out to be. Suspected but
unconfirmed: `_repair_stranded_elevation` floods from `rooms[0]`'s centre, which may sit inside the
region it is meant to be judging.

**5. `BR51.24` points two ways and needs a rule, not a fix.** `docs/09` C2 says a destroyed part
never detaches, and `BodyProjector` honours that. So the model may be right and inspect wrong. The
entry says the same; nobody has decided.
