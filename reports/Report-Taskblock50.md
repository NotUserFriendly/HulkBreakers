# Taskblock 50 Report — Under the clock, but not under five minutes

**Passes A, B and D landed; suite green — 2435 tests, 0 failures.** Pass D was taken **out of order,
before C**, for a reason recorded below. **Passes C, E and F are not done.**

**Full gate 446.8 s → 332.4 s (26%).** The block's acceptance is *under five minutes*, and that is
**not met** — 332.4 s against a 300 s bar. What remains is named at the end with what each piece is
worth, rather than reported as nearly-there.

## Decisions made without asking

- **Pass D was run before Pass C, and the ordering was the point.** The suite could not measure
  itself: three consecutive full gates with no code change between them came out at **970, 1305 and
  961 turns**, and two came out at **350.7 s and 396.4 s**. Any saving from B, C or E was smaller
  than that swing, so it would have been unverifiable underneath it. Pass D removes the swing at
  source. It also closes `BR49.01`, which I had filed the day before against exactly this.

- **`FIRST_WIN_CAP` is 9, derived from the measured rate rather than picked.** At the measured 0.72
  completion rate, nine straight losses is 0.28⁹ ≈ **one run in 180 000**. It is deliberately a
  *collapse* detector — at a rate of 0.20 it fails about one run in seven, at 0.10 about one in
  three, and a mild regression it will not fail at all. **That is the design, not a gap:** the
  reported count is the signal, and a threshold on a small integer count is precisely what put
  `MIN_COMPLETION_RATE` a fraction of one seed from red and got it lowered twice.

- **`MIN_COMPLETION_RATE` is left in place, unused by the test that used to read it.** The taskblock
  says propose, do not remove. **The proposal: retire it.** Nothing reads it as a gate now, and a
  constant that no longer gates anything but still looks like a threshold is the kind of thing a
  future reader trusts. `CompletionSampler.should_escalate` and `escalation_probability` still use it
  and still have their own tests, so the escalation path is unaffected either way.

- **Pass B's headline saving does not exist, and I did not manufacture it.** The pass is written as
  "thirteen bout-building files play their own bouts — point them at the corpus, ~200–250 s". The
  corpus hands out **outcome records**; those files need **live boards**. This is not my inference —
  `BoutCorpus`'s own header, written when taskblock-48 built it, says so outright: *"There is no
  accessor for a live board here at all; a test that needs one builds its own, which is what the
  eight other bout-building files already do **and why they are not candidates for this**."* Two
  files converted; the rest keep their own bouts, which is the audit's "hand-built is right" outcome.

- **The two conversions that did land came from different levers than the pass names.** The suite's
  most expensive file went **94 s → 41 s** by making *sample size a parameter*, not by adopting the
  corpus — its test drives a verb that does its own sampling, and every assertion in it is about the
  shape of the report. `test_watched_run` was the one genuine corpus adoption: it played a seed
  headless *and* watched in order to compare them, and the headless half is exactly what the corpus
  already recorded.

- **Bounding a horizon is allowed; shopping for a cheap seed is not.** Taskblock-48 declined to
  shorten `test_ai_batch_yield` because "comparing a shorter one would mean seed-shopping for a cheap
  map and calling it a saving" — correct, and it rules out a different move than the one taken here.
  `CompletionSampler.run_seed` now takes a turn cap, and the determinism test runs the **same seed**
  to a bounded horizon. The map is whatever the seed says; the run just stops earlier.

- **Adopting the corpus makes a targeted run of a corpus reader slower, and that is a real cost.**
  `./run_tests.sh test_watched_run.gd` went 18.2 s → 49.3 s, because in isolation that file becomes
  the first toucher and pays for the whole corpus. Pass D then shrank the corpus to one bout and the
  regression went away — but the ordering matters: **corpus adoption before Pass D would have made
  the edit loop worse for every file it touched.**

- **`HulkTheme.build()` was left uncached**, though it is the single biggest remaining lever
  (`test_spectator_overlay.gd`, 32.4 s, 37 scene builds, zero bouts). Caching the theme would collapse
  `ui_builds` — a counter the work budget gates on and which taskblock-48 added specifically to make
  view-only cost visible — from 344 to about 1. That is trading a measurement away for seconds, and
  it is a supervisor call rather than mine.

## Tests that failed, then were corrected

1. **A hidden assertion was checking a constant against itself.** `test_the_in_window_verb_reports_the_
   same_sample_and_changes_nothing` compared the completion count against `SAMPLE_SEEDS` while its own
   failure message claimed to check "the summary counts the rows it printed". It would have passed a
   formatter that printed a different number of rows than it summarised — the exact defect it exists
   to catch. Found only because shrinking the sample to one seed made the two numbers disagree. It
   compares against the rows now.

2. **Two runtime errors presented as a 600 s hang, not a red test.** Changing the corpus's shape left
   `third["counted"]` and `mine["rate"]` reading keys that no longer exist. Under `-d` a missing
   dictionary key is a **Debugger Break**, so the run stopped at a `debug>` prompt with no verdict and
   sat there until it was killed. Taskblock-48 recorded this hazard; this is the first time it cost me
   a full timeout, and it is worth restating because the symptom looks nothing like the cause.

3. **`gdlint` caught a constant declared below the functions** (`class-definitions-order`) — the full
   gate refuses to run at all on a lint failure, so this presented as an empty gate rather than a
   message. Moved up with the other constants.

## Open questions

- **The five-minute acceptance is not met: 332.4 s.** What is left, measured, in order:

  | file | cost | bouts | why it is still expensive |
  |---|---|---|---|
  | `test_ai_batch_yield.gd` | 47.6 s | 3 | bout *length* — taskblock-48 measured the pacer at 6% and cut nothing |
  | `test_completion_sampler.gd` | 40.5 s | 3 | one bout to the 100-turn cap, inside the verb under test |
  | `test_spectator_overlay.gd` | 32.4 s | 0 | 37 real scene builds; see the `HulkTheme` note above |
  | `test_map_gen.gd` + `_raised_rooms` | 38.9 s | 0 | seed sweeps over generated maps |
  | `test_suite_run.gd` + `test_run_suite.gd` | 33.8 s | 0 | real subprocesses |

  Reaching 300 s needs ~33 s from that list. **Every entry has a reason it costs what it does**, and
  three of them are guarded by decisions taken deliberately in earlier blocks.

- **Pass E2's premise does not survive contact, and I stopped rather than force it.** It expects the
  two subprocess clusters to merge — "several of these spawn a real subprocess each; one spawn serves
  the cluster". They do not: the spawns differ *by design*. `test_the_launcher_agrees_with_the_shell_
  about_the_same_rung` runs the same file through `OS.execute` **and** through `SuiteRun` precisely
  because they are different code paths, and the probe pair sets the force-failure variable to `1` in
  one process and `""` in another — the both-directions property this project has been burned by
  losing. Merging them would buy seconds by deleting the thing being tested.

- **Passes C, E and F are not started.** C (the scripted corpus) is the one I would do next: it is the
  only remaining item that could move the 133 hand-built files, and its stated third outcome —
  *hand-built is quietly wrong, the fixture drifted from what the game produces* — is the one likely
  to find real defects rather than seconds.

- **`test_full_mission.gd`'s turns exclusion may now be removable.** `SuiteBudget.TURNS_EXCLUDED`
  exists because that file seeded from the clock; it now plays one bout in the healthy case and its
  turn count is small and stable. Removing the exclusion would put the file back under the budget it
  was carved out of — worth doing once a few runs confirm the new spread, not on one measurement.
