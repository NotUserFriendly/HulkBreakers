# Taskblock 48 Report — Three rungs, a window on the run, then the collapse

**Passes A, B and B2 landed; suite green.** The supervisor cleared the mid-block checkpoint after
running the suite from the game window and watching a forced failure replay as a real bout. Passes C
and D follow.

Full gate ~585 s, fast gate ~126 s, a targeted run ~3.7 s.

## Decisions made without asking

- **`candidates` and `shot_planes` stayed ungated in the work budget** (carried from taskblock-47) and
  **`test_full_mission.gd`'s turns are now excluded from it entirely.** Three full runs measured 1680,
  1578 and 1385 turns — a 19% spread against 15% headroom — and all of it comes from one file that
  seeds its sample from the clock *on purpose*. Gating that is gating on luck. The fix is exclusion,
  not a bigger number: its *bouts* stay gated because that count is exactly `SAMPLE_SEEDS`.

- **A targeted run narrows the fixed floor; the import step stays.** Measured before deciding:
  `gdlint src test` 6.14 s, import 2.32 s, parse guard 0.82 s, GUT startup ~1.2 s. gdlint runs over the
  target only (0.21 s) and the checkpoint parse guard is skipped — it guards checkpoint scenarios, not
  anything under test. **Import stays**: it registers a `class_name`, and skipping it makes a newly
  added script invisible in a way that looks like a broken test.

- **Only the full gate may write the profile artifacts**, whatever `WRITE_PROFILE` says. They describe
  the whole suite, so a run that saw part of it cannot honestly produce them.

- **The replay rebuilds a fixture; it never re-runs the test.** The headless run already established
  the reason and the result — what was missing is what the test *built*. That also sidesteps hosting
  `GutRunner` in the live scene tree, where it would fight the running game for the root.

- **`WatchedRun` was folded onto `ReplayHandle` rather than kept alongside it**, so a failed
  map-generation test and a failed completion seed queue in one list with one set of controls. Its 11
  existing headless tests pass unchanged.

- **The force-failure variable goes on the child's command line, never on this process.**
  `OS.set_environment` is process-wide, and taskblock-47 already had one test switch the fast gate off
  by clearing a variable it set.

- **The panel purges the board on launch.** The supervisor's suggestion, taken as given: with the old
  bout still on screen, a working replay and a dead one look identical.

## Tests that failed, then were corrected

**Roughly twenty distinct defects before commit across the three passes.** Five below, chosen because
each names a different way to be wrong.

1. **One log file for every process, so a suite that runs suites overwrote its own feed.** The path was
   `suite_run_<counter>.log` with a `static` counter — which restarts at 0 in *every* process. The
   game's panel run was file 1; the gate reached `test_suite_run.gd`, which made its own `SuiteRun` in
   its own process, numbered it 1, and truncated the file the panel was tailing. **The panel then read
   the nested run's verdict as its own**: a forced fast gate reported "PASSED — 20 passing, 0 failing",
   which is `test_grid.gd`'s count, and appeared to stall on whichever file was on screen when the log
   rewound. Two symptoms, one shared path. The pid is in the name now.

2. **`failures()` could not read a single real run.** GUT colours its output, so summary lines arrive
   with an escape prefix before `- test_name` and every prefix check missed. It went unnoticed because
   my tests fed it hand-written lines with no escapes — **input tidier than reality, which is worse
   than no test**, because it reports success for a parser that has never seen its subject.

3. **The entire replay path had zero callers.** `offer_failures`, `bind` and `on_bout_finished` were
   never invoked from `src/`; the panels sat holding `run = null` and `battle = null`. Every piece was
   tested and proven to work *when called*, and nothing asserted it got called — `docs/11`'s named
   failure mode, walked into a week after quoting it twice.

4. **`kill()` killed the shell and not the Godot it launched**, leaving **79 orphaned Godot processes**
   running suites nobody was watching. My own test hid it: I had asserted `run.is_running()`, which
   short-circuits on `finished` and verified nothing. It counts real processes now. The fix also needed
   `kill` routed through bash — it is a shell builtin, and `OS.execute` fails *silently* when it cannot
   find a binary, which is how the first fix appeared to work and did nothing.

5. **`test_suite_run.gd` launched the full gate, which runs `test_suite_run.gd`.** Unbounded recursion,
   braked only by how fast each generation was killed; it reached **107 concurrent Godot processes**.
   Every run started from a test now targets a file that cannot contain itself.

**A pattern worth naming, because it accounts for most of the list:** four separate times I wrote a
test that assumed nobody was exercising the feature it covered — a subprocess inheriting the
force-failure variable, an assertion that the environment was *empty* rather than *unchanged*, a tier
test that cleared an environment variable mid-run, and a layout test that counted the window sizes it
had *asked* for. Each passed until the feature was used.

## `SUPERVISOR`-owned entries moved to `Pending`

None this block.

## Open questions

- **A visual test's fixture is not always worth looking at, and the split is now visible.**
  `test_map_gen_raised_rooms.gd`'s handles rebuild a map with no units on it — correct, since the map is
  what failed — so a replay of one renders a board that does not move. `test_exit_code_probe.gd`'s
  handle is a seed bout that plays. Both are right; there is no single answer to "what should a replay
  show", and the handle is the place that decides.

- **B2.4 asks whether the replay mechanism makes `checkpoint_8`/`checkpoint_9` redundant. Partly, and
  not yet.** A checkpoint is "a visual test whose assertion is a human", which is exactly what a
  replayed handle is — and `checkpoint_9` already drives `load_battle` from a `GridFixture`, the same
  path `ReplayHandle` uses. What the replay cannot do is answer a question nobody has failed a test
  about: checkpoints exist to look at something *on request*, not only when it breaks. **Converging
  them would need a way to replay a handle without a failure**, which is a small addition to the panel
  rather than a new mechanism. Worth doing before a third renderer accretes; not this block.

- **Resolution variation in the layout test is uncovered and cannot be covered headlessly.** Neither
  `root.size` nor `content_scale_size` changes any reported rect with no real window, so a loop over
  four resolutions measures one layout four times. It checks the single viewport headless has, and says
  so. A visual checkpoint is the tool for the rest.

- **The panel's numbers are flagged starting points, not derived ones**: 560 wide, 260 tall for the
  feed, 18 visible lines, a 0.25 s poll. Sized for a `res://test/unit/...` path without crowding the
  board.
