# TEST-AUDIT.md — How to audit the suite

**Not part of the workflow.** Nothing in the taskblock cadence runs this, and no pass is expected to
produce or update the CSV. It is a tool the supervisor reaches for when a question about the suite comes
up — run it deliberately, act on it, let it go stale. **If it ever appears in `CLAUDE.md`'s workflow
steps or in a taskblock's standing acceptance, that is the mistake.**

## Where it lives, and how the coupling was broken (taskblock-53 Pass A)

**Everything the audit is lives in `res://audit/`** — the CSV, its checks
(`test_suite_audit_csv.gd`), and the `audit_rules.py` helper that reads and writes the judgement
columns. Nothing under `res://test/` reads any of it, and nothing in `src/` imports it.

**Its own entry point.** The ordinary suite runs `--dir=res://test`, so the audit is never in scope.
Run it deliberately, by pointing the same runner at its own directory:

```
godot --headless --path . -s res://tools/run_suite.gd -- --dir=res://audit
```

Regenerating the mechanical columns is still `WRITE_PROFILE=1 ./run_tests.sh`, which writes
`res://audit/suite_audit.csv` alongside the profile. Then fill the judgement columns — see the
procedure below.

**It is deletable, and that is asserted rather than asserted-to-be-true.** `res://audit/` can be
removed outright and the ordinary suite still passes; the acceptance for the pass that separated it was
to remove it, run, and restore. `test_suite_profile_consistency.gd` keeps it that way by scanning every
`.gd` under `res://test/` for a reference to the audit tree — comment lines stripped, because prose
naming the path is documentation and only code is a dependency.

**What used to couple them, and why it had to go.** The audit CSV owned the assertion that per-test
counters sum to the file-level totals, which made a *committed snapshot an input to the ordinary
suite*: add a test to a file the snapshot covered and the gate went red until someone regenerated both.
taskblock-52 hit exactly that — a fresh `suite_profile.json` and a stale CSV cannot coexist, so the
CSV's deliberate staleness could not be preserved.

**The assertion was kept and re-pointed, not deleted.** It is the load-bearing check *of the profiler*,
so it now gates the profiler against itself: `suite_profile.json` carries both a per-file `files` array
and a `totals` dictionary, and summing the first must reproduce the second. Same failure caught, no
snapshot involved. It lives in `test/unit/test_suite_profile_consistency.gd`, with two companions the
sum alone cannot catch — that no total exists without a per-file source, and that identity fields
(`path`, `script`, `test`, `order`) never become totals. That last one is the exact leak that once put
`order` (2 953 665) into a committed profile's totals as though it were work.

**A failing audit run is a report, not a broken build.** The first run after separation reports
**2668 rows against 2665 declared tests** — the three-test drift from moving its own checks out of the
suite. That is the tool working: `test_the_csv_has_one_row_per_declared_test` failing *is* the signal
"regenerate before you trust this". It gates nothing, and no pass is obliged to make it green.

**The audit still has to compile.** `tools/checkpoints/parse_guard.gd` covers `res://audit/` for the
same reason it covers `tools/`: nothing runs it on a schedule, so nothing else would notice it rotting,
and the next audit could be six months away. A **missing** audit tree contributes zero paths rather
than an error — deleting it is legitimate, so it cannot be what breaks the guard.

A **one-time, repeatable** procedure. Not a living document, and the CSV it produces is not maintained
— it is a snapshot taken to answer a question, acted on, and allowed to go stale. Re-run it when the
question comes back.

**What it is for:** finding tests that cost more than they are worth, tests that guard nothing another
test does not already guard, and tests whose names no longer describe what they do.

---

## The artifact

One row per test. **Never per file** — a per-file summary is a directory listing with extra steps, and
the interesting questions are inside files. *Why are these forty tests in one file? Why are these three
separate?* Those are only visible per test.

```csv
origin_file,test_name,description,usec,bouts,turns,candidates,floods,plans,shot_planes,rule_guarded
```

| Column | Source | Notes |
|---|---|---|
| `origin_file` | mechanical | path relative to `test/` |
| `test_name` | mechanical | the `func test_…` name, unmodified |
| `description` | judgement | **usually empty — see below** |
| `usec` | per-test profiler | wall-clock for that test alone |
| `bouts`, `turns`, `candidates`, `floods`, `plans`, `shot_planes` | work counters | how much work the test actually does |
| `rule_guarded` | judgement | **the rule, not the test — see below** |

CSV so it can be sorted, filtered and pivoted outside the repo. It is an input to a decision, not a
document to read top to bottom.

---

## The two judgement columns

Everything else is mechanical. These two are the audit.

### `description` — leave it empty unless something is wrong

**The test names in this repo are already sentences.** `test_depth_cap_of_zero_stops_a_deflection_from_
spawning_any_ricochet` needs no gloss, and writing one produces a worse copy of a better name.

Fill this column only when:

- **the name does not say what the test checks** — it is vague, abbreviated, or names a function
  instead of a behaviour; or
- **the test does not do what the name says.** The name has drifted from the assertions, or the test was
  extended and the name was not.

**A filled cell is a finding, not documentation.** The second case in particular is a defect: either the
name lies or the test drifted, and both mislead everyone who greps for coverage later. Expect this
column to be mostly empty. If it is mostly full, the column is being misused.

### `rule_guarded` — the rule, not the test

Write the **system rule** the test defends, at a level above the test itself. Many tests will share a
rule. **That is the point** — sorting by this column is what makes redundancy visible.

| test | ✗ restatement | ✓ rule |
|---|---|---|
| `test_depth_cap_of_zero_stops_a_deflection_from_spawning_any_ricochet` | "depth cap of zero stops ricochets" | ricochet depth caps bound deflection chains |
| `test_a_ray_over_a_flat_neighbor_of_a_raised_cell_stays_at_ground_level` | "rays over flat neighbours stay at ground level" | ray height follows the surface it passes over |

If every row has a unique rule, the column was written as a paraphrase and the audit produced nothing.
**Prefer reusing an existing rule string over inventing a near-duplicate** — near-duplicates are how a
cluster hides.

---

## The third judgement column — `outcome`, on the fixture census (taskblock-68)

**A second artifact, and a different question.** `suite_audit.csv` asks *what does this test cost
and what rule does it guard*. `audit/fixture_census.csv` asks *is this file's hand-built fixture
correct, or is it hiding something* — a **per-file** question, because the fixture is a property of
the file rather than of any one test. Same judgement-column discipline, same carried-forward
regeneration, one row per file.

**Why the question exists.** A cost probe measured a **one-box** body, reported 41 usec per unit,
and the supervisor's next live session came back at **13 fps** — an assembled shell is 48 boxes and
`placements_aabb` costs eight corner transforms per box (`BR32.05`'s archive entry). The suite was
green throughout, and nothing in it could have said otherwise.

**Every classified fixture is exactly one of three.** The classification set is the files that call
`Part.new()`; a file that never builds a `Part` has no fixture to classify.

| | meaning | action |
|---|---|---|
| **`CORRECT`** | The rule under test does not involve a body's structure. A hand-built `Part` is the *right* fixture — narrower, faster, and it fails for one reason. | Leave it, and **say so in the row.** An unexplained hand-built fixture is what makes the next auditor re-derive all of this. |
| **`AVOIDING`** | Hand-built to dodge cost or setup, not because the rule is structure-free. It would pass against a real unit; nobody tried. | Move it onto a real definition, or record why the cost is not worth it. |
| **`DRIFTED`** | **The test passes against a unit that could not occur.** A real unit breaks it, or the fixture asserts something the game's own data contradicts. | The outcome worth finding. It is what produced the 13 fps. |

### The line between `DRIFTED` and an instrument artefact

The obvious rule — *substitute a real unit; if the file goes red it is `DRIFTED`* — does not
survive contact. The substitution drops whatever the fixture helper parameterised and changes the
weapon under the test, so most red files are red for reasons that say nothing about the fixture.
taskblock-68 drew the line here, and it is the reusable part:

> **A broken assertion is `DRIFTED` when it is a claim about the game. It is an artefact when it is
> a restatement of the fixture's own inputs.**

`assert_eq(rows.size(), 3)`, where 3 is the number of parts the fixture just authored, restates an
input — it would be equally true of any fixture and says nothing about the game. But `assert_eq(
real_hit.part.id, &"wall", "the real plane really does resolve to the wall")` is a claim about how
the game resolves a shot, and a real shell contradicts it.

**The corollary is that `AVOIDING` absorbs most of the interesting middle.** A fixture whose rule
*does* involve structure but which is only ever exercised at trivial scale — one part, one row, one
socket — is `AVOIDING`, not `CORRECT` and not `DRIFTED`.

### The three instruments, all committed and all regenerable

- **`audit/fixture_census.gd`** -> `fixture_census.csv`. `shape` (`no_unit` / `real_unit` /
  `hand_built`) narrows the classification set to the candidates; `hand_built` is the candidate set.
- **the borrowed-id scan**, in the same emitter -> `fixture_conflicts.csv`. A test that writes
  `gun.id = &"pistol"` and then `gun.damage = 20.0` has authored a pistol that does not exist. This
  settles the half of `DRIFTED` that a scan can settle. **A conflict is a fact, not a verdict** —
  borrowing a real id as a readable label is ordinary and correct, and is what most rows are.
- **`audit/substitute_real_unit.py`** -> `substitution_probe.jsonl`. Replaces a candidate's single
  `-> Unit` helper with `RealUnit.build` and runs it. Applicable only to files with exactly one
  such helper, and **it emits no verdict** — see the line above.

**`test/support/real_unit.gd` is what "a real unit" means.** One checked constructor: it validates
through `DeepStrike.validate_assembly` and asserts the box count, so a degenerate assembly fails
the calling test at the point of construction instead of being handed back to be measured.

---

## Procedure

1. **Regenerate the mechanical columns.** The per-test profiler emits everything except the two
   judgement columns. Never hand-transcribe a number that a tool can emit.
2. **Fill `rule_guarded` file by file**, reusing rule strings aggressively. Working within a file keeps
   related tests in view; reusing strings across files is where the value is.
3. **Fill `description` only on the two triggers above.**
4. **Sort by `rule_guarded` and read the clusters.** Every cluster is a question: do these tests guard
   the same rule from different angles, or the same rule the same way?
5. **Sort by `usec` and by `turns`.** Expensive rows guarding a rule that a cheap row also guards are
   the audit's whole output.
6. **Act, using the cut rule below.**

---

## The cut rule

Carried from taskblock-47 Pass E3, and it is what gives the audit teeth:

> **A test may only be cut if breaking the rule it guards makes a *different* test fail.**

**Demonstrate it — do not assert it.** Break the underlying behaviour, confirm something else goes red,
restore, then delete. Record the covering test's name alongside the cut. If nothing else goes red, the
test is not redundant: it is the only guard, and it stays regardless of what it costs.

taskblock-39 lost six tests with no successor because a redundant test and the only test of a real rule
look identical in a diff. This rule exists because of that.

**A list of deletions without a covering-test column is not reviewable.** Neither is a merge that loses
which fact broke — merged tests keep distinct assertion messages.

---

## What the audit is not

- **Not a coverage report.** It says what tests exist and what they cost, not what is untested. A rule
  nobody wrote a test for does not appear.
- **Not maintained.** Nothing regenerates it on a schedule and nothing gates on it. It goes stale
  immediately and that is fine.
- **Not authority.** `rule_guarded` is one reader's classification. It is a lens for spotting clusters,
  not a specification of the system — `docs/NN` is that.
