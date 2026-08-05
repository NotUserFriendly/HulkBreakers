# Taskblock 57 Report — the layout, and an editor you can actually author in

**Every pass has landed and the block is closed.** The taskblock's eight passes took thirteen
commits: A, B and C1 in session one; C2a, C2b, C3, D1, F, D2 and E in session two; G1, G2 and H in
session three. Each ended on a green full gate and committed. **The closing gate is 3072/3072, 0
failures**, confirmed by a second full run on the closing commit.

Every line of the block's acceptance is met: `safe_rect` and `screen_rect` are real and escaping is a
slot property; the action bar publishes slots and is not special-cased to do so; every surface in
Pass C's table is in its declared place; `queue_panel` and `stat_panels` are gone and queueing is
legible in the log; one emit puts an announcement in both surfaces; aim is a mode; **and a height is
authored by dragging an arrow to 0.3.**

**Two passes ran out of the taskblock's stated order, both for a coupling the spec's ordering does not
show.** F ran before the rest of D (the aim view had to survive the retirement of the module owning
it), and C split three ways rather than two.

## Pass timings

Recorded as each pass's full gate exited 0 and it committed — not when its code was written. Kept in
the gitignored `tb57-pass-times.md` as the block runs; copied here because that file is local and
this one is not.

**Clock time, not just the date.** Several sessions can run in one day, so a date alone says nothing
about how long anything took.

| pass | completed | gate | commit |
|---|---|---|---|
| A — coordinate spaces, UI scale | 2026-08-04 14:18 CDT | 2910/2910 | `335045f` |
| B — action bar publishes slots | 2026-08-04 14:28 CDT | 2917/2917 | `d153579` |
| C1 — placement arithmetic | 2026-08-04 14:52 CDT | 2931/2931 | `dbc52d2` |
| C2a — the placements | 2026-08-04 15:56 CDT | 2944/2944 | `d27698e` |
| C2b — Pass C's behaviours | 2026-08-04 16:15 CDT | 2968/2968 | `fc93aff` |
| C3 — the Inspect viewer splits out | 2026-08-04 16:45 CDT | 2971/2971 | `be6a888` |
| D1 — queueing becomes a log line | 2026-08-04 17:16 CDT | 2982/2982 | `7311b0d` |
| F — aim is a mode | 2026-08-04 17:49 CDT | 2992/2992 | `33c85cc` |
| D2 — the retirements, modes collapse | 2026-08-04 18:32 CDT | 2988/2988 | `0a11845` |
| E — announcements view the log | 2026-08-04 18:49 CDT | 2997/2997 | `d3e3b2b` |
| G1 — three bars, not one with three contents | 2026-08-04 20:19 CDT | 3023/3023 | `c9998e0` |
| G2 — the editor's own surfaces | 2026-08-04 20:50 CDT | 3039/3039 | `1696e97` |
| H — the manipulation gizmo | 2026-08-04 21:12 CDT | 3072/3072 | `8f13255` |

**Thirteen pass commits across the taskblock's eight named passes**, first commit to last within each
session:

| session | span | passes | per pass |
|---|---|---|---|
| one — A → C1 | 34 min | 3 | 11.3 min |
| two — C2a → E | 173 min | 7 | 24.7 min |
| three — G1 → H | 53 min | 3 | 17.7 min |

**A number in the previous version of this report was wrong and is corrected here.** It read *"173
minutes for six — 11 min/pass against 29"*, and session two was **seven** passes, not six: C2a, C2b,
C3, D1, F, D2 and E. The real rate is **24.7 min/pass, not 29**, which softens rather than overturns
the reading it supported — session one really was about twice as fast, and the reason is unchanged
and still measured: **C2a took ~60 minutes and D2 ~43**, and two passes getting much harder in
particular is not passes getting harder in general. Session three's passes were the largest in the
block and came in under session two's average, which is the evidence for that.

**The gate grew from 579.8 s to somewhere around 620–645 s across the session** — 75 tests and four
new modules — and the range is the honest form of that number rather than a hedge. Pass H's gate
reported 645.8 s; a confirming run on the *same* commit reported **621.0 s**, so run-to-run variance
here is about 25 s, which is a third of the 66 s the two single runs would otherwise have implied.
**A single-run delta of 66 s was not a measurement I should have quoted to the second**, and the
usable reading is the weaker one: the growth is of the order of the suite's existing per-test cost,
not evidence that anything new is expensive.

**Four full-suite runs in session three — three pass gates plus the opening baseline — cost about 41
minutes**, against 53 minutes of commit-to-commit span. The gate remains the dominant cost of a pass
and is the entire reason the targeted rung exists.

**The test count fell once**, at D2: 2992 → 2988, when the queue panel's own file went and two tests
that drove its rows went with it. Recorded because a falling count is worth being able to explain.

## Decisions made without asking

**Pass C was split three ways, not two.** C1 was the arithmetic; C2a moved the modules onto it; C2b
built the four behaviours; C3 was the Inspect-viewer split the supervisor assigned its own pass. The
approved scope — "the nine placements plus Pass C's four behaviours" — was the largest single stretch
in the block, and two green commits beat one long uncommitted one.

**The action bar is collapsible, reversing a decision made earlier in this same block.** C1 recorded
"the action bar and its four satellites are not collapsible", which was already inconsistent with the
data shipped beside it: `ModuleSlots.SLOT_EDGES` carries `ACTION_ROW: EDGE_BOTTOM`. The alternative
was carving a named exception into a rule whose whole value is having none.

**`ModeChrome.relayout` / `ViewModule.relaid_out` is a small new mechanism, and the taskblock asks to
be told.** The battle layout places absolutely, which is what makes it testable arithmetic; absolute
positions do not follow a resized window. Going fullscreen would have stranded every surface at the
windowed size.

**`ControlOverlay.switch_mode` is a second new mechanism, and the taskblock asks to be told.** Pass F
says "no suspension mechanism", and this is not one: a module leaving the set is genuinely unmounted
and freed. What it is instead is a *diff* — modules in both sets are untouched — because the switch is
triggered by the aim, so rebuilding the surface would destroy the aim it was reacting to.

**Pass F ran before the rest of Pass D**, which is the largest sequencing call in the block and one
the supervisor gave me latitude to make. `stat_panels_module` owned `AimView`; Pass D retires
`stat_panels`; Pass F needs the aim view to survive. Running D first would have meant deleting the
dartboard and rebuilding it a pass later.

**`AimReadoutModule` is a module I added that the taskblock does not mention.** Retiring `stat_panels`
would have taken the READING/RESOLVES text with it, and the taskblock's own stop-and-report rule is
that a retirement must not silently lose coverage. Its placement is invented, and flagged as a
starting position.

**Announcement priorities are three rows with picked numbers** (3/5/8 seconds, `HulkTheme`'s existing
colour tiers), ordered rather than tuned and flagged tunable. The taskblock specifies the *mechanism*
and not the values.

**Announcements are left-aligned always**, taking the option the taskblock explicitly permits.

**Two numbers were picked and flagged tunable rather than presented as design**: the budge floor
(eight of the layout's own padding units, so it is derived from something) and the perf monitor's
background alpha.

### The G and H stretch

**A shared `BarModule` base, which is a form of inheritance this project has deleted twice.** The
alternative was three unrelated modules each rebuilding the same six containers and publishing the
same four names — which is where they would drift. What forced the *overlay* fork was all-or-nothing
inheritance of **behaviour**; there is no behaviour here to inherit, only the scaffolding, and
`_fill_bar` is the one hook. **The alternative I did not take is a single bar branching on the mode**,
which the taskblock names in the pass title as the failure to avoid.

**A third placement-kind button — `Cover` — that the taskblock does not name.** It asks for *Place
Items* and *Tiles* and says "tiles and claims get their own buttons"; the editor could author
**blockers** before this pass, and shipping two of three kinds would have deleted every wall and
barrel an author can place. Generated from `MapPlacement`'s own kinds with a label table and a derived
fallback, so a fourth kind grows a button rather than needing this decision again.

**`ModuleSlots.TOP_LEFT` was renamed to `PACING_ROW` rather than reused under a lying name.** The
spectator's pacing row is bottom-centre now. Five call sites, and it is the difference between a slot
that says *where* and one that says *what for*. `PACING_ROW` and `TUNABLES` also left `SLOT_EDGES`
entirely: published at two different edges by two different providers, they have no single edge.

**The spectator and editor modes both moved to `BATTLE_LAYOUT`.** For the spectator this is Pass C's
table applied to a battle that happens to be watched. For the editor it is a correction: tb56 F's
"reuses the player mode's layout" was true when the editor named `PLAYER_COLUMNS` and the player mode
did too — Pass C moved the player mode off it, and **reusing an abandoned layout is not the same claim.**
The consequence is that `PLAYER_COLUMNS` and `TOP_LEFT_ROWS` are now named by no shipped mode, which is
queued in `PLAN.md` as a decision to make rather than swept.

**The editor's four dropdowns became four plain fields.** The bar chooses the tool, kind, part and
claim kind now; a dropdown in a panel *and* a button on a bar would be two ways to answer one
question. The cost is that several tests changed from driving widgets to driving the model, which is
what they should have been doing.

**`SuiteRunPanel` moved from the bottom-right corner to the top-left**, which is scope the taskblock
did not ask for. It is a real collision rather than tidying: the panel reaches into the action bar's
own band, and G1 put the spectator's cluster there. The bottom-right is spoken for twice over — the
perf monitor has the corner, the bar's satellites the band above it.

**`ControlOverlay._unhandled_input` became a walk over modules in declaration order.** The alternative
was a second hardcoded module name and a comment explaining which of the two wins. **This changes
input routing for every mode**, which is why it is here: `ViewModule.handle_input` returns false by
default and `BoardInspectModule` returns false always, so nothing but the gizmo can consume anything.

**The gizmo is armed by a tool, and that is the design decision the taskblock's "do not let this
become a second selection system" forced.** The editor has no `SelectionController` — its "existing
selection" is the cell its one click router already resolved — so `apply_tool_at` hands the gizmo a
cell when the `gizmo` tool is active. The alternative was the gizmo picking its own subject off a raw
click, which is precisely the second selection system.

**"The significant ones" was not invented.** The taskblock says significant warnings announce and does
not say which. Rather than picking, this takes a category the code already computes separately —
`EditorController.navigability_warnings()`, the one describing a board a bout cannot be played on.
`ALERT` rather than `CRITICAL`, since the loudest tier is reserved for what ends a mission; flagged
tunable.

**Three placements in G and H are invented and flagged**: the editor's section-details panel in the
Inspect-viewer slot (which is G2's stated home, landed in G1 so the panel was never stranded at
(0,0)), the gizmo readout's band, and the arm lengths and handle sizes.

## Tests that failed, then were corrected

**Sixteen across the block. Five are from the G/H stretch and are listed first; the earlier eleven
follow in brief.** Almost all were the tests being right and the code being wrong; three were the
reverse, and those are the useful ones.

1. **`Gizmo.resized_box` moved the face nobody dragged.** It snapped the extent and the centre
   independently, which looks equivalent to snapping the face and is not: growing a box by an odd
   number of steps moves its centre by half a step, and snapping *that* shifts the whole box.
   Dragging the bottom of a 2.0-tall claim down by 0.5 left its top at **2.05**. Caught by the test
   asserting the anchored face is an invariant — written because "the opposite face stays put" is the
   whole promise of a face handle. It snaps the dragged face and derives the rest now.
2. **`SuiteRunPanel` overlapped the spectator's control cluster.** Not a new bug: a 560 x 331 panel
   anchored bottom-right has always reached into the action bar's band, and nothing showed it while
   the cluster sat in the opposite corner. `test_debug_panel_layout.gd` caught it the same day the
   cluster moved. **This is the class of finding a layout test exists for** — the conflict was two
   passes old and invisible until something moved into the space.
3. **Two spectator tests were reading a coordinate space that had stopped meaning what they assumed
   — the reverse direction.** With the log inside the bar, `position` is measured against a margin
   container whose own origin moves; the resize test reported the bottom edge dropping 100 px while
   the panel was in fact still hard against the bottom of the screen at y=1080. Read off
   `get_global_rect()` now. **The same lesson the block had already recorded once**, one container
   over, which is worth saying plainly.
4. **Two of my own test fixtures were wrong, and both read as product bugs.** The warnings test
   authored a pit with no spawn marker — `navigability_warnings` floods *from* a spawn, so there was
   nothing to report and the empty log read as "warnings never reach the log". And the dedup test
   counted zero because an empty board's warnings are reported by the `refresh()` inside `_mount`,
   before any test can attach a sink; it now introduces a warning it can watch arrive.
5. **`"%s" % an_empty_Array` is an engine error**, because `%` treats an Array as the argument list —
   "not enough arguments for format string", raised on the run that *passes*, which GUT counts as a
   failure. Exactly the shape of the `%v`-on-a-`Rect2` lesson already recorded in
   `test_battle_placements.gd`, one container over. Both now go through `str()`.

**The earlier eleven, in brief.** The action bar's cluster was 1740 px wide against a 960 px bar and
ran End Turn off the display; `context.slot()`'s `ui_root` fallback answered "was I placed?" *yes* in
every mode without a battle layout; `PerfPanel`'s outer rect never took its body's height;
`set_anchors_preset` preserved a rect measured against a not-yet-laid-out parent (**the third time
that exact lesson has been learned in that file**); the queue confirmation rode into the RESOLUTION
event stream; two tests were asserting the wrong thing and now assert the right one; **`AIM_MODULES`
had no aim readout and the gate did not care, because the only assertion was
`aim.modules == AIM_MODULES` — a tautology wearing coverage's clothes**; a pre-selection nobody was
told about left the action bar drawing its empty state over a selected unit; the same pre-selection
stomped deliberate selections; `select_and_announce` emitted twice; and the announcement feed reported
a redraw only on expiry.

**One test was deleted rather than repaired, which is worth saying plainly.**
`test_the_real_production_wiring_enters_step_out_on_a_covered_enemy` opened with a board click to
select the shooter, which pre-selection made both unnecessary and harmful. The step went; the test
kept everything after it.

**And one thing that is not a test failure at all — the gate could report success on a run it did not
finish.** The suite runs under `-d`, so a runtime script error raises a Debugger Break; the break ends
the run, `run_suite.gd` never reaches `_on_end_run`, and the process exits **0**. Pass C3's first full
gate reported `EXIT=0` from a log with no totals in it. `run_tests.sh` now fails the build without the
summary line the runner prints last — **and it fired twice more in session three**, once on a
`void function cannot return a value` parse error mid-conversion and once on an out-of-bounds index
past a failed assertion. Both would otherwise have been green runs that saw three quarters of the
suite.

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** No pass in this block touched an entry in `docs/BUGS.md`. `BR56.01` remains `Active` and
untouched, per the standing do-not-fix instruction — `PLAN.md`'s *Retire ramps* item deletes the
subsystem it lives in.

## Open questions

**The tuning pass is the block's own stated leftover and is now `PLAN.md` NEXT 1.** The taskblock
said it outright: *"the supervisor will fine-tune with CC after the bulk lands... padding, exact sizes
and colour values are the cheap half and they are the half that wants a screen."* Every number is a
named constant in one file each, and three placements are invented rather than specified — the aim
readout, the gizmo readout, and the editor's section-details panel. **The suite pins the structure**,
so a number moving cannot quietly move a surface somewhere else.

**Two chromes are now named by no shipped mode**, and I have deliberately not deleted them.
`PLAYER_COLUMNS` and `TOP_LEFT_ROWS` are still built, still reachable, and still exercised by tests
that mount an invented mode against one — and the slot vocabulary they publish (`LEFT_COLUMN`,
`READOUT_COLUMN`, `TOP_RIGHT`, `BOTTOM_RIGHT`) is likewise named by nothing that mounts. **Either they
are the spare layouts a fifth mode picks up, and `ModeChrome`'s header should say so, or they go with
their slot names.** This project has been bitten by "correct and unreachable" before; the difference
is that a chrome nobody names costs nothing at runtime, and deleting one is a real reduction in what a
future mode can ask for. Queued as a decision, not as a sweep.

**Nothing in a *bout* announces yet, and that half is still open.** G2 gave the mechanism its first
real customer — the editor's navigability warnings tag themselves and reach both surfaces from one
emit — but no call site in a battle tags anything. Choosing which battle events shout at the player is
a design decision the taskblock does not make. G2's warnings are now the worked example of what each
one costs: one `Announcement.tag(data, priority)` at an existing emit, no new path.

**"Resolve to Here" still has logic and no UI.** `BR27.08` put it on a queue-panel row; the panel
retired and took the only affordance with it. `keep_queue_suffix` and `queue_partially_resolved` are
untouched and still tested. Queued with a suggested home (a stop marker on a ghost leg, which is what
`resolve_until` already takes) but **not designed** — that is a supervisor call.

**`unit 0 queued action: EndTurnAction(unit=0)` is still what a player reads.** `CombatAction.describe()`
defaults to a debug shape and only `MoveAction` overrides `short_describe()`. Not a regression — the
retired queue panel showed the identical string — but the combat log is player-facing in a way a debug
row was not, and the taskblock's own example reads `action: burst`. Naming is a design call and
`docs/08` forbids the view birthing a string, so it is queued rather than invented.

**Two rows of Pass C's own table shipped half-met, deliberately.** The debug menu has its placement
and not its drag-resizable height, because the same taskblock's *Not this block's job* list says "it
gets a placement here and nothing more" — and the table gives the menu 480 px at 1x while
`DebugControlPanel` carries a 520 px minimum, so it overhangs by 40. Both queued; either number can
move in the tuning pass.

**The cursor does not show what is being placed, and that is the option not taken rather than a gap.**
G2 offers an either-or by name — a cursor icon *or* the bar's own highlight — and the bar's highlight
shipped, because a cursor icon is a `Control` tracking the mouse over a 3D board with its own z-order
and hit-testing questions. Recorded in `PLAN.md` only so a later reader does not find the sentence,
look for the icon, and mistake a taken option for a missed one.
