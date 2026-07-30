# Taskblock 50 — Adopt the corpus, script the rest, and clear the deck for the hunt

*Acts on taskblock-49's audit. Depends on taskblock-48 and taskblock-49.*

**The objective is a number: a full run under five minutes, and never seen twice in one block.** The
suite is ~476 s. The audit found that reaching ~150 s **requires deleting nothing** — the largest single
item is a facility that exists and is unused.

taskblock-51 is the bug hunt. The last pass here clears the deck for it.

---

# PASS A — Retire `HULK` from the test and tooling vocabulary

`HULK_FAST_GATE`, `HULK_TEST_ROOT`, `HULK_FORCE_TEST_FAILURE` — the prefix namespaces **environment
variables**, which are global to the process, so a bare `FAST_GATE` could collide with anything else on
the machine. **Real job, wrong word.** `HB_` does it identically without spending a setting word on a
shell variable.

**`LootTable.HULK_SOURCE := &"hulk"` stays.** Loot sourced from the hulk is the word meaning what it
means — that is the use the vocabulary exists for.

Same shape and same acceptance as taskblock-40's `void` sweep: **a grep for `HULK` returns only
hulk-domain uses.** Comments and doc-comments included; a stale comment naming a retired variable is
what sends the next reader to a name that no longer exists.

**TESTS:** a guard test asserting the sweep is clean, scoped so the loot-domain use passes.

---

# PASS B — Adopt the corpus that already exists

**`CORPUS_READERS` has exactly one entry.** taskblock-48 Pass C built `BoutCorpus` and pointed
`test_bout_corpus.gd` at it. Meanwhile **thirteen other bout-building files play their own bouts — 56
bouts, 319 s, 67% of the suite.**

Point them at the corpus. **~200–250 s, and no test changes what it asserts**, so the cut rule does not
apply and nothing needs a covering test.

- **Hand out records, never live state** — a test mutating a cached `CombatState` corrupts every later
  reader and the failure surfaces somewhere unrelated.
- **A file that genuinely needs its own bout keeps it, and says why in a comment.** Some will: a test of
  a specific board is not a corpus reader. That is a finding to record, not a failure to work around.
- **`CORPUS_READERS` and `BOUT_FILES` must stay honest.** `suite_tier.gd`'s own header explains why a
  corpus reader can profile at zero while still belonging in `BOUT_FILES`, and `test_suite_tier.gd`
  exists to tell those apart. Adding twelve readers is exactly the case that comment anticipates.

**TESTS:** the corpus plays its bouts exactly once per suite run (assert the counter — paying twice is
the failure this pass exists to prevent); every file moved onto it asserts what it asserted before;
`test_suite_tier.gd` still distinguishes a corpus reader from a stale entry.

---

# PASS C — A scripted corpus, for tests the AI has no business breaking

`BoutCorpus` calls `CompletionSampler.run_seeds`, so it plays **AI-driven** bouts. Right where the AI is
the subject; wrong for the **133 files that build state by hand precisely to keep the planner out.**

**A second corpus: preset seed, predetermined actions, no planner in the loop.** That gives a combat or
movement test the real resolution path — two-phase turns, the action queue, the log — without the AI as
a failure point. `test_work_counters.gd` already drives a turn by hand and asserts a scripted turn
counts while building no bout; taskblock-47 Pass E retargeted the tb38 flat-bout guard from a
planner-driven bout to a scripted queue with no loss of coverage.

**Two corpora, two questions:**

| corpus | subject | driven by |
|---|---|---|
| sampled | the AI's behaviour | random seeds, real planning |
| **scripted** | everything else | one preset playthrough, fixed actions |

**Prototype first, then migrate.** Move a handful of files and report what it cost and what it caught
before converting more. The audit's three outcomes apply per file: hand-built is right; hand-built was
avoiding the AI (move it); **hand-built is quietly wrong** — the fixture drifted from what the game
produces and the test passes against a board that could not occur. The third is the one worth finding.

**TESTS:** a scripted bout resolves identically on every run without invoking the planner (assert the
plan counter is zero — a scripted corpus that quietly plans is the failure mode); migrated tests assert
what they asserted before.

---

# PASS D — `seeds_to_first_win` replaces the completion rate

Stop at the first completion and report **how many seeds it took**.

**Cost scales inversely with health, which is the right shape.** At ~72% completion the common case
stops at seed 1 or 2 — roughly one bout instead of eight. When the AI regresses the metric gets more
expensive, and the suite pays attention exactly when something is wrong.

**It also degrades gracefully where a rate does not.** `MIN_COMPLETION_RATE` nearly died because a
threshold on a small integer count sat less than one seed from red. `seeds_to_first_win` is a continuous
signal: 1 is healthy, 4 is worth a look, 9 is a problem, and no constant sits on a knife edge.

- **A cap is the only tuning it has.** No win in N seeds is the failure. Pick N from the measured rate
  and record the reasoning beside the constant, the way `SAMPLE_SEEDS` already does.
- **Report the number, not just pass/fail.** The stat is the point; a green boolean throws away the
  signal that made this worth doing.
- **`MIN_COMPLETION_RATE` is the supervisor's.** Propose its retirement; do not remove it unasked.

**TESTS:** a generator that always completes reports 1; one that never completes fails at the cap rather
than running forever; the reported count matches the seeds actually played.

---

# PASS E — Order by failure, merge the true clusters, fix the lying names

## E1. Indicators first — order, never skip

**Run the most-frequently-failing tests first so a red run goes red early.** The pain is
time-to-first-red, not total runtime: a failure at minute nine costs the whole run.

**Do not skip tests because an indicator passed.** An indicator that passes while the thing it indicates
is broken means the suite is greener than the code — and this project has hit that four blocks running,
once from a single `""` return that silently dropped eleven bout files and went green. **Ordering is
free and safe; skipping is the same hazard at suite scale.**

Log the order with the run so a failure can be replayed exactly. That is the whole reproducibility
requirement.

## E2. Merge the three real clusters

Same rule **and** same scope, per the audit. Cut rule applies; the covering test must be a real peer,
and merged tests keep distinct assertion messages so a failure still names which fact broke.

| rule | rows | cost |
|---|---|---|
| the run panel reports the real rung and the real verdict | 9 | 20.6 s |
| the gate's exit code reflects the run's real verdict | 4 | 12.3 s |
| every spawn zone is walkable and reachable | 8 | 17.0 s |

Roughly 35 s and ~10 tests. Several of these spawn a real subprocess each; one spawn serves the cluster.

## E3. The eight `description` findings are a defect list

All eight are under 10 ms, so **this is worth zero seconds and is still worth doing** — the value is
that grepping for coverage stops lying. `test_taskblock21_gun_data.gd` holds two (pins a content choice
as though it were a rule, and cites an archived taskblock nobody can open); `test_the_flank_test` is a
label rather than a sentence. Rename or drop.

## E4. Trim the seed lists

`test_completion_sampler` (10 bouts) and `test_full_mission` (8 bouts, one test at 62.6 s). **Sample
size is a tunable, not a rule.** ~80 s, and Pass D may absorb most of it already — re-measure before
trimming rather than doing both blind.

---

# PASS F — Clear the deck for taskblock-51

Small things that make a hunt cheaper, not fixes.

- **The replay queue needs a baseline.** It shows only failures today, and an anomaly is not
  identifiable without a reference for normal — the likeliest reason the review layer has not paid off
  yet. **Queue one representative success per test alongside the failures**, capped, with an option to
  sit through everything.
- **A chime when a run finishes.** The window is watched intermittently by definition.
- **Triage the ledger by subsystem.** 31 open entries; the hunt goes cluster by cluster, not
  chronologically. Group them and note which share a suspected cause — the tracer cluster, the
  spectator/player divergence trio, the map-generation entries. **Grouping only; change no status and
  close nothing.**
- **Every open entry has a repro path or a stated reason it lacks one.** An entry that cannot be
  reproduced is not a bug to hunt, it is a bug to re-observe, and knowing which is which before the hunt
  starts is worth more than an hour during it.

**TESTS:** the baseline replay is capped and does not become the default; ledger grouping changes no
statuses (diff the status lines before and after).

---

# Acceptance

- **A full run under five minutes**, reported against Pass A's build stamp.
- Nothing deleted except the eight named naming defects.
- `HULK` returns only hulk-domain uses.
- `seeds_to_first_win` reported as a number.

# Not this block's job

- **Fixing bugs.** taskblock-51.
- **`MIN_COMPLETION_RATE`.** Propose; the supervisor disposes.
- **Skipping tests on an indicator's say-so**, per E1.
- **Migrating all 133 hand-built files.** Pass C prototypes and reports; the rest follows the evidence.
