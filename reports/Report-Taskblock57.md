# Taskblock 57 Report — the layout, live; and a handoff mid-block

**Nine passes have landed, each committed on a green full gate: A, B and C1 in a previous session;
C2a, C2b, C3, D1, F, D2 and E in this one. The block is incomplete** — **G (the editor surface) and
H (the manipulation gizmo) are unstarted.** This is a handoff report written for the next session
rather than a closing one.

**The layout is live and the retirements are done.** `ViewModes.player()` uses
`ModeChrome.BATTLE_LAYOUT`, every surface in Pass C's table is where the table puts it, `queue_panel`
/ `stat_panels` / `single_unit` are gone, aim is a mode, and announcements are a second view of the
combat-log stream.

**Passes ran F → D2, not D → F**, and the reason is in the open questions below.

**Rewrite this opening when the block closes.**

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

**Session one (A → C1): 34 minutes for three passes. Session two (C2a → E): 173 minutes for six** —
11 min/pass against 29. The gap is not the passes getting harder in general; it is two of them
getting much harder in particular. **C2a took ~60 minutes** (it switched the chrome and had to chase
four real layout defects out of the suite) and **D2 took ~43** (three failed gates, two of them from
one subtle pre-selection interaction).

**The test count fell once**, at D2: 2992 → 2988. That is a retirement, not a regression — the queue
panel's own file went, and two tests in `test_battle_scene_input.gd` that drove its rows went with
it. Recorded because a falling count is worth being able to explain.

## Decisions made without asking

**Pass C was split three ways, not two.** C1 (a previous session) was the arithmetic; C2a moved the
modules onto it; C2b built the four behaviours; C3 was the Inspect-viewer split the supervisor
assigned its own pass. C2 became C2a/C2b because the approved scope — "the nine placements plus Pass
C's four behaviours" — was the largest single stretch in the block, and two green commits beat one
long uncommitted one. The taskblock splits its own passes (A1/A2, G1/G2), so this follows its grain.

**The action bar is collapsible, reversing a decision made earlier in this same block.** C1 recorded
"the action bar and its four satellites are not collapsible". That was already inconsistent with the
data shipped beside it: `ModuleSlots.SLOT_EDGES` carries `ACTION_ROW: EDGE_BOTTOM`, and
`test_slot_properties.gd` pins "bottom is a side too". Nothing surfaced the contradiction while no
module declared a `preferred_slot()`. The alternative was to carve a named exception into a rule
whose whole value is having none. Taking the consistent reading costs nothing a player notices — the
bar is not collapsed by default — and the satellites stay non-collapsible on their own merits, since
they ride a centred bar and fold with it.

**`ModeChrome.relayout` / `ViewModule.relaid_out` is a small new mechanism, and the taskblock asks to
be told.** The battle layout places absolutely, which is what makes it testable arithmetic; absolute
positions do not follow a resized window, where the anchor-preset chromes did. Going fullscreen would
have stranded every surface at the windowed size. The hook exists rather than each module connecting
to `resized` itself because the regions must move before anything re-derives from them, and two
handlers on one signal would settle that by connection order.

**`ModeChrome._legacy_readout` is a deliberately labelled temporary.** `queue_panel`, `stat_panels`
and `controls_legend` are not in the placement table because Pass D retires or relocates all three.
Switching the chrome without them would have stranded all three at (0,0) on top of each other and on
top of the debug menu. The alternative was two passes of churn on the same files. It is deleted with
them.

**The queueing log entries emit from the player's path only, and the raw `ActionQueue.enqueue` still
does not log.** The AI planner enqueues and discards while it evaluates; the entries exist to confirm
that a *click* registered, and burying that in someone else's deliberation is the failure to avoid.
A test pins the asymmetry so it reads as a decision rather than an oversight.

**The perf monitor is click-through everywhere except its two controls.** The table says
"click-through", and the readout has a dump checkbox and a Reset button. A control you cannot press
is not a control, and the alternative — moving them into the debug menu — is a redesign the block
explicitly excludes.

**Pass F ran before the rest of Pass D**, which is the largest sequencing call in the block and the
supervisor gave me the latitude to make it. `stat_panels_module` owned `AimView`; Pass D retires
`stat_panels`; Pass F needs the aim view to survive. Running D first would have meant deleting the
dartboard and rebuilding it a pass later, or growing a temporary home for it. Running F first turned
a collision into an ordinary move.

**`AimReadoutModule` is a module I added that the taskblock does not mention.** Retiring
`stat_panels` would have taken the aim readout — the READING/RESOLVES text — with it, and the
taskblock's own stop-and-report rule is that a retirement must not silently lose coverage. It names
`queue_panel`'s confirmation role; this is the same shape one module over. The alternative was
letting the text go and reporting it, which is what I did for *"Resolve to Here"* — the difference is
that the readout is the thing you are reading *while aiming*, and the aim mode exists to show it.

**Its placement is invented**, because Pass C's table describes the battle surface and has no row for
a surface only the aim mode has. It anchors along the bottom of the safe rect — the band the aim mode
frees by turning the action bar off — and that is flagged as a starting position, not a decision.

**Announcement priorities are three rows with picked numbers.** 3/5/8 seconds, ordered rather than
tuned, using `HulkTheme`'s existing colour tiers rather than a new palette. Flagged tunable. The
taskblock specifies the *mechanism* (priority drives duration, colour and an unread `sound`) and not
the values.

**Announcements are left-aligned always**, taking the option the taskblock explicitly permits. The
alternative it offers — centred when the inspect panels are closed — would make the module read
Inspect's visibility every frame, and Inspect is not even mounted in the aim mode.

**`ControlOverlay.switch_mode` is a second new mechanism, and the taskblock asks to be told.** Pass F
says "no suspension mechanism", and this is not one: a module leaving the set is genuinely unmounted
and freed. What it is instead is a *diff* — modules in both sets are untouched — and the reason is
that the switch is triggered by the aim, so rebuilding the surface would destroy the aim it was
reacting to.

**Two numbers were picked and are flagged as tunable rather than presented as design**: the budge
floor (eight of the layout's own padding units, so it is derived from something rather than
free-floating) and the perf monitor's background alpha (0.35, against `PerfPanel`'s own 0.82, which
was chosen when the readout had an empty corner rather than the board behind it).

## Tests that failed, then were corrected

**Six worth recording. Five were the tests being right and the code being wrong; one was the
reverse.** All were found by the suite, none by reading.

1. **The action bar's cluster is 1740 px wide, not the 960 the table gives the bar.** Anchored at
   the slot's left edge it ran from x=480 to x=2220 on a 1920 screen, putting End Turn at x=2142 —
   entirely off the display. Caught by a click test that pushes a real click at the button's real
   rect. Nothing about the code looked wrong; the table's number is about the *bar*, and the four
   surfaces published off it are outside it. It centres on the bar's band now.
2. **`context.slot()` falls back to `ui_root`, so "was I placed?" answered *yes* in every mode
   without a battle layout.** Inspect stretched over the entire screen in spectator and editor; the
   debug menu landed at (0,0), on top of the spectator's own top-left cluster. The helper's fallback
   is right for a module looking for somewhere to hang a child and wrong for one asking whether it
   was placed. Asked of `slots` directly now.
3. **`PerfPanel` is a plain `Control`, so its outer rect never took its body's height.** Invisible
   while it hung from the top of the screen; pinned to the bottom-right corner it drew its body from
   y=1080 *downward*, off screen. The outer node tracks the body now.
4. **`set_anchors_preset` preserves the rect measured against a not-yet-laid-out parent**, which put
   the readout at x=-420. All four anchors and all four offsets, explicitly — **the third time that
   exact lesson has been learned in that file's history**, which is recorded in its own comments.
5. **The queue confirmation rode into the RESOLUTION event stream.** `TacticsController` opened its
   `MemorySink` *before* queueing the final action, so `turn_ended` — which `LogPlayback` replays as
   the animated resolution — carried a TACTICS `action_queued` event. The ordering had been
   harmless for as long as queueing was silent.
6. **Two tests were asserting the wrong thing and now assert the right one** — the reverse
   direction. The top-left/debug-menu overlap test compared two `position` fields that were local to
   *different parents* the moment the debug menu became a child of its own slot region, and read
   them as screen coordinates; both rects reported (0,0), overlapping by arithmetic wherever they
   actually were. And the editor-chrome test measured *sameness* with the player mode when the claim
   is *reuse of an existing layout*, so moving the player mode failed it with a report of a seventh
   layout nobody had added.

**Five more from the later passes, and the first is the worst kind.**

7. **`AIM_MODULES` had no aim readout, and the gate did not care.** D2 built `AimReadoutModule`
   specifically so retiring `stat_panels` would not take the READING/RESOLVES text with it — and the
   edit adding it to the aim set silently did not apply. **D2 went green anyway, because the only
   assertion was `aim.modules == ViewModes.AIM_MODULES`**, which is true of any list whatsoever. A
   tautology wearing coverage's clothes. Pass E found it by eye while adding `announcements` to the
   same list. The set is pinned by name now.
8. **A selection nobody was told about.** The collapsed player mode's pre-selection reached straight
   into `selection.select()`. `ActionBar`, the pips and the overlays all refresh on
   `selection_changed`, so a turn began with a unit genuinely selected and an action bar still
   drawing its empty state — clicking a slot armed nothing at all.
9. **The pre-selection stomped deliberate selections.** Unconditionally selecting meant the trailing
   auto-select of an awaited AI batch could land *after* a player's own selection and disarm it. It
   fills an EMPTY selection only now, which is all it was ever for.
10. **`select_and_announce` emitted twice** — `selection_changed.emit()` and then `_refresh_overlay`,
    which emits it too. Every listener refreshed twice for one selection. Caught by a test that
    counted the emissions rather than checking the value.
11. **The announcement feed reported a redraw only on expiry**, so a new announcement did not draw
    until an unrelated one aged out. It would have presented as "announcements are late".

**And one test was deleted rather than repaired, which is worth saying plainly.**
`test_the_real_production_wiring_enters_step_out_on_a_covered_enemy` opened with a board click to
select the shooter. `TacticsController` treats a press on the **already-selected** unit's own body as
the start of a facing drag, so with pre-selection that click no longer selects anything — it is
exactly the click the pass removed the need for. The step went; the test kept everything after it.

**Also worth recording because it is not a test failure at all — the gate could report success on a
run it did not finish.** The suite runs under `-d`, which GUT needs to notice unexpected engine
errors, so a runtime script error raises a Debugger Break; the break **ends the run**,
`run_suite.gd` never reaches `_on_end_run`, never computes an exit code, and the process exits **0**.
Pass C3's first full gate reported `EXIT=0` from a log with no totals in it, having stopped three
quarters of the way through. `run_tests.sh` now checks for the summary line the runner prints last
and fails the build without it — verified against both real logs, and it then caught a second real
case within the hour.

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** No pass in this stretch touched an entry in `docs/BUGS.md`. `BR56.01` remains `Active` and
untouched, per the standing do-not-fix instruction — `PLAN.md` NEXT 3 deletes the subsystem it lives
in.

## Open questions

**G and H are unstarted, and G1 is bigger than it looks.** *"Three action bars, not one with three
contents"* wants a **new shape** for the editor's — labelled buttons rather than squares, and a
*"centred, searchable list of every part placeable on a tile"*. `EditorModule` today is a full
authoring panel of dropdowns in the readout column, not an action bar, so G1 is a new module plus a
new searchable list, not a re-slot. **Splitting G1 from G2 is the obvious move** and follows the
taskblock's own G1/G2 division.

**Pass D's `top_left_controls_module` → the spectator action bar is still undone, and it belongs to
G1.** Pass D lists it, but the spectator action bar is *built* in G1 — so the move had nowhere to go
until that module exists. It is the one line of Pass D not yet landed, and it is not lost, just
sequenced where it can actually happen.

**"Resolve to Here" has logic and no UI.** `BR27.08` put it on a queue-panel row; the panel retired
and took the only affordance with it. `keep_queue_suffix` and `queue_partially_resolved` are
untouched and still tested. Queued in `PLAN.md` with a suggested home (a stop marker on a ghost leg,
which is what `resolve_until` already takes) but **not designed** — that is a supervisor call.

**Nothing emits an announcement yet.** Pass E built the mechanism, the priority table and both
views, and `Announcement.tag` is the way in — but no existing call site tags anything, so the
position is correct and empty in play. **That is deliberate**: choosing which events shout at the
player is a design decision the taskblock does not make, and G2's *"validation warnings... the
significant ones surface as announcements"* is the first real customer. Worth a supervisor pass over
"what should announce" at some point.

**Two rows of Pass C's own table shipped half-met, deliberately.** The debug menu has its placement
and not its "drag-resizable height", because the same taskblock's *Not this block's job* list says
"it gets a placement here and nothing more". And the table gives the menu a quarter of the 16:9 safe
width — 480 px at 1x — while `DebugControlPanel` carries a 520 px minimum, so it overhangs its slot
by 40 px. Both are queued in `PLAN.md`; either number can move in the tuning pass.

**`unit 0 queued action: EndTurnAction(unit=0)` is what a player now reads.** `CombatAction.describe()`
defaults to a debug shape and only `MoveAction` overrides `short_describe()`. This is **not a
regression** — the retired queue panel showed the identical string — but the combat log is
player-facing in a way a debug row was not, and the taskblock's own example reads `action: burst`.
Naming is a design call and `docs/08` forbids the view birthing a string, so it is queued rather than
invented.

**The rolling-five report rotation is still deferred, for the same reason as last time.** CLAUDE.md's
rule deletes `Report-Taskblock52.md` in the same commit that writes this file. It has not been
deleted, because the rule's trigger is a *finished* taskblock and this one is open. The rotation
should happen in the commit that closes taskblock 57.
