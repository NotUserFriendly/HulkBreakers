# Taskblock 47 — The suite: measure it, tier it, watch it, cut it

*Depends on taskblock-46. No `PLAN.md` item — this is tooling debt, raised because taskblock-46 was
~45 minutes of coding and ~2 hours of testing.*

The suite went ~355 s → ~1370 s across one block and is now the dominant cost of doing work. Some of
that is honest: 2337 tests against a growing codebase, and the completion gate genuinely plays 20
bouts where the old pinned window played 12. The rest is a suite that has never been profiled, tiered,
or audited.

**Measure first.** This project has optimized an unprofiled function three times — taskblock-35,
taskblock-42 and taskblock-43 all worked on the wrong one, and taskblock-43's bench settled it in an
afternoon. Do not skip Pass A because the answer seems obvious.

One structural fact to start from: **23 of 241 test files run bouts at all**, and
`test/integration/test_full_mission.gd` is a *single test function* that plays 20 of them. The
expensive work is already isolated by directory, not smeared across the suite.

---

# PASS A — Profile the suite, change nothing

Per-file and per-test cost, in two currencies:

- **Wall-clock**, for humans deciding what to cut.
- **Deterministic work counts** — bouts played, turns resolved, actions scored, `ShotPlane` builds,
  pathfinder floods. These are exact and machine-independent, and Pass B gates on them.

**Output goes somewhere durable, not into a report.** `reports/` rolls at five blocks and this is a
baseline meant to be compared against for a long time. A committed file beside the suite, regenerated
by a `tools/` script.

**The profiler must not be expensive itself.** If instrumenting every test costs more than it reveals,
instrument per-file and say so.

**Report the top 20 by wall-clock and the top 20 by turns resolved separately.** They will not be the
same list, and the difference is the interesting part: a file that is slow without resolving turns is
slow for a reason worth understanding rather than a reason worth budgeting.

**TESTS:** the profiler produces identical work counts across runs (if it doesn't, the counts aren't
deterministic and Pass B has no foundation); it runs on the normal headless path.

---

# PASS B — A test for the tests: budget the work, not the seconds

**Gate on deterministic counts; report wall-clock alongside.** A wall-clock assertion is
machine-dependent — it flakes on a different laptop or a busy CPU, and the recorded response to a
flaky threshold in this project is to raise the constant, which is how the completion floor nearly
died.

Work counts don't have that problem, and they name the cause. taskblock-46's search-memory fix took
mean turns-to-complete 19.1 → 26.8 and every bout-running test inherited it. **A turns-resolved budget
would have gone red on the commit that caused it.** A seconds budget would have gone red three commits
later, on whichever change happened to cross the line.

- Budgets per tier and for the suite as a whole: total bouts played, total turns resolved.
- **Headroom stated with its reasoning**, beside the constant, in the shape
  `completion_sampler.gd`'s `SAMPLE_SEEDS` note already uses.
- The failure message names the offending file and the delta, not just the total.

**This is a ratchet, not a ceiling.** Legitimate growth means raising the budget deliberately and
saying why in the same commit — the point is that it becomes a decision instead of a drift.

**TESTS:** exceeding a budget fails with the file and delta named; the budget test itself is cheap
(it reads counters, it does not re-run anything).

---

# PASS C — Tier the gate

**Fast gate — the per-change loop.** Everything that doesn't run a bout. This is what runs after every
edit, and it should be the overwhelming majority of the 2337 tests at a small fraction of the cost.

**Full gate — the per-pass loop.** Everything, including bouts. Green before a pass is committed.

**The completion check stays in the gate at a smaller `n`.** taskblock-46 sized `SAMPLE_SEEDS` at 20
from measured escalation cost; a smaller sample escalates more often but the escalation is no longer
in `run_tests.sh`, so the worst case is bounded. **Re-derive the number rather than picking one** —
`CompletionSampler.escalation_probability` already exists and the table in that file is the precedent.
Note the non-monotonicity CC found: `n=12` is worse than `n=10` because the threshold is an integer
count.

**The 100-seed escalation moves to `tools/`, out of every gate.** Per the supervisor: the watched run
(Pass D) comes first, and the escalation is what you reach for when watching didn't answer it. Its
remaining job is producing a defensible number for `BR45.03`'s closure — real, but occasional.

**TESTS:** the fast gate runs zero bouts (assert on Pass A's counter, not on a directory glob — a
glob goes stale the moment someone adds a bout to a unit test); both gates are invokable
independently; the full gate is a superset of the fast one.

---

# PASS D — The watched run

**A seed is already a complete reproduction handle.** `CompletionSampler.run_seed(map_seed)` takes
nothing but the seed — presets and rosters are constants inside it, and it builds through
`BoutSetup.build_bout`, the same path the bout builder uses. So a failing seed replays exactly, with
no recording, no capture format, and no replay machinery. **Build on that; do not invent an artifact.**

- **Live per-seed table**, filling in as the run proceeds — seed, outcome, turns. The 15-of-20 case is
  the whole point: the pattern is visible at seed 5, and the run can be killed there.
- **Say on screen what is being checked.** The completion condition, the turn cap, and what
  `EXTRACTED` / `TERMINATED` / `STRANDED` each mean. A pass/fail with an unexplained criterion is
  something to interpret rather than read.
- **Take a seed list and play those bouts in sequence, watched.** Give it `[3, 7, 11]` and it plays
  each as a real rendered bout, in order, with the same controls a normal bout has. This is the
  connection between "the test failed" and "here is what happened" — and it is the reason the
  escalation can move out of the gate.
- **Stop, skip and re-watch** without restarting the run.

Build it on the `DebugVerbs` row taskblock-46 added rather than a bespoke surface — that table is
already the seam that turns "a thing you can do from the window" into typed parameters.

**TESTS:** the seed list plays in the order given; a watched seed produces the same outcome the
headless path reported for it (**this is the pass's real acceptance** — if watched and headless
disagree, one of them is lying and everything built on the sampler is suspect); killing a run
mid-sequence leaves no state behind.

---

# PASS E — The audit: retarget, merge, then cut

In that order, because the risk rises at each step.

## E1. Retarget — the big, safe win

**A test that runs a bout to observe something a scripted action queue would show is paying for a
planner it does not need.** taskblock-46 has the precedent: the tb38 flat-bout guard was narrowed from
a planner-driven bout to a scripted action queue through the same `resolve_until`, and it still guards
movement, per-tile facing, AP accounting, turn structure and the log's shape.

Go through the 23 bout-running files and ask of each: **is the planner the subject, or the scaffolding?**
Where it's scaffolding, script the queue. Same coverage, none of the AI cost, and nothing is lost —
which is why this comes before anything that deletes.

## E2. Merge — cheap and low risk

Tests in one file that build the same fixture and assert adjacent facts can become one test with
several assertions. **For bout tests the fixture *is* the cost**, so merging four tests that each
build the same board is close to a 4× saving on that file.

Keep the assertion messages distinct enough that a failure still names which fact broke — a merged
test that reports "something in here is wrong" has traded time for diagnosis.

## E3. Cut — and the rule that makes it safe

`PLAN.md` states the hazard exactly: **deleting a redundant test and deleting the only test of a real
rule look identical in the diff.** taskblock-39 hit it, and six tests went with no successor.

> **A test may only be cut if breaking the rule it guards makes a *different* test fail.**

Demonstrate it, don't assert it: break the underlying behaviour, confirm something else goes red,
restore, then delete. **Record the covering test's name in the commit message.** If nothing else goes
red, the test isn't redundant — it's the only guard, and it stays regardless of what it costs.

**Report every cut with its covering test.** A list of deletions without that column is not reviewable.

**TESTS:** total assertion count does not fall in proportion to the test count — a large drop in
assertions means coverage left with the redundancy; the work-count budgets from Pass B fall
measurably, which is the point of the pass.

---

# Acceptance

- Pass A's profile is committed and regenerable.
- Pass B's budgets fail on a deliberate regression, naming the file.
- The fast gate runs zero bouts and is the per-change loop.
- A failed seed can be watched, from the window, without a CC session.
- The suite's total turns-resolved is **materially** lower, and the report says by how much and from
  which pass. A wall-clock figure alongside it, marked as the softer number.

# Not this block's job

- **Changing what any test asserts.** Retarget, merge and cut — never weaken. A budget is not a reason
  to lower a floor.
- **`MIN_COMPLETION_RATE`.** It is 0.35 against a closure condition of 0.5 and that gap is `BR45.03`'s,
  not this block's.
- **BR46.02, ramps, or the pace/shutdown mitigation.** `PLAN.md`.
- **Authoring intelligence tiers.** `PLAN.md` NEXT item 2, behind Attributes.
