# Taskblock 57 Report — the layout, live; and a handoff mid-block

**Passes A, B, C1 (a previous session) and C2a, C2b, C3, D1 (this one) have landed, in order, each
committed on a green full gate. The block is incomplete** — the rest of Pass D, and E through H, are
unstarted. This is a handoff report written for the next session rather than a closing one.

**What changed since the last version of this report: the layout is live.** `ViewModes.player()` uses
`ModeChrome.BATTLE_LAYOUT`, so every surface in Pass C's placement table has moved to where that
table puts it. The previous opening said "nothing visible has moved"; that is no longer true.

**Rewrite this opening when the block closes.** It describes seven of eight-plus passes.

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

**Pass D is coupled to Pass F in a direction the taskblock's ordering does not show, and this is the
thing the next session most needs to know.** `stat_panels_module` owns the `AimView`. Pass D says
"`stat_panels_module` retires"; Pass F says the aim view and dartboard "are not UI modules and do not
become ones — they are what the mode switches *to*". **Retiring `stat_panels` wholesale deletes the
aim view Pass F depends on.** D1 stopped at the retirement's stated prerequisite rather than
discovering this halfway through the deletion. The aim view needs a home first; the cheapest reading
is that Pass F's mode switch is what gives it one, so **F may need to run before the rest of D**, or
D2 must rehome `AimView` on its own terms. A supervisor call if the ordering matters; otherwise the
next session should take the F-first reading.

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
