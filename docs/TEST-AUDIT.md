# TEST-AUDIT.md — How to audit the suite

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
