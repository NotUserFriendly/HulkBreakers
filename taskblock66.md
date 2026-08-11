# Taskblock 66 — Shard the gate, and the makespan is one draw

*Depends on taskblock-65's profile and counters. **Pass A has landed** (`83544b4`); B through F are
the remaining work. Every number below is measured unless marked otherwise.*

**The full gate is 1333.5 s attributed / 1338.1 s wall** at `b7a51ef`, 363 scripts / 3547 tests,
single-threaded on a 32-core machine at 94–96% CPU. **The parallelism is available and the cost of not
having it is supervisor time** — at twenty-odd minutes a gate, two taskblocks is a working day.

**The makespan is one file, and that file's cost is a random variable.** `test_watched_run.gd` is
**361.2 s** at HEAD, of which **360.97 s is a single test** — indivisible by file-level sharding. That
cost is not a property of the file: `BoutCorpus._sample` is filled by
`CompletionSampler.seeds_to_first_win()` seeded from the clock (`bout_corpus.gd:59`), drawing from
0–9999 (`completion_sampler.gd:270`) and playing until the first win, capped at `FIRST_WIN_CAP` (9).
**The whole cost lands on whichever `SuiteTier.CORPUS_READERS` file the run touches first** —
`completion_sampler.gd:123` says exactly this.

**So the makespan is the corpus shard, and this block's job is to make everything else disappear behind
it.** Non-corpus work is **972.3 s**; across 15 other shards that is **~65 s each**, under the corpus
shard in every draw the model admits.

---

## Decisions this block is built on

**Recorded so no pass re-litigates them.** All the supervisor's, taken during spec review.

| | Decision | Reason |
|---|---|---|
| **The draw stays random** | `BoutCorpus.sample()` is not pinned or fixed | The test exists to prove a win *can* occur. A fixed set of bouts pays the cap every run rather than sometimes — the escalation stopping early is why the typical gate is cheaper than the worst. Making the cost constant makes it constantly bad. Also what taskblock-46 spent a pass establishing. |
| **Nothing depends on whole-suite run order** | taskblock-65's second open question, closed by decision | A committed shard map is free to reorder across shards. |
| **The shard map is committed, not portable** | This machine is the reference | CC has ~75% of 32 cores; the supervisor is using the rest. |
| **`test_battle_scene.gd` is not split** | At 63.3 s it is not the wall | Trigger recorded — split it if it ever becomes the determiner of gate length. |

---

## Pass A landed: the measured inputs

**All five items passed, no stop condition fired.** These figures replace every pre-pass estimate in the
original spec, including two that were wrong.

| input | spec assumed | **measured** | source |
|---|---|---|---|
| `p` — completion rate | 0.15–0.25 | **0.220**, 95% CI **0.139–0.301** | 100 seeds, ten windows at 0…9000 |
| `L` — losing bout | 34.7 turns | **61.3 turns** | 78 losers, **30 at the 100-turn cap** |
| `W` — winning bout | 58.3 turns | **45.6 turns** | 22 winners |
| per-process floor | 1.05 s | **1.29 s** | 1.21 / 1.29 / 1.36 s |
| subprocess-spawning files | 16 (**spec was wrong** — grep matched comments) | **3** | `test_suite_process`, `test_run_suite`, `test_suite_run` |

**The cost model, re-issued.** A draw is `(N−1)` losers plus one winner, or 9 losers at the cap:

| | turns | seconds (band 0.77–1.39 s/turn) |
|---|---:|---|
| E[draw], `E[N]` = 4.06 | 235 | **181–326 s** |
| cap draw, 9 losers | 552 | **425–767 s** |

**The gate becomes roughly 3–5 minutes typical, 7–13 at worst, against 22 today.** Report it as a band.

**A2's floor is not material**: 20.6 s of total floor across 16 shards against 16.8 s at the old figure —
~4 s against a makespan of 181–326 s. It does not move the shard count.

**The window belief is dead, and both file headers carrying it want correcting at the doc review.** Fisher
exact on the recorded 5/12 vs 8/12 gives 0.414; A3's own chi-square across ten scattered windows gives
11.42 on 9 df against a 16.92 critical value. **No evidence the seed space has structure.** taskblock-46's
decision to *sample* rather than pin is correct regardless and is not reopened.

### Three qualifications on the measured inputs

**1. `p` is P(complete **within 100 turns**), not P(complete).** `run_seed` runs `BoutRunner` to
`TURN_CAP = 100` and counts only `EXTRACTED`; **30 of 78 losers reached that cap**, so 30% of sampled
seeds were still playing when the clock stopped. Two consequences: **`TURN_CAP` is an unlisted cost
lever** — it sets `L`, and `L` is the makespan — and **`p` and `L` are coupled through it**, so any
arithmetic that re-derives one against the other while holding the other fixed is not quite valid.

**2. The CI still spans the range decisions turned on.** Across it, P(cap) runs **1-in-3.8 to 1-in-25**.
The point estimate is 1-in-9.4. **No conclusion in this block changes anywhere in that interval**, which
is the useful thing to say — but no downstream file should receive the point estimate as a fact.

**3. The model is turns-linear, and there is evidence of a per-bout fixed cost.** A4's live draw was 33
turns in 49.8 s — **1.51 s/turn, outside the band**. Solved against A3's 20-seed run (1280 turns /
1315.8 s): ~33 s fixed per bout plus ~0.52 s/turn. **At the current `E[N]` this lands within a few
seconds of the table above**, so the headline holds — but anyone later pricing a *turn* reduction against
this model will over-credit the saving.

---

# PASS B — Two free checks against Pass A's own data

**Both are arithmetic on numbers already in hand. Neither needs a bout run.**

## B1. Validate the model against the four historical draws

Corrected to **1, 1, 6, 5** corpus seeds (the replay makes `test_watched_run.gd`'s bout count
`draw + 1`), with the replay's turns counted:

| draw | model predicts | observed |
|---|---:|---:|
| N=1 | 91 turns | 88 |
| N=1 | 91 | 82 |
| N=6 | 398 | **246** |
| N=5 | 336 | **268** |

**The single-seed draws validate; the multi-seed ones come in 1.25–1.6× under.** One is roughly 2σ
against loser variance, which is large with 38% of losers at the cap — so this may be noise. **Run the
check and say which.** Consistent over-prediction would mean `L` is measured on a harder population than
the corpus draws from, and the makespan estimate is conservative — the safe direction, but worth knowing
before it is quoted for a block.

## B2. Re-derive `BR65.01`'s cap arithmetic

The entry's *"one gate in four"* and its cap figures (28 for ~1%, 18 for ~1 in 20) all come from
`p = 0.15`. **Restate against 0.220 with the interval**, and note qualification 1 above — the cap
arithmetic and `L` move together through `TURN_CAP`.

**TESTS:** none — both items are report content.

---

# PASS C — `BR65.01`: the flake is fixed without lengthening the tail

**`FIRST_WIN_CAP` was sized against a ~72% completion rate.** At 0.220 the completion assertion goes red
on **one gate in 9.4** (1-in-3.8 to 1-in-25 across the interval). **A gate that fails for a known reason
is a gate people learn to re-run**, which is how a real failure gets waved through — worse during a doc
review, when the gate runs repeatedly.

**This pass is justified across the whole interval and does not wait on anything.** The flake rate was
never the whole argument: the cap was derived against 0.72, which is wrong at every candidate `p`, and
**a fixed known-winning seed is a strictly better proof that a win is reachable than a random draw is, at
any `p`.**

**The obvious fix is the wrong one, and it is wrong specifically because of this block.** Raising the cap
to a 1% flake rate costs bouts, and **the cap is the makespan** — every added cap step is another `L` in
the worst case. Lowering it raises the flake rate. `test_per_tier_probe.gd:95` already asserts
`FIRST_WIN_CAP == 9` for exactly this reason: thresholds here have historically been moved to quiet a
flapping gate.

## C1. The assertion splits, the cap does not move

**One rule is doing two jobs.** *A win is reachable* is a property of the game and should be proven
deterministically. *How many seeds it takes today* is a measurement and should be reported.

- **A deterministic guard asserts a win is reachable.** A known-winning seed, fixed, one bout — A3's 22
  winners supply them, and window bias is irrelevant here since the seed only has to win reproducibly.
- **The clock-drawn sample stops asserting `won`** and keeps `assert_gt(played, 0)` plus its printed
  report. A cap draw with no win becomes information, not a red gate.
- **`FIRST_WIN_CAP` stays 9** and `test_per_tier_probe.gd:95` stays green.

**The failure message already points at this** — it tells the reader to *"confirm with the deterministic
run before treating it as real."* This promotes that confirmation from a manual tool into the test.

**Put the deterministic guard in a shard other than the corpus shard.** It costs one bout and the corpus
shard is the makespan.

## C2. The escalation's advertised cost is stale by an order of magnitude

`tools/probe_seeds.gd:15` says the 100-seed escalation *"costs upward of ten minutes."* **At A3's measured
rate it is ~110 minutes serial.** The comment dates from when `p` was 0.72. Correct it with the measured
figure, and record that **A3's ten-parallel-window form runs the same 100 seeds in ~11 minutes** — that
is now the cheap way to run it and it should be documented in the header rather than rediscovered.

**SUPERVISOR NOTE — C1 is this block's one design change.** The random draw stops being a pass/fail gate.
One test, trivially reversible. **Say no and Pass C becomes "re-derive the cap and accept a longer tail."**

**TESTS:** the deterministic seed completes a mission; the clock-drawn sample runs and reports without
asserting a win; `FIRST_WIN_CAP` is still 9.

---

# PASS D — The gated counters, before anything is packed

**Pass A found this and it is the block's most consequential finding.** A1's equality test ran six files
unsharded, then one-file-per-shard across six processes. **Nine of eleven counters matched exactly** — the
aggregation mechanism is sound. Two did not:

| | floods | maps |
|---|---:|---:|
| unsharded | 667 | 242 |
| summed shards | 703 | 260 |

Traced per shard, it is `MapCorpus` duplication and nothing else — each process fills its own cache.
**Both counters are in `SuiteBudget.GATED`** (`suite_budget.gd:187`).

**This must be settled before the packer, because the packer's affinity choices move a gated counter.**
Leave it and the fork is bad in both directions:

| baseline measured | consequence |
|---|---|
| unsharded | every sharded gate reports inflation that is not drift |
| sharded | **changing the shard map silently moves a budget** — scheduling becomes visible to the drift guard |

## D1. Subtract the duplication as a quantity

**The precedent is in the same file and it is exact.** taskblock-65 Pass F hit this shape with the corpus
draw contaminating `turns`, and `suite_budget.gd:120` records the resolution: *"the uncontrolled thing is
a quantity, not a file, and it is now subtracted as one."* `CompletionSampler.sampled_turns` is that
quantity; `turns` is baselined at the controlled 496 rather than the draw-dependent 808.

**Duplicated corpus fills are a quantity.** Count them — a fill that is not the first fill of that key in
the gate — and subtract, so `maps` and `floods` gate on controlled values regardless of shard map.

**This also resolves the tension in the finding.** Pass A observed, correctly, that `maps` inflation is a
direct numeric measure of how badly a shard map splits corpora — a perfect affinity map inflates by zero.
**But a counter cannot be both the gate and the diagnostic**, which is precisely what Pass F untangled.
Subtracting gives both: the gated total stays controlled, and **the subtracted quantity is the affinity
score**, which makes E3's rule checkable rather than argued.

**TESTS:** `maps` and `floods` are equal sharded and unsharded after subtraction; the subtracted quantity
is nonzero when a corpus is deliberately split and zero when it is not; the budgets pass on summed shard
counters.

---

# PASS E — The packer

## E1. Committed, not computed

Deterministic assignment is what a reproducible merged profile requires, and it removes work stealing —
which would move corpus draws between runs.

**`SuiteOrder` is not in conflict, and it must be said so it is not "fixed."** Failure-history ranking
(`run_suite.gd:160`) continues to operate **within** each shard, so a red shard still fails early.
**Assignment is committed; ordering inside an assignment stays adaptive.**

## E2. The corpus shard is shard 0, and it starts first

**Longest-processing-time-first.** The corpus shard is the makespan in every draw, so it must never wait
on a scheduler. Everything else is packed to finish under it.

## E3. Co-location is a cost, not a free constraint

**Co-locating readers inflates one bin, and that bin may already be the makespan.** The rule: **co-locate
when the fill cost exceeds the imbalance co-location creates.** Per corpus, not as a blanket policy:

| corpus | fill | reader files | verdict |
|---|---:|---:|---|
| `BoutCorpus` | the draw, 1–9 bouts | 3 (`SuiteTier.CORPUS_READERS`) | **must co-locate** — it is the makespan and must be paid once |
| `MapCorpus` 32×24 | 11.2 s | 11 | **decide from the packing**; D1's subtracted quantity scores the choice |
| `MapCorpus` 40×30 | 16.9 s | 3 | as above |

## E4. Stale-profile behaviour is a normal case

A new file has no profile entry. **Assign unknowns a conservative default and say so**, rather than
treating them as free and letting one shard grow a tail.

## E5. Sixteen shards, and not thirty-two

Sixteen is comfortable at ~24 usable cores; thirty-two oversubscribes, and past the point where the
non-corpus shards fall below the corpus shard, extra shards buy nothing. **Derive the number from where
the non-corpus makespan crosses 181–326 s** and report it. Sixteen is the expectation, not the
requirement.

## E6. The profile that feeds the packer comes from an unsharded run

**Sixteen processes competing for twenty-four cores inflates and scrambles per-file wall-clock** — and the
packer reads per-file wall-clock. **A sharded regeneration would degrade the packer's own input a little
more each time.** Keep `tools/profile_suite.gd` on the single-process path and say so in its header.

**TESTS:** the packer produces balanced shards against a known profile; a file absent from the profile
gets the conservative default; the three `CORPUS_READERS` files land in one shard; the shard map is
committed and identical across two runs.

---

# PASS F — A red gate stays readable, and determinism is stated

**Readable failure is what makes people abandon sharding, not the parallelism.**

- **One aggregated verdict**: pass/fail, summed counters, every failure with its file, test and message.
- **Ordering must be stable.** Shards finish out of order; **the report must not.** A gate whose output
  reorders between runs is a gate nobody can diff.
- **A shard that crashes is a gate failure, not a missing section.** Silent partial success is the worst
  outcome available and the easy bug to ship — the same failure mode `run_tests.sh`'s completion guard
  already exists for.
- **Keep the single-process path working.** `./run_tests.sh` unsharded stays available for debugging, and
  it is what Pass A's equivalence test compared against.

**Determinism.** Seeded work is unaffected — separate processes with separately seeded RNGs produce
identical results, because nothing in the suite reads wall-clock or process identity into a seed.
**Assert it** rather than asserting that it is true.

**The corpus draw is deliberately non-deterministic and stays that way** (see Decisions). **Under affinity
sharding exactly one shard draws**, so behaviour is unchanged from today: one draw per gate, shared by
every reader. **That is the property to assert** — it is what would break first if someone later
"improved" the packer by splitting the readers.

**TESTS:** an induced failure in one shard fails the gate and names the test; two runs of the same green
suite produce identical output; a killed shard fails rather than passing quietly; identical fingerprints
sharded and unsharded for one seed; exactly one corpus draw per sharded gate.

---

# SUPERVISOR DECISION — boards from disk

**Pass A measured the supervisor's proposal and it works.** Build boards fresh at gate start, serialise,
hand them out: **loading is 5–6× cheaper than generating** (62.5 ms vs 389 ms at 32×24; 81.6 vs 414 at
40×30) and `MapSerializer` round-trips faithfully 5/5 on a full signature. The refinement Pass A proposed
— a lazy shared disk cache wiped at gate start — is a better shape than a prologue.

**Recommendation: not in this block. Its own PLAN item, after the doc review.** Three reasons:

1. **It does not buy the makespan.** The corpus shard is `BoutCorpus` *playing missions*, not map
   generation. Boards-from-disk makes the other fifteen shards cheaper and unconstrained; the gate still
   ends when the draw ends.
2. **D1 makes the current design correct in the meantime.** Once duplicated fills are subtracted, the
   `MapCorpus` affinity constraint is a pure performance question. Boards-from-disk would then drive the
   duplicated quantity to zero — a clean, measurable follow-up rather than a prerequisite.
3. **It changes how the suite gets its fixtures, and it needs a fidelity guard.** `BR62.05` is this bug
   having happened once — dropped blocker `height`/`size`/`offset`/`facing` that *"round-tripped because
   both ends discarded the same things."* A future `Grid` field added without a serializer update would
   silently change what the whole suite sees. Cheaply guarded (hash before save, after load, same gate),
   but that is correctness work and this block is scheduling.

**One gap to carry into that item if it is taken.** *"The wipe is the invalidation"* holds for the full
gate. A targeted run — change `MapGen`, run one file — does not wipe and reads stale boards. **Wants a
generator stamp in the cache key, or a wipe on any run.**

**Say yes and it becomes Pass G here, after E.** E3's `MapCorpus` rows then read *"unconstrained"*.

---

# Acceptance

- The model is checked against the four historical draws and the result stated.
- `BR65.01`'s arithmetic is re-derived against `p = 0.220` with its interval.
- The completion flake is gone and `FIRST_WIN_CAP` has not moved.
- `probe_seeds.gd`'s advertised cost matches its measured cost, and names the parallel form.
- `maps` and `floods` are equal sharded and unsharded; the duplication is a named, subtractable quantity.
- The shard map is committed, corpus-aware, and identical across runs.
- A failure in any shard fails the gate and names itself; output is stable across runs.
- Exactly one corpus draw per gate.
- The gate is re-measured and **reported as a band, with counters**, against 1333.5 s.
- The profile is regenerated from an unsharded run.

# Not this block's job

- **Threads.** Evaluated and rejected in taskblock-65: the counters are shared statics the profiler
  brackets by diffing, and threading would destroy the per-file attribution that found tb65 Pass D's
  hidden 400-turn bout. **A slower gate is a better trade than never being able to explain one again.**
- **Tuning `TURN_CAP`.** It is a real cost lever — it sets `L`, and `L` is the makespan — but lowering it
  also lowers measured `p` and changes what the completion number means. **A design question, not a
  scheduling one.** Record it; do not turn it.
- **Splitting `test_battle_scene.gd`.** At 63.3 s it sits under the corpus shard. **Trigger recorded:
  split it if it ever becomes the determiner of gate length.**
- **Re-litigating sample-versus-pinned-window.** A3 corrected the *evidence* cited for it; taskblock-46's
  decision stands either way. Correcting the two file headers is doc-review work.
- **Making the corpus's own turn count observable.** Already queued in `PLAN.md`; worth ~250 turns and not
  a sharding change.
- **Cutting any test.** This block changes where tests run, not which ones exist.
- **The doc review.** It follows this.
