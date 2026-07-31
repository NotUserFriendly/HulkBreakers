# Taskblock 51 Report — The bug hunt, and one bug that was four

**Passes A and B partially landed; the framerate deep-dive took the block, then the addendum's perf
suite, then both addendum passes.** Suite green — **2582 tests, ~309 s**. **`BR26.02` is paused by supervisor decision while it is "decent", not closed.**

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

## Design changes I filed as bugs

The supervisor's rule is that design changes live in the report and their notes until review, not in
`BUGS.md`. One entry broke it and two more are worth flagging.

- **`BR51.02` was half a feature request.** "`set_part_hp` should accept targets that are not unit
  parts" is a capability that never existed, and the entry said so in its own text — *"a tooling gap,
  not a game defect"* — while sitting in the ledger anyway. **The widening landed**: the verb now takes
  the same `{kind, unit, cell}` object target `move_object` already used, an empty `part_id` means the
  blocker itself, and a bare `Unit` still works unchanged. The entry has been restated to cover only
  the genuine defect underneath it — that cover cannot be made the panel's active target at all — which
  Pass K subsumes.
- **`BR51.06` was withdrawn from the ledger by the supervisor as a design change**, not a defect: the
  debug panel's `pick` button also setting the active target is a behaviour to decide on, not a fault to
  repair, and *"if they do the same thing, pick should likely be removed"* is a design call. It lives
  here and in the supervisor's notes until review. **Not acted on.**
- **`BR51.10` was a real defect with a design-change remedy.** Inspect being live when
  nothing is selected is an affordance that lies whichever way it is fixed, so it stays a bug; but
  *"disable it"* is one choice among several and is the supervisor's. Likewise `BR51.06`'s second
  option — deleting `pick` outright because it duplicates active-target selection — is a design call,
  not a repair.

Nothing else in the BR51 series is a design change; the rest describe behaviour contradicting its own
specification.

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

## The performance monitor (addendum, supervisor-specified)

The hunt's own instrument was the thing that failed it: a `fps_dump` sampled once, two seconds after
entering aim, with the mouse still — structurally unable to see a defect that only appears while the
mouse moves. It reported 161 fps against three separate reports of 8. **The supervisor's ruling, now
recorded: their word is authoritative alongside measurements, and an instrument that disagrees with the
chair is itself a suspect.**

So the readout is a live panel rather than more log lines. `PerfStats` (logic, headless-testable) holds
the four figures, and every case in `test_perf_stats.gd` is arithmetic that can be checked by hand —
including the supervisor's own worked example, verbatim.

- **1% low** is the mean of the slowest 1% of frames, the hardware-review reading — confirmed with the
  supervisor, since the 99th-percentile *frame* is a different number.
- **Average dropping the top 1%** cuts on **speed**, not on a count of entries: every frame below
  `0.99 x fastest`. On the worked example (100 x 10 fps, 20 x 159, 30 x 160) it reads **10.0**.
- The readout **states its own coverage** ("reporting 62% of 4210 frames"), because a figure computed
  after discarding data should say how much it discarded.
- It **samples every frame and redraws on the 2 s tick**. Nothing sorts per frame — a profiler that
  costs frames measures its own overhead.

**A number in the supervisor's own example was wrong and it strengthened their case.** They gave the
plain mean of that distribution as "~40fps"; it is 59.9. The conclusion — that the mean is useless here
— holds harder, not less: it overstates by 6x rather than 4x. Asserted in the test so the record stands.

**The panel took three arrangements to place, and all three are in the changelog.** A chrome row and a
verb-pane caption were different mistakes, and the second one *passed a test*: the checkbox was
labelled correctly, emitted correctly, and toggled the right panel while sitting in the pane that
belongs to the selected verb — so it captioned every entry in the list. **No test of its behaviour
could see that**; the regression test asserts parentage, and was verified by re-breaking the layout.

The landed shape is the supervisor's: **"UI Element Control" is a list entry**, its checkboxes fill the
same right-hand pane every verb uses, and `DebugUiElements` is the table behind it — a new toggleable
element is a row, not UI code, the same shape `DebugVerbs` already had. Apply is **disabled** while the
category is selected rather than pressable-and-inert.

## What the block actually executed, said plainly

**Four of ten original passes are untouched and a fifth is barely started.** The block went where the
evidence went — the framerate deep-dive, then the performance monitor, then both addendum clusters —
and each of those was a supervisor decision at the time. But tb51 as written is roughly half executed
and that should not be buried:

| pass | state |
|---|---|
| A — repro session | **done** (five hunts, fourteen entries filed) |
| B — ledger repairs, caching | **B1 done**; B2 and B3 untouched (B3 left unmerged on supervisor instruction) |
| C — tracers and impact drawing | **untouched** — six entries, the largest remaining cluster |
| D — wall cutout and occlusion | **untouched** |
| E — queue and action legality | **untouched** |
| F — aim and camera framing | `BR26.02` `Pending`, paused by supervisor; three others untouched |
| G — map generation and movement | **untouched** |
| H — performance | **untouched**; `BR27.09` may be closeable on a fresh number |
| I — spectator vs player | **done** — all three closed, two of them via addendum Pass L |
| J — loners and digest | `BR48.01` closed; four untouched |
| addendum K — selection | **done** |
| addendum L — death mid-turn | **done** |

## The addendum's two passes

**Pass K — selection only understood units.** A missing type, not a broken rule: `SelectionController`
held one slot shaped `Unit`, while `PartPicker.hit` had always scanned blockers and field items. The
picker saw barrels; selection had nowhere to put them. `SelectionTarget` (logic, headless) holds
`UNIT`/`PART`/`CELL` plus an empty target that answers questions instead of being `null`, and wraps the
hit dict `board_clicked` already emits rather than inventing a second vocabulary. `selected_unit`
survives as a **derived property** — eighty-one readers still mean it, and a second stored field would
drift. Closed `BR51.10` and the live half of `BR51.02`; `BR48.01` came out of the same cluster.

**Pass L — death was not a lifecycle event anything listened for.** `SelectionController` never
referenced `alive`, so `selected_unit` outlived the unit it pointed at. It invalidates on **read** now,
not on a notification from `kill_unit`: that would have put a TACTICS concern inside a RESOLUTION
mutation and still missed every other route by which a unit stops being valid. Closed `BR51.09`
(mine), `BR27.07` and `BR32.09`.

**`BR27.07` was the same bug fixed on one call site out of two.** tb32 Pass D deferred the active-turn
flip until after playback in `SquadControlOverlay` and called it "a real confirmed bug" in its own
comment — and changed only that caller. `SpectatorOverlay._advance()` kept applying the highlight before
`play()` drew the previous unit's move. **The supervisor's controlled comparison is what found it**:
correct under player control, wrong under AI. A human turn ends after its own animation, so the player
path structurally cannot expose the gap.

## `BR48.01` took three diagnoses, and the dump settled it

Two confident readings of the code were wrong — an empty modal on bare tiles, then the preview's
lighting nodes not being released on close. **Dumping the battle `World3D` answered it in one run:** at
rest it had **four** lighting contributors, the board's environment and light plus `InspectPanel`'s,
because `SubViewport.own_world_3d` defaults to false. After one inspect cycle it had two.

The board had been accidentally double-lit its whole life. The first subject taking the fallback path —
cover, a loose item, a bare tile — set `own_world_3d = true`, removed both, and nothing put them back.
**The supervisor's *"starting a new bout does fix it"* is what proved it**; neither earlier theory
predicted that, and this one requires it. The lesson is the block's own: two readings of the source lost
to one dump, and the supervisor's incidental detail outweighed both.

Brightness was then restored as a **measurement** — `BOARD_LIGHT_ENERGY = 2.0`, because two identical
directional lights were additive. Ambient was deliberately not doubled: the two `WorldEnvironment` nodes
were not additive, so it never changed.

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

## `BR51.11` — the long way round

`ResolutionPlayer` tweened facing with `tween_method`, which interpolates its two arguments as **plain
numbers**: handed raw orientations it runs 0.1 -> 6.0 the long way, 336 degrees left instead of 24
right. Fixed by tweening towards `from + angle_difference(from, to)`.

**Both of the supervisor's observations were diagnostic.** *"They end up facing in reasonable
directions"* is why this was visual-only — only the path was wrong, never the arrival — so **the test
asserts the arc, not the endpoint**, because an endpoint test passes on the broken version. *"Squad 1
and not squad 0"* is a distribution of starting facings rather than a squad rule, and that is pinned in
a test so the fix is not later read as a squad-specific patch.

## The catch-up hypothesis, proposed and disproved in one session

The supervisor read the perf monitor's spike and asked: *"Is it queuing frames for some reason, and when
those finally get to hit, they run over?"* A catch-up frame is identified by **adjacency**, so
`PerfStats` was extended to report the fastest frame with the frames either side of it.

**Eight dumps answered it: `fastest 3915.8 (prev 116.2, next 260.0)`.** The frame before the spike was
116 fps — nothing stalled — so the hypothesis is disproved and the proposed `BR51.15`/`BR51.17` merge
was withdrawn. The instrument the block built answered a question about itself in one session, which is
the return on having built it.

**And a shared assumption was wrong:** `avg less top 1%` reads 177-185, above the monitor's refresh.
**The game is not capped at 160 — the display is.** Exactly the uncapped condition the supervisor
predicted when specifying these figures.

## Narrower than its name — three times in one block

Three green assertions sat beside live defects, each testing something narrower than its name claimed:

1. `test_a_diagnostic_keeps_its_own_row_and_is_never_folded_into_plumbing` protects the kind literally
   called `diagnostic`, not diagnostics generally — so `fps_dump` folding into `wall_cutout` (`BR51.13`)
   never registered.
2. `test_clicking_a_bare_tile_or_a_tiles_object_opens_the_same_inspect_panel` only ever places a crate.
   The empty case its name covers was never run.
3. A test I wrote this block asserting the perf readout was "wholly on screen" passed on a panel
   spanning the entire display, because left-edge and right-edge checks are both satisfied by one.

This is the failure taskblock-49's audit exists to find, arriving three times from three directions. A
name is not a specification, and the gap between them is where defects live.

## `SUPERVISOR`-owned entries moved to `Pending`

- **`BR26.02`** — the aim framerate. Per-motion cost 113 504 → 8 878 usec, confirmed live by the
  supervisor's own dumps (2 s samples 8 → 116/160). **Paused, not closed, at their instruction.** The
  session minimum of ~7.5 survives and now has a named lead: `BR51.15`.

## Open questions

- **The ~7.5 fps session minimum is one stall, not a load**, and the supervisor has located it: *"a
  distinct hitch right as the over the shoulder camera gets behind the unit"*. Filed as `BR51.15`. That
  is a far better lead than a stray stall and is where this resumes.

- **Averages are the wrong statistic and this block proved it.** One session read `min 7.5, avg 140.1`
  — and the supervisor notes the averages are further tainted by alt-tabbing while observing. **The
  performance monitor above is the answer to this and it is built**; every framerate entry still open
  (`BR51.14`, `BR51.15`, `BR27.09`) should be re-measured through it rather than through a `fps_dump`.

- **RESOLVED. `BR51.13` contradicted a passing test**, and the assertion was the narrower thing. `test_log_fold.gd` asserts a diagnostic is never folded into
  plumbing, and `fps_dump` is being folded into `wall_cutout` runs in every log this block. Read the
  test before the code: a green assertion beside a live defect means the assertion is narrower than its
  name.

- **`BR51.14` is very likely `BR26.02` on the non-aim path** — and now has an instrument. — hovering tiles with a unit selected drops
  160 to ~20, motion only. The two fixes that worked should transfer, but it wants its own measurement
  first rather than an assumed diagnosis.

- **`BR51.01` (shots land left) is still unexplained and untouched since its frame theory was
  disproved.** The reticle and resolver were measured to agree to 0.0000 cells across four geometries,
  so the remaining suspects are camera-side. The supervisor suggested moving the camera to the left to
  test; that experiment is still available and now affordable at 113 fps.
