# Taskblock 56 Report — One view of modules, and the editor that proves it

**All six passes landed, in order, each committed on a green full gate.** A–E landed first at
2837/2837; Pass F followed in a later session and the block closes green.

**The block's central question — "is the editor a module set plus one authoring module?" — is
answered yes.** `ViewModes.editor()` is a six-line table entry: six modules that already existed
plus one new `EditorModule`, in the player mode's own chrome. No subclass, no new chrome, no
duplicated panel, nothing reached into another mode. The other two structural acceptances hold as
before: every module mounts against a context with no overlay, and a mode is a table entry rather
than a file.

**One correction to how that is counted, because the naive measure gets it wrong.** Two of the
editor's six existing modules — `claim_volumes` and `camera_framing` — are mounted by no *other*
mode, so "modules unique to the editor" reads as three. They are not the editor bringing anything:
Pass E built and tested both, and `PLAN.md` recorded `ClaimVolumeModule` as "correct and
unreachable" pending exactly this surface. The test therefore counts against a pinned list of what
existed before Pass F opened.

*Sections below are in pass order; Pass F's are at the end.*

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

**Does the editor need a subclass?** ~~The block's own most valuable possible finding, and it is
unanswered because Pass F was not reached.~~ **Answered by Pass F: no.** See that pass's sections
below.

---

# Pass F — the editor

## Decisions made without asking (Pass F)

**The editor mode reuses `ModeChrome.PLAYER_COLUMNS` rather than declaring a layout of its own.**
The alternative was an `EDITOR_COLUMNS` chrome sized to an authoring panel, which would have been
defensible and would also have weakened the pass's own claim: a chrome is a named layout a mode asks
for, so adding one is the closest thing to "the editor needed a surface of its own" that the module
system still permits. Reusing an existing layout makes "no new chrome" a fact rather than a
judgement call, and the authoring panel sits in the left column that already exists for panels.

**Nothing validates on the way in; `GridPlacement.can_place` is replayed as a warning instead.** The
alternative was to gate placement on the attachment grammar, which is what the generator does. F4
says warn and never block, and `MapSerializer`'s header had already settled the same question for
the load path — so the grammar is replayed over a board grown in authored order and reports "a
catwalk with nothing to attach to" rather than refusing it. **A deliberately broken board is
authorable**, which was the requirement.

**Undo is a snapshot stack, not an inverse operation per verb.** The alternative is cheaper at
runtime and more code: twelve inverses, of which the one nobody exercises is the one that is wrong.
A board is a few hundred placements, so a full deep copy per edit is affordable and makes "undo
restores the prior state exactly" true by construction. Two consequences chosen deliberately: every
verb snapshots *even when it changes nothing measurable* (otherwise an author's third undo lands
somewhere different depending on what their second edit hit), and addressing is by cell rather than
by a held `MapPlacement` (a restore builds fresh resources, so a held reference would point at a
placement the model no longer contains).

**`BoutInjector.load_map_file` was added rather than having the editor save-then-load-by-path.** The
path route works and needs no new code, and it would mean the only launchable board is one already
written to disk. The factoring keeps one route into a bout: `load_map` and `load_map_file` share
`_swap_to_map`, so an authored board is marked `was_injected` and logged exactly as any other board
swap is — under `load_map`'s own verb name, with `<authored>` as its path, because a log line naming
a file that does not exist is worse than one saying there was none.

**When that put `BoutInjector` over its 1000-line gate, the file resolution moved to `BoardSwap`
rather than the limit moving.** The alternative — raising `max-file-lines` — is precisely what
taskblock-45 Pass E spent a pass undoing, and `test_retired_planner_sweep.gd` asserts the 1000
directly. `BoardSwap` exists *because* the injector was over its limit once before, and its header
says so; "which file did they mean" is no more debug policy than "where does this unit stand now"
was. `resolve_map`/`resolve_section`/`swap_to_map` moved; the guard, the refusal reasons and the
`inject` log line stayed, and the reasons a refused load gives are unchanged. **The injector now
sits at exactly 1000 lines**, which is a thing to notice rather than to be comfortable about — the
next verb added to it has to move something out first.

**The board is swapped live on every edit, so units get relocated as you author.** The editor mode
installs over whatever bout `BattleScene` already built. The alternatives were to clear the roster
(inventing a bout concept this pass has no business inventing) or to draw the authored board without
touching the live grid (a second rendering path for the same board — the parallel-system smell).
Swapping through the same `BoardSwap` a map load uses means what you author *is* what a bout would
get, and the relocation is stable rather than jumpy. It is visibly odd, and it is recorded in the
module header and in `PLAN.md` against *Main menu*, which is where a no-bout entry point belongs.

**The whole-section declarations are discovered from `SectionFile`, not listed.** A constant list
would be simpler to read and would need editing every time the section format grows a field. The
discovery reads the resource's own property list minus the properties the editor models explicitly,
so a new `@export` becomes an editable field the day it is added — the standing open-vocabulary rule
applied to an authoring surface rather than to content.

**Adding the editor key was scope taken on, and taken on deliberately.** Nothing installed the mode:
it was reachable only from tests. That is exactly the state Pass E left `ClaimVolumeModule` in and
which `PLAN.md` then had to carry as an open item for a whole block, so shipping an unreachable
authoring *surface* would have repeated the mistake one level up. `EDITOR_KEY` (N) mirrors
`SIMULATE_BOUT_KEY` exactly — one constant, one legend row, two lines in
`BattleScene._unhandled_input` — and that cost is itself the clearest measure of what the mode table
bought.

**`target` is an open `StringName`, not a two-value enum.** It has two answers today, which argues
for an enum by CLAUDE.md's rule. It names a *file format*, and a third authored format is a schema
plus a serializer rather than an engine state, so it is content vocabulary in the same sense
`MapPlacement.kind` is. Reversible either way; flagged because the rule genuinely points both
directions here.

## Tests that failed, then were corrected (Pass F)

**Seven, across four files.** `test_editor_controller.gd` passed 30/30 on its first run; the seven
were four in `test_editor_mode.gd`, one caught only by the full gate, and two caught only by
regenerating the suite profile. **The five most useful are below; the last two are covered in their
own section under "the profile was four taskblocks stale", because they are not really about this
pass.**

Two were real defects in my code, two were my own fixtures holding wrong assumptions, and three were
pre-existing debt that my work made visible.

1. **`_save_into` wrote to `res://data/maps/user://test_editor_mode_saved.tres.tres`.** A real
   defect. It keyed "is this already a path" on `res://` rather than on `://`, so any absolute path
   that was not `res://` got the directory and the extension glued on anyway. **The test was right
   and the code was wrong.** Fixed by keying on `://`, which is the honest question being asked.
2. **`open()` then could not reopen what the editor had just written** — the same assumption in
   reverse, and only visible once (1) was fixed. Rather than patch the second copy, `open()` now
   goes through `BoardSwap.resolve_map`/`resolve_section`, so "a name or a path" is answered in one
   place for the editor, `load_map` and `preview_section` alike. `BoardSwap`'s own path test widened
   from `res://` to `://` in the same edit; no catalog display name contains `://`.
3. **"exactly one module is new to the editor" failed, reporting three — and the test was wrong, not
   the mode.** `claim_volumes` and `camera_framing` are declared by no other mode because Pass E
   built them for exactly this surface and left them unmounted. Measuring "new" as "unique to the
   editor" measures the wrong thing: **a claim about what a pass cost cannot be read off the tree
   that pass already changed.** Rewritten to count against a pinned list of the eighteen modules
   that existed before Pass F opened, with the reasoning in the constant's own comment. This is the
   most useful failure of the four — the naive measure would have made an honest result look like a
   failed one.
4. **"sanity: the live board is not already the authored one" failed because it already was.** The
   fixture authored a board and then asserted the live grid had not changed yet — but authoring
   swaps the board live, which is the feature. The sanity check was rewritten to assert on
   `was_injected` instead, which is what actually distinguishes *previewing* a board from
   *launching* one. The behaviour was right; my assumption about it was a turn out of date.

5. **The retired-word guard caught a doc comment, and only the full gate could.** I wrote "writing a
   field into the void" in `editor_controller.gd`; "void" has been lore-only outside a `-> void`
   annotation since taskblock-39/40. Reworded. **Worth recording because of where it was caught:**
   both targeted runs and the whole view-modules directory were green, and this is structurally
   invisible to them — the guard sweeps `src/`, so only a run that includes it can see a word I
   introduced anywhere. It is the concrete case for CLAUDE.md's "widen before you commit" rather
   than an argument for it.

## The profile was four taskblocks stale, which is the other two failures

**`test/suite_profile.json` was last regenerated at taskblock-52** (commit `303e1db`), so the
per-taskblock regeneration was skipped for 53, 54, 55 and 56 A–E. Both remaining failures are that,
surfacing at once when I regenerated it — and **neither guard could have reported earlier**, because
both read the *committed* profile rather than the live run, a trade `test_suite_budget.gd`'s own
header states outright.

**`ui_builds` 344 → 627, of which this pass is 63.** Measured per file against the tb52 profile so
the growth names its causes: `test_editor_mode.gd` +63 (mine), `test_view_modes.gd` +38,
`test_spectator_overlay.gd` +36, `test_resolution_player.gd` +33, `test_squad_control_overlay.gd`
+15, eleven others +47. So **169 of the 232 landed before Pass F and were never recorded.** The
baseline is raised to the honest current measurement with that table in `suite_budget.gd`. The
lesson is about cadence rather than size: regenerated per taskblock, each of these would have been
reported against the change that caused it, which is the argument that file's header already makes.

**`test_map_serializer.gd` builds 2 bouts and was not in `SuiteTier.BOUT_FILES`.** It has carried
`should_skip_script()` since taskblock-53 Pass B — the fast gate really was skipping it — but the
list entry was missed, and the tier guard reads bout counts from the stale profile, so it never saw
the two bouts that appeared at tb53. Added. **Nothing in Pass F caused it**: the file has not been
touched since taskblock-54 Pass A, and a targeted run confirms the 2 bouts against the current tree.

**A recommendation rather than a finding:** regenerate the profile with `WRITE_PROFILE=1` at the end
of every taskblock, as the file's header assumes. Four blocks of drift arriving as one number is the
failure mode the ratchet was built to prevent, and it very nearly cost more to attribute than it did
to fix.

**Also worth recording: the Pass E claim-module guard had to be narrowed, and that is the guard
working.** `test_no_play_mode_declares_the_claim_module` asserted that *no* mode in `ViewModes.all()`
declares `claim_volumes` — written as a total ban because there was no authoring surface for the
exception to apply to. It now excludes a pinned one-entry `AUTHORING_MODES` list and additionally
asserts that the set of modes drawing claims is *exactly* that list, so the exception cannot widen
by accident. A total ban retired the day the thing it held empty went live.

## `SUPERVISOR`-owned entries moved to `Pending` (Pass F)

**None.** Pass F touched no entry in `docs/BUGS.md`. The two defects it fixed were introduced and
corrected inside the pass and never landed, so neither is a ledger entry.

**What the supervisor may want to look at anyway, since none of it is verifiable headlessly:** press
**N** in a running game to open the editor. The claim boxes drawing in their four colours, the
authoring panel's layout in the player mode's left column, and whether the live board preview reads
as helpful or as distracting while units are shuffled around by it are all things a headless run
cannot report on.

## Open questions (Pass F)

**Should the editor start on an empty world rather than on top of a bout?** Today it installs over
whatever `BattleScene` built, so units are relocated onto the authored board on every edit. The board
and the authoring are correct; the units are noise. The fix is an entry point that builds a world
with no bout in it, which is *Main menu*'s work and is sequenced immediately after this. **The
evidence points at leaving it** until that item is picked up, rather than growing a second
world-construction path here — but if the noise makes the editor unpleasant to use in practice, that
is a judgement only the supervisor can make from the running game.

**A claim is authored one cell at a time.** `add_claim` places a one-cell volume from the deck to a
flagged 2.4, and `resize_claim` takes an arbitrary `Box` and is fully tested — so every extent the
format can express is reachable, and only the click-and-drag *affordance* is missing. Whether that
affordance is worth a pass on its own, or should wait until someone has authored a real section and
found out how much it hurts, is a scheduling call. Recorded in `PLAN.md` either way.

**`DEFAULT_CLAIM_HEIGHT` is 2.4 and nothing chose it.** It is the height a full-cell wall stands at,
which makes it a defensible default and not a designed one. Flagged in the constant rather than
presented as a decision.
