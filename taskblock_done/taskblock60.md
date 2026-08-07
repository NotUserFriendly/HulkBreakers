# Taskblock 60 — Prep: delete two, instrument four, dissolve seven

*Precedes taskblock-61's bug hunt. Closes `PLAN.md`'s *Retire ramps; introduce `step_height`*, *Every
way of firing announces itself*, and *Player view and sim view*.*

**The ledger holds 44 live entries and three clusters a hunt cannot productively chase in their current
state.** Each has a PLAN item that changes the situation, and each changes it a different way — by
deletion, by instrument, by dissolving a class. **None of the three is a bug fix**, and that is the
point: a hunt that opens against the current ledger spends its first day on entries that were about to
evaporate, or guessing at four shot bugs it cannot read.

**No bug is fixed in this block.** Pass D triages; taskblock-61 hunts.

---

# PASS A — Retire ramps; introduce `step_height`

**Two entries close as `Obsolete` for free**: `BR56.01` (repair ramps stamped facing 45 degrees across
their own cell) and `BR51.12` (ramps generating over ramps facing the other way). Both describe a
subsystem this pass deletes, and **fixing a facing bug in code that is about to go is the expensive
order.**

**`step_height` does not exist, and that is the work.** `MAX_CLIMB_LEVELS` is 1.0 and
**capability-gated** — a non-climber cannot go up at all without a ramp or ladder, so a 0.3 tile is not
walkable-onto by anything in the game. Introducing a free step height is what makes stairs work, and
that one number replaces five separate checks:

| today | under `step_height` |
|---|---|
| `is_ramp_at` in `ClimbAction` — refuse, it is a walk | rise ≤ step height → walk |
| `is_ramp_at` in `HopDownAction` | rise ≤ step height → walk |
| `_is_ramp_surface` in `move_cost` | rise ≤ step height → flat cost |
| `MapGen.RAMP_MAX_RISE` and its generator branch | place tiles at heights |
| `CellKind.RAMP` in `MapGenScratch` | gone |

**Five categorical checks become one continuous comparison**, and it is the better rule: *can this unit
step up that far* rather than *is this thing labelled a ramp*.

**`Surface.facing` never reaches the pathfinder**, so a ramp is already traversable from any direction.
The directionality that would be the strongest argument for keeping ramps is not implemented — which is
also why `BR56.01` is a visual defect on a field nothing reads.

- **Step height becomes a per-unit stat**, which a ramp could never express. **The generator's
  navigability invariant must then run against the lowest step height in play**, not a constant.
- **A cosmetic ramp part is fine** — sloped geometry, no special traversal. If a two-tile stair does not
  read well, the answer is content.
- **The editor's auto-placed terrain places ramps rather than `ship_floor`.** Almost certainly the same
  constant; it retires here.
- **Ramps return later as a real category** — a chassis with no step height at all, needing a continuous
  slope. That is about the chassis, not about a cell being labelled, and it is not this.

**TESTS:** a unit with no climbing capability walks up a rise at or below its step height and not one
above; a generated map passes the asymmetric navigability flood against the *lowest* step height
present; nothing references `is_ramp_at`, `RAMP_MAX_RISE` or `CellKind.RAMP`; the editor's auto-placed
terrain is `ship_floor`.

---

# PASS B — Every way of firing announces itself

**Four shot-geometry entries are currently unreadable**: `BR51.01` (sniper and chaingun shoot wide
left), `BR54.01` (AI rounds up to 43 degrees off facing), `BR52.07` (one burst shot at roughly 90
degrees), `BR52.13` (nothing penetrated across an entire battle).

**`BurstAction` is the only firing path that emits a fire event.** `AttackAction`, `StabAction`,
`SlashAction`, `GrindAction`, `Suppression` and `Overwatch` emit **impacts only** — one of seven paths
announces itself, and a sniper firing is indistinguishable from a sniper idling until something is hit.

**This has already cost real time.** `BR54.01`'s angle table had to be **inferred from impacts**, and
the measurement existed at all only because impacts happen to carry origin and hit points. A hunt
without this investigates four related bugs by reconstruction.

- **A framework the paths tag into, not one more event kind.** The point is that a new way of putting a
  round in the air announces itself **by construction** rather than by whoever adds it remembering to.
  `burst_fired` becomes one member of a vocabulary instead of the exception that happens to have one.
- **`ShotResolution` is the seam.** Six of seven already funnel through `resolve_and_log_point`;
  `Overwatch` reaches `log_impact_result`/`log_miss_result` directly. Put the announcement where they
  already meet, not in each caller.
- **Carry what the four entries need:** the origin, the intended direction, the unit's own facing, and
  the weapon. `BR54.01` is the angle between facing and travel; without facing in the event it is
  inferred again.
- **Decide the melee vocabulary once.** A stab resolves through the same path but *fired* is the wrong
  word, so the term is probably neutral with the weapon's method as data.

**TESTS:** every firing path emits an announcement (**enumerate the paths in the test, so an eighth
path fails until it tags in** — that is the by-construction claim); the event carries origin, direction,
facing and weapon; a shot that hits nothing still announces.

---

# PASS C — The view draws a snapshot

**Seven entries are one root:** `BR30.02` (debug `move_object` mutates state, model never moves),
`BR51.24` (part destroyed by explosion leaves inspect but stays on the model), `BR52.06` (a leg appears
to have no model), `BR52.09` (destroyed cover's model stays), `BR54.02` (a part vanishes before the
tracer that destroyed it plays), `BR57.01` (units at the previous bout's cells), `BR59.02` (`Delete`
removes the record, not the mesh).

**All of them are the model and the view disagreeing about what exists**, because the view is refreshed
by explicit calls and some paths do not call. **taskblock-59 fixed exactly this shape twice inside the
editor** — a translate branch that redrew handles and never called `refresh()`, and a delete that
removed the record and left the mesh. The same defect, in the same week, in a different surface.

**The view draws from the last resolved state**; the sim works on its own copy; the view swaps and
animates when the work completes.

- **`refresh_unit_views(touched_ids)` is already the explicit sync point** and `dup()` already exists,
  so the seams are present rather than needing invention.
- **It also answers `BR54.02` and `BR27.07` properly.** A view drawing the last *played* state cannot
  show a part removed by a shot that has not been drawn, and cannot highlight a turn whose animation has
  not played. Those are the same bug at two clocks.
- **This is the pass most likely to be too large.** If it is, **stop and report** — the hunt inheriting
  seven entries *knowing they are one thing* is a far better position than today's, and a half-built
  snapshot split is worse than none.

**TESTS:** a state mutation with no redraw call leaves the view correct on the next frame (**the
property, since "someone forgot to call refresh" is the class**); a destroyed part leaves the model when
its impact plays, not when the action resolves; a new bout draws no unit from the previous one; the
editor's delete removes record and mesh together; a seeded bout is byte-identical.

---

# PASS D — Triage what is left, and name the deep ones

**No fixes.** Group the remainder by shared cause and mark what A–C closed, so taskblock-61 opens
against a sorted list rather than a chronological one.

**Mark the deep-investigation entries explicitly.** These are the ones that will eat a hunt if they are
picked up casually, and knowing which they are before starting is worth more than an hour during:

- **`BR51.01` / `BR54.01` / `BR52.07`** — shot geometry. Pass B makes them readable; they are still
  three symptoms that may be one cause and may be three. **Read the new log before forming a theory.**
- **`BR32.04` / `BR32.05` / `BR32.08`** — the wall cutout. `BR32.05` needs a real ray test in the
  shader, which was a rewrite when it was filed. **`RayCaster` and `PartPicker`'s struck-point reporting
  now exist**, so it is materially cheaper than the entry suggests — worth re-reading before deferring
  it again.
- **`BR52.12` / `BR52.15`** — overwatch. `BR52.12`'s own finding is that overwatch fires only on
  movement and nothing moved, which points at the AI rather than at overwatch. **Confirm which before
  either is worked.**
- **`BR55.01`** — intermittent engine abort in `LoS.has_los`. Intermittent plus engine-level plus
  taskblock-58 having rewritten what `LoS` consults; **re-verify it still reproduces before hunting
  it.**
- **`BR52.14`** — `test_suite_run.gd` intermittent in the full gate, passing targeted. Test
  infrastructure, not game behaviour, and it will waste a hunt.

**The framerate entries are not hunted.** The ledger header now records the release bar (120 at 4K) and
the working tolerance (1% low above 40, no frame over ~100 ms), and states that these entries sit
deliberately. **Do not re-triage them**; that is what writing it down was for.

**TESTS:** none. This pass produces a sorted ledger and a report section.

---

# When to stop and report

- **Pass C outgrows the block.** Report the seven-as-one finding and stop; do not half-build it.
- **Pass A's `step_height` changes generated maps' navigability.** The invariant runs against the lowest
  step height in play, and if that fails on existing seeds it is a finding.
- **Pass B turns up the cause of `BR51.01`.** Append it and stop — fixing it is taskblock-61's.

# Acceptance

- `BR56.01` and `BR51.12` are `Obsolete`, and nothing references the ramp subsystem.
- Every firing path announces itself, and a test fails if an eighth does not.
- Either the snapshot split lands, or the seven-entry class is documented as one root with a reason it
  did not.
- The ledger is grouped by cause, with the deep-investigation entries named.

# Not this block's job

- **Fixing any bug.** taskblock-61.
- **Framerate.** The bar and the tolerance are recorded; the entries sit.
- **`BR58.01`'s candidate budget.** Its own item; it reads as performance and is determinism.
- **The editor's remaining gestures.** Its own item and not hunt-blocking.
