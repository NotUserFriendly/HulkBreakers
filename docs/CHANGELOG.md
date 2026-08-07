# CHANGELOG.md — What's Been Built

## Taskblock 61 — the hunt

### Pass A — shot geometry, and the instrument finally read

**Full gate green: 342 scripts, 3350 tests, 0 failures.**

**The three angle entries are three causes, not one** — which is the answer the pass existed to
get, and it means the wall cutout does not inherit a shared upstream cause.

**`BR52.10` fixed.** `UtilityContext._lof_possible` read `field.allows(cell)` — terrain and opacity
only — so nothing anywhere asked whether a squadmate stood in the firing line, and an AI unit would
put a twelve-round burst through the ally in front of it. It now also fails when a living squadmate
sits on `Grid.line(cell, target.cell)`. **A regression restored, not a feature added**: the retired
branch planner refused this and logged `held: ally_in_line` until the taskblock-45 rewrite.

**No new input and no new weight, deliberately.** `shoot.tres` already carries `line_of_fire` as a
consideration and `UtilityScorer`'s product model preserves a zero at every `n`, so answering
`false` vetoes shooting from that cell outright. Inventing a friendly-fire weight would have been a
balance number nobody chose, saying something the existing veto already says. Read through
`WorldView.units_visible_to` rather than `_state.units` — allies are on the radio, so a squadmate is
in that list at every tier including `MINDLESS`.

**Measured over four bouts: impacts landing on a squadmate fell from 121/1803 (6.71%) to 37/1642
(2.25%).** A 66% reduction, **not elimination, and the residual is expected**: the check is
cell-granular by design and under two-phase turns an ally can move into a line after the decision
to fire was made. Five tests; two go red when the check is reverted.

**`BR54.01` confirmed, and what is left is a decision rather than an investigation.** 1391 first-hop
impacts paired to their announcing shot: mean off-axis **17.20°** under 2 cells, **2.51°** beyond 8
— monotonic decay, exactly what `docs/02` predicts if the aim point is the frontmost region's
centre. Two independent measurements now agree (`docs/02` had 20.1° at one cell). **Both sweeps
produced only one weapon each**, so the range half is confirmed and the weapon-independence half
still rests on the entry's original table — stated rather than glossed.

**`BR52.07`'s diagnosed mechanism is unreachable and nothing here did it.** The entry says the fix
lands when `CombatState.shot_resolver` inverts; it defaults to `&"ray"`, and `RESOLVER_PLANE` is
named only by its own constant, the differential harness and a comment. Marked `Pending` rather
than closed, because the cause being unreachable is not the symptom being confirmed gone — and the
entry now records what a reappearance would disprove.

**`BR51.01` re-verified live and lifted out of the hunt.** `CameraRig.aim_at` still rotates the one
real camera up to 5 degrees toward the reticle, and the aim ray casts through it. The supervisor's
specification is architectural — the camera turns a cursor pixel into a world point, and the shot
runs gun-to-point with no camera in the expression — so it became `PLAN`'s *Take the camera out of
shot processing* rather than being half-built in a hunt pass. **Pass A's AI sweeps say nothing
about it in either direction**, since the AI path never touches a camera.


## Taskblock 60 — prep for the bug hunt: delete two, instrument four, dissolve seven

**Full gate green: 341 scripts, 3345 tests, 0 failures.**

*Prep, not repair. **No bug is fixed in this block**; Pass D triages and taskblock-61 hunts.*

### Pass A — ramps retired, `step_height` introduced

**Five categorical checks became one continuous comparison.** `Surface.is_ramp_at`,
`MapGen.RAMP_MAX_RISE`, `MapGenScratch.CellKind.RAMP`, `_stamp_ramp`, `_stamp_ramp_pair` and
`_connect_with_a_ramp` are deleted. The rule is now *can this unit step up that far*, never *is
this thing labelled a ramp*.

**`Unit.step_height()` is a per-unit stat through `StatResolver`**, mirroring `mp_per_ap` exactly —
so a leg swap changes what a unit can step over on the same frame, and two units on the identical
board legitimately disagree about the same rise. `BASE_STEP_HEIGHT` is **0.3, flagged not designed**:
it is the stair riser the design names, not an invented number, and everything downstream derives
from it rather than assuming it.

**`Pathfinder.for_unit(grid, unit)` replaced fifteen `Pathfinder.new(grid, unit.shell.can_climb())`
call sites.** A caller could read one mobility property off a unit and default the other; now it
cannot. `SearchRoute.generate` takes the unit for the same reason.

**The free rise is symmetric.** Up and down within the step both cost `DEFAULT_COST` — an
asymmetric one would manufacture one-way ground a fraction of a level at a time, which is `BR46.02`
in miniature.

**The generator builds stairs and repairs with ladders.** A flight is `ceil(rise / step_height)`
steps, so the tread count is derived and retuning the step height reshapes stairs with no further
edit. The repair path's ramp branch is gone entirely: a rise inside the step height was never
stranding, and everything above it is a ladder — **the branch `test_map_navigability.gd` had
measured as dead is now the only branch there is**, and that test inverted rather than being
deleted, as its own note instructed.

**`MapNavigability` and `MapGen.generate` take the step height**, defaulting to
`Unit.BASE_STEP_HEIGHT`; a caller holding a roster passes `Unit.lowest_step_height(units)`. The
invariant has to assume the worst case or it certifies boards the shortest-legged unit cannot leave.

**A cosmetic ramp survives as content.** `data/parts/ramp.tres`, `Surface.RAMP_TAG` and
`RampGeometry` still render a slope and `CellInspection` still names it. What went is the traversal
privilege. The guard in `test_step_height.gd` bans the three retired **identifiers**, deliberately
not the word — a total ban cannot tell a correct use from an incorrect one, and the word is still
live.

**Reverted mid-pass, and worth recording.** Dissolving `CellKind.RAMP` silently dissolved a
protection it was carrying: `_scatter_cover` skipped non-`OPEN` cells, so cover could never land on
a ramp. With treads as ordinary `OPEN` cells, cover began sealing stairs and
`_repair_stranded_elevation` then flattened the rooms behind them — **raised ground across eight
seeds fell from 15.8% of walkable cells to 8.3% before this was caught.** `_author_levels` now
records the flight (treads and the cell it lands on) into a `stair_cells` set that `_scatter_cover`
refuses. **The measurement is what found it; nothing failed.**

**Measured, both sides, 40x30 across eight seeds:**

| | ramps | `step_height` 0.3 | `step_height` 0.5 |
|---|---|---|---|
| raised cells | 1076 (15.8%) | 883 (12.8%) | 1076 (15.8%) |
| one-way (stranded) cells | 0 | 0 | 0 |
| generation, 8 seeds | — | ~2.1 s | ~2.1 s |

**The residual gap at 0.3 is the honest cost of the pass**: a 3-tread flight needs more room than a
2-cell ramp did, so some rooms find no approach and are flattened. Navigability is untouched at
every step height measured. **Which step height to ship is a balance call and is the supervisor's** —
the code makes it one number.

**Two entries closed as `Obsolete`** — `BR56.01` (repair ramps stamped at 45 degrees) and `BR51.12`
(ramps stacked facing opposite ways). Both describe deleted code; neither was verified fixed.
Supervisor-authorised over the owner gate, on the record that they reopen if met again.

**`BR60.01` filed.** Measuring the before/after turned up a **pre-existing** defect that reproduces
identically on both sides: `MapNavigability` asks "can you get out", so a raised region you can
never get *into* is invisible to it — 12 such regions across 60 seeds at 40x30, largest 235 cells.
Not fixed here.

### Pass B — every way of firing announces itself

**`BurstAction` was one of seven paths that announced.** `AttackAction`, `StabAction`,
`SlashAction`, `GrindAction`, `Suppression` and `Overwatch` emitted impacts only, so a sniper
firing and a sniper idling were indistinguishable in the log until something was hit. All seven
now announce.

**`ShotAnnouncement` is an object, not a seventh emit**, and that is what makes it
by-construction. It carries the origin, the intended direction, **the unit's own facing**, the
weapon, and which path took the shot; `ShotResolution.resolve_and_log_point` announces from it,
so the six paths that share that seam cannot announce a shot different from the one they
resolve. `Overwatch` resolves through `DamageResolver` itself and calls
`ShotResolution.announce` rather than writing a `combat_log.emit` by hand — an announcement
written at one call site is one that can drift from the six the resolver writes.

**Once per trigger pull, not once per projectile.** `announce_once` is idempotent per instance,
so a shotgun pull's nine pellets share one announcement and a three-round burst emits three.
Granularity is expressed by how many announcements a caller builds rather than by a flag.
**`burst_fired` is untouched** — it is a per-burst summary `LogFold` reads, and one of those now
covers the several announcements a burst's pulls emit.

**The melee vocabulary, decided once.** The event kind is `weapon_used`, deliberately neutral,
with `method` as an **open `StringName` vocabulary** (`fire` / `thrust` / `swing` / `grind`). A
stab resolves through the identical path and *fired* is the wrong word for it, so a vocabulary
that only fits guns would be wrong again for the next delivery anybody authors. Suppression's
opportunity attack announces as a thrust because it reaches for a `stab` provider — the method
follows the weapon that delivers, not the rule that triggered it.

**`BR54.01` is a field now rather than a reconstruction.** `off_facing` — the wrapped angle
between where the unit is pointed and where the round went — is computed into the event, because
that entry *is* that angle and it had to be inferred from impact geometry to be characterised at
all.

**An eighth path fails a test until it tags in**, which is the taskblock's own definition of the
claim. `test_every_firing_path_announces_itself.gd` enumerates the seven, sweeps `src/` for any
file reaching a shot resolver that is not listed, and checks every listed file still builds an
announcement. **Verified non-vacuous**: a planted eighth path was caught and named.

**A finding, from a test failing.** `AttackAction.apply` calls `FaceAction.face_for_free` toward
its target *before* firing, so the facing an announcement records is post-re-face. The fixture
assumed otherwise and went red. It is worth stating because it sharpens the instrument: a queued
attack should read near-zero `off_facing`, so **`BR54.01`'s 43 degrees is not a stale-facing
effect** — consistent with `docs/02`'s own measurement that the aim point is the frontmost
region's centre, which moves off-axis without the unit turning at all. taskblock-61 should read
the log before forming a theory, which is what the taskblock asks anyway.

**Behavioural coverage is three of seven and says so.** `AttackAction`, `BurstAction` and
`StabAction` are driven as real actions — the three shapes that could fail differently. The
other four are covered structurally plus by their own files; duplicating five fixtures here
would have bought nothing.

### Pass C — the snapshot split did NOT land, and the seven entries are not one root

**Stopped and reported, which is the outcome this pass's own stop rule asks for** when the work
outgrows the block — *"a half-built snapshot split is worse than none."* What it did not
anticipate is the reason: **the premise does not hold.** Tested rather than taken from the
entries, and the seven fall into five different classes.

| entry | actual class | evidence |
|---|---|---|
| `BR54.02` part vanishes before its tracer | **the snapshot class, and the only one** | `refresh_unit_views` bakes at the FINAL state; `ResolutionPlayer._prime` already retro-applies a display offset — but only for `_display_cell` / `_display_orientation`. There is no equivalent for *structure*. |
| `BR27.07` active-turn highlight | same class, same clock | named by `BR54.02`'s own entry |
| `BR52.06` a leg has no model | **a membership disagreement** — see `BR60.02` | `UnitGeometry` emits boxes under `hp > 0`; `BodyProjector.projects` also admits `is_mangled`/`is_disabled`. Measured: a mangled leg at 0 hp is **hittable and draws nothing**. |
| `BR52.09` destroyed cover stays drawn | **a missing teardown path** | nothing in `src/view/` listens for `part_destroyed` at all, and `_spawn_blocker` keeps no handle to the mesh it creates. A snapshot would not help; there is nothing to remove it *with*. |
| `BR51.24` exploded part stays on model | **an undecided rule, pointing two ways** | the entry's own note: *"if that still holds, the model is right and inspect is wrong"*, and `refresh_unit_views` already runs on this path. |
| `BR30.02` debug move never draws | **unreproduced** | three real-scene scenarios tried and recorded as a negative result; needs a supervisor repro. |
| `BR57.01`, `BR59.02` | **already fixed, awaiting confirmation** | both `Pending` from prior sessions; `BR57.01`'s fix has since moved on again — the editor now draws no bout unit at all. |

**So the hunt inherits something better than "seven entries that are one thing": seven entries
sorted by what each actually is**, with two of them already closed pending a look, one that is a
decision rather than a defect, and one that turned into a new measured entry.

**`BR60.02` filed, and it is the substantive find.** Two functions answer *"does this part
exist"* and answer differently, in the same frame, with no animation involved — a mangled or
disabled part at 0 hp still projects (occludes, hittable) and emits no box for the view to draw.
That is `docs/10`'s "render is hitbox" pillar broken outright, it is very likely `BR52.06`, and
it rules out that entry's own `volume` theory (every leg part authors real boxes, checked).
**Which side is wrong is a real decision and is not made here** — it is the fourth instance of
one membership question having two answers, so it belongs with `PLAN.md`'s *Derive plane/picker
membership instead of answering it in four places* rather than as a fifth local patch.

**Nothing was built.** No bug is fixed in this block, and the snapshot split is left whole for
whoever takes it — with the note that **half of it already exists**: `ResolutionPlayer` holds
display state for position and facing during playback, and `BR54.02` is that same idea missing
for which parts exist. That is a much smaller piece of work than the entry implies.

### Pass D — the ledger sorted by cause, and the deep ones named

**Every open entry carries a `cluster:` line, and that line is the sort.** Sixteen clusters over 46
entries. **Nothing is derived and no index is maintained** — `grep 'cluster: `shot-geometry`'` is
the whole query, the same posture the `^### BR` heading grep already has, and the reason `BUGS.md`
has never needed a table of contents.

**A cluster is a claim about shared cause, not about subject matter.** `BR52.09` and `BR54.02` are
both *"the model and the picture disagree"* and land in **different** clusters, because one is a
missing teardown path and the other is a timing gap — a hunt treating them as one thing fixes
neither. That distinction is what Pass C's testing bought.

**The five deep-investigation groups are named in `BUGS.md`'s own header** with what to check
before starting: read the new firing log before theorising about shot geometry; re-read the wall
cutout because `RayCaster` made it cheaper than its entry says; confirm whether `BR52.12` is an AI
defect wearing overwatch's clothes; re-verify `BR55.01` still reproduces; and do not spend a hunt on
`BR52.14`, which is test infrastructure.

**The framerate entries were not re-triaged**, per the taskblock's instruction — the bar and the
tolerance are recorded in the ledger's own header and those entries sit deliberately.

**Two entries were re-pointed by this block's own findings.** `BR32.04` is filed under `wall-cutout`
but is also a `two-clocks` symptom and may need no shader work at all; `BR52.06` gained a measured
probable cause (`BR60.02`) and had its own `volume` theory ruled out.

**Ledger arithmetic: 46 open at the start, 46 at the end.** `BR56.01` and `BR51.12` closed
`Obsolete`; `BR60.01` and `BR60.02` filed from measurements taken in Passes A and C. The taskblock's
own "44 live entries" counts the post-Pass-A state.

### Follow-up — the step height corrected to 0.4, and a round on the `Suspected` entries

**`BASE_STEP_HEIGHT` is 0.4**, the supervisor's number, with 0.5 rejected as too generous a slope.
**The 0.3 that shipped in Pass A was a misreading and the correction is worth recording**, because
the design document reads as though it says 0.3: `PLAN`'s *"two ordinary tiles at 0.3 and 0.6"*
names tile **heights**, not step sizes, and that flight's steps are 0.3, 0.3 and **0.4** — the
largest is the last one, so the example needs 0.4 to be walkable at all.

**Re-measured at 40x30 over eight seeds: 15.7% of walkable cells raised, 0 stranded**, against the
retired ramps' 15.8%. **So the ramp retirement costs essentially no elevation at this value** — the
12.8% reported for Pass A was a consequence of the wrong constant, not of the retirement. Three
fixtures that pinned the old boundary now **derive** their rise from the constant instead of
writing it as a literal, because that assertion has been invalidated twice already.

**A regression introduced by this block, found by the full gate and fixed rather than pinned.**
Shorter stairs left more rooms raised, and on one seed a **spawn zone straddled a full
`LEVEL_HEIGHT` ledge** — half a squad spawning on a shelf the other half cannot climb, breaking
`BR40.04`'s invariant. **Measured on both sides to establish it was mine**: zero non-uniform zones
before this block, one after. `_mark_zone` now keeps only the cells sharing the block's
**majority** level.

**That fix took two attempts and the first was worse than the bug.** Reading heights through
`UnitGeometry.true_height_for_cell` returned 0.0 for every cell, because `_mark_zone` runs before
`_emit` and `grid.surfaces` is still empty — a filter that silently matched everything, caught only
because the sweep stayed red. Anchoring on `room.position` then collapsed a zone from four cells to
one, because that corner was the single low cell beside a raised shelf, and **the three cells it
discarded were the board's only way onto that shelf** — turning a spawn-zone defect into a 95-cell
unreachable region. Majority-anchoring keeps both. Cost across 40 seeds: **two zones at three cells
instead of four, and zero non-uniform.**

**`BR60.01` appeared at 32x24 for exactly one build and then hid again**, which is the strongest
evidence yet that board size is why nobody has seen it. The step-height raise exposed a 34-cell
region on seed 29; the spawn-zone fix moved a zone onto the shelf and it became reachable.
**Neither change touched the defect.** At 40x30 it is completely stable across every variation
tried — six regions of 50 to 235 cells, before and after the retirement, at 0.3 and 0.4, with and
without the spawn fix. `KNOWN_UNREACHABLE` is empty and asserted as **equality** rather than
`is_empty()`, so a reappearance is a red test rather than a silent pass.

**A round on all five `Suspected` entries, and four moved.**

- **`BR32.08` confirmed and promoted to `Active`.** `wall_cutout_units` is fed
  `combat_state.units` — every unit — and the occluder filter checks `null`, validity, the active
  unit, squad, and `extracted`, but **never `alive`**. A dead friendly shell keeps its cell and its
  view, so it keeps punching a porthole through walls. The `extracted` skip is the precedent and
  its own comment argues the case word for word.
- **`BR52.13` closed `Obsolete`** — re-measured across six real AI bouts: **380 of 2450 impacts
  penetrate (15.5%)**, against the original zero of 156. Neither reading is wrong; that battle was
  chaingun-versus-steel, a pairing that cannot penetrate, so the sample reported zero by
  construction. **The model was never broken; the sample was narrow.** Closed `Obsolete` rather
  than `Resolved` because nobody fixed anything.
- **`BR52.14` re-measured and deliberately left open.** 3 fails in 236 runs, none since run 138 —
  98 consecutive clean runs including four gates this block. **Ninety-eight clean runs is not a
  fix**, and the entry's own requirement (a captured failure) is unmet.
- **`BR33.01` and `BR51.18` re-verified, unchanged, left `Suspected`.** The first still reproduces
  in code and is waiting on whether the feature survives at all; the second is still structurally
  possible (`_display_cell` and `_display_orientation` remain separate) and still unreproduced.

**The armour-balance observation inside `BR52.13` was salvaged into `PLAN.md` rather than
archived** with the entry: `steel.tres` authors no `deflect_threshold_deg` and leans on a 30.0
default against a measured ~31 degree engagement. A shipped material resting its feel on unauthored
defaults is a decision, and a closed bug report is the wrong place to keep one.

## Taskblock 59 follow-up — fourteen editor reports across four review rounds

**Full gate green: 339 scripts, 3322 tests, 0 failures, 1396.6 s.**

### The gizmo

**A drag is a pure function of where it started and where the pointer is now.** `Gizmo.amount_at`
is a delta measured from the grab and both callers applied it to the **current** value, so every
mouse-motion event re-applied the whole drag — six events at a **stationary** pointer took a wall
from 3.4 to 8.4. `Gizmo.drag_start_state` snapshots the subject and `GizmoModule.begin_drag` is the
only way to start one, so a caller cannot begin a drag without a snapshot. **The claim drags had the
identical defect and no report against them.**

**The gizmo addressed a cell, so the handles sat on a pillar while the drag moved the floor under
it** — the handles came from the topmost placement and `set_height` wrote to the topmost *surface*.
A surface now moves by its `height` and anything else by its `offset`, which is what the two fields
already mean. The detachment report is the same defect: after a drag the handles and the moved thing
disagreed.

**Horizontal drags move the placement by whole cells**, and `gizmo.cell` re-points at the
destination so the handles follow. Sub-cell movement stays `offset`'s job. **The readout follows the
cursor** instead of sitting where the action bar happens to be. **Arming a non-gizmo tool releases
the subject and its ghost**; swapping Select↔Scale keeps it.

### A cell can hold a column

`PartPicker.hit` reports the **world point struck**, so the editor can tell which of a stack was
clicked. Place, delete, select and scale all address the struck placement; the cell-addressed forms
remain as the fallback for a click that resolved off the ground plane. **Cover lands on the deck
that was clicked** via `MapPlacement.offset`, rather than by changing `Surface.first_walkable` — a
documented grid rule the pathfinder reads, and a test pins that it did not move.

### Three corrections

**The ghost was wrong, not the logic.** `BoardView` draws a blocker at the cell's true walkable
height, ignoring the authored height — correct, because `MapPlacement.height` is surfaces-only —
while the ghost drew at the target height. My first fix changed `FacePlacement`, the shared answer
the *click* uses, and so moved where things were authored. Reverted; the ghost derives the height
**and the facing** the board will use.

**A placement is seated against the face it was clicked on.** `ship_floor` authors its box at
`center.y = -0.1, size.y = 0.2`, so it hangs entirely below its own height — placing it at the
struck plane put it in the 0.2 the clicked floor already occupied. Top face now seats the new part's
bottom, bottom face seats its top, side face seats its bottom. A `wall` is unaffected, which is why
this only showed on floors.

**The bare-cell fallback was unconditional.** `BoardPicker.cell_at_ray` resolves against the board's
terrain plane, so *any* ray crossing the board yields a cell — pointing above a tile, or over a wall
at something behind it, still drew a ghost there. Reported as *"an invisible copy higher up"* and
*"I can click things behind the actual object I'm aiming at"*: one cause, nothing phantom. Limited
to genuinely empty cells, which was its purpose.

### And the rest

- **The editor draws no bout units at all.** taskblock-59 Pass B covered only the units the board
  could not seat; `swap_board` seats on the first free walkable cell, so the first floor tile put
  one on the board. The stale unit and the wall cutout were **one unit**.
- **The "PL" toggle reads what is on screen.** Fixed in `UiButtonsModule`, because the desync
  belonged to every module in the cluster whose surface can open by other means.
- **`PartPicker` can strike surfaces**, opt-in — clicking a floor struck nothing before, which is
  why a click placed into the cell rather than against a face. Off by default because
  `TacticsController` resolves aim through the same call.
- **`EditorTools` had reached into `GizmoModule`** for two tool names: `src/logic/` depending on
  `src/view/`. The vocabulary now lives in logic.

### Reverted, and worth recording

- **Refusing co-planar floors.** Tried, then backed out: two floors in a cell *can* be expressed, so
  refusing is a legality opinion — the line taskblock-59 Pass A drew — and it broke
  `test_an_illegal_placement_is_still_placed_and_only_warned_about`, a taskblock-56 F4 acceptance.
  The supervisor's reframing was the real answer and is the `PartPicker` change above.
- **The ledge veneer's derived facing.** Built and tested — a side click faces it back at the ledge,
  a top click reads the struck point for the nearest edge — then **reverted on the supervisor's
  call**, because `BoardView` draws a blocker at facing `0.0` and `MapSerializer` drops a blocker's
  facing entirely. A placement carrying a facing nothing renders is the visual/logic disagreement
  this block spent its time removing. *Both halves need to be possible first*; **blockers need a
  real transform**, which is queued.


## Taskblock 59 — the editor stops lying, and the tiers reach a bout

### Pass F — the completion rate, per tier, and it inverted

**Every completion figure this project had recorded was an all-`TRAINED` figure**, because
`Unit.intelligence_tier` defaulted to `TRAINED` and nothing set it (Pass E). Taken again with the
tiers authored, over seeds 0–5, three units a side, 100-turn cap:

| tier | completed | rate | mean turns | outcomes | cost |
|---|---|---|---|---|---|
| `MINDLESS` | 2/6 | **33.3%** | 26.0 | 2 extracted, 4 at the cap | 112 s |
| `GRUNT` | 0/6 | 0.0% | — | 5 at the cap, 1 stranded | 230 s |
| `TRAINED` | 0/6 | 0.0% | — | 6 at the cap | 343 s |
| `ELITE` | 0/6 | 0.0% | — | 4 at the cap, 2 stranded | 466 s |
| mixed | 0/6 | 0.0% | — | 6 at the cap | 324 s |

**`MINDLESS` is the only tier that finished a mission, and that is the finding.** It cannot shoot,
take cover or overwatch — so it walks to the extraction cells and extracts, in a mean of 26 turns.
Every tier that *can* fight stops to fight and hits the 100-turn cap instead. `TERMINATED` here is
`BoutRunner`'s own safety net, not a defeat: the combat-capable tiers do not lose, **they fail to
converge.**

**Cost rises monotonically with capability** — 112 s, 230 s, 343 s, 466 s — while completion does
not. More thinking, more planning time, no more missions finished.

**Suite wall-clock stopped being a comparable figure**, and that is a consequence of the wider
roster rather than a measurement problem. `seeds_to_first_win` plays seeds until one completes, so
the suite's cost scales inversely with the draw; at three units a side each seed is a much larger
bout. Three full-gate runs on the same tree measured **1373.5 s, 1330.6 s and 978.9 s**, with the
runner reporting *"seeds to first completion"* of 6 and then 1. The stable numbers are the work
counters the runner already prints and the probe's per-row timings over a fixed window.

**Reported, not tuned.** The taskblock's instruction was explicit: *"if the mixed rate drops below
the floor, that is a finding about the floor as much as about the AI."* `FIRST_WIN_CAP`, `TURN_CAP`
and `SAMPLE_SEEDS` are unchanged and pinned by a named test.

**Two caveats that stop this being over-read.** Six seeds is a tiny sample, and seeds 0–11 is
recorded in `CompletionSampler`'s own header as the *pessimistic* corner of the seed space — the
window taskblock-46 removed for exactly that reason. The **relative ordering** is the result; the
absolute rates are not a rate. The same build's `seeds_to_first_win`, drawing randomly, found a
completion in 6 seeds on the full gate, so the mixed roster is not at 0% in general.

**A prediction of mine that was wrong, stated plainly:** I expected an all-`MINDLESS` squad might
never complete a mission and said so before measuring. It completes more often than any other tier.
Extraction is a *movement* objective, and I had assumed it required winning a fight.

### Pass E — the intelligence tiers reach a bout

`Unit.intelligence_tier` existed since the AI's world model was built and **nothing ever set it**.

**`BotPreset.intelligence_tier`**, authored where a unit is authored, defaulting to `TRAINED` so a
preset that says nothing behaves as it always did. `DeepStrike.assemble_from_preset` applies it —
the one path with a preset to read from. Tiers authored on the three combat testers: chaingun
`GRUNT`, pump shotgun `MINDLESS`, sniper rifle `ELITE`; the labourers stay `TRAINED`.

**`CompletionSampler` builds a mixed 3v3** instead of one labourer against another — the
supervisor's call over tiering the labourers, which would have made the measured bout a walkover
between a unit that can shoot and one that cannot. `build_at_tier` gives the per-tier breakdown over
the same map and roster, so what is measured is intelligence and not weapons.

**Every recorded seed changed meaning.** A figure from before this pass and one after are not
comparable. Nothing on disk pinned one — `BoutCorpus` draws from the clock — so there was no
artifact to regenerate, only past figures to distrust.

**Superseded, not fixed:** the tier table describes `GRUNT` as *"memory and the shoot/cover/overwatch
set"*, but `overwatch.tres` has read `[TRAINED, ELITE]` since taskblock-45. The content is what runs.

### Pass D — the ledge veneer places from a click

`LedgeVeneer` computed the span, the part was authored, hp followed volume — all taskblock-58. **No
click called it**, so a veneer needed a hand-authored `.tres`.

`span_among` takes a list of heights, so the rule has one implementation and two sources: a `Grid`
for the loader, the authored placements for the editor — `FacePlacement` already refuses to build a
`Grid` per hover and this follows it. The struck normal decides direction; the rise is carried as an
ordinary `MapPlacement.size`, so it round-trips and gets volume-scaled hp with no special case.

**A limit found while building it and pinned by a named test: growing *up* can never snap to
anything through a click.** A top-face pick strikes the top of the stack by definition and the
placement lands on that same cell, so "the nearest surface above the face you struck" is always
empty and growing up always takes the 0.8 default. Growing **down** snaps exactly as specified.

### Pass C — the Scale tool authors a size

`MapPlacement.size` landed in taskblock-58 and **nothing wrote it but a hand-authored `.tres`**. The
gesture existed too — the Scale tool, the gizmo and face picking — and was never connected.

**The tool's definition**, as the supervisor stated it: the handle perpendicular to the face grabbed
moves that face alone; the handles parallel to it grow mirrored. That makes the inherited spec line
*"a top face scales X and Y mirrored"* consistent — a top face's perpendicular axis is Y, so its
parallel pair is the grid's X and Y, which are the world's X and Z.

**`MapPlacement.offset`** records the shift an asymmetric face move makes. It rides `size`'s path
exactly: `PlacedVolume.boxes_for` displaces the boxes and `MapSerializer` bakes them into the part's
volume, so `BoardView`, `RayCaster`, `SightSpans` and `DamageResolver` needed no change at all.

**`GizmoDrag.grow` solves for the offset from where the faces should end up**, rather than adding a
fixed half-drag — and that distinction was found by a failing test rather than by reasoning.
`boxes_for` scales about the part's origin, so `wall`, with its base at y=0, already grows upward on
its own; the first cut assumed and lifted the wall off its own floor by half the drag.

**Found in passing:** `SectionSerializer._lifted` and `_shifted` rebuild placements without `size`,
so a stacked or stitched section reset a sized wall to the part's own dimensions. A taskblock-58 gap,
fixed here.

### Pass B — seven gaps where the capability existed and the way in did not

- **The ghost appears over an empty tile.** `PartPicker.hit` answers `{}` over bare board — true, and
  the wrong answer to *"what is under the cursor"* — so the one place an author cannot infer what a
  click will do was the one place the preview was silent.
- **The parts-list button toggles the list.** It flipped `collapsed`, which `PartsListModule` never
  read; the border followed the list correctly while the press did nothing to it.
- **Map Thing gets its picker.** The selection existed and had no way in, so every click authored the
  default `Interior` claim.
- **The readout names the active placement** — the one piece an author needs and cannot infer.
- **The gizmo's handles were always clickable inside a part** (`Gizmo.hit` has no occlusion in it and
  the gizmo takes the input walk first); what was missing is that you cannot aim at what you cannot
  see, so the focused part now draws see-through. `CellGhosting` carries it.
- **The wall cutout stops keying off the last bout's units**, expressed as *"not drawn, so not cut
  around"* — which names no mode in `BoardView`.
- **The default floor is `ship_floor`, not whatever sorts first.** Supervisor's call.

**The last one closed two reports at once.** `surface_part_ids()` is alphabetical and the
GROUND-attaching parts are `[ramp, ship_floor]`, so the ordinary floor of this game had been `ramp`
since taskblock-56 — whose own comment said the intent was `ship_floor`. That is both *"auto-placed
terrain places ramps"* and *"warnings appear when placing `ship_floor`"*: **the warning was correct**,
about a surface the editor had silently authored on the author's behalf.

### Pass A — the editor's model and view stop disagreeing

Two reports, one defect. `EditorModule._refresh_board` returned silently whenever
`MapSerializer.to_grid` refused the model, so the view froze at the last board that built while the
model went on accepting edits — **every later placement invisible, every later delete too.**

- **`to_grid` gains a lenient mode**: draw everything drawable, name the rest. Strict is now
  *"lenient, refuse at the first skip"* — one traversal, one rule set. The editor renders leniently;
  the bout path stays strict.
- **`EditorController.place` refuses a second blocker** on a cell and says why, so the model cannot
  hold what the board has nowhere to put. Surfaces still stack and broken boards are still
  authorable — this is the format's limit, not an authoring opinion.
- **The ghost asks the same refusal the click asks.** Hovering a wall's top face previewed a stacked
  wall that could never exist, and taskblock-58's *"what appears is what the ghost showed"* test
  passed throughout **because it compared the ghost against the model and never against the board.**
- **`EditorPanel`** takes the widgets out of `editor_module.gd`, which hit the 1000-line gate for the
  third time — predicted in taskblock-58's own report.


### Pass F — parts get real dimensions, and HP follows volume

**`MapPlacement.size` is the size a placement was authored at**, `Vector3.ZERO` meaning "the part's
own" — so every map written before this loads byte-identically, because an absent field reads as
zero and zero reads as unchanged.

**`MapSerializer` applies it at load, and that is the whole integration.** A sized placement becomes
a `Part` whose `volume` *is* the scaled boxes and whose `hp` is the volume-scaled number, so
`BoardView`, `RayCaster`, `SightSpans` and `DamageResolver` all work on the real size **with no
change at all** — there is nothing special about it for them to know. That is what makes *"a
3 x 3 x 0.5 wall exists as one part"* literally true rather than a convention.

#### HP is linear in volume, and the density is authored

**Linear, on the supervisor's call** against a sub-linear alternative: *"diminishing returns on more
mass is the opposite of how armor works in real life."* Twice the wall is twice the hp.

**`Part.hp_per_volume` is the knob, in data, and it is opt-in.** A part authoring none keeps its
`hp` at every size, so nothing in the existing library rebalanced. `wall` authors **25.0**, which is
exactly its own 60 hp over its own 2.4 m³ — **the default wall is unchanged to the hitpoint**, which
is what made this safe to turn on. Measured: 60 at natural size, 120 doubled, 30 halved; the
taskblock's 3 x 3 x 0.5 wall is one box, 4.5 m³, 113 hp.

**Volume sums the boxes, not the bounding extent**, so a part authored as several boxes around a gap
gets no credit for the gap — `docs/02`'s shield-with-an-eyehole, applied to hp.

#### The support pillar is terrain

It holds things up, and `terrain` became a real tag in Pass D — so this is two lines of data plus a
density that likewise reproduces its authored 10 hp exactly.

#### The ledge veneer

A flat wall hung off a tile's edge, **sized by what it reaches rather than by an authored height**.

**Two gestures, not one, and the first model was wrong.** Collapsing them into a single
`span_between(from, above, below)` made a veneer grown *down* from a 2.5 tile with nothing under it
come out **zero tall**, because "the tile I am hanging from" and "the anchor above me" were the same
number. The taskblock states two sentences and they are two gestures: grown **up** from a top edge
(default `UNANCHORED_RISE`, 0.8), grown **down** from a side (falls to the deck, so its height is
the tile's own). **"Snaps to both" turned out not to be a third case** — it is what growing in a
direction does when that direction finds something. The wrong model is recorded in the class note so
it is not re-derived.

**0.8 is deliberately odd and flagged rather than designed.** A veneer coming up at 1.0 would be
indistinguishable from one an author sized to a level; 0.8 announces itself as a default. The real
answer is authored ledge art whose own box height should drive it.

**The name stays.** The taskblock calls it provisional and asks for better if one turns up; none
did. *Skirt* reads as decoration and undersells something with hp that stops shots, and *facade*
carries "false front", which is exactly what this is not.

#### A Pass C interaction this pass is the first to exercise

**A resized wall can be thinner than a cell, and `SightSpans` only counts boxes that fully cover
one.** So a 0.5-thick wall blocks the real march and does **not** register in the visibility field's
pre-filter. That is Pass C's fail-open rule working as designed — the field must never report "no
line" where one exists — and Pass F is the first content that reaches it. Recorded at the rule
itself: the consequence is that the pre-filter weakens as authors use thin geometry, the measure to
watch is how much work it still saves, and the fix if it stops saving enough is a finer occupancy
than "fully covers a cell".


### Pass E — the parts list moves to the Inspect slot, and placing resolves against the struck face

**`PartsListModule` owns the searchable list** and takes `ModuleSlots.INSPECT_PANEL`, the slot
`InspectModule` uses. The taskblock justified the share with *"while placing you cannot be
selecting"* — Pass D turned that from a claim about the author's intent into a claim about the code,
since `select` and the three `place_*` verbs are one vocabulary and `active_tool` holds exactly one.
The module closes Inspect when it opens, and the test asserts the two are **never** both up rather
than that they usually are not.

**One widget, two callers**, on the supervisor's call: the place verbs and Load open the same list.
`EditorBarModule` borrows it rather than building one, and connects the pick in `link()`, which is
the seam where every module in the mode is known to exist.

**"Toggleable from UI buttons" came for free.** `INSPECT_PANEL` is edge-pinned, so the module
reports itself collapsible and `UiButtonsModule` builds the toggle by sweeping for exactly that —
the fourth time asking for a toggle has been answered by a `preferred_slot()`, with nothing in
either file naming the other.

#### What appears is what the ghost showed, by construction

`FacePlacement.target_from` is **one function**, called by the preview to decide where to draw and
by the click to decide where to author. A ghost that computed a landing spot and a placement that
computed one would be two answers to a single question; there is one, so they cannot disagree. The
test comparing the ghost's transform to the placement's checks that the wiring is live, not that two
formulas match.

- **A side face steps into the cell the normal points into**, not the cell the ray crossed. Those
  coincide for a wall filling its cell and diverge for anything narrower, and the normal is the
  honest one — it is the face that was looked at.
- **A diagonal normal resolves to one orthogonal step.** `GridPlacement`'s grammar has no corner
  attachment, so a diagonal target would be a placement with no neighbour to attach to.
- **It reads authored `MapPlacement` rows, not a built `Grid`.** The first cut called
  `EditorController.to_grid()`, which rebuilds the whole board — a per-frame whole-map serialization
  to answer a question about one cell, with a ghost redrawn on every mouse move.

**`PlacementGhostModule` draws the real thing in a different colour**, from the same
`UnitGeometry.assembly_placements` call `BoardView` uses for an actual placement, rather than a
stand-in shape with its own reasons to be wrong.

**`BoardInspectModule.hovered_pick` is a second signal, not a widened `hovered_cell`.** The existing
one answers "which cell" and is what `EditorCoordsModule` wants; widening it would make every
listener take a dict to read a coordinate. **It fires only when something is connected**, because it
runs `PartPicker.hit` per motion event — `BR35.01` measured that at 1 559 usec on a real board, and
a mode with no ghost has no reason to pay it.

**`editor_module.gd` hit the 1000-line gate twice in this taskblock**, which is what moved the tool
vocabulary to `EditorTools` in Pass D and `target_from` to `FacePlacement` here. Both landed in
better homes than they left; the trigger was a lint gate rather than a design insight, and that is
worth saying plainly.


### Pass D — ten editor verbs become seven, grouped by what a click means

The old list was grouped by what a click *touched* — a verb per marker, a verb per flag — which is
why it took ten entries to express what an author experiences as three gestures: put something
down, take something away, grab something. Now: **`select`, `place_terrain`, `scale`, `delete`,
`place_map_thing`, `place_big_part`, `place_part`.**

**The generated-from-vocabulary property survived and got stronger.** `EditorBarModule` built a
button per tool but skipped `place`, which was really three placement-kind buttons; the three
placing verbs are tools now, so the row is generated with **no exception in it** and a test asserts
the button count equals the vocabulary count.

**`terrain` is a real tag on real parts** — `wall`, `ship_floor`, `ramp`, `ladder`. The taskblock
names it, so it is authorised content rather than an invented vocabulary, and it is what lets
*Place Terrain* derive its `MapPlacement` kind **per part**: terrain that attaches to `GROUND` is a
surface, terrain that does not is a blocker. That closes a class of authoring error — an author
could previously pick `wall` and `field_item` and author a placement the loader refuses.

**`height` folded into `select`, and that was checked rather than assumed.** `GizmoModule._drag_to`
already calls `EditorController.set_height` on a Y-axis drag of a placement, so the verb's whole
behaviour is what the translate handles do. It became direct manipulation instead of a spinbox and
a click.

**The tool vocabulary moved to `src/logic/editor_tools.gd`.** `EditorModule` went over the repo's
1000-line gate, the same split `InspectPanel` took when `BotViewer` came out of it — and logic is
the truer home: which tools exist, and what kind each authors, are questions with no widget in them
and are headlessly tested now.

**What this did NOT fix, stated at the filter rather than only here.** *Place Big Part* and *Place
Part* still offer every arm, head and battery in `DataLibrary.parts_pool()`. Nothing in the data
separates a crate from a forearm, `placeable_part_ids`'s own header has said so since taskblock-57,
and the taskblock authorises one tag rather than two. **Pass D split the verbs; the pool is still
unfiltered for two of the three.**


### Pass C.2 — the pacer stops being a test's hidden variable

**Pass C merged on the supervisor's call.** The one red test it carried,
`test_ai_batch_yield::test_a_yielding_batch_produces_the_identical_bout`, now raises `PlanPacer`'s
wall-clock budget out of the way and asserts the raise was genuinely enough rather than assuming
headroom. `ControlOverlay` grew `pacer_budget_msec` and `last_pacer` to make that reachable — the
view owns the pacer, so the view owning its budget follows, and production never sets either.

**The fingerprint comparison is untouched.** That equality is the whole test.

**This is not the regression being hidden**, and the distinction is worth stating: the test was
built to assert a seeded bout is identical driven through the yielding overlay or through a tight
loop, and it was *also* asserting something about wall-clock, because the yielding path aborts on a
deadline and the tight loop has no pacer to abort. One test was carrying two claims.

**The low budget was never the bug — the bug is that it is wall-clock at all.** A budget that fires
on ordinary turns is a governor rather than a backstop, and a wall-clock governor varies by machine,
so the same seed produces different bouts on different hardware. Latent since taskblock-44 and
unobserved while planning stayed under the number; `BR58.01` stays `Active` with the mechanism, and
`PLAN.md` carries the fix — pace on candidates, keep wall-clock only as a pathological backstop,
and derive the cap from a measured distribution rather than inventing it.


### Sight is geometry, a placement has a position, and a pick reports its face

Taskblock 58, passes A to C. Three prerequisites for the editor's real tools, each of which would
otherwise have been built twice.

#### `Grid.opacity` is retired, and geometry is the only answerer

**Three things answered "can A see B".** `LoS.has_los` walked `Grid.line` reading a flat per-cell
float array; `VisibilityField` shadowcast from that same array and recorded its own limit in its own
doc comment (*occlusion data here is 2D, per cell, with no per-level*); `RayCaster` marched the real
boxes. **Geometry already knew what blocks and a parallel flat array also claimed to.**

`LoS.has_los` is a real march now — `RayCaster.geometry_candidates`, the same reject and the same
slab test a round takes, with the unit loop left off. The array, its accessors, its `MapFile`
serialization, the editor's `sight_blocking` tool and `DamageResolver`'s reach-in to clear the flag
on a destroyed wall are all gone together. **Destroying the geometry is clearing the flag.**

**What the array could not express, measured:** a wall standing at ground level no longer hides a
unit two levels above it, and the same wall raised into the sight line still does. Same cell, same
part — a per-cell float had nowhere to put the difference.

**Two behaviour reversals came with it**, both recorded in `SUPERSEDED.md`. Cover now blocks sight
when it stands in the line, because every 3D volume does; a crate you can see over is still cover.
And `Overwatch`'s `LoS.has_los` gate is deleted — it was vetoing `_torso_visible`, which asks the
same question more precisely from the real muzzle against the real body, and which is what lets a
leaning striker be seen past full-height cover.

#### The cost, taken rather than assumed

`PLAN.md` asked for the number first. Measured on a 32x24 generated board, at the Pass B commit and
again after:

| | array-backed | geometry-backed |
|---|---|---|
| `VisibilityField.build` | 3 695 usec | 7 784 usec |
| `field.allows` (per candidate) | 0.46 usec | 0.49 usec |
| `LoS.has_los` | 3.8 usec | 662 usec |

**The obvious shape — ask `LoS.has_los` per cell — measured 535 ms per field build and was rejected
on the spot.** So the field is *built from* geometry rather than *cast per* query: `SightSpans`
reduces every blocker, placed surface and field item to the vertical spans it occupies over the
cells it fully covers, in one pass, and the line walk samples that. Roughly twice the old build cost,
which is the half the taskblock calls affordable, and **the per-query cost stayed a bit test**,
which is the half it does not.

`SightSpans` is deliberately weaker than the march, in the safe direction the field's contract
requires: a box only occupies a cell it *fully* covers, spans are never merged, and a grazing line
passes. Swept on a real board, the entire gap between it and the march is scatter pillars, which are
smaller than a cell. `test_sight_geometry.gd` asserts the containment rather than arguing it.

#### And it costs planning time, which broke a test rather than being absorbed

**Per-turn planning went from a 412 ms mean to 569 ms**, measured over twelve `BoutRunner` steps on
the bout board at seed 4242, at the Pass B commit and again after. `PlanPacer`'s budget is 400 ms,
**so it was already being exceeded before this pass** — Pass C made the aborts earlier and more
frequent, and `test_ai_batch_yield.gd` went red because a budgeted run stopped matching an
unbudgeted one.

Three optimisations landed inside the pass and are counted in the numbers above: `RayCaster.
obstructed` is an any-hit loop with early exit rather than the nearest-hit march (999 -> 152 usec),
with a ground-plane reject in front of the per-cell height lookup and a vertical-band reject in
front of building a surface's box placements; `Cover` hoists `units_visible_to` out of its per-cell
walk; and `SightSpans` is derived once per planning ply and shared across every field that ply
builds, which takes the AI's field cost back toward parity.

Re-taken at the end of the block: the full gate is **682 s at Pass B and 770 s with Pass C**, a
**1.13x** whole-suite cost with one failing test. **A mid-block figure of 2.2x was wrong** — it
compared `SUITE-PROFILE.md`'s baseline, generated at an older commit, against a run taken before
these optimisations existed.

**It is left red and reported rather than tuned away.** `BR58.01` carries the numbers, the four
options considered, and why the most likely right answer — making the pacer count candidates
instead of milliseconds, so a viewed bout is seed-reproducible again — is a decision about the AI's
own guarantee rather than a taskblock-58 edit. Raising the budget or rewriting the test would both
have hidden that the AI now searches less on real hardware.

#### Cover reads the field instead of walking its own line

`Cover.is_covered_from` called `LoS.has_los` **per candidate cell**, inside the scoring loop
taskblock-43 measured at 98.3 ms — and that call was itself a duplicate, since a field for the same
threat had already computed the answer for every cell that turn. It takes the field as a **required**
argument now, because an optional one is two branches deciding the same thing differently depending
on what the caller happened to be holding.

**Cover's own flatness is untouched and still open.** The blocker/unit walk takes two `Vector2i` and
has no height in it. This fixed *what cover sees*; making cover directional in 3D is `PLAN.md`'s own
item.

#### A placement has a position; a cell does not own it

`Grid.surfaces` was `Dictionary[Vector2i, Array[Surface]]`, so a floor's position was its dictionary
*key* — it could not exist except as something a cell held, and moving one meant delete-and-re-add.
The store is a flat `Array[Surface]` now, each carrying its own `cell`, and the per-cell dictionary
is an index over it. **`surfaces_at()` kept its exact contract**, which is what made the swap cheap:
thirty-one call sites are untouched, and the five that walked the dictionary directly got
`placements()`. `RayCaster` came out slightly *cheaper* — one flat walk instead of a dictionary
lookup per cell per ray cast.

**`GROUND` now means "attaches to nothing"** rather than "attaches to the cell", which stopped being
expressible once a placement carried its own position. The alternative on the table — retire it for
a support requirement — needs the support graph this pass explicitly does not build. The
one-per-cell refusal survives restated as occupancy, **deliberately not loosened to per-height**:
that is a behaviour change wearing a refactor's clothes, and it is queued instead.

**No behavioural difference, checked rather than asserted.** A seeded bout on `proving_ground` was
digested at the previous commit and again after: board hash 3747730889 over 190 cells, bout hash
989906744, 46 turns, 752 events, all four units' end cells and hp identical.

#### A pick reports the face it struck

`UnitPicker.ray_box_hit` has reported the struck face since taskblock-52, and both search loops above
it threw it away — so a caller that needed a face had to cast a second ray, which would have been
free to disagree. `UnitPicker.hit` and `PartPicker.hit` carry `normal` out now, `SelectionTarget`
keeps it across `from_pick` / `to_hit` / `from_hit`, and `TacticsController._cell_at` puts it in the
hit dict. **Nothing new is computed.** A miss carries no `normal` key rather than `Vector3.ZERO`,
because a zero vector survives a `dot` and reads as an answer.


### UI review, reserve items — two fixed, one handed back

**The performance readout survives an overlay swap.** `BattleScene.set_overlay` tears every module
down and builds a fresh one, so a readout that always came back hidden lost the state on every
swap — and swapping to the spectator is exactly what you do to watch a framerate you just turned on
in the player view. A `static var` on the module, because **the state belongs to the session rather
than to any one surface**: it is the same readout over the same `PerfStats` whichever mode is
mounted, which is the reasoning that made it its own module rather than the debug panel's child.

**The combat log stops rebuilding every line's offset on every mouse motion.**
`_on_log_hovered` fires per `InputEventMouseMotion` and called `_line_offsets()`, which walked the
whole label calling `get_line_offset(i)` once per line. Cached between text changes now, keyed on
the line count so it cannot go stale and point the hover preview at the wrong line.

**That is a removal of wasted work, not a framerate fix, and the entry says so.** `BR57.03` stays
`Active`: CC cannot see a framerate, and a performance claim is a number rather than an
adjudication. The next suspect is named there — `TacticsController.update_hover` ray-picks against
every unit and blocker per motion event, and `BR35.01` already had to put a cheap reject in front of
that test once.

**The inspect viewer's flat unit shading is unresolved, and the earlier fix was symptomatic.**
Raising the preview camera's ambient made it brighter and still flat; *every face identically
shaded* means the directional light contributes nothing at all, which is a different fault from
"lit from an awkward angle". `BR57.02` records the four suspects already ruled out and the asymmetry
worth chasing — it reproduces only on units, and a live unit is the only subject that takes the
isolate-camera path rather than the fresh-copy one.

### UI review passes 4 and 5 — one control per surface, and the surfaces become windows

**Two more supervisor passes**, plus the one review-chat note that produced the most durable thing
in any of them.

#### A general overlap check, which is the note worth reading

> *Collision testing is per-case, not general... There is no test asserting that no two surfaces
> overlap in a given mode. CC's own finding shows why that matters: `SuiteRunPanel` had reached into
> the action bar's band for two passes, invisible until the spectator cluster moved into the same
> space. That was caught by a test written for a different pair, by luck of adjacency.*

`test_surfaces_do_not_overlap.gd` resolves **every mounted module's real rect** in each mode and
asserts no two intersect except by declaration. **The exception list is the substance** — eight
pairs, each with its reason, and an exception is a *pair* rather than a surface, so a module excused
for sitting under the click-through announcement band is not thereby excused for landing on the
combat log. Two self-checks keep it honest: every declared exception must name modules some mode
mounts, and the comparison is exercised on rects it should reject.

**It found something on its first run.** `control_toggle` and `turn_controls` reported identical
rects — not a collision but a *shared node*, since Watch inserts into the turn column rather than
building beside it. Declaring that pair as an exception would have hidden a real collision between
them if they ever stopped sharing, so the check skips identical nodes instead.

#### One control per surface

`IV` is gone: Inspect's `INS` governs the panel and the viewer, which are one inspector as far as a
player is concerned. `REP` no longer appears where the panels are not constructed — the player view
never builds them, so a button was being offered for a surface that was not there.

**Every border reads `ViewModule.is_showing()` per frame** rather than being set at press time. A
border set by a press is a claim about the press; Inspect opens from a board click, the keybindings
sheet from the H key, the debug menu from its own control. The bar's own toggle is built last and at
70% size, and the border is a 50% grey rather than the alert tier.

#### The surfaces become windows

The test-suite box takes Inspect's own rect and draws over it — **draw order is child order**, so
"over" is set by the mode declaring `replay` after `inspect` rather than by a z-index nobody would
find. The watched run's table, previously a loose panel anchored centre-right, is adopted into its
column. Its title bar is the combat log's shape with `[?]` and `[x]`.

The keybindings legend is a centred panel that blocks scroll as well as clicks (it was `STOP` for
clicks, but an unaccepted wheel event still reached `CameraRig`). The Inspect viewer's frame is
oversized **as** the border rather than carrying a stroke. The combat log is padded off the screen
edge as well as off the bar. The editor and spectator modes both gained the keybindings sheet, and
the spectator gained `inspect_viewer` — it had none, so `InspectPanel` built its own docked one and
the mode was still showing the pre-Pass-C3 layout.

#### The editor inherits a world it did not build, and that is now three defects

Extraction markers survived into the editor because `sync_board_view` passes
`mission.team_extraction_cells`; an authored board has no mission, so it builds with none. **That is
the third symptom of one cause**, after the units at their last cells (`BR57.01`) and the movement
tiles. `EditorModule`'s header carries the table now: each fix is right on its own terms — do not
draw what is not there — and none of them touches the cause. **Expect a fourth.** The entry point
that builds a world with no bout in it is `PLAN.md`'s *Main menu*.

#### The inspect viewer's darkness was structural

`BR48.01` made the viewer share the battle's world so it can point at the *real* unit at its real
board position — which means it withdraws its own light, because adding one there would light the
whole battle. The subject is then lit by the board's single directional light, from the board's
angle, seen from a camera at a different one. **The camera's own `environment` override is the one
seam that cannot leak**, so `PREVIEW_AMBIENT_ENERGY` (0.9 against the board's 0.35) goes there, with
a test pinning that the default stays the board's.

### UI review passes 2 and 3 — one control per thing, and the surfaces get edges

**Two more supervisor passes over the layout**, worked the same way as the first: each item names
what was seen on screen.

#### One kind of button, one control per thing

**Every control in the UI-buttons cluster is summon/dismiss.** *"I seem to have two different
'classes' of buttons, a 'summon/dismiss' style button and then a 'disable/enable'? There should be
one."* The module toggles were `toggle_mode` buttons carrying a stuck pressed state while Inspect,
the debug menu and the keybindings legend were plain presses. All of them are plain presses now, and
**a border shows what is up** — *"Button 'on', button is highlighted and module is visible."*

**A module that owns a control is no longer given a second one.** `ViewModule.provides_own_button()`
— the cluster swept every collapsible module into a toggle, so Inspect had **three** buttons (its
own `INS`, a derived `INS` that collapsed instead of opening, and the viewer's `IV`) and the debug
menu had two. The abbreviation collision was predicted in `UiButton.abbreviate`'s own header and
happened anyway.

**Hover is 0.5 s on chrome buttons**, stated per caller rather than baked in: `HoverDwell.delay` is
per instance and `TooltipView.show_data` takes a wait. **Still one clock** — taskblock-57 required
the tooltip and the log's overflow preview to share a *mechanism*, not a duration.

**Dismissing the action bar no longer takes the button that brings it back.** The collapse hid
`bar_root`, and the UI buttons are published off it. It hides `backing` alone now, and the row gives
up its height so the satellites drop to the bottom edge rather than floating an eighth of a screen
above it.

#### `top_left_controls` and `TopLeftControls` are deleted

Inject is obsolete (the `DBG` square opens the debug menu), New Battle is retired outright, and
Watch / Assume Control moved into the turn-order column. **With all three gone the cluster held
nothing**, so the module and the class it wrapped are both deleted rather than left as a container
of nothing.

#### The surfaces get edges

Inspect is padded off its corner **and inside itself**; the Inspect viewer sits in a bordered,
padded frame instead of being a bare subview over the board; the editor's details panel is padded
all round and its rows clip rather than setting the panel's width. The keybindings legend is a
centred panel with a background and an `[x]` — it needed re-centring on `resized`, because
`set_anchors_preset` works off the rect a panel built that frame does not have yet.

The editor gained the debug menu it had no way to reach, the tile picker offers only `GROUND`-
attaching parts, a wall placed on bare ground brings the last floor used with it, and the combat
log's `[+]` names itself.

#### The defect worth the most

**Folding Assume Control into `TurnControlsModule` broke the spectator's central contract**, and the
suite said so immediately: eight tests in `test_spectator_overlay.gd` went red at once, with bouts
advancing two turns per step and clicks landing on a board that had moved.

`TurnControlsModule` is `Kind.INPUT` — End Turn resolves against the authoritative `CombatState` —
and **`ViewMode.has_unit_input()` answers by building each declared module *unmounted* and asking
`kind()`**. A module cannot make that answer depend on finding a `TacticsController`, because at
that point it has no context to look in. So a spectator declaring `turn_controls` claimed unit
input, and `_on_battle_loaded` drove the AI batch itself.

`ControlToggleModule` is the fix and the reasoning is the design: **handing control over is not unit
input** — it changes who plays the squad rather than queueing anything against one — so it is
`DISPLAY`, and both modes may have it. It inserts itself at the top of the turn column when one
exists, because `ACTION_BAR_RIGHT` is an `HBoxContainer` and two modules each adding a column put
Watch *beside* End Turn rather than above it (measured: y=1048 against 1026).

### The first UI review pass over taskblock-57's layout

**The supervisor's first look at the shipped surface**, worked as a review rather than as a
taskblock. Each item below names what was seen, because none of them came from a spec.

**The bar is the centred item now, not the cluster around it.** *"Action bar needs to be the
centered item, with the combat log to the side of it."* `BarModule`'s rows are plain `Control`s and
every piece anchors against `BattleLayout`'s own band — the bar on the centre line at the width the
table gives it, each satellite pinning an edge to one of the bar's edges and growing away.
**The first attempt used two equally-expanding wings and did not work**: an `HBoxContainer`
distributes only the *leftover* width equally, on top of each child's own minimum, so a 520 px log
on one side still pushed the bar 48 px right of centre. Measured at 1008 against a screen centre of
960; it is 960.0 now and stays there when a 300 px surface is added to one side only.

**The bar is a fixed eighth of the safe height, and it has a background.**
`BattleLayout.ACTION_BAR_HEIGHT` was 96 px and is `ACTION_BAR_HEIGHT_FRACTION = 1/8` — a pixel
constant cannot be a fraction of the screen at more than one resolution. **The boxes are fitted into
the band rather than the band growing to the boxes**: `ActionBar.setup` takes a box side and
`ActionBarModule.box_side()` derives it, because ten 108 px items over two rows is 216 and the whole
bar is 135. The background is a real `StyleBoxFlat` on a panel the bar owns.

**Unit resources are centred over the bar.** The slot spans the bar and centres its content;
previously it sat at the slot's left edge, measured at x = 541 against a bar centre of 960. The UI
buttons pin their *right* edge to the bar's right edge — a surface **within** the bar's span rather
than beside it, which is a different pin from the one the turn controls use and was 332 px out.

**The UI-buttons cluster is square abbreviated buttons with hover descriptions.** *"All toggles and
descriptive text should be replaced with square BUTTONS with an up-to three letter abbreviation on
them. Hovering them for 1.5 seconds should show a description."* `UiButton` is one class the three
modules that put controls in that row all use — `UiButtonsModule`, `InspectModule` (which owns its
own button because it owns the enabled state that follows the selection) and `ControlsLegendModule`.
**A row of controls that do not agree on their own shape is what the review found**, and a helper
each of them called is a shape three files can drift from. Abbreviations are derived from the id
(`action_bar` → `AB`, `inspect` → `INS`), so no module is named. **The dwell is not implemented
there**: `TooltipView.show_data` already waits on the shared `HoverDwell` clock, and a second timer
would be the third. `tooltip` joined the spectator and editor module sets so their clusters can
describe themselves.

**The editor's section-details panel fits its slot.** *"Too wide. Should be roughly half as wide as
it is tall, and given a slight padding off that corner."* The slot always was half as wide as tall;
the panel was 516 px in a 360 px slot, because a `PanelContainer` takes its content's minimum width
and **a `ScrollContainer` reports its content's minimum on any axis it cannot scroll**. Enabling
horizontal scrolling drops that to zero. `inspect_viewer_rect` is padded off the physical corner —
it escapes the safe rect, so its corner is the window's.

**Verbose no longer unfolds anything.** *"Verbose is currently unfolding elements which is not its
purpose. Unhook it from that, and leave it open for later."* Pass C read the table's checkbox as
meaning "every group drawn open"; it does not. The flag, the checkbox and the signal all stay and
**nothing reads the flag to decide what is drawn** — authored and unread, the same shape as
`Announcement`'s `sound` field. A group is open because the reader opened it.

**The combat log's overflow preview has a background bigger than its own text**, so a revealed line
is not tangent to the lines above and below it, and the label is offset by the margin so the glyphs
still land on the line they are revealing.

#### Defects found

- **`SearchableList` was not filtering at all, and the test that covered it passed.** `queue_free`
  is deferred to the end of the frame, so the old rows were still children — and still drawn — while
  the filtered ones were appended after them. Typing `barrel` into a four-entry list left **five**
  rows on screen. `remove_child` before `queue_free` is the fix. **The test read `shown_ids()`,
  which reports the module's own `rows` array — correct throughout. Nothing asked the container what
  it was actually showing**, which is the failure this project keeps having to relearn: read the
  real node back.
- **`BR57.01` — units stood at their previous bout's cells in editor mode.**
  `BoardSwap.swap_board` **returns** the ids of units it could place nowhere and `EditorModule`
  discarded that value, so on a board with no floor yet every unit kept its cell from the last bout
  and was still rendered there. The views of stranded units are hidden now — *do not draw what is
  not there*, the same rule the risers and the ground quad went for. `SUPERVISOR`-owned and marked
  `Pending`; the real answer is an entry point that builds a world with no bout in it, which is
  `PLAN.md`'s *Main menu*.

### taskblock-57 Passes G1, G2 and H — three bars, the editor's own surfaces, and the gizmo

**The block closes here.** G1, G2 and H land the two `PLAN.md` NEXT items the block was opened for
(*The UI layout*, *The manipulation gizmo*), and every line of the taskblock's acceptance is met.

#### Three action bars, not one with three contents (G1)

**`BarModule` owns the placement and nothing else.** All three bars occupy `ModuleSlots.ACTION_ROW`
and publish the same four satellite slots Pass B defined — because *"four surfaces pin relative to
the action bar"* is a fact about **where the bar is**, and every mode's bar is in the same place.
`_fill_bar` is the only hook a concrete bar overrides.

| mode | bar | shape |
|---|---|---|
| player | `ActionBarModule` | square items, **left-aligned, two rows**, small padding |
| spectator | `SpectatorBarModule` | the transport controls and the old top-left cluster |
| editor | `EditorBarModule` | labelled buttons — place/tiles/cover, claims, save, load, run, undo |

**The pass title names the failure mode**, and the shape is the answer to it: one bar reading which
mode it is in would be a fourth answer to "what is the surface right now", after `ViewMode`,
`ModeChrome` and the module set. `test_three_bars.gd` asserts the three are distinct scripts *and*
that all three resolve one slot, because either alone is satisfiable by the wrong design.

**The player bar went to two rows and it fixes a measured overflow.** Ten 108 px boxes on one row
are 1080 px against a bar the table gives 960 — it overhung its own bar at 1x and by more at any UI
scale above it. Five columns over two rows is 540. `ActionBar.setup` now takes any `Container`; it
never cared what arranged the boxes.

**The spectator's controls moved across the screen and the two modules that draw them did not
change a line.** `SpectatorBarModule` publishes `PACING_ROW` and `TUNABLES` inside itself, so
`PlaybackModule` and `TopLeftControlsModule` land in the bar without either learning a bar exists —
which is the module system's own premise (*"where a panel sits is a property of the surface, not of
the panel"*) applied to the one case it was written for. **That is Pass D's last unlanded line**,
which had nowhere to go until this bar existed.

**`SearchableList` is one widget with two callers** — *Place Items* over the parts pool and *Load*
over the map and section catalogs. `SearchFilter` (logic, pure) is the search rule: every
whitespace-separated term must appear, `_` read as a space, empty query matches everything. **Load
had no affordance at all before this pass**; `EditorModule.open` was reachable only from a test.

**A third placement-kind button exists that the taskblock does not name.** It asks for *Place Items*
and *Tiles*; the editor could author **blockers** before this pass, and naming two of three kinds
would have deleted every wall and barrel an author can place. `PLACEMENT_LABELS` is an open table
over `MapPlacement`'s own kinds with a derived fallback, so a fourth kind grows a button.

#### The editor's own surfaces (G2)

**The coordinate readout is what Pass C's split was for.** `EditorCoordsModule` declares
`ACTION_BAR_TOP_LEFT` — the same slot `unit_resources` declares — and the editor mode declares one
and the player the other. *"Same slot, different module"*, and it cost a `preferred_slot()`. It
follows `board_inspect`'s new `hovered_cell` signal, emitted off the ray that handler already casts,
rather than casting a second one per frame.

**The section-details toggle cost a `preferred_slot()` too.** `EditorModule` declares
`INSPECT_VIEWER`, which is left-edge-pinned, so `is_collapsible()` answers true from the slot alone
and `UiButtonsModule` builds the checkbox by sweeping for exactly that. **No line in either file
names the other** — the collapse rule from Pass A doing the job it was built for. Folding the panel
leaves the authoring verbs working, because they are on the bar.

**Validation warnings reach the combat log, and the significant ones announce.** `EditorLog` emits
one `LogEvent` per warning and tags the significant ones — **one emit, two views**, Pass E's rule, so
nothing can put a line in one and not the other. *"The significant ones"* is not invented here: it
takes a distinction the code already draws, `EditorController.navigability_warnings()`, which is the
category describing a board a bout cannot be played on. **Only what is new is said**, because
`refresh()` runs after every edit against a list recomputed whole.

**The current tool is carried by the bar's own highlight**, which is one of the two options the
taskblock offers by name. `EditorModule.active_tool` became a setter emitting `tool_changed`, so a
tool set from anywhere highlights identically — and the `place` tool lights the *kind* button that
says what the next click will author, since there is no unqualified "Place" button on this bar.

#### The manipulation gizmo (H)

**The drag math is logic and the scene decides nothing.** `GizmoDrag` is screen delta → axis delta →
snapped value, and the one thing it cannot work out for itself is `axis_on_screen` — the screen-space
vector one world unit along the axis covers, which only a projection can answer. **A vector per
axis, not a pixels-per-unit scalar**: a perspective camera foreshortens differently per axis and per
position, and an arrow seen almost end-on covers almost no pixels at all.

**The snap is applied to the resulting value, never to the delta.** Snapping the delta lets two
drags of 0.04 accumulate to 0.0 while the handle has visibly moved, and lets a value that started
off-grid stay off-grid forever. Every value the gizmo produces is a multiple of 0.1 by construction,
swept across 501 pixel deltas rather than sampled.

**Handles are boxes, so picking is `UnitPicker.ray_box_t`** — the project's one ray-vs-box test,
which the taskblock names as the reuse to make. Translate is three arms; resize is **six** face
cubes, because dragging the top up and the bottom down are different edits with the same axis and
the same direction.

**It is armed by a tool, and that is what keeps it from being a second selection system.**
`EditorModule.apply_tool_at` — the one router every board click in the editor already goes through —
hands the gizmo a cell when the `gizmo` tool is active. The gizmo is told; it does not look. The one
event it consumes is a press **on its own handle**, because a handle is drawn over the board and a
grab must not also author on the cell underneath.

**A refused resize leaves the claim exactly as it was.** `Gizmo.resized_box` returns null for a drag
that would collapse or invert the volume, and nothing is written — *"refused rather than clamped
silently"*, because a clamp is indistinguishable from a laggy drag where a face that simply stops
moving is unambiguous.

**Input routing became a walk.** `ControlOverlay._unhandled_input` used to reach for `board_inspect`
by name; it now offers the event to every mounted module in declaration order and stops at the first
that consumes it. `ViewModule.handle_input` returns false by default, and `BoardInspectModule`
returns false always — it never claims exclusivity, so ordering is what decides.

#### Defects these passes found in their own work

- **`Gizmo.resized_box` moved the face nobody dragged.** Snapping the extent and the centre
  independently looks equivalent to snapping the face and is not: an odd number of steps moves the
  centre by half a step, and snapping that shifts the box. Dragging the bottom of a 2.0-tall claim
  down by 0.5 left its top at **2.05**. Caught by the test asserting the anchored face is an
  invariant; it snaps the dragged face and derives the rest now.
- **`SuiteRunPanel` overlapped the spectator's cluster the moment the cluster moved into the bar.**
  A 560 x 331 panel anchored bottom-right reaches into the action bar's own band, and had always
  done so; nothing showed it while the cluster was in the opposite corner. Moved to the top-left,
  which is free in every mode that constructs it.
- **Two tests were reading a coordinate space that had stopped meaning what they assumed.** The
  spectator log's resize tests measured `position` against a margin container whose own origin moves,
  and reported the bottom edge falling 100 px while the panel was in fact still hard against the
  bottom of the bar. Read off `get_global_rect()` now — the same lesson the block already recorded
  once, one container over.
- **A test's own fixture, twice.** The warnings test authored a pit with no spawn marker, and
  `navigability_warnings` floods from a spawn — so it got an empty log and read it as "the warnings
  never reach the log". And the dedup test counted zero because the empty board's warnings are
  reported by the `refresh()` inside `_mount`, before any test can attach a sink.
- **`"%s" % an_empty_Array`** is *"not enough arguments for format string"* — `%` treats an Array as
  the argument list. An engine error on the run that passes, which GUT counts as a failure. The same
  shape as `%v` on a `Rect2`, one container over.

### taskblock-57 Passes A–F — the layout, live; the retirements done

**SUPERSEDED IN PART — see the taskblock-57 Passes G1, G2 and H entry above.** This entry was
written while the block was open and said so; G (the editor surface) and H (the gizmo) have since
landed and the block is closed. The spectator and editor chromes it describes have both moved to
`BATTLE_LAYOUT`, and the action bar it describes is one of three.

**The layout is live**: `ViewModes.player()` uses `ModeChrome.BATTLE_LAYOUT`, so every
surface in the block's placement table has moved to where that table puts it, and the modules the
table does not name have been retired.

**`UiLayout` (`src/logic/`, pure) owns the two coordinate spaces.** `safe_rect` is the largest 16:9
rect fitting inside the screen, centred — 16:9 at every ratio and never larger than its screen.
`screen_rect` is the window. `crush_factor` is how far a narrower-than-16:9 screen stretches back
over the bars `safe_rect` would leave: **ultrawide letterboxes and narrow ratios crush**, because an
ultrawide has more room than the layout was authored for while a 4:3 screen is short of exactly the
axis the bars would waste.

**A tension in the spec, resolved and flagged rather than papered over.** taskblock-57 A1 says
narrower ratios "crush rather than clip"; its own test says `safe_rect` "is 16:9 inside any screen
ratio and never exceeds it". One rect cannot do both. The rect keeps the guarantee the stated test
names and the crush became a factor applied to what is drawn into it — reversible, since one
function changes if the rect itself should fill.

**Escaping the safe rect is a property of a slot**, not a comment in a panel:
`ModuleSlots.escapes_safe_rect` / `edge_of` / `is_side_pinned` / `rect_for`, plus
`ModuleContext.slot_rect`. **UI scale** is a `static var` defaulting to 1.0 with one place reading
it, headed for an options menu that does not exist. `ViewModule` gained `preferred_slot()` and
derives `is_collapsible()` from it, so a module answers "must I be toggleable" from where it sits
rather than from a flag that can drift.

**A module may be a slot provider — the block's one named new mechanism, built general.**
`ViewModule.published_slots()` returns `StringName -> Control` and `ControlOverlay` publishes
whatever any module returns, immediately after mounting it. **No branch anywhere names the action
bar**; it is simply the first module to use the hook, publishing `action_bar_left`, `_right`,
`_top_left` and `_top_right` as real children of its own subtree so the four surfaces that pin
relative to it move with it for free. Ordering is the rule that already existed — a provider is
declared before its dependants, as `unit_input` already is before every display module.
**taskblock-56 Pass C's stand-alone acceptance is not weakened**: a mode declaring the combat log
and no action bar mounts both, and an absent action-bar slot falls back to `ui_root`.

**`BattleLayout` (`src/logic/`, pure) is the placement table as arithmetic**, with
`ModeChrome.BATTLE_LAYOUT` a thin builder over it. That split is the point — *"is it in its declared
place"* is answerable headlessly, where a chrome full of anchor presets is testable only by
screenshot. Five new slots (`inspect_panel`, `inspect_viewer`, `debug_menu`, `perf_monitor`,
`announcements`), with exactly three declared as escaping.

**The debug-menu budge takes a floor AND a measurement, because neither alone is right.** With the
table's own fractions the menu and Inspect **abut exactly at 1x**, by arithmetic and not by luck:
the menu ends at `1/2 + 1/8 = 5/8` of the safe width and Inspect begins at `1 - (2/3)(9/16) = 5/8`.
So a purely measured budge is **zero at the only scale anyone can currently play at**, and a fixed
distance is too small everywhere else — the 220 px first written clears neither the 480 px overlap
at 1.5x nor the 960 px at 2.0x. C1 shipped the measured-only form and flagged that it could never
fire; **the supervisor's call was to floor it**, given as `X + X*(SCALE-1)` — which is `X * SCALE`,
i.e. exactly `UiLayout.scaled(X)`, so it goes through the one place that reads UI scale rather than
adding a second scaling rule. `debug_menu_budge_distance` is `max(floor, overlap + padding)`. The
floor's magnitude is eight of the table's own padding units and is **flagged tunable, not design**.

**Two guards fired during the block, both by design.** Pass A's *"nothing escapes yet, the three
arrive in Pass C"* failed when C1 added them — now pinned at exactly three. And GUT called the first
side-pinned sweep *risky — did not assert*, correctly: no module declares a slot until C2, so it
ranged over an empty set. It now also asserts the set equals a pinned `EXPECTED_SIDE_PINNED`, which
**C2 must update deliberately**.

**REVERSED IN C2a — see the taskblock-57 Pass C entry below.** C1 recorded that the action bar and
its satellites were "deliberately absent from `SLOT_EDGES`, so they are not collapsible". That was
already inconsistent with the data shipped beside it (`SLOT_EDGES` carries `ACTION_ROW: EDGE_BOTTOM`,
and `test_slot_properties.gd` pins "bottom is a side too"); nothing surfaced it while no module
declared a slot. The action bar **is** collapsible.

### taskblock-57 Passes D2, E and F — aim is a mode, the retirements land, announcements view the log

**Pass F ran before the rest of D, and the reason is a coupling the taskblock's ordering does not
show.** `stat_panels_module` owned `AimView`; Pass D retires `stat_panels`; Pass F needs the aim view
to survive. Running F first turned a collision into an ordinary move.

**`AimView` belongs to `UnitInputModule` now** — it is `Node3D` world geometry (the window quad, the
decal, the targeting line) driven entirely by that module's `TacticsController`, and the taskblock
says outright that the aim view and dartboard **are not UI modules and do not become ones**. A module
that turns off while aiming was the wrong owner for the thing you aim with. Its text readout is a UI
panel and became `AimReadoutModule`; the two are joined at `link()` time and either end may be absent.

**`ViewModes.AIM_MODULES` is the table entry**: five of the player mode's seventeen. **The ones that
stay are there for correctness, not taste** — `combat_log` in particular, because its sink attaches
at mount and is rebuilt *empty* on remount, so turning it off and on would clear the visible log
every time anyone aimed.

**`ControlOverlay.switch_mode` diffs the sets, and that is the design rather than an optimisation.**
The switch is triggered *by* the aim, so rebuilding the surface would construct a new
`UnitInputModule`, a new `TacticsController` and a new `aiming_at` — destroying the aim in order to
render it. Modules in both sets are not suspended, not rebuilt, not touched at all. **This is not a
suspension mechanism**, which the taskblock rules out: a module leaving the set is genuinely
unmounted and freed, and a departing provider's published slots are erased with it.

**Which mode to switch to is data** (`ViewMode.aim_mode_id`), so no branch in the host names the aim
surface. The chrome is deliberately not rebuilt, so a switch between differing chromes is refused
loudly rather than half-applied.

**`queue_panel`, `stat_panels`, `QueuePanel` and the `_legacy_readout` chrome are deleted**, along
with `single_unit`, `TurnPolicy.SINGLE_UNIT` and `ControlOverlay.controlled_unit`. The collapsed
player mode pre-selects whichever unit it drives, which is the one thing `single_unit` actually did.

**A retirement lost coverage twice, and only one loss was named.** The taskblock flags
`queue_panel`'s confirmation role (Pass D1's combat-log entries). It does not mention that
`stat_panels` also owned the **aim readout** — hence `AimReadoutModule` — nor that **"Resolve to
Here" (`BR27.08`) was a per-row button on the queue panel**, so retiring the rows retired the only
way to reach the verb. `keep_queue_suffix` and `queue_partially_resolved` are untouched and still
tested: the logic survives with no UI, and it is queued in `PLAN.md` rather than absorbed silently.

**Floor tiles are inspectable and gated**, as a row in `DebugUiElements` rather than a hardcoded
checkbox — *"rare targets, floor tiles especially, should need enabling from the debug menu, or every
misclick lands on the floor."* Off by default.

**Announcements are a second VIEW of the combat-log stream, never a second message path.** One emit;
`CombatLog` fans out to its sinks as it already does; `AnnouncementFeed` is one of them and carries
**the only thing the log lacks — a lifetime, which belongs to the view.** *"In one and not the
other"* is not a bug guarded against, it is a state nothing can reach because nothing chooses.
Priority is a data table (duration, colour, `sound`); an unknown priority is **shown with the default
treatment rather than dropped**; the `sound` field is authored and unread, with a test that greps
`src/` for readers. Left-aligned always, which is the simpler option the taskblock explicitly permits.

#### Defects these passes found in their own earlier work

- **`AIM_MODULES` had no aim readout.** D2 built `AimReadoutModule` precisely so retiring
  `stat_panels` would not take the READING/RESOLVES text with it, and the edit adding it to the set
  silently did not apply. **The D2 gate stayed green because the only assertion was
  `aim.modules == AIM_MODULES`** — true of any list whatsoever, a tautology dressed as coverage. The
  set is pinned by name now.
- **A selection nobody was told about.** The pre-selection reached straight into
  `selection.select()`. `ActionBar`, the pips and the overlays all refresh on `selection_changed`, so
  a turn began with a unit genuinely selected and an action bar still drawing the empty state —
  clicking a slot armed nothing. `TacticsController.select_and_announce` makes the announcement part
  of making a selection.
- **The pre-selection stomped deliberate selections**, because the trailing auto-select of an awaited
  AI batch could land after a player's own click and disarm it. It fills an EMPTY selection only.
- **`select_and_announce` emitted twice** — it called `selection_changed.emit()` and then
  `_refresh_overlay()`, which emits it too. Caught by a test that counted.
- **The announcement feed reported a redraw only on expiry**, so a new announcement did not draw
  until an unrelated one aged out. It would have read as "announcements are late".


### taskblock-57 Pass C (C2a, C2b, C3) and D1 — the modules move, and queueing becomes a log line

**The placement table is real on screen.** Every surface in it declares `preferred_slot()` and lands
on `BattleLayout`'s own rect, asserted end to end by reading mounted panels' `get_global_rect()` back
rather than re-deriving them (`test_battle_placements.gd`).

**Three modules are new because three surfaces had no module of their own**, and a module declares
one slot — so a surface welded inside another module could never be in its own declared place.
`unit_resources` takes the AP/MP pips out of the action bar (G2 replaces that exact surface with a
coordinate readout in editor mode — *"same slot, different module"*, which is impossible while it is
welded inside a third). `perf_monitor` takes the readout out of `debug_panel` and takes the FPS
figure off the combat log, so there is one framerate surface over one meter. `ui_buttons` is what
makes A2's collapse rule **reachable** — the flag and its hook had existed since Pass A with no
control that could reach them.

**`ModeChrome.relayout` / `ViewModule.relaid_out` — a small new mechanism, named rather than built
quietly.** The battle layout places absolutely, which is what makes it testable arithmetic; absolute
positions do not follow a resized window where the anchor-preset chromes did. The hook exists rather
than each module connecting to `resized` itself because the regions must move before anything
re-derives from them, and two handlers on one signal would settle that by connection order.

**`_legacy_readout` is a deliberately labelled temporary** carrying `queue_panel`, `stat_panels` and
`controls_legend`, which the table does not place because Pass D retires or relocates all three.
Without it, switching the chrome would strand all three at (0,0) on top of each other. **It is
deleted with them.**

**Pass C's behaviours.** End Turn asks first when AP or MP would be wasted (`TurnEndPrompt`, logic —
it reads the PREVIEWED unit, since a queued move has not spent its AP yet and prompting off the raw
unit would fire nearly every turn). The combat log minimises to a **button**, 520 px to 35, flush
against the bar. Word wrap and verbose are checkboxes; verbose is emitted, not applied, because what
it means is the sink's business (every fold group drawn open, still presentation-only, tb22 F2).

**`HoverDwell` — one timer, two behaviours, which the taskblock asks for by name.** 1.5 s, up from a
0.4 s that was flagged in its own comment as a guess. A shared *object* rather than a shared
constant: a constant leaves each caller writing its own accumulate-and-compare, and this project has
produced two visibility systems, two aiming paths and two overlay hierarchies from that shape. The
**content models stay apart** — the tooltip renders `TooltipData` beside the cursor and says what a
control will DO; the log's preview shows a line verbatim over that line and says what it already
SAYS. `LogLineProbe` carries the decidable half so the preview is testable without a laid-out
`RichTextLabel` in a live window.

**`BotViewer` — the 3D view, out of `InspectPanel` and into the table's own top-left row.**
Moved, not rewritten: both rendering paths, the isolate cull masks and the `BR48.01` lighting
withdrawal are the same code. `inspect_panel.gd` goes **992 → 756 lines**, which was the other
reason: the block's own first edits pushed it over the 1000-line limit. One class, two placements —
the panel takes a viewer if its host supplies one and builds its own if not, so every existing test,
the spectator and editor modes, and the stand-alone acceptance keep the docked layout unchanged.

**D1: queueing is legible in the combat log**, which is the replacement the taskblock requires to
land *before* `queue_panel` retires. `QueueLog` emits `unit N queued a move to (x,y)` /
`unit N cancelled move`, folded by `LogFold` into one drillable counted row per run. **A move names
its destination** because "queued a move" without a cell fails at the one thing the line exists for.

**One path in, which is the reason one line covers everything.** Before this there were nine ways to
enqueue — five `queue_*` methods on `SelectionController` and four direct
`selection.current_queue().enqueue(...)` calls in `TacticsController` — and a confirmation at each
would have been nine chances to forget one. `SelectionController.enqueue` is now the only one, and
it logs only what the queue actually accepted. **The AI's queueing is deliberately not logged**: the
entries exist to confirm a click, and a planner enqueues and discards while it evaluates.

#### Defects found by tests that reading the code would not have caught

- **The action bar's CLUSTER is 1740 px wide, not the 960 the table gives the bar.** Anchored at the
  region's left edge it ran to x=2220 on a 1920 screen, putting End Turn at x=2142 — off the
  display. It centres on the bar's band now.
- **`context.slot()` falls back to `ui_root`**, so "was I placed?" came back true in every mode
  *without* a battle layout: Inspect stretched over the whole screen in spectator and editor, and
  the debug menu landed at (0,0) on the spectator's own cluster. Asked of `slots` directly now.
- **`PerfPanel` is a plain `Control`**, so its outer rect never took its body's height. Harmless
  hanging from the top; pinned to the bottom corner it drew its body from y=1080 *downward*.
- **`set_anchors_preset` preserves the rect measured against a not-yet-laid-out parent**, which put
  the readout at x=-420. All four anchors and all four offsets, explicitly — the third time that
  lesson has been learned in that file's history.
- **`Camera3D.look_at` needs a live tree.** `InspectPanel` got that for free by building the viewer
  inside `setup()`; construction moved earlier, so the framing call is deferred to `_ready()`.
- **The queue confirmation rode into the RESOLUTION event stream.** `TacticsController` opened its
  `MemorySink` *before* queueing the final action, so `turn_ended` — which `LogPlayback` replays as
  the animated resolution — carried a TACTICS `action_queued` event. Invisible while queueing was
  silent; caught by the first full gate after it stopped being.

#### The gate could report success on a run it did not finish

**`run_tests.sh` now fails when the suite does not finish, and this is the most important fix in the
stretch.** The suite runs under `-d`, which GUT needs to notice unexpected engine errors — so a
runtime script error raises a Debugger Break, **the break ENDS THE RUN**, `run_suite.gd` never
reaches `_on_end_run`, never computes an exit code, and the process exits **0**.

Not hypothetical: Pass C3's first full gate reported `EXIT=0` from a log with no totals in it,
having stopped three quarters of the way through because two test files still reached for fields
that had moved. A runner that has vanished cannot report its own absence, so the caller checks for
the summary line the runner prints last and fails the build without it. Verified against both real
logs — the truncated one lacks the marker and fails, a good one passes — and it then caught a second
real case within the hour.

#### Reversed within the block

`EXPECTED_SIDE_PINNED` went from empty to four (`debug_panel`, `inspect`, `action_bar`,
`inspect_viewer`), which is the Pass A tripwire working exactly as built. Filling it forced the
action-bar collapsibility call recorded above.


### taskblock-56 Pass F — the editor, and the collapse's own proof holds

**The block's central question was "is the editor a module set plus one authoring module?" and the
answer is yes, with one correction to how it is counted.** `ViewModes.editor()` is a six-line table
entry declaring six modules that already existed plus one new `EditorModule`. **No subclass, no new
chrome** (it reuses `ModeChrome.PLAYER_COLUMNS` unchanged), no duplicated panel, and nothing
reached into another mode — every module it names is one `ModuleCatalog` builds for anybody.

**The correction is worth stating because a naive count gets it wrong.** Two of the editor's six
existing modules — `claim_volumes` and `camera_framing` — are mounted by *no other mode*, so
"modules unique to the editor" reads as three rather than one. They are not the editor bringing
anything: Pass E built and tested both, and `PLAN.md` recorded `ClaimVolumeModule` as "correct and
unreachable" pending exactly this surface. `test_editor_mode.gd` therefore counts against a pinned
list of what existed before Pass F opened, because a claim about what a pass *cost* cannot be
measured from the tree that pass already changed.

**`EditorController` (`src/logic/`, `RefCounted`) holds the whole editing model and the scene holds
none of it** — `BuilderController`'s split applied again. Place and remove parts, heights and
facings, spawn markers, sight-blocking, board size, claims (add/resize/retype/remove), edges,
per-cell chance, the whole-section declarations, undo, both saves, both loads, and every warning.
30 tests, no node built in any of them.

**Undo is a snapshot stack, chosen over inverse operations deliberately.** A board is a few hundred
placements so a snapshot is cheap, and "undo restores the prior state exactly" becomes true by
construction rather than by a dozen careful inverses, the one of which nobody exercises being the
one that is wrong. Every verb snapshots before mutating — *including* verbs that change nothing
measurable, so an author's third undo does not land somewhere different depending on what their
second edit happened to hit. Addressing is by cell rather than by a held `MapPlacement`, because a
restore builds fresh resources.

**The whole-section declarations are discovered from `SectionFile`, not listed.** A new `@export`
on that resource becomes an editable field the day it is added; the only thing `EditorController`
knows is which properties it models itself (`STRUCTURAL_FIELDS`). The standing open-vocabulary rule
applied to an authoring surface.

**Nothing validates on the way in, and that is F4.** `GridPlacement.can_place` is *not* replayed as
a gate — it is replayed as a **warning**, over a board grown in authored order, so "a catwalk with
nothing to attach to" is named rather than refused. `warnings()` also carries the format's own
`describe_problems`, the placements the loader would reject outright (out of bounds, unknown part),
and the navigability verdict. A board with a pit nothing can climb out of loads, launches, and says
so. Which format's opinion is reported is `target`'s decision, because the two disagree: a board
with nothing walkable is a broken **map** and a legitimate **section**.

**F3 — the authored board launches through `BoutInjector.load_map_file`, which is `load_map` with
the file-reading half taken off.** Not a second route into combat: both share `_swap_to_map`, so the
board reaches a bout down the identical path a generated one does, and the bout is marked
`was_injected` exactly as any other injection is. Logged under `load_map`'s own verb name with
`BoardSwap.AUTHORED_SOURCE` (`<authored>`) as its path, because a log line naming a file that does
not exist is worse than one saying there was none.

**`BoutInjector` went over its 1000-line gate and the file resolution moved to `BoardSwap`** —
which is the same pressure that created `BoardSwap` in taskblock-54 and is recorded in its header.
`resolve_map`/`resolve_section`/`swap_to_map` moved; the guard, the refusal reasons and the `inject`
log line stayed. Refusal reasons are unchanged, so nothing a refused load says changed. **Its
path test widened from `res://` to `://`**, so a `user://` path is a path too — no catalog display
name contains `://`.

**Two defects found by the tests and fixed in the pass:** `EditorModule._save_into` built
`res://data/maps/user://…​.tres` for any name that was already a path (keyed on `res://` rather
than on `://`), and `open()` carried the same assumption in reverse and could not reopen what the
editor had just written. `open()` now goes through `BoardSwap`'s resolution rather than a third copy
of "a name or a path".

**`ClaimVolumeModule` is mounted for the first time**, which closes the loop Pass E left open —
authoring a claim draws it, in its declared colour, at its declared extent. The Pass E guard that
banned it from *every* mode is narrowed to *every play mode*, with the authoring modes pinned in a
one-entry list: that is the guard working as intended rather than being weakened, since it was only
ever a total ban because there was no authoring surface for the exception to apply to.

**A known limit, flagged rather than worked around.** The editor mode installs over whatever bout
`BattleScene` already built, so units already on the board are relocated onto the authored one by
the same `BoardSwap` a map load uses. An authoring session that starts with no units at all wants an
entry point that builds a world without a bout — that is *Main menu*, sequenced after this.

**The editor is reachable on `N`**, mirroring `SIMULATE_BOUT_KEY` exactly — one constant, one legend
row, two lines in `BattleScene._unhandled_input`. Added because without it the editor was mountable
only from tests, which is the state Pass E left `ClaimVolumeModule` in and which `PLAN.md` then had
to carry for a block; shipping an unreachable authoring *surface* would have repeated it one level
up. That cost is also the clearest measure of what the mode table bought.

### taskblock-56 Pass F — the suite profile was four taskblocks stale

**Not editor work, and recorded separately because it is not.** `test/suite_profile.json` was last
regenerated at taskblock-52 (`303e1db`); the per-taskblock regeneration was skipped for 53, 54, 55
and 56 A–E. Regenerating it surfaced four blocks of drift at once. **Both guards that read it are
structurally incapable of reporting sooner** — they read the committed file rather than the live
run, which `test_suite_budget.gd`'s own header states as a deliberate trade.

**`SuiteBudget.BASELINE["ui_builds"]` 344 → 627, of which Pass F is 63.** Per-file against the tb52
profile: `test_editor_mode.gd` +63 (this pass), `test_view_modes.gd` +38, `test_spectator_overlay.gd`
+36, `test_resolution_player.gd` +33, `test_squad_control_overlay.gd` +15, eleven others +47 — so
**169 of the 232 predate this pass.** Raised to the honest measurement with that table in the
constant's own comment, per the ratchet's "raise the number and say why in the same commit". No
other gated counter moved past its limit (`bouts` 54 → 57 against a ceiling of 64).

**`test_map_serializer.gd` added to `SuiteTier.BOUT_FILES`.** It builds 2 bouts and has carried
`should_skip_script()` since taskblock-53 Pass B — the fast gate was skipping it correctly — but the
list entry was missed, and the tier guard reads bout counts from the profile, so it never saw the
bouts appear. Nothing in Pass F caused this; the file has not been touched since taskblock-54 Pass A.

### taskblock-56 Pass A — the tiles are wound the way every other box is (`BR55.02`)

**`BoardView._add_box` emitted all six faces inside out.** It is the only hand-wound geometry the
project has — every other box on the board is a Godot `BoxMesh` — which is why fifty taskblocks of
parts never showed this and the tile parts did the moment they existed. Back-face culling was doing
its job against geometry built the wrong way round: outward faces discarded, interior faces drawn.

**Fixed by reversing the six quads, not by disabling culling.** Culling stays on; no material
changed. `_add_quad` is deliberately untouched — it is shared with `_build_grid_lines`, whose quads
were already correct and would have been flipped face-down by a fix applied one level down.

**The convention is now measured rather than asserted.** A real `BoxMesh` emits every triangle with
`(b - a).cross(c - a)` pointing *into* the solid — dot with its own stored outward normal is `-1` on
all twelve. A front face runs clockwise seen from outside. The old doc comment claimed the opposite
in so many words, which is the bug recorded as truth; it is rewritten in the same edit.

**`ImmediateMesh` carries no normals on this surface**, confirmed by reading `ARRAY_NORMAL` back off
a built mesh rather than by reading the source. So this was never the reversed-winding-with-correct-
normals case that looks like a culling setting — winding alone decided it.

**`test_board_view_winding.gd` reads the engine's own box back to establish the convention** and
requires the tile mesh to agree with *that*, so nobody restates the rule from memory again. It was
checked against the bug: on the old winding it reports `12 of 12 tile faces wound inside out`; on
the fix, 4/4. It also pins the grid lines as up-facing.

**Why the existing tests missed it, which is the transferable part.** `test_no_risers.gd` counts
vertices and `test_board_view.gd` asserts an AABB — both winding-blind. Geometry in exactly the
right place facing exactly the wrong way satisfies every assertion taskblock-55 Pass B wrote.
CLAUDE.md's "read the real node back, don't re-derive it" had been applied to placement and never to
orientation.

### taskblock-56 Pass B — where a shot aims, answered in writing

**An investigation, not a fix.** No aim path changed in this pass.

**The two paths agree, and structurally rather than luckily.**
`ActionCatalog.build_firing_action` is the only place in `src/` that constructs a firing action,
and every firing action resolves its aim point through one expression,
`ShotPlane.center_of(plane, target) + aim_offset`. The player passes `reticle_offset`; the AI
(`UtilityExecutors.build`) omits the argument and takes the same `Vector2.ZERO` default, as do
overwatch and the step-out triple's middle leg. **A default left alone is not a second
implementation.** `test_one_aim_path.gd` pins both halves: the two paths' actions compared field by
field, plus a source sweep asserting nothing outside the catalog constructs a firing action.

**Which removes a suspect from `BR51.01`** — a player/AI split is not what moves those shots.

**But the aim point is not the target's centre.** `ShotPlane.center_of` returns the centre of the
target's **frontmost region** — whichever single projected face of whichever single part sits
nearest the shooter. An outstretched weapon *is* the aim point. Measured on a real assembled body:
**20.1° off the muzzle-to-target axis at 1 cell**, 5.9° at 2, 0.6° at 3, −0.1° at 10 — and the
winning part changes identity with range (pistol → plate → arm cladding) because depth ordering
shifts with the projection angle. The aim point's *height* drops to that part's height too, 0.80 at
a gun against 1.36 at the upper body, so the same mechanism aims down as well as sideways.

**This confirms `BR54.01`'s stated unverified suspect** and reproduces its range effect from the
geometry rather than from the log. **It does not account for the whole of it**: that entry measured
43.1° at 2.3–5.3 cells and this mechanism tops out near 20° at *one* cell. Appended there as a
confirmed contributor with residue, explicitly not as a closure.

**Recorded in `docs/02` as a finding, not a specification.** Nothing chose the current behaviour;
it is what "the frontmost region's centre" came to mean once bodies stopped being single boxes.

**Two things found while looking, neither fixed here.** `ShotPlane.center_of`'s no-region fallback
returns `Vector2(target.cell.x, target.cell.y)` — grid cell coordinates handed back where callers
expect a `(lateral, world height)` plane point; it fires only when the target projects nothing at
all, which is why nothing has seen it. And `InternalTargeting.aim_offset_for` — the knowledge-gated
aim-at-a-named-internal path — **has no production caller**; nothing outside its own tests reaches
it.

**A note on the block's own text:** taskblock-56 Pass B names `BR51.01` while quoting `BR54.01`'s
measurements. Findings were appended to both — the confirmation to `BR54.01`, the elimination to
`BR51.01`.

### taskblock-56 Pass C — the overlays became module lists

**`SquadControlOverlay` 942 -> 338 lines, `SpectatorOverlay` 718 -> 316**, and what is left in each
is chrome plus a declaration. Everything else is a `ViewModule` in `src/view/modules/`, shared
between them rather than written twice.

**The acceptance holds, and it was the pass's own stop condition.** *"A module can be instantiated
with no overlay at all — if a module needs its parent, it is not a module."* All fifteen modules
mount and unmount against a `ModuleContext` whose every field is null: no battle, no UI root, no
host, no tactics, no slots. `test_view_modules_stand_alone.gd` iterates `ModuleCatalog` rather than
hand-listing, so a module added later is covered the day it is added.

**There is deliberately no `overlay` field in `ModuleContext`.** The cheapest way to make "a module
cannot need its parent" true is to leave the parent out of the vocabulary. A module that wants the
world asks for `battle`; one that wants somewhere to hang a `Control` asks for `ui_root`.

**Two axes, not one.** `DISPLAY` reads the sim and draws; `INPUT` queues actions against a unit. The
line is drawn at the `TacticsController` path specifically — the input set is exactly `unit_input`,
`action_bar` and `turn_controls`, pinned as a list so a mode's "no input modules" claim cannot be
quietly falsified. **Spectator's contract is now `has_unit_input() == false` rather than the absence
of an inheritance edge.**

**Recorded rather than quietly decided: `DebugPanelModule` is DISPLAY even though injection mutates
the board.** It is a debug-build-only verb path that a spectator has carried since taskblock-30, and
classifying it INPUT would make Spectator an input mode and destroy the distinction. Debug verbs sit
outside the classification, gated by `OS.is_debug_build()` rather than by mode.

**Layout belongs to the mode, behaviour to the module.** A mode publishes named `slots` and a module
asks for the one it wants, falling back to `ui_root` or to itself. That fallback is what lets the
same module appear in a mode with no such column — and what lets it mount against nothing at all.

**What was duplicated and now is not:** the debug panel and perf readout (`_on_debug_panel_applied`,
`_on_ui_element_toggled` and `_on_perf_stats_ticked` were byte-for-byte identical in both overlays,
doc comments included), the combat log window and its sink lifecycle, the replay panels, the inspect
modal, and resolution playback.

**One genuine behaviour difference was found and both halves kept**, per "extract, do not rewrite":
`SquadControlOverlay` re-pointed `sink.fold.state` at the new `CombatState` on a battle load and
`SpectatorOverlay` did not. The module always re-points, which is a strict superset — pointing the
fold at the current state cannot be wrong for a sink whose state has not changed.

**A guard test moved with the code, and the move is a stronger guarantee.**
`test_bout_injector_determinism.gd` asserted that *both* overlays reference `bout_injector`, because
each built its own gated debug panel. There is one gated module now, so the assertion is that the
module has it and that no overlay reaches for `battle.bout_injector` directly. Two gated copies
became one, removing the thing that could drift — the same argument tb31 Pass A made when
`inject_button` collapsed into `TopLeftControls`.

**Input has exactly one engine entry point.** `BoardInspectModule` exposes `handle_input(event)` and
deliberately does not define `_unhandled_input`: a module defining one would receive events wherever
its host happened to parent it, and a host that also forwards would dispatch the same click twice.
Same reasoning as the per-frame `tick` living on the host.

**Three overlay members became public because a test needs to see them**, and the reasons are
recorded on each: `UnitInputModule.repair_menu` (whether a picker opened and what it listed),
`pick_repair` (a real `PopupMenu`'s `id_pressed` cannot be emitted headlessly), and
`PlaybackModule.cycle_speed` (the wrap cannot be asserted through a click).

Full gate green, 2812/2812.

### taskblock-56 Pass D — one view, and a mode is a table entry

**The four overlay subclasses are deleted.** `SquadControlOverlay` (942), `SpectatorOverlay` (718),
`GenerateBoutOverlay` (373) and `SingleUnitOverlay` (54) are four rows in `ViewModes`: which
modules, in what chrome, with what options, under which turn policy. `ControlOverlay` is 416 lines
and is the only surface class.

**The acceptance holds.** `test_view_modes.gd` builds a mode that exists nowhere in `src/` — an odd
combination no shipped mode uses, so it cannot be satisfied by a real mode's code path — mounts it
against a real `BattleScene`, and asserts it produced exactly the modules it declared. Every shipped
mode is separately asserted to compose its own declaration, in order.

**`single_unit` is `player` plus one field**, asserted directly. That 54-line file was never small
because the mode was small; it was small because inheritance let it take everything.

**Spectator's contract became checkable rather than structural.** It used to be expressed by *not
inheriting* the player overlay. It is now `has_unit_input() == false`, asserted twice — from the
declaration alone (no battle needed) and against a mounted surface, where the concrete fact is that
there is no `TacticsController` at all and therefore no path from a click to `ActionQueue.enqueue`.

**Chrome is three named layouts** (`player_columns`, `top_left_rows`, `centered_menu`) publishing
named slots a module asks for and degrades without. **Options are applied generically by property
name**, so adding one is a table entry too and `ControlOverlay` knows what none of them mean.

**Module-to-module wiring moved into a `link()` hook**, called after every module has mounted, so
the connections a module wants do not constrain declaration order the way its mount-time reads do —
and a new mode needs no wiring code. Two host capabilities, `advance_ai_turns` and `rebind_all`, are
published on `ModuleContext` as `Callable`s rather than by handing a module the surface.

**Two real bugs found while migrating, both caused by the migration and both instructive:**
- **A modeless surface defaulted to the player mode**, which *has* unit input, so `_on_battle_loaded`
  drove the AI batch. Every fixture that installs a bare placeholder to neutralise
  `BattleScene._ready()` found its bout one turn further on with units standing somewhere else.
  `ViewModes.empty()` is the faithful translation of the old inert base class.
- **Routing the AI batch through a signal silently broke it.** `emit` does not await a coroutine
  handler — it runs it to the first `await` and detaches — so a caller awaiting the turn returned
  with the batch still in flight. That is exactly the defect tb45 Pass E fixed by adding an `await`
  to a fire-and-forget call, and a signal would have reintroduced it wearing a nicer shape. The
  advance is awaited inline in `UnitInputModule._on_turn_ended`.

**A third, subtler timing fact worth recording:** the single-unit auto-select used to work *because*
the old code did not await — it ran at the batch's first suspension. Awaiting properly moved it a
frame later, past the point a caller looks. It now happens inside the batch loop, the moment the
controlled unit becomes current, which is the same timing without depending on where a suspension
lands.

**The checkpoint parse guard earned its keep**, catching `checkpoint_9.gd`'s orphaned
`SpectatorOverlay` reference — precisely the `BR40.02` failure mode it was added for, where a rename
orphaned two scenario scripts for fifteen taskblocks because nothing re-ran them.

**The deferred bugs, re-checked as the pass asked.** `BR27.04` and `BR32.09` were already `Resolved`
and archived before this block, so the "three deferred to this refactor" framing was out of date.
`BR35.02` **did not evaporate**, and the note appended to it says why: its stated shared cause —
Spectator re-implementing Squad's panels — was true of the other two and never true of it. Blind
`y == 0` plane math was not a second copy of anything the player view did better, so there was
nothing to converge on. Left `Active`; **`Pending` would have been a false claim.**

**Test migration: 0 deleted, all migrated.** Every view test that reached an overlay field now
reaches the owning module through a typed accessor. Three tests changed what they assert rather than
how: the debug panel's input owner is the board module rather than the surface (a correction — it is
the thing that actually owns the click), the injector guard names one gated module rather than two
gated overlays, and the bout-injector wiring test reads `battle.bout_injector` directly.

Full gate green, 2822/2822.

### taskblock-56 Pass E — the three view gaps, as modules

All three are `PLAN.md`'s *Seeing what you authored*, and all three are asserted on the boxes rather
than on a render.

**Floor tiles go dark forest green** (`WorldPalette.TILE_TEMP`, `#2E4A32`) while there are no models.
They shared a material with walls and units, so a board read as one undifferentiated mass. **The
whole revert is `WorldPalette.TEMPORARY_TILE_TINT = false`** — `BoardView._build_tiles` calls
`WorldPalette.tile_color()` and does not know which branch it got, which keeps the temporary thing
genuinely one edit from gone. The material branch is tested directly so it cannot rot while unused.

**Loading frames what it built.** `CameraRig.frame_bounds()` eases through the same `_ease_to` every
other framing uses — a load that snapped would be the only camera move in the game that jumps.
`CameraFramingModule` supplies the bounds, computed from the same `UnitGeometry.assembly_placements`
call `BoardView` draws from and `RayCaster` marches, so "what is framed" and "what is drawn" cannot
drift. **Yaw and pitch are deliberately untouched**: the complaint is "the camera is pointing
somewhere else after a load", not "the camera is at the wrong angle".

**The framing test reads the rig back rather than re-deriving it**, per CLAUDE.md — the tween is
stepped to completion and the question asked is *does the content's bounding sphere fit inside the
frustum at the zoom the rig ended up at*. Measured on an 8x6 board with a wall: **content radius
5.166, rig zoom 9.759, visible radius 5.941.** A first version of this test compared the target zoom
to the target zoom and passed while proving nothing; it was rewritten before landing.

**Claim volumes get drawn** — one translucent box per claim, `ClaimVolumeModule`. Exterior red,
interior **vibrant lime**, empty blue, entry orange. **The two greens are deliberately far apart** —
dark forest floor, vibrant lime claim — and that separation is asserted as an RGB distance rather
than as two literals, so retuning either keeps the constraint that matters. Measured: **0.662**.

**Never in play, and enforced rather than intended.** A claim is consumed at assembly and does not
exist on an assembled board, so drawing one during a bout would be drawing something that is not
there — the exact defect the riser and ground-quad deletions were about. `no_play_mode_declares_the_claim_module`
checks that against `ViewModes.all()` rather than trusting the table to stay right.
**Superseded in form, not in intent, by taskblock-56 Pass F (above):** the guard was written as
"no mode at all" because no authoring surface existed yet. With the editor mounting the module it
is now "no *play* mode", with the authoring modes pinned in a one-entry list and the set of modes
drawing claims asserted to equal it exactly. The rule it enforces is unchanged.

**A claim whose `kind` has no colour still draws**, in a fifth colour nobody uses. `kind` is an open
`StringName`; **visible-but-unstyled beats invisible** — an author who invents a verb should see
their claim in the wrong colour rather than wonder why nothing appeared. A claim with no `box` is
skipped rather than crashed on, matching `SectionClaim`'s own stated posture.

**`board_view.gd` hit the 1000-line limit during this pass**, which is why the tint switch lives on
`WorldPalette` rather than in `BoardView`. That turned out to be the better home anyway — one place
owns the override and its rationale — but the constraint is what prompted it, and the file being at
its ceiling is worth knowing.

Full gate green, 2837/2837.

### taskblock-55 — closing doc audit

**A fourth test was passing while proving nothing, and only a read found it.**
`test_grid_line_color_is_pushed_well_away_from_the_ground_color` measured grid-line contrast
against `WorldPalette.GROUND` — the per-cell ground quad's colour, which **nothing has drawn since
Pass B deleted that quad**. A contrast assertion against a colour that is never rendered passes
forever. It now measures against the *material* colour a floor tile is actually drawn in.

Worth stating as a class: **deleting a thing does not fail the tests that measured it, it makes
them vacuous.** Pass B's own suite went green immediately; nothing pointed at this.

**`WorldPalette.GROUND` has no production consumer left** and is documented as such. Kept, because
it is still the contrast anchor `BACKDROP` is calibrated against — but its survival is not evidence
that a ground plane exists.

**`docs/10` described a ground plane that no longer exists** and used the retired absence word in
its own palette table. Corrected, with the cell/tile distinction stated where the palette is
defined.

**`PLAN.md`'s vocabulary and stacking items still carried their full unbuilt specs** under "landed"
headers. `PLAN.md` is forward-only, so that is the one thing it must not do. Both collapsed to a
landed summary, with the still-open residue kept as its own list — `is_room` grouping being
order-based rather than adjacency-based, the unconsumed `encounter_types` whitelist,
`SectionRoller.part_for_tag` as a content-library hook, and the absent thin wall part — each with
its own **Needs:** line.

**`SUPERSEDED.md` had only Pass B's reversals.** Five rows added for C, D and E: the
`MapSerializer` delegation becoming partial, `SectionEdge.side` no longer being "a closed set of
four", openings gaining a height, `to_grid` gaining a seeded roll, and `WorldPalette.GROUND` no
longer being drawn in.

### taskblock-55 Pass E — demo sections, and a preview that rolls

**Eleven named sections in `data/sections/`**, authored by `tools/author_taskblock55_sections.gd`
and named for **what each one is for**: `pump_room` (clutter, and a garrison that can fail),
`reactor_walk` (the merge partner), `cutting_yard` (an `Empty` claim over a neighbour's floor),
`hull_breach_lip` (the Interior/Exterior conflict), `coolant_stack_lower`/`_upper` (the stacked
pair), `service_crawl` (an entry connecting to nothing), `grand_hold_north`/`_south` (one room in
two sections — the south half declares `is_room = false`), and `blast_door_narrow`/`_wide` (a small
door with an expanded entry claim, and the larger door that overwrites it).

taskblock-54's `east_hall` and `west_hall` are identical and their names say nothing — fine as
format fixtures, useless as vocabulary fixtures. These are read far more often than they are run.

**The preview takes a seed and rolls the declarations**, so reloading with the same seed
reproduces a section exactly and a different seed produces a different example of the same
section. **That makes the preview the determinism test as well as the authoring tool** — a drift
in roll order stops being something only a test could catch. `preview_section` gained a seed
parameter, the debug verb gained the field, and the seed is logged so a preview can be reproduced
from its own record.

**A null generator still rolls nothing**, which is every caller predating this pass and anyone who
wants the authored skeleton rather than one example of it.

**Three tests that passed while proving nothing, and were rewritten:**
- **The clutter cap was never reached.** The fixture tagged its clutter `barrel`, which no part
  answers to, so `part_for_tag` skipped every one and the fullest preview across forty seeds held
  one item against a cap of two. `assert_lte(most, cap)` passed on a section producing almost
  nothing. Tags now name real parts, and the test asserts the cap is **reached** as well as not
  exceeded.
- **An assembly "reproduced" an empty board twice.** Two empty results match perfectly. It now
  asserts non-empty before asserting reproducible.
- **A ban test banned a tag nothing offered.** Satisfied by doing nothing. It now bans
  `barrel_pallet`, which the section genuinely offers.

**Found by that rewrite, and worth stating because it surprises: the clutter cap is a budget, and
it does couple cells.** Banning one tag frees a cap slot, so a later cell that had been capped out
now lands. The draw *order* is untouched — every candidate draws whether or not it can land — but
the room's remaining budget is not. The two are separate properties and the tests now measure them
separately rather than conflating them into one wrong claim.

### taskblock-55 Pass D — sections stack: intervals, and `up`/`down` edges

**A section can sit above or below another.** An observation deck on top of a stairwell, and a
second tall room refused because it needs space the stairwell occupies.

**Intervals, deliberately not voxels.** `ClaimResolver.interval_of` reduces a section to the
lowest and highest world Y anything it places or claims occupies, and stacking is one comparison
against another such pair. taskblock-37 made height continuous on purpose: a voxel grid quantizes
to its resolution, so 0.5 voxels cannot express a 0.3 step and 0.1 voxels are twenty mostly-empty
layers per cell.

**Claims already carried the vertical extent**, so nothing new had to be declared to make sections
stack — a claim's box *is* its interval, which is the same property that answered the
whole-column question in Pass C.

**The merge exception is honoured, and it is the common case rather than a corner one.**
`describe_interval_overlap` permits an overlap that any merge volume spans, because two rooms
sharing a wall overlap by exactly that wall — without it **every adjacent pair of rooms would be
refused.**

**`up` and `down` are data, and adding them cost two constants and a row in `opposite`.**
`edge_for` already took an open `StringName`; the note that "sides are a closed set of four in
practice" was a statement about shipped content, not about the format, and it stopped being true
here without anything being restructured.

**`SectionEdge.opening_height`: an entry at height 3 does not match an entry at height 0.** A door
at ground level and a door at the top of a staircase are different joins, and every other field on
an edge would have called them the same one — `openings` says where *along* a wall an opening sits
and nothing about how far up it is. Continuous, like every other height here.

**`span_of` answers `width * rows` for a vertical side.** Two stacked sections meet over their
whole footprint, so that is what must match; answering `rows` would have let a 6x4 section stack
on a 2x4 one because both happen to be four rows deep.

**A vertical join is lifted out of `stitch` rather than encoded as a zero cell offset.** The
horizontal path is written in cell offsets, which say nothing about a section stacked on another;
a zero offset that quietly meant something else would be the kind of overload that reads fine and
is wrong.

**Measured, and the finding that corrected three of this pass's own tests:** `ship_floor` is a
0.2-thick slab hung **below** the height it is placed at, so a deck resting its underside on a
3.0 ceiling has its walkable top at **3.2**, not 3.0. The stacking lift is computed from both
sections' real extents and accounts for the deck's own thickness. My first three assertions
assumed 3.0 and were wrong; the resolver was right. This is also the clearest argument for the
interval model in the whole pass — a quantized grid at any usable resolution could not express a
0.2 deck, let alone tell "resting on the ceiling" from "overlapping the room below."

**Found, not fixed: `BR55.01`**, an intermittent engine abort in `LoS.has_los` seen once during a
full-suite run and not reproducible (the same file passed in isolation; the next full run was
green at 2781 tests). `Grid.get_opacity` indexes a flat array with no bounds check and `LoS` never
calls `in_bounds`. On the AI path, unrelated to this block's changes as far as the trace goes.
Recorded rather than guessed at.

### taskblock-55 Pass C — the section authoring vocabulary

**A second class of section data: declarations consumed at assembly and never present in an
assembled map.** A placed board has a barrel or it does not; it has no "40% chance of a barrel."
This is where a section stops being a small map.

**Claims are volumes, and a claim's extent IS its declaration.** `SectionClaim` carries a `Box`
and a `kind` — a translucent shape that overlaps freely, is drawn only while authoring, and is
gone by the time a board exists. That dissolves the whole-column-versus-interval question
outright: **the shape is the interval.**

**Same geometry, deliberately not a `Part`.** A claim has no hp, no material, no sockets, no
destructibility, and must never reach a part picker, loot, or a shot plane. Subclassing `Part`
would have inherited every one of those and then needed each suppressed — an exclusion list
nobody could justify later.

**The four verbs are all rules about co-occupancy**, resolved by `ClaimResolver`: `empty`
forbids, `interior`/`exterior` require and are each other's only conflict partner, `entry`
negotiates by intersection, `merge` permits and unifies.

**Geometry decides and metadata does not get a vote.** A big entry meeting a small one yields the
small one *because that is what an intersection is* — no comparison, no ranking, no priority
field. Walls beside a door force a small-to-small connection for the same reason: the wall is
simply not part of the shared region. The one genuine ranking left is `SectionClaim.face_area`,
and it is measured rather than declared.

**Unification, not deduplication.** Two same-type walls in a merge volume become **one part at
one part's thickness** — the doubled wall is the invisible defect this verb exists to prevent.
Differing types refuse with a reason naming both, because picking a winner would be worse than
refusing. Merge applies to floors identically.

**An entry connecting to nothing becomes a wall**, filled by `stitch` in both directions.
Otherwise doors overwrite paintings and open into the back of an oven. A door auto-declares an
entry over its own face (`ClaimResolver.entry_for_door`) and **deleting that claim is the
authoring verb that makes the door furniture** — not a join point, not overwritable.

**Clutter and spawners stay per cell**, as `SectionSpawn` with a per-cell chance and an open tag
vocabulary. They name *a place something may appear* rather than a volume of space, and giving
them box extents would have been a false economy — a barrel sits on the floor of a cell and the
interval question never arises.

**Whole-section declarations landed on `SectionFile`:** `maximum_clutter`, `banned_clutter`,
`minimum_garrison` (**all-or-nothing — a roll below it spawns none, never a reduced number**),
`maximum_garrison`, `encounter_types` (**authored, validated, consumed nowhere**, so sections
written today need not be revisited), and `is_room`.

**`is_room` is the load-bearing one and cannot be inferred.** Encounters roll per *room*, a room
may be several sections, and crossing an invisible seam inside one large hold must not trigger
anything. A square of empty cells with one exterior wall is a legitimate section and explicitly
not a room; a section of identical shape may be a cell block that is. Only the author knows.

**`SectionRoller` rolls the declarations against a seeded RNG**, and the hazard it defends
against is **iteration order, not the RNG** — rolling over a Dictionary keyed by cell makes the
draw order follow authoring order, so the board changes when someone moves a barrel. `spawns` is
an ordered `Array`, and `_ordered` re-sorts by cell besides. Every candidate draws even when it
cannot land, so adding a ban does not shift every later cell's result.

**The `MapSerializer` delegation became partial, exactly as the block predicted.** Placements
still route through it — a previewed section genuinely is a tiny map — but a co-occupancy verb is
not, and a `MapFile` has nowhere to put one. `stitch` consumes claims before building anything.

**Validation is warnings, never load failures**, the same posture the format already took. What
the new checks catch is specifically the class of mistake that is *invisible in the result*: a
zero-extent claim, a verb no rule consumes, a garrison minimum nothing could reach. Those look
exactly like a section that chose to do nothing; a malformed placement already announces itself.

**Flagged, not designed:** `SectionRoller.part_for_tag` resolves a clutter tag to a part of the
same id and to nothing otherwise. Choosing which part a *kind* of thing resolves to is the
content library's job, and there is no content library — the dullest possible rule was chosen so
this does not quietly become where content selection lives.

**Measured, and worth recording:** the shipped `wall` part is a **full-cell 1.0 x 2.4 x 1.0 box,
not a 0.2-thick slab**, so the block's literal "two 0.2 walls merge to 0.2, not 0.4" case cannot
be exercised with shipped content. The test asserts the invariant instead — merged thickness
equals one part's own authored thickness, read from the part — which holds at any thickness and
does not bake a number the content does not have.

### taskblock-55 Pass B — cells stop carrying height; tiles carry it

**The per-cell ground quad is deleted, and nothing replaces it.** `BoardView` drew one flat quad
per cell at that cell's own height. That is the same defect taskblock-54 deleted the risers for,
one primitive down, and it survived that pass only because it was the older of the two: over a
floored cell the quad was a *second* thing co-planar with the real `Surface` part's top face,
and over an unfloored cell it was ground you could see with nothing behind it at all.

**A cell is a grid square and carries no elevation.** Height lives on the **tile** — the walkable
`Part` — and `BoardView._build_tiles` now draws those parts as their real authored boxes, six
faces each, at their own height and facing. An unfloored cell draws nothing, which is what
`_build_empty_indicators` already marks.

**The drawing and the hitbox come from one call.** `_build_tiles` reads
`UnitGeometry.assembly_placements`, which is exactly what `RayCaster._consider_surface` marches.
*Render is hitbox* stops being a property this file has to remember and becomes one it cannot
break — there is no second formula left to drift. Pinned by reading the built mesh's AABB back
and comparing it against that call directly, not against a re-derivation.

**Grid lines went back to one flat plane.** taskblock-37 had made them per-cell to match the
terraced quad; with the quad gone the reason went too, and the pass's own rule — a tile "is the
only thing at that elevation" — forbids a line riding a tile's top face, which would be the same
co-planar pairing again. A raised tile now hides the lines beneath it, and the drop at its edge is
marked by the tile's own real sides: geometry a shot actually intersects.

**Blocker and overlay-marker heights are unchanged, deliberately.** Both read `_height_for`, which
resolves through `true_height_for_cell` to the placed walkable `Surface` — so both were already
asking the *tile* where it is, not the cell. A blocker resting on a tile is a part on a part.

**The build-log step `terrain` (counted in cells) became `tiles` (counted in walkable parts).** A
per-cell count would report a number nothing in the scene corresponds to.

**Reverted mid-pass: nothing.** The one thing that changed shape under review was naming — see
the guard note below.

**The `tile` vocabulary guard is retired** (`test_cell_vocabulary_guard.gd` deleted). It banned
the word outright, so it failed the first code that used the word *as intended* — 73 hits across
the three files this pass touched. taskblock-54 swept the word out of its wrong sense specifically
so this block could give it its right one, which makes the ban a finished migration rather than a
live rule. `void` and `HULK_` guards stay: those words are **retired**, not reserved, so a total
ban remains exactly the right instrument. Recorded in `SUPERSEDED.md`.

**`Surface` is not a tile — it is where a tile is.** Stated in `surface.gd` because the two are
easy to run together: a **tile** is the walkable `Part` itself (`ship_floor`, with volume,
material, sockets, hp); a **`Surface`** is the record of one placed at a cell (which part, what
height, what facing); a **cell** is the grid square and has no height of its own. Not every
`Surface` holds a tile — a ladder is placed the same way and is explicitly not walkable.

### taskblock-55 Pass A — one word boundary, one walk, three guards

**`VocabularySweep` owns the boundary rule and the directory scan.** All three vocabulary guards
— taskblock-40's, taskblock-50's `HULK_` prefix and taskblock-54's — now read from it. Each keeps
only its own **policy** (which allowlist applies, whether the return annotation is exempt, whether
hits are checked per occurrence), because those genuinely differ and folding them in would be a
worse coupling than the duplication removed.

**The re-sweep found less than expected, and that is the result.** The corrected non-letter
boundary caught **one** line for taskblock-40's retired word and **zero** for the `HULK_` prefix.
The prefix guard was never vulnerable — a pattern with no lookbehind matches *more*, not less — so
the block's premise that both earlier sweeps shared the flaw holds for one of the two.

**The one hit was worth having.** `grid_fixture.gd` named `MapGen._finalize_walls_and_void`, which
was both retired vocabulary **and a function that no longer exists** (`_finalize_walls_and_empty`).
Fixed to name the real function; de-wording alone would have left a comment pointing at nothing.

**Allowlists shrank, as the block predicted.** taskblock-40's guard now needs **none at all** —
`avoid` and `devoid` are excluded by the boundary itself, each having a letter before the word.
Only one entry survives in the `tile` guard and one domain constant in the prefix guard.

> **Overwritten by taskblock-55 Pass B (above): there are two guards now, not three.** The `tile`
> guard was retired one pass later, when the word went live and the ban failed the first correct
> use of it. Everything else here still holds — the shared boundary, the shared walk, and the
> `VocabularySweep` exemption all stayed.

**`VocabularySweep` is exempt from every sweep it runs**, stated once rather than added to three
allowlists — the same exemption each guard already had for its own file, extended to the
implementation the three were merged into. It is a permission for a *file that is part of the
mechanism*, not for a word.

**The guards caught each other again**, for the second block running: the shared helper names all
three retired words, and the guards' new cross-references named each other's. Both reworded rather
than exempted. Also `_scan_dir`/`_scan_file` were deleted from the prefix guard once the shared
walk replaced them — dead code that still looked authoritative.

### taskblock-54 Passes C, D, E — the section format, authored sections, and a proven join

**A section is defined by its edges, which is the whole reason it is a second format.**
`SectionFile` carries `SectionEdge`s — which side, exterior or open, what `join_tag` a neighbour
must offer, and which cells along the side a unit can walk through. A `MapFile` has nowhere to
put any of that.

**What it reuses, deliberately:** `MapPlacement` unchanged, parts by `DataLibrary` id, no runtime
state, one open `kind`, a Resource per placement. `SectionSerializer.to_grid` **delegates to
`MapSerializer`** — a section previewed alone genuinely is a tiny map, so a second placement loop
would be two answers to one question.

**What makes it a section and not a small map, tested as a contrast:** a square of empty cells
with one exterior wall and no interior walls is **valid**, and the identical content is a
**broken map** (`MapSerializer.describe_problems` rejects it — a map with nothing to stand on is
broken). A format that could not express the edge-piece case would be a map format wearing a
different name.

**Where the socket analogy breaks, found by building it.** The attachment grammar is the
precedent one scale up, and three things do not carry over: a socket is a *point* with a
transform while an edge is a *span* with specific walkable openings; a socket has one host while
two sections are **peers**, so `can_join` reads both sides and either can refuse; and
`PartGraph.attach` mutates the socket to record an occupant, while a join is a fact about a
*layout* rather than about either file.

**Unsatisfiable joins are rejected with a reason, and the two that matter are:** an open edge
with no `join_tag` (nothing could ever match it) and an opening where nothing is walkable (no
neighbour could ever join through it). The second is what makes an edge mean something — you may
declare a doorway anywhere, but not where there is no floor.

**Three sections authored** into `data/sections/`: `West Hall` and `East Hall`, which join on a
`corridor_4w` tag, and `Sealed Bay`, which is **the same size and the same shape** and still
refuses — so the refusal is carried by the edge metadata rather than by geometry. The openings
are rows 1–2 of 4 rather than the whole side, because two whole-side edges would match without
the opening comparison ever doing work.

**Preview mirrors `load_map` rather than inventing a second shape** — `SectionCatalog`, a
disk-populated dropdown, and a name-or-path resolution. `BoardSwap` was extracted because both
verbs replace the whole board and faced the same relocation problem, and `bout_injector.gd` was
over its 1000-line limit besides.

**Pass E proves a join and nothing more.** Two authored sections stitch into a 12x4 board, a
flood confirms a unit can walk from one section into the other, taskblock-53's asymmetric
navigability flood reports **zero** one-way cells across the seam, and a seeded bout on the
stitched board replays exactly. **Not a generator:** no library selection, no layout algorithm,
no whole-board assembly, and nothing here extends `MapGen`.

**The edge metadata was sufficient.** That was the pass's real question — if it had not been,
the format would have changed before anything was built on it.

### taskblock-54 Pass B — risers deleted, height still continuous, escapes counted

**B1: the risers are gone and nothing replaces them.** `_build_terrain` no longer emits a
vertical quad between cells of differing height, and `_add_riser` is deleted. That face had no
`Part` behind it (`BR52.03`), so a round fired horizontally into a step passed through the drawn
geometry and travelled on under the raised floor. **The deletion is the fix**: drawing nothing
there makes render and geometry agree by both being absent. Verified by vertex count rather than
by eye — a terraced 4x4 and a flat 4x4 now emit identical terrain, 96 vertices each.
**`BR52.03` closes `Obsolete`, not `Resolved`** — the code it describes is gone rather than
repaired. Raised floors now read as floating slabs; filling a step's side is authored content and
there is nothing to author it into until sections exist.

**B2: height stays continuous, and an attempted "improvement" here was wrong.** A spread of
awkward heights (0.1 … 4.75) round-trips exactly with none collapsing onto another, and a
0.3-high part is standable. **A free-step threshold was added and then reverted**: making a
sub-level rise cost ordinary movement contradicted *"partial MP costs round up"*, a settled
`PLAN.md` decision pinned by `test_pathfinder.gd` — a 0.3 rise costs `ceil(4.0 × 0.3) = 2`, cheap
rather than free. **Recorded rather than fixed:** a unit with no climbing capability still cannot
cross a 0.3 lip, and no shipped part carries the tag. That is `BR46.02`'s residue, answered at the
generator level in taskblock-53 rather than by loosening the movement rule.

**B3: a round that leaves the board is counted.** `CombatState.shots_escaped` joins the per-bout
work counters and the `miss` event carries `escaped: true`, so the outcome is greppable rather
than inferred from the absence of an impact. **Distinct from missing the target** — a round that
strikes a wall instead is an ordinary miss and is not counted. Gaps are legitimate now, so how
leaky a board is becomes a number that surfaces a content problem long before anyone notices by
eye.

### taskblock-54 Pass A — `tile` is the walkable part; `cell` is the grid square

**303 word-uses swept across `src`, `test` and `tools`** — nearly four times taskblock-40's
sweep. `cell` was already the code's word for the grid square (`Vector2i cell` everywhere), so
the work was renaming everything that used `tile` to mean it: twelve identifiers, one class, two
files, and the comment bulk.

**Renamed:** `TileInspection` → `CellInspection` (it gathers "everything the readout needs for a
single cell", so the old name described the wrong thing), `open_tile` → `open_cell`,
`_open_move_tiles`, `pixel_radius_for_tiles`, `for_tile`, `_is_tile`, `_tile_cell` →
`_inspected_cell`, `tile_root`, `_tile_object`, `extraction_tiles`, `_build_extraction_tiles`,
`empty_tiles`. Two of those are `build_step` log names, so bout-build log output changes.

**The word-boundary sweep was not enough, and that is worth recording.** `\btiles?\b` treats
`_` as a boundary, so it reported clean while `test_..._extraction_tiles` and
`EXTRACTION_TILE_HEIGHT` still plainly contained the word. The rule that works is **a non-letter
on each side**, which catches those and gets every genuine substring right for free —
`hostile`, `percentile`, `volatile`, `versatile`, `projectile` and `stiletto` all have a letter
on one side, so **no exception list is needed**. Only `tileable` is allowlisted, as ordinary
English.

**`tile` is now unused in code**, held in reserve for the walkable part itself — a
`floor_bulkhead` inside a cell. `test_cell_vocabulary_guard.gd` keeps it that way, verified by
re-breaking: a bare `tile` anywhere under the scanned roots fails it by file and line.

**The two vocabulary guards police each other.** The new guard's doc comment named taskblock-40's
guard and its retired word, which failed *that* guard — correctly, since the word really was in a
scanned file. Reworded rather than adding a second exemption, because exempting files is how a
sweep quietly stops sweeping.

### taskblock-53 — the debug map loader is a dropdown, populated from disk

The `load_map` verb offered a typed text box, so loading a map meant knowing a `res://` path by
heart. It is a `CHOICE` dropdown now, listing every authored map by its own `map_name`.

**`MapCatalog` scans `data/maps/` on demand**, and `DebugVerbs.all()` rebuilds its spec list
every time the panel opens — so **a map dropped into the folder appears with no code edit**, the
same rule this project applies to socket types and profiles. Deliberately not a `DataLibrary`
pool: that loader keys everything on a resource `id`, and a `MapFile` has a human `map_name`
because a map is named for a person to pick out of a list, so fitting it would have meant
growing a second identifier for the loader's benefit.

**`BoutInjector.load_map` takes a name or a path.** Resolving the name inside the injector
rather than in the panel keeps the dropdown and a script on one entry point, instead of the
panel doing a lookup the injector would then have to trust. An unknown name is refused with
`no_map_by_that_name` and changes nothing.

Sorted by **filename**, not display name, for the reason `DataLibrary._load_dir` already is: a
raw directory order is filesystem-dependent, so two machines could otherwise offer the same
dropdown in different orders.

### taskblock-53 Pass E (half) — a climb can be interrupted; the AI still cannot queue one

**Landed: the interruption.** `ClimbAction.apply_interruptible` consults the mid-move hook and
returns the same `{"stopped": bool}` shape `MoveAction.apply_stepwise` does, so
`CombatState._resolve_until_body` treats an interrupted climb and an interrupted move
identically — same reason (`mid_move_interrupt`), same refund, same log line. Not a parallel
path.

**Why it matters more than it sounds.** A unit on a ladder is the most exposed it will ever be —
slow, committed, unable to take cover — and it was **the one thing in the game that could not be
shot at while moving**, because `apply()` never consulted a hook. `docs/09`: "every real exposure
the same."

**The hook fires once, after the climber has committed.** A climb is one transit, not a run of
cells, so there is no per-cell cadence to borrow; it is called with the unit already at the
destination because that is where an overwatcher's line-of-fire has to resolve. **The climb
always completes** — being shot on a ladder ends your turn, it does not rewind the rungs.

**Not landed: no AI path queues a vertical move.** The planner still moves exclusively via
`MoveAction`, so vertical movement has never happened in a real bout. The scoring already knows
about height — `_closes_distance` reads path distance and `move_cost` prices a ladder edge —
what is missing is the executor that turns "the best cell is up there" into a `ClimbAction`.
**Split deliberately:** that half touches the planner's action construction, where a regression
is hardest to attribute, and folding it in alongside a movement change would have made the two
inseparable. Queued in `PLAN.md` as *The AI can queue a vertical move*.

### taskblock-53 Pass D — the generator owes navigability, and `BR46.02` closes

**Re-measured either side of the fix with the entry's own reproduction, 40 seeds at the real
32x24 bout size: 16 of 40 -> 0 of 40.** Seed 16, the worst case on record with 216 one-way
cells, comes back clean.

**`MapNavigability` is the invariant.** Flood out from a spawn, flood back, and any cell in the
first set but not the second is ground a unit can walk into and never leave. It runs a
**non-climbing** `Pathfinder` deliberately — checking with `can_climb` would pass maps only a
part nothing in the repo carries could traverse.

**One change to the prescribed method, and it matters.** The naive check floods back from every
reached cell, which is O(cells^2) and unusable across a sweep. The return flood runs **once**
from the origin over *reversed* edges — a cell can reach the origin exactly when the origin can
reach it backwards. It reproduces the recorded 16/40 exactly, which is what makes the shortcut
demonstrably equivalent rather than merely faster.

**The repair runs last, on the finished `Grid`** rather than on the scratch, because that is
where real surfaces, heights and ramp tags live — and it is what the check measures, so repair
and check cannot disagree about what a legal step is. Ladders are placed through
`GridPlacement`, so the generator is held to the same attachment grammar an author would be.

**A finding: the rule's ladder half is measured-dead.** The spec is "rise <= 2 gets a ramp;
anything higher gets a ladder", and nothing generated can reach the second half. A cell is
one-way only if you can *fall into* it, which caps the drop at `MAX_HOP_DOWN_LEVELS` (2.0); the
way out is the same face, so the repair's rise never exceeds `RAMP_MAX_RISE` (2.0). **The branch
is kept rather than deleted** — the same call taskblock-52 made about its measured-dead tiebreak
stage — with a test that fails if the constants stop making it dead and says to update rather
than delete it.

**Stranding stays a legitimate outcome.** The invariant belongs to generation and is consulted
nowhere at runtime; an authored map that fails it still loads, which the committed proving
ground relies on.

### taskblock-53 Pass B — the tile format, and the first committed map

**Nothing serialized before this.** A `Grid` existed only as something `MapGen` produced or a
fixture hand-built, which is why eight blocks of AI diagnosis were done by hunting seeds.
`MapFile`/`MapPlacement` are `Resource`s and `MapSerializer` converts both ways with no
SceneTree.

**One `MapPlacement` class with an open `kind`** (surface / blocker / field_item) rather than
three near-identical Resources — kind is content, so it is an open vocabulary, and three classes
would be three places to update. **A Resource per placement rather than parallel arrays**,
because Pass B needs the `.tres` hand-authorable and parallel arrays are one transposed row from
a silent hole in the floor.

**Parts are stored by `DataLibrary` id, never embedded, and runtime state is excluded.** A map is
the pristine authored board, not a savegame: embedding copies would freeze a balance number into
every map ever saved, and `occupant_id` belongs to a bout. Tests pin both — a damaged blocker
reloads intact, and a loaded map comes back unoccupied. `opacity` is stored rather than derived,
because it correlates with wall blockers but is written independently.

**Loading deliberately does not enforce the placement grammar.** The grammar gates the *act* of
placing, and replaying it at load would reject a legitimate saved stack whose cell is no longer
empty by the time the second surface loads. An authored map may also be broken on purpose, so
`describe_problems()` warns instead. What load *does* reject is a file that does not describe a
board — unknown part id, out-of-bounds cell, non-positive dimensions, two blockers on one cell,
mismatched sparse arrays — each naming the offending value.

**Acceptance met.** Round trip over a generated 40x30: **1237 placements, equivalent cell for
cell**. Bout parity: the same seeded bout on generated and round-tripped geometry emits **159
events, identical event for event** — compared as a full transcript rather than an outcome,
because two bouts can reach one result down different paths.

**`data/maps/proving_ground.tres` is the first committed map**, authored by
`tools/author_taskblock53_map.gd` on the same convention every `tools/author_*` script uses.
21x12, three elevations, one ramp as the only route up, and three stacked height-4 shelves
deliberately unreachable until a ladder exists. Its test prints an ASCII dump, per the rule that
a spatial system without one is unverifiable.

**`BoutInjector.load_map` is the placeholder loader**, registered as a board-changing debug verb.
It relocates living units onto the loaded map's own spawn markers by squad rather than leaving
them inside walls, and names any it could not place rather than refusing the whole load.

### taskblock-53 Pass C — the ladder, and the grammar's first real use (it did not hold)

**C1's finding: the placement grammar had never once succeeded.** tb38 built it and warned
*"the first catwalk discovers the grammar doesn't hold."* It didn't. **No shipped surface part
authored a single `Socket`**, so `_find_attach_point` could not match anything — every side
attachment was structurally impossible, and the grammar's only recorded behaviour was
*refusing* a second `GROUND` placement. A test pins the socket count so it cannot regress to
unusable silently.

**C2's design question is answered: orientation does not enter the attachment vocabulary.**
Direction is geometry and geometry is already on the socket. `ship_floor` authors four `LEDGE`
sockets with real per-edge transforms, and a placement takes the socket physically facing it —
so a platform can be laddered on any side and the transforms do work instead of decorating.
Putting direction in the type would double every socket name and repeat the "one word carrying
unrelated axes" mistake `SUPERSEDED.md` records against the retired playstyles. Written into
`docs/01`.

**What the grammar did need was height, and the first rule was too strong.** A side attachment
now skips a surface *in its own cell at its own height* — the ground under its feet — which is
what stops a ladder binding to the floor it stands on instead of the ledge beside it. The first
version excluded same-height hosts everywhere and **broke tb38's own tests**: a catwalk spanning
horizontally from a neighbour at the same height is precisely the case side attachment exists
for. Own cell wins when it qualifies, which is how *"a segment side-attaches to the segment
below it"* falls out with no stacking rule of its own — the same cell is simply in the search.

**A ladder is a second source of legality for an action that already exists** (`can_climb() or
ladder`), and it **replaces the rise cap with its own reach** rather than raising it:
`MAX_CLIMB_LEVELS` exists because a bare face is only climbable so far, and a ladder removes
that by construction. Without this a three-segment ladder would be unusable, which defeats
"tileable to arbitrary height".

**`LADDER_COST_SCALE` was backwards on the first try, and the number is flagged.** 1.5 made a
ladder the *most* expensive way up — nobody would build one — and made tall ladders fail their
affordability check outright, because `ClimbAction` charges the whole rise as one action and a
four-level ladder cost 16. At 0.5 a ladder level costs 2.0 against a ramp's 1.0 and a bare
climb's 4.0, which orders the three the way the fiction does. `ClimbAction` reads the same
constant, so the planner's quote and the action's charge cannot drift.

**A correction to a comment I wrote in this pass:** `LADDER_SEGMENT_RISE = 2.0` was documented
as "one level". `UnitGeometry.LEVEL_HEIGHT` is **1.0**, so it is two — deliberately more than a
bare face, since a ladder reaching no further than free-climbing would have no reason to exist.


### taskblock-53 Pass A — the audit is disjoint from the suite

**`res://audit/` is its own tree with its own entry point** — the CSV, its checks
(`test_suite_audit_csv.gd`), and the `audit_rules.py` judgement-column helper. The ordinary suite runs
`--dir=res://test` and never sees it; the audit runs
`godot --headless --path . -s res://tools/run_suite.gd -- --dir=res://audit`.

**The acceptance was performed, not reasoned about:** with `audit/` deleted outright, the suite passes
**2665 tests, 0 failures, exit 0**, and the parse guard degrades to 19 scripts rather than erroring.
Then restored.

**The coupling that forced taskblock-52's churn is gone.** The audit CSV used to own the assertion that
per-test counters sum to the file-level totals, which made a *committed snapshot an input to the
ordinary suite* — add a test to a covered file and the gate went red until both were regenerated. A
fresh `suite_profile.json` and a stale CSV cannot coexist, which is why that block could not preserve
the CSV's deliberate staleness.

**The assertion was kept and re-pointed rather than deleted**, since it is the load-bearing check *of
the profiler*: `suite_profile.json` already carries a per-file `files` array and a `totals` dictionary,
so summing the first must reproduce the second. Same wiring bug caught, no snapshot involved. Two
companions cover what the sum alone cannot — that no total exists without a per-file source, and that
identity fields never become totals, which is the exact leak that once put `order` (2 953 665) into a
committed profile's totals as though it were work.

**A guard keeps it disjoint.** `test_suite_profile_consistency.gd` scans every `.gd` under
`res://test/` for a reference to the audit tree. **Comment lines are stripped**, because this rule's own
explanation has to name the path it forbids — a path in prose is documentation, a path in code is a
dependency. Excluding the scanning file by name would have been easier and would stop it policing
itself.

**The audit still has to compile**, and only that. `parse_guard.gd` covers `res://audit/` for the same
reason it covers `tools/` — nothing runs it on a schedule, so nothing else would notice it rotting, and
the next audit could be six months out. **A missing audit tree contributes zero paths rather than an
error**, since deleting it is legitimate. Verified by re-breaking: a syntax error in the audit makes the
guard name the file and fail.

**Staleness is now the expected state.** The first run after separation reports 2668 rows against 2665
declared tests — the drift from moving its own seven checks out and adding four. That failure is the
tool reporting "regenerate before you trust this", and it gates nothing.

### taskblock-52 — supervisor bug-hunt pass: five closed, five filed, one duplicate found

**Closed on the owner's instruction:** `BR52.04` (combat-log NUL corruption), `BR34.05` (misses
vanish), `BR30.10` (shots resolve through walls, closed after the verification it asked for — 44 wall
impacts in one battle, every hit on a wall *face plane*, zero `PENETRATE` outcomes anywhere), and
`BR52.11` (the bout seed). `BR35.01` closed on a re-measurement: **774 usec against the 1 559 usec
recorded in taskblock-51**, a 2.0x improvement from the `SKIP_RADIUS` reject.

**`BR35.05` closed `Obsolete` and its symptom re-filed as `BR52.10`.** This is the duplicate the
dedup pass was for. `BR35.05` described `LineOfFire.approach_path`/`closing_path`, both **deleted** in
tb46 Pass C with the engagement-score planner that was their only caller — so the entry's subject no
longer exists. **`Obsolete`, deliberately not `Resolved`:** nobody verified squads stopped blocking
each other, the implementation was replaced underneath the report.

**The defect survived the rewrite, and that is the finding.** The old branch planner logged
`held: ally_in_line` — it genuinely refused a shot through a squadmate. `UtilityPlanner` carries no
consideration for it, and an AI unit now fires through an ally: one put **eight point-blank rounds
into the squadmate in front of it**, destroying the torso and ejecting the matrix on turn zero. Two
vestiges confirm the loss rather than a reading of intent — `LineOfFire`'s doc comment still advertises
*"the planner's ally-in-line check"* that has no caller, and `AiDecisionLog.emit` (which printed the
`hold_reason`) is still in the tree with **zero callers**. `docs/SUPERSEDED.md` says that log was
"deleted with the branches it named"; it was orphaned, not deleted.

**Two other filings were checked against closed entries and are not re-openings.** `BR52.12`
(overwatch never fires) resembles `BR24.03`, whose fix was **verified still present in source** —
`bout_runner.gd` calls `state.resolve_until(queue, Overwatch.check_trigger)`. `BR52.09` (a destroyed
cover object's model stays on the board) resembles `BR51.24` but is a different subsystem: a
**blocker** under `BoardView`, which has no per-part teardown at all, against a **unit's** part under
`HitVolumeView`, where `refresh_unit_views` does run.

**One filing was withdrawn and rewritten.** `BR52.09` was first written up as a balance analysis of
deflect angles — CC misread the report as "the forklift is not dying" when it was "the model stays
visible after destruction". The measurement survives as `BR52.13` (`Suspected`/`CC`), where it is
labelled as CC's own observation rather than the supervisor's report.

### taskblock-52 — every bout logs its own seed (`BR52.11`)

**`BattleScene.load_battle`'s optional `header_event` argument is gone.** The seed rides on
`CombatState.bout_seed` and `load_battle` emits it unconditionally, so a caller cannot produce a bout
with no record of how to reproduce it. **`session_start` is renamed `bout_start`** — the old name was
right when a log file held one bout, and since `FileSink` began appending it routinely holds several.

**What was actually broken.** `GenerateBoutOverlay._on_start_bout_pressed` called the two-argument
form — the form every caller in the codebase uses — so the seed a player typed was handed to
`BoutSetup.build_bout`, generated the whole bout, and was then dropped. Because a new bout appends,
the file opened with the launch bout's `seed=2` and every later bout ran underneath it carrying none
of its own. **A reader takes line 1 as the seed for the file and is wrong**, which is exactly how a
play-by-play got reported against seed 2 when the bout had a four-digit one.

**The origin seed, not the derived one.** Both generators seed a local RNG with the origin number and
hand `rng.randi()` to `CombatState.new`, so `state.rng.seed` is derived and **would not regenerate the
map**. Logging it would have looked correct and replayed nothing — a worse failure than the missing
line, because it is silent. `bout_seed` carries the origin, and a test proves the distinction by
rebuilding the board from the carried value and by asserting `rng.seed != bout_seed`.

**Two generators cover every path.** `BoutSetup.build_bout` stamps it, which reaches the Generate Bout
overlay, `CompletionSampler.build_for_seed`, `ReplayHandle.from_seed`, the watched-run panel and
checkpoint 9; `BattleScene._seed_battle` stamps the launch path. `_seed_battle` now takes the seed
rather than a prebuilt RNG, because the origin number has to still be in hand to stamp.

**The field sits on `CombatState` rather than in its constructor** — `CombatState.new` has 733 call
sites and almost none of them are bouts anyone replays. **0 is a real seed, not a sentinel**
(`GenerateBoutOverlay` uses it as the fallback for unparseable input), so a hand-built fixture state
honestly reports seed 0 instead of pretending to be unset.

**The regression test is the one the old shape could not have:** it asserts on the **second** bout in
one scene, through the two-argument call, and demands its own distinct four-digit seed — the thing
that was silently absent. Suite green.

**A second half, found in play: the seed reached the file but not the top of the in-game panel.**
`load_battle()` emits the header into whichever panel is up, and `GenerateBoutOverlay` *then* swaps the
overlay — so the panel that received it is torn down and the fresh one starts empty. The file sink
survives because `BattleScene` owns it; a panel does not. **The first fix made this visible rather than
causing it** — that path previously emitted no header for the swap to lose. `BattleScene` now keeps the
bout's header and hands it to a newly installed overlay's sink after `setup()`, **pushed straight into
the sink rather than re-emitted through `CombatLog`**, because a second `emit()` would also reach the
file and write two `bout_start` lines for one bout. Scoped to the header on purpose: replaying arbitrary
history to late-attaching sinks would change what "one stream, many sinks" means. Verified by
re-breaking it — with the call removed, exactly the two panel assertions fail.

**`test/suite_audit.csv` and `test/suite_profile.json` were regenerated together, and the previous
session's deliberate exclusion of eight taskblock-52 files could not be preserved.** The exclusion was
not a filter but deliberate *staleness*: both files were left un-regenerated, so they agreed with each
other. `test_per_test_counters_sum_to_the_file_level_profile` checks per-test counters against the
profile's **global** totals, so a fresh profile and a stale CSV cannot both hold. Adding tests to
`test_battle_scene.gd` — a file the snapshot already covered — forced the regeneration. Dropping the
eight files back out was tried and fails that sum assertion (`shot_planes` 3 127 against 9 043). All
2 668 rows carry a rule, reusing the existing vocabulary, so the distinct-rule count is unchanged at
351.

### taskblock-52 Pass F — the flip lands: the ray chain resolves every shot

`CombatState.shot_resolver` defaults to `&"ray"`. **Full suite green with the flag inverted** — 281
scripts, 2664 tests, 0 failures. The plane is not deleted and stays selectable by the same one field,
for the differential experiments and for a rollback; `ShotPlane` is referenced at 133 sites across 76
files and removing it belongs to its own block.

**Both gating jobs were fixture defects, and neither needed a resolver change.**

**`BR52.08` closed, and it was two cancelling defects rather than one.** `_make_weapon` authored no
`volume`, so `UnitGeometry.muzzle_point` never found a placement and fell back to
`DEFAULT_MUZZLE_HEIGHT`. But `_make_shooter`'s HAND socket was *also* an identity transform, which
puts the hand — and the muzzle — at world Y=0, on the deck. The missing volume was hiding the
identity socket: fix only the volume, as the first attempt did, and every test in the file starts
firing from the floor, which is what cascaded into three further failures. Fixing both is
behaviour-preserving by construction — the weapon carries `data/parts/pistol.tres`'s own box verbatim
and the HAND socket carries `DEFAULT_MUZZLE_HEIGHT`, so the baseline shooter now genuinely produces
the 1.25 muzzle it was accidentally producing before, and `grip_y` finally reaches the muzzle.

**A recorded prediction turned out to be wrong, and it is the useful part.**
`test_a_hip_height_muzzle_behind_low_cover_hits_the_cover_not_the_target` was marked in place as
due to invert on the flip and **it does not invert** — it passes under both resolvers. The earlier
reading measured the broken fixture: at the real 0.3 grip height the round is at 0.4 where the 0.6
cover stands and strikes it, rather than at 0.87 clearing it. So the test now tests what its name
says, for the first time in five blocks.

**The deflect fixture: the comment was right and the geometry was not.** `test_shot_resolution.gd`
aimed along direction (3, 4) but displaced the aim point sideways by 2.0. The plane treats that
displacement as a **parallel translation** of the whole flight, so the round still travelled at the
stated ~37 degrees; the chain aims at the displaced *point*, which **rotates** the flight instead —
the real muzzle-to-aim vector was (1.4, 0.5, 5.2), meeting the face at **16 degrees**, inside steel's
30-degree threshold. Removing the lateral offset makes the real flight equal the stated one under
both models, and the cover then has to sit where that stated ray actually goes: cell (3, 2), not
(2, 2). **Measured and printed into the run log rather than asserted on trust: 37.25 degrees.** No
angle was swept for.

**`docs/PLAN.md`'s *Wide scatter passing through a wall seam* is closed and removed from the plan.**
It was a design call among three options, and the flip answers the last of them. Two were already
answered in Pass A — merging contiguous blocker cells closes a gap that does not exist, and capping
scatter radius would hide a modelling error behind a balance number — after the recorded 56/200
turned out to reproduce in an 11x11 room and no other, with a 41x41 sweep at 90 angles x 41 offsets
returning **0/3690**. The genuine cause was the plane's parallel-ray scatter model translating the
whole flight, muzzle included, outside the building. The chain diverges from the gun by construction,
which the item's own text named as what would actually fix it. Floors became real geometry in Pass D,
so the third candidate landed too. **`BR34.05` is the same decision from the other direction and is
`SUPERVISOR`-owned, so it stays `Pending` and is not closed here.**

**The suite's own cost readout changed shape and is worth recording.** Both figures are re-taken from
the final green run, not from the intermediate one that had only the first fixture fixed: `shot_planes`
fell from **14 965 to 9 079** across the full run, and total suite time from **370.6 s to 288.1 s**.
The remaining plane builds are the aiming job the plane keeps (centre mass, aim layers, AI
line-of-fire) plus the parity experiments that deliberately run both models. Two orphaned
`DirectionalLight3D` nodes in `test_world_palette.gd` are unchanged by this block and predate it.

### taskblock-52 Pass F — 15 of 16 blocking fixtures updated; the flip is two bounded jobs away

**Superseded by the entry above** — the sixteenth fixture landed and the flag is flipped.

**Each blocking assertion was restated in terms of the rule it protected, not bumped to match new
output.** Impact counts stopped being a proxy for anything once a round continues past its target
into the deck, so:

- burst tests count **pulls** (`burst_pull`), which is what "a burst fires `burst_size` independent
  pulls" actually asserts;
- pellet-per-pull is asserted on the spread pattern rather than inferred from impacts;
- `landed_so_far` is checked against pulls that landed;
- attack and suppression tests assert **who was hit** (`target_unit_id` / `part`), not how many
  impacts followed;
- "only the first attack fired" counts `AttackAction` log lines;
- the deflect test **finds** its deflect rather than assuming index 0.

**One premise died outright and was rebuilt rather than patched.** *"A real burst's pull events
always total burst_size **even with misses**"* cannot produce a miss on a floored board any more,
because nothing misses — which is the entire point of the block. It fires on an **unfloored** grid
now, the "out through the ceiling" case `docs/02` names as the one legitimate way to hit nothing.

**Not flipped, one fixture short.** `test_shot_resolution.gd`'s deflect fixture no longer deflects
under a muzzle-to-aim march. Sweeping for a geometry that does, and keeping whichever one makes the
assertion pass, is how a suite starts describing itself instead of asserting anything — so it is left
honest and flagged rather than green and hollow.

### taskblock-52 — `BR52.08`: every "muzzle height" test has been firing from 1.25

**Superseded by the flip entry above** on two counts, both worth reading rather than just the
correction: the diagnosis was **half the defect** (`_make_shooter`'s identity HAND socket is the
other half, and it is why the first fix attempt cascaded), and the prediction that
`test_a_hip_height_muzzle_behind_low_cover_hits_the_cover_not_the_target` **would invert was wrong** —
it passes under both resolvers once the fixture is real.

**`_make_weapon` authors no `volume`**, so `UnitGeometry.muzzle_point` finds no placement and falls
back to `DEFAULT_MUZZLE_HEIGHT`. `_make_shooter_with_grip_height`'s own `grip_y` argument **reaches
nothing** — a test asking for a 0.3 hip-height muzzle gets a 1.25 one.

**Why it survived five blocks is the interesting half:** the shot plane resolves at the **aim
point's** height rather than along the muzzle-to-aim line, so where the muzzle actually sat never
affected the outcome. The fixture could be wrong and the test still green — the same "narrower than
its name" family this project keeps finding, arriving from a new direction: here the *fixture* cannot
produce what the *name* claims.

It stops being harmless under the ray chain, which marches muzzle-to-aim. A round from 1.25 down to a
0.5 chest is at ~0.87 where 0.6 cover stands and correctly clears it, so
`test_a_hip_height_muzzle_behind_low_cover_hits_the_cover_not_the_target` **will invert when the
resolver flips, and that is not a regression**. Marked in place so it does not ambush the flip. The
fix (a real `volume` on the fixture weapon) was attempted and reverted: it moves the muzzle for every
test in the file at once and cascaded into three further failures wanting their own judgement.

### taskblock-52 Pass F — `self_obstruction` deleted

**`ShotPlane.self_obstruction` is gone** (supervisor's call). It hand-modelled tb22 H2's rule — *"the
shot's ray originates and immediately hits the cover if the muzzle is below the cover's height"* — by
redirecting the aim point onto the obstruction. A ray marched from the real muzzle to the aimed point
produces that outcome from geometry, so keeping the rule too would be two answers to one question.

**Confirmed redundant on the plane path as well, not just the ray path.** With the redirect removed
and the flag still on the plane, the low-cover tests **still pass** — the plane's own level-shot model
already caught the same cover, so the redirect was belt-and-braces there. That is a stronger reason to
delete it than "the chain covers it".

Removed from `AttackAction`, `BurstAction` and **`StabAction`**. **Melee is worth a note:** a stab
still resolves through the plane (the chain returns early for the slide and none deflect modes), so if
that redirect ever mattered for melee it now wants its own answer — flagged rather than assumed, since
no test covers it and the plane catches the ordinary case anyway.

Four `test_shot_plane.gd` tests for the deleted function went with it, and `suite_audit.csv` /
`suite_profile.json` were reconciled by hand rather than regenerated — a full regeneration rewrites
3 565 lines of machine-dependent timings for a one-number change.

### taskblock-52 Pass F — the 14 blockers diagnosed: all fixture assumptions, none a chain defect

The flag was inverted, the failures enumerated and root-caused, then reverted so the tree stays
green. **Every one of the 14 is a fixture encoding the plane's behaviour**, and they fall into two
shapes.

**1. More impacts than expected** — a 12-round burst logging 36, "3 pulls x 9 pellets" logging 61
rather than 27. A round continues while it still carries damage, and floors are real geometry now, so
it punches through its target and goes on to strike the deck. Settled by the supervisor: a pellet
penetrating that effectively is a **balance** problem for when ammo types land, not a resolver one.

**2. A shot is no longer level, and this explains every cover and muzzle-height failure at once.**
**The plane models a shot as travelling at a constant height** — `DamageResolver._find_next` tests
every region at the aim point's own `y`, so a round fired from a 1.25 muzzle at a 0.5 chest sits at
0.5 the whole way and clips anything 0.6 tall in between. **The chain marches muzzle-to-aim-point,
which slopes.** Probed on that exact geometry: the ray is at **0.845** where the 0.6 cover stands, and
correctly passes over it. A real round does slope, so the chain is right and the fixtures encode the
level-shot approximation.

**This retires CC's earlier reading of the low-cover failure.** It was reported as "the fault is in
how `AttackAction` composes the aim point, not in the chain" on the strength of a probe that fired
*level* rays and saw them strike the cover correctly. That probe was measuring the wrong thing: it
never reproduced the slope, which is the whole difference. Nothing is wrong with `AttackAction`.

**One decision to take before the flip, flagged not taken:** `ShotPlane.self_obstruction` (tb22 H2,
"the shot originates and immediately hits the cover if the muzzle is below the cover's height")
hand-models a case the chain now gets from geometry for free. Keeping both is two answers to one
question.

### taskblock-52 — the combat log stops corrupting itself (`BR52.04`)

**`FileSink`'s own doc comment said "Appends to a real file". The code opened with
`FileAccess.WRITE`, which truncates. The mismatch between the two was the bug.** Two sinks alive on
one path — a new bout attaching one while the old is still open — meant the second reset the file to
zero while the first still held a handle tens of kilobytes in; its next write landed at that stale
offset and the kernel zero-filled the gap.

**Measured on a real session log: 49 403 of 138 436 bytes were NUL**, one contiguous run starting at
byte 1073. **Worse than it sounds**, because `file` then classifies the log as `data` and **`grep`
silently declines to match it** while `tail` still renders fine — so it reads as healthy to a human
and returns nothing to every tool. Several greps against that file came back empty during this
session before the cause was found.

**A new bout appends; a new session rotates** (supervisor, 2026-08-02). A bout is not a session:
several bouts in one run share a log, and the next run archives it into
`out/logs/combat-YYYYMMDD-HHMMSS.log` before starting clean. **The live path deliberately does not
move** — `tail -f`, `grep` and the startup "log: <path>" line all point at `out/combat.log`, and
there is only ever one live session, so it is the archive that needs distinct names. Rotation is
**per path and once per process**, not per construction, or a second sink attaching mid-session would
rotate the log out from under the first — the exact case this whole entry is about. The archive is
named for **when that session ran** (the file's own modification time), so a name describes its
contents, and the stamp is sortable so a directory listing is already in session order. Two defences, answering different halves: open with `READ_WRITE` so nothing truncates
(`WRITE` survives only as a create-if-missing fallback), **and** `seek_end()` before every write,
since two live handles each carry their own position and opening at the end would not survive the
second one.

**The regression tests were verified by re-breaking the fix**, not merely by passing. Reverted to
`FileAccess.WRITE`, both fail — and that also showed the corruption is not only the large-offset NUL
case: at small scale the stale handle writes *mid-line*, producing
`move: from the second sinkmove: the first sink is still alive`.

**`BR35.08` (detonations are invisible) closed on the owner's instruction** after the supervisor saw
an explosion trigger naturally. Recorded as owner-directed rather than CC-verified — no change in
this block targeted it; what moved underneath it was taskblock-51's detonation work. `BR51.21` (no
injection ever animates) is untouched, so a debug-forced blast still cannot draw.

**`BR52.05` (the click hitch) withdrawn from the ledger by the supervisor** — actively being
investigated as part of current work, so it belongs in the report rather than the bug list, per the
standing rule about defects in systems still being built.

### taskblock-52 Passes E and F — the dartboard is an input device, and the flag inverts

**The aim preview stopped being a second resolver.** `AimController._resolve_hit` built its own
`ShotPlane` and walked it, purely to answer "what is under the reticle" — so `docs/08`'s pillar (the
tooltip and the damage come from the same call) was true only by two implementations agreeing. It
follows `CombatState.shot_resolver` now, so preview and shot go through **one** query by construction.
`test_aim_controller.gd`'s corpus test was extended rather than repointed: it checks both models
against their own resolver, which is strictly more than it checked before.

**The ray path is the simpler of the two, which is the point of the split.** The dartboard already
produces a world point — `AimPlaneGeometry.world_point` is where `AimView` draws the reticle — so B
exists before resolution is asked for anything, and the shot is muzzle-to-B. The plane path has to go
through `ray_from_muzzle`, whose own doc comment explains that vertical aim is expressed by *moving
the muzzle's height* while keeping `dir.y == 0`, because the plane's coordinates cannot carry a tilted
ray. A march needs no such convention. Asserted: a click at a screen position recovers the aim point
the reticle was drawn from, and the impact sits on the muzzle-to-reticle line to 0.000000.

**Pass F: adoption approved, and the flag flip is NOT landed.** The parity case holds and
`ShotPlane` is neither deleted nor retired — but **inverting `CombatState.shot_resolver` red-lights
14 tests**, and Pass F's acceptance is a green suite with the flag inverted. Flipping it anyway would
be hacking around a failure. The plane still resolves shots; the ray chain is fully built, tested and
selectable by one field.

**What the 14 are, recorded so the next session starts with them.** They cluster as *more impacts
than expected* — a 12-round burst logging 36, "3 pulls x 9 pellets" logging 61 rather than 27 — which
is what a round continuing until its damage runs out looks like now that floors are real geometry: it
punches through its target and goes on to strike the deck. **That is arguably correct under
`BR34.05`'s own rule and it triples impact counts, log volume and tracer draws.**

**Corrected 2026-08-02:** CC framed this as an open design question about whether a *spent* round
keeps marching. It does not and never did — `RayChain` returns as soon as `spill <= 0.0`, so a round
stops when its damage is exhausted. The extra impacts are rounds that still carry real damage. The
supervisor's reading stands: a pellet penetrating that effectively is a **balance** problem for when
ammo types land, not a resolver one — **so the Pass F failures are fixture expectations encoding the
plane's behaviour, not a decision waiting on anyone.** At least one failure is a different shape:
`test_attack_action.gd`'s low-cover obstruction case resolves to the target instead of the cover —
and **the raw march handles that correctly in isolation** (probed: level shots from muzzle height
0.30 and 0.50 both strike the cover at t=1.50; 0.80 clears it), so the fault is in how `AttackAction`
composes the aim point, not in the chain.

**What `ShotPlane` is still for, since Pass F asks:** its **aiming** job, and nothing else — centre
mass (`center_of`/`depth_of` for the default aim point), aim-layer enumeration for the layered-target
UI, muzzle self-obstruction, and the AI's line-of-fire and overwatch predicates. That is exactly the
boundary `docs/02` states, so it is not left jobless and does not retire in a later block on current
evidence.

**A real bug in the chain, caught by an existing test the moment the ray became the default.**
`test_penetration_traverses_body.gd` failed on the lodged-bullet mechanic (tb20 C4, "punched in,
could not punch out"): the chain cleared its hollow-cavity flag **before** checking whether the round
actually cleared the far face, which silently deleted the mechanic on the new path. The fixture held
the right assumption and the new path was wrong.

**And a second harness gap, beyond `BR52.02`.** That failure raised a script error, which opens a
**debugger break that halts the run waiting for input** — a ten-minute timeout that looked exactly
like a hang. Recorded on `BR52.02`, which is already about a test file's failure being invisible to
the gate.

**`docs/SUPERSEDED.md` carries six rows** for the reversal: the plane as resolver, the parallel-ray
scatter model, the approximated incidence angle, floors being in no resolver at all, the dead
`is_destructible` flag, and the aim preview's own second resolver.

### taskblock-52 hard pause — both models alive behind a flag, the plane still the default

**The default inverted in Pass F — see the flip entry above.** Everything else in this entry stands:
the flag, its per-bout scope, `dup()` carrying it, and `_aim_point_world` as the one conversion.

**`CombatState.shot_resolver` chooses the model**, per bout rather than as a global static so a
differential can put one board through both without mutating shared state, and so a test switching
resolvers cannot leak into the next. `dup()` carries it — a preview must resolve the way the real
bout will, or `docs/08`'s pillar breaks. `ShotResolution.resolve_point` is the dispatch;
`ShotPlane` is untouched and still the default.

**`_aim_point_world` is the single conversion between the two aiming vocabularies.** The plane takes
`(origin, direction, lateral offset)` and tests every candidate at a constant lateral; the chain takes
a muzzle and an aimed point. One conversion means the differential compares one shot rather than two
similar ones.

**Seam sweep, both models, same room:** plane **56/200 empty**, ray chain **0/200**. On a room large
enough to hold every offset both are 0/945, so the ray chain's zero is not merely the absence of the
plane's own defect.

**Differential, 216 seeded shots, 11-room:**

| | count |
|---|---|
| agree | 33 |
| ray hit, plane missed | 64 |
| different part struck | 113 |
| different outcome | 6 |
| **plane hit, ray missed** | **0** |

The direction that would be a defect is empty. **And the disagreements are explicable, measured
rather than asserted:** of the plane's 152 hits, only **100 (65.8%) report a hit point that actually
lies on the surface they say they struck**; the ray chain is **216/216 (100%)**. The plane
reconstructs a hit coordinate from `(depth, lateral)` where `depth` is the struck cell's *centre*
projected on the shooter-to-target line rather than the face the round met, so a third of its
reported impacts name a place that is nowhere near the thing they hit. That is the `different_part`
bucket. The 6 `different_outcome` cases are STOP_DEAD versus DEFLECT on the same surface — the
incidence angle, which the plane approximates and the chain solves.

**Cost, release build, and it inverts the concern:**

| | plane | ray chain |
|---|---|---|
| one shot | **6 715 usec** | **2 021 usec** (3.32x faster) |
| a 12-round burst | **148 829 usec** | **~24 256 usec** (6.1x faster) |
| builds per burst | 20 | — |

Debug figures track (8 368 → 2 424, 3.45x). The taskblock named the burst cost as "the one number
that could sink this"; it does the opposite, because the amortisation the plane was credited with is
not something it performs.

**Determinism holds on both paths**, and traversal is **geometric rather than dictionary order** —
asserted by building the same room with its blockers inserted in reverse and checking 52 headings
give identical answers. The plane's `sort_custom` over `Dictionary` iteration is stable only because
map generation is seeded; the march never consults insertion order.

**A comparator bug in the differential, caught before it was believed.** The first version compared
`region.part` by object identity across two independently built boards and reported 152 of 216 shots
as `different_part` while its own printed detail showed both models striking `wall/STOP_DEAD`. It
compares part id plus landing cell now. A second measurement bug in the same session: an attribution
check that rounded hit coordinates to cells scored the ray chain at 51%, because a hit lands exactly
on a box face and a coordinate at 0.5 rounds into the neighbouring cell — replaced with a real
point-to-box distance, which is where 100% came from.

### taskblock-52 Pass D — membership dissolves: floors are ordinary geometry, and a dead flag wakes up

**The ray marches all four collections.** `ShotPlane.build` looped `state.units` and
`grid.blockers`; `PartPicker` looped those plus `grid.field_items`; **neither looked at
`grid.surfaces`**. That absence is the whole of `BR34.05`'s "or the floor" half — a round angled
slightly down had nothing to intersect, so "miss" was not a wrong branch being taken, it was the only
branch that existed. Measured: **59/59 shallow downward shots land** inside a closed room.

**Floors got geometry as data, not as code.** `ship_floor` and `ramp` now carry a `volume` — a
full-cell box whose **top face sits exactly at the surface height**, matching the flat quad
`BoardView._build_terrain` draws there. A designer adding a new walkable surface adds a Part with a
volume; no code edit, and no synthesised stand-in box in the caster.

**The 0.2 thickness is flagged, and it is not a balance number today.** No shipped material authors a
`dt_curve`, so `MaterialEntry.dt_at` returns the flat `dt` regardless of thickness — the floor's box
depth has no DT effect at all right now. Nothing on screen contradicts any value under the level
step either, since the renderer draws a zero-thickness quad. **Worth a real decision the moment a
`dt_curve` is authored**, and flagged as such rather than presented as settled.

**`Part.is_destructible` finally does something, and it had to.** The flag is declared in `part.gd`
("False marks permanent terrain... that can never be destroyed") and set on `ship_floor` and `ramp`,
and **no logic anywhere read it** — a dead field, harmless only because nothing could shoot a floor.
`ship_floor` carries `hp = 1`, so the first round to strike a deck plate would have destroyed it,
`BodyProjector.projects()` would have stopped projecting it, and rooms would have developed holes in
their floors. `apply_damage_to_part` now refuses to damage or destroy an indestructible part — it
still stops the round, it simply never reaches zero. Floors stay at 1 hp rather than being given an
invented hit-point total. Blast radius checked rather than assumed: only `ship_floor` and `ramp` ship
with the flag false; walls are explicitly destructible (tb31 Pass C) and `test_map_gen.gd` asserts it.

**Surfaces are placed at their own height, not the cell's.** `_consider_surface` reads
`surface.height` and `surface.facing` directly rather than going through
`UnitGeometry.true_height_for_cell`, which resolves to a cell's *first walkable* surface — a catwalk
over a floor would otherwise place both at the lower one's height. Asserted with two stacked surfaces
at one cell.

**Every remaining miss has a named reason, asserted rather than waved at.** On an open, unwalled
board a shallow enough round genuinely leaves the map, which `docs/02` counts as legitimate. The test
asserts a shot misses **exactly when** its own flight would run past the board before reaching the
deck — 3 of 59, each shallower than the board is long. The first version of that test asserted 29/29
on an open board, got 26, and was wrong.

### taskblock-52 Pass D — reported, not built: should membership be derived?

The taskblock asks whether the four collections should be replaced by one "everything occupying
space" query that the ray, the picker and the inspect preview all consume, and explicitly asks for a
report rather than a build.

**Yes, and the evidence is that the same gap has now been found three times from three directions.**
`PartPicker` scanned two collections while the plane scanned two different ones; `InspectPanel`'s
non-unit path was a third instance (`BR51.25`); and `BR52.01` was a fourth — the picker and the
renderer disagreeing about the *height* of the collection they did share.

**The next absent collection is not prevented structurally.** Nothing in the code says "these are the
things that occupy space"; each consumer writes its own `for cell in grid.<something>` loop, so a
fifth collection is found the same way these were — by someone noticing a shot passing through
something. `RayCaster.tied_candidates` is now the closest thing to a single answer, but it is one
consumer's private list rather than a shared query.

**What a derived query should be, when it is built:** `Grid` exposing occupancy, so the collections
become an implementation detail of the grid rather than a vocabulary every caller must know. The
tell that it is right will be `PartPicker` becoming a thin filter over it — the picker deliberately
should *not* return floors (clicking a floor selects the tile, which `BoardPicker` handles), so the
query must be filterable rather than one-size-fits-all.

**Not built here, deliberately.** It would touch every consumer in the same block that replaced the
resolver, which is exactly the attribution problem Pass F exists to avoid.

### taskblock-52 Pass C — ties resolve, log the stage that did it, and one stage turns out never to fire

**`RayTiebreak` has all three stages and every tie writes a `ray_tie` line naming the one that
resolved it.** The log was specified precisely because nobody knew the tie rate; measured now, from a
point source in a walled 21x21 room: **4 ties in 720 rays (0.56%)**, and 4 in 1440 — the extra angles
add none, because the ties are exactly the four axis-aligned directions.

**Stage 2, the box cast, earns its place: 9 of 9 angled ties.** The probe is a box aligned to the
ray, swept along it, represented by its four cross-section corner rays; each candidate is scored by
the earliest `t` any corner reaches it. For a ray at angle theta the cross-section basis tilts with
it, so one corner sits fractionally further downrange and reaches the shared face plane first — and
it favours the side the ray is angling away from, which is a fact about the approach rather than a
coin flip. **It iterates the tied set alone and returns one of its members**, so it is structurally
incapable of reporting a body the raycast did not find; asserted, as the taskblock asks by name.

**`PROBE_RADIUS` is 0.05 and is not a projectile width.** Box casting as a weapon property is
explicitly a later design lever, and letting a tiebreak dictate the weapon model would be the wrong
reason to build it. Flagged and tunable.

**Stage 3, closest root, has never fired — and the reason is structural, not a sampling accident.**
The design's argument was that "the gun is offset from the unit's centreline and the two cells'
centres differ, so root-to-root distance separates them." **The condition that creates an
axis-aligned tie defeats exactly that:** to meet two side-by-side cells at one `t` with an
axis-aligned ray, the ray must lie on their shared plane, and every point on that plane is
equidistant from both roots whatever the muzzle offset. Measured directly — both roots at
7.08872365951538 — so stage 3 is symmetric in precisely the case stage 2 defers to it in.

What actually catches those is the **geometric stable order** (cell, then part id), which is a
stronger determinism guarantee than the plane ever had: the plane sorted with `sort_custom` over
`Dictionary` iteration, which is insertion order and therefore a property of the map generator
rather than of the resolver.

**Closest root is kept rather than deleted**, because removing a stage the taskblock specified is a
design call and not CC's. It is recorded as measured-dead in
`test_closest_root_does_not_fire_in_any_tie_that_can_currently_be_constructed`, whose own doc
comment says to update it rather than delete it if a later change makes the stage fire.

### taskblock-52 Pass B — the ray chain: A to B, then C becomes B

**`RayChain` marches a projectile through the actual world.** A is the muzzle, B is the aimed point,
first hit wins; the angle of incidence is solved against the struck face; a penetration continues
the same ray and a deflection starts a new one, both through the same call. **0/360 empty** across a
72-angle x 5-offset sweep inside a closed room — the supervisor's standing rule from `BR34.05` is
satisfied and, for the first time, runnable.

**Three new logic classes, all headless.** `RayHit` (one struck surface: part, body, socket, real
face normal, thickness, cell, root origin, entry and exit) with `to_region()` so
`DamageResolver.resolve_impact` and every `ShotResolution` log consumer stay byte-for-byte unchanged;
`RayCaster` (the one "what does this ray meet" query, over units, joints, blockers and field items);
`RayTiebreak` (stage 3 today, closest root; the box cast is Pass C's).

**`UnitPicker.ray_box_hit` is the one slab test now**, and `ray_box_t` is a thin read of it. It
reports the face the ray clipped against, carried out through the placement's orthonormal basis —
which is what makes incidence native. **No `PhysicsDirectSpaceState`**: that needs a live scene tree
and would move shot resolution into the view layer.

**Six `DamageResolver` helpers became public rather than being copied** — `roll_crit`,
`crit_effects`, `resolve_joint_hit`, `resolve_destruction_consequences`,
`inflict_lodged_wound_if_inside`, `body_of`. The chain decides *where* a round goes; what happens
when it arrives is still the one resolver.

**Joints are in the march.** `UnitGeometry.assembly_placements` takes `include_joints` (default
false, so every existing caller and the whole view layer is unchanged) and emits one
`BodyProjector.JOINT_BOX_SIZE` box per occupied socket, carrying the socket on the `BoxPlacement`.
Without it every joint hit would have read as a ray-versus-plane disagreement for no reason other
than one model not knowing joints exist.

**A real bug the tests caught, and it was found by reading a log rather than by an assertion.** The
first chain advanced past the struck box's *entry* face, which leaves the round inside it — one
500-damage round logged **six impacts on one plate**. `ray_box_hit` now reports the exit face too,
and a penetration resumes past it. There is an assertion for it now, and a second for `hollow`
parts, whose entering-and-exiting pair is the one case that legitimately strikes one box twice
(nothing in shipped data sets `hollow`, so that branch had no coverage at all).

**`BR52.01` fixed, and it was two defects.** `PartPicker` hit-tested blockers and field items at
world height 0 while `BoardView._spawn_blocker` draws them at the cell's real height — and
`near_ray`'s cheap reject measured distance to a point on the *ground*, so a blocker on a cell
raised by 2.0 was **rejected outright** for any ray passing above ~3.0, the exact failure that
reject's own doc comment says must never happen. Both now read `true_height_for_cell`. Proved
against `BoardView`'s own placement call rather than a re-derived expectation.

**`BR52.02` filed, not fixed:** a test file that fails to parse is dropped from the run and the
suite still exits 0. Walked into it while renaming `_near_ray` — ten tests vanished and the gate
stayed green.

### taskblock-52 Pass A — the seam baseline, re-taken, and the recorded cause overturned

**The 56/200 figure reproduces exactly, and it does not mean what both living documents said it
meant.** `SeamSweep` (`src/logic/seam_sweep.gd`) is taskblock-35's uncommitted harness rebuilt and
committed: a shooter in a fully enclosed room, shots swept over angles x lateral offsets, counting how
many resolve against nothing. Parameterised by the thing that fires, so the plane and the ray chain are
measured by one instrument rather than two.

**Reproduced at 56/200 in an 11x11 room** — and only in an 11x11 room. Sweeping room size showed the
count tracking the room, not the walls: 9-room 80/200, 11-room 56/200, 13-room 24/200, and **17, 21 and
31-rooms zero**. That is the shape of a measurement of the *room*, not of a projection artifact.

**Three measurements say the recorded diagnosis is wrong.** `BUGS.md` (`BR34.05`) and `PLAN.md`
(*Wide scatter passing through a wall seam*) both record the cause as adjacent wall cells' projected
rects failing to tile edge-to-edge, letting a wide dartboard point thread a real gap.

1. **The threshold is the wall's own face.** Swept in 0.25 steps along one axis: every offset to **5.25**
   hits, every offset from **5.50** misses. The perimeter wall box's outer face is at exactly 5.50. A
   seam would scatter empties across offsets and angles; this is one clean edge sitting on the geometry.
2. **The vanishing rounds start outside the building.** `DamageResolver` tests every region at a
   *constant* lateral offset, so a scattered round is modelled as a ray **parallel** to the
   shooter-to-target line, translated sideways by the whole dartboard displacement. At lateral 6.0 in an
   11-room the flight begins at (5.00, 11.00) — `in_bounds` false. It never reaches the wall to thread it.
3. **No seam is measurable.** A 41x41 room, 90 angles x 41 offsets out to 15, every offset well inside
   the walls: **0/3690 empty.**

**So the defect is in how scatter is modelled, not in how walls are projected** — and the ray chain
fixes it structurally rather than by patching, since a march from the real muzzle to the aimed point
diverges from the gun the way a real round does.

### taskblock-52 Pass A — the plane does not amortise across a burst, and the cost case rested on it

**A 12-round chaingun burst builds 20 shot planes.** `DamageResolver.resolve_shot` builds its own plane
on entry — every pull, every pellet, every ricochet hop — so the plane `BurstAction` builds up front is
used only to pick the aim point. The stated trade ("one build serves a whole burst, then N cheap
point-in-rect tests, where a ray chain pays per round") describes something the code does not do.

Measured on a real 217-blocker board (`tools/shot_cost_bench.gd`, debug build):

| | usec |
|---|---|
| plane build (1291 regions) | **8 509** |
| one shot (build + walk) | **8 549** |
| of which the walk | **~260** (noise; one run measured -52) |
| one 12-round burst | **183 000** |
| planes per burst | **20** |

**~97% of a shot's cost is building a plane it then barely uses** — 2.44% of regions contain the aim
point in the test fixture. `test_shot_plane_amortisation.gd` pins the counts (deterministic and
machine-independent) rather than the timings.

**A number that informed the decision turned out to be stale.** `BR26.02` recorded `ShotPlane.build` at
**35 258 usec**; a bare build on a comparable board now measures **8 509**. The two were taken through
different call paths — the historical figure came off `aim_state()`, which also cloned the state before
taskblock-51 memoised it — so this is not a claimed 4x win, it is a warning that the figure the trade
was being argued from no longer describes the thing it names.

**`tools/bench_release.sh` takes a `BENCH` env var** (`ai_planning` default, `shot_cost` new) and
`bench_main.gd` takes `--bench=`; every existing invocation is unchanged.

### taskblock-51 — a CC-owned sweep: `BR35.03` confirmed closed, `BR35.01` mitigated

**`BR35.03` was already fixed and only needed confirming**, exactly as its triage predicted. taskblock-42
Pass E gated the board rebuild on `DebugVerbs.affects_board(verb_id)` and **both** overlays carry it.
Closed on a reading, with no change made — recorded that way rather than as a fix.

**`BR35.01`: a cheap reject before the per-box test.** `PartPicker.hit` ran a full assembly ray test
against every blocker and field item regardless of the ray's direction — a handful of props when it was
written, 200+ wall cells since tb31 C, on every mouse motion. It now skips a cell whose perpendicular
distance from the ray exceeds `SKIP_RADIUS`. **18 454 -> 14 390 usec per motion (54 -> 69 fps)** on the
same probe this block has used throughout; with the earlier tooltip fix that is **42 527 -> 14 390**, a
third of the original.

**Stated plainly: this is a mitigation, not the structural fix.** The scan is still linear in blocker
count with a cheap reject in front; a spatial index is the real answer and was not attempted. The reject
is conservative by design — admitting a cell the real test rejects costs time, rejecting one that would
have been hit is a shot through a wall.

### taskblock-51 — detonations reach cover, chain in waves, and go off where they actually are

**Cover takes the blast.** `detonate()` iterated `state.units` and nothing else, so a barrel beside a
barrel could not chain and an explosion beside a wall left it untouched — the same units-only assumption
that had hidden the drawing gate. Blockers in radius now take the damage.

**Chaining is the supervisor's stated shape:** *"chain react simultaneously, then in order, they should
never re-explode something that's already exploded."* Everything in one wave goes off together and its
damage lands before the next wave is decided. **Termination is the exploded set, not a depth cap** — a
bound that says "this cannot go on forever" is not the same as one that says "nothing goes off twice",
and only the second was asked for. Two barrels in range of each other are the case that loops without it.

**And a blast is centred on the exploding part, not its owner's cell** — the supervisor's catch:
*"an ammo rack on a unit's back may be higher up or offset."* `_locate_cell` returns the unit's cell, so
a mounted part detonated at its wearer's feet. `UnitGeometry.assembly_placements` already composes each
part's real world transform — what renders the box and what `PartPicker` hits — so that is asked rather
than a second answer derived. Measured: a mounted plate logs `(5.00, 1.25, 5.15)` where it used to log
`(5, 0, 5)`. **The test uses a sub-part deliberately**: the shell root legitimately sits at the unit's
base, so a root-part fixture passes on the broken version too.

**`Detonation` is now its own file**, split from `DamageResolver` when chaining pushed that past its
1000-line cap. `DamageResolver.locate_cell` became public rather than copied, since a second "where is
this part" would be the parallel system this project keeps deleting.

**Filing correction (supervisor):** defects in a system actively being built are not bugs, they are
symptoms of work in progress, and belong in the report until the system settles. Three entries CC had
filed were withdrawn on that basis; the session's one real defect — a part destroyed by an explosion
vanishing from inspect while staying on the model — is filed as `BR51.24`.

### taskblock-51 — `set_part_hp` is a board-changing verb

One line, and it explains a paired symptom the supervisor reported: a barrel forced to 0 hp stayed drawn
while inspect showed an empty tile. `set_part_hp` was absent from `BOARD_CHANGING_VERBS`, so
`sync_board_view()` never ran after it — correct while the verb only changed a number, wrong the moment
`BR51.20` let it destroy things.

**The remaining reports from that session are filed rather than fixed**, because each is a decision:
`BR51.21` (no injection ever animates — the overlay never calls `ResolutionPlayer.play()`, which is why
the explosion sphere cannot appear on this path), `BR51.22` (detonations damage units only, never cover —
`detonate()` iterates `state.units` and nothing else), and `BR51.23` (a detonation is centred on the
owning unit's cell, so an ammo rack explodes at its wearer's feet — the supervisor's own catch, and CC
chose wrong).

### taskblock-51 — `BR51.20`: zeroing a part now runs its failure mode, and one place emits a detonation

`BoutInjector.set_part_hp` set the number and stopped. `DamageResolver.resolve_part_failure` — the only
thing that runs MANGLE / DISABLE / DETONATE / FRAGMENT / MELTDOWN — had exactly one caller, inside impact
resolution. So a goo barrel forced to 0 hp sat there intact, and **forcing a detonation, the entire point
of being able to target a barrel (`BR51.02`), never worked**. Nothing in this block had ever set one off.

**`resolve_part_failure` takes a nullable `ImpactResult`** and writes results only when there is one, so
the injector invents no hollow stand-in — that would have been a second failure path beside the
resolver's.

**And the detonation event moved to where the failure happens.** It was emitted by
`ShotResolution.log_impact_result` off the impact, which meant a failure with no impact resolved
mechanically and logged nothing. `DamageResolver` emits it now: one emitter, both callers.

**Two costs, recorded rather than glossed:** the event is centred on the exploding object's own cell
rather than the bullet's strike point (more correct for an explosion, but it is a change), and it logs
**unattributed** — `ImpactResult` carries no attacker, and threading one through three layers for a
visual fix was not worth it. That is a real loss against the previous emission site.

**This is a synthetic failure, and the supervisor's caveat stands:** what matters is a barrel getting
shot, and this forces the consequence without the cause. It makes the consequence observable; it does
not verify the shot path, which is `BR51.01`'s job.

### taskblock-51 — a detonation draws because it detonated, not because it hurt someone

**The supervisor's argument closed a gap CC had merely documented:** *"if something is exploding, isn't
it a part? Shouldn't it always draw because it catches itself in the explosion?"*

`DamageResolver.detonate()` iterates `state.units` only, and a goo barrel is a **blocker** — so it is
never in its own blast list. Gating the drawn sphere on `detonated_units` therefore hid every explosion
that caught nobody, which is most of them. `ImpactResult` now carries **`detonated`**: that it went off,
which is a different fact from whom it hurt, and it is what the event is emitted on.

CC had recorded this as a known gap needing "a fact the resolver does not currently return". The fact was
one line; the reason it stayed a gap is that CC treated a documented limitation as a resolved question.

### taskblock-51 Pass C — `BR35.08`: detonations are visible, at their real size

Built to the supervisor's spec: a translucent red sphere from the detonation point, growing outward to
the **actual explosion radius**, then fading. **Grow : fade is 1 : 3**, and the total is a tunable beside
the other bullet timing (`DETONATION_MS`, 1000 ms).

**The radius travels in the log rather than being chosen in the view**, which is the whole point — a
drawn extent computed view-side would be `BR35.04`'s decorative tracer wearing different clothes. A new
`detonation` event carries the centre and `part.detonate_radius`, and is emitted **once per explosion**;
the existing `detonate` events are one *per affected unit*, which is right for damage bookkeeping and
would have stacked one sphere per victim.

**Known gap, stated rather than hidden:** a detonation that harms nobody produces an empty
`detonated_units` and so draws nothing. Reaching it needs a "this part detonated" fact the resolver does
not currently return, distinct from "these units were hurt" — the same shape as `BR34.05`, where absence
of a thing to hit is indistinguishable from nothing having happened.

### taskblock-51 Pass C — continuations are dull orange and flash with their own hit

Both supervisor-specified. A penetration or a ricochet is the **same round still travelling**, so it now
draws in a dull orange (`TRACER_CONTINUATION_COLOR`) rather than sharing the primary's bright flash —
the blue it replaces was chosen for the decorative projection deleted in `BR35.04` and made a
continuation look like a second, unrelated shot.

**And a pull's hops flash together rather than in sequence.** An event whose successor continues it is
started without being awaited, so only the final hop of a pull is waited on: one trigger pull is one
visual event, a bright primary with its dull-orange continuations alongside. `BR27.03` records that
these were always supposed to resolve simultaneously; taskblock-27 Pass A2's `DEFLECT_BEAT_MS` was a
deliberate pause built on the opposite assumption and is now unused rather than merely reclassified.

**Guarded against the obvious over-reach:** a *new* pull is never folded into the one before it, and
only an `impact` can continue a pull — a `move` or `faced` between hops ends it, so a tracer is never
drawn concurrently with an unrelated animation.

### taskblock-51 Pass C — a hop is not a new shot (`BR27.03` / `BR34.01` pacing)

**The supervisor's correction to the previous entry:** deflects should be *visible*, the blue lines were
simply reporting something that did not happen. *"When a bullet is fired, I want to be able to see what
it hit, and then where it went."* That is what removing the decorative projection leaves — the real
continuation. `resolve_shot` returns one `ImpactResult` per hop and `resolve_and_log_point` logs them
adjacently, so a ricochet that finds a target already draws from the deflection point to its real hit.

**And the pacing was the other half.** *"All shots would land and tracers flash, THEN the deflections
would flash, even though logically a shot would land and deflect right after each other."*
`ResolutionPlayer.play()` inserted `INTER_SHOT_BREAK_MS` between **every** consecutive impact, so a
single trigger pull that hit a wall and carried on read as two gunshots a tenth of a second apart.

Impacts now carry a **`hop_index`** — 0 is the shot, anything higher continues it — and only hop 0 takes
the between-shots break. A round reads as one object travelling rather than as a reply to itself. The
decision is a named static (`starts_a_new_pull`) so it can be asserted directly instead of by measuring
wall-clock gaps, and an event with no `hop_index` defaults to starting a pull, so fragments, misses and
pre-existing logs are never silently glued together.

**Still open in this cluster:** `BR35.07` (`STOP_DEAD` overshoot), `BR34.05` (misses vanish — a logic
defect, not a drawing one), `BR35.08` (detonations draw nothing), and `BR34.01`'s other half, the bright
flash replaying per hop rather than once per pull.

### taskblock-51 Pass C — `BR35.04`: the decorative deflect projection is deleted

**The cluster's suspected shared root, located.** `ShotResolution.log_impact_result` stamped
`deflect_end_*` on **every** DEFLECT: the reflection direction pushed out to `max_range`, with its own
comment stating the intent — *"so the reflected direction is always drawable regardless of whether a
real ricochet hop follows it"*. `ResolutionPlayer._play_impact` then drew that as a second, blue
segment. A line to an arbitrary distance, corresponding to nothing that resolved, and on screen
indistinguishable from a real hit. It invented the wall impacts the supervisor spent a review session
investigating.

**Removed, not reconciled** — the supervisor's explicit call. A ricochet that finds a target logs its
own `impact` with a real origin and hit point and draws through the ordinary path; one that finds
nothing now draws nothing, which is the truthful answer. `ImpactResult.reflected_dir`/
`reflected_vertical` are untouched; the resolver needs them to recurse.

**Four existing tests asserted the defect** and had to be rewritten, not merely updated: "a deflect
draws a second tracer", "N deflects draw 2N segments", "the second segment is blue", and the
logic-side "a DEFLECT carries a deflect endpoint". None was wrong about what the code did; all four
were wrong about what it should do, and together they held the defect in place. A fifth was added: a
log written *before* this change still replays without inventing geometry, because the view no longer
reads those fields at all.

**What this does NOT yet fix, stated so the cluster is not assumed closed:** `BR35.07` (`STOP_DEAD`
drawn past its hit point), `BR34.05` (misses vanish — which is a *logic* defect, "miss" being modelled
as terminate-the-round rather than continue-until-something-stops-it), `BR34.01` (every hop replays the
full hit flash), `BR27.03` (inter-event sequencing) and `BR35.08` (detonations draw nothing, which needs
the supervisor's specified growing red sphere). The primary tracer was confirmed faithful — it draws
real `origin_*` to real `hit_*` — so those four are not instances of this same substitution.

### taskblock-51 — `BR51.11` (the long way round), corpses as wrecks, and the catch-up theory disproved

**`BR51.11`: `tween_method` interpolates plain numbers.** `ResolutionPlayer` handed it raw orientations,
so 0.1 -> 6.0 ran 336 degrees left instead of 24 right. It now tweens towards
`from + angle_difference(from, to)` — the same facing, numerically adjacent to the start. **The test
asserts the arc, not the endpoint**, because the broken version arrives in the right place too; verified
by reverting, where four of six angle pairs take the long way. Squad 1 and not squad 0 is a
distribution of starting facings, not a squad rule, and that is pinned so the fix is not read as a
squad-specific patch.

**Corpses are selectable as wrecks** (supervisor's decision): *"Dead units should not be selectable as
units. They should be selectable in the same way parts on the ground or cover is."* Pass K is what made
this a one-line answer — a `PART` target already describes "a thing on the board with parts on it", so
a wreck needs no fourth kind. **Nothing can be commanded through one**, because only a `UNIT` target
reaches the queue; a wreck is inspectable and nothing else. Both click dict shapes resolve it.

**The catch-up hypothesis is disproved by the instrument built to test it.** Eight dumps all read
`fastest 3915.8 (prev 116.2, next 260.0)` — the frame *before* the spike was 116 fps, not a stall, so
the 0.255 ms frame is not paying back an overrun. The proposed `BR51.15`/`BR51.17` merge is withdrawn.
The maximum is still an artifact (a frame that did no drawing), so `BR51.17` stays open with the
catch-up remedy removed from its options. **Also visible: the game is not capped at 160** — `avg less
top 1%` reads 177-185, above the monitor's refresh, exactly the uncapped condition the supervisor
predicted when they specified these figures.

### taskblock-51 — the performance readout reports the fastest frame's neighbours

**The supervisor's question, made answerable:** *"Is it queuing frames for some reason, and when those
finally get to hit, they run over?"* A frame that takes almost no time because the previous one overran
reports a huge `1 / delta` — bookkeeping, not throughput.

Two readings in their live dumps support it. `instant` hit **212.6** against a 160 Hz cap, so
above-refresh frames are genuinely being produced; and the reporting fraction bounds the spike exactly
— **one frame in 4 585** sits within 1% of the maximum, an isolated outlier rather than the top of a
cluster.

The signature of catch-up is **adjacency**, so `PerfStats.fastest_neighbourhood()` returns the fastest
frame together with the frames either side of it, and `describe()` carries a sixth line:
`fastest 2013.4 (prev 7.9, next 148.0)` reads as a stall being paid back, while
`fastest 161.2 (prev 158.0, next 159.4)` is simply the fastest of a healthy run. **Both cases are
tested** — without the contrast case the figure could not tell them apart and would be decoration.

**This is what should decide `BR51.17`.** If the maximum is a catch-up artifact then anchoring the
top-1% cut to it is anchoring it to noise, and the fix is excluding frames that are not real frames —
not a different percentile. That is a better answer than any of the three CC offered, and it came from
the supervisor's observation. **Possibly one defect with `BR51.15`**: `min` has read 7.4 in every dump
this session, so if the fastest frame sits immediately after a ~7 fps frame, the stall and the bogus
maximum are the same event seen from both ends.

### taskblock-51 — `BR51.14`: hovering tiles cost a `CombatState` clone per mouse motion

**Measured before it was touched**, per the entry's own instruction not to assume it was `BR26.02`
again. On a 216-blocker board, one motion while merely hovering with a unit selected:

| | usec/motion | clones per 30 calls |
|---|---|---|
| before | **42 527** (23 fps) | 48 |
| after | **18 454** (54 fps) | 19 |

The supervisor reported 160 fps falling to ~20, which the first number matches almost exactly.

**The cause was not the per-event rate, it was a clone.** `TooltipController.refresh()` was connected
to **both** `hover_changed` *and* `mouse_moved` — and `mouse_moved` fires unconditionally on every
motion, while `refresh()` calls `SelectionController.previewed_unit()`, which is a `CombatState.dup()`.
Following the cursor across one tile does not change a word of what the tooltip says, so `mouse_moved`
now only **repositions** (`TooltipView.move_to`, which already existed privately) and rebuilds only when
the hovered target changes or the queue's revision does — the latter because `TileInspection` runs from
the *previewed* unit, so a queued move changes what a tile reads as without the hovered cell moving.

**And the hover is coalesced to one update per drawn frame**, which the reticle got in `BR26.02` and
this path did not. A 500-1000 Hz mouse against a 60-160 fps game ran it hundreds of times per frame.
Safe for the same stated reason: it is an absolute raycast through the literal cursor, not an
accumulated delta. The companion test asserts an idle frame still costs nothing, so the per-event cost
was removed rather than moved.

**The remaining 19 clones are real rebuilds** — one per genuinely new hovered tile. Memoising
`previewed_unit()` is where the next win is, and `BR26.02` recorded two attempts at it that were
reverted for concrete reasons (callers mutate the previewed unit; state changes within a frame), so it
is left alone rather than retried blind.

### taskblock-51 Pass L — death mid-turn, and an indicator fixed on one call site out of two

**`BR51.09`: the selection invalidates on read, not on an event.** `SelectionController` never
referenced `alive` anywhere, so `selected_unit` was a raw reference that outlived the unit it pointed
at — kill the acting unit and its reachable-cell overlay kept drawing into the next unit's turn.
Notifying the selection from `kill_unit` would have put a TACTICS-time concern inside a RESOLUTION-time
mutation and still missed every *other* route by which a unit stops being valid, so `selected_target`
now guards on read. **A call site cannot forget to subscribe to something it does not subscribe to** —
asserted by killing a unit behind the controller's back and never telling it. The unit's queued plan
goes with it, since `_queues` is keyed by unit id.

**`BR27.07`/`BR32.09`: the same bug, unfixed on the second call site.** tb32 Pass D deferred the
active-turn flip until after playback in `SquadControlOverlay`, with a comment calling it "a real
confirmed bug" — and changed only that one caller. `SpectatorOverlay._advance()` went on applying the
highlight *before* `resolution_player.play()` drew the previous unit's move. That is exactly the
supervisor's controlled comparison — *"the indicator moves to the next unit before the animation
completes when the AI is controlling; it moves with the unit correctly when the player is
controlling"* — and the reason the player path passes today is that a human turn ends *after* its own
animation, so it never exposes the gap. The AI path now defers and applies identically.

**Coverage gap, stated rather than papered over.** The deferral primitive is tested directly:
`apply_highlight = false` genuinely withholds the flip, `apply_active_turn_highlight()` genuinely
performs it, and the default still applies. **Driving `_advance()` end-to-end headlessly is not
covered** — a spy standing in for `ResolutionPlayer` hangs the runner rather than failing it, since a
runtime error under `-d` becomes a debugger break. The ordering inside `_advance` is verified by
reading it against the player path it now matches.

**Not decided, deliberately: whether a dead unit is selectable.** The addendum asks for that to be a
decision rather than a consequence, and Pass K made "select the wreck" expressible. It is a design
question and is left to the supervisor — what Pass L fixes is the stale pointer, which is not the same
question.

### taskblock-51 — `BR48.01`: the board was accidentally double-lit, and inspecting took the second light away

**Found by dumping the battle world rather than by reading the code** — two confident diagnoses had
already been wrong, and the dump settled it in one run. At rest, before anything is inspected, the
battle `World3D` had **four** lighting contributors: the board's own `WorldEnvironment` and
`DirectionalLight3D`, **plus the inspect panel's**. After one inspect cycle it had two.

`SubViewport.own_world_3d` **defaults to false**, so `InspectPanel`'s private `WorldEnvironment` and
`DirectionalLight3D` have been in the battle's world since the panel was built. Nothing looked wrong,
because the extra light only ever made the board brighter. It becomes visible the first time a subject
takes the **fallback path** — `open()` with no live view, which is what cover, a loose item or a bare
tile resolves to — because that sets `own_world_3d = true` and takes both nodes **out** of the battle
world. The board drops to its real single-light level and stays there, since `_isolate_clear()` never
restores the flag. **A new bout rebuilds the panel and the accidental second light comes back**, which
is the supervisor's own *"starting a new bout does fix it"* — the detail that proved it, and that
neither earlier theory could explain.

**The preview's lighting is now withdrawn whenever the viewport shares a world**, applied at build time
as well as on every transition, so the battle's lighting is constant. The flag itself is left alone:
assigning `own_world_3d` runs Godot's scenario attach/detach and errors with `Parameter "scenario" is
null` where no scenario exists yet — which is why "release the world on close" and "claim our own world
at build" were both tried and both abandoned.

**And the brightness is restored, as a measurement rather than a new number.** The supervisor preferred
the old look, so `WorldPalette.BOARD_LIGHT_ENERGY = 2.0` puts the board back at exactly what was on
screen: the two lights were identical in rotation and energy, therefore additive, therefore 2 x 1.0.
**Ambient is deliberately not doubled** — the two `WorldEnvironment` nodes were *not* additive (Godot
resolves one winner) and both carried the same `AMBIENT_COLOR`/`AMBIENT_ENERGY`, so ambient never
changed. `directional_light()` takes an optional energy defaulting to 1.0, so `BuilderScene` — which has
no second viewport and was never doubled — is untouched.

**Correction to this entry as first written:** it named `WorldPalette.LIGHT_ENERGY` as the tunable.
**No such constant existed** — `directional_light()` never set `light_energy` at all, so the board ran
on Godot's default 1.0. `BOARD_LIGHT_ENERGY` is new.

### taskblock-51 — `BR48.01`, second attempt (superseded by the entry above): the preview's lighting nodes

**The supervisor's own diagnosis, and it was right:** *"this may not be a UI issue, it may be lighting
as the inspect panel draws the clicked item, and the lighting might be custom there, and then said
lighting doesn't get reset to board style."*

`InspectPanel._preview_viewport` carries a `WorldEnvironment` **and** a `DirectionalLight3D` for its
fallback path, which renders a fresh copy in its own isolated world. The isolate-camera path — what a
click on a live item takes, so the panel shows the *actual* unit on the field — needs the opposite,
`own_world_3d = false`, and that puts **both nodes into the battle's `World3D`**: a second environment
and an extra directional light over the whole board. The comment beside them already flagged that a
second `WorldEnvironment` there "isn't a well-defined 'also applies' situation", and solved it only for
the preview camera via a per-camera override; the main camera was left to whatever Godot resolved.

It persists after closing because **`_isolate_clear()` deliberately never touches `own_world_3d`** — its
own comment says so, written in taskblock-22 for an unrelated reason. Inspect one live subject and the
viewport stays world-shared for the rest of the session.

**The fix ties the preview's lighting to who owns the world**, not to open/close: while the world is
shared, the light is hidden and the environment detached, so it is never in the battle world in either
state. The preview camera's own `environment` override already gives it the right ambient regardless of
which world it lands in, and the subject is lit correctly because it genuinely is on the board. The
fallback path keeps its lighting, which is the only lighting in its isolated world.

**Two approaches were tried and abandoned first, both recorded because each failed for its own reason.**
Releasing the shared world in `close()` asks Godot to detach a viewport from a scenario it has already
left — `Parameter "scenario" is null`, an error rather than a no-op — and reordering `close()` to
release before hiding did not help, because the detach is invalid regardless of order. Making the
assignment idempotent removed a redundant flip but not the genuine one. Tying the lighting to world
ownership avoids the flip entirely.

### taskblock-51 — `BR48.01`, first attempt: an empty modal on a bare tile

**The trigger was the open path, not the close one**, exactly as the supervisor's re-diagnosis said.
`Grid.blockers.get(cell)` is **null for a bare tile** — `open_tile`'s own doc says so — and the
spectator's fallback passed that straight in. The panel renders its matrixless shape regardless (every
`_refresh_*` no-ops gracefully on a null root, by design), so clicking empty ground opened a 900x600
modal containing nothing and paused the bout. It reads as a dim that will not lift because there is
nothing in the panel to explain what happened. A cell whose blocker the ray missed but whose ground
position was hit still opens — that is a real object, coarsely picked.

**"Does a second open/close make it darker" is now answered rather than eyeballed.** Stacking and
persisting are indistinguishable from the chair, so the tests read the real nodes back: the preview
camera's `cull_mask` is what `_isolate_focus` narrows, and `_isolate_clear` restores it from a value
captured once at build time and never re-derived — so it cannot ratchet. Asserted across two full
cycles and across opening a second inspect over the first, which is the close path that never presses
a button. **It does not stack.**

**The test that should have caught this was named for it.**
`test_clicking_a_bare_tile_or_a_tiles_object_opens_the_same_inspect_panel` only ever places a crate —
its name covers the empty case and its body does not, and the defect lived in that gap. Second instance
of narrower-than-its-name in this block, after the log fold's diagnostic assertion. Verified by
re-breaking the fix: both new assertions fail without it.

### taskblock-51 Pass K — selection understands more than units

**The root was a missing type, not a broken rule.** `SelectionController` held one slot,
`selected_unit: Unit`, while `PartPicker.hit` had always scanned `grid.blockers` and
`grid.field_items` — so the picker saw barrels, cover, walls and field items and selection had
nowhere to put them. Four reported symptoms were that one gap from different directions.

`SelectionTarget` (logic, headless) holds `UNIT` / `PART` / `CELL` plus an empty target that answers
questions rather than being `null`. **It wraps the hit dict `board_clicked` already emits** rather than
introducing a second vocabulary. `selected_unit` survives as a **derived property** — eighty-one
readers still mean it, and a second stored field would drift from the target.

- **Clicking cover selects the cover** (`TacticsController._click_part`), where it previously did
  nothing unless an action was armed. **This drops the unit selection**, which is a real behaviour
  change; the queue survives, being keyed by unit id.
- **A cell click with a unit selected is still a move order.** Tile selection was added where there was
  nothing, and nothing was taken away.
- **`BR51.02`'s remaining defect is closed at the source.** `click_cell`'s capture branch reported
  every non-unit click as a bare `CELL`, so cover could never become the debug panel's active target
  and every OBJECT-target verb inherited the hole — while the ray path resolved `PART` correctly. Two
  paths disagreeing about what a click means was the bug.
- **`BR51.10`: Inspect is disabled when the target has no body**, driven by the selection rather than
  by "has anything been clicked". `InspectPanel.open_tile` could always describe a loose part; the
  capability was simply unreachable from the board.
- **Spectator picks parts, not just units**, and **only opens the modal for what it can describe** —
  opening it for an unrenderable target left the dim over the board with nothing on top (`BR48.01`'s
  shape).

**A refusal names what it refused.** The `"refused"` status path already existed, so this was smaller
than triage assumed — what was missing is that it did not say *which* target it declined, which starts
mattering once a bare tile or a barrel can be the active one. It reads `Set Part HP: refused (cell
(4, 4))`. **Only OBJECT-param verbs name the target**: for the rest the active item is not what they
acted on, and naming it would report the wrong cause for their own failure.

**A bug found while building it:** `PartPicker.hit` returns `{unit, part, cell, t}` with **no `kind`**;
`board_clicked` emits `{kind, unit, part, cell}`. Routing a raw pick through `from_hit()` classified
every hit as a bare cell and stopped spectator unit clicks pausing the bout. Each shape now has its own
named constructor, and the trap is asserted.

### taskblock-51 — `BR51.13`: a plumbing run folds one kind, not any plumbing

`fps_dump` and `wall_cutout` are both plumbing kinds, and the fold grouped any consecutive stretch of
*any* plumbing kinds — so a framerate measurement between two wall-cutout events was swallowed by their
counted row. Runs now break on a change of kind: eleven consecutive `fps_dump` events still fold into
one row, so the anti-flooding purpose it was added for is intact.

**A passing test sat beside this the whole time.**
`test_a_diagnostic_keeps_its_own_row_and_is_never_folded_into_plumbing` protects the kind literally
named `diagnostic`, which is absent from `PLUMBING_KINDS` and never reached the folding code. Its name
claims a general rule; it asserts a membership check. **And an existing test asserted the defect** — it
required a mixed run to be labelled "2 log events". That test was not wrong about what the code did,
only about what it should do, which is the harder kind to catch.

**The current-state snapshot**, by system, with the taskblock that landed each. Grows as work ships.
For what changed shape along the way see `SUPERSEDED.md`; for what's next see `PLAN.md`.

**A changelog logs changes — it is not a code-you're-proud-of log.** Three kinds of entry belong here
that are easy to leave out, and all three are worth more than another success line:
- **Approaches tried and reverted.** "A greedy distance scorer was tried first and reverted, because it
  reproduces the concave-wall freeze" saves the next person from re-trying it. A dead end that isn't
  written down gets walked twice.
- **Partial wins, stated honestly.** "Halved the cost, did not eliminate it — the remainder is real
  per-cell geometry work" is the useful form. Rounding a partial fix up to a complete one is how a
  known-incomplete thing gets treated as done.
- **Audited and found correct.** When a sweep checks N sites and finds them fine, that conclusion is a
  current-state fact and belongs here — it is exactly what stops the next audit re-deriving the same
  ground. Record what was checked and *why* it holds, not just that it passed.

**When a later change overwrites an entry, mark the old one and point forward to the newer entry** —
don't silently leave a description that has stopped being true. A stale entry in a current-state
snapshot is worse than a missing one, because it still reads as authoritative.

*Current as of taskblock-48 Passes A–D landed — the suite has three rungs (a ~3.7 s targeted run, a
~126 s fast gate, a ~450 s full gate), one runner that both counts and fails, a run window in the game
that replays failing tests as real bouts, a shared bout corpus, and a budget that can finally see
view-only cost. taskblock-47 Passes A–E landed — the suite is profiled, budgeted on deterministic work
counts, split into a 119 s fast gate and a 537 s full gate, and audited down from 4545 turns to 1578.
**The block's biggest finding was not about the suite**: `CompletionSampler` had been naming a retired
playstyle as its profile id since taskblock-46 Pass E, so every completion rate measured in between ran
with the AI's profile weights switched off — the real figure is **72%**, not 56%, and `BR45.03`'s gap to
the old planner is 3 points rather than 19. Previously current as of the post-taskblock-46 search-memory fix — `ROAM`/`HUNT` no longer oscillate between two
cells (`BR46.01`, completion 56% over 100 seeds, unchanged within noise — the fix moved the failure
mode, not the rate), and the hunt for the other half of that report found that **16 of 40 generated maps
contain ground a unit can walk into and never leave** (`BR46.02`, open, a design call). taskblock-46
Passes A–F landed — AI v2 part three: raised rooms no longer punch pits
under cover and spawn tiles (BR40.03/BR40.04), the completion number is a random sample with a
deterministic escalation behind it rather than a pinned pessimistic window, four search verbs give a
unit with nothing in sight something to do, `Panic` names the give-up instead of shrugging silently, and
the `docs/11` tier table is filled in with an Elite depth 2–3 lookahead — **but nothing authors
`intelligence_tier`, so every unit in every measured bout is `TRAINED` and most of that table is
reachable from tests only.** Completion moved 54% → 60% across the block; `BR45.03` is narrowed, not
closed. The playstyle vocabulary is deleted outright and a bout names a `UtilityProfile` id directly.
taskblock-45 Passes A–E landed — AI v2 part two: the engagement-score planner is
deleted and a utility scorer over data-authored actions replaces it. Per-candidate `ShotPlane` casts
are gone outright (29.1 builds per turn → 0.0) and plan cost fell 485ms → 131ms, but **mission
completion fell 87.5% → 54.2% over 24 seeds and `MIN_COMPLETION_RATE` sits at 0.35 rather than its
old 0.5** — a known, characterized regression carried forward as `BR45.03`, and the highest-priority
AI item in `PLAN.md`. taskblock-44 Passes A–D landed — AI v2 part one: the release-vs-debug number
exists (~1.29x, so debug overhead is not the explanation), the line-of-fire query is inverted, the
WorldView information seam is in, and a unit's turn is navigable rather than frozen. taskblock-43
Passes A–D landed — the AI planning-cost block, whose most useful result is that the candidate search
it attacks is only ~25% of a planning turn and the LOF prefilter scan is the rest (see "AI planning
cost" below). taskblock-42 Passes A–E landed (F and G held — see below). taskblock-41 Passes A–F —
"Diagnostics: the log becomes the instrument" is closed, and so is "Checkpoints return as an ordinary
tool." The combat log now carries engine and script errors, pairs every command with its outcome and
a reason, narrates a bout build in construction order, and draws itself as a real window with a live
framerate on it. Checkpoints are a tool again rather than a gate, guarded in CI by parsing what
cannot be rendered. See `PLAN.md`.*

---

## Combat core

**Part graph** (tb01–02, docs/01/01a) — inverted attachment (parts declare `attaches_to`, sockets
declare `socket_type`); socket ids; socket transforms (sockets = joints, parts = bones); limb
decomposition; capability tags (`TRIGGER`/`SUPPORT`/`GRIP`/`POWER`) + weapon `requires`; keyed
cladding vs generic plates. Bot builder debug scene over the real `BodyAssembler`.

**Geometry & targeting** (tb02/06/07/23, docs/02) — continuous projection, no exposure table,
retaining each part's real vertical position (tb23 A: a head projects higher than a waist, no
longer flattened to one height plane); depth-sorted shot plane with gap fall-through (the sniper
thread); dartboard scatters isotropically in both the lateral and vertical axes (tb23 B);
`resolve_ray(muzzle, dir)` the resolution seam, now a true 3D ray — a shot can pass over a short
part into a taller one behind it, and a ricochet branches vertically as well as horizontally
(tb23 C); `READING`/`RESOLVES` never conflated. **Muzzle-anchor fix** (tb27 A1) — every attack
action now builds its shot-plane `origin` from the SAME shouldered-muzzle point as its `direction`
(previously `direction` used the shooter's cell, `origin` its own muzzle — the mismatch could
resolve a target at negative depth relative to the ray, animating as the burst firing backward).
Shot/deflect impacts also now hold a deliberate beat (`DEFLECT_BEAT_MS`) between the primary hit
and its own deflect tracer (tb27 A2), instead of both resolving in the same instant.

**One geometry: the 2D/3D shot-plane split closed, and the first slice of multi-level (tb36,
docs/02/PLAN.md)** — tb23 gave rays a real vertical component; the surfaces they resolved against
stayed 2D for three more taskblocks. Four passes, each re-running a seeded full-mission bout (seed
12354) and diffing its combat-log event stream byte-for-byte against the pass before it — every
pass landed with **zero observable change** to that bout, the standing proof that none of this
altered a single level shot.
- **Pass A** — `BodyProjector.project`/`project_assembly`/`project_part`/`_project_box` and
  `ShotPlane.build` widen to `Vector3` origins/directions; every existing caller wraps its flat
  `Vector2` with `y == 0.0`. Pure plumbing, provably inert.
- **Pass B** — `_FACE_NORMALS`/`_FACE_CORNERS` grow from four side faces to six (`+/-X`, `+/-Z`,
  `+/-Y`), each carrying its own real 4 local corners instead of the old 2-corner-plus-tilt-
  widening encoding. The visibility test is fully 3D now — a face's real world normal (including
  its vertical component) against the ray's own real 3D direction, not the horizontal slice alone.
  **Fixes the headline bug:** a part tilted so its local up is horizontal (`Poses.aiming()`'s own
  -45° shoulder tilt, taken further — `Poses.prone()`'s 90° tilt hits this exactly, and
  `test_prone_pose_changes_the_projected_shot_plane_vs_idle` now correctly shows a SECOND real face
  where the old four-face model only ever showed one) used to go edge-on on all four old faces
  simultaneously and vanish; it now projects a real region. A face genuinely facing the shooter
  registers even with a degenerate-height rect (an untilted horizontal face's own true property in
  this plane model — see the multi-level note below); the hollow far-face rule (tb20 C3) still
  emits exactly the entering/exiting pair, not the four extra faces six candidates could otherwise
  leak.
- **Pass C** — `ShotPlane.build` does its own height reconciliation once, at the source: a
  `_shear` step converts every region's `rect.position.y` from absolute world height into height
  relative to the ray's own real path, providing "height relative to here" — the two-path
  duality (`resolve_ray`'s own real-3D-ray path vs. `build`'s ground-heading-only path) never
  fully unified because `build`'s own `(lateral, real world height) x depth-along-ground` plane
  basis is deliberately not a full pinhole camera; `resolve_ray`'s own separate `muzzle.y +
  vertical_slope * depth` reconstruction is gone, replaced by reading a plane already built that
  way. Provably a no-op for every caller except `resolve_ray` (`origin.y`/`direction.y` both
  `0.0` everywhere else, still true after this pass). The dead-vertical bail stays — an honest
  `null`, not an arbitrary basis that would silently rotate the dartboard's own scatter axes.
  **Audited and found correct as scoped:** `DamageResolver`'s own separate `vertical_slope`/
  `_find_next` mechanism (ricochet flights only, `origin_height`/`vertical_slope` both `0.0` for
  every real first-hop caller today) is a genuinely different, self-contained value, not a
  duplicate of the gap this pass retired — flagged as a candidate to reconcile once Pass D's own
  elevation reaches a first-hop shot, not this pass's to touch.
- **Pass D** — `Grid.height` (row count) renamed `Grid.rows` in the same commit that adds
  `Grid.level` (a per-cell integer, defaulting to 0, alongside `terrain`/`opacity`) — the first
  real slice of multi-level maps (docs/PLAN.md). `Unit.level` (cached, synced from the grid at
  `CombatState.add_unit`) drives `UnitGeometry`'s own root-transform Y translation
  (`LEVEL_HEIGHT = 1.0`, docs/PLAN.md's own "two ramps make one full level" math, not a number
  invented here) and a matching raise in `ShotPlane.build` (`BodyProjector` composes a body in
  body-local space and has no notion of cell/level at all — elevation only enters where a cell's
  world position already gets composed in). Deliberately inert in normal play: `MapGen` writes
  nothing (the array's own default is already 0), and `Pathfinder` never reads `level` at all.
  `BoutInjector.set_cell_level` (+ a matching debug-panel entry) is the only way a nonzero level
  exists today — exactly the tool this needs before any movement verb can force a real scenario to
  watch. **Surfaced, not a bug:** an UNTILTED box's own top face is height-DEGENERATE in this
  plane's `(lateral, world-height)` basis — a single point, not a range (`Rect2.has_point` never
  contains any point when `size.y == 0`, confirmed live) — so a shooter standing above a target
  correctly produces a real top-face `Region` (proven in `test_multi_level_geometry.gd` by reading
  the produced Region back, per this file's own testing convention — never re-deriving the
  formula), but "resolving" onto that exact single point via `resolve_ray`'s own query would mean
  solving for one exact slope, not aiming. Only a genuinely TILTED face (this pass's own headline
  case) gains real height extent. **Out of this slice, staying that way:** vertical movement verbs
  (climb/hop-down/ramps/stairs), height-aware pathfinding, fall damage, height-derived combat
  bonuses — the rest of docs/PLAN.md's own multi-level item. **Superseded by tb37 below** — every
  item in that "out of this slice" list except fall damage/height-derived bonuses (deliberately
  still out) is now built.
- **Pass E (in progress, supervisor-driven)** — the view catches up to elevation. `ResolutionPlayer.
  _world_anchor` reads `UnitGeometry.true_height_for_cell` instead of hardcoding Y=0.0, and the new
  `&"climbed"`/`&"hopped_down"` log events (both now carrying the same `"path"` shape a `move` event
  does) route through the exact same `_play_slide` machinery — a climb or hop-down plays as a real
  vertical slide with no dedicated animation code. `HitVolumeView`'s team marker and facing wedge
  offset by `unit.height`. `BoutInjector.force_climb`/`force_hop_down` (+ matching debug-panel
  verbs) let the supervisor trigger either action live — no AI path queues them yet.
  **Root-caused and fixed a "no visual change on raise" bug:** `BoardView`'s ground was one flat
  `PlaneMesh` for the whole grid, never reading `Grid.level` at all. Replaced with `_build_terrain`
  — one flat top quad per cell at its own real height, plus vertical riser quads between
  differently-elevated orthogonal neighbors, a stepped XCOM-style terrace (supervisor's own call
  over a smooth heightmap). `_build_grid_lines` got the same per-cell treatment as a follow-up
  (it was still one flat mesh at a single world height even after the ground itself went per-cell)
  — each cell now draws its own complete border at its own height, so a riser boundary frames each
  side's own step instead of one line cutting through it.
  **Level precision widened, supervisor's explicit choice over two smaller alternatives:**
  `Grid.level`/`Unit.level` go from `int` to `float` — genuinely arbitrary elevation, not just whole
  levels plus a ramp's own fixed `+0.5`. `Pathfinder.MAX_CLIMB_LEVELS`/`MAX_HOP_DOWN_LEVELS` become
  real height caps; climb cost scales proportionally to rise (`CLIMB_COST * rise / LEVEL_HEIGHT`)
  instead of a flat per-level charge. `HopDownAction`'s drop-distance check now goes through
  `Unit.height`/`true_height_for_cell` (ramp-aware) instead of raw levels, converging with
  `ClimbAction`'s own convention. **Real bug found during the level-precision audit, not just
  plumbing:** `ShotPlane.build`'s cover/blocker projection used `grid.get_level(cell) *
  LEVEL_HEIGHT` directly, missing a RAMP tile's own `+0.5` rest offset that `BoardView._spawn_
  blocker` already rendered cover at — a hit on ramp-standing cover could land somewhere the
  rendered box never occupied. Fixed to read `UnitGeometry.true_height_for_cell` like the unit
  projection just above it already did.
  **Cell picking fixed too, a pre-existing gap the terracing exposed rather than caused:**
  `BoardPicker.cell_at_ray`/`plane_hit_t` (taskblock03 D1, predates multi-level entirely) always
  intersected a fixed `y == 0` plane — correct until a cell's own real top face could move off world
  0. Supervisor: "mousing over a cell requires you to mouse over the base of the terrain, not the
  top." Both now take an optional `grid` and iteratively resolve against the real terrain (guess a
  height, find the crossing, look up that candidate cell's own real height, repeat, capped at 4
  passes so a ray skimming a riser boundary still terminates); `grid` defaults to null, so every
  flat-board caller is unaffected. `TacticsController`/`SpectatorOverlay` thread their real grid
  through at every hover/click/debug-panel-pick call site.
  **Still open, per `PLAN.md`:** the camera at height and the wall cutout against elevation, both
  needing the supervisor's own eyes, not headless-verifiable.

**Multi-level: elevation reaches the game (tb37, docs/PLAN.md)** — tb36 built the geometry and left
it wired to nothing; four passes make level mean something. Same "one seeded full-mission bout,
diffed byte-for-byte" proof as tb36 for Passes A–C (an all-level-0 bout can't observe any of this);
Pass D's own `MapGen` change necessarily reshuffles the bout's own generated map, so its seed was
re-picked (12369→12373) instead — the test file's own established convention for exactly this kind
of change, documented five times over in its own header before this one.
- **Pass A** — real muzzle height and vertical direction threaded through all six `ShotPlane.build`
  callers (`AttackAction`/`BurstAction`/`LineOfFire`/`Overwatch`/`Suppression`/`TacticsController`),
  replacing each one's own hardcoded flat `Vector3(x, 0.0, y)`. New `ShotPlane.elevation_for()` is
  the one shared helper every caller now builds its plane from (real level DELTA between origin and
  target cells, never a shooter's raw muzzle height against a target's raw ground height — the
  former cancels correctly under a uniform raise, the latter would double-count the shooter's own
  above-ground muzzle offset). `ShotPlane.build`'s tb36 `_shear` step is now opt-in (a new `shear:
  bool` param, only `resolve_ray` sets it) — it was silently correct only because no other caller
  ever passed real elevation before this pass; once they did, unconditional shear broke every
  caller besides `resolve_ray`. **Real bug found and fixed, not just plumbing:** `DamageResolver.
  _find_next`/`resolve_shot`/`_resolve_slide` assumed a dartboard aim point's height was always
  anchored at depth zero (true only for a ricochet's own fresh continuation plane) — a first hop's
  aim point sits at the TARGET's own real depth instead, so every elevated first-hop shot silently
  resolved to nothing at all until a new `point_depth` anchor was threaded through the whole chain.
- **Pass B (BR36.01)** — fixed at the source: new `PartGraph.walk_with_joints()`/`Shell.
  all_parts_with_joints()` (NOT a change to `walk()`/`all_parts()` themselves — those back
  `living_parts()`'s hp>0 filter, and a joint handle's own hp defaults to 1 and is never touched by
  joint damage, so repurposing them would make every unit's own joints read as permanently-living
  parts). Used by all six self-exclusion call sites and by `DamageResolver._body_of`'s own ricochet
  continuation exclusion. **Live-fire finding:** the seeded bout diverged after this pass alone,
  isolated to the ricochet fix — a shot that deflects off a body could previously re-hit that SAME
  body's own joint region at point-blank range instead of continuing its flight, reachable at level
  0 all along, not an elevation-specific bug.
- **Pass C** — `Pathfinder.move_cost` becomes an edge cost (`from`, `to`), not a per-destination one:
  a new `Enums.TerrainType.RAMP` is ordinary pathing regardless of level delta (1 MP, no special-
  casing); climbing up with no ramp is capability-gated (new `Shell.can_climb()`, an open `CLIMBER`
  tag nothing authors yet) at 4 MP, capped at 1 level; dropping down with no ramp is always legal up
  to 2 levels at a flat 1 MP, no capability gate — the deliberate asymmetry makes one-way routes for
  free. Threaded through every construction site tied to a specific mover; `MapGen`'s own internal
  connectivity check stays at the default (cannot climb) on purpose. tb36's own "Pathfinder ignores
  level" acceptance test is deliberately now false, replaced.
- **Pass D** — new `Unit.height: float`, the real continuous world height (`UnitGeometry.
  true_height_for_cell`: `level * LEVEL_HEIGHT`, plus a fixed `+0.5` on a `RAMP` tile — a ramp's own
  `Grid.level` is authored at its LOWER endpoint, so resting on it is genuinely partway up) —
  `Unit.level` stays the discrete int gating decisions only. New `ClimbAction` (capability-gated,
  4 MP/level or 2 MP/half — the half case is a climb launched from a ramp tile) and `HopDownAction`
  (no capability gate, flat 1 MP, legal to 2 levels) as real queued actions. `MapGen` authors real
  elevation for the first time: a seeded fraction of rooms raised one level, each connected to the
  surrounding network by exactly one `RAMP` tile, backstopped by a general `_repair_stranded_
  elevation` flood-and-flatten pass (a raised room's single ramp can still get sealed by ordinary
  scattered cover landing on its approach tile, or by a wide corridor serving two OTHER rooms
  crossing through it — rather than chase every such topology by hand, anything a non-climbing
  `Pathfinder` can't reach from a real anchor gets flattened back to level 0). No deliberate
  climb-only pockets authored this pass. Height-derived combat bonuses deliberately NOT added — the
  "a shot from higher ground resolves against more of the target" claim is read back and asserted
  (`test_a_shot_from_higher_ground_resolves_against_more_of_the_target`), confirming it's already
  emergent from Pass A's own geometry, matching the taskblock's own explicit instruction not to
  author a bonus on top of it. **Out of this slice, staying that way:** fall damage/knockdown on
  deep drops, parts/perks raising the climb cap, ladders as authored content, arc'd shots and
  thrown-weapon height advantage, no AI path yet queues `ClimbAction`/`HopDownAction` and neither
  integrates with `MoveAction`'s own mid-move overwatch hook, view-layer elevation correctness
  (Pass E, fenced for the supervisor, not started).

**Floor and terrain become parts (tb38, docs/PLAN.md)** — the tb31 wall move, generalised: everything
walkable is a placed `Part` now, not a terrain code. Same "one seeded flat bout (all level 0, no
ramps), diffed byte-for-byte after every pass" guard as tb36/37; ramp-carrying content is
deliberately excluded from that guard and covered by its own dedicated fixture instead.
- **Pass A** — the placement model, consumed by nothing. New `Surface` (part + real world height +
  facing) and `Grid.surfaces` (`Vector2i -> Array[Surface]`, the same container shape
  `field_items` already established) sit alongside `terrain`/`level`, which stay authoritative. New
  `GridPlacement` is the attachment grammar: a part attaches downward (`GROUND` in its own
  `attaches_to`) only to a cell with no surface yet, or sideways to a free, type-matching `Socket` on
  an orthogonal neighbour's own surface — reusing `PartGraph.is_legal_attachment`/`attach` verbatim,
  never a parallel legality check.
- **Pass B** — `MapGen` authors two flyweight floor parts (`ship_floor`, `ramp`) onto every non-VOID
  cell, derived from the just-finished grid rather than rewriting the carve/ramp/repair machinery's
  own internals (the BSP carve legitimately re-visits the same cell more than once, which the
  attachment grammar correctly refuses a second time — `_author_surfaces` runs once, last, mirroring
  the finished terrain/level instead). A `VOID` cell gets no surface at all — "unfloored," not a
  terrain code.
- **Pass C** — height and pathfinding now read a cell's own placed surface, not `Grid.level`/terrain
  directly (`UnitGeometry.true_height_for_cell`, `Pathfinder`'s walkability/move-cost gate). Ramps
  become a real two-tile, 22.5° profile (`+0.5` level per tile, replacing tb37's one-tile 45° rise) —
  `MapGen._connect_with_a_ramp` places an inner (room-bordering) and outer tile with a shared facing;
  new `RampGeometry` pins the settled low/high/lateral edge heights (0 / +0.5 / +0.25), built and
  tested even though nothing renders it yet. Partial climb MP rounds up (a 1.2 MP climb charges 2).
  **Real bug found and fixed:** `_repair_stranded_elevation` never flattened a stranded `RAMP` tile,
  only a stranded `OPEN` cell — invisible under tb37's model (a ramp's own authored level was always
  0), exposed once the corrected model gives the room-bordering tile a genuinely non-zero level; now
  reverts a stranded ramp fully to plain ground. `test_full_mission.gd`'s seed re-picked
  (12373→12383) — the two-tile ramp reshapes which rooms get ramped, the same established pattern as
  every prior generator-reshaping re-pick.
- **Pass D** — scope revised by the supervisor mid-taskblock: not the `Grid.level`/`TerrainType`
  retirement itself (confirmed blast radius: 14–17 production files, 36–37 test files still read the
  pre-placement model directly), but making that retirement safe to run as its own follow-up block.
  New `GridLegacyBridge` consolidates three previously-scattered `surfaces.is_empty()` fallback checks
  into one instrumented seam; a full-suite run tallies **4,318,367** hits across three call sites
  (`Pathfinder._base_cost`/`move_cost`, `UnitGeometry.true_height_for_cell`) via a GUT post-run hook
  (`tools/legacy_grid_bridge_burndown.gd`) — the retirement block's own real acceptance test is this
  counter reading zero, not a grep. **Out of this taskblock, staying that way:** the actual
  `Grid.level`/`TerrainType.{OPEN,WALL,RAMP,VOID}` deletion and the void→lore-only vocabulary sweep
  (both the named follow-up block, `PLAN.md`); catwalks/bridges as authored content; floors
  projecting into the shot plane (BR34.05 stays open — would break this block's own byte-identical
  guard).

**Legacy grid model retired (tb39, docs/PLAN.md)** — the follow-up block tb38 Pass D split out:
deletes `Grid.level`, `Enums.TerrainType`, and `GridLegacyBridge` outright, migrating every
remaining direct reader and fixture onto the real placement model. Full suite ends at 2120/2120,
`GridLegacyBridge`'s own burn-down counter at zero (down from tb38's 4,318,367 hits), and a
grep finds no surviving `Grid.level`/retired `TerrainType` value/`GridLegacyBridge` reference
anywhere, tests included.
- **Pass A** — replaces the old pinned-seed "does THIS scripted mission reach extraction" harness
  (`docs/SUPERSEDED.md` — six re-picks, every one a legitimate mechanics change absorbed as noise
  instead of a signal) with a completion-RATE sampling test (`test_full_mission.gd`) built on the
  same `BoutSetup`/`DeepStrike`/`BoutRunner` path a real "Simulate Bout" menu uses, never a
  hand-rolled turn loop. Measured baseline: 12 seeds at a 100-turn cap, 1-vs-1 AGGRESSIVE
  `a_brand_laborer` bouts, ~80% EXTRACTED; `MIN_COMPLETION_RATE` set to 0.5, well below the
  observed rate but low enough to catch a real collapse — flagged as a tunable, not a design
  number.
- **Pass B** — `MapGen` carves into a private `MapGenScratch` (its own local `terrain`/`level`
  arrays, never `Grid`'s public surfaces API) and emits real `Surface`s once, at the very end
  (`_emit`), rather than authoring onto a real `Grid` mid-carve the way tb38 Pass B did — carving
  legitimately re-visits the same cell many times (splitting rooms, re-cutting corridors, the
  emergency fallback corridor), which `Grid.surfaces`'s attachment grammar correctly refuses a
  second `GROUND` placement onto; scratch has no grammar to fight at all. `MapGenScratch.
  place_surface` is the one shared formula both `as_temporary_grid()`'s mid-generation
  reachability grids and `_emit`'s real final authoring use, so the two can never drift apart.
- **Pass C** — the three legacy-bridge readers (`Pathfinder._base_cost`/`move_cost`,
  `UnitGeometry.true_height_for_cell`) read real placed surfaces unconditionally now, no fallback;
  `GridLegacyBridge`'s counter confirmed at zero across the full suite before deletion. New
  `test/support/grid_fixture.gd` (`GridFixture.flat`/`place_floor`/`place_ramp`/`place_wall`)
  builds real placed `Surface`s for a fixture instead of hand-set terrain arrays — the single
  mechanism used to migrate roughly 55 test files off the legacy model, each proven to still fail
  for its own reason (anti-vacuity) after migration. `Pathfinder._terrain_costs`/`_min_possible_
  cost` and `CombatState.terrain_costs` retired outright as dead weight (only ever read inside the
  now-deleted legacy-bridge branch); `Pathfinder.new(grid, can_climb)` drops the parameter. New
  `Surface.is_ramp_at(grid, cell)` de-duplicates a ramp check `Pathfinder`/`ClimbAction`/
  `HopDownAction` each held their own private copy of. **Two real bugs found via migration, not
  cosmetic swaps:** `test_climb_action.gd`'s ramp-climb test was pinned against
  `GridLegacyBridge`'s superseded flat `+0.5` ramp offset (tb37) — migrating onto a real placed
  ramp `Surface` changed the asserted cost from 2 MP to 3 MP, matching `RampGeometry.
  STANDING_OFFSET` (tb38 Pass C's already-corrected value); the test itself was stale, not the
  game. `test_squad_control_overlay.gd`'s real-raycast click test broke once a wall got real 3D
  geometry — `PartPicker.hit()` can report a closer blocker hit than a unit hit, so a wall on the
  shooter/enemy's shared view-axis column could occlude a click; fixed by reorienting the fixture
  perpendicular to the camera's default view axis, not by weakening the click test.
- **Pass D** — full rename, not a partial one (explicit call): `Enums.TerrainType`
  (`OPEN`/`WALL`/`SPAWN_A`/`SPAWN_B`/`VOID`/`RAMP`) → `Enums.SpawnMarker`
  (`NONE`/`SPAWN_A`/`SPAWN_B`, an explicit `NONE = 0` sentinel since a fresh `Grid.spawn_marker`
  array already defaults every cell to `0`); `Grid.terrain`/`get_terrain`/`set_terrain` →
  `Grid.spawn_marker`/`get_spawn_marker`/`set_spawn_marker`; `Grid.level`/`get_level`/`set_level`
  deleted outright, no replacement field. `MapGenScratch` gets its own local `CellKind` enum
  (`UNCARVED`/`OPEN`/`RAMP`/`EMPTY`) — never reuses `Enums.SpawnMarker`. `TileInspection` gets its
  own local `PhysicalState` enum (`EMPTY`/`OPEN`/`RAMP`) for its tooltip classification, since
  `Grid`'s enum no longer represents any physical fact at all. `GridLegacyBridge` and
  `tools/legacy_grid_bridge_burndown.gd` deleted outright. Vocabulary sweep: "void" retired for
  the physical-absence state everywhere in code/comments (lore-only from here on, e.g. the ship
  setting); "empty"/"unfloored" instead — `MapGenScratch.CellKind.EMPTY`, `AsciiRender.
  CHAR_EMPTY`, `BoardView.EMPTY_BORDER_COLOR`/`EMPTY_FILL_COLOR`/`_build_empty_indicators`,
  `TileInspection.PhysicalState.EMPTY`. **Checked and found correct:** `MapGenScratch` never
  reaches for `Grid`'s public spawn-marker/blocker API outside `as_temporary_grid()`'s documented
  blocker pass-through; `map_gen.gd` touches `Grid.spawn_marker` only inside
  `_place_spawn_zones`/`_mark_zone`, confirmed by the file's own source-scanning acceptance test
  (`test_map_gen_touches_grids_spawn_marker_api_only_in_spawn_marking`). One test-suite-only bug
  found during the final full-run verification: `test_determinism_check.gd`'s own custom compare
  lambda still read `a.terrain`/`b.terrain` post-rename, a stale reference with no production
  impact (caught by the very first full-suite run after the rename, not shipped).

**"Void" retired from code entirely (tb40 Pass A, docs/PLAN.md)** — tb39 Pass D's vocabulary sweep
left the word alive in ~44 identifiers/comments and left open whether the rule was prose-level or
grep-strict; settled grep-strict, since "voidhulk" is the game's own lore term and a future grep for
it needs to return lore only. Four distinct categories, not one find-and-replace: `WorldPalette.VOID`
(the 3D environment's background color, not tile coloring) → `WorldPalette.BACKDROP`, naming the role
rather than the value; `MapGen._finalize_walls_and_void` → `_finalize_walls_and_empty` (and every
citing comment); the miss-tracer cluster in `ShotResolution`/`ResolutionPlayer` (`void_range`, "void
ray"/"void tracer"/"void endpoint") → `miss_range`/"miss ray"/"miss tracer"/"miss endpoint" — a
distinct concept from physical absence (how far a missed shot's tracer draws), renamed without
touching miss-tracer behavior, ranges, or the deflect path; ordinary-English "void" in comments
("floating in a void", historical quotes of retired spec language) rewritten in current terms, tbNN
provenance tags kept. New repo-wide guard test (`test_void_vocabulary_guard.gd`, modeled on tb39's
own `test_map_gen_touches_grids_spawn_marker_api_only_in_spawn_marking` file-scan pattern) walks
`src/`/`test/`/`tools/` and fails on any `\bvoid\b` outside a literal `-> void` return annotation —
the acceptance grep as a real test, not a one-off shell command. Full suite: 2121/2121.

**Camera framing across height deltas measured, found sound (tb40 Pass B, docs/PLAN.md)** — "measure
before changing anything," not a blind fix. A height-delta matrix (target displaced ±1/±3/±6 levels
from the shooter, real solver internals — `CameraOrbitState._solve_back`/`_both_fit`, not a
reconstruction from the returned {yaw, pitch, zoom} via trig round-trip, which loses enough precision
right at the fit boundary the solver deliberately lands on to read as a false failure that was never
real) printed as a table and checked against every hard invariant the pass named: both bodies fit at
every delta including ±6, the camera never sits below the lower of the two bodies (it's pinned at
`shooter.y + ATTACK_UP_OFFSET` regardless of target height, so it's structurally always at or above
the shooter), and the solved framing is continuous across the delta-crosses-zero seam (no explicit
height branch in `attack_framing`'s own algebra to discontinue at). The one real number: vertical look
angle grows from ~7° at the same level to ~25–34° at a 6-level delta on a 3-cell horizontal separation
— real, but bounded by the fit search itself, not runaway. **No code change** — per the pass's own
explicit instruction not to assume a defect exists because a pass is named for it; the tilt-angle
number is handed to Pass D as something for the supervisor's own eyes to judge, not fixed on
spec. `sniper_framing` centers the target at any height by construction (`pan_offset = target.center`,
no shooter dependency at all) — checked across the same matrix rather than assumed from the structural
argument alone. New pinned regression guard locks today's same-level solve exactly, so a future height-
anchoring change (if the supervisor ever wants Pass B4's midpoint-anchor idea) is provably a no-op on
a flat map. Full suite: 2125/2125.

**Wall cutout under elevation diagnosed, not fixed (tb40 Pass C, BR32.05)** — reasoned from
`wall_cutout.gdshader`/`WallLegibility.pixel_radius_for_tiles` source against two named cases, no
shader run (headless rendering never executes a fragment shader). Same root cause BR32.05 already
names (no real ray/line-of-sight test), but elevation opens a genuinely new way for the coarse
heuristic to misfire: the Euclidean-depth gate has always doubled as a correct "is this wall really
between camera and unit" proxy specifically because a flat map makes "behind the unit" and "farther
from camera" the same condition — elevation breaks that equivalence (an elevated wall can be
Euclidean-nearer to the camera than a low unit even while sitting horizontally behind it on the
ground plane). No new `docs/BUGS.md` entry opened — same fix BR32.05 already wants (a real ray test or
an angle-based gate) covers this case too; finding appended to BR32.05 instead.

**Checkpoint 8: a loadable multi-level scenario (tb40 Pass D, closes taskblock-37 Pass E)** — "hand
the supervisor a loadable scenario, not a description." Three hand-built scenarios (target above the
shooter, target below, a same-level control), one shared grid shape (`GridFixture` — the same call
`MapGen._emit` makes — a ground floor, a real 3x3 elevated platform, one real destructible wall
between them), loaded through the real `BattleScene.load_battle()` entry point and framed through the
real `CameraRig.ease_to_framing()` "entering aim" call (tb34 Pass D) — never a mock, never a
re-derived formula. `./checkpoint.sh 8` regenerates it; `tools/checkpoints/checkpoint_8.gd` is the
driver, following checkpoint 6's stills-only pattern (`run_visual_checkpoint.sh` case 8). A yes/no
checklist ships in the generated README, folding in Pass B's own measured numbers and Pass C's
finding as something to confirm, not hunt.

Fixed a real bug found wiring this up: `DeepStrike.assemble_reference_humanoid`/`assemble_from_preset`
never set `unit.height` themselves (every assembly path leaves that to the placer — same convention
`BoutInjector.set_cell_level` already follows) — `checkpoint_8.gd` reads it back from the real placed
`Surface` via `UnitGeometry.true_height_for_cell`, never assumed from the level passed to the grid
builder. Also caught and fixed a `BoutRunner` "squad controller(s) never assigned" error on load —
`CombatState.assign_all_to_human()` (tb31 Pass B's own "Control All Squads" shortcut) for a static
viewing scenario nothing should auto-advance.

**A real render surfaced BR40.01, a genuinely new camera-solver limitation no headless matrix could
have caught** — Pass B's own height-delta matrix only checks two bounding SPHERES against the FOV
cone, with no scene geometry in the harness at all to occlude against. Rendering the "target below"
scenario for real showed almost nothing: the solved camera position sits *past the far edge of the
platform the shooter is standing on*, because `_solve_back` pushes the camera backward far enough to
fit both bodies' angular footprint with no awareness that "backward" can walk it off a small stand's
own edge — the platform's own solid mass ends up between the camera and everything else. Filed as
`BR40.01` (`Active`, owner `CC`, since CC found and root-caused it, source not yet promoted), not
fixed — out of both Pass D's own scope (build a scenario, not fix the rig) and Pass B's own fence (a
missing occlusion check, not an anchor-height problem B4 would have touched). The checkpoint's own
"target below" screenshot doubles as this bug's live repro rather than being reshot to hide it.

Incidental: restored `out/checkpoints/06/` (`board_wide.png`/`cyborg_closeup.png`/
`twelve_arm_rig.png`/`README.md`) after an exploratory `rm -rf` clobbered them mid-session while
confirming this sandbox's GPU/X11 setup could run a visual checkpoint at all (`git checkout --`
recovered them byte-identical; flagged here since CLAUDE.md's own safety protocol is "run `git
status` before any command that could discard uncommitted work" and this one skipped that step).
Also found, in the process: both existing visual checkpoint scripts (`checkpoint_6.gd`/
`checkpoint_7.gd`) crash outright (`Identifier "UnitView" not declared`) — `UnitView` was renamed to
`HitVolumeView` in an earlier taskblock and neither script was updated, since visual checkpoints
aren't part of `run_tests.sh` and nobody had re-run them since. **Not fixed** — out of this pass's own
scope; `checkpoint_8.gd` uses the current `HitVolumeView`/`load_battle()` path throughout, so it
isn't affected, but 6 and 7 need their own follow-up pass before they'll run again.

**Failure model & joints** (tb09, joint depth tb26 D) — five failure modes: `MANGLE` (¼ residual
DT, stays attached), `DISABLE` (inert, attached), `DETONATE` (replaces cook-off), `FRAGMENT`,
`MELTDOWN`. Child-owned joint HP, no modes; depleting one drops the intact subtree. Joints aimable
(the precise-elbow shot). Spill-through: penetration damages the plate fully, spills
`damage − effective_dt` onward. **Joint HP default raised 1→3** (tb26 D) — a weaken-then-sever
gradient instead of any hit reaching a joint severing it outright; per-part overrides still win.
**Joint cladding** (`Socket.joint_cladding`, tb26 D) — an optional Part authored directly on the
socket owning the joint it protects; `BodyProjector` projects it as an ordinary Region in front of
the joint's own region, so it absorbs/deflects through the existing part/DT/spill machinery (tb20's
layered-body cladding model, reused verbatim) rather than a new damage mechanism.

**Armor, damage & weapons** (tb09/10/13/23) — DT from a `dt_curve` table; penetrate/stop-dead/
deflect by real geometry, incidence/reflection read a region's real 3D surface normal (tb23 C, not
a flattened one); ricochet retention `lerp(0.90,0.25,bend)`; crits bypass-or-bonus; bonus-pen as a
DT-discount (penetration only, negative for buckshot). Ammo owns the payload (`AmmoDef`); gun is a
modifier (`WeaponDef`). Cartridge chambering (family + length). Two scatters: dartboard (aim) vs
spread pattern (mechanical). Burst = N independent pulls, recoil accumulates. Recoil computed.
**Audited (tb19 H): burst-fire-sometimes-produces-no-shots** — the suspected cause (`is_legal`/
`apply` reading different `burst_size` sources) never existed; a 200-seed sweep against the real
`chaingun.tres` confirmed every pull always fires — the reported symptom is the chaingun's own wide,
outer-weighted scatter genuinely missing often, even on pull 0 before any recoil (a data/balance
fact, confirmed with the project owner, not silently retuned). New `&"burst_pull"` combat-log events
(hit/miss + running `landed_so_far` tally) make "did all N pulls execute" directly observable.

**Layered bodies & power** (tb20/22) — bodies as cladding/skeleton/organs; knowledge-gated occlusion
of internals (source stubbed to "known"); penetration traversal (DT attenuation, overpen = 0°
deflect, `hollow` flag, lodged-inside wounds); **wounds** as non-terminal repairable per-part state;
penetration-driven deflection resistance (closed the angle-lock stalemate); power drives AP through
an authored diminishing curve (tb20 F, revised tb22 B) with coring; the reaction window
(perk-gated, default none). A unit that can neither move nor act may voluntarily **shut down** —
inert, still occupying its cell/occluding the shot plane, excluded from turn order (tb22 C).

**Range** (tb19) — effective / max / min with a linear sub-1 accuracy band in the effective→max
range; discrete min-range failure (explosive duds); AI movement is range-aware. Internal-targeting
shots (tb20 B) were audited against this pipeline (tb20 G, confirm-only — no separate code path) and
confirmed to run through it unchanged: an internal aim just shifts `AttackAction`'s dartboard center,
so it inherits the same effective→max accuracy band and never bypasses range banding.

**Repair** (tb22 E) — `RepairResolver`/`RepairAction`, five authored battery parts + the Arc Welder,
repair-with-scrap (1:1, up to 3 HP per use, 4 AP; scrap's own resource id is the damaged part's
`material` field). Reachable via a right-click "Repair with Scrap" item and an action-bar Repair
button. **Partial**: logically complete and tested, but not yet reachable in natural gameplay — no
existing part's `salvage_yield` produces the `material`-field scrap namespace repair reads, since
that's a new id space kept deliberately separate from the existing `salvage_yield` categories
(`metals`/`organics`/`reactives`). A follow-up authoring pass is needed before a scavenged scrap pile
actually feeds a welder.

## Melee (tb25, keystone 1)

**Delivery** (tb25 A) — reach = `weapon_def.weapon_length` (free, no exposure) +
`Shell.shell_reach` (leanable exposure budget). A strike needing shell lean poses the torso
forward (`Poses.lean`, the same `ROOT_SOCKET_ID` seam `Poses.down()`/`prone()` already use) — no
melee-specific exposure system, the existing overwatch torso check fires against the leaned
geometry unchanged. Beyond `shell_reach + weapon_length`, a reach-gated step-in
(`MeleeDelivery.find_step_in_cell`) reuses `StepOutPlanner`'s own move-assembly structure.

**Resolution reuse** (tb25 B) — `StabAction`, a point-payload strike sharing
`ShotResolution.resolve_and_log_point`/`DamageResolver`/`ShotPlane`/`RangeModel`/`Dartboard`
verbatim with `AttackAction` (structurally a sibling, never a parallel resolver). Legality is
reach-gated (`MeleeReach.in_reach`, a real 3D distance via `UnitGeometry.bounding_sphere` — a
sword can't hit someone 1 up, a polearm hits at √2) instead of range/LoS-gated. The ranged
accuracy pipeline is reused unchanged — melee's own tight dartboard is point-blank range through
the existing curve, not a special rule.

**Three payloads, one deflect seam** (tb25 C) — `DamageResolver.resolve_shot` gained an additive
`deflect_mode` (default `&"ricochet"`, every prior caller unchanged): `&"slide"` (stab) retries
once against a laterally-nudged point on the same plane instead of ricocheting; `&"none"`
(slash/hold, per point) stops outright, no bounce. `SlashAction` — a line payload
(`MeleeLine.sample`, horizontal/vertical/45°, `slash_length` long) hitting everything along it; a
vertical line spreads along `Region.rect`'s own real-height axis (tb23) for free. `GrindAction`
(armed as action id `&"hold"`; the class name avoids colliding with tb19's own "defer to next
ally" `HoldAction`) — `weapon.burst` doubles as hit count, each hit's `bonus_pen` stacks raw and
uncapped (`base * i`), `DamageResolver`'s own existing PENETRATE spill cascade already gives
"continues through cladding" for free.

**Spherecast** (tb25 D) — `ShotPlane.disc_overlaps_rect` (radius ≤ 0.0 is exactly
`rect.has_point`, every point-only caller unchanged): a stab's own `weapon_def.stab_width` disc
can't thread a gap narrower than it, the same sniper gap-fall-through inverted. A stepping stone
to a real shapecast — the shape math lives in exactly one place.

**Suppression un-stubbed** (tb25 E) — `Suppression.resolve_opportunity_attacks` fires the
attacker's own real melee weapon (`ActionCatalog.provider_for(attacker, &"stab")`) through the
identical `ShotResolution` pipeline `StabAction` itself uses, replacing the flat unarmored stub
hit; gated on `state.is_preview` now that the outcome is RNG-driven, matching `AttackAction`.

**AI** (tb25 F) — PSYCHOTIC (prefers melee, closes to minimize distance, never flees) and TURTLE
(flees rather than melee — `Suppression.is_suppressed`-gated, otherwise an ordinary
cover-weighting planner) fold into `UnitAI`'s existing dispatch; `_preferred_firing_action_id` now
also recognizes `&"stab"` (purely additive), so AI weapon choice reads the same
`ActionCatalog` seam every other firing pick already does. The baseline "punch" (a POWER-capable
part providing its own `&"stab"`, no weapon needed) is proven at the engine level; authoring it
onto shipped content (and a real `shell_reach` per shell template) is unauthored balance work, not
invented here.

## Combat structure & AI

**Turn structure** (tb06, docs/09) — TACTICS/RESOLUTION re-entrant loop; `resolve_until →
COMPLETED|STOPPED(reason,refund)`, interrupt when the next action is illegal; overwatch (torso gate,
visible as a 30° slice, tb19) — the AI can now genuinely weigh and hold it, not just react to it
(tb24 C); one-stream combat log, folded into hierarchical action-level summaries at render time
(tb22 F). **Combat-log shot geometry in text, not just data** (tb28 C) — `ShotResolution`'s own
impact/miss logging (made public: `log_impact_result`/`log_miss_result`, were `_log_impact`/
`_log_miss`) folds the real origin/hit geometry `data` already carried (tb22/23) into `text` too, so
`out/combat.log` shows it directly — `LogEvent._to_string()` only ever rendered `text`, so the
geometry was invisible outside a live playback or a `data` inspection until this. `Overwatch._fire`'s
own separate, hand-rolled `&"impact"` event (no geometry, no crit/wound/destroy/salvage cascade at
all) now routes through the same shared path every other firing action uses — no parallel logging
system, and overwatch misses are logged for the first time. **Per-tile move facing** (tb16 A) —
`MoveAction.apply_stepwise` faces before each step, not once at the end (`FaceAction.face_for_free`
per tile, free); a curved or interrupted path faces correctly mid-move, and an interrupted move is
left facing its actual direction of travel at the interrupt point, not its start facing. **Round**
(tb17-1 A, audited and already correct — no code change needed) — `CombatState.round_number`,
incremented exactly when turn order wraps back to the front, not once per unit's turn; the boundary
future per-round effects and the Hold action (tb19 F) key off. **Hold action** (tb19 F) —
`HoldAction` defers a unit's turn to after the next ally acts, still within the same round; carries
all held AP/MP forward, regenerates none; available to AI and player — the AI holds instead of
taking a clearly bad action (e.g., facing uselessly when its own ally blocks the firing line).

**Resolution speed** (tb18) — `Matrix.personal_speed` (flat bonus to everything); unified
resolution-speed formula (lower resolves first); re-validating ordered resolver; initiative;
equal-speed simultaneity (`CombatState.simultaneous_group()` — a logic-level grouping query only;
turn order/`advance_turn()` still hand back one unit at a time, and skipping the inter-turn pause
during playback for a simultaneous group is a flagged `BoutRunner`/`ResolutionPlayer` follow-up, not
yet built); **Step Out** (auto-assembled orthogonal move/fire/return through the
resolver, dies-exposed on interrupt). Both legs are free — `MoveAction.free` costs no MP/AP either
direction, for the AI's own `StepOutPlanner` usage and the player alike (tb27 B2, docs/SUPERSEDED.md
— previously a deliberate "real cost, no discount" choice). The player's own Step Out flow now
matches the intended sequence: confirming a cell queues only the free out-leg and opens ordinary
aim mode from the stepped-out position (camera/dartboard follow the queued move for free via the
existing preview machinery); firing appends the free return leg; canceling aim mid-step-out undoes
the queued out-leg (tb27 B). **Queue panel** (`QueuePanel`, rebuilt BR27.08 — `docs/SUPERSEDED.md`)
— the in-turn readout of a unit's own queued actions; each entry is a real row (What/AP/MP labels)
carrying its own "Resolve" button, wired directly to `TacticsController.resolve_to_marker(index)` —
resolves the queue's prefix through exactly that entry on press, no separate select-a-row-then-press-
a-global-button step and no persisted marker state. Rebuilt this way after the prior `Tree`-based
mechanism (click a row to set a marker, a separate global button to fire) could never be made to
reproduce a real, supervisor-confirmed "nothing happens at all" failure in this environment — replaced
with the same primitives every other reliable click surface in this codebase already uses.
**Resolving to an earlier point keeps what's queued after it** (supervisor follow-up,
`docs/SUPERSEDED.md`) — `SelectionController.keep_queue_suffix()` replaces the old `reset_turn()` call
`resolve_to_marker()` used to make after a partial resolve, which discarded the entire remaining queue
along with the prefix that actually resolved. The same queued `CombatAction` objects replay unmodified
against the just-updated real state — safe because every action already re-validates itself against
whatever `state` it's actually handed (docs/09), not a captured reference. **A `MoveAction`'s own row
text drops its unbounded path** — `CombatAction.short_describe()` (new, defaults to `describe()`
unchanged for every other action) is what a queue row actually shows; `MoveAction` overrides it to keep
everything `describe()` already says except the `path=...` term (`"MoveAction(unit=%d)"`, matching every
sibling action's own `ClassName(unit=%d, ...)` style), since that term alone — not the row's format in
general — was what stretched the readout across the whole display. The full path still reaches the
hover tooltip, as an extra "Detail" row (`TooltipBuilder.for_queue_entry()`).

**AI** (tb14/16/17-1/24) — `UnitAI.plan_turn`, deterministic, human & AI emit the same queue,
firing derived from the same `ActionCatalog.build_firing_action` seam a weapon's own
`provides_actions` governs for both (tb24 A/B — `is_legal` enforces it as an engine rule, not a UI
convention); the AI can weigh other provided, non-firing actions the same way, overwatch the first
consumer (tb24 C). Playstyles: AGGRESSIVE (never holds overwatch), COVER_SEEKER (only from cover),
SKIRMISHER (~5), MARKSMAN (~7+, prefers it), PSYCHOTIC (prefers melee, closes to minimize
distance, never flees), TURTLE (flees rather than melee — tb25 F). Line-of-fire safety (won't
shoot through allies); reachability-aware targeting. **Suppression** (tb19 E, un-stubbed tb25 E) — a
`two_handed` weapon is illegal to fire while its wielder is adjacent to a living enemy
(`Suppression.blocks_weapon`), and leaving an adjacent tile draws a free melee attack
(`resolve_opportunity_attacks`, a flagged stub hit until tb25 E gave it a real weapon); this alone
keeps the AI from crowding into face-to-face range with no melee system built. **Engagement
positioning** (tb27 C1) — when no reachable cell has real line
of sight this turn, `_engagement_score` now scores primarily on `LoS.obstruction_count` (opaque
cells between a candidate cell and the enemy), which strictly decreases as a unit works around a
corner even while raw distance plateaus — a real, measured improvement (a 60-real-map sweep's
never-reaches-LOS seed count dropped 16/60 → 8/60), not a complete fix: a corridor requiring
temporary backward movement before a gap appears can still trap this per-turn greedy scorer.
**Line of fire, not line of sight** (tb33, `docs/SUPERSEDED.md`) — fixed the corridor case above and
closed BR30.10's own 81%-into-walls finding in one stroke: `LineOfFire.has_clear_line_of_fire`
(new, `src/logic/line_of_fire.gd`) resolves the exact same `ShotPlane` a real shot fires through
(sharing one first-hit resolution with the refactored `_ally_in_firing_line`), rather than trusting
`LoS.has_los` — opacity-only by design, and blind to the cover-Part walls became (tb31 C). Threaded
through `_plan_ranged`'s fire gate (`clear_from_here`/`final_blocked`) and `_engagement_score`'s own
line check (`any_reachable_has_los` → `_has_lof`, `NO_LOS_PENALTY` → `NO_LOF_PENALTY`); a
weapon-range prefilter (`_any_reachable_has_lof`) keeps the added `ShotPlane.build`-per-cell cost off
cells that can't fire anyway (BR26.02). **Closes BR32.10** (AI stuck on U-shaped/concave maps): when
nothing reachable this turn has a shot, `LineOfFire.approach_path` Dijkstra-floods (new
`Pathfinder.nearest_matching`) to the nearest cell that would, truncated to this turn's own MP budget
(new `Pathfinder.truncate_to_budget`) — the fallback re-fires turn over turn until a reachable cell
genuinely has one, unsticking the exact "moves away before it gets closer" detour a per-turn greedy
scorer structurally can't make. `LoS`/`LoS.obstruction_count` are unchanged and still opacity-based —
only the AI's own fire/standoff *gate* moved from sight to fire; genuinely sight-based questions
(`is_covered_from`) still read `LoS`.

**Depth floor on shot resolution** (tb35 Pass B, BR34.06/BR27.02) — `ShotPlane.build`'s own
depth-sort has no floor at zero, by design (a region behind the ray's own origin is legitimately
present, the aim window reads it) — but `LineOfFire._first_hit_excluding`, `ShotPlane.
resolve_projectile`, and `DamageResolver._find_next` are three independent "walk the depth-sorted
plane, return the first match" implementations that all inherited that same unfloored sort with no
floor of their own, so a wall many tiles behind the shooter (still in the plane on purpose) could
sort first and win almost every resolution. This was BR27.02's own logged 12/12-chaingun-pulls-
DEFLECT-on-a-wall-behind-the-shooter case, and — post tb31's dense walls — the same defect made
`has_clear_line_of_fire` read "no clear line" almost everywhere, which was BR34.06 (the AI passing
every turn in bouts). Fixed by flooring the RESOLVING path only, opt-in (`resolve_projectile` gained
a `floor_at_zero` parameter, default false — every raw/body-local-plane caller is unaffected;
`self_obstruction`/`region_at` opt in; `resolve_ray` and `_find_next`, always fed a real
shooter-anchored plane, floor unconditionally) — `ShotPlane.build`'s own sort and the aim window's
`window_depth` reading are untouched. **Second, distinct fix once LOF was genuinely correct:**
`LineOfFire.approach_path` (tb33 Pass B) is capped at `weapon.max_range + APPROACH_MARGIN`, so a unit
starting genuinely far from the nearest real LOF cell still found nothing and held. New
`LineOfFire.closing_path` — real A* toward a cell next to the enemy, no LOF requirement — is the
fallback for that case; deliberately not a greedy per-turn distance scorer (reproduces BR32.10's own
concave-wall freeze; real A* just routes around).

**AI decision log** (tb35 Pass A1) — `plan_turn` was unwatchable: "the AI is broken" and "the game is
slow" were supervisor adjudications, not greppable evidence. New `AiDecisionLog.emit` (`src/logic/ai/
ai_decision_log.gd`, kept out of `unit_ai.gd` itself to stay under its own file-length cap) writes one
`&"ai_decision"` event per unit-turn through the ordinary `CombatState.combat_log` — which branch
`_plan_ranged` took (`fired_in_place`/`repositioned`/`approach_fallback`/`closing_fallback`/
`no_lof_no_route`/`stepped_out`/`overwatch`), whether it fired, and if it held, why
(`no_weapon`/`ally_in_line`/`no_clear_lof`/`out_of_range`/`other`) — read back off a `MemorySink` in
tests, the same convention `test_combat_log.gd` already uses. A diagnostic side-channel only, never
read back by any planner, so `plan_turn`'s own purity/determinism contract is untouched.

**Two framerate dumps, in the combat log** (tb35 Pass A1, BR26.02) — "the reason this bug has
survived three passes is that CC cannot see a framerate" gets an actual fix: **Aim FPS**
(`TacticsController._dump_aim_fps()`, once per `_enter_aim_mode()` transition, 200ms later, past the
entry transient) and **Turn FPS** (new `FpsDumpSink`, watching `combat_state.combat_log` for
`&"turn_start"`, wired in `BattleScene.load_battle()` alongside `file_sink` so every bout gets one
regardless of overlay) both emit `&"fps_dump"` events with a `context` tag, greppable straight out of
`out/combat.log`. `Engine.get_frames_per_second()` only means something inside a real running client,
so the headless coverage here only proves the plumbing fires on schedule — the actual before/after
numbers still want a live session.

**Per-turn LOF memoisation** (tb35 Pass A3, BR27.09) — `_any_reachable_has_lof` and
`_engagement_score` each independently resolved `LineOfFire.first_hit` for the same (unit, enemy,
cell), doubling the real `ShotPlane.build` cost of every reposition-or-hold turn. New
`LineOfFire.cached_first_hit` (opt-in `Variant` cache param, `null` default — every other caller
unaffected) backs one per-turn `Dictionary` threaded through `_plan_ranged` →
`_any_reachable_has_lof`/`_pick_engagement_position`/`_engagement_score`/`_ally_in_firing_line`, so
each cell resolves once. Measured on a real 60-turn bout: average reposition/hold-turn cost dropped
2023ms → 974ms. Not a full fix for BR27.09 — the remaining per-cell `ShotPlane.build` cost is real and
this memoisation can't remove it further without a bigger algorithmic change.

**The `body is Unit` / `Grid.blockers` assumption audit** (tb35 Pass C) — tb31 C turned walls into
full-height, dense `Grid.blockers` Parts; this pass checked every place written for the old
sparse/small-cover shape. **Audited and found correct as-is** (the `is Unit` distinction in each case
does exactly what it should regardless of wall density): `attack_action.gd`/`burst_action.gd`/
`stab_action.gd`'s own muzzle self-obstruction redirect (a static obstruction, cover or wall, should
redirect aim onto it; an ally blocking should not — that's the player's own informed risk, not this
codebase's call); `shot_resolution.gd`'s `target_unit_id` falling to -1 for a non-Unit body (every
consumer already treats -1 as "no unit hit," unaffected by what kind of non-unit thing it was);
`UnitAI._ally_in_firing_line`'s own `region.body is Unit` check (asks specifically "is an ally
blocking," correctly false for a wall — wall-blocking is `has_clear_line_of_fire`'s own separate,
already-correct concern); `Pathfinder.move_cost` (an O(1) dict lookup, density-proof by construction);
`tile_inspection.gd` (a single-key lookup, same reason); `los.gd`/`inspect_panel.gd`/
`world_palette.gd` (no `grid.blockers` reads at all).

**Fixed:** a destroyed wall (or any blocker) never cleared `grid.opacity` — `Pathfinder` already
treated a destroyed blocker as passable (its own `hp > 0` check), but `LoS.has_los` kept reading the
same cell as permanently opaque forever, since nothing at combat time ever touched the `opacity` array
map-gen set once. New `Grid.cell_of_blocker(part)` (a reverse lookup, only ever run on the rare
destruction event, never per-frame) backs a new clear in `DamageResolver.
_resolve_destruction_consequences` — a no-op for ordinary destructible cover, whose own cell was never
opacity-flagged to begin with. **Fixed:** `BoardView._build_wall_indicators`'s own flat gray-tile-plus-
cross marker checked `TerrainType.WALL`, a condition confirmed (via a real generated bout) to never
match any cell on a live map anymore — `MapGen._finalize_walls_and_void` gives every real, exposed
wall cell `OPEN` terrain plus a genuine blocker Part instead. Not a live-game bug (the wall's own mesh
already makes "can't walk here" obvious), but the loop's own doc comment was stale and the condition
could still double-draw on a hand-authored/debug grid that sets `TerrainType.WALL` directly — guarded
against that narrow case and corrected the comment.

**Re-derived, not fixed: BR32.07** ("burst cannot aim at a wall"). Traced the full aim-entry chain
(`TacticsController.click_cell` → `PartPicker.hit` → `_enter_aim_mode` → `aim_state()` →
`AimController.resolve()` → `ShotScatter.for_shot()`) end to end — every step is generic over action
id, and a new regression (`test_tactics_controller.gd::
test_arming_burst_and_clicking_a_wall_enters_aim_mode`) confirms arming burst and clicking a real wall
cell correctly enters aim mode headlessly. No code-level break found; recommends a live re-check
before further digging (the same class of headless-vs-live gap BR27.08 hit).

**Found, not fixed — logged as BR35.01/02/03:** `PartPicker.hit()` scans every `grid.blockers`/
`field_items` entry on every mouse-move hover, not just cells near the ray (real perf cost, now that
blockers number in the hundreds); `SpectatorOverlay`'s tile-inspect click resolves via ground-plane
math alone, with no check for an intervening wall — a click can silently inspect a cell hidden behind
one; every debug-panel verb application triggers a full `sync_board_view()` rebuild, not just ones
that can touch `blockers`/`field_items`. All three have a clear fix shape but real risk if rushed
(geometry correctness for the first two, an exact debug-verb-id list for the third) — left open rather
than guessed at.

**BR33.01 left untouched** — no supervisor policy call has been made yet on the aim-scroll-cycles-
walls question; per the taskblock's own instruction, not guessed at.

**Fixed: the wall-cutout feed-refresh boundary (tb35 Pass D, BR32.01/03)** — `BoardView.
wall_cutout_units` was set in exactly one place in the whole codebase, `SquadControlOverlay._on_
battle_loaded()`; `SpectatorOverlay` (the default overlay every fresh bout starts in) had no handler
that ever touched it, and `BattleScene.load_battle()` itself never re-pointed it either. Starting or
reloading a bout while staying in Spectator mode left the feed pointing at whatever it held before —
null on first launch, the previous bout's own orphaned units on any later one — exactly "a stray
cutout with no unit there" (BR32.01) and "carried over from a previous bout" (BR32.03, the same
defect, not a separate one). Also explains why clicking "Assume Control" always fixed it: that's the
only path that ever installs a real `SquadControlOverlay`, the only code that ever set the feed.
Fixed by moving the assignment into `BattleScene.load_battle()` itself, once, for every overlay.
**Root-caused, not fixed: BR32.04** (cutout snaps to the destination ahead of the move animation) —
confirmed `ResolutionPlayer._play_slide` animates a unit's own `HitVolumeView.position` directly every
tween tick, while `update_wall_cutout()` recomputes from the model's own already-resolved `unit.cell`,
never reading the view's own current transform. Fix direction is clear (a per-unit "current display
position" `Dictionary` written by the tween, read before falling back to the logical cell) but
correctly scoping its own lifecycle wants a dedicated pass, not a rushed one here.

**Mission & meta** (tb07, docs/07) — no win state (EXTRACTED/TERMINATED/STRANDED); enemy count never
an ending; gather→extract/terminate; asymmetric, whole-squad, visible extraction — the player squad
must get everyone to a team-coded tile, can't self-extract early (tb22 A); bout-setup places each
side's extraction tiles on the *opposing* side, forcing the teams through each other (tb23 E1);
pseudo-persistent hulks; loot overlap; deep strike.

**Squad control gets an `UNASSIGNED` state** (tb31 B) — `SquadController` was a hard `{HUMAN, AI}`
binary, so `CombatState.controller_for()`'s fallback had to silently pick a side (BR30.09's root
cause). `UNASSIGNED` is now the zero-default; `BoutRunner._init()` hard-errors if any squad on the
board is still unassigned when a runner is built, so an ill-defined bout can't run at all.
`assign_all_to_human()` / `assign_rest_to_ai(human_squads)` are the visible authoring shortcuts that
replaced the old hidden HUMAN default; `_seed_battle` assigns explicitly.

**Every action arms from the bar the same way** (tb31 D) — `ActionDef.requires_target: bool` (two
shapes) became `Enums.TargetingMode` (`BOARD`/`NONE`/`PART_PICKER`); `ActionBar` dispatches by mode, so
overwatch (`NONE`, its first real UI call site) and repair (`PART_PICKER`) reach the bar directly
instead of bolted-on `SquadControlOverlay` buttons. `ActionCatalog.ap_cost_for` extended to
overwatch/repair — each had the same fixed-cost-vs-part-cost drift BR30.11 fixed for burst, caught on
first wiring.

**Wall occlusion cutout shader** (tb32 A, supersedes tb31 C — `docs/SUPERSEDED.md`) — replaces tb31 C's
one-wall-at-a-time GDScript alpha-blend
(`BoardView.WALL_FADE_ALPHA`/`_set_wall_alpha`) with a lit, per-fragment dithered `discard`
(`wall_cutout.gdshader`, one shared `ShaderMaterial` for every wall). `BoardView.update_wall_cutout()`
projects every unit in `wall_cutout_units` to a screen position/depth/tile-derived pixel radius
(`WallLegibility.pixel_radius_for_tiles`, new pure helper) and feeds them as uniforms each frame; the
shader decides per-fragment whether to discard. Cuts around every unit at once now, not one focal unit;
spectator never feeds any units, so the cutout simply never fires there (unchanged, flagged as trivial
to wire later). **Friendly fade in aiming view** (tb32 B, redesigned after live testing —
`docs/SUPERSEDED.md`) — a friendly
standing between the camera and the active (shooter) unit fades gray. The first version drew a
separate ghost overlay in `BoardView`, leaving the friendly's own real `HitVolumeView` fully opaque
underneath it — confirmed live to read as "something faint happening," not an actual fade. Redesigned
to fade the friendly's own real body instead: `HitVolumeView.set_occlusion_faded()` swaps every body
mesh instance's `material_override` to a translucent gray (never touching the ground marker/facing
wedge, `set_active_turn()`'s own concern, or `highlight_part()`'s `mesh.material.next_pass` chain,
which lives underneath, untouched). The occlusion decision itself moved to `BattleScene._process()`
(the one place holding both the live camera and every `HitVolumeView`), reusing Pass A's
`occludes_on_screen`/`pixel_radius_for_tiles` unchanged against `BoardView.aim_active_unit`; friendly-
only, never the active unit, only while `tactics.aiming_at != null`.

**`PartPicker`: target anything, not just enemies** (tb32 C) — a click can now resolve to a non-unit
Part (`Enums.HitKind.PART`, new): scatter cover, a wall, a downed bot's shell, a loose field item, not
just a live unit's own body (`Enums.HitKind.UNIT`, unchanged) or bare ground (`CELL`). `PartPicker.hit()`
generalizes `UnitPicker` (still the unit-ray-test path underneath) to also ray-test every
`Grid.blockers`/`field_items` Part via the same boxes `BoardView` renders
(`UnitGeometry.assembly_placements`); `TacticsController.aiming_at` is now an `AimTarget` (unit-or-part
+ cell, `ShotPlane.center_of_part`/`UnitGeometry.bounding_sphere_for_part`/`CameraRig.
ease_to_attack_framing`'s new sphere-Dictionary signature all branch on it) so the dartboard/camera
frame a Part exactly like a Unit. This reaches all the way into RESOLUTION, not just the click: `Attack
Action`/`BurstAction.is_legal()` no longer hard-require a live unit at `target_cell` — a blocker/field-
item Part (`Grid.shootable_part_at`) is enough — `apply()` re-derives whichever is actually there and
computes the aim point via `center_of_part` when there's no unit. Ranged weapons only this pass;
`Stab`/`Slash`/`GrindAction` still require a real target Unit (`MeleeReach.distance_3d` needs one) — see
PLAN.md's own follow-up note.

## Tooling, data & view

**Data layer** (tb10/11) — all definitions in `.tres`; `DataLibrary` (res:// builtin + user://
override, user wins); `DataValidator` (named errors, shared editor-save + game-load). Resource
Editor: standalone-scene tuning tool, survives reboots, writes user://, tree-table with
sort/filter/dropdowns/undo/rotating preview. (Layout/resize/column/preview bugs fixed
2026-07-18 in 713f411/1bff29b/944d019 — see BUGS.md; landed outside the taskblock cadence, logged
here retroactively.)

**Test suite** (tb12) — audited for over-granularity (1,026 funcs, 38% single-assert) by measuring
directly rather than assuming: only 3 genuine same-setup clusters existed
(`test_grid`/`test_map_gen`/`test_selection_controller`, 7→3 funcs, 0 asserts lost) — the taskblock's
own ~394→~120 merge estimate did not hold at this suite's actual granularity, and the remaining
single-assert funcs are correctly-scoped distinct scenarios, left untouched rather than force-merged
to chase the estimate. **Audited and found current:** `test_body_projector.gd`/`test_damage_resolver.gd`
(~25% of test LOC, covering systems rebuilt box→per-face→ray and exposure-table→DT→failure-modes)
read test-by-test against the live projector/damage model — no dead-shape test survived from a
replaced model; one redundant pair folded into its survivor instead of deleted.
`test_data_migration_losslessness.gd`'s hand-typed `EXPECTED_PARTS`/`EXPECTED_MATERIALS` fixtures
(previously checked only against themselves) re-verified against the real pre-migration
`DeepStrike.default_part_pool()`/`MaterialTable.default_table()` output, restored from git history —
0 mismatches across 22 parts/8 materials. Assert count unchanged throughout (2333→2333).

**View** (tb15/22, docs/10/10a) — 3D HL2-era; render is hitbox; two palettes; attack camera solves
framing (orbits target); poses = socket overrides; `HitVolumeView` permanent; per-part `mesh_scene`
(mixed assemblies). One `BattleScene` + swappable control overlays. Found and fixed a real ordering
bug in the merge (tb15 A): `BattleScene._ready()` used to call `new_battle()` (which emits the
session-start log line) before any overlay — and its log sink — existed to catch it, silently
dropping the first on-screen log line; fixed by installing the overlay first and having it react to
a new `battle_loaded` signal, which `load_battle()` now emits synchronously before session-start.
**Fix: two playback perf hitches (tb19 I)** — `ResolutionPlayer`'s per-frame tween callback re-ran a
full linear-scan unit/view lookup on EVERY FRAME of every slide/facing animation, now resolved once
per event; `refresh_unit_views()` rebuilt every unit's entire mesh subtree on every turn advance, and
`SquadControlOverlay._on_turn_ended()` called it three times per player turn (one fully redundant) —
new `LogPlayback.affected_unit_ids()` narrows the rebuild to just the units a turn's events actually
named. Playback animation
(slide/facing/shot-fade-to-tracer), animation-gated in the view only, tunable timings; every shot
and ricochet hop draws its own tracer at its real, fully 3D logged position, not one guessed
segment pinned to a constant height (tb22 D, real height tb23 D). **Ground-overlay height ladder**
(tb27 C2) — team marker / extraction tile / overwatch arc / facing wedge each hold a distinct,
deliberately-ordered depth band (`0.010 → 0.06 → 0.09 → 0.17`) instead of one marker bumped in
isolation per report; found and fixed a real, previously unreported co-planar pair (team marker vs.
extraction tile) no prior fix or test had ever checked. **Turn indicator** (tb27 D2, redesigned tb32 D
per BR27.07 — `docs/SUPERSEDED.md`) — originally recolored the active unit's facing wedge/team marker
to a distinct `ACTIVE_TURN_COLOR`; retired once the highlight was found landing on the wrong unit.
`HitVolumeView.set_active_turn()` now shows/hides the whole marker assembly instead — team marker AND
facing wedge together (the supervisor's own correction: "facing marker" meant the whole disk+wedge,
not the wedge alone) — for the active unit only, no recolor at all; presence, not color, indicates
whose turn it is. `BattleScene.refresh_unit_views()`'s `apply_highlight` parameter defers the flip
until after the resolution animation actually finishes (the ordering half of BR27.07 — the highlight
used to jump to the next unit mid-animation). **AP-gated action bar** (tb27 D3, fixed tb30 by BR27.05's
own fix below) — a slot the unit can't afford dims and refuses
to arm, reusing `ActionCatalog.provider_for`'s own `ap_cost`. **Camera reset after aiming** (tb27
D4) — `CameraRig` snapshots the pre-aim orbit state and eases back to it once aiming ends, via a
shared `_ease_to()` helper. **Wall tiles non-inspectable** (tb27 D5) — a wall click is a real
no-op, same posture as a miss; `InspectPanel`'s own null-root branch also resets stale isolate-view
state so it can never leak a live-board render slice into a "nothing to show" case regardless of
caller. **Spectator/player parity** (tb27 D1a/D1c) — the spectator log no longer word-wraps
(matching the player log); spectator view gained inspect-on-hover (`UnitPicker.hit()` driven off
mouse motion, mirroring `SquadControlOverlay`'s own highlight wiring but with no "selected unit"
gate, since spectator has no selection concept) — previously it had no hover feedback at all.
**Fix: turn controls swallowed clicks behind a stale tooltip** (BR31.01) — a tooltip left over from
hovering the 3D board right before the cursor crossed onto a `turn_controls_column` button never
cleared, since `TacticsController`'s own hover tracking lives in `_unhandled_input`, which a
`MOUSE_FILTER_STOP` `Button` never lets fire while the cursor sits over it. Each turn-control button's
own `mouse_entered` now hides the stale tooltip first — the same fix `QueuePanel`/`ApMpPipRow` already
needed for the identical reason.

**Bouts** (tb14) — watchable AI-vs-AI with pacing controls, a seed, a bout-setup menu. The
verification rig. **Bout roster as an expanding list** (tb16 E, tb17 D) — no count field, list
length *is* the count; each row is `[Bot ▾][AI ▾][D][-]` — a per-bot AI dropdown (moved from
per-team to per-bot), a `[D]` duplicate (copies preset + AI choice, inserted below its source), `[-]`
to remove; `BoutSetup.build_bout` takes an `Array[BoutRosterEntry]` (preset + AI choice) per
team. **The `[AI ▾]` menu listed playstyles until taskblock-46 Pass E below, which retired that
vocabulary — it now lists the `UtilityProfile` `.tres` files themselves, so a new profile is a file
and no code edit.** **Map generation** (tb16 C, grid-size fix tb17 A) — BSP room/hallway split with tunable knobs
(`MIN_ROOM_SIZE`, `MIN_LEAF_SIZE`/`MIN_CHILD_SIZE`, `CORRIDOR_WIDTH_MIN`/`MAX`, grid width/height);
rooms ≥ 7 on their min dimension, hallways 3–5 wide, deterministic per seed. `BattleScene`/
`BoutSetup` grid sizes (40×30 / 32×24) are derived off `MapGen.MIN_LEAF_SIZE` so the BSP reliably
splits 2–3 times per axis — tb16 raised `MIN_ROOM_SIZE` without raising these, silently collapsing
every real battle/bout to a single room with no hallways until tb17 A caught it (`BR17.01`,
`docs/BUGS-ARCHIVE.md`); new tests pin each caller's grid constants against `MapGen.MIN_LEAF_SIZE *
2` so a future threshold raise fails loudly instead of collapsing every map again. **Audited (tb19
J): headless vs. watched bouts already share one path** — found the taskblock-14/15 split already
correct: one `BoutRunner` drives every path, `ResolutionPlayer`/`refresh_unit_views()` only ever read
`combat_state`, never mutate it — no merge needed. Locked in with a direct regression test asserting
playback never mutates a unit's own real fields. **Seeded variant generation** (tb28 A) — `VariantFamily`
(DataLibrary-loaded: `variation_amount`, `omittable_sockets`, `swap_pool`, open StringName data, no
per-family code) + `VariantGenerator` produce structurally different bots from one base `BotPreset`,
deterministic per seed; `BodyAssembler` gained a `&""` Loadout-override sentinel ("leave this socket
bare") variant generation uses to omit armor/cladding without erroring. `JunkBot` ships as real
content — a small template with independently addressable per-limb ARMOR/CLADDING sockets (the
reference humanoid's own arm/leg sockets share generic ids across L/R by design, so per-limb variation
needed new content, not a retrofit). **Kits & instant equip** (tb28 B) — `BotPreset.kit` (null =
unchanged pre-existing behavior) names a container socket, what's stocked into it, and the weapon that
equips out of it into a grip socket via the existing `Inventory`/`PartGraph` ops, no parallel attach
path; chambers ammo through `WeaponResolver.try_chamber` like any other load. `KitEquipper.equip` reads
an `Enums.EquipMode` defaulting to `INSTANT` — `VISIBLE` is declared as the seam a future "watch them
arm up" mode slots into, no behavior behind it yet. `BoutSetup._spawn_squad` runs it for any kitted
roster entry right after assembly — a bout of kitted units starts fully armed at turn 1, proven against
shipped content (`kitted_chaingun.tres`). **Bout injection** (tb29, `src/debug/bout_injector.gd`) — the
debug scalpel: `BoutInjector` mutates a LIVE `CombatState` from outside the turn loop so a specific
scenario can be forced and watched. Every verb goes through one gate — reject outright while
`CombatState.is_resolving` (true only for the synchronous span of an active `resolve_until()` call, a
mid-resolution mutation is forbidden, docs/09's own two-phase-turn discipline applied to the debug
channel); otherwise mark `CombatState.was_injected` (set for good, never cleared — an injected bout is a
deliberate determinism break) and log a distinct `&"inject"` event before anything else runs. Verbs:
`spawn_unit`/`set_position`/`hand_weapon`/`equip_from_kit` (the tb28 self-arming path, forced mid-bout)/
`set_part_hp`/`inflict_wound` (reuses the inspect panel's own `WoundEffects.apply_if_status_crosses_
threshold`)/`set_ap`/`set_mp`/`set_facing`/`set_pose`/`force_current_unit`/`force_overwatch_arm`/
`force_action` (`CombatState.try_apply` — reuses the real legality check, never bypasses it);
`set_therms` is a flagged stub (therms aren't built). RNG needs (a spawned unit's matrix id) draw from
the bout's own `rng`, so the same injections in the same order on the same seed stay reproducible-given-
the-injections. **Tooling misstep, tried and reverted (tb30)** — investigating BR27.06 by reproducing
it outside the headless suite, a raw `SceneTree` driver script (`tools/investigate_br27_06.gd`,
copied from the pre-tb28/29 `checkpoint_6/7.gd` pattern of hand-rebuilding `BattleScene` internals and
driving `TacticsController` programmatically) crashed Godot outright — it referenced `UnitView`, a
class renamed to `HitVolumeView` since `checkpoint_7.gd` was written, and the resulting parse error
dropped Godot into its interactive script debugger, which then SIGSEGV'd under a real Vulkan/X11
context with no stdin attached. No lasting damage; the script was deleted, not reworked. Two things
were missed before writing it: `BoutInjector` is deliberately hard-gated out of player-controlled
bouts (tb29 Pass C) — Step Out is a `SquadControlOverlay`/player-input mechanic, so reaching for
injection here was a category error before any script got written; and the intended division of
labor is "CC scripts/forces, the supervisor watches" — for a player-input-only bug, the correct
non-headless step is the real game with the supervisor at the wheel, not a bespoke driver script
reinventing what the overlay system and `BoutInjector` already provide. **Injection reaches a
player-controlled bout too (tb30)** — `bout_injector` moved up to
`BattleScene` itself (built once per `load_battle()`, survives a spectator ↔ player overlay swap via
`toggle_blue_control()`, since `CombatState` was always the one shared source of truth regardless of
which overlay is installed). Both `SpectatorOverlay` (hover-targeted — spectator has no selection
concept) and `SquadControlOverlay` (selection-targeted — a player bout has a real one) offer the same
`[*]` Inject menu (`InjectMenu`, one shared item list/dispatch — no parallel copies of "what does
Inject do"), calling the exact same API programmatic use does. The real safety property — no
*ordinary* click/action can ever trigger injection — now lives at `TacticsController`/`ActionBar` (the
actual gameplay-input classes, a source-level routing test proves neither references `BoutInjector` at
all), not at "which overlay happens to be installed"; `SquadControlOverlay`'s own Inject button is
additionally gated behind a real `OS.is_debug_build()` check (never even constructed in a release
export), not just the `[*]` naming convention every other debug menu in this codebase still only has.
**Debug control panel (tb30, rolled in from a planned tb31)** — three more `BoutInjector` verbs
(`attach_part`, general case behind `hand_weapon`'s existing `_attach` helper; `remove_unit`, wraps
`CombatState.kill_unit`; and tile edits `place_cover`/`clear_cover`/`set_passable`, real
`Grid.blockers`/`set_terrain`/`set_opacity` writes, no parallel spatial model). `InjectMenu` (one
shared item list/dispatch) is retired, replaced by **`DebugControlPanel`** — a generic,
data-driven click-to-force UI: `DebugVerbSpec` (id/label/typed params/apply `Callable`) rows,
`DebugVerbs.all()` the full table, `DebugControlPanel` builds its form from that table alone, so a
new verb is a new row, never new panel code (deliberately excludes `force_action`/`equip_from_kit`/
`set_therms` — no generic widget can build an arbitrary `CombatAction` or authored `Kit`, and therms
aren't built). A "Pick" button next to a Unit/Cell field arms a one-shot board-click capture via a
new duck-typed `board_clicked` signal / `input_capture_mode` flag on both `TacticsController` and
`SpectatorOverlay` — same shape on both, so "Pick on Board" works identically in a player bout and
spectator, and neither gameplay-input class needs to import the panel or `BoutInjector` to expose
it (the source-routing test from the tb29 paragraph above still holds against both). Both overlays'
Inject button now opens/closes this one shared panel instead of a per-target popup menu.
**Fix: debug panel had no anchor, sat on top of the pre-existing top-left HUD (tb30 follow-up)** — a
freshly opened `DebugControlPanel` defaulted to the top-left corner with no anchor set at all,
landing directly on top of `controls`/`tunables` (both already anchored there in both overlays). New
`_center_top()` (horizontal center, a fixed `TOP_MARGIN` from the top) runs once after `setup()`'s
layout settles and again on every `get_viewport().size_changed`, so a mid-session window resize
doesn't leave it off-center; `test_debug_control_panel.gd` pins the real node's `position` back
rather than re-deriving the centering formula.
**Active-target memory + move-object (tb30 follow-up)** — the panel now keeps an "active target":
every board click while it's open (not just a field's own "Pick") updates it and a label above the
panel's own control column shows it, via the same `board_clicked`/`input_capture_mode` hook, now
armed/disarmed against the panel's own visibility instead of per-pick. `BoutInjector.move_object
(target, to_cell)` generalizes `set_position` (unit-only) to move whatever a hit-shaped `{kind, unit,
cell}` dict points at — a unit (delegates to a shared `_move_unit` helper `set_position` also fronts,
the same split `_attach` already uses, logged under its own verb name), or a cell's `Grid.blockers`/
`Grid.field_items` contents (a real dictionary re-key, preserving the Part's own state, never a fresh
duplicate). A new `DebugVerbSpec.ParamType.OBJECT` always resolves from the active target, never a
manual-entry widget. Move Object keeps its `to_cell` param's ordinary manual X/Y entry and adds a
"Move On Next Click" button — snapshots the active target, then applies the move the instant the next
board click lands, no separate Apply press. The verb picker itself is now a scrolling `ItemList` on
the panel's left side; selecting a verb populates a "control panel" column on the right with that
verb's own param rows, Apply, and status — the panel's whole layout, not just its verb table, stays
data-driven off `DebugVerbs.all()`.
**Fix: a debug-spawned unit rendered nothing (tb30 follow-up)** — `BattleScene.unit_views` was only
ever populated once, in `load_battle()`'s own build loop; `BoutInjector.spawn_unit` adds straight into
`combat_state.units` with no view ever constructed for it. New `BattleScene.sync_unit_views()` diffs
the two and builds the missing `HitVolumeView`(s), mirroring `load_battle()`'s own construction; both
overlays' `_on_debug_panel_applied` call it before `refresh_unit_views()`. Confirmed fixed by the
supervisor. (An initial theory that a reported "move also doesn't visually work" was the same bug,
tested against an already-invisible just-spawned unit, was WRONG — the supervisor had tested move
first, separately; still open, see docs/BUGS.md/the taskblock report.)

**Fix: debug `remove_unit` never actually looked dead (tb30 follow-up)** — `HitVolumeView.is_downed()`
(the one thing `refresh()` checks to pick the DOWN pose) reads `Unit.resolve_matrix() == null`, never
`alive` directly — the same thing a REAL kill leaves behind (`DamageResolver.eject_matrix_if_needed`
nulls the hosting part's own `hosted_matrix`, drops it as a loose `Grid.field_items` entry, THEN calls
`kill_unit`). `remove_unit` only ever did the `kill_unit` half, so `resolve_matrix()` kept finding the
still-docked matrix and the view never changed. Now ejects the matrix the same way first — a debug
removal reads exactly like a real kill instead of a flag flip nothing checks.
**Renamed `kill`; `spawn_object`/`remove_object` generalize the rest (tb30, same-day follow-up)** —
the supervisor split debug removal into two distinct verbs: `kill` (this fix above, unchanged
behavior, renamed) is a REAL narratively true death; new `remove_object(target)` is debug-only
cleanup that makes whatever the active target is — a unit, cover, or a loose item — vanish ENTIRELY,
no corpse, via the same hit-shaped `{kind, unit, cell}` dict `move_object` already consumes. A unit
hit calls `CombatState.kill_unit` (bare, no matrix ejection); a cell hit erases both `Grid.blockers`
and `Grid.field_items` there at once. `BattleScene.remove_unit_view()` is the view-layer half
(`BoutInjector` itself can't touch the SceneTree) — destroys the unit's `HitVolumeView` and tracks its
id in `_removed_unit_ids` so a LATER debug verb's own `sync_unit_views()` pass never resurrects it
(reset on every `load_battle()`). New `spawn_object(cell, part_id, pool, as_cover)` generalizes
`place_cover` to also cover the loose-item half of `Grid` (`field_items`) — `place_cover`/`clear_cover`
refactored into shared raw `_place_cover`/`_clear_cover`/`_spawn_field_item` helpers (no parallel
logic), still directly callable, just no longer separate panel rows next to their own generalization.

**Fix: `Grid.field_items` had zero visual representation anywhere (tb30 follow-up)** — a real,
pre-existing `Grid` concept (loose dropped Parts/Matrices — a real kill's own matrix ejection, a
severed limb, or now a debug `spawn_object` loose-item drop) that nothing ever drew, in debug tooling
OR real gameplay. `BoardView.build()` now also iterates `grid.field_items`: a loose Part reuses
`_spawn_blocker`'s own box geometry (same "render is hitbox" contract, just never registered as a
movement/LoS obstruction); a loose Matrix (no `volume`) gets a flat placeholder marker. `board_view.
build()` was also only ever called once, at `load_battle()` — the exact same gap `sync_unit_views()`
already closed for units, unnoticed for cover. New `BattleScene.sync_board_view()` re-triggers
`build()` (already a correct full clear-and-rebuild) after any debug verb touching blockers/
field_items, called from both overlays' `_on_debug_panel_applied` alongside `sync_unit_views()`.

**Fix: action-bar affordability read the raw unit, not the queue preview (BR27.05)** —
`ActionBar.refresh()`/`_on_box_gui_input()` both compared against `tactics.selection.selected_unit.ap`
directly. Per docs/09's own "queuing mutates nothing," `unit.ap` never drops for an action that's
merely queued this turn, only once it resolves — so an action already committed to the queue (e.g. a
move that burned AP once MP ran out) was invisible to a LATER slot's own affordability check, which
kept reading the unit's full starting AP and stayed clickable regardless. Both call sites now read
`tactics.selection.previewed_unit()` instead — the same source `reachable_cells()` already uses for
the identical reason.

**Fix: Step Out evaluated cover from the shooter's stale pre-move cell (BR27.06)** — same bug class as
BR27.05, one file over. `TacticsController._enter_aim_or_step_out_mode` read `selection.selected_unit`
directly; per docs/09's "queuing mutates nothing," that stays at the shooter's turn-start cell until
the queue resolves, so a player who moved toward/into cover and THEN armed a shot had cover evaluated
from the stale pre-move position — silently falling through to ordinary aim mode instead of the
step-out the shooter's real, about-to-be-true position warranted. Root-caused by first disproving a
standing hypothesis from this taskblock's own earlier BR27.06 investigation ("the trigger condition
may just be too rare on real maps"): a 60-seed sweep of real `MapGen` maps driven through full
AI-vs-AI bouts found ~1850 genuine covered-with-a-candidate encounters, and `MapGen._scatter_cover`
never sets `grid.opacity`, so most of those are plainly visible/clickable too — not rare, and not an
LOS edge case. Swapped to `selection.previewed_unit()`, the same fix shape as BR27.05.

**Pass D: audit of `selected_unit` staleness across the rest of tactics-phase view code (BR30.07/
BR30.08)** — BR27.05 and BR27.06 turned out to be the same bug in two places, so tb30 audited every
other `selection.selected_unit` read that feeds position/AP-dependent state (not identity) per a
supervisor-authored suspect list. `TacticsController._confirm_step_out()` computed its outbound path
via `Pathfinder.astar(shooter.cell, firing_cell)` off the raw cell — `MoveAction.is_legal()` requires
`path[0] == actual.cell` against the unit's real (previewed) position, so a move queued before
triggering step-out silently failed to enqueue and fell through to `cancel_step_out()`, invisibly.
`TooltipController.refresh()` passed the raw unit into `TileInspection.inspect()`, whose
`visible_from_selected` field runs a real LOS check from the selected cell directly — stuck showing
visibility from the turn-start position after a move was queued. Both swapped to `previewed_unit()`,
each verified failing without the fix and passing with it first. `step_out_exposure()`/
`_refresh_overlay()`'s own `Overwatch` calls were ALSO flagged as suspects but, after tracing (and an
empirical probe), turned out not to matter — `would_trigger_at()`'s general-case branch always
re-resolves the mover by id and relocates to the candidate cell regardless of the passed reference's
own stale `.cell`, so no fix was needed there.

**Fix: shots resolved straight through walls (BR30.10)** — `LoS.has_los()` and `ShotPlane.build()` read
entirely disjoint data: `LoS` reads only `grid.opacity` (correctly opaque for wall cells, gating
tactical aim/step-out decisions), while `ShotPlane.build()` only ever projects `state.units` and
`state.grid.blockers` — never `opacity`. `MapGen` never wrote a `blockers` entry for WALL cells (only
scattered cover got one), so a real wall had an opacity flag but no Part, no mesh, nothing in the shot
plane — invisible to actual hit resolution even though it correctly gated the UI. `MapGen` first gave
every exposed WALL cell a `blockers` Part so a wall registered in the shot plane at all (BR30.10).
**tb31 C then reworked the model** (`docs/SUPERSEDED.md`): a wall is now a **destructible** high-DT
cover `Part` (`data/parts/wall.tres`) on an otherwise-passable `OPEN` tile — not an indestructible
terrain flag — and the negative space past a wall's ring is a new `Enums.TerrainType.VOID`
(non-navigable, opacity 0, no Part: a shot passes into it, nothing to hit). `Pathfinder.move_cost()`
now clears a **destroyed** blocker (`hp <= 0`), so a blown wall — or any dead scatter cover — opens its
tile to movement, one mechanism for both (mangle/rubble states deferred, `docs/PLAN.md`).
`MapGen._finalize_walls_and_void()` resolves this in two passes (classify every cell's exposure
against the untouched grid, then mutate) so exposure can't cascade through solid rock. **Wall
legibility** (`WallLegibility`, `BoardView`) fades a wall occluding the player's selected unit —
screen-space projection (`unproject_position` + depth), real alpha blend kept lit — so walls stop
hiding the action without vanishing; VOID cells render black with a dark-gray border.

**Fix: burst shown as affordable without enough AP; step-out silently dropped the shot (BR30.11)** —
`ActionBar._can_afford()` compared AP against the providing weapon's plain `ap_cost` for every action
id, but `BurstAction` has always charged its own, usually-higher `weapon_def.burst_ap_cost` when
authored. A unit with enough AP for the plain cost but not the real burst cost saw (and could arm)
BURST as affordable, only to have the shot silently rejected at `enqueue()` time — including after a
free step-out move, which read as "step out doesn't work with burst" even though step-out's own entry
logic is genuinely action-id-agnostic (verified directly, no fix needed there). New
`ActionCatalog.ap_cost_for(action_id, provider)` is the one seam both `ActionBar._can_afford()` and
`BurstAction._ap_cost()` (now a one-line delegate) read, closing the drift.

**Inspect panel** (tb21/22/23/26) — the current inspect surface: rotating bot viewer, matrix area,
sorted inventory tree (weapons→containers→parts), info panel + item viewer, status/wound column,
dead-zone hold, right-click debug menu (debug-only items `[*]`-prefixed; inflict-status/create-part
submenus, tb22 G). The one inventory surface in player view too — `InventoryPanel` retired (tb22 I).
Click-to-pause-inspect in spectator, id+squad+variant in the header (tb26 C3). The isolate camera
(single-unit preview) shows the model standing on real ground, correctly lit, not floating in a
void (tb23 E2). **Tile/object inspector** (tb26 E) — `InspectPanel.open_tile(cell, root)` wraps a
tile's blocker Part (or null, a bare tile) in a matrixless, shell-only synthetic Unit and drives it
through the same display path a real unit uses, no parallel inspector; spectator's click-to-inspect
falls through to `BoardPicker.cell_at_ray` when a click misses every unit's own body.

**Transparency** (docs/08) — one `StatResolver`, provenance on every value, tooltip == damage from
one call.

**Control-surface consolidation** (tb31 A) — `TopLeftControls` (a shared `HBoxContainer`) is the one
construction path for Inject / New Battle / Watch across `SpectatorOverlay` and `SquadControlOverlay`,
where each overlay previously built its own copy; grouped top-left, clear of the debug panel's anchor.
The keybindings display now defaults off, toggled by a `Keybindings` button alongside the existing
H-key. Fixed a latent click-passthrough bug found while wiring it (the shared container's
`mouse_filter` defaulted STOP, swallowing clicks in the gaps between buttons).

**Aim view: truth & legibility** (tb34) — the dartboard was quietly lying: `AimController.resolve`
(the drawn board) called `Dartboard.resolve_scatter` with no range multiplier while every real shot
(`AttackAction`/`BurstAction`/`StabAction`) correctly widened with distance, so the board shown was
always the weapon's best-case accuracy and understated spread more the farther you fired. New
`ShotScatter.for_shot` is the one place `range_cells → RangeModel.dartboard_radius_scale →
Dartboard.resolve_scatter` gets assembled now — every consumer calls it, so the drawn and fired boards
can't independently drift again. Fixed the cache landmine this creates: `AimView._rings_match` now
keys on ring-to-outer-ring ratio instead of absolute radius, so a pure range change resizes the decal
instead of rebuilding the 128x128 ring image pixel-by-pixel every frame (`DartboardTexture.build`
already normalizes by `outer_radius`, so a uniform rescale is byte-identical). Two previously-invisible
spread sources now draw: a burst's later pulls widen the board cumulatively
(`RecoilResolver.widen`), but only pull 0 ever showed — `AimController.recoil_bound_radius` draws the
widest pull's own bound as a crisp outline, baked into the same texture (its ratio to the outer ring is
weapon-constant, so the cache invariant survives); a pellet round's mechanical spread pattern
(`SpreadPattern.pattern_radius`, made public) doesn't scale with range, so it's drawn as a genuinely
separate, un-cached overlay circle (`DartboardTexture.build_solid_dot`) rather than baked in. **Part
tooltips in aim view** — new `TacticsController.update_aim_hover` maps the cursor to an aim-plane point
and finds the Region there (`ShotPlane.region_at`, a thin public alias for the internal
`resolve_projectile`), writing only `aim_hovered_part`, never the reticle or `resolves` — hovering
reads, it never re-aims, split into its own function so that's structural, not just documented.
`AimView` renders the hit part's tooltip in-world via a `Label3D` coplanar with the aim window
(`TooltipView.to_plain_text`, a third host for the same `TooltipData` shape `to_bbcode` already
renders, since `Label3D` has no BBCode support). **Sniper framing** — beyond
`CameraOrbitState.SNIPER_FRAME_DISTANCE` (5 cells, a tunable), the attack camera frames the target
alone (`sniper_framing`) instead of shooter-over-shoulder (`attack_framing`): this rig's own topology
(the camera always faces its own pivot) means panning directly onto the target's center puts it
dead-center on screen at any yaw/pitch, so no dual-sphere BACK solve is needed, just a closed-form
single-sphere zoom. Both framings ease through the same shared tween
(`CameraRig.ease_to_framing`/`_ease_to`). **Fix: BR26.02, low framerate while aiming** — two real costs
removed: the cache-invalidation fix above, and a redundant `AimView._process()` override (found
2026-07-21, applied here) that unconditionally called `refresh()` every single frame while aiming even
though `refresh()` was already fully wired to `tactics.aim_changed`; deleted outright once every
mutation path was re-confirmed to emit it. `docs/BUGS.md`'s own scroll-layer-cycles-walls finding
(BR33.01) is deliberately still open — a policy call, not a mechanism one, left for the supervisor to
decide having now seen this block's finished aim view.


### Diagnostics: the log becomes the instrument (tb41 Passes A–D, F, docs/09)
**Render coalescing (Pass A, BR27.09 cost #1).** `emit()` updates the model and marks dirty; the
`RichTextLabel` draw happens at most once per frame, driven from `ControlOverlay._process`. New shared
`UiLogSink` base; both `UISink` and `HierarchicalUiSink` extend it. **BR27.09's own prescribed fix —
incremental `append_text` — was overridden with the supervisor's approval and NOT taken**: it fits the
flat sink but cannot fit the folding one, where a new event routinely rewrites an existing group's
summary rather than appending a row. Coalescing is correct for both, and its real value is that render
cost stops scaling with event count *at all*, which is what makes Pass D affordable.
Measured on BR27.09's own scenario (200-line scrollback, 3v3, peak 29 events), real classes against a
real label in a real tree: `UISink` 4845µs → 225µs on a peak turn, `HierarchicalUiSink` 10058µs →
870µs. **`HierarchicalUiSink` had never actually been measured and is ~2× the sink that had been** —
~10ms on a peak turn in the sink both live overlays use, not the ~5ms BR27.09 estimated from the flat
one. Headless and a real x11 display agreed within ~2%. **The several-second hitch survives, as
expected** — its mechanism is the synchronous AI batch, untouched here; BR27.09 stays `Active`.

**Engine and script errors on the same stream (Pass B).** `EngineErrorTap` is a real Godot `Logger`
(`OS.add_logger`); every error becomes a `LogEvent` of kind `diagnostic` on whichever `CombatLog` is
current. `LogSink.wants()` is the opt-out, checked once in `CombatLog.emit()`. **The reachable set was
observed, not assumed**: `push_error`/`push_warning`, GDScript runtime errors *with the real script
file and line*, and engine-internal C++ `ERR_FAIL_*` all reach it; **a hard crash never will**, and
that boundary is stated in docs/09 rather than left implied. One engine failure can produce several
callbacks as the C++ chain unwinds — reported faithfully, not deduplicated. `_log_message` is
deliberately not hooked (`print()` routes through it and `StdoutSink` prints every event — an
unbounded loop).

**Commands paired with outcomes (Pass C).** `CommandLog` emits a `command` event before every attempt
and a `command_outcome` after, carrying a machine-readable `reason`. Pass B covered every rejection
that already went through `push_error`; this covered the remainder — **~40 bare `return false` paths in
`BoutInjector` that were silent even to the console**, each now naming its cause. Shared helpers stopped
answering only "no": `_move_unit`/`_place_cover`/`_clear_cover`/`_spawn_field_item` return a reason and
`_attach` returns `{part, reason}`, because three different failures collapsing into one null left
callers unable to say which happened. A refusal while queueing and a refusal at resolution read
differently. `try_apply` no longer refuses silently and `resolution_stopped` names the action that
could not run. **Reverses tb29's "a rejected call is a true no-op (no log entry)"** — the mutation and
RNG halves stand, the silence does not (`SUPERSEDED.md`). **Not done:** a per-action legality *reason*
would mean changing `is_legal`'s signature across every action; deliberately out of scope, so
`try_apply` reports `action_illegal` plus the action's own `describe()`.

**Deliberate verbosity and the bout-build log (Pass D).** `BoardView.build()` narrates itself in
construction order — terrain, grid lines, empty tiles, extraction tiles, walls, cover, field items —
each with its own count and a running index, counted where they are built rather than re-derived from
the grid. Plus `unit_assembled` (listing parts in socket-tree order) and `overlay_activated`/
`overlay_deactivated`. **"bot constructed, part attached" is logged where a unit ENTERS the world**, not
inside `DeepStrike`/`BodyAssembler`/`PartGraph.attach`: those are pure static logic with no `CombatLog`
in reach, and threading one down would push a diagnostic concern into the deepest layer for a per-socket
event nobody asked for. **The wall cutout is deliberately NOT logged per frame** — it runs every frame
on every wall while the camera orbits and `FileSink` flushes per line, so it logs only when the cut set
meaningfully changes. `LogFold` folds the new high-volume kinds into one counted row per run;
`diagnostic` is pointedly excluded, because collapsing an error into a quiet counted row is the
opposite of what an error is for.
*Fixed a regression this pass caused:* the build log displaced `session_start` from the log file's
first line, breaking docs/09's "replayable from its own log file alone". `load_battle` now takes an
optional header event emitted between attaching the sinks and building anything, and the active
overlay's log sink attaches explicitly at that point (`ControlOverlay.attach_log_sink`) instead of as a
side effect of `battle_loaded`, which fires at the *end* of the load and missed everything.

**The log becomes a window (Pass F).** `CombatLogPanel`: title bar, minimize, drag-to-resize, a real
background, scroll hand-off at the content's ends, and a live FPS readout in the title bar.
`FpsMeter` and `LogScrollHandoff` hold the real rules and are headlessly tested; the chrome is
plumbing, deliberately untested, and this pass is **a session opener, not a definition of done**.
docs/09 now records that `FpsDumpSink` and this readout are *supposed* to disagree and must not be
reconciled — the gap between them is the only signal separating BR26.02 from BR27.09. **BR34.02 is
answered structurally (the panel has a real background) but NOT closed** — it is `SUPERVISOR`-owned.
*Two layout bugs were found by rendering, not by testing*: a `PanelContainer` sizes every child to
fill, so the readout stacked under the log instead of overlaying it; and `PRESET_TOP_RIGHT` bakes
offsets from a zero-width Label, so it grew off the panel and over the board. Neither was visible to
any headless assertion. `SpectatorOverlay` still uses its own bare label — converting it belongs to the
live iteration this pass opens.
*Supervisor follow-up, same block:* panel widened to a self-declared 520px (it previously inherited
~260px from the surrounding column, which cut most lines off), and **the scroll hand-off was fixed —
it had never actually worked.** `LogScrollHandoff` was correct and unit-tested throughout; the rule was
simply never consulted, because Godot marks a mouse event handled whenever it reaches a
`MOUSE_FILTER_STOP` control under the cursor, whether or not that control calls `accept_event()`. The
`RichTextLabel` consumed the wheel before `_gui_input` on the panel ever ran. Handing off therefore
**`BR34.02` closed `Resolved` by the supervisor** — the panel's real background was one of the two
changes that entry asked for; the `mouse_filter` sweep it also wanted is still outstanding.
*Then the scroll behaviour was reversed outright on supervisor correction*, and the reversal is the
more useful record: Pass F's spec said the wheel should fall through to the camera at the content's
ends, **which is the behaviour `BR30.05` already reports as a bug** for the debug panel — so building
it as written reproduced a known defect somewhere new. The log now absorbs the wheel whenever the
cursor is over it. Two implementation attempts were wrong before the third worked, both because
`MOUSE_FILTER_STOP` does less than it appears to: it consumes clicks (which is why left/middle/right
always behaved) but a wheel still reaches `_unhandled_input`, and `RichTextLabel` scrolls without
consuming. The panel now scrolls explicitly in `_input` and calls `set_input_as_handled()`.
`LogScrollHandoff` and its unit tests are deleted — the rule they encoded no longer exists. **A
cautionary case worth keeping:** that class was correct and green throughout, while the feature it
served did nothing at all, because nothing ever asked it. Only a spy at the real input stage showed
it (`test_combat_log_panel.gd`), and that test carries a deliberate control case so it cannot pass
vacuously.

**`BR30.05` — the same two defects in the debug panel, fixed (`Pending`, `SUPERVISOR`-owned).**
Clicks: `DebugControlPanel` was `MOUSE_FILTER_IGNORE` on taskblock-07 Pass B4's "a plain container
has no click of its own" rule — but it is a `PanelContainer` with an opaque `HulkTheme` background,
so the rule does not fit it; scoped to genuinely invisible containers and this panel set to `STOP`
(`SUPERSEDED.md`). Scroll: the 2021 diagnosis blamed `ItemList` not marking the wheel handled *once
it can't scroll further* — the real fact is broader and was measured, **`MOUSE_FILTER_STOP` never
blocks a wheel from `_unhandled_input` at any scroll position**. The panel consumes it explicitly.
The wheel is **forwarded before being consumed** rather than swallowed: consuming wholesale would
have silently deleted `SpinBox`'s wheel-to-adjust, which several verb forms use, so the event routes
to whatever is under the cursor first (verb list scrolls, `Range` steps) and only then is marked
handled. The forwarding hit-tests by position rather than reading
`Viewport.gui_get_hovered_control()`, because hover is only bookkept from real mouse *motion* and is
null whenever a wheel arrives without one — caught by the `SpinBox` test failing against the hover
version. The entry's own request for a repo-wide `mouse_filter` sweep is **not** covered.

### Checkpoints return as an ordinary tool (tb41 Pass E, docs/09)
The **gate** was retired, not the capability: no hard stop, no permission step. `./checkpoint.sh N`
runs `tools/checkpoints/checkpoint_N.gd` against a real display; the driver is generic and **the
scenario owns its own README and checklist**, so the description cannot drift from the code (three
heredocs were ~200 of the driver's 224 lines).
**The parse guard is the load-bearing piece.** Visual checkpoints sit outside the headless gate by
necessity, so nothing re-runs them — which is how a `UnitView` rename orphaned two scripts for ~15
taskblocks with nothing going red (`BR40.02`). Rendering can't happen in CI; parsing can.
`tools/checkpoints/parse_guard.gd` fails the build on a parse error or a script that stopped being a
`SceneTree` entry point. **It is a script, not a GUT test, and that was found the hard way:** written
as a test first, it worked — but `run_tests.sh` runs GUT with `-d`, and under the debugger a parse
error raises a break that *waits for input*, so the guard would have hung the build instead of failing
it. It now runs without `-d`, ahead of GUT. Proven both ways by reintroducing BR40.02's exact
`UnitView` reference and watching each behave.
`checkpoint_{6,7}.gd` **deleted** rather than repaired — updating two dead scripts so they could then
be removed is work with no product. `BR40.02` closed as **`Obsolete`, not `Resolved`**: nobody
verified a fix, because there was no fix. `out/checkpoints/` is local-only now (`.gitignore` plus
`git rm -r --cached`; the ignore alone does not untrack), with `out/checkpoints-kept/` tracked so
keeping an image is a copy rather than a forgotten `git add -f`. **The durable artifact is the answers,
not the images** — they go in `reports/`. The old GUT-based checkpoints 1–5 left `checkpoint.sh`
entirely: they were never checkpoints, just regression tests, and now live under `test/baselines/` with
names that say so.

### Both views share one combat log (supervisor request, post-tb41)
`SpectatorOverlay`'s bare `RichTextLabel` is retired for the same `CombatLogPanel` the player view
uses, so the title bar, drag-to-resize, `[-]`/`[+]` minimize, real background, wheel absorption and
FPS readout stop being a player-view-only privilege — two views with two log widgets is how they
drift apart every time one is improved.

The panel writes its height through **both** `custom_minimum_size.y` and `size.y`. The overlays lay
it out completely differently — a column child in the player view, absolutely positioned against the
bottom-left corner in the spectator view — and each situation respects only one of those, so writing
one leaves drag-to-resize silently inert in whichever view the author wasn't looking at.

**`fps_dump` joined `LogFold.PLUMBING_KINDS` off the back of it, and that was a real bug nobody had
reported.** Rendering the converted spectator log showed eleven identical `Turn FPS ... 74.0` rows
filling the panel and pushing every combat event out of view: `FpsDumpSink` emits one per turn, and
Pass D never added the kind to the fold list. Folded, not dropped — `out/combat.log` is unaffected,
folding being presentation only (tb22 F2). **The same flooding was live in the player view**; the
spectator view only made it obvious because it runs turns continuously.

Checkpoint 9 (`./checkpoint.sh 9`) authored for the conversion under Pass E's own no-permission
policy — and it earned the parse guard its keep immediately: the first draft called a
`DataLibrary.bot_presets()` that does not exist, and the guard failed the run and named the file
before anything rendered.

### Bug hunt: the turn-boundary hitch, measured (tb42 Passes A–E, BR27.09/BR26.02)
**Partial by design; F and G are not started.** The block's result is a diagnosis, not a fix.

**Pass A — the instrument.** BR26.02's 2026-07-23 revision, unbuilt since. Two dumps per turn:
`turn_boundary` at **0ms** (the boundary cost itself — the number BR27.09 is about, which did not
previously exist at any offset) and `turn_settled` at **2000ms**. The boundary dump is emitted
**synchronously**: any await would push it past the transient it exists to catch. The aim-entry dump
moved to the same delay and reads the shared constant.

**Passes B–C — costs #2 and #3 cut, and they are small.** `HitVolumeView.refresh()` freed and
re-instanced every child even when only a transform changed: 858µs → **351µs** on the move path,
795µs → **267µs** on the aim path. The cheap path **refuses** on any node-set difference rather than
enumerating safe cases. Turn start walked the socket tree five separate times (instrumented and
confirmed — BR27.09's "5–6" was right): 118µs → **40µs**, threaded rather than cached, because a
stale power reading is a silent wrong number. **Both together are under 1% of one AI step.**

**Pass D — the batch yields, and the hitch survives.** `advance_ai_turns` had no `await` at all; it
now yields a frame between units, so input stays alive and each unit's move is visible instead of the
opposing team teleporting. **But a single `BoutRunner.step()` costs ~1672ms** — 24 steps of a real
3v3 bout is 40.1 seconds of pure planning. Yielding between steps buys one responsive frame every
~1.7s. **The several-second hitch is ONE `UnitAI.plan_turn` call, not an accumulation**, so this
relocates the bug rather than fixing it: the remaining work is per-candidate-cell pathfinding/LOS/
cover scoring in `unit_ai.gd`, which tb35 Pass A3 halved once and which has grown back.
**⇒ SUPERSEDED in part by "AI planning cost" (tb43) below — that naming of the remainder was right
about the file and wrong about the function.** The candidate scoring is ~25% of a planning turn;
`_any_reachable_has_lof`'s prefilter scan over the whole reachable set is ~70%. Determinism
verified — a seeded bout is identical through the yielding path and a tight no-yield loop.
Coalescing fork settled as "refresh only the units that step touched", which is proportional to what
changed rather than tb19 I2's measured whole-board waste.

**Pass E — the debug path.** Every debug verb triggered a full `BoardView.build()`, including the ~20
that touch one unit's AP or facing; `DebugVerbs.affects_board()` is now the one authority both
overlays read (BR35.03, `Pending`). Also fixed: `BoutInjector._move_unit` set `unit.cell` without
re-deriving `unit.height`, so a debug move onto a raised cell rendered at the old elevation —
invisible on a flat map, which is why every flat fixture missed it. **Not a fix for BR30.02**, whose
symptom still does not reproduce. `BR35.01` deliberately untouched and said so.

### AI planning cost: cut the search, and find out the search was not the cost (tb43 Passes A–D, BR27.09)

**The block did what it set out to do and disproved its own premise doing it.** It is scoped as
"attack the candidate count and the work per candidate", on the standing assumption — carried by
tb35, tb42 and this block alike — that `UnitAI._pick_engagement_position` is where an AI turn's
seconds go. Passes A, B and D all attack it. **It is about a quarter of a planning turn.** The
measurement that says so is in Pass D below, and it retargets BR27.09.

**The instrument first.** `tools/bench_ai_planning.gd` — 5 seeds x 12 steps of a 3v3, headless and
repeatable, reporting ms per AI step, the Pass B difference rate, a per-role cost split, a branch
census, and a `--profile` breakdown of one turn. Every number here comes from it. **The earlier
~1672ms/~1498ms figures in this bug came from a bench nobody kept and are not part of this series** —
this one starts at ~745ms for the same work, and only differences within it mean anything.

**Pass A — exact early-out in the scorer** (landed in a prior session, `8ebca0e`). Every term in
`_engagement_score` is a non-negative penalty except `cover_bonus`, which is bounded by
`COVER_SCORE_BONUS`, so a cell whose cheap terms already put its ceiling at or below the best
complete score cannot win and skips both line walks whole. `<=` rather than `<` because selection is
strict `>`: a cell that can at best tie never wins. Acceptance was identical output, not speed.
**~1672ms → ~1498ms on the old bench (~10%).**

**Pass B — the candidate rectangle** (`src/logic/ai/engagement_rect.gd`). Scores only the reachable
cells inside a box with two corners on the unit and its target, padded 2 laterally and, on the far
side beyond the unit, by the weapon's own standoff distance. **The asymmetric half is the load-bearing
half**: a unit that wants to back off finds its cells behind itself, exactly where a symmetric pad is
thinnest, and `MIN_COMPLETION_RATE` would very likely still pass while the optimisation shoved
long-range units into knife fights. **~745ms → ~674ms (~9%), keeping 64.9% of candidates
(95.7 → 62.1 per decision), chosen cell differing in 7 of 60 decisions (11.7%)** — much of that being
cells that *tie*, since on open ground a whole arc sits at the standoff distance and scores
identically. The LOF prefilter deliberately still sees the **whole** reachable set: culling before it
would flip which branch runs, not just which cell wins inside one.

**Pass C — batch plumbing.** `Unit.batch_id` (0 = independent, and every generated mission leaves it
there), a `set_batch` injector verb and debug-panel row, a round-scoped `BatchPlan` on `CombatState`,
and a board badge (`B2`, `B2*` for the leader) whose text is decided by a headless logic-layer
function so what it says is testable without a screen. Explicitly **not** `squad_id`: that is the
team, and overloading it would make every batch a second team.

**Pass D — leaders plan, followers follow.** First member of a batch to take a turn claims the lead
and pays for the full search; later members that round read its destination and scan the ≤9 cells
around it. Leadership is **derived, never stored** — no `leader_id`, no promotion logic, nothing to
desync; a leader dying mid-round leaves its record intact so the squad finishes the manoeuvre and
reorganises next round when the record ages out.

**Pass D's own acceptance is NOT met, and that is the block's most valuable output.** It asks for a
follower to be dramatically cheaper and says that if it isn't, the local scan is too wide. Measured:
**leader ~330ms, follower ~317ms, about 4%** — and the scan cannot be narrowed below radius 1. So the
turn was profiled rather than the constant tuned, and per repositioning turn (means over 60):

| | ms |
|---|---|
| `_any_reachable_has_lof` | **271.9** |
| `_pick_engagement_position` | 98.3 |
| `_nearest_living_enemy` | 15.0 |
| `Pathfinder.reachable` | 2.5 |

**The LOF prefilter scan over the whole reachable set is the real remaining cost**, and it is paid by
leader and follower alike. Branch census over the same 60 turns — `repositioned` 23,
`no_lof_no_route` 15, `followed_leader` 10, `closing_fallback` 4, `fired_in_place` 5, `stepped_out` 2
— shows **19 turns in 60 end with no reachable cell having a line at all**, each having scanned every
reachable cell to find out. The cheapest exact attack is ordering that scan nearest-the-target first,
since it early-returns on the first hit and currently walks BFS-from-the-unit order. **Deliberately
not built**: this block is triage with a stated scope. It is in `PLAN.md` and on BR27.09.

Whole-bout effect of batching one squad of three: **~671ms → ~646ms per AI step.** BR27.09 stays
`Active`; nothing here closes it.

### AI v2, part one: measure, invert, seam (tb44 Passes A–D, BR27.09/BR44.01)

**Every performance figure this project had ever recorded came from a tools binary**, and nobody had
checked how much of the hitch was GDScript's debug per-line overhead. Now measured, on the same bench
and seeds throughout: `editor_debug` ~686–712ms → `exported_release` ~530–554ms per AI step,
**~1.29×**. Roughly 78% of the cost survives into a real player build, so the planning cost is
genuine. `src/debug/build_identity.gd` classifies the running build and is stamped into the bench's
first line and every `fps_dump` event, so a number never again needs its provenance explained in
prose. `tools/bench_release.sh` runs both builds and refuses to report unless the binary itself
declares `build=exported_release`.

**Getting that number required fixing BR44.01, and it is the more consequential find: the first-ever
export of this project loaded no data at all** — no parts, ammo, presets, materials or variant
families. `DataLibrary._load_dir` filtered on `ends_with(".tres")`, true in the editor and false in
every export, since `convert_text_resources_to_binary` ships `crab.res` + `crab.tres.remap`. It
presented as a bare SIGFPE with no message, because an empty pool makes `i % pool.size()` an integer
modulo by zero that a release build traps at the CPU. Two structural consequences: an export template
**ignores `-s res://...`** (confirmed by passing a nonexistent script and getting the identical
crash), so the bench needed a main-scene entry point behind a `bench` feature tag; and the bench body
moved to `AiPlanningBench` so the debug and release entry points cannot drift.

**The line-of-fire query is inverted** (`src/logic/visibility_field.gd`). One `VisibilityField` per
target per turn, `PackedInt64Array`, flat `i = x + y*W + z*W*H`; each candidate's question becomes a
bit test. **~700ms → ~525ms per AI step (~24%)**, ~412ms release. It is a conservative **prefilter** —
one obligation, never report "no line" where one exists — and `ShotPlane` stays final, so acceptance
was identical output. It deliberately over-includes on cover, on units, and across elevations. The
occluder test is opacity **and** a blocker the plane would actually resolve against
(`BodyProjector.projects`, extracted so there is one answer): opacity alone is *wrong*, not coarse,
because `Grid.opacity` is never cleared when a wall dies. The all-negative case — 19 of 60 turns in
taskblock-43's census — now costs **exactly zero** `ShotPlane` builds.

**Where the cost went, which is the pass's real output.** `any_lof_scan` 271.9 → 77.8ms, new
`field_build` 4.2ms, but `engagement_search` 98.3 → **251.2ms**. The scorer did not get slower; it was
being subsidised by a scan that built a plane for nearly every reachable cell and left them in the
per-turn memo. The remaining cost is per-candidate casts inside `_engagement_score`.

**The `WorldView` seam** is the planner's entry point; `CombatState` reaches it only through
`canonical_state_for_resolvers()`. Today it returns everything — a pass-through with a doorway in it,
byte-identical across a seeded bout. **The boundary is not `CombatState` versus not-`CombatState`: it
is knowledge-about-units versus everything else, and that line runs THROUGH `Grid` and THROUGH
`BatchPlan`.** Geometry is free; occupancy is not geometry (`Grid.occupant_id` would leak every unit's
position past the filter, so the guard forbids it); the team blackboard is a Trained-and-above tier
capability, so batch plans are observer-gated on both read and write. The resolver door may appear
only as a bare argument, never followed by a dot — greppable, and enforced, because a prose rule with
no enforcement is what BR40.02 was. Restriction is stubbed behind a disabled flag with staleness
derived rather than maintained, and an anti-vacuity test proves a restricted view changes what a unit
decides.

**A unit's turn is now navigable rather than frozen.** The planner yields mid-plan every `chunk`
candidates and the acting unit is named on screen while it thinks. This makes nothing faster and is
not meant to: taskblock-42 Pass D yielded *between* steps, which bought nothing, because one step is
the entire think. The chain became coroutines because GDScript rejects a conditional-await single
implementation at parse time and a second planner would be two paths deciding one thing. A hard turn
budget backs the label, since a thinking state that never ends is worse than a freeze; aborting is
safe at any iteration because the incumbent is the unit's own cell until strictly beaten. Frame
boundaries do not change decisions, asserted directly.

### AI v2, part two: the utility planner replaces the branch cascade (tb45 Passes A–E, docs/PLAN.md)

**The engagement-score planner is deleted.** `src/logic/ai/unit_ai.gd` — 1369 lines, eight
`max-file-lines` bumps, every one justified by "part two replaces this file" — is gone, and the
linter cap is back at its default 1000. `test/unit/test_retired_planner_sweep.gd` greps `src/`,
`test/` and `tools/` for the retired name and asserts the 1000 directly, so neither can drift back
silently. Full retirement note, including the measured before/after, in `SUPERSEDED.md`.

**The model** (Pass A). `ResponseCurve` / `ConsiderationDef` / `UtilityActionDef` / `UtilityProfile`
as data; `UtilityScorer` as the maths. Considerations MULTIPLY, so one zero vetoes outright; the
IAUS compensation factor keeps a 5-consideration action comparable to a 2-consideration one at equal
quality. **The compensation is not exact and the residual is documented rather than hidden** — it
shrinks the dimensional penalty from "five inputs retain 51%" to "89%", and the remaining ~11% is an
accepted cost, not a tuning problem.

**Selection over the existing action layer** (Pass B). `UtilityActionDef.executor_id` names one of
the twenty tested classes in `src/logic/actions/` through `UtilityExecutors`; nothing was
reimplemented. `UtilityContext` is the seam that turns a candidate cell into the `{input_id: 0–1}`
dictionary the scorer consumes — and is the only place in the planner that knows what a grid, a
weapon or a line of fire is.

**Actions and profiles are `.tres` files**, under `res://data/utility_actions/`,
`res://data/utility_profiles/` and `res://data/batch_objectives/`, loaded by `DataLibrary` like every
other content type. `PLAN.md`'s claim that the rest of the tier table "needs preconditions and a
consideration set, not new machinery" is now literal. `tools/author_taskblock45_ai.gd` authors them.

**Intelligence gates information, and the gate is load-bearing.** `WorldView.MEMORY_TIERS` makes
remembered sightings a tier capability: `MINDLESS` sees only what its own eyes currently reach and
stops knowing an enemy exists the moment line of sight breaks, where `TRAINED` acts on what it wrote
down. The two tiers decide differently on the same board and the two profiles decide differently with
tier held constant — both asserted directly, because a tier that silently does nothing is the failure
this design is most exposed to.

**A floor is not a preference — the most consequential authoring lesson of the block.** In a product
model, a consideration whose curve can reach 0.0 does not express "prefer this", it expresses
"refuse everything else". A plain linear `standoff_match` therefore meant "refuse to act more than
eight cells off the preferred distance", which would stop a rifleman with a thirty-cell weapon ever
taking a long shot, and nothing about the arithmetic announces it. Every consideration expressing a
preference is now floored; only `line_of_fire`, which expresses a genuine impossibility, can reach
zero.

**The batch objective, built dormant** (Pass C). A leader runs one coarse utility pass over four
authored objectives and the answer is injected as a consideration input for every follower — squad
coordination without a squad planner, replacing taskblock-43 Pass D's copied destination. Standing
rule 5 is untouched: the objective is computed once per batch per round and reused, never a licence
to resolve units together. **Dormant publishes an all-ones neutral vector, never all-zeros** — zeros
would veto through the product and every `batch_id == 0` unit, which is every unit in play today,
would stop acting.

**The objective damping floor had to be lowered to do anything, and that was found by testing rather
than by reading.** At 0.5 the batch had an objective, the log recorded it, every follower read it,
and **not one decision changed** — `shoot` carries a higher base weight and is served by `hold`
alone, so `advance` and `withdraw` damped it identically. At 0.25 the three cases separate. A
mechanism that is wired end to end and still inert is exactly the "silently does nothing" failure,
arriving on the batch axis instead of the tier one.

**Head to head, then the flip** (Pass D). The same seeds through both planners, 24 of them, re-taken
at the end of the block from one standalone probe with the old planner run from a worktree:

| | old | new |
|---|---|---|
| seeds 0–11 | 9/12 (75.0%) | 5/12 (41.7%) |
| seeds 12–23 | 12/12 (100%) | 8/12 (66.7%) |
| **combined** | **21/24 (87.5%)** | **13/24 (54.2%)** |
| mean turns to complete | 23.6 | **10.6** |
| per-unit plan cost, mission bout | 139.90 ms | **86.51 ms** |
| per-unit plan cost, 3v3 combat bout | 485.16 ms | **131.25 ms** |
| `ShotPlane` builds per turn | 29.1 | **0.0** |

**The speed win is large and the play regression is real but smaller than it first looked.**
`ShotPlane` builds per turn falling to exactly zero is the structural claim, not a speed tweak — line
of fire is a bit test against one `VisibilityField` per target per turn, and the canonical resolver is
consulted only when an action is actually enqueued.

**It is not uniformly worse: when it finishes, it finishes in less than half the turns.** The dominant
failure is `TERMINATED`, the turn cap running out — mostly not losing fights, failing to finish. Two
structural causes were tested and ruled out: the information restriction (identical 33.3% with the
view forced unrestricted) and the candidate-set cull (no change). **Seeds 1, 2 and 6 fail under both
planners**, so three of the eleven failures predate this block and the incremental regression is
eight seeds.

**`MIN_COMPLETION_RATE` went 0.5 → 0.25 → 0.35.** It was landed at 0.25 against a mid-block reading of
37.5%; re-measuring at the end put the real figure at 54.2% and the floor came back up to one seed
below the window the test actually samples. **This is the block's most repeatable lesson: a
measurement taken once, mid-change, is not evidence.** Three numbers here were reported before they
were true, and re-taking them cost minutes and moved the headline by seventeen points.

**A combat-only pool cannot finish a mission, and the head-to-head is what made that concrete.** The
first measurement returned **0% completion** against the old planner's 75% — not because the planner
played worse, but because completion means EXTRACTED and nothing in the Pass B pool could gather an
objective or walk to an extraction tile. The fix was four more `.tres` rows (`seek_objective`,
`gather`, `seek_extraction`) plus the mission inputs to score them over. It also exposed a real
defect the tests had not: candidate cells were computed only when an enemy was known, so a unit with
nothing in sight could not move anywhere at all.

**Three real planner defects, all found by reading the decision log rather than the code.** Each had
survived a green test suite, and each is the kind that a completion rate alone reports only as a
number:
- **A candidate is a (cell, action) pair, and the planner only moved to the cell when the action was
  itself a move.** So `shoot@(3,0)` — chosen because (3,0) sits at a good standoff — was fired from
  wherever the unit already stood. Two units traded shots across a corridor forever, neither closing.
  The log is what exposed it: every entry read `shoot@(3,0)` while the unit sat at (1,0), and the
  mismatch between those two coordinates is the whole bug in one line.
- **A unit standing on its destination scored every OTHER cell as a perfect approach.** `_closes_to`
  returned a flat 1.0 when the distance-to-target was already zero, so a unit that reached its
  extraction tile walked off it and back, every turn, forever — two units alternating onto one tile
  for a whole turn cap, neither ever standing still long enough for the hold to mature.
- **A refused action ended the turn instead of falling through.** `ActionQueue.enqueue` is the only
  thing that knows what a unit can afford from where it will actually be standing, so "the scorer
  wanted this and the executor said no" is ordinary. Stopping there meant a marksman whose own shot
  was unaffordable picked `shoot`, had it refused, and ended its turn — never reaching the overwatch
  it should have held, because overwatch was simply never scored again.

**Holding turned out to be the hardest single action to author, and it broke three different
things.** `HoldAction` keeps the unit CURRENT — that is what deferring means — so anything that lets
it win by default livelocks a bout:
- **It was offered after the unit had already acted.** A unit that spent its whole turn on six shots
  then "held", which is a contradiction: holding is a substitute for acting, not a coda to it. Only
  offered while the turn is still empty.
- **The planner appended `EndTurnAction` behind it.** Hold means *do not end my turn yet*; ending it
  anyway threw the deferral away. `UtilityActionDef.ends_turn` marks the actions nothing may be
  queued behind — data, not an `is HoldAction` branch, for the same reason `repeatable` is.
- **It won by forfeit whenever the candidate scan was short.** The retired planner only held when the
  shot was genuinely blocked; offered unconditionally, hold is what is left when everything else is
  out of range or out of reach. **The view's own `PlanPacer` budget shortens the scan**, so a watched
  bout could livelock where a headless one did not — the worst kind of difference. `lof_blocked` is
  published as an explicit inverse predicate (preconditions are an all-must-hold list with no
  negation) and hold now requires it.

**A missing `await` in the view, exposed rather than caused by this block.**
`SquadControlOverlay._on_turn_ended` called `advance_ai_turns(battle)` fire-and-forget. It is a
coroutine, so the handler returned the instant the planner first suspended and the AI batch completed
some frames later, unobserved. It had no visible effect while the old planner happened never to
suspend on small boards; the utility planner yields through `PlanPacer` on any real candidate set, and
the batch then ran after whatever came next had already read the turn state. Both call sites are
awaited now.

**`hold_position` needed `enemy_known`, which is subtler than it looks.** Holding means "defer to the
next ally, who may open a line" — a combat reason. Offered with no enemy known it broke extraction
outright: `HoldAction` ends the turn itself, so a unit on its extraction tile that chose to hold never
reached the trailing `EndTurnAction` whose hold-check is what matures a hold into a real extraction.
It sat on the tile holding, correctly, forever.

**The candidate rectangle is drawn toward the enemy, and a unit has somewhere else to be.** Culled
alone, a unit that could see an enemy could not consider a single cell toward its resource node or
extraction tile — it could fight or travel, never both. The cells that genuinely close on a mission
destination are added back, at most one per destination.

**Precedence became a weight instead of a branch.** The old planner had a hard "combat first"
ordering above a non-combat branch. Every combat action requires `enemy_known`, so with nothing in
sight the mission actions are the only ones offered and win by default; with an enemy in sight both
compete and the authored weights decide.

**Shots per turn are decided by AP, not by a constant.** `MAX_SHOTS_PER_TURN = 3` is gone; `shoot`
is authored `repeatable` and a turn fires until `ActionQueue.enqueue` refuses the shot it cannot pay
for. `MAX_SELECTIONS` is a backstop deliberately set ABOVE the AP ceiling — it sat exactly at it for
one commit, where the two were indistinguishable, and a test now keeps them apart.

**Moved out of the planner so they could outlive it**: `Cover.is_covered_from` (read by
`StepOutPlanner` and `TacticsController` for the player's own step-out affordance),
`ActionCatalog.preferred_firing_action_id`/`provided_firing_action_id` (a question about the weapon,
not the plan), and `AiPlanner.PLAYSTYLES` (the vocabulary outlives the planner; retiring it is still
`PLAN.md`'s). **~~`AiPlanner.PLAYSTYLES`~~ — overwritten by taskblock-46 Pass E below: the vocabulary
is deleted outright and a bout names a `UtilityProfile` id directly.** `EngagementRect` survived untouched — it was always pure candidate-set geometry with no
planner state in it, which is why it separated cleanly in taskblock-43 and cost nothing here.

**Found and fixed on the way: the AI planning bench had been unable to compile since taskblock-44**
(BR45.02). taskblock-44 Pass C changed the planner's helpers to take a `WorldView` and Pass D made
`_pick_engagement_position` a coroutine; the bench called all of them and was updated for neither.
Nobody found out until Pass D tried to use it. **This is BR40.02's failure mode one directory over**,
so the fix is the class rather than the instance: `tools/checkpoints/parse_guard.gd` now parses every
`tools/*.gd`, not only `tools/checkpoints/checkpoint_*.gd`.

**The guard was wrong before it was right, and the wrongness is the point.** `load()` returns a
`GDScript` object for a script that failed to COMPILE — the resource loads and the compile fails, and
they are separate events — so the widened guard reported "16 script(s) OK" with a deliberate syntax
error sitting in the tree. It checks `reload() == OK` now, and it is verified in both directions:
a deliberate break makes it fail, removing the break makes it pass. `tools/migrate_data.gd` carries
an `@retired-tool` marker — it is a taskblock-10 migration whose own doc comment records that the
generators it walks were deleted by the pass that landed its output, so it can never parse again and
reporting it every build would be noise.

### A performance readout, because the mean was the number that lied (tb51)

**`PerfStats` (logic) and `PerfPanel` (view), to the supervisor's own specification.** The reason is
taskblock-51's own record: one session read **min 7.5, avg 140.1**, and four framerate defects were
found in that block without the mean ever pointing at one of them. Uncapped, this game tops out the
monitor, so a session mixing 8 fps stalls with 160 fps idling reports a healthy average and feels
terrible.

**Five figures:** instant; rolling (a true rate — frames ÷ seconds over 2 s, republished on that
cadence, never a mean of rates); the single worst frame; **1% low** as the mean of the slowest 1% of
frames, which is the hardware-review reading the supervisor confirmed; and **the average with the
fastest 1% of *speeds* removed** — the cut sits at **0.99 × the fastest frame seen**, chosen by the
supervisor over a proportion-of-range reading because the two diverge on narrow spreads. That last
figure reports **what fraction of frames survived the cut**, because a number computed after
discarding data should say how much it discarded.

**Arithmetic correction, recorded because it strengthens the case:** the supervisor's worked example
said the plain mean would read "~40fps" — it is **59.9**. The figure they asked for reads **10**, so
the mean overstates by 6×, not 4×. Both numbers are pinned in the test.

**A bug the tests caught while building it:** 120 frames of `1.0/60.0` sum to 1.999999…, so a bare
`>= 2.0` window check never fired and six seconds reported two ticks instead of three. Fixed with an
epsilon, and the remainder now carries rather than being discarded so the cadence cannot drift.

**"UI Element Control" is a list entry, and the toggles live under it** (supervisor). The readout's
switch does not escape the two-column layout — it belongs to a *category*, so the category gets a row in
the verb list and its checkboxes fill the same right-hand pane every verb uses. `DebugUiElements` is the
table behind it: **a new toggleable element is a row there, not UI code**, the same shape `DebugVerbs`
already had one layer down. Ids are open `StringName`s; the table names elements and the overlays own
the nodes, so the panel never learns what a performance readout is. One `ui_element_toggled(element,
shown)` signal replaced `perf_panel_toggled` — a signal per element would have re-created the coupling.
The entry sits **after** every verb, so `_on_apply_pressed`'s existing index guard already declines it,
and Apply is additionally **disabled** while it is selected rather than pressable-and-inert. Switch
state is held on the panel, not in the checkbox: the pane is rebuilt on every verb switch, so a box
holding its own state would forget while the readout stayed on screen.

**Superseded twice before landing — both attempts are recorded below because each was a different
mistake.**

**The toggle was in the wrong column, and captioned every verb.** It was first added beside the
active-target label, inside the pane that shows the *selected verb's* controls — so a panel-scope
checkbox read as the heading of every entry in the list, and the supervisor saw "Performance Monitor"
captioning `Make Current`. It now sits in the panel's own chrome above the verb split. The regression
test asserts **parentage**, because the checkbox was labelled correctly and emitted correctly while
broken; no test of its behaviour could see it. Verified by re-breaking the layout and watching the test
fail.

**Two placement bugs, and the second one passed a test.** Anchoring right and setting `position` put the
panel at x = -16 — hard against the left edge with only its right sliver showing. Replacing that with a
lone `offset_right` left `offset_left` at the anchor, so it resolved to the **full 1904-pixel screen
width at x = 0** — and an assertion checking "left edge on screen, right edge on screen" was satisfied
by a panel covering the whole display. All four anchors and offsets are pinned now, and the layout test
asserts **the width**, which is the property both broken versions actually violated. The toggle is
labelled **"Performance Monitor"** rather than "Perf readout", which named the implementation instead of
the thing.

**The panel is offered by the debug panel and outlives it.** Toggled from inside `DebugControlPanel`,
owned by the overlay — closing the debug panel does not take the readout down, which is what was asked
for. Present in both player and spectator views, since it is tied to debug rather than to a mode. It
samples every frame and **redraws only on the rolling tick**; a profiler that costs frames measures its
own overhead. An opt-in checkbox dumps the figures to the combat log on that same cadence, emitted by
the panel and *written by the overlay*, so no view reaches into a `CombatState` to log.

**The aim-session dump now reads `PerfStats` rather than its own min/frames/seconds.** That second
implementation is how the log came to report 161 fps for a session the supervisor experienced as 8 —
one measurement now, and the session dump gained the 1% low and the trimmed average, since a bare min
and mean were exactly the pair that hid four defects. **The single worst frame was kept** alongside the
1% low rather than replaced by it: the supervisor has been reading a session minimum all block and it
is the figure that matched what they were feeling.

### The aim view's framerate: four defects, one symptom (tb51)

**113 504 usec per mouse motion → 8 878.** 8.8 fps to 113, measured through a real `SquadControlOverlay`
on a 214-blocker board. `BR26.02` is **paused, not closed**, by supervisor decision.

**What it actually was, in the order found — each fix revealed the next:**

1. **`TacticsController.aim_state()` rebuilt the shot plane and cloned the state on every call**
   (35 258 usec), and was called twice per motion plus once per aim-view redraw. Memoised on the
   plane's real dependencies and **deliberately not on `reticle_offset`**, which is the one value that
   changes constantly and cannot affect the plane.
2. **The memo's own cache key cloned the state**, by asking `previewed_unit()` for the previewed cell.
   `CombatState.dup()` measures **26 083 usec** — `Grid.dup` deep-copies 214 blocker parts and 768
   surfaces. Replaced with `ActionQueue.revision`, a counter bumped on every queue change.
3. **`update_aim_hover` still emitted `aim_changed`.** The signal split into `aim_changed` (state) and
   `reticle_changed` (cheap) had converted three emit sites and missed the one that runs on every
   motion — and which `aim_reticle_at_screen` calls internally, so both paths still reached
   `SquadControlOverlay._on_selection_changed`, which previews twice.
4. **The reticle ran per motion *event*, not per frame.** A 500–1000 Hz mouse against a 60–160 fps game
   backed the queue up so the reticle drew stale positions — *"the dartboard almost seems to lazily
   follow the cursor"*. Coalesced to the newest position, applied once in `_process`.

**Two caches were tried and reverted, and the reasons are in the code:** an empty-queue fast path
(callers mutate the previewed unit, so handing back the live one corrupted the board — three step-out
tests), and a per-frame preview memo (state changes *within* a frame when a resolution spends AP — four
action-bar tests).

**`CombatState.dups` is now a profiled work counter**, because a 26 ms call reached several times per
mouse motion was invisible to every budget. The suite reports ~7 155 clones a run.

**Instrumentation was wrong for three passes, and that is the lesson worth keeping.** `fps_dump` took a
single `Engine.get_frames_per_second()` reading two seconds after entering aim — while the mouse was
still — and reported 161 fps for a session the supervisor experienced as 8. **Their report was correct
throughout and was the evidence the instrument was broken.** It now samples every frame and reports
min, average and frame count on leaving aim.

**Side effect, measured: `BR27.09` improved** — turn-start FPS 38.0 → 91–147. Not closed.

**Also landed:** `set_part_hp` takes an object target so it can reach blockers and field objects
(`BR51.02`); `kill_unit` advances the turn when it kills the current unit (`BR51.04`/`BR51.05`, closed
by the owner); a `CHOICE` param type so a debug verb can carry its own dropdown options as data; and
per-element `set_aim_visual` switches that let the supervisor bisect a GPU cost CC cannot measure —
which cleared every aim visual and the wall cutout as suspects.

### The suite under five minutes: seeds_to_first_win, two corpora, failure-first ordering (tb50)

**Full gate 446.8 s → 290.4 s (35%), 2462 tests.** The five-minute acceptance is met, and thinly:
three clean runs measured 288.4 / 288.8 / 290.4 s, while a run sharing the machine measured 313.5 s.
**~290 s on an idle machine** is the defensible number.

**Pass E2 — a shared map corpus, and it is what closed the gap.** `test_map_gen.gd` and
`test_map_gen_raised_rooms.gd` ran **14 independent seed sweeps** regenerating ~650 maps to ask 14
questions about 50. Every sweep was checked first — **none mutates its grid** — so `MapCorpus.read()`
returns the cached `Grid` with no copy at all, and `copy()` is there for anyone who needs to mutate.
**22.7 s → 11.2 s** and **16.2 s → 5.6 s**, more again across the full gate since both want the same
maps.

**The corpus sets a trap, and it caught its own author.** Two tests compare *two independent
generations of one seed*; through `read()` they receive the same object twice and pass
unconditionally — silently deleting the suite's only check that generation is reproducible. The bulk
conversion did exactly that and was caught by reading the diff. Those two sites keep calling
`MapGen.generate`, and a test now pins that `read()` returns identity.

**Pass E1 — failure-first ordering, and nothing is ever skipped.** `SuiteOrder` ranks scripts by how
often and how recently they have failed; the runner enumerates the scripts itself and hands GUT an
ordered list. **It is a permutation, asserted as one** — the pass forbids skipping, because an
indicator that passes while the thing it indicates is broken makes the suite greener than the code,
which this project has hit four blocks running. The order is printed each run so a failure can be
replayed exactly. History lives in `out/suite_failures.json`, **gitignored**: it must update on
ordinary runs to learn anything, and committing it would churn every diff and make one machine's
flakes everyone else's run order.

**Pass F — a baseline beside each failure, a chime, and a triaged ledger.**
`ReplayCatalog.handles_with_baselines` queues each failure with its script's own known-good fixture,
opted in through the existing `replay_handle_for` hook via a `BASELINE_TEST` sentinel — so nothing
changes for the ~250 scripts exposing no handles. Not the default, and the cap counts *failures* so
context never costs coverage. The finish chime is two synthesised tones, rising for green and falling
for red, guarded so no audio device can fail a run. **The ledger triage went in the block's report,
not `docs/BUGS.md`** — that file's header argues against derived indexes and category sections, and
31 headings were diffed before and after to prove no status moved.

**Passes E3/E4 — the eight name defects renamed, and the seed-list trim found already done.** Eleven
renames rather than eight: the `pass_b_` prefix cited an anonymous taskblock pass on four names in one
file. `test_the_flank_test` became
`test_a_shot_from_behind_reaches_the_thin_rear_plate_a_frontal_shot_cannot`;
`test_the_unbuilt_tier_table_rows_are_still_unbuilt`, which reads the utility *action pool* and never
touches the tier table, became `test_the_four_utility_actions_with_no_executor_are_still_unauthored`.
The audit CSV's keys moved with them, so the classification survived. **`description` is now empty
across all 2441 rows** — the defect list is closed. E4 needed nothing: Pass D had already taken
`test_full_mission` from eight bouts to one, so there was no fixed seed list left to trim.

**Pass A — `HULK_` retired from tooling identifiers.** `HB_FAST_GATE`, `HB_TEST_ROOT`,
`HB_FORCE_TEST_FAILURE`. `LootTable.HULK_SOURCE` keeps the prefix and is allow-listed by name — loot
sourced from the hulk is the word meaning what it means. The guard bans the **screaming-case prefix**,
not the word: `Hulk`, `HulkTheme`, `hulk_seed` are the domain vocabulary and a case-insensitive sweep
would have flagged hundreds of correct uses. It scans `.sh` as well as `.gd`, because the retired names
were environment variables and `run_tests.sh` is where they were read.

**Pass D — `seeds_to_first_win` replaces the completion rate**, and this is the change that mattered.
`CompletionSampler.seeds_to_first_win` plays seeds until one completes, capped at `FIRST_WIN_CAP = 9`,
drawing lazily so a healthy run never generates the maps it did not need. **`test_full_mission.gd` went
15.2 s → 1.5 s, 8 bouts → 1.** Cost now scales *inversely* with health: a regressing AI makes the
measurement more expensive, which is the right shape.

The cap is derived, not picked: at the measured 0.72 rate, nine straight losses is 0.28⁹ ≈ one run in
180 000. It is a **collapse detector by design** — at 0.20 it fails about one run in seven, at 0.10
about one in three, and a mild regression not at all. The reported count is the signal (1 healthy, 4
worth a look, 9 a failure), because a threshold on a small integer count is exactly what put
`MIN_COMPLETION_RATE` a fraction of a seed from red and got it lowered twice. **That constant is left
in place and unused by the test that read it**; retiring it is proposed, not done.

**This closes `BR49.01` as a side effect.** The fixed eight-seed sample made total turns swing 970 /
1305 / 961 across three runs with no code change, flapping the work budget and making every other
saving unmeasurable underneath it. The corpus now plays one bout in the healthy case.

**Pass C — `ScriptedCorpus`, and a measured finding that there is nothing to migrate onto it.** A board
built through `BoutSetup` (real presets, real assembly, a real generated map) with both squads `HUMAN`,
driven by an authored queue through the same `CombatState.resolve_until` the AI's own output uses. It
**provably never plans** — asserted on `AiPlanner.plans`, the counter the profile reports — with a
companion test proving that counter does move when something really plans.

**The migration it was built for does not exist, and the survey says why.** All **137** hand-built test
files reference specific `Vector2i` cells, so none can take a shared generated board without changing
what they assert; and **117 of the 137 are already under 1 s with zero bouts**, so there was no cost
there to recover. `test_work_counters.gd`, the obvious candidate, asserts that a hand-driven turn builds
*no* bout — migrating it would build one and delete the assertion. **The corpus is therefore a fixture
for new tests and for the `test_tb38_flat_bout_guard.gd` pattern, not a saving.** The audit outcome the
pass was hunting — *hand-built is quietly wrong* — went unfound, which is a result rather than a gap.

**Pass B — partial, and its premise was wrong.** The pass expects thirteen bout-building files to move
onto `BoutCorpus` for ~200–250 s. The corpus hands out **outcome records**; those files need **live
boards** — which `BoutCorpus`'s own header has said since taskblock-48 built it: *"a test that needs one
builds its own, which is what the eight other bout-building files already do and why they are not
candidates for this."* Two files moved:

- **`test_completion_sampler.gd` 94 s → 41 s** — not by adopting the corpus, but by making **sample
  size a parameter** on `CompletionSampler.sample`/`draw_seeds` and on the `sample_completion` verb.
  The test drives a verb that samples for itself, and every assertion in it is about the *shape* of the
  report. One seed witnesses that exactly as eight do.
- **`test_watched_run.gd`** — the one genuine corpus adoption. It played a seed headless *and* watched
  to compare them; the headless half is what the corpus already recorded.

**`run_seed`/`run_seeds` take a turn cap.** Bounding the horizon is not the move taskblock-48 refused:
that was seed-shopping for a cheap map, which makes the fixture unrepresentative. Here the seed is
unchanged and the run stops earlier, which is sound for any property true at any horizon.

**Recorded because it shaped the ordering:** adopting the corpus makes a *targeted* run of a corpus
reader slower — `./run_tests.sh test_watched_run.gd` went 18.2 s → 49.3 s, since in isolation that file
becomes the corpus's first toucher. Pass D then shrank the corpus and the regression vanished. Corpus
adoption before Pass D would have degraded the edit loop for every file it touched.

### The suite indexed per test, and classified by the rule each test defends (tb49 Passes A–B)

**Full gate 487.5 s, 2431 tests, 255 files.** The artifact is `test/suite_audit.csv`, one row per test,
produced by the procedure in `docs/TEST-AUDIT.md`. **Nothing was cut** — the block produces evidence;
acting on it is a later block under the cut rule.

**Pass A — per-test granularity.** `run_suite.gd` already snapshotted the work counters at script
boundaries; it now does the same one level down and emits `origin_file,test_name,description,usec,bouts,
turns,candidates,floods,plans,shot_planes,rule_guarded`, sorted by file then declaration order because
the procedure fills the judgement columns file by file. **Where setup lands is stated rather than
assumed:** GUT fires `start_test` *before* `before_each`, so a shared fixture is charged to the test that
triggers it, and `before_all`/script load are charged to nobody. That unattributed remainder was measured
at **8.4 s of 496 s — 1.6%**.

The acceptance the taskblock names — per-test counts summing to the file-level counts — is **arithmetic,
not corroboration**, and the test says so: taskblock-47 made a file's counters the sum of its tests'
precisely because the outer window was corrupted by `before_each` resets. The independent check is the
row count against `func test_` read off disk.

**Pass B — 2431 rows classified, 328 distinct rules (13.5%).** `description` is filled on 8 rows (0.33%),
each a name defect: two cite deleted taskblock documents, one asserts "three scatter rings" as though
ring count were a rule (`docs/00`: **N rings, never 3**), one is drifted outright
(`test_the_unbuilt_tier_table_rows_are_still_unbuilt` reads the *action pool*, not the tier table), and
four are vague. The full list is in the block's report.

**What the classification shows, stated plainly because it is not what the procedure predicted.** The
largest clusters are cross-cutting invariants rather than redundancy — *"a degenerate input yields an
empty result, never an error"* is 89 tests across 60 files and costs **1.1 s in total**. Cost concentrates
in individual rows instead: the four most expensive (**102.3 s**, **62.6 s**, **49.8 s**, **20.0 s**) are
49% of the 476 s attributed to tests. Each has cheap clustermates, and in every case checked **the cheap
peer does not cover the expensive one** — the cheap one guards the rule at unit level, the expensive one
guards it end-to-end through a real bout. That is a coverage ladder, not duplication, so the cut rule
would not license the cuts the procedure expected to find. The lever the data does offer is per-rule:
whether a given rule needs a bout-level rung at all.

**`CsvLine` (`src/logic/`) — one CSV codec for the writer and the reader.** Rules are written as full
sentences, so 711 of them contain a comma; the writer quoted correctly and the reader split on `,`,
shifting every numeric column one place right and reading `bouts` as **8697** against a true **56**. The
alternative considered and rejected was a comma-free label vocabulary — letting the storage format
dictate the classification. A second hand-rolled splitter is the same bug waiting again.

**Two junk counters removed from the profile.** Pass A's per-test rows carry `test` (the name) and
`order` (the declaration index), and file rows are the key-wise sum of their tests' — so both were
summed as though they were work, into every file row and into `totals`, where the run reported
`order: 2,953,665` and `test_smoke.gd` reported `order: 1705`. Nothing gated on them, which is why a
green suite carried them for a whole block. The aggregation now excludes one named `IDENTITY_KEYS` set
rather than three inline key checks that had drifted apart, and `test_suite_budget.gd` asserts the
shape — every key in the profile is a non-negative count and no identity field reaches `totals` — so
the next bookkeeping field added to a row cannot leak the same way.

**Regeneration no longer erases the audit.** Pass A's writer emitted both judgement columns empty every
time, so the next `WRITE_PROFILE=1` run destroyed 2424 hand-filled cells with a green suite either way;
it now merges them forward on `(origin_file, test_name)`. The bug behind it appeared **twice, in two
languages** — `FileAccess.open(path, WRITE)` truncates before the renderer reads the old file back,
exactly as `open(path, "w")` did in the Python helper an hour earlier. The carry-forward is demonstrated
rather than asserted: a full `WRITE_PROFILE=1` gate ran and the file came back 2431/2431 classified.

### Three rungs, a window on the run, and the collapse (tb48 Passes A–D, docs/TOOLING.md)

**Full gate 1493 s → 450 s across taskblocks 47–48**; fast gate ~126 s; a targeted run ~3.7 s.

**Pass A — three rungs, one runner.** `./run_tests.sh <file.gd>` joins `fast` and the full gate; a bare
filename resolves by search, and two files sharing a name prints both and exits 2, because that is a
repo mistake to fix rather than a case to disambiguate. The fixed floor was measured before deciding
what to skip: `gdlint src test` 6.14 s, import 2.32 s, parse guard 0.82 s, GUT startup ~1.2 s. A
targeted run lints only its target and skips the checkpoint parse guard; **the import step stays**,
because it registers a `class_name` and skipping it makes a new script invisible in a way that looks
like a broken test.

`tools/profile_suite.gd` became `tools/run_suite.gd` and is the **only** entry point. There had been two
into one suite and **only one of them failed the build** — `gut_cmdln.gd` passed `-gexit` while the
profiler called `quit(0)` unconditionally after writing its JSON. Artifacts are opt-in via
`WRITE_PROFILE`; counts print on every run, and a targeted run also prints its delta against the
committed profile.

**The turns budget was gating on luck**, found here rather than assumed: three full runs measured 1680,
1578 and 1385 turns — a 19% spread against 15% headroom — and all of it comes from
`test_full_mission.gd`, which seeds from the clock *on purpose*. Its turns are excluded now, in
aggregate and per-file; its bouts stay gated because that count is exactly `SAMPLE_SEEDS`.

**Pass B — a window on the run.** `SuiteRun` launches `run_tests.sh`, tails it live and can kill it;
`SuiteRunPanel` is the surface, mounted under both overlays beside the combat log. The feed is the real
output of the real script: filtering narrows what is *drawn*, never what is stored. Completion is
decided by an exit marker rather than by a process disappearing.

`WatchedRunOverlay` was **deleted** — it had been a fifth `SpectatorOverlay` subclass, and the reasoning
that produced it is the reasoning that produced the hierarchy `PLAN.md` exists to dissolve. It is a
panel now, so the block ended with one fewer subclass.

**Killing had to reach the grandchild.** `run_tests.sh` spawns Godot, and killing the shell left it
running: a full-gate run started by a test left **79 orphaned Godot processes**. Runs go under `setsid`
and the whole process group is signalled — through bash, because `kill` is a builtin and `OS.execute`
fails *silently* when it cannot find a binary, which is how the first fix appeared to work and did
nothing. Separately, `test_suite_run.gd` launched the full gate, which runs `test_suite_run.gd`:
unbounded recursion that reached **107 concurrent Godot processes** before it was obvious.

**Pass B2 — replay failures in the game.** The suite runs as a subprocess, so its maps live in that
process's memory and the launcher could only ever be a terminal in a window. `ReplayHandle` is a seed or
a callable returning `{state, mission}` — exactly what `BattleScene.load_battle` already takes — and
`ReplayCatalog` asks a failed test's script for one via a static `replay_handle_for`. A script without
the method has no visual form and is skipped; **"nothing to show" is the right answer for most of the
suite** rather than a fault. `WatchedRun` was folded onto handles, so a failed map sweep and a failed
completion seed queue in one list with one set of controls.

**And none of it was wired.** `offer_failures`, `bind` and `on_bout_finished` had zero callers in `src/`;
the panels sat holding `run = null`. Every piece was tested and proven to work *when called* and nothing
asserted it got called — `docs/11`'s named failure mode. Two further reasons nothing appeared: the panel
kept whatever bout was already on screen, so a working replay and a dead one looked identical (the board
is purged on launch now); and **`failures()` could not read a single real run**, because GUT colours its
output and every prefix check missed an escape sequence. That went unnoticed because the tests fed it
hand-written lines with no escapes — **input tidier than reality is worse than no test.**

**One shared path caused two more symptoms.** `SuiteRun`'s log name carried a `static` counter, which
restarts at 0 in every process — so the nested `SuiteRun` inside `test_suite_run.gd` truncated the file
the game's panel was tailing. A forced fast gate reported *"PASSED — 20 passing, 0 failing"* (that is
`test_grid.gd`'s count) and appeared to stall on whichever file was on screen when the log rewound. The
pid is in the name now.

**Pass C — a shared bout corpus.** `BoutCorpus` draws one random sample per suite run, plays it once and
hands out deep copies. **The draw stays clock-seeded**, which is the whole constraint: taskblock-46
established that a pinned window measures the pessimistic corner of the seed space, so sharing fixed
seeds would have undone that while the test kept passing. Records only, never live state — a mutated
cached `CombatState` would surface as a failure with no connection to its cause.

`test_completion_sampler.gd` went **24 bouts → 10**: three of its four bout-playing tests run on canned
records, because the shape of a report is a pure function of the records behind it. The end-to-end test
lost its duplicate sample — it had replayed the same eight seeds purely to compare two renderings of one
formatter. `test_full_mission.gd` plays none of its own.

**Pass D — both outliers diagnosed, and the budget grew eyes.** `test_ai_batch_yield.gd` measured 18.4 s
per bout and the guess was that the pacer's frame yields paid for it. **Measured false:** same seed,
tight 18485 ms against paced 19660 ms, 54 turns either way, 344 yields — the pacer is **6%**, about
3.4 ms a yield. The cost is bout *length*, 54 turns against the sampler's ~13. Nothing incidental, so
nothing cut.

`test_spectator_overlay.gd` costs 32.5 s with **zero bouts**, which no budget could see because every
gated counter measured AI work. `HulkTheme.ui_builds` closes that: every overlay's `_build_ui` calls
`HulkTheme.build()` and nothing in `src/logic/` does, so it moves for a view test and stays put for a
headless bout — asserted both ways. It measured **344**, and immediately named the file the pass was
about: `test_spectator_overlay.gd` tops it at 70 builds across 35 tests.

### The suite: measured, budgeted, tiered, watched, cut (tb47 Passes A–E, docs/TOOLING.md)

Tooling debt, raised because taskblock-46 was ~45 minutes of coding and ~2 hours of testing. The suite
had gone ~355 s → ~1370 s across one block and had never been profiled, tiered or audited.

**Pass A — profiled, changed nothing.** `tools/profile_suite.gd` drives `GutRunner` directly and
snapshots deterministic work counters at each script and test boundary, writing a committed
`test/SUITE-PROFILE.md` (for reading) and `test/suite_profile.json` (for the budget). New counters where
nothing was counting: `Pathfinder.floods`, `CombatState.turns_resolved` and `CombatState.bouts_built`.
**Turns are counted at `advance_turn`, not in `BoutRunner`** — a turn is a turn whether a runner drove
it or a test did, and a runner-side counter would have reported Pass E's scripted rewrites as free.

The findings contradicted the framing twice: **11 of 242 files build a bout, not 23**, and
`test_full_mission.gd` was not the expensive one — `test_completion_sampler.gd` was, at 730 s and 88
bouts, three times the integration test. Its own header, written the previous block, called it
"deliberately cheap … at most a handful of bouts, and most run none at all". Four tests were 995 s of
1493 s; the worst spent **252 s and 20 full missions asserting that a unit had not moved.**

**Pass B — budgets on counts, not seconds.** Measured justification rather than assertion: two runs of
identical work came out at **1286 s and 1493 s** while the work counts were identical to the integer.
Counts also name the cause — taskblock-46's search-memory fix took turns per bout 19.1 → 26.8, so a
turns budget goes red on the commit that did it where a seconds budget goes red three commits later.
`candidates` and `shot_planes` are reported but deliberately **not** gated: they move with how the
planner scores rather than with how much the suite asks of it, and an AI change failing a suite-cost
test is the false positive that gets budgets deleted.

**Pass C — two gates.** `./run_tests.sh fast` (119 s) skips the bout-building files; `./run_tests.sh`
(537 s) is everything and remains the rule before a pass commits. **The tier is a file list, not a
directory**: ten of eleven bout files live outside `test/integration/`, so a directory rule would have
declared the fast gate bout-free while it played most of the bouts. `SAMPLE_SEEDS` re-derived 20 → 8.

**Pass D — the watched run.** `WatchedRun` sequences a seed list; `WatchedRunOverlay` extends
`SpectatorOverlay` so a watched bout has exactly the controls a normal bout has. **No artifact**: a
seed is already a complete reproduction handle, so bouts are rebuilt rather than replayed.
`CompletionSampler.build_for_seed` was split out so the watched and headless paths cannot build
different bouts from the same seed — asserted, not assumed.

**And that split surfaced the block's most important finding.** `CompletionSampler` was still passing
`&"AGGRESSIVE"` as its profile id, a playstyle taskblock-46 Pass E retired. An unknown id does not
throw — the scorer falls back to unweighted — so **every completion rate measured since that pass ran
with no profile weights at all**: 56/100 unweighted against **72/100** weighted, mean turns 26.8
against 13.5. Against the retired planner's 75% on level ground the gap is **3 points, not 19**, which
re-frames most of `BR45.03`. `MIN_COMPLETION_RATE` deliberately left at 0.35 — out of this block's
scope, and moving a floor the day the number moves is how this project got into trouble with that
constant before.

**Pass E — retarget, merge, cut, in that order.** Turns 2651 → 1578, bouts 79 → 62, gate 930 s → 537 s,
**with the assertion count unchanged** (103192 → 103187 against two fewer test functions), which was
the acceptance: a large drop in assertions would have meant coverage left with the redundancy.

- *Retarget*: `test_frames_pass_during_the_batch` played an entire mission to prove one frame passed —
  and was not even exercising the case `advance_ai_turns` exists for, since an all-AI bout never
  reaches its `wants_turn_for` exit. Squad 0 is HUMAN now.
- *Merge*: the two in-window verb tests each paid for a full sample to make two assertions about one
  invocation. For a bout test the fixture is the cost.
- *Cut*: `test_the_batch_still_runs_to_completion` — 178 s and a 400-turn bout to assert
  `round_number > 0`. **Covering test: `test_a_yielding_batch_produces_the_identical_bout`**,
  demonstrated by sabotaging `advance_ai_turns` to strand its loop and confirming the fingerprint test
  went red on its own. Sabotage reverted before the cut.

### Search verbs get a memory; one-way ground found underneath them (post-tb46, BR46.01/BR46.02)

**`ROAM` and `HUNT` oscillated between two cells for a whole mission, and it shipped.** Both score
`travel_fraction` — go as far as you can — which is memoryless: the farthest reachable cell from A is
B, and the farthest from B is A. A unit with no enemy in sight walked to the edge of its reach and then
shuttled between two tiles until the turn cap. Found in a supervisor's real combat log, where **every
unit on both squads decided `roam` on every turn and covered two or three distinct cells for the entire
bout**; reproduced on an open board as 6 distinct cells in 14 turns with ten of those turns spent
alternating between `(19,23)` and `(31,23)`.

**taskblock-46 Pass C had already written the fix down and applied it to one verb only.**
`SearchRoute`'s own comment says oldest-visit-wins "cannot ping-pong between two while a third is
ignored" — true, and `PATROL` was the only verb with a route to hang that on. `Unit.recent_cells` now
generalises it: a bounded trail (`RECENT_CELLS` = 8, flagged) written for **every** unit every turn,
not only while searching, because a unit that fought across a room and then lost its target must not
treat that room as unexplored. `UtilityContext.INPUT_UNVISITED` grades it by recency rather than as a
binary visited/not — a binary makes every cell outside the trail identical and permits the same
oscillation with a longer period.

`roam` and `hunt` score it unfloored, so ground just left can reach zero; **`putter` scores it floored
(0.5) on purpose**, because puttering is meant to stay local and an unfloored memory would quietly turn
it into a slow roam. After the fix the same probe covers 15 distinct cells in 14 turns. Regression-
tested as ground covered *and* as an explicit A-B-A-B alternation count, since "it moved a lot" and "it
stopped looping" are different claims and only the second is the defect.

**It did not improve completion, and the 20-seed reading that suggested it had was a lucky draw.** The
deterministic 100-seed escalation after the fix returns **56/100 (56.0%)**; a sample run had shown
14/20 (70%). There is no clean before/after at this sample size — the last 100-seed reading was 60% and
predates Pass E, so it measures a different action pool, and comparing the two would be comparing
builds rather than behaviours. **What the fix demonstrably changed is the failure mode:** `TERMINATED`
— bouts that simply never end, the oscillation's own signature — fell **27 → 20**, while `STRANDED`
rose **13 → 24**. Units that cover ground find each other and some of those fights are lost. The fix is
justified by the behaviour being correct, not by the completion rate, and the remaining gap points at
combat quality rather than at another search gate.

**The escalation also got slower**: it now exceeds 900 s where it used to fit, because bouts run longer
when units actually travel. Mean turns to complete went 19.1 → 26.8.

**Chasing the other half of the same report turned up a bigger, separate problem: 16 of 40 generated
maps contain ground a unit can walk into and never leave** (`BR46.02`, open). Descent is free; climbing
reads a `CLIMBER` part tag that **no part in the repo carries**, so every lowered region is a one-way
door for every unit that exists. Worst seed has 216 such cells.

**A symmetric connectivity check cannot see this, which is why it was never caught** — spawn zones are
mutually reachable on 60 of 60 seeds, so the maps read as fine. The defect only appears under
*asymmetric* reachability: flood out from a spawn, then flood back from each cell reached and ask
whether the spawn is still in the set. Deliberately not fixed here: the direction is a design call
between authoring a `CLIMBER` part, constraining `MapGen` to guarantee two-way connectivity, and having
the planner refuse a one-way step. Recorded with the measurement and the options rather than picked.

**BR32.10 had been misattributed twice and is now split.** "The AI is stuck on a concave map" is a
symptom with at least three unrelated causes: no path to a firing cell (the original, fixed in tb46
Pass C), no memory of where it has been (`BR46.01`), and no way back out of where it went
(`BR46.02`). The combat log distinguishes them; the screen does not.

**BR40.03 and BR40.04 closed `Resolved` by the supervisor.** Worth stating what that does *not* cover:
the sweep behind them measured pit *depth*, not *escapability*. No pits, and still somewhere to get
stuck.

### AI v2, part three: the tier table filled, and the playstyle vocabulary retired (tb46 Passes A–F, docs/11)

**Pass A — nothing sinks into a raised room's floor (BR40.03/BR40.04).** One cause, two entries.
`MapGen._repair_stranded_elevation` floods with a real `Pathfinder` and flattens every unreached `OPEN`
cell to level 0, and `Pathfinder._base_cost` returns `-1.0` for any cell carrying a live blocker — so a
cell a scattered crate had just landed on was **unreachable by construction** and got flattened
regardless of whether anything about it was stranded. For spawn cells the flatten fired and then
`_mark_zone` erased the blocker, leaving a correctly-marked tile a full `LEVEL_HEIGHT` below its own
room; since no part in the repo carries `CLIMBER`, a unit spawned there had exactly one reachable cell
and spent the battle in it. Blocker cells are now deferred out of the flatten and levelled against their
neighbours afterwards.

**The fix was wrong once first, and the miss is the useful part:** the deferred pass checked only
orthogonal neighbours while the flood is 8-way, which left **1 sunk crate out of 9,279** — a single
cell across a 40-seed sweep, invisible to anything but a total count.

**And the tests were vacuous until they were told not to be.** Every assertion in the file is free on a
flat map ("no cell sits in a pit" is trivially true if nothing is ever raised), so a change that quietly
stopped generating elevation would have turned the whole file green while deleting the feature it
guards. `test_the_generator_still_authors_raised_rooms` pins the other side: 30/40 maps still author a
raised room, 3,996 of 22,938 floored cells sit above level 0.

**Pass B — the completion number became re-takeable.** `test_full_mission.gd` sampled seeds 0–11 every
run, which was the *pessimistic* window: 41.7% there against 66.7% on seeds 12–23 on the identical
build, a 25-point spread the test could not see. `CompletionSampler` draws `SAMPLE_SEEDS` random seeds
per run and prints every one, so a run is reproducible after the fact; on a dip it reports the exact
command for the deterministic 100-seed escalation rather than running it automatically.

`SAMPLE_SEEDS` is **sized from the measured escalation cost, not by feel** — at a 0.54 rate against a
0.35 floor, n=10 escalates 1 run in 9 and n=20 escalates 1 in 38 for four seconds more in expectation.
Note the non-monotonicity that makes intuition useless here: n=12 is *worse* than n=10 (0.126 vs 0.114),
because the threshold is an integer count and `ceil(0.35 × 12) = 5` demands 41.7% where
`ceil(0.35 × 10) = 4` demands 40%.

**Pass C — the search verbs, and a bug fixed twice in the same place.** Four behaviours (`ROAM`,
`PATROL`, `HUNT`, `PUTTER`) for a unit with nothing in sight, plus `SearchRoute` for the one verb with
state. Routes are derived lazily from wherever the unit stands, deterministically and without an RNG,
and scheduled by **oldest-visit-wins** — no authored order, no index to advance, so every point gets
visited, it cannot ping-pong between two while a third is ignored, and an unreachable point ages out of
contention on its own with no detect-and-remove step.

`LineOfFire.approach_path`/`closing_path` were deleted here (see `SUPERSEDED.md`); what replaces them is
not a branch at all but path distance from one flood rooted at the target.

**The candidate-cell early-out was wrong for the second time.** `UtilityContext.build` gated computing
candidate cells on having something to move toward, which taskblock-45 Pass D had already found wrong
for the mission actions and this pass found wrong again for the search verbs — for which "nothing in
sight" is the entire trigger. Whatever the list of reasons to move is, it is never complete, and a unit
whose reason is missing from it silently gets a candidate set of one cell. The gate is gone rather than
extended.

**Pass D — `Panic`, the named give-up.** A utility planner can genuinely rate every option at or below
the veto floor, which the branch cascade it replaced could not even express. Panic emits a named event
with a **reason**: `nothing_offered` says the pool has a hole in it for this unit, `all_vetoed` says the
pool covered it and every option scored zero, `budget_aborted` says the clock ran out. Those want
different fixes and used to be the same silent shrug — "the AI just stood there" and "the AI panicked"
look identical from outside.

**It re-broke a guard the retired planner had carried with a comment saying it had been caught live:**
a unit holding its own extraction tile looks identical to a stalled one from the scorer's side, and
panicking it into a shutdown takes a unit that was about to extract cleanly out of the mission.
`EndTurnAction.is_holding_position` is checked first now, and
`test_a_winning_bout_runs_to_a_terminal_state` caught it again — which is the argument for that test
existing rather than for trusting the reasoning.

**Pass E — the tier table, and the playstyle enum retired.**

- **Tier gates.** `shoot` and `take_cover` at Grunt-and-above; `overwatch`, `flank` and `suppress` at
  Trained-and-above. `flank` and `suppress` were the only two tier-table rows whose executors already
  existed — `item`, `call help`, `bait` and `ambush` are **not built**, and `call help` has no mechanism
  at all (a unit cannot influence another unit's plan today). They are `PLAN.md` items, not authoring.
- **Setting a batch objective is Elite-only**, where reading one stays Trained-and-above
  (`WorldView.OBJECTIVE_SETTING_TIERS`). A Trained batch is a real configuration; it just has nobody in
  it who makes the call.
- **`UtilityLookahead` — Elite's depth 2–3 search.** Depth 2 is the enemy's shot from where it stands
  (one visibility field per known enemy, reused across every cell); depth 3 is the enemy moving first
  and then shooting (one field per cell, so it runs over a fixed shortlist of the best-scoring cells).
  It is expressed as **one normalized input** rather than as a minimax beside the scorer, because a
  utility AI has one place to put "this option is worse than it looks" and two ways to decide is the
  no-parallel-systems rule broken. Measured on the reference board: a cell in a wall's shadow predicts
  0.00 threat at depth 2 and 1.00 at depth 3, because the enemy can walk around the wall — cover that
  can be stepped around is not cover, and that is the whole behavioural difference between Elite and
  Trained.
- **The playstyle vocabulary is deleted, bridge and all.** See `SUPERSEDED.md` for what it was; the
  short version is that six names selected between two profiles, five of them landing on the same one.

**Four rows of the table played identically before they were made not to, and both causes were
methodological rather than mechanical.** Elite and Trained had the same action pool, so the comparison —
which read only the pool — declared Elite decorative when its entire difference was in the world-model
and depth columns. And `defensive` withdrew exactly as readily as `cowardly` because it had **no stated
weight** for `seek_extraction`: an absent weight is a neutral opinion, and "defensive" is not neutral
about retreat.

**Two test boards were not the boards their comments described.** Both used `place_floor` plus a
hand-assigned blocker, which is cover that everything can see straight through — sight is blocked by
`Grid.opacity`, which only `GridFixture.place_wall` sets. Fixing that then exposed the opposite error:
a wall drawn *across* the firing lane hid the enemy outright, every combat action fell out of the pool,
and all four profiles returned the single verb they had left. **A board that cannot express a difference
is not evidence that there is none.**

**Completion across the block**, all measured after the fact rather than quoted from a prior pass:
taskblock-45 end 54% → Pass A/B re-baseline 50% (24 seeds) / 54% (100 seeds) → Pass C 60% → Pass D 60%.
The retired branch planner sat at 75% on 24 seeds of fixed ground, so `BR45.03` is narrowed, not closed.

**The one thing this block did NOT establish, stated plainly:** `Unit.intelligence_tier` defaults to
`TRAINED` and **nothing authors it** — not a preset, not a matrix, not a roster entry. Every rate above
is an all-Trained rate, and the Mindless, Grunt and Elite rows, the memory and blackboard gates, and the
entire Elite lookahead are reachable from tests and by hand only. The tier table is built and unshipped;
authoring tiers onto units is `PLAN.md` NEXT item 2.

## Economy

**Inventory & economy** (docs/05) — mass/bulk/RAM; discount once at the worn layer (body-attached
floor 0.8); rigidity (soft collapse, rigid don't); body-carry as inert cargo; 7 resources;
`salvage_yield` on parts. Field objects (scrap_pile, goo_barrel, crate, pillar, forklift w/ POWER
socket, barrel_pallet) — on-board resource/cover, block movement, project into the shot plane.

## Matrices

**Matrices & surrogates** (docs/04) — logic vs intelligence; base/link split; docks into `MATRIX`
socket; surrogates dock like parts (tier DAG); matrices never lost; `Matrix.ai_profile` carries AI
personality (**was `Matrix.playstyle` — renamed by taskblock-46 Pass E, which retired the playstyle
vocabulary; it now names a `UtilityProfile` id**). *Frozen — no more depth.*
