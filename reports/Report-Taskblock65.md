# Taskblock 65 Report — a map is a map, and the suite stops paying twice

**All six passes landed in order** — A (survey), B (the stride leaves generation), C (the
retrofit), D (`test_ai_batch_yield`), E (the sweep) and F (the counters) — each green on the fast
gate and committed, plus a close-out that makes the profile self-maintaining. The full gate is
**1044 s against tb64's 1378.3 s**, 363 scripts / 3547 tests / **0 failures**.

**The block's two headline findings are both corrections to its own premise.** Pass A's expected
~100 s of recoverable map work measured **~62 s**, and three of the five files the taskblock named
were worth under a second between them while two it did not name were worth 16 s. And Pass D's
turn cap — the thing the taskblock asked for — turned out to be **the smaller half** of a 279.9 s
file: 400 of its 432 turns were being spent by a test whose own comment said it cost "a handful",
because a controller was set one line too late and had been since taskblock-47.

**A third correction landed after the passes closed, and it reversed a Pass F decision of mine.**
Making the full gate write the profile turned a latent budget flake into a reachable one, and
fixing it properly showed that the exclusion I had defended in Pass F was aimed at the wrong
thing — see *Decisions*. One bug was filed (`BR65.01`) and one of my own framings of it was wrong
and was corrected by the supervisor.

<!-- Rewrite this opening whenever a later pass moves it. -->

## Decisions made without asking

**Pass A proceeded rather than stopping, and the correction is the reason to read it.** A2 names
three stop conditions; none was met — the boards are not materially different, the corpus widens
by two keys rather than substantially, and 62 s is well past the "twenty seconds is not worth the
churn" bar. **The alternative was to stop on "the number is not 100 s"**, which would have
declined a real 62 s saving over a prediction the pass existed to test. What is *not* glossed is
that the A1 table was wrong about distribution, and the survey in `MapCorpus`'s header says so.

**`_connect_with_a_stair` keeps its `step_height` parameter where `generate` lost its.** The
taskblock says remove the parameter; this is a partial exception. Generation only ever passes
`DESIGN_STEP_HEIGHT` and nothing outside the file can reach it, so the misbuild is gone — but the
derivation (`ceil(rise / step_height)`, so a longer stride builds a shorter stair) is a real
property that `test_a_larger_step_height_builds_a_shorter_stair` proves directly. **The
alternative was deleting the parameter and the test with it**, which would have removed a proof
rather than a defect.

**`MapNavigability.roster_report` skips its flood for a roster at or above the baseline.** That
looks like an optimisation and is not: `move_cost` admits a rise at or under the mover's step
height, so a longer-striding unit walks every edge a baseline unit can and cannot be stranded
where one is not. **It is exact.** Stated because the cheap-looking version of this — sampling, or
a tolerance — would have been a guess, and because it means the check costs nothing today and
starts working the day a legless chassis lands.

**`BoutSetup` returns the report and never gates on it.** A roster the check refuses still builds
a bout. **The alternative was refusing the bout**, which would have re-created exactly what Pass B
removes — the board bending to the roster — one layer up.

**Pass D bounded both drivers rather than shortening one.** tb48 explicitly declined to cut this
test, on the grounds that *"comparing a shorter one would mean seed-shopping for a cheap map and
calling it a saving"*. That objection is correct and this is not that: seed, board and AI are
unchanged, and **both** the tight loop and the yielding batch stop at the same declared cap. A cap
on only the reachable driver would have compared a 16-turn bout against a 164-turn one.

**`ControlOverlay.turn_cap` is new production surface added for a test.** Defaulted to
`BoutRunner.DEFAULT_TURN_CAP` and never set in production — the same standing `pacer_budget_msec`
beside it has held since tb58, which is the precedent it was written against. **The alternative
was leaving `advance_ai_turns` uncappable**, which makes the equality untestable at any length.

**Pass E recommends against the corpus it was sent to find.** A mounted `BattleScene` is the
biggest repeated cost in the suite — 1177 ms, 41 files, 512 tests, larger than `BoutCorpus` and
`MapCorpus` combined — and sharing one is the wrong answer, because a mounted overlay **is the
thing under test** where a `Grid` is read-mostly. The list names the narrower cut instead
(declaration properties asserted by mounting a scene). **Saying "found it, don't build it" was the
judgement call**; the taskblock asked for a list and a list that only contains work is not a
survey.

**Pass F picked two counters and ruled out a third by checking rather than by preference.**
"Scenes mounted" is already `ui_builds`. Recorded because a second counter for an existing
quantity is worse than none — it splits attention and invites the two to disagree.

**`maps` was tested for a weaker claim than `ui_builds`.** A bout generates one map, so the
"moves for X and not for Y" shape `ui_builds` uses is **false** here. The test asserts what is
true — one for a bout, five for a five-seed sweep. **The alternative was copying the established
test shape**, which would have shipped a guard asserting something untrue.

**I reversed my own Pass F conclusion about the budget exclusion, after the close-out made it
matter.** Pass F argued that `TURNS_EXCLUDED` should stay a single filename and the corpus swing
should be absorbed by the `turns` baseline — reasoning I still think was right *given a manually
regenerated profile*. Making the full gate write it automatically changed that: a green run with an
unlucky corpus draw would have written 1131 turns against a limit of 904 and failed the **next**
run. **The fix showed the earlier framing was aimed at the wrong object.** What is uncontrolled is
not a file — it is the sampler's own turns, clock-drawn and stopped at the first completion — and
that cost lands on whichever corpus reader happens to run first. `CompletionSampler.sampled_turns`
counts the quantity and `SuiteBudget` subtracts it; a filename was only ever a proxy for it.
`TURNS_EXCLUDED` stays at one entry, so the guard that refused me in Pass F is still satisfied and
is now largely redundant rather than load-bearing. **The alternative was raising the turns baseline
to ~1300 to cover the worst draw**, which is "raise the constant until it stops" — the exact habit
`SuiteBudget`'s own header is written against.

**The full gate writes the profile by default now.** The taskblock offered "a line in the
workflow" or "`run_tests.sh` writing the profile"; both were done, with the script as the
mechanism and the workflow line as the explanation. **A red run writes nothing** — that constraint
is not in the taskblock and was added because the counts of a suite that did not complete are
worse than no fresh counts. `run_tests.sh` also exports `HB_NO_WRITE_PROFILE=1` to its children:
every suite-spawning test passes a target today and so already refuses, but that is a property of
their arguments rather than of the design.

## Tests that failed, then were corrected

**Four, and two of them were the suite correctly refusing something I did.**

1. **`test_the_exclusion_list_stays_small_and_gates_bouts_regardless` refused my budget fix, and
   it was right.** Having found that `BoutCorpus`'s clock-seeded play length makes
   `test_watched_run.gd` swing 88 → 246 turns between runs, I added the other two corpus readers
   to `TURNS_EXCLUDED` — and hit a guard asserting fewer than three exclusions, written by
   somebody who anticipated exactly this move. **An exemption is a hole in the gate and the answer
   to "this moved for a reason I do not control" is not to widen the hole until nothing trips.**
   `turns` is baselined at the measured total instead, which keeps the swing visible in a number.
   The real fix is queued rather than bodged.
2. **My own inference about per-turn cost was wrong, and the counters caught it.** From the cap-4
   vs cap-16 comparison I derived "early turns cost ~5.1 s, later ones ~300 ms" — a model fitted
   to a total that secretly contained a 400-turn bout. `bouts 3 turns 432` on the cost line is
   what exposed it. **The lesson is the one this project keeps relearning**: a number that needs a
   story to explain it usually has a different cause than the story.
3. **`gdformat test/` swept two files this block never touched.** `test_lint_config.gd` and
   `test_resolution_player_elevation.gd` were already unformatted in the tree; reverted rather
   than folded into a pass commit. Not a test failure, but it would have been unrelated churn in
   a diff about map corpora.
4. **`class-definitions-order` rejected the spawn counter twice.** Placing `static var
   processes_spawned` and its `reset_diagnostics()` at the top of `suite_run.gd` put a function
   ahead of the consts and, worse, put my paragraph where the **class doc comment** belongs — so
   the file briefly described itself as a counter rather than as the suite launcher. Moved below
   the consts, class doc restored.

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** This block filed no bug entries and closed none — its findings were in tests and
tooling, which are recorded in `docs/CHANGELOG.md`. `BR63.01`, `BR63.02`, `BR63.03` and `BR61.07`
remain `Pending` from taskblock-64 and are untouched here.

## Open questions

### Parallelising the suite: processes yes, threads no — evaluated, not queued

Investigated at the supervisor's request while the final gate ran. **Held here rather than in
`PLAN.md` deliberately** — it wants more research before it becomes work.

**Threads look unviable, and the corpus argues against them rather than for them.** The prompt for
this was that the corpus makes per-thread tests more viable; measured, the opposite holds — a
shared mutable cache is precisely what needs synchronising, and `MapCorpus.read()` hands back *the
same object with no copy*, which is the entire saving. Five blockers, hardest last:

| blocker | measured |
|---|---|
| SceneTree is main-thread-only in Godot | **99 of 363 files** call `get_tree()` / `add_child` / `await process_frame` |
| `DataLibrary` is global mutable state reset per test | **97 files** do `reset()` + `load_all()` in `before_each` |
| every work counter is a shared static | the profiler brackets each file by **diffing** them |
| GUT is one runner with shared state | not thread-safe |
| the corpora are themselves shared statics | `MapCorpus._cache`, `BoutCorpus._sample` |

The third is the one that would hurt most: **it would destroy the budget mechanism this block just
extended**, and the per-file attribution that found Pass D's hidden 400-turn bout.

**Processes look genuinely good.** Per-process overhead measured at **1.05 s** — 1.75 s wall for a
run whose tests take 0.7 s — because `gdlint`, `--import` and the parse guard are once-per-gate,
not once-per-shard. Bin-packed against the committed profile (1044 s, 363 files):

| shards | makespan | speedup | limited by |
|---:|---:|---:|---|
| 4 | 262 s | 4.0x | even split |
| 8 | 132 s | 7.9x | even split |
| **16** | **66 s** | **15.7x** | even split |
| 32 | 64 s | 16.2x | **one file** |

**The wall is a single file** — `test_battle_scene.gd` at 63.4 s. Nothing past 16 shards improves
until it is split, so 16 is the target and 8 the conservative choice. The machine has 32 cores and
each run is single-threaded (94-96% CPU), so the parallelism is genuinely available.

**The one design constraint comes straight from Pass C, and naive sharding would undo it.** Each
process gets its own corpus cache:

- **32x24** — 50 boards, 11.2 s to fill, **11 reader files**. Round-robin across shards costs up to
  **+112 s of duplicated generation**.
- **40x30** — 50 boards, 16.9 s to fill, **3 reader files**. Up to **+34 s**.

**Affinity sharding** — corpus readers kept together — pays each fill once, as today. The argument
is sharper for `BoutCorpus`, whose sample is the most expensive *and* most variable work in the
suite: two shards each drawing their own means two `seeds_to_first_win` escalations, and at the 15%
completion rate (`BR65.01`) that is routinely nine bouts each rather than one.

**What is not yet answered, and why this is not a `PLAN.md` item yet:**
1. **Do the 25 subprocess-spawning tests survive sharding?** They shell out to `run_tests.sh`; log
   paths are PID-keyed so they should, but that is reasoning rather than measurement.
2. **Does anything depend on whole-suite run order?** `SuiteOrder` ranks by failure history, and
   `SuiteTier`/`SuiteBudget` read the committed profile. Read-only, so probably fine — unverified.
3. **Is the merged profile reproducible?** Counters are additive so summing works, but the shard
   assignment must be deterministic and committed; dynamic work-stealing would move corpus draws
   between runs and make the profile unreproducible.
4. **Does a shard failing report usefully?** One red shard among sixteen must not read as a green
   gate — the same failure mode `run_tests.sh`'s completion guard already exists for.

**The honest summary:** a ~8-16x wall-clock win looks real and the mechanism is ordinary
(`run_suite.gd` already accepts repeatable `--test=`), but it needs a merge step, a committed
affinity-aware shard map, and answers to the four above. **Roughly a taskblock, not a pass.**


### How flaky is an acceptable gate? (`BR65.01`)

**The completion rate is 15%, and that is by design** — the supervisor, 2026-08-11: *"as maps
become harder to navigate, and win conditions more stringent, completions will be rarer. Dropping
from 72% to ~40% was a game rules update, and ~40% down to 15% was a map update."* **My first
framing of this as drift was wrong and the entry was rewritten.** Measured deterministically over
seeds 0–19 and **byte-for-byte identical on a tb64 worktree**, so nothing in this block moved it.

**What was never resized to follow is `FIRST_WIN_CAP`.** At 9 seeds and a 15% rate,
`test_seeds_to_first_completion_stays_low` goes red on **P = 0.232 — about one full gate in four**,
with nothing wrong. It fired once during this block's close-out. At the 0.72 the cap was chosen
against it would have been 1 in 94 000.

**The decision needed is what false-red rate is worth paying for**, because a raised cap costs
bouts on exactly the unlucky runs: **28 gives ~1 in 100, 18 gives ~1 in 20**. Filed rather than
picked. Whatever is chosen, the constant should carry the rate it was sized against, so the next
rules or map change makes it visibly stale instead of quietly flaky.

**A caveat on my own number:** 20 seeds puts 15% at roughly 3–38% with 95% confidence, and
`ESCALATION_SEEDS` is 100. The full hundred should be run before sizing anything against 15.0%.

**`bouts` and `candidates` still have no mechanism, where `turns` now does.** The same three full
gates measured **80 / 85 / 88 bouts** and **911 200 / 1 292 621 / 1 816 411 candidates**, almost all
of it the corpus draw. `sampled_turns` fixed the counter with a live flake and stopped there; the
other two are gated against a single-sample baseline (`candidates` is not gated at all). The work is
the same shape and small — queued in `PLAN.md`.

**The mounted-`BattleScene` cost is measured but its true total is bounded, not known.** At one
mount per test the 41 files pay ~600 s; at one per construction site, ~108 s. **Nothing counts
mounts directly** — `ui_builds` counts theme builds, which is a proxy — so narrowing that range
needs its own counter. Worth knowing before anyone sizes the work in `PLAN.md`.

**Whether `maps` should have more per-file caps.** Four were set from measurement
(`test_map_gen` 235, `test_battle_scene` 95, `test_map_gen_reachability` 58,
`test_spectator_overlay` 42). The suite total is gated at 1083, so a new fifty-seed sweep in an
unlisted file is caught by the total and not by name. **Adding a cap per map-generating file would
name it faster and would also be a table nobody maintains** — left as measured rather than
guessed at.
