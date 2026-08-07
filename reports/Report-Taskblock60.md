# Taskblock 60 Report — prep for the bug hunt: delete two, instrument four, dissolve seven

All four passes landed in order. **A retired ramps and introduced `step_height`; B gave all seven
firing paths an announcement; C stopped and reported rather than building, because its premise did
not hold; D sorted the ledger.** **Full gate green: 341 scripts, 3345 tests, 0 failures.**
**No bug was fixed**, which is the block's own rule. The ledger went from 46 open to 46
open — two closed as `Obsolete`, two new ones filed from measurements taken along the way.

## Decisions made without asking

**`BASE_STEP_HEIGHT` is 0.3, and I shipped it rather than asking first.** It is the stair riser the
design names — *"a ramp becomes two ordinary tiles at 0.3 and 0.6"* — so it is the stated default
rather than an invented balance number, which is the branch `CLAUDE.md`'s ask-don't-invent rule
points at. The alternative was 0.5, and it is not neutral: measured over eight seeds at 40×30,
**0.3 gives 12.8% raised ground and 0.5 gives 15.8%, against the old ramps' 15.8%**, because a
flight is `ceil(rise / step_height)` steps and a longer flight fits fewer places. **Navigability is
0 stranded cells at every value measured**, so this is feel, not correctness. It is queued in
`PLAN.md` with the table as a decision for you; the generator derives everything from the one
number, so changing it is a one-line edit.

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

## Tests that failed, then were corrected

**Nine failing before correction, across five files.** Four of the five were fixtures holding an
assumption the pass deliberately reversed, which is the useful kind.

1. **`test_continuous_height_and_escapes.gd` — the most important one.** It pinned *"a 0.3 rise is
   pathable at the rounded-up partial climb cost"* and *"a non-climber still cannot cross it"*, and
   its own comment recorded that **taskblock-54 tried a free-step threshold and rejected it** as
   contradicting `PLAN.md`'s settled *partial MP costs round up*. So this pass re-introduces a
   previously rejected idea. Corrected by reversing both pins and recording the reversal in
   `SUPERSEDED.md` with the distinction that makes it right this time: step height is not a
   discount on climbing, it is the boundary between walking and climbing, and round-up still
   governs everything above it. A fresh assertion pins that a 0.4 rise still rounds up.

2. **`test_map_gen.gd::..._at_most_one_correctly_typed_floor_surface` — the assertion was counting
   the wrong thing all along.** It counted *every* surface at a cell, not every walkable one. A
   ladder is a placed surface too, so a repair ladder sharing a cell with its floor failed it — but
   only once ladders became the only repair. `BR51.12`'s own note predicted exactly this
   ("if that test passes while this reproduces, the assertion is narrower than its name").

3. **`test_map_gen.gd::..._every_raised_area_is_ramp_reachable` — six failures, and none was
   elevation becoming unreachable.** `_raised_regions` counted cells carrying a live blocker as
   raised ground; a blocker cell is unreachable by construction and no unit could stand there. The
   caller's own doc already excused this in prose and the code never implemented it. Measured
   before changing it: the old generator produced **zero** such regions at that board size and the
   new one produces **six, every one exactly one cell with exactly one blocker.**

4. **`test_pathfinder.gd` — four failures, all fixtures asserting ramp privilege.** Rewritten as
   step-height and stair claims. One became the inversion that states the whole pass: a ramp-tagged
   surface now buys no traversal the geometry did not earn, asserted against a plain floor at the
   same height behaving identically.

5. **`test_every_firing_path_announces_itself.gd` — my own fixture was wrong, and finding out was
   worth more than the test.** It set a shooter 90° off its target and asserted the announcement
   would record that. It went red because **`AttackAction.apply` free-faces the shooter at the
   target before firing.** See Open questions.

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
