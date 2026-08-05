# Taskblock 58 Report — Faces, locations, one answerer, and the editor's real tools

**Passes A, B, C and C.2 landed, in order; D, E and F are not started.** All four are on `master`
and the suite is green. C was reviewed on a branch and merged on the supervisor's call; C.2 is the
addendum written after that review, which merges C, takes the wall-clock budget out of
`test_ai_batch_yield`, and files the pacer defect as its own `PLAN.md` item rather than building it.

**Two measurements are in play and they are not the same number.** Per-turn planning cost rose
**1.38x** (412 ms -> 569 ms, twelve steps at seed 4242); whole-suite cost rose **1.13x** (682 s ->
770 s). The addendum's own framing reads the 1.13x as replacing the 1.38x — it does not. What 1.13x
replaced was a wrong 2.2x of mine; the 1.38x planning figure was taken after the optimisations and
stands. Both are true of the same code.

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

**Pass C was committed to a branch rather than to `master`, and its failing test left failing for
review.** The cheap alternative was making `test_ai_batch_yield` compare like with like, which
closes the red at no cost and hides that the AI searches less on real hardware. **The supervisor
took a third option in C.2** — raise the budget out of the test *and* record the defect as its own
item — which gets the test back to testing yielding without the regression going unrecorded.
Raising `DEFAULT_BUDGET_MSEC` itself stayed rejected throughout: it is flagged in its own comment as
a guarantee rather than a balance figure, and it would hide the machine-dependence rather than fix
it.

**Pass C.2: `ControlOverlay` grew two fields so a test could stop measuring the wrong thing.**
`pacer_budget_msec` and `last_pacer`. The addendum asked for the budget to be raised in the test and
for a companion assertion that the raise was genuinely enough — neither was reachable, because
`advance_ai_turns` builds its pacer internally. The view owns the pacer (only something in a tree
can supply a frame signal), so the view owning its budget follows, and `last_pacer` has the same
diagnostics-only standing `PlanPacer.aborted` already has. Production sets neither. **The
alternative was making `DEFAULT_BUDGET_MSEC` a `static var`**, which would have let any caller
mutate a guarantee that is meant to be one.

**Ten minutes as the raised budget.** Far past any turn, so if it is ever reached that is a real
defect rather than a slow machine — which is what the companion assertion is for.

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

**Pass C.2's instruction extended to a second site the addendum did not name.**
`test_watched_run.gd`'s watched-vs-headless comparison has the identical shape — a pacer'd run
against a corpus record played with none — and it was **flaky rather than red**: green in isolation,
failing under full-suite load at 39 turns against 67. The addendum's reasoning is general ("refusing
to let one test carry two claims"), so I applied it there too rather than leaving a known flake
behind. Recorded in `BR58.01`. **The flaky one is the more alarming of the two**, because a test
that fails only when the machine is busy reads as noise rather than as a finding.

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

**1. The pacer — answered, and filed rather than built.** The supervisor's call: merge C, take the
budget out of `test_ai_batch_yield`, and make the pacer its own item. It is in `PLAN.md` now with
the direction (pace on candidates, keep wall-clock as a pathological backstop) and with the cap
named as a measurement rather than a value. `BR58.01` stays `Active`. **The one thing that item
cannot state is its own size** — every seeded bout that completes headlessly today may begin
aborting mid-plan once the counter runs unconditionally, and that churn cannot be sized without
running it. Sizing it is the item's first task, which is written down there.

**2. `LoS.SIGHT_HEIGHT` is `UnitGeometry.DEFAULT_MUZZLE_HEIGHT`, flagged not designed.** A sight line
and a shot line wanting the same height is the honest default, and every production caller of
`has_los` is gating or scoring a shot — but inventing a separately-named eye constant would have been
a balance number presented as design. The real answer is a per-shell sensor height.

**3. Does `LoS.has_los` at 152 usec want a spatial index?** It was 3.8 usec as an array lookup and is
two orders dearer as a real march, already optimised from 999. The remaining cost is that every query
walks every blocker and every placement. `SightSpans` is the structure that would fix it, but making
`has_los` read it means caching the derivation somewhere that can notice a wall losing its last hit
point — and a stale span table is a shot through a wall. Left unbuilt deliberately.
