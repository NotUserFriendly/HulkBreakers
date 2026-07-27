# Taskblock 42 Report — Bug hunt: the hitch, then a batch

**Partial and deliberately open.** Passes A–E landed in order, each committed separately, suite green
throughout — 2218/2218. Passes **F and G are not started**: the supervisor released E early, then
halted the rest until the hitch is at least minimized. `taskblock42.md` stays in the tree.

**The block's real result is a diagnosis, not a fix.** Costs #1–#3 are measured and cut; the hitch is
not, and Pass D established why.

| cost | before | after |
|---|---|---|
| #2 `HitVolumeView.refresh()`, move path | 858µs | **351µs** (2.4×) |
| #2, orientation preview (BR26.02's aim path) | 795µs | **267µs** (3.0×) |
| #3 turn-start power block | 118µs | **40µs** (3.0×) |
| **#4 one `BoutRunner.step()`** | **~1672ms** | **~1672ms — untouched** |

A–C together are **under 1% of a single AI step**. 24 steps of a real 3v3 bout is 40.1 seconds of
pure planning. The several-second hitch is *one* `UnitAI.plan_turn` call
(`src/logic/ai/unit_ai.gd:152`), not an accumulation of small ones, so yielding around it buys one
responsive frame every ~1.7s and fixes nothing. That is the whole bug now, and it wants an
algorithmic pass rather than another sweep.

## Decisions made without asking

- **Pass A: the boundary dump is emitted synchronously, with no `await`.** `create_timer(0.0)` or
  `process_frame` would push it a frame past the boundary — precisely the transient it exists to
  catch — and quietly make it a second copy of the settled sample under a different label. There is a
  test asserting it lands before anything yields. `data.context` also changed from the old ambiguous
  `"turn"` to `turn_boundary`/`turn_settled`, since there are two turn dumps now; a grep written
  against the old value will stop matching.
- **Pass B: the cheap refresh REFUSES rather than guesses.** It compares a signature of everything the
  node *set* depends on and returns false on any difference, so the caller falls back to a full
  rebuild. The alternative — enumerate the cases where reuse is safe — is the shape that produces a
  view which silently stops updating in a case nobody thought of.
- **Pass C: explicit threading, not a per-turn cache.** The pass said "cached for the turn"; a cache
  needs invalidating on every structural change to the part tree, and a stale power reading is a
  silent wrong number rather than a crash. Threading a pre-walked list has no state to go stale, so
  the "cache invalidates on any structural change" acceptance is met by there being nothing to
  invalidate.
- **Pass C: reported as not worth much, rather than presented as a win.** 118µs → 40µs is real and
  will not be felt. The pass explicitly allowed stopping if the cost was small next to B and D; I did
  the work (it was already written and is low-risk) but the number is recorded plainly on BR27.09
  rather than dressed up.
- **Pass D's coalescing fork, decided before coding as required: refresh only the units THAT step
  touched, after that step.** Neither of the two options the taskblock named — not "no refresh until
  the end" (a frozen but interactive board), not "whole board per step" (undoing tb19 Pass I2's
  measured finding). I2's waste was refreshing every unit repeatedly; this is proportional to what
  changed, usually one unit, and Pass B made each 2.4× cheaper.
- **Pass D: reported as not fixing the bug it was aimed at.** The yield delivers real things —
  input stays alive, each unit's move is visible as it happens instead of the opposing team
  teleporting — but the hitch survives, and the measurement says it always would have.
- **Pass E: fixed a defect that was not on the list.** `BoutInjector._move_unit` set `unit.cell` but
  never re-derived `unit.height`/`level`, which `CombatState.add_unit` and `MoveAction` both do. A
  debug move onto a raised cell left the unit rendering at its old elevation. **This is not a fix for
  `BR30.02`** — that entry's symptom is the model not moving at all, which still does not reproduce —
  and I have said so on the entry rather than let the adjacency imply a closure.
- **Pass E: `BR35.01` deliberately skipped.** `PartPicker.hit` still scans every blocker and field
  item per call. Named on the entry rather than quietly dropped.
- **No `fps_dump` before/after per pass.** Pass A built the instrument; capturing 0ms/2000ms numbers
  per pass needs three real-GPU runs against three reverted builds. The taskblock has the supervisor
  measuring on a clean build at the pause, so the direct µs figures above are what CC produced.
  Flagged at the pause; the supervisor did not ask for the dump comparison instead.

## Tests that failed, then were corrected

Four, all caught before commit. Three are the useful kind — the test was wrong, not the code.

1. **Pass B's equivalence test** (~30 assertions failing). It compared the two views' children by
   index, and rebuilding the ground markers appended them to the *end* of the child list, so a cheap
   refresh and a full rebuild held the same nodes in different tree order. Nothing rendered
   differently — every child is world-space — but "identical to a full rebuild" is the entire safety
   claim of the pass, so I fixed the code with `move_child` rather than weakening the assertion.
2. **Pass C's structural-change test.** I asserted `mp_per_ap` would change when non-root parts are
   destroyed; the reference humanoid's agility does not come from those parts. Premise wrong, code
   fine — rewritten to assert the real property, that the operable list shrinks immediately with
   nothing remembered.
3. **Pass E's verb-list test** (2 failing). It caught my own error: `BOARD_CHANGING_VERBS` listed
   `place_cover`/`clear_cover`, which are **not** panel verbs — the panel exposes
   `spawn_object`/`remove_object`, which front both. They matched nothing, so the classification
   silently did less than it claimed. This is the third time this session a hand-written list of names
   has been wrong in a way only a cross-check against the real registry caught.
4. **Pass E's test file had no `extends GutTest`.** `test_debug_verbs.gd` did not exist and my append
   created it headerless. GUT reported it as an unhelpful parse failure rather than naming the cause.

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** `BR27.09` and `BR26.02` both gained measurements and stay `Active`, as the taskblock
required. `BR35.03` moved to `Pending` but is `CC`-owned, not `SUPERVISOR`-owned.

## Open questions

- **The hitch is now one number in one function.** `UnitAI.plan_turn` at ~1672ms/step: per-candidate
  pathfinding, LOS and cover scoring across ~96 reachable cells. tb35 Pass A3 halved it once
  (2023ms → 974ms) by removing duplicate `ShotPlane` resolution and named the remainder as real
  per-cell geometry; it has grown back. The options are roughly: cap or tier the candidate set,
  cache geometry across candidates within a turn, or move planning off the main thread. That is a
  design call, not a sweep, and it gates Passes F and G.
- **Whether Pass D's yield is worth keeping on its own merits** if the planning cost is fixed
  another way. It costs nothing and makes the batch interruptible, but it was justified as a hitch
  fix and is not one.
- **`BR26.02`'s aiming path has one number and needs the rest.** 795µs → 267µs per orientation change
  is one cost on that path; nobody has measured what else is on it, and the supervisor has already
  said aiming is tolerable.
