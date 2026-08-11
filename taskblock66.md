# Taskblock 66 — Shard the gate, and the makespan is one draw

*Depends on taskblock-65's profile and counters. A short block before the post-taskblock-65 doc review.*

**The full gate is 1333.5 s attributed / 1338.1 s wall** at `b7a51ef`, 363 scripts / 3547 tests,
single-threaded on a 32-core machine at 94–96% CPU. **The parallelism is available and the cost of not
having it is supervisor time** — at twenty-odd minutes a gate, two taskblocks is a working day.

**One number in taskblock-65's report does not survive to this block, and it is the one the plan rested
on.** That report bin-packed against the committed profile as it stood at `67933bc` — 1044 s, with
`test_watched_run.gd` at 63.2 s — and concluded that the wall was `test_battle_scene.gd` at 63.4 s and
that 16 shards gave a 66 s makespan, 15.7×. **The next commit replaced that profile.** At `b7a51ef`,
`test_watched_run.gd` is **361.2 s**, of which **360.97 s is a single test**
(`test_a_watched_seed_matches_what_the_headless_path_reported`). File-level sharding cannot divide it,
so 66 s describes the luckiest available draw rather than the expected one.

**That cost is not a property of the file.** `BoutCorpus._sample` is filled by
`CompletionSampler.seeds_to_first_win()` seeded from the clock (`test/support/bout_corpus.gd:59`),
drawing seeds from **0–9999** (`completion_sampler.gd:270`) and playing until the first win, capped at
`FIRST_WIN_CAP` (9). **The whole cost lands on whichever `SuiteTier.CORPUS_READERS` file the run happens
to touch first** — `src/logic/completion_sampler.gd:123` says exactly this, and
`test/support/suite_budget.gd:105` records the swing that exposed it.

**Four measurements of the same work, no relevant code change between them:**

| source | seeds played | turns | `test_watched_run.gd` | turns/seed |
|---|---:|---:|---:|---:|
| `suite_budget.gd:107` | 2 | 88 | 121.9 s | 44.0 |
| profile at `67933bc` | 2 | 82 | 63.2 s | 41.0 |
| profile at `bfc8efb` | 7 | 246 | 279.2 s | 35.1 |
| profile at `b7a51ef` (HEAD) | 6 | 268 | 361.2 s | 44.7 |

**Two runs at the same seed count differ by 1.9× in seconds**, because the machine is in use while the
gate runs. **Counts are stable; seconds are not** — the finding `SuiteBudget` was built on, and the
reason everything below is stated in turns with a seconds band.

---

## Decisions this block is built on

**Recorded so no pass re-litigates them.** All four are the supervisor's, taken during review of this
spec's first draft.

| | Decision | Reason |
|---|---|---|
| **The draw stays random** | `BoutCorpus.sample()` is not pinned or fixed | The test exists to prove a win *can* occur. A fixed set of bouts pays the cap every run rather than sometimes — the escalation stopping early is why the typical gate is cheaper than the worst. Making the cost constant makes it constantly bad. It is also what taskblock-46 spent a pass establishing. |
| **Nothing depends on whole-suite run order** | taskblock-65's second open question, closed by decision | A committed shard map is free to reorder across shards. |
| **The shard map is committed, not portable** | This machine is the reference | CC has ~75% of 32 cores; the supervisor is using the rest. Portability is not a goal. |
| **`test_battle_scene.gd` is not split** | At 63.3 s it is no longer the wall | Trigger recorded instead — split it if it ever becomes the determiner of gate length. |

**So the makespan is the corpus shard, and this block's job is to make everything else disappear behind
it.** Non-corpus work is **972.3 s** at HEAD's draw; across 15 other shards that is **~65 s each**,
comfortably under the corpus shard in every draw the model admits.

---

## What is measured, what is modelled, and what is not yet known

**The escalation's length is not an empirical quantity — it is `min(Geometric(p), 9)`.** Sampling it
repeatedly measures a coin whose bias is the only unknown, at roughly 250 s per sample, and ten samples
still yield only ~2 observations of the cap case. **Model it and measure the unit costs instead.** The
first draft of this block specified ten live escalations at 56–90 min; this replaces that with ~15 min.

**The model.** A draw is `(N−1)` losing bouts plus one winner, or 9 losers if it reaches the cap.

```
E[turns] = (E[N] − P(win)) × L + P(win) × W        cap draw = 9 × L
```

**Its inputs, and how well each is known:**

| input | best value | source | trusted? |
|---|---|---|---|
| `L` — losing bout | **34.7 turns** | derived from the four real draws above | reasonably — real seed space |
| `W` — winning bout | **58.3 turns** | `BR65.01`, `probe_seeds` over 0–19 | mean only, one window |
| seconds per turn | **1.028**, band **0.77–1.39** | 1280 turns in 1315.8 s; band from the table above | the band is the answer, not the mean |
| **`p` — completion rate** | **0.15–0.25** | see below | **no** |

**`p` is the block's weakest input and it drives both headline claims.** Every estimate of it in this
project is small-n, and the ones in view are drawn from a window the codebase itself distrusts —
`completion_sampler.gd:12` and `bout_corpus.gd:17` both warn about the pinned window measuring the
pessimistic corner. `BR65.01`'s 0.15 is 3/20 over seeds 0–19, a subset of that same window.

**A window-free estimate already exists in the four real draws, and it is unstable in exactly the way
that matters.** Those draws come from 0–9999 and all four ended under the cap, so they are uncensored
geometric observations:

| estimator | p̂ | P(no win in 9) |
|---|---:|---:|
| MLE over the four draws (4 wins / 17 seeds) | **0.235** | 0.090 |
| adding taskblock-65's observed cap-9 no-win as a censored observation (4 / 26) | **0.154** | 0.232 |

**One additional observation moves p̂ by 1.5×.** That is the honest statement of what is known.

**One recorded fact deserves less weight than it is carrying.** `completion_sampler.gd:12` reports seeds
0–11 at 41.7% against 12–23 at 66.7% *"on the identical build"*, and this block inherited it as evidence
that the seed space has structure. **Fisher exact on 5/12 against 8/12 gives p ≈ 0.41** — a spread that
size at n = 12 is what noise looks like. **taskblock-46's decision to sample rather than pin is correct
regardless** and is not reopened here; what is corrected is the belief that the windows are *known* to
differ. Pass A3 tests it directly instead of assuming it either way.

**What the gate becomes, across the plausible range of `p`:**

| p | E[seeds] | E[turns] | corpus shard | P(cap) | cap draw |
|---:|---:|---:|---|---:|---|
| 0.15 | 5.12 | 196 | **151–272 s** | 0.232 | 240–434 s |
| 0.235 | 3.87 | 156 | **120–217 s** | 0.090 | 240–434 s |
| 0.30 | 3.20 | 134 | **103–186 s** | 0.040 | 240–434 s |

**Report the gate as a band, not a number.** Roughly **3–7 minutes against 17–25 today**. A single
headline figure for a gate whose cost is a random variable is the thing that just went stale.

---

# PASS A — One shard, and the numbers the plan rests on

**Run a subset of `test/` in a separate process and get its counters back.** Nothing is packed and
nothing is committed in this pass.

**`tools/run_suite.gd` already hosts `GutRunner` and already accepts `--dir=` and `--test=`**
(`:167`, `:187-190`). **A shard is that runner pointed at a file list**, not a new entry point.

## A1. The counters must survive the process boundary

Each shard reports `bouts`, `turns`, `candidates`, `floods`, `plans`, `shot_planes`, `maps`, `spawns`
and taskblock-65 Pass F's two, and **the gate sums them.** They are diffed statics, so they are additive
by construction — but that is reasoning, and this pass is where it becomes measurement.

**If they do not aggregate cleanly the budgets go dark and this block stops here.**

## A2. The real per-process floor

taskblock-65 measured **1.05 s**, on the argument that `gdlint`, `--import` and the parse guard are
once-per-gate rather than once-per-shard. **Confirm that against the actual shard invocation.** If the
floor is materially higher, the shard count that pays for itself changes and Pass C needs re-deriving.

## A3. `p`, from the whole seed space — ten windows in parallel

**`probe_seeds.gd` already accepts `-- <first> <count>` and each window is an independent process.**
Run **ten** of them concurrently:

```
first ∈ {0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000},  count = 10
```

**100 seeds spanning the whole draw space, ~11 minutes wall, no code change.** One 10-seed window is
~11 minutes serial, so ten in parallel cost the same wall time as one and return ten times the data.
There are 32 cores.

**This answers three questions with one run:**

1. **`p` across the real space.** 100 seeds gives a 95% interval of about ±0.08 at p̂ ≈ 0.2, and crosses
   the size where 0.15 and 0.30 are actually distinguishable (n ≈ 42 for 80% power). Forty seeds does
   not comfortably.
2. **Whether the window matters at all.** Ten scattered windows test it directly. **Expect it not to** —
   see the Fisher figure above — and record the result either way, because the belief that it does is
   currently load-bearing in two file headers.
3. **`L` and `W` separately.** `CompletionSampler.run_seeds` returns per-seed rows carrying
   `outcome_name` and `turns`; `probe_seeds` prints total elapsed. **Capture the rows, not just the
   aggregate** — turns by outcome class is the input the model needs and the aggregate throws it away.

**Then compute the distribution** rather than sampling it, and **re-issue the table above** with measured
inputs.

## A4. One live confirmation draw

**One clock-drawn escalation**, ~4 minutes, checking that the live path agrees with the model. Not a
sample — a check that the model describes the right thing.

## A5. Do the subprocess-spawning tests survive a shard?

**Sixteen test files shell out** (`run_tests.sh`, `OS.execute`, `create_process`); taskblock-65 counted
25 such tests and left this as its first open question. Log paths are PID-keyed so they *should* survive.
**Run them inside a shard and see.** This is the taskblock-65 question that cannot be answered by
reading.

**TESTS:** a one-shard run reports the same counts as an unsharded run of the same files. **That
equality is the pass** — a shard that miscounts is worse than no shard.

**Stop and report if:** counters do not aggregate; the floor is materially above 1.05 s; the subprocess
tests do not survive; or **`p` comes back outside 0.10–0.35**, at which point the makespan table and
`BR65.01` both want re-deriving before Pass C packs anything.

---

# PASS B — `BR65.01`, and the flake is fixed without lengthening the tail

**`FIRST_WIN_CAP` was sized against a ~72% completion rate; the real rate is far lower, so
`test_seeds_to_first_completion_stays_low` goes red on a substantial fraction of gates** with nothing
wrong. **A gate that fails for a known reason is a gate people learn to re-run**, which is how a real
failure gets waved through — worse during a doc review, when the gate runs repeatedly.

**This pass does not wait on Pass A3, and does not change if `p` comes back high.**

| p | P(no win in 9) | reading |
|---:|---:|---|
| 0.15 | 0.232 | one gate in 4 |
| 0.235 | 0.090 | one in 11 |
| 0.30 | 0.040 | one in 25 — still a red gate most weeks at this gate frequency |

**And the flake rate was never the whole argument.** The cap was derived against 0.72, which is wrong at
every candidate value of `p`; and **a fixed known-winning seed is a strictly better proof that a win is
reachable than a random draw is, at any `p`.** What A3 changes is this pass's urgency, not its
correctness.

**The obvious fix is the wrong one, and it is wrong specifically because of this block.** Raising the cap
to reach a 1% flake rate at p = 0.15 needs **29**. **The cap is now the makespan** — 29 bouts in one
shard would cost more than the entire sharded gate. Lowering it raises the flake rate. The knob that
fixes the flake and the knob that sets the worst case are the same knob, and `test_per_tier_probe.gd:95`
already asserts `FIRST_WIN_CAP == 9` for exactly this reason: thresholds in this project have
historically been moved to quiet a flapping gate.

## B1. The fix: the assertion splits, the cap does not move

**One rule is doing two jobs.** *A win is reachable* is a property of the game and should be proven
deterministically. *How many seeds it takes today* is a measurement and should be reported.

- **A deterministic guard asserts a win is reachable.** A known-winning seed, fixed, one bout. Seeds
  0–19 hold three completions, reproduced byte-for-byte on a worktree of `60c9554` — **window bias does
  not matter for this purpose**, since the seed only has to win reproducibly. Pick one.
- **The clock-drawn sample stops asserting `won`** and keeps `assert_gt(played, 0)` plus its printed
  report. A cap draw with no win becomes information, not a red gate.
- **`FIRST_WIN_CAP` stays 9** and `test_per_tier_probe.gd:95` stays green.

**The failure message already points at this.** Today's assertion tells the reader to *"confirm with the
deterministic run before treating it as real"* — this pass promotes that confirmation from a manual tool
into the test, which is where a load-bearing claim belongs.

**Put the deterministic guard in a shard other than the corpus shard.** It costs one bout and the corpus
shard is the makespan.

## B2. The escalation's advertised cost is stale by an order of magnitude

`tools/probe_seeds.gd:15` says the 100-seed escalation *"plays a hundred missions and costs upward of
ten minutes."* **At the measured 65.8 s per seed it is ~110 minutes** — the comment dates from when `p`
was 0.72 and bouts were shorter. **Pass B's own failure message points readers at that command.**
Someone told to expect ten minutes and handed two hours does not run it twice. Correct the header with
the measured figure, and note that A3's parallel-window form is the cheap way to run it.

**SUPERVISOR NOTE — B1 is this block's one design change.** The random draw stops being a pass/fail
gate. It is one test and trivially reversible, and it is proposed because the alternative fix attacks
this block's own headline. **Say no and Pass B becomes "re-derive the cap and accept a longer tail."**

**TESTS:** the deterministic seed completes a mission; the clock-drawn sample runs and reports without
asserting a win; `FIRST_WIN_CAP` is still 9.

---

# PASS C — The packer

## C1. The shard map is committed, not computed

Deterministic assignment is what taskblock-65's third open question requires for a reproducible merged
profile, and it removes work stealing — which would move corpus draws between runs and make the profile
unreproducible.

**`SuiteOrder` is not in conflict with this, and it must be said so it is not "fixed."** Failure-history
ranking (`run_suite.gd:160`) continues to operate **within** each shard, so a red shard still fails
early. **Assignment is committed; ordering inside an assignment stays adaptive.** Both mechanisms
survive untouched.

## C2. The corpus shard is shard 0, and it starts first

**Longest-processing-time-first.** The corpus shard is the makespan in every draw, so it must never be
waiting on a scheduler. **Everything else is packed to finish under it.**

## C3. Co-location is a cost, not a free constraint

**Each process gets its own `MapCorpus._cache` and `BoutCorpus._sample`**, so a corpus split across
shards is refilled in each of them. But **co-locating readers inflates one bin**, and that bin may
already be the makespan. **The rule: co-locate when the fill cost exceeds the imbalance co-location
creates.** Apply it per corpus, not as a blanket policy:

| corpus | fill | reader files | verdict |
|---|---:|---:|---|
| `BoutCorpus` | the draw, 1–9 bouts | 3 (`SuiteTier.CORPUS_READERS`) | **must co-locate** — it is the makespan and must be paid once |
| `MapCorpus` 32×24 | 11.2 s | 11 | **decide from the packing** — 11.2 s duplicated across two shards may beat inflating one |
| `MapCorpus` 40×30 | 16.9 s | 3 | as above |

**Report which corpora qualify and why**, and treat that as the general rule: **any shared expensive
setup is a bin-packing constraint with a price attached.**

## C4. Stale-profile behaviour is a normal case

A new file has no profile entry. **Assign unknowns a conservative default and say so** rather than
treating them as free and letting one shard grow a tail.

## C5. Sixteen shards, and not thirty-two

**CC has roughly 75% of 32 cores.** Sixteen is comfortable; thirty-two oversubscribes and, past the point
where the non-corpus shards fall below the corpus shard, extra shards buy nothing at all. **Derive the
number from where the non-corpus makespan crosses the corpus shard's typical cost** and report it.
Sixteen is the expectation, not the requirement.

## C6. The profile that feeds the packer comes from an unsharded run

**Sixteen processes competing for twenty-four cores inflates and scrambles per-file wall-clock** — and
the packer reads per-file wall-clock. **A profile regenerated under sharding would degrade the packer's
own input a little more on every regeneration.** Keep `tools/profile_suite.gd` on the single-process
path and say so in its header, so nobody helpfully parallelises it later.

**TESTS:** the packer produces balanced shards against a known profile; a file absent from the profile
gets the conservative default; the three `CORPUS_READERS` files land in one shard; the shard map is
committed and identical across two runs.

---

# PASS D — A red gate stays readable

**This is what makes people abandon sharding, not the parallelism.** Sixteen shards is sixteen output
streams, and a red gate must stay something you can act on without reading all of them.

- **One aggregated verdict**: pass/fail, summed counters, and every failure with its file, test and
  message.
- **Ordering must be stable.** Shards finish out of order; **the report must not.** A gate whose output
  reorders between runs is a gate nobody can diff.
- **A shard that crashes is a gate failure, not a missing section.** Silent partial success is the worst
  outcome available here and the easy bug to ship — the same failure mode `run_tests.sh`'s completion
  guard already exists for.
- **Keep the single-process path working.** `./run_tests.sh` unsharded stays available for debugging, and
  it is what Pass A's equivalence test compares against.

**TESTS:** an induced failure in one shard fails the gate and names the test; two runs of the same green
suite produce identical output; a killed shard fails rather than passing quietly.

---

# PASS E — Determinism, and what is deliberately not deterministic

**Seeded work is unaffected**: separate processes with separately seeded RNGs produce identical results,
because nothing in the suite reads wall-clock or process identity into a seed. **Assert it rather than
asserting that it is true** — a seeded bout produces the same fingerprint sharded and unsharded.

**The corpus draw is deliberately non-deterministic and stays that way** (see Decisions). **Under
affinity sharding exactly one shard draws, so the behaviour is unchanged from today** — one draw per
gate, shared by every reader. That is the property to assert, and it is what would break first if someone
later "improved" the packer by splitting the readers.

**The budgets already survive this and need verifying, not fixing.** `b7a51ef` made
`CompletionSampler.sampled_turns` subtractable, so `turns` is baselined at the controlled 496 rather than
the draw-dependent 808, and `SuiteBudget` gates on counts rather than seconds by design. **Confirm the
budgets read correctly from summed shard counters.**

**TESTS:** identical fingerprints sharded and unsharded for the same seed; exactly one corpus draw per
sharded gate; the budgets pass on summed counters.

---

# Close-out

- **Re-measure the gate and report it with counters**, so the speedup is attributable rather than
  asserted.
- **Report the gate as a band across the draw**, using A3's measured inputs. **One number is what went
  stale last time.**
- **Record `p` and the window result where the next reader will find them.** `p` now sits behind both
  the makespan and `BR65.01` and currently lives in a bug entry. If A3 finds the windows equivalent, say
  so in `completion_sampler.gd`'s header, next to the claim it corrects.
- **Regenerate the profile from an unsharded run** and commit it.
- **`BR65.01` closes** if Pass B lands, or carries the supervisor's alternative if it does not.

# Acceptance

- A shard's counters equal an unsharded run's for the same files.
- `p` measured across 100 seeds spanning the draw space; `L` and `W` separated; the window question
  answered either way.
- The subprocess-spawning tests run inside a shard.
- The completion flake is gone and `FIRST_WIN_CAP` has not moved.
- `probe_seeds.gd`'s advertised cost matches its measured cost.
- The shard map is committed, corpus-aware, and identical across runs.
- A failure in any shard fails the gate and names itself; output is stable across runs.
- Exactly one corpus draw per gate.
- The gate is reported as a band, with counters, against 1333.5 s.

# Not this block's job

- **Threads.** Evaluated and rejected in taskblock-65: the counters are shared statics the profiler
  brackets by diffing, and threading would destroy the per-file attribution that found Pass D's hidden
  400-turn bout. **A slower gate is a better trade than never being able to explain one again.**
- **Splitting `test_battle_scene.gd`.** At 63.3 s it sits under the corpus shard, so it is not the wall
  and nothing forces it now. **Trigger recorded: split it if it ever becomes the determiner of gate
  length.** Its 63.3 s for 6 bouts and 3 turns is scene-mount cost and deserves its own look eventually.
- **Re-litigating the sample-versus-pinned-window decision.** A3 corrects the *evidence* cited for it;
  taskblock-46's decision stands either way.
- **Making the corpus's own turn count observable.** Already queued in `PLAN.md`; worth ~250 turns and
  not a sharding change.
- **Cutting any test.** This block changes where tests run, not which ones exist.
- **The doc review.** It follows this.
