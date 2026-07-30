# Taskblock 49 Report — The suite, classified by the rule each test defends

**Passes A and B landed; suite green — 2431 tests, 0 failures, 487.5 s.** Pass A added per-test
profiling and emitted the audit CSV; Pass B filled both judgement columns for every row.

**2431 rows, 328 distinct rules — 13.5%.** `description` is filled on 8 rows (0.33%), all of them
name defects. Nothing was cut: this block produces evidence.

## Decisions made without asking

- **`rule_guarded` is written as a full sentence, commas and all** — *"a debug verb reuses the real
  gameplay path, never a shortcut"*. 711 of the 2431 rules contain a comma. The alternative was a
  comma-free label vocabulary that a naive reader could split, and it was rejected: letting the
  storage format dictate the classification is how the column becomes a set of tags nobody can read
  a question out of. The file is CSV, so it is now written and read as CSV.

- **One CSV codec, in `src/logic/`, rather than a splitter each in the writer and the reader.** The
  reader and writer disagreeing is exactly what went wrong (below), and two hand-rolled splitters is
  the same bug waiting again.

- **Regeneration now carries the judgement columns forward instead of blanking them.** The Pass A
  writer emitted both columns empty every time, which meant the next `WRITE_PROFILE=1` run silently
  destroyed 2424 hand-filled cells with a green suite either way. `TEST-AUDIT.md` says the artifact
  is not maintained and nothing gates on it — true, and not a reason to make the tool eat it. The
  merge is keyed on `(origin_file, test_name)`; a test that disappears simply drops its cells.

- **A cluster of one is reported, not smoothed away.** 12 rules have exactly one test. Some are
  genuine — `test_smoke`'s *"the suite runs at all"* should be alone — but they are also where a
  near-duplicate would hide, so they are listed rather than merged into a neighbour to flatter the
  ratio.

- **Two `description` triggers were read strictly.** The column is filled only where the name is
  vague or has drifted from the body — not where a name is merely terse. Eight cells, listed below.
  Had it been read loosely it would have run to hundreds, and `TEST-AUDIT.md` is explicit that a
  mostly-full `description` means the column is being misused.

## What the audit actually says

**The largest clusters are cross-cutting invariants, not redundancy.** The top three —
*"a degenerate input yields an empty result, never an error"* (89 tests, 60 files), *"one mechanism,
distinctly logged — no parallel systems"* (50 tests, 35 files), *"a real input event reaches the
control it lands on"* (39 tests, 13 files) — are each one rule applied to many different subjects.
They are cheap: the 89-test degenerate-input cluster costs **1.1 s in total**. Sorting by this column
does not find waste at the top; it finds the project's actual design pillars, which is a useful
answer but not the one the procedure was hunting.

**Cost concentrates in five rows, not across a cluster.** 476 s is attributed to tests; the four
most expensive rows are **102.3 s**, **62.6 s**, **49.8 s** and **20.0 s** — 49% of the total between
them. Each is the expensive member of a cluster whose other members are effectively free:

| Row | Cost | Rule (cluster size) | Cheapest peer |
|---|---|---|---|
| `test_completion_sampler::test_the_in_window_verb_reports_the_same_sample_and_changes_nothing` | 102.3 s | a shared fixture is played once and handed out as copies (7) | 0.001 s |
| `test_full_mission::test_bout_completion_rate_meets_the_measured_floor` | 62.6 s | the AI finishes missions at or above the measured floor (1) | **sole guard** |
| `test_ai_batch_yield::test_a_yielding_batch_produces_the_identical_bout` | 49.8 s | the same seed produces the same battle (28) | 0.000 s |
| `test_watched_run::test_a_watched_seed_matches_what_the_headless_path_reported` | 20.0 s | one mechanism, distinctly logged (50) | 0.000 s |

**The cheap peer does not cover the expensive one in any of these four**, which is why nothing was
cut. `test_repeated_runs_agree` costs nothing because it re-runs a scorer; it cannot tell you a
*bout* replays identically. The pattern the audit really surfaces is that **the expensive rows are
the ones that carry a rule end-to-end through a real bout, and their cheap clustermates carry the
same rule through a unit**. That is a coverage ladder, not duplication — but it is now visible, and
the question of how many rungs each rule needs is answerable per rule instead of per file.

**The 102.3 s row is the one worth a decision.** It guards the shared-corpus rule with a real
`CompletionSampler` window, and taskblock-48 built `BoutCorpus` precisely so this cost is paid once;
six other tests guard the same rule for 0.001 s each. Whether the in-window verb needs a real sample
or can read the corpus is a supervisor call, not a cut I should make.

**Two shape questions the file layout raises.** `test_attack_action.gd` spans **18 rules across 31
tests** — the widest in the suite, and a fair description of `AttackAction` itself being where
range, cover, elevation, provider, AP and the shot plane all meet. Against that,
`test_aim_view_dartboard_cache.gd` (9 tests) and `test_hit_volume_view_refresh.gd` (8 tests) are each
**one rule, one file** — cohesive, and also the shape that makes a whole file cuttable in one move if
its rule ever turns out to be covered elsewhere.

**Every filled `description` — the defect list:**

1. `unit/data/test_taskblock21_gun_data.gd::test_every_reference_gun_has_three_scatter_rings_middle_heaviest`
   — name asserts "three scatter rings" as though ring count were a system rule; `docs/00` says **N
   rings, never 3**. The data authors three; the test pins a content choice and the name reads as a
   constraint.
2. `unit/data/test_taskblock21_gun_data.gd::test_authored_ap_costs_match_the_taskblocks_own_numbers`
   — cites "the taskblock's own numbers"; taskblock files are archived and deleted, so it points at a
   document a reader cannot open.
3. `unit/debug/test_debug_verbs.gd::test_the_two_ambiguous_verbs_always_rebuild` — names neither verb
   nor the ambiguity; the docstring has to supply `move_object`/`remove_object`.
4. `unit/logic/ai/test_tier_and_profile_table.gd::test_the_unbuilt_tier_table_rows_are_still_unbuilt`
   — **drifted.** The body asserts four utility *actions* (`use_item`, `call_for_help`, `bait`,
   `ambush`) are absent from the authored pool. Nothing in it reads the tier table.
5. `unit/logic/test_camera_orbit_state.gd::test_pass_b_same_level_solve_is_pinned_as_a_regression_guard`
   — says only that something is "pinned", not which solve or which regression; the `pass_b` prefix
   cites an anonymous taskblock pass, which four names in that file share.
6. `unit/logic/test_inventory.gd::test_carried_mass_appendix_d_worked_example` — points at
   "appendix D" of an unnamed document.
7. `unit/logic/test_joints.gd::test_an_uncladded_joint_behaves_as_before_just_with_the_new_hp_default`
   — "as before" and "the new default" are relative to an unstated moment.
8. `unit/logic/test_reference_humanoid.gd::test_the_flank_test` — a label, not a sentence. Every
   other test in that file names its own assertion.

## Tests that failed, then were corrected

**Three defects, all mine, all in the tooling this block added — and the last two are the same
mistake made twice.**

1. **`tools/audit_rules.py` truncated the CSV before reading its own header.** `open(PATH, "w")`
   emptied the file, then `fieldnames()` re-read it and got `None`. It destroyed
   `test/suite_audit.csv` on the first write; restored from git. The tool now refuses to write a
   partial batch at all — a miss on any `(file, test)` key aborts the whole set, because writing the
   rest would leave the sweep looking finished with rows quietly unclassified.

2. **The audit test read `bouts` as 8697 against a true 56.** Filling `rule_guarded` with sentences
   put commas in the last column; the Python writer quoted them correctly and the GDScript reader
   split naively on `,`, shifting every numeric column one place right. **My own classification is
   what broke the test that reads it** — the column had been empty for its whole life, so no reader
   had ever met a quoted field. Fixed with `CsvLine`, one codec for both ends.

3. **The same file was written CRLF and read LF**, so the last header cell parsed as
   `rule_guarded\r` and every lookup of the real name raised — which under `-d` is a debugger break,
   not a red test, so it presented as a hang. Python's `csv` writer defaults to `\r\n`; the writer
   now pins `\n` and the reader normalises anyway.

4. **`FileAccess.open(AUDIT_PATH, WRITE)` truncated the file before `_render_audit_csv()` read it
   back to carry the judgement columns forward.** This is defect 1 again, in a different language,
   *after* I had already diagnosed and fixed it once — and it wiped all 2424 cells on the first
   `WRITE_PROFILE=1` run. The classification was recovered by merging the fresh mechanical columns
   against the committed file. The render now happens before the open, and the carry-forward is
   **demonstrated rather than asserted**: a full `WRITE_PROFILE=1` gate ran and the file came back
   with 2431/2431 rows still classified.

**Worth naming: three of the four are one bug — reading a file after opening it for writing.** It
survived a fix in Python and reappeared in GDScript ten minutes later, because I fixed the instance
and not the shape.

## Open questions

- **The audit's headline finding is not the one the procedure predicted.** `TEST-AUDIT.md` expects
  expensive rows sharing a rule with cheap ones to be the output — "the audit's whole output". They
  exist, but in every case checked the cheap peer guards the rule at unit level and the expensive one
  guards it through a real bout. So the cut rule (*breaking the rule must make a different test
  fail*) would **not** license those cuts: breaking bout-level determinism does not redden
  `test_repeated_runs_agree`. The lever the data actually offers is narrower — deciding, per rule,
  whether a bout-level rung is needed at all. Worth saying because the procedure is otherwise sound
  and I would rather flag the mismatch than quietly report a weaker finding as the expected one.

- **`test_the_in_window_verb_reports_the_same_sample_and_changes_nothing` at 102.3 s is 21% of the
  attributed suite.** Its rule already has six other guards. Whether it can read `BoutCorpus`
  instead of playing its own window is the single highest-value cut in the file, and it is a
  supervisor call under the cut rule.

- **`test_full_mission::test_bout_completion_rate_meets_the_measured_floor` is a 62.6 s sole guard**
  — the only test of *"the AI finishes missions at or above the measured floor"*. By the cut rule it
  stays regardless of cost. Recording it because a sole guard at that price is exactly the row
  someone will otherwise propose cutting on cost alone.

- **`MIN_COMPLETION_RATE` is still 0.35 against a measured 72%** (carried from taskblock-46, unchanged
  here).

- **Regenerating the CSV is now safe, but the audit is still a snapshot.** New tests arrive with
  empty judgement cells and nothing reddens — correct per `TEST-AUDIT.md`, and worth knowing: the
  classification decays quietly rather than loudly.
