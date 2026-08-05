# Taskblock 57 Report — the layout, and an editor you can actually author in

**The block is closed, and five supervisor review passes plus a short reserve list have been worked
since.** This report covers both, in that order: the block first, then everything after it.

**The taskblock's eight passes took thirteen commits** — A, B and C1 in session one; C2a, C2b, C3,
D1, F, D2 and E in session two; G1, G2 and H in session three. Each ended on a green full gate and
committed, and the closing gate was 3072/3072 with 0 failures.

**The five review passes came after the block closed** and are *not* taskblock passes: the
supervisor ran the game, wrote what they saw, and each pass worked that list. They ran on targeted
gates at the supervisor's explicit instruction — *"I don't need a 20 minute test suite being run a
dozen times for a UI tuning pass"* — with a full gate at the checkpoint after pass 3 (3117/3117) and
another at the end of pass 5 (3131/3131).

**Two of the three reserve items landed; the third was handed back.** Both open reports are in
`docs/BUGS.md` as `BR57.02` and `BR57.03` rather than described only here, because a report is spent
after one reading and a defect that is still open needs a durable home.

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

---

# After the block — five UI review passes

**Not taskblock passes.** The supervisor ran the game and wrote up what they saw; each pass worked
that list. There is no spec behind any of it, so every item below names what was reported.

**Run on targeted gates by instruction**, with one full gate at the end — *"only check tests you
create in the process of making these changes... We'll run one full suite at the end of my UI
passes."* That trade is examined honestly under *Tests that failed* below, because it cost something.

| pass | committed | what it covered |
|---|---|---|
| 1 | 2026-08-05 06:20 CDT | the bar is the centred item; square abbreviated buttons; four defects |
| 2 | 2026-08-05 07:40 CDT | one button feel; tile filtering; six defects |
| 3 | 2026-08-05 08:53 CDT | one control per thing; framed panels; the spectator contract |
| 4 | 2026-08-05 10:31 CDT | one control per surface; borders that read the surface; the overlap check |
| 5 | 2026-08-05 11:44 CDT | the test suite becomes a window; keybinds everywhere; the dark preview |

**The checkpoint gate after pass 3 was 3117/3117, 0 failures, 714.7 s** — against 3072 at the
block's close. **714.7 s against the 620–645 s range measured then**: the growth is real, but the
run-to-run variance recorded above (~25 s) is a third of it, so it is one more point in a range
rather than a step change.

## Decisions made without asking

**The bar's rows are anchored `Control`s rather than containers.** My first fix for *"the action bar
needs to be the centered item"* used two equally-expanding wings, which **looks** correct and is
not: an `HBoxContainer` distributes only the *leftover* width evenly, on top of each child's own
minimum, so a 520 px combat log still pushed the bar 48 px right of centre. Measured at 1008 against
a screen centre of 960. Anchoring each piece against `BattleLayout`'s own band has no dependency on
what is in the satellites. **The failed attempt is recorded in `SUPERSEDED.md` deliberately** —
it is the kind of wrong answer that looks right in review.

**`ActionBar.BOX_SIZE` no longer sizes the player's bar.** tb08 E1 set it to 108 ("3x its current
size"); ten of those over two rows is 216 against a bar the placement table now gives 135. **A bar
that is a fixed fraction of the screen cannot also be sized by its boxes**, so `box_side()` derives
the square from the band and `BOX_SIZE` survives as the default and the stand-alone answer. That
demotes a number an earlier taskblock chose, which is worth saying out loud.

**`UiButton` is a shared class, and abbreviations are derived rather than tabled.** Three modules put
controls in that row and each built its own shape, which is what the review saw. Deriving the label
from the module id means a module added later gets one with no edit — at the cost of collisions,
which is what the hover description is for. **The collision was predicted in that file's own header
and then happened**: `inspect` and Inspect's own button both read `INS`.

**Tile filtering was reported rather than invented.** The supervisor asked to be told if it needed a
tag system, and it does — for two of the three kinds. A *surface* is answerable from data today (a
tile attaches to `GROUND`, which is the rule `GridPlacement.can_place` enforces, not a convention),
so that filter is in. **Blockers and field items are not**: `parts_pool()` is every `Part`, arms and
heads included, and nothing says which belong on a board. That is a content decision.

**A wall placed on bare ground brings the *last floor used*, not a named default.** Reaching for a
specific part id would have been inventing content; the author's most recent floor is the one they
are building with.

**The editor's warnings label was deleted rather than restyled.** The supervisor asked what the
orange text was; it was the editor's own warnings list, duplicating what G2 had just moved into the
combat log. Two records of one thing.

**`top_left_controls` and `TopLeftControls` are deleted, which is more than was asked.** The review
retired the three controls individually; with all three gone the cluster held nothing. Deleting the
container and its class is the conclusion, but it is a deletion nobody explicitly requested.

**`ControlToggleModule` is a new module the review did not ask for**, and the reason is in the
defects below: folding Watch into `TurnControlsModule` broke the spectator's contract, and the fix
could not be a flag because `kind()` must be answerable unmounted.

**`ReplayModule.is_collapsible()` is overridden rather than derived.** The collapse rule reads the
slot's edge, and those panels anchor themselves. Overriding says "toggleable for a reason the slot
cannot express" — the alternative was inventing a slot so the derivation came out right.

**The combat log's width is derived from the layout rather than re-picked.** `DEFAULT_WIDTH` is 520
and predates the bar being centred; the space beside the bar is `(safe - band) / 2`, so the panel
takes whatever that leaves. A second number to keep in step with the first is a second number to get
wrong.

**Three tests were deleted rather than repaired**, each because its subject no longer exists: the
top-left/debug-menu overlap (no cluster), the shared-cluster construction claim (same), and a
source-reading gate check on a deleted file — that last one's *guarantee* moved to
`DebugPanelModule` and is asserted there, so the check moved rather than being dropped.

**`verbose` is left wired and unread**, on the supervisor's *"leave it open for later"*. It is the
same shape as `Announcement`'s `sound` field, and the same risk: a field nobody reads is one somebody
later assumes is wired.

**The two plan items were ordered by me.** The live message asked for the terrain rename "next up";
`temp.md` asked for the gizmo rework "at the top of plan". Both said top. The rename is NEXT 1 on the
grounds that the chat instruction was the more recent and more specific one, and the gizmo rework is
NEXT 2 — **say so if that is the wrong way round.**

## Tests that failed, then were corrected

**Five, and the first two are the ones worth reading.**

1. **`SearchableList` was not filtering at all, and the test covering it passed.** `queue_free` is
   deferred to the end of the frame, so the old rows were still children — and still drawn — while
   the filtered ones were appended after them: typing `barrel` into a four-entry list left **five**
   rows on screen. **The test read `shown_ids()`, which reports the module's own `rows` array — and
   that array was correct throughout.** Nothing asked the container what it was actually showing.
   This is the project's own "read the real node back" rule, failed by me, in a test I wrote two
   sessions earlier. The replacement asserts against `results.get_children()`.
2. **Folding Assume Control into `TurnControlsModule` broke the spectator's central contract**, and
   the suite said so instantly — eight tests red at once, bouts advancing two turns per step, clicks
   landing on a board that had moved. `ViewMode.has_unit_input()` builds each declared module
   **unmounted** and asks `kind()`, so an INPUT module in a display-only mode makes that mode claim
   it can mutate state. **The test that caught it was not a new one**; it was the spectator's own
   pacing tests, which is what a contract test is for.
3. **`Array[StringName].sort()` is not alphabetical.** It orders by the engine's internal
   `StringName` ordering — measured as `ramp, metal_scraps, twisted_sheet_metal, head, battery, ...`
   where alphabetical starts `ammo_rack, arc_welder, arm`. That was the supervisor's *"looks like
   'add' order... looks random"*, and it is a real defect rather than a preference.
4. **The final full gate truncated, and the completion guard caught it.** `test_battle_scene.gd`
   asserted every child of the turn-control column is a `Button`, and `ControlToggleModule` inserts
   a gap spacer there. **I had run that file — before the change that broke it.** See below.
5. **Two spectator tests were reading a coordinate space that had stopped meaning what they
   assumed**, reporting the log's bottom edge falling 100 px while it was still hard against the
   bottom of the screen. Read off `get_global_rect()` now. The same lesson the block had already
   recorded once.

**The targeted-gate trade, stated plainly.** Running only the files I touched was the instruction and
it was the right call for the pace — but it cannot see that a change broke a file tested *earlier in
the same pass*, which is exactly what happened at item 4. **One truncated run at the checkpoint is a
cheap price** against a dozen eleven-minute gates, and the guard turning a silent green into a loud
red is what made it cheap. Worth knowing the shape of the cost rather than assuming there was none.

**Several fixture and formatting errors of my own** are not counted above but were real time:
`"%s" % an_empty_Array` raises an engine error (`%` treats an Array as the argument list), a warnings
test authored a pit with no spawn marker to flood from, and a scripted comment rewrap mangled two
markdown tables in file headers.

## `SUPERVISOR`-owned entries moved to `Pending`

**`BR57.01` — units stand at their previous bout's cells in editor mode.** Root-caused and fixed:
`BoardSwap.swap_board` **returns** the ids of units it could place nowhere, and `EditorModule` was
discarding that value, so on a board with no floor yet every unit kept its cell from the last bout
and was still rendered there.

**To see it work:** open the editor with a bout on screen (`E`). Before, the previous bout's units
stood on the empty grid; now the board is empty until you author floor and spawn markers, and they
return when *Run Test Bout* seats them.

## Open questions

**The tag system for the part list is yours to call**, and it is the one thing the review asked to be
told about rather than worked around. Tiles filter today; blockers and field items cannot be
separated from body parts without a tag on the part.

**The terrain rename is NEXT 1 and wants its own full gate** — 524 hits across 49 files, including
authored `.tres` maps that carry part ids as data. It was deliberately not done inside a review pass
for that reason.

**The gizmo rework is NEXT 2** and is a rebuild rather than an adjustment, on the supervisor's call.
`GizmoDrag` and the ray-vs-box handle picking survive it; the arming and tool routing do not.

**Two chromes are still named by no shipped mode** (`PLAYER_COLUMNS`, `TOP_LEFT_ROWS`), along with
the slot vocabulary they publish. Unchanged from the block's own close: either they are the spare
layouts a fifth mode picks up, and `ModeChrome`'s header should say so, or they go.

**Nothing in a *bout* announces yet.** The editor's navigability warnings are the mechanism's first
real customer; no call site in a battle tags anything, and which events should shout at the player is
a design decision.

## Passes 4 and 5 — decisions made without asking

**A general overlap check exists now, and its exception list is the design.** The review chat's note
asked for one; what it does not settle is which overlaps are legal. Eight pairs are declared, each
with the reason, and **an exception is a pair rather than a surface** — a module excused for sitting
under the click-through announcement band is not thereby excused for landing on the combat log. That
shape is mine, and it is the difference between a check and a mute button.

**Identical nodes are skipped rather than declared.** The check's first run flagged `control_toggle`
against `turn_controls`, which share one column. Excusing that as a *pair* would have hidden a real
collision between them if they ever stopped sharing.

**`is_showing()` is a new hook on `ViewModule`.** The review asked for the highlight to follow the
window rather than the press, and doing that per-button would have meant each owner remembering to
refresh on every route in. A hook the cluster reads per frame is one place.

**`provides_own_button()` now covers `inspect_viewer`, whose control is another module's.** The hook
was written for "I build my own"; the viewer builds none and is governed by Inspect's. That widens
the hook's meaning to "the cluster must not build one for me", which is what it always did.

**`SuiteRunPanel` was given `BattleLayout.inspect_rect` rather than a row of its own in the table.**
It has now moved three times in four passes — bottom-right, top-left, Inspect's rect — and the
reason is that it has never had a declared placement. Reusing Inspect's is the smallest honest fix
and it is still not a table row. **If the placement table should grow a row for it, say so.**

**The `[?]` on that box is a plain `Button`, not a `UiButton`.** The square-abbreviation shape
belongs to the UI-buttons cluster; this is window chrome sized to a title bar beside `[x]`. Two
buttons that look alike in different contexts would be the same mistake the cluster's own review
found, inverted.

**`WorldPalette.environment()` grew a parameter.** The preview needed more ambient than the board
and the per-camera override is the only place that cannot leak — but that makes the default
load-bearing, so a test pins that the no-argument call still returns the board's value.

## Passes 4 and 5 — tests that failed, then were corrected

**Four, and none of them was a product bug — every one was a test still asserting a decision the
review had reversed.** That is worth saying plainly, because it is a different failure mode from the
earlier passes and a healthier one.

1. **The border test pressed a button and asserted the border immediately.** With borders re-read
   per frame rather than set by the press, it had to let a tick happen — which is the change working,
   not a regression.
2. **The viewer-frame test asserted a border stroke** the review had asked to be removed in favour
   of oversizing the panel. It asserts the padding and the fill now, and that the stroke is gone.
3. **The run panel's "pinned width" was its own constant**, and the box is placed by the layout now.
   The claim — a long feed line must not widen it — is unchanged.
4. **Two tests pinned `SHRINK_END` on the turn buttons**, which is the opposite of the left-align
   that was asked for.

**And one deferral rather than a failure**, because it is the honest shape of the trade: the test
suite's *"hover a line"* preview is **not done**. The combat log's is built on `RichTextLabel` line
offsets and the suite feed is a plain `Label`, so it is an extraction plus a widget change rather
than a reuse — and dropping that into the last pass unrun was worse than saying so.

## Passes 4 and 5 — open questions

**The editor inherits a world it did not build, and that is now three defects rather than one.**
Units at their previous cells (`BR57.01`), movement tiles, and extraction markers — each found by
eye, each fixed on its own terms, none of them touching the cause. `EditorModule`'s header carries
the table. **Expect a fourth.** The real fix is `PLAN.md`'s *Main menu*: an entry point that builds
a world with no bout in it.

**The test suite's hover-line preview** is the one review item left undone, and it wants the combat
log's overflow preview extracted into a shared class first.

**`SuiteRunPanel` still has no row in the placement table** — see above.

## The reserve items — decisions, and one thing said plainly

**The performance readout's state is a `static var`, which is session-scoped global state and worth
flagging as such.** The alternative was threading it through `ModuleContext`, which would make one
debug readout's visibility a property of the world every module sees. The state genuinely belongs to
the session — it is the same readout over the same `PerfStats` whichever surface is mounted — and a
static is the honest expression of that. **It does mean the value persists across tests inside a
run, and that is not hypothetical**: the full gate went red on it. `test_perf_panel.gd` turns the
readout on through the real debug-menu path, so the test asserting "it starts off" started with it
already on — and passed in isolation, which is exactly how a targeted rung hides session state. The
test sets the state it needs now instead of assuming it. **This is the second time in these passes
that the full gate caught something a targeted run could not**, and both times it was state or
ordering rather than logic.

**The combat log's offset cache invalidates on line count rather than on an explicit call.** A cache
with a manual invalidate would have been faster to write and is the wrong trade here: a caller that
forgot to invalidate produces a hover preview pointing at the *wrong line*, which is far harder to
notice than a slow pan. The line count is the property that actually changes when the text does.

**The FPS report is not claimed as fixed, and that is deliberate.** A real per-motion cost was found
and removed — the supervisor's hunch pointed straight at it — but *"removed obviously wasted work"*
and *"fixed the framerate"* are different claims, and only one of them is supported. CC cannot see a
framerate. `BR57.03` stays `Active` with the next suspect named.

**The inspect-viewer fix in pass 5 was symptomatic, and the changelog entry that presented it as an
answer was wrong.** The follow-up observation — *every face identically shaded* — rules ambient out:
that is what ambient-only looks like, so the directional light contributes nothing rather than
contributing badly. The ambient raise is kept on its own merits and `BR57.02` carries the four
suspects already eliminated, so the next session does not repeat them. **The asymmetry is the clue**:
it reproduces only on units, and a live unit is the one subject that takes the isolate-camera path
instead of the fresh-copy one.

**Where this session stopped, and why.** The third reserve item is the one place the context ran
out: the obvious causes were checked and cleared, and continuing would have meant guessing at a
render path with no room left to trace it properly. Shipping a second symptomatic fix on the same
bug would have been worse than handing it back.
