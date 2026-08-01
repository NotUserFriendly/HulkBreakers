# Taskblock 49 — Per-test cost, and the suite audit

*Produces the artifact `docs/TEST-AUDIT.md` describes. Depends on taskblock-48 closing.*

**Run this after taskblock-48's Passes C and D land.** Those collapse the sampler and address the two
outliers, which changes per-test cost across the most expensive files in the suite. An audit taken
before them describes a suite that no longer exists.

Two passes: make per-test cost measurable, then produce the index.

---

# PASS A — Per-test profiling

`profile_suite.gd` snapshots the work counters at `start_script` / `end_script`, so today's granularity
is **per file**. The audit needs per test. Same pattern, one level down — GUT emits test-level
signals alongside the script-level ones already hooked.

- **Snapshot deltas per test**, for every counter the file-level profiler already tracks: `usec`,
  `bouts`, `turns`, `candidates`, `floods`, `lookahead_fields`, `plans`, `shot_planes`.
- **State where setup lands, and be explicit about it.** Whether `before_each` runs inside or outside
  the test's measurement window decides whether a shared fixture is attributed to the test that uses it
  or to nobody. Either is defensible; **an unstated choice is not**, because it silently changes which
  tests look expensive. Write it in the profiler's header, not just the report.
- **Emit CSV**, with the two judgement columns present and empty. Pass B fills them; nothing
  hand-transcribes a number a tool can emit.
- **Keep the file-level profile working.** It is what the work budgets read, and this pass adds
  granularity rather than replacing the artifact.

**TESTS:** per-test counts sum to the file-level counts already recorded (**this is the acceptance** —
if they disagree, one of the two is wrong and the audit inherits it); a test that builds no bout reports
zero bouts; the CSV parses and has one row per `func test_` in the suite.

---

# PASS B — Fill the index

Follow `docs/TEST-AUDIT.md`. Two columns are judgement; the rest come from Pass A.

## B1. `rule_guarded` — reuse strings aggressively

Write the **system rule** the test defends, above the level of the test itself. **Reusing an existing
rule string is the goal, not a shortcut** — sorting by this column is what makes clusters visible, and a
near-duplicate string is how a cluster hides.

If every row ends up with a unique rule, the column was written as a paraphrase of the test name and the
audit has produced nothing. Check this before finishing: **the count of distinct rules should be a small
fraction of 2366.**

## B2. `description` — a defect list, not documentation

Leave it empty unless the name does not say what the test checks, **or the test does not do what the
name says.** The second is a real defect — the name lies, or the test drifted and the name did not
follow — and it misleads everyone who greps for coverage afterwards.

**Expect this column to be mostly empty.** The names in this repo are already sentences. If it comes
back mostly full, it is being used to restate names and the rows are worthless.

## B3. Report the questions, not just the file

The CSV is an input to a decision. In the report, surface:

- **The largest `rule_guarded` clusters** — where several tests defend one rule. Each is a question: the
  same rule from different angles, or the same rule the same way?
- **Expensive rows sharing a rule with a cheap row.** The audit's whole output.
- **Every filled `description`**, listed. That is the defect list.
- **Files whose tests span many unrelated rules**, and files whose tests all share one. Both are shape
  questions: why is this one file, and why are these three separate?

**Cut nothing in this block.** The audit produces evidence; acting on it is a supervisor decision and a
later block, under `TEST-AUDIT.md`'s cut rule — *a test may only be cut if breaking the rule it guards
makes a different test fail*, demonstrated rather than asserted, with the covering test recorded.

**TESTS:** none beyond Pass A's. This pass produces a document, and a test asserting that a
classification is correct would be asserting one reader's judgement.

---

# Not this block's job

- **Cutting, merging or retargeting anything.** Evidence first.
- **`docs/TEST-AUDIT.md` itself** — supplied; refine it only if doing the audit shows the procedure is
  wrong, and say so if it does.
- **Coverage.** The index says what exists and what it costs, never what is untested.
- **Maintaining the CSV.** It is a snapshot. Nothing regenerates it and nothing gates on it.
