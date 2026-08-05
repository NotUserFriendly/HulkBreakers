# Taskblock 58 Report — Faces, locations, one answerer, and the editor's real tools

**Passes A, B and C landed, in order; D, E and F are not started.** A and B are on `master` and
green. **C is on branch `tb58-pass-c` and is not merged**: it is functionally complete and every
sight, cover, overwatch, field, picker and map test passes, but it raised per-turn planning cost by
1.38x, which trips `PlanPacer`'s 400 ms wall-clock budget and makes a viewed bout stop matching a
headless one — `test_ai_batch_yield` goes red as a result, and it is the block's only red test
(branch: 3156 of 3157, 770 s; `master` at Pass B: 3149 of 3149, 682 s). That is left red and reported
(`BR58.01`) rather than tuned away, and it is the decision this report most needs.

**The taskblock's own docs for all three passes are on the branch, not on `master`.** They were
written as one taskblock-58 entry covering A through C, and splitting it so `master` could carry the
A/B half would put two records of the same change in the tree. So `master` currently has A and B's
code with their changelog entries pending the merge. Flagged rather than worked around.

## Decisions made without asking

**`GROUND` means "attaches to nothing", and the one-per-cell refusal survives as occupancy.** The
taskblock named two options and said to pick one. The other — retire `GROUND` in favour of a support
requirement — needs the support graph Pass B explicitly does not build, so every floor on every map
would have been unplaceable. **I also deliberately did not loosen the refusal to "not at this
height"**, which is the change vertical stacking wants and is one line: Pass B is a storage inversion
with no intended behavioural effect, and that would be a behaviour change wearing a refactor's
clothes. Queued in `PLAN.md`, and pinned by a named test so the loosening has to be deliberate.

**`Overwatch`'s `LoS.has_los` gate is deleted, which changes play.** With sight geometric,
full-height cover correctly blocks the cell-to-cell line — and then vetoed `_torso_visible`, which
asks the same question more precisely from the real muzzle against the real body, and which is what
lets a leaning striker be seen past that cover. The alternative was keeping the gate and accepting
that leaning past full-height cover can no longer trigger overwatch, which would have quietly
deleted a mechanic taskblock-25 built. **This is the largest unilateral gameplay call in the block.**

**Cover blocks sight now, and two fixtures had to stop pretending otherwise.** *"Every 3D volume
blocks sight"* means a crate at eye height is in the way for the same reason a wall is. That reverses
`LoS`'s own opening line. `test_melee_delivery.gd` used a 2.0-tall blocker as "cover" and
`test_batch_objective.gd` placed a full `wall` Part and relied on leaving the opacity flag unset —
both now author cover you can genuinely see over. Recorded in `SUPERSEDED.md`.

**The field is built from geometry rather than cast per query, and the derived structure is weaker
than the march.** `PLAN.md` asked for the cost first and it decided this: asking `LoS.has_los` per
cell measured **535 ms per field build** and was rejected on the spot. `SightSpans` reduces every
blocker, surface and field item to the vertical spans it occupies over the cells it **fully** covers
— so a prop straddling two cells occupies neither. That is deliberate under-reporting, because the
field's standing obligation is never to report "no line" where one exists. Swept on a real board, the
whole gap between it and the march is scatter pillars. The containment is asserted rather than
argued.

**`VisibilityField` keeps over-inclusion 3 even though the data no longer forces it.** A cell at
another elevation is still reported visible wholesale. The occluder test could answer across bands
now; what stops it is that the field casts eye-to-eye while a shot runs muzzle-to-aim-point. Removing
the margin trades the one failure mode that matters for casts on a once-per-turn build. Left as a
deliberate safety margin, with the retirement condition written down.

**`Cover.is_covered_from` takes the field as a required argument, not an optional one.** An optional
field means two branches deciding the same thing differently depending on what the caller happened to
be holding, which is the arrangement the pass exists to delete. Every caller either already held a
field for that threat or builds one and reuses it.

**`RayCaster.obstructed` is an any-hit loop, separate from the nearest-hit march.** A second
traversal, deliberately — not a second geometry model: the reject, the slab test and the placement
enumeration are the identical calls. Taken for cost (999 -> 152 usec) and justified by the fact that
a nearest hit exists exactly when any hit does. A sweep asserts the two agree rather than leaving
that in a comment.

**`LoS.obstruction_count` deleted.** A second visibility formula with no caller anywhere in `src/`,
whose own comment named a consumer that had already been retired.

**Pass C committed to a branch rather than to `master`, and the failing test left failing.** The
cheap alternative was making `test_ai_batch_yield` compare like with like — both paths budgeted or
neither — which closes the red today and costs nothing. It also hides that the AI searches less on
real hardware, so I did not take it. Raising `DEFAULT_BUDGET_MSEC` was rejected for the same reason:
it is flagged in its own comment as a guarantee rather than a balance figure.

## Tests that failed, then were corrected

**Six failing before correction across two gates**, four of them the useful kind — the change was
right and the fixture held an assumption that had stopped being true.

1. **`test_melee_delivery.gd` (2 tests).** A lean past cover stopped triggering overwatch. The
   fixture's own comment said its blocker was *"full torso height... so exposure here can only be
   about DEPTH ordering, never about peeking over a short wall"* — which was only reachable while
   cover did not block sight. **Root cause was not the fixture**: it exposed `Overwatch` gating a
   coarse cell line in front of a precise body-accurate one. Fixed by deleting the gate.
2. **`test_batch_objective.gd`.** Every batch objective started planning the identical turn, which
   that test exists to catch. The fixture placed a `wall` Part as "cover" and documented that it
   left opacity alone so the enemy stayed visible to a restricted view. With sight geometric a
   2.4-tall wall blocks, the enemy vanished, and there was nothing left to plan against. The fixture
   now authors a crate shorter than `LoS.SIGHT_HEIGHT`.
3. **`test_watched_run.gd`.** Failed on the full gate only. `Cover.is_covered_from` was calling
   `units_visible_to` **once per intermediate cell of its line**, recomputing the same set every
   step — wasteful when a restricted view answered it with an array lookup per unit, and expensive
   once it answered with a real sight line. Hoisted out of the loop.
4. **`test_void_vocabulary_guard.gd`.** I used a retired word in a new doc comment. Reworded.
5. **`test_ai_batch_yield.gd` — not corrected, still red.** See below.

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** Two `SUPERVISOR`-owned entries got dated notes and no status change: `BR35.02` and
`BR32.05` both name *"a real ray/line-of-sight check"* as the fix they need, and that primitive now
exists (`RayCaster.obstructed` / `cast_geometry`). Nothing calls it from either path and neither bug
is fixed — the notes exist so the next attempt does not re-derive the check.

## Open questions

**0. A number I reported during the block turned out to be wrong, and it mattered.** Mid-block I
put the whole-suite cost of Pass C at 2.2x. **Both ends of that were bad**: the "before" was
`test/SUITE-PROFILE.md`'s 530 s, a baseline generated at an older commit rather than at Pass B, and
the "after" was a 1178 s run taken *before* the three optimisations that then landed. Re-taken at
the end of the block on the same machine, **`master` at Pass B is 682 s and the branch is 770 s —
1.13x.** The per-turn planning figures below were taken after the optimisations and stand. The
lesson is the one the project already writes down: a measurement that predates the fixes is not a
measurement.

**1. The pacer, which is what blocks the merge.** `PlanPacer` aborts on wall-clock, so a bout driven
through the viewed path stops being reproducible from its seed once planning exceeds the budget —
which contradicts the standing determinism rule. Measured, twelve steps on the bout board at seed
4242: **412 ms mean per turn at Pass B, 569 ms at Pass C, against a 400 ms budget.** The budget was
therefore already being exceeded before this block; C is what walked it off the edge.

Options, and where the evidence points:

- **Pace on candidates instead of milliseconds.** The counter already exists — `note_candidate()` is
  called once per scored candidate at both sites, and `should_abort()` is already called immediately
  before each, so neither call site changes. Roughly fifteen lines in `plan_pacer.gd` plus six tests
  that set `budget_msec`. **The subtlety is the point of it**: `note_candidate()` returns early
  headless today, so a deterministic budget must count unconditionally — which means headless bouts
  start aborting too, and that is exactly what makes the two paths agree again. It is also a real
  behaviour change, and I cannot size the golden churn without running it. **This is where the
  evidence points**, and the cap value is balance-adjacent, so it wants a measured distribution
  rather than a number I invent. The suite's own counters give a ~900 candidates/turn mean over
  1,063 turns; a mean is not a cap.
- **Keep wall-clock as a backstop alongside it.** Then determinism holds only until the backstop
  fires — the window narrows rather than closing.
- **Drop the time stop entirely.** A pathological board then freezes the view for as long as the
  work takes, which is the precise failure `PlanPacer` was built to prevent. The trade is that a slow
  machine stops thinking *worse* and starts freezing *longer*.
- **Leave the pacer alone and change the test.** Unblocks D-F immediately at the cost of hiding the
  regression. Reasonable if you want the editor work now and the pacer as its own item; I would note
  it in `BR58.01` rather than quietly rewriting the test.

**2. `LoS.SIGHT_HEIGHT` is `UnitGeometry.DEFAULT_MUZZLE_HEIGHT`, flagged not designed.** A sight line
and a shot line wanting the same height is the honest default, and every production caller of
`has_los` is gating or scoring a shot — but inventing a separately-named eye constant would have been
a balance number presented as design. The real answer is a per-shell sensor height.

**3. Does `LoS.has_los` at 152 usec want a spatial index?** It was 3.8 usec as an array lookup and is
two orders dearer as a real march, already optimised from 999. The remaining cost is that every query
walks every blocker and every placement. `SightSpans` is the structure that would fix it, but making
`has_los` read it means caching the derivation somewhere that can notice a wall losing its last hit
point — and a stale span table is a shot through a wall. Left unbuilt deliberately.
