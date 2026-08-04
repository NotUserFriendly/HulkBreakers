# Taskblock 56 Report — One view of modules, and the editor that was not reached

**Passes A, B, C, D and E landed, in order, each committed on a green full gate (2837/2837 at the
end). Pass F — the editor — was not started.** The block's two structural acceptances both hold: every
module mounts against a context with no overlay, and a mode is a table entry rather than a file. The
editor was the one pass left, and it is the one the block called its own proof, so **the central
question "is the editor a module set plus one authoring module?" is unanswered rather than answered
either way.** It is specified in full in `PLAN.md` under *Map and section editors*.

## Decisions made without asking

**Stopping after Pass E rather than starting Pass F.** The alternative was to begin the editor and
leave it partly built. Pass F is `EditorController` plus two serializer round-trips plus a bout launch
plus a validation surface, and it is comparable in size to Pass C or D individually. CLAUDE.md's rule
is to stop and flag rather than hack around; a half-built editor would also have made the block's own
most valuable question — does the editor need a subclass? — unanswerable in a *misleading* way rather
than an honest one. The spec is copied into `PLAN.md` verbatim because `taskblock56.md` rotates away.

**`DebugPanelModule` is classified `DISPLAY` even though debug injection mutates the board.** The
display/input axis is drawn at unit input — the `TacticsController` path ending in
`ActionQueue.enqueue`. Injection is a debug-build-only verb path that the spectator view has carried
since taskblock-30. Classifying it `INPUT` would have made the spectator an input mode and destroyed
the exact distinction Pass C exists to express. The alternative was a third axis for debug surfaces;
that is the debug-menu overhaul, which this block explicitly is not. Recorded in the module's own
header rather than left implicit.

**`ModuleContext` has no `overlay` field at all.** Pass C's acceptance is that a module cannot need its
parent. The alternative was to pass the overlay and rely on discipline. Leaving the parent out of the
vocabulary makes the acceptance structural instead of aspirational — the two things a module genuinely
needs from its host are published as `Callable` capabilities (`advance_ai_turns`, `rebind_all`).

**Overlay panel fields became module accessors rather than forwarding properties.** ~150 test call
sites moved from `overlay.inspect_panel` to `overlay.inspect().panel`. The cheaper alternative was to
keep a field per panel forwarding into its module, which would have kept every test untouched and
quietly preserved the thing the collapse was removing: "which panels exist" as a property of the class
rather than of the mode. Four forwarding properties were kept on the spectator surface during Pass C
as a deliberate intermediate step, and removed in Pass D.

**Pass B's findings were appended to `BR54.01` as well as `BR51.01`.** The block's text names `BR51.01`
while quoting `BR54.01`'s measurements (43°, 8.6° chaingun). Rather than pick one, the confirmation
went to `BR54.01`, whose stated unverified suspect it settles, and the elimination went to `BR51.01`,
which is what the pass was asked to bear on. Both entries say so.

**`BR35.02` was left `Active` rather than marked `Pending`.** Pass D asked for the three deferred
entries to be re-checked and marked `Pending` with what changed. `BR27.04` and `BR32.09` were already
`Resolved` and archived before this block. `BR35.02` did not evaporate, and nothing was fixed — so
`Pending` would have asserted a fix that does not exist. A note was appended explaining why its stated
shared cause was wrong for that entry specifically.

**A design question was opened and deliberately not answered.** Pass B established that a shot's aim
point is the centre of the target's *frontmost projected region* — not the body's centre, not a point
on the muzzle-to-target axis. Nothing chose that; it is what "frontmost region" came to mean once
bodies stopped being single boxes. It is written into `docs/02` labelled a finding, explicitly not a
specification. Picking between the three candidate aim points is a design call, and it is in the open
questions below.

## Tests that failed, then were corrected

**Five, four of which were the change being right and a fixture holding an old assumption.**

1. **`test_view_gap_modules.gd`'s camera-framing test passed while proving nothing** — caught before it
   landed, not by the suite. It computed the target zoom and asserted it against the target zoom, which
   agrees with itself and nothing else. Rewritten to step the framing tween to completion and ask
   whether the content's bounding sphere fits the frustum *at the zoom the rig landed on*: content
   radius 5.166, rig zoom 9.759, visible radius 5.941. This is the failure shape `docs/TEST-AUDIT.md`
   keeps finding and it was one commit from being added to the pile.
2. **`test_bout_injector_determinism.gd` asserted both overlays reference `bout_injector`.** They no
   longer do — one gated module does. The change is a strictly stronger guarantee (two gated copies
   became one, removing the thing that could drift), so the test was pointed at the module and gained a
   second assertion that no surface reaches for the injector directly.
3. **`test_spectator_overlay.gd` asserted the debug panel's input owner is the overlay.** It is now
   `BoardInspectModule` — which is a correction rather than a regression: the panel borrows a click
   from whatever owns `board_clicked`, and that is now the board module. The overlay's own signal still
   fires, so nothing wired against it changed.
4. **Three spectator tests failed because a placeholder overlay started driving the AI.** Fixtures
   install a bare `ControlOverlay` to neutralise `BattleScene._ready()`. A modeless surface defaulted to
   the player mode, which *has* unit input, so it drove the AI batch and every fixture's bout was a turn
   further on with units standing somewhere else. `ViewModes.empty()` is the faithful translation of the
   old inert base class. **The root cause was a default I chose, not an old assumption** — the fixtures
   were right.
5. **`test_squad_control_overlay.gd`'s "the AI batch actually runs" failed because a signal does not
   await its handlers.** Routing the batch through `turn_resolved` looked cleaner and silently broke it:
   `emit` runs a coroutine handler to its first `await` and detaches, so an awaited turn returned with
   the batch in flight. That is precisely the defect tb45 Pass E fixed by adding an `await` to a
   fire-and-forget call. The advance is awaited inline.

**Also worth recording, since nothing failed but something nearly did.** The single-unit auto-select
used to work *because* the old code did not await — it ran at the batch's first suspension point.
Awaiting properly moved it a frame later, past where a caller looks. It now runs inside the batch loop
the moment the controlled unit becomes current, which is the same timing without depending on where a
suspension happens to land.

**And the checkpoint parse guard earned its keep**, catching `checkpoint_9.gd`'s orphaned
`SpectatorOverlay` reference at the full gate — exactly the `BR40.02` failure mode it was added for,
where a rename orphaned two scenario scripts for fifteen taskblocks because nothing re-ran them.

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** Recorded as a deliberate result rather than an omission:

- **`BR55.02`** (tile winding) was `CC`-owned and is `Resolved` and archived. What is verified is that
  the emitted vertex order now matches the primitive every other box on the board is built from, with a
  test that reports `12 of 12 tile faces wound inside out` when reverted. What is *not* verified is that
  the board looks right — a headless run culls nothing, so the supervisor seeing a tile from above is
  still the only confirmation of the symptom as reported.
- **`BR35.02`** was re-checked as Pass D asked and is still `Active`. Nothing was fixed, so `Pending`
  would be a false claim.
- **`BR51.01`** and **`BR54.01`** received appended findings, not status changes — Pass B was an
  investigation and says so.

## Open questions

**Where should a shot aim?** Pass B found that it currently aims at the centre of the target's
frontmost projected region. Measured on a real assembled body: **20.1° off the muzzle-to-target axis at
1 cell, 5.9° at 2, 0.6° at 3, −0.1° at 10**, with the winning part changing identity as depth ordering
shifts, and the aim *height* dropping to that part's height (0.80 at a gun, against 1.36 at the upper
body). Three candidates: the frontmost region as today, the body's centroid, or a point on the
muzzle-to-target axis. **The evidence points at the axis** — it is the only one of the three that makes
"the gun points where the round goes" true by construction, and the current behaviour was never chosen.
But it is a design call with combat consequences (a centroid or axis aim point makes an outstretched
limb harder to target deliberately), so it has not been made.

**`BR54.01` has residue, and it matters for how it gets closed.** The mechanism above is confirmed and
has the right shape and range-dependence, but tops out near 20° at *one* cell and ~7° at two, where that
entry measured **43.1°** at 2.3–5.3 cells. Something else is also in play. Closing the entry on the
confirmation alone would be premature, and the entry says so.

**`ShotPlane.center_of`'s no-region fallback looks wrong and was not filed.** It returns
`Vector2(target.cell.x, target.cell.y)` — grid cell coordinates handed back where every caller expects a
`(lateral, world height)` point in plane space. It only fires when a target projects no region at all,
which may be unreachable in practice, which is why it was noted on `BR54.01` rather than given its own
ID. **A supervisor call: real defect, or dead branch?**

**`InternalTargeting.aim_offset_for` has no production caller.** The knowledge-gated aim-at-a-named-
internal path exists, is tested, and nothing outside its own tests reaches it. Either it is unfinished
work or it is dead code, and which one determines whether it belongs in `PLAN.md` or in a deletion.

**Does the editor need a subclass?** The block's own most valuable possible finding, and it is
unanswered because Pass F was not reached. Everything it needs is in place — seventeen modules, a mode
table, a chrome layout system, and `ClaimVolumeModule` sitting tested and deliberately unmounted waiting
for an authoring surface to turn it on.
