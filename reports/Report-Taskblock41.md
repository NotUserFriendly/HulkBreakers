# Taskblock 41 Report — Diagnostics: the log becomes the instrument

All six passes landed in order (A→B→C→D→E→F), each committed separately, suite green throughout —
2183/2183 at the end, up from 2168 at the start of tb40's close. Closes `PLAN.md`'s NEXT item 2 and
the QUEUED "Checkpoints return as an ordinary tool" outright.

## Decisions made without asking

- **Pass B: `OS.add_logger` exists, so the "reachable set" is much larger than the taskblock assumed
  — and I verified it before writing anything rather than after.** The pass told me to write the
  reachable set down first, so I probed the engine directly with a throwaway `Logger` subclass, one
  case at a time. The surprise: **GDScript runtime errors are reachable, carrying the real script file
  and line**. A null deref mid-resolution now lands in the log next to the event before it. I had
  assumed going in that only our own `push_error` calls were catchable and had drafted a much weaker
  design around that; the probe is the only reason the pass isn't a fraction of what it is.
- **Pass B: `_log_message` deliberately not hooked, so `print()` is not captured.** `StdoutSink`
  prints every event it receives, so capturing messages would be an unbounded print→emit loop. This
  narrows "diagnostics on the stream" to errors only; an alternative would be capturing prints and
  excluding `StdoutSink`, which trades a loop for a rule every future sink has to remember.
- **Pass B: engine error chains are reported faithfully, not deduplicated.** One missing resource
  produced three callbacks as the C++ chain unwound. Collapsing them needs a policy nobody specified,
  and the unwind chain is itself information — flagged as tunable rather than invented.
- **Pass C: `try_apply` reports `action_illegal` plus the action's `describe()`, not a real per-action
  reason.** A genuine reason means changing `is_legal`'s signature across every action in the
  codebase. That is a bigger, riskier change than "audit the action path" warrants, so it is stated
  as not-done rather than half-done.
- **Pass C: two rows appended to `SUPERSEDED.md`.** This pass reverses tb29's documented "a rejected
  call is a true no-op (nothing mutated, **no log entry**, no RNG draw)". The mutation and RNG halves
  stand; the silence does not. `BoutInjector`'s own header carried that claim and was corrected too.
- **Pass D: the wall cutout is not logged per frame, and this is the one place I narrowed the
  taskblock's own wording.** "cutout drawn to (x, y)" taken literally means an event per frame per
  wall while the camera orbits, and `FileSink.emit()` flushes to disk per line — it would cost more
  than the effect it documents and bury every other event. It logs when the cut set meaningfully
  changes instead. Stated in the code and here rather than quietly scoped down.
- **Pass D: "bot constructed, part attached" is logged where a unit enters the world, not inside
  assembly.** `DeepStrike`/`BodyAssembler`/`PartGraph.attach` are pure static logic with no
  `CombatLog` in reach. Threading one down would push a diagnostic concern into the deepest layer of
  the codebase to buy a per-socket event. `CombatState.add_unit` lists the parts in socket-tree order
  instead, which answers the diagnostic question without the plumbing.
- **Pass E: the parse guard is a shell-invoked script, not a GUT test — and the reason matters more
  than the choice.** *(Written up here at the supervisor's explicit request.)* I wrote it as a GUT
  test first and it worked. Then I proved it by reintroducing BR40.02's exact `UnitView` reference
  into a scenario script — and it **hung**. `run_tests.sh` runs GUT with `-d`, and under the debugger
  a parse error inside `load()` raises a Debugger Break that waits for input. **The guard would have
  hung the build instead of failing it, which is a strictly worse failure than the silent rot it
  exists to catch** — a red build gets fixed, a hung build gets killed and shrugged at. Moved to
  `tools/checkpoints/parse_guard.gd`, run without `-d` and *ahead of* GUT so a broken scenario fails
  fast before the debugger-enabled step can reach the same file. Verified both ways: broken → exit 1
  naming the file, restored → "1 scenario(s) OK". Worth knowing generally: **this is a trap for any
  future guard that validates by loading something.** It also checks each scenario still extends
  `SceneTree`, which is what actually caught the reintroduced break — a script with a parse error
  still loads as a `GDScript` object, just with an empty base type, so "did it parse" alone is a
  weaker check than it sounds.
- **Pass E: `checkpoint_{6,7}.gd` deleted rather than repaired, and BR40.02 closed `Obsolete` rather
  than `Resolved`.** `PLAN.md` called for the deletion; the status choice is mine. Nobody verified a
  fix because there was no fix — the code the entry describes no longer exists. Writing `Resolved`
  would assert a verification that never happened.
- **Pass E: the old GUT-based checkpoints 1–5 removed from `checkpoint.sh` entirely**, beyond the
  PLAN item's "rename them". They were never checkpoints — they are regression tests the suite
  already runs, and a separate ritual around them only ever produced a second, staler copy of what
  `./run_tests.sh` prints. They live under `test/baselines/` now.
- **Pass F: the FPS readout sits in the title bar, not over the log body.** The taskblock says "drawn
  over the log, not in it". Rendering it showed that at the panel's real width the body's top-right
  corner is exactly where the first log line sits, so it printed straight through the text. The title
  bar is the one strip of the panel with no content to collide with. Still over the panel, never
  emitted into the stream, which is what the instruction was protecting.
- **Pass F: `SpectatorOverlay` still uses its own bare log label.** Only `SquadControlOverlay` was
  converted. The pass is explicitly a session opener to be iterated live, and converting the second
  overlay to a shape that is about to change seemed worse than leaving it consistent with itself.
  Flagged rather than silently skipped.
- **Passes A/F: I rendered real frames and looked at them.** This sandbox has a working GPU and X11.
  Pass A's numbers were measured against a real `RichTextLabel` in a real tree (headless and x11
  agreed within ~2%, so that cost needs no GPU to re-measure later), and Pass F's panel was checked by
  actually looking at `./checkpoint.sh 8` output — which is how both of its layout bugs were found.

## Tests that failed, then were corrected

Four, all caught before commit. Three are the "the change was right and the fixture held an old
assumption" kind.

1. **`test_end_turn_action.gd::test_end_turn_emits_turn_end_for_the_ending_unit_then_turn_start_for_
   the_next`** (5 assertions failing). It asserted the exact stream length was 2; Pass C's
   command/outcome pair made it 4. The test's real intent is the *ordering* of two specific events,
   so it now filters for them — and additionally pins the new bracketing pair, which is a contract
   worth having a test. A length assertion on a shared stream breaks on the next legitimate addition
   too; filtering is the durable form.
2. **`test_battle_scene.gd::test_new_battle_logs_the_seed_at_session_start_to_both_sinks`** (crashed
   on an empty array). **This one was a real regression, not a stale fixture.** Pass D's bout-build
   log displaced `session_start` from the log file's first line, breaking docs/09's "replayable from
   its own log file alone". First fix attempt — emitting the header earlier — fixed the file and
   broke the UI sink, because the overlay's sink only attaches on `battle_loaded`, which fires at the
   *end* of `load_battle()`. Real fix: `load_battle` takes an optional header event and emits it
   between attaching the sinks and building anything, and sink attachment became an explicit
   `ControlOverlay.attach_log_sink` call at that same point instead of a side effect of a signal.
3. **`test_battle_scene_input.gd::test_every_richtextlabel_panel_ignores_the_mouse_except_the_log`**.
   Flagged `CombatLogPanel` and its body for sitting at `MOUSE_FILTER_STOP`. The guard was right to
   look and wrong to fail: its rule is "a Control that renders **nothing** must not eat clicks" (the
   BR31.01/BR34.02 class), and a panel drawing a real opaque background is the opposite case. Taught
   it to recognise a script-defined `_gui_input` override and a genuinely visible style box, while
   still catching an invisible container at STOP.
4. **Pass A's own new equivalence test.** Compared two sinks' BBCode byte-for-byte, but
   `HierarchicalUiSink` embeds `group.get_instance_id()` in its `[url=...]` metas, and instance ids
   are routinely **negative** — my normalising regex (`group_[0-9]+`) matched nothing, so the test
   failed on object identity rather than content.

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** No `SUPERVISOR`-owned entry was closed or moved this taskblock.

- `BR27.09` (Pass A) gained a measured before/after note and an explicit record that its prescribed
  fix was overridden — it stays `Active`, and the several-second hitch it is really about is
  untouched, as the taskblock instructed.
- `BR34.02` (Pass F) is answered structurally — the log panel has a real background now, so it is
  honest about the space it occupies — but the call is the supervisor's and CC does not close it.
- `BR40.02` moved to `Obsolete`, but it is `CC`-owned, not `SUPERVISOR`-owned.

## Open questions

- **`BR34.02` is ready for a look.** Pass F gives the log a real background, which is one of the two
  things that entry says must change. Whether that settles it, or whether the click-through half is
  still wanted, is the supervisor's call. The `mouse_filter` sweep it also asks for stayed out of
  scope per the taskblock; it is still the third instance of that failure class.
- **How far to take the log window.** Pass F is deliberately a starting position: panel width comes
  from the surrounding column and the log is narrow enough that lines are cut off, minimize collapses
  to the bar without remembering a dragged height across a minimize/restore cycle, and
  `SpectatorOverlay` is unconverted. All of that is cheap to change once there is an opinion; none of
  it is worth guessing at.
- **Whether the engine-error unwind chain should be deduplicated.** One failure currently produces
  several `diagnostic` events. It is faithful, and the chain is real information, but it is also
  three lines where a reader wants one. Evidence is thin either way until the log has been read in
  anger — no policy invented.
- **`FpsMeter`'s one-second window and `CUTOUT_LOG_GRID`'s 64px quantum are flagged placeholders**,
  picked to be reasonable rather than right. Both are one-line changes.
