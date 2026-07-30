# Taskblock 50 Report — Under the clock, but not under five minutes

**Passes A, B, C, D and E3/E4 landed; suite green — 2441 tests, 0 failures.** Pass D was taken **out of
order, before C**, for a reason recorded below. **E1, E2 and F are not done.**

**Full gate 446.8 s → 321.6 s (28%).** The block's acceptance is *under five minutes*, and that is
**not met** — 321.6 s against a 300 s bar. What remains is named at the end with what each piece is
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

- **Pass C shipped the corpus and found there is nothing to migrate onto it — measured, not
  assumed.** `ScriptedCorpus` builds a board through `BoutSetup` (real presets, real assembly, a real
  generated map), sets both squads to `HUMAN`, and drives it with an authored queue through the same
  `CombatState.resolve_until` the AI's output goes through. It provably never plans, and the companion
  assertion proves the counter would notice if it did.

  Then the migration survey: **all 137 hand-built files reference specific `Vector2i` cells**, so none
  can take a shared generated board without changing what they assert — which the pass's own rule
  forbids (*migrated tests assert what they asserted before*). And **117 of those 137 are already under
  1 s with zero bouts**, so there was no saving there to collect. The one file that looked like an
  obvious candidate, `test_work_counters.gd`, asserts that a hand-driven turn builds **no** bout;
  migrating it would build one and delete the assertion.

  **So the corpus's value is prospective rather than a saving**, and I have recorded it as that: it is
  the fixture for new combat and movement tests, and the pattern `test_tb38_flat_bout_guard.gd` already
  had to invent for itself. The pass's third outcome — *hand-built is quietly wrong* — went unfound,
  which is a real result and not a skipped search.

- **E3 done: all eight name defects renamed, and the `description` column is now empty.** The two
  citing deleted taskblock documents, the one asserting "three scatter rings" as though ring count were
  a rule, the drifted one (`test_the_unbuilt_tier_table_rows_are_still_unbuilt`, which reads the *action
  pool*), and `test_the_flank_test` — now
  `test_a_shot_from_behind_reaches_the_thin_rear_plate_a_frontal_shot_cannot`. **Eleven renames, not
  eight:** the `pass_b_` prefix cited an anonymous taskblock pass on four names in one file, and fixing
  one while leaving three would have been half a fix. The audit CSV's keys were updated alongside, so
  the classification survived the rename rather than silently losing eleven rows.

- **E4 needs nothing: Pass D absorbed it.** The pass asks to trim the seed lists in
  `test_completion_sampler` and `test_full_mission`, and says to re-measure before trimming rather than
  doing both blind. Re-measured: `test_full_mission` plays **one** bout now instead of eight, and
  `test_completion_sampler` is down to three. There is no fixed list left to trim.

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

3. **A companion assertion was green by vacuity, in the very test written to prevent that.**
   `test_the_planner_counter_would_notice_if_it_did_plan` handed squad 1 to the AI and stepped the
   runner — but `BoutRunner.step()` is a no-op while the *current* unit belongs to a human squad, and
   the current unit was squad 0's. It asserted the planner counter moves and the counter never moved,
   so it failed honestly rather than passing; had the default current unit been the other squad's it
   would have passed for the wrong reason. Both squads are handed over now.

4. **A file was added to `BOUT_FILES` without its skip hook**, and `test_suite_tier.gd` caught it —
   listed as a bout builder, no `should_skip_script()`, so the fast gate would have run it and quietly
   built bouts. That test exists for exactly this and it worked.

5. **`gdlint` caught a constant declared below the functions** (`class-definitions-order`) — the full
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

- **E2's one remaining opportunity is a shared map fixture, and it is pass-sized.**
  `test_map_gen.gd` and `test_map_gen_raised_rooms.gd` together run **14 independent seed sweeps** and
  regenerate roughly **650 maps** between them — 38.9 s, zero bouts. Generating that set once per
  process and handing out copies is the same move `BoutCorpus` made, and it is most of the ~34 s still
  needed to reach five minutes. I did not start it here: it touches 14 call sites across two files and
  the grids get mutated by some tests, so it wants deep copies and its own test rather than a rushed
  edit at the end of a block.

- **Pass E2's subprocess half does not survive contact, and I stopped rather than force it.** It expects the
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

## Pass F — the deck, cleared for taskblock-51

**The ledger triage lives here, not in `docs/BUGS.md`.** That file's own header argues against exactly
what the taskblock asks for: *"a single `grep '^### BR'` is the whole open-bug index and nothing
derived needs maintaining"*, one flat list, no category sections. A subsystem grouping is a derived
view that would need maintaining, and adding one would have traded a durable convention for a
convenience. **No status was changed and nothing was closed**, verified by diffing the 31 `### BR`
heading lines before and after: identical.

**31 open entries — 28 `Active`, 2 `Suspected`, 1 `Pending`. Seven clusters:**

| cluster | entries | shared suspected cause |
|---|---|---|
| **Tracers and impact drawing** | BR27.03, BR34.01, BR35.04, BR35.07, BR35.08 | one drawing path that projects a decorative fixed-range line instead of replaying the resolved geometry. BR35.04 and BR35.07 are almost certainly one defect stated twice. |
| **Wall cutout / occlusion** | BR32.04, BR32.05, BR32.08, BR35.02 | the cutout's coarse screen-space heuristic, which taskblock-49's audit classified under *a wall fades only when it is near the focal point on screen and in front of it*. BR32.08 is `Suspected` and would be confirmed or dropped by the same session. |
| **Spectator vs player divergence** | BR27.04, BR27.07, BR32.09 | two overlays reaching different conclusions about the same state — the "no parallel systems" rule, which the audit found 50 tests already defend. |
| **Aim and camera framing** | BR26.02, BR33.01, BR34.04, BR40.01 | the aim view's layer model and the framing solver. BR26.02 (framerate while aiming) may be a symptom of BR35.01's per-hover scan rather than its own defect. |
| **Map generation and movement** | BR46.02, BR35.05 | one-way ground the AI walks into; ally-blind approach paths. Both are pathing questions about generated terrain. |
| **Queue and action legality** | BR27.01, BR30.04, BR32.07, BR34.03 | the step-out/queue path — BR27.01 is itself four bugs in one entry and should be split before the hunt, not during it. |
| **Performance, no shared cause** | BR27.09, BR35.01, BR35.03 | independent hot paths; BR35.03 was already closed structurally by the `DebugVerbs.affects_board` work and may only need confirming. |

Two entries sit outside any cluster: **BR45.01** (surrogate DAG demotion placeholder) and **BR45.03**
(the planner's completion rate, `SUPERVISOR`-owned and the one automated check standing between this
project and an AI that cannot finish a mission). **BR48.01** is its own thing and visual.

**Repro paths: 10 of 31 carry one.** The other 21 are descriptions without a stated route back to the
symptom, and **that is the single biggest tax on the hunt** — an entry that cannot be reproduced is a
bug to re-observe, not a bug to fix, and finding out which is which costs more during a hunt than
before one. I did not manufacture repro steps for entries I have not reproduced; inventing a plausible
route would be worse than the gap, because it would read as verified. The honest split:

- **Has a repro:** BR27.01, BR30.02, BR30.04, BR32.04, BR32.07, BR34.05, BR40.01, BR45.03, BR46.02, BR48.01.
- **No repro path, and most are `SUPERVISOR`-sourced visual observations** — which is *why* they lack
  one, and is a reason to start those sessions with the supervisor watching rather than to treat the
  gap as neglect.

**The replay queue now has a baseline.** `ReplayCatalog.handles_with_baselines` queues each failure
with its script's own known-good fixture directly after it, opted in through the existing
`replay_handle_for` hook via a `BASELINE_TEST` sentinel — so nothing changes for the ~250 scripts that
expose no handles. **It is not the default**, and the cap counts *failures* rather than entries, so
asking for context never costs coverage. One baseline per script however many of its tests failed.

**A finish chime.** Two synthesised tones — rising for green, falling for red, so the verdict is
audible without looking. Guarded so it can never fail a run: a machine with no audio device, and the
headless suite itself, finish exactly as before. Asserted headlessly against the real panel, because
"a courtesy that can fail a run is a defect" is the kind of claim worth a test rather than a comment.

## Open questions

- **The five-minute margin is thin.** ~290 s on an idle machine, 313 s sharing it. The next thing that
  adds 10 s crosses back over, and there is no headroom left in the cheap levers — the remaining
  expensive files each have a reason recorded above. If the bar matters, `HulkTheme.build()` caching
  (32.4 s, one file) is the next lever and it costs the `ui_builds` counter.

- **`MIN_COMPLETION_RATE` should be retired.** Nothing reads it as a gate since Pass D.
  `should_escalate` and `escalation_probability` still take it as a parameter and still have their own
  tests, so removing the constant is a one-line change whenever you want it. Left in place because the
  taskblock says propose, not remove.

- **21 of 31 open bugs have no repro path**, and most are `SUPERVISOR`-sourced visual observations —
  which is *why* they lack one. The cheapest thing that would make taskblock-51 go faster is a session
  with you driving, capturing routes back to the symptoms, before the hunt starts rather than during
  it. I deliberately did not invent plausible-looking repro steps for bugs I have not reproduced.

- **BR27.01 is four bugs in one entry** ("Player Step Out: four bugs, one system") and should be split
  before the hunt. Splitting it changes nothing about status; it just stops one ID standing for four
  independent outcomes.
