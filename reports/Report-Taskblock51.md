# Taskblock 51 Report — The bug hunt, and one bug that was four

**Passes A and B partially landed; the framerate deep-dive took the block.** Suite green — 2497 tests,
~302 s. **`BR26.02` is paused by supervisor decision while it is "decent", not closed.**

Four supervisor hunting sessions. **Ledger 31 → 40 open**, which is the honest shape of a hunt: five
entries closed, fourteen filed, several re-diagnosed.

## Decisions made without asking

- **`BR26.02` was worked far past its share of the block, and that was the right call** — the
  supervisor confirmed it mid-block ("this fps issue is flagrant, and needs this deep dive") but the
  first three passes on it were mine. It blocked every other aim-related entry: `BR51.01`, `BR34.04`
  and `BR33.01` all need the aim view, and none can be judged through a slideshow.

- **`update_aim_hover`'s hover check now early-outs when the hovered part is unchanged.** Not asked
  for, and a behaviour change: a listener that expected a signal per motion now gets one per *change*.
  Nothing depended on the old rate, and a signal firing on every motion regardless is one every
  listener has to defend itself against.

- **The reticle is coalesced to one update per drawn frame.** This drops intermediate cursor positions
  — safe only because the reticle is an absolute raycast through the literal cursor rather than an
  accumulated delta. **That property is now asserted in a test**, because if it ever became relative
  this optimisation would start silently losing mouse movement.

- **`CombatState.dups` was added as a profiled work counter.** A 26 ms call reached several times per
  mouse motion was invisible to every budget because nothing counted it. The suite now reports ~7 155
  clones a run — a number worth its own look later.

- **Three duplicate entries I filed were folded back** into `BR26.02`, `BR34.05` and `BR48.01`. I
  transcribed from the supervisor's notes straight into the ledger without reading the ledger first;
  36 open entries is more than fits in one head and I did not check. **Nothing was closed by the
  merges** — the bugs stayed open under their original IDs.

- **`BR27.04` was closed on the owner's instruction**, and recorded as owner-directed rather than
  CC-verified: they re-checked, did not see it, and judged it a misfile.

- **The two pairs flagged as possible duplicates — `BR27.07`/`BR32.09` and `BR35.04`/`BR35.07` — were
  left unmerged** on the supervisor's explicit instruction.

## The framerate bug was four bugs wearing one symptom

Measured through a real `SquadControlOverlay` on a 214-blocker board, per mouse motion:

| | usec |
|---|---|
| at the start of the block | **113 504** (8.8 fps) |
| after all four fixes | **8 878** (113 fps) |

1. **`aim_state()` rebuilt the shot plane and cloned the state on every call** — 35 258 usec, twice per
   motion. Memoised on what the plane actually depends on, and deliberately **not** on
   `reticle_offset`.
2. **The memo's own key cloned the state.** It asked `previewed_unit()` for the previewed cell, which
   previews, which is a `CombatState.dup` at **26 083 usec** — reintroducing exactly the cost it
   existed to remove. Replaced with `ActionQueue.revision`.
3. **`update_aim_hover` still emitted `aim_changed`**, which `SquadControlOverlay._on_selection_changed`
   listens to, and which previews twice. My own earlier signal split had converted three emit sites and
   missed the one that runs on every motion — and which `aim_reticle_at_screen` calls internally, so
   both paths still reached it.
4. **The reticle ran once per motion *event*, not per frame.** A 500–1000 Hz mouse against a 60–160 fps
   game meant the queue backed up and the reticle drew positions from several events ago. That is the
   supervisor's *"the dartboard almost seems to lazily follow the cursor"* — latency, not framerate,
   and a different bug from the three above it.

**Two caches were tried and reverted**, recorded in `SelectionController.previewed_unit()` so they are
not retried blind: an empty-queue fast path (callers mutate the previewed unit — `StepOutPlanner` does
— so handing back the live unit corrupted the real board), and a per-frame memo (state changes *within*
a frame when a resolution spends AP).

**Side effect, measured: `BR27.09` improved** — turn-start FPS went **38.0 → 91–147** across later
sessions. Not closed; it was never investigated and a hitch remains.

## Tests that failed, then were corrected

1. **I closed `BR51.02` on a test I wrote against a dict I invented.** `set_part_hp` was fixed for a
   hand-built `{kind: CELL, …}` target and never once driven through the click that produces the real
   one — which is `kind: PART`. The supervisor found it broken immediately. **A test that constructs
   its own input cannot tell you the caller never produces it**, which is taskblock-48's "input tidier
   than reality" arriving from a new direction. It has a test on the real click shape now.
2. **My own bisection tool walked into the trap it documents.** Converting the map-gen sweeps to
   `MapCorpus.read()` silently included two tests that compare *two independent generations of one
   seed* — through a cache they receive the same object twice and pass unconditionally, deleting the
   suite's only check that generation is reproducible. Caught by reading the diff, not by a test; there
   is a test now.
3. **A companion assertion was green by vacuity inside the test written to prevent vacuity.**
   `test_the_planner_counter_would_notice_if_it_did_plan` handed one squad to the AI, but
   `BoutRunner.step()` no-ops while the *current* unit is human — and it was.
4. **The `BR51.04` fix moved the symptom rather than removing it.** Killing the current unit now
   advances the turn, but nothing told the selection to let go, so the dead unit's movement overlay
   lingered. Filed as `BR51.09`, mine.
5. **Widening `set_part_hp`'s target dropped `hp` from the command log**, breaking the pairing
   `test_command_log.gd` requires — the log has to reconstruct the call, and I had removed an argument
   from it while adding one.

## `SUPERVISOR`-owned entries moved to `Pending`

- **`BR26.02`** — the aim framerate. Per-motion cost 113 504 → 8 878 usec, confirmed live by the
  supervisor's own dumps (2 s samples 8 → 116/160). **Paused, not closed, at their instruction.** The
  session minimum of ~7.5 survives and now has a named lead: `BR51.15`.

## Open questions

- **The ~7.5 fps session minimum is one stall, not a load**, and the supervisor has located it: *"a
  distinct hitch right as the over the shoulder camera gets behind the unit"*. Filed as `BR51.15`. That
  is a far better lead than a stray stall and is where this resumes.

- **Averages are the wrong statistic and this block proved it.** One session read `min 7.5, avg 140.1`
  — and the supervisor notes the averages are further tainted by alt-tabbing while observing. Their
  proposed performance suite (1% lows, average excluding the top 1%, a "reporting 85% of frames" line)
  is in `PLAN.md` and would have shortened this hunt considerably.

- **`BR51.13` contradicts a passing test.** `test_log_fold.gd` asserts a diagnostic is never folded into
  plumbing, and `fps_dump` is being folded into `wall_cutout` runs in every log this block. Read the
  test before the code: a green assertion beside a live defect means the assertion is narrower than its
  name.

- **`BR51.14` is very likely `BR26.02` on the non-aim path** — hovering tiles with a unit selected drops
  160 to ~20, motion only. The two fixes that worked should transfer, but it wants its own measurement
  first rather than an assumed diagnosis.

- **`BR51.01` (shots land left) is still unexplained and untouched since its frame theory was
  disproved.** The reticle and resolver were measured to agree to 0.0000 cells across four geometries,
  so the remaining suspects are camera-side. The supervisor suggested moving the camera to the left to
  test; that experiment is still available and now affordable at 113 fps.
