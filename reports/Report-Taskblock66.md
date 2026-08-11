# Taskblock 66 Report — Shard the gate, and the makespan is one draw

**Pass A has landed; B through E have not.** All five of its items pass and none of the four
stop-and-report conditions fired. **`p` is measured at 0.220 across 100 seeds** spanning the real draw
space, which replaces every pre-pass estimate in the spec and in this report.

**The headline for the block, restated against measured inputs:** the corpus shard is **180–326 s
typical** and **424–766 s at the cap**, against **1333.5 s today** — roughly **3–5 minutes typical, 7–13
at worst, against 22**. The cap draw is a **1-in-9.4** event, not the 1-in-4.3 the spec assumed.

<!-- Rewrite this opening whenever a later pass moves it. -->

## Decisions made without asking

### A defect in the spec's inputs, recorded before Pass A ran — and an estimate from it that did not survive

The spec's pre-pass `p` came from four draws recovered from committed profiles, read as **2, 2, 7, 6**
corpus seeds off `test_watched_run.gd`'s bout count. **That file builds one bout the corpus did not
draw** — `test_a_watched_seed_matches_what_the_headless_path_reported` reads `BoutCorpus.rows()` and
then replays the corpus's first recorded seed through a paced `BoutRunner`, which is the entire point of
the test. Its bout count is always **corpus draw + 1**.

Confirmed by direct observation, on one run where both numbers are visible:

```
taskblock-65 fullgate3 log:   seeds to first completion: 5
profile that run wrote:        test_watched_run.gd bouts = 6
```

**The accounting defect is real. The correction I derived from it was not an improvement.** I restated
`p̂` as 0.308 (4 wins / 13 seeds) against the spec's 0.235 (4/17). **Measured over 100 seeds, `p` is
0.220** — nearer the spec's figure than mine. Both were four-draw estimates and both were noise; the
100-seed measurement supersedes them equally. Recorded because reporting the verified half without the
overshoot would make the finding look better than it was.

**The cost inputs moved the way I said, and by more than I said.** I argued `W` was too high and `L` too
low. Measured: **`W` 45.6 against the spec's 58.3**, **`L` 61.3 against the spec's 34.7** — directionally
right on both, badly wrong on the magnitude of `L`, which I had put near 39.

**What survives regardless of where `p` landed, and why the finding still mattered:** **A4 compares the
live draw against `seeds_played`, not against a bout count.** `seeds_to_first_win` already returns it and
the gate already prints it (`"seeds to first completion: N"`). Inferring the draw from a file's bout
count is the exact step that produced the error, and it would have made every confirmation run report a
false mismatch of exactly one bout.

### Two of the spec's corrections to taskblock-65 are accepted, and verified

**Fisher exact on the recorded 5/12 vs 8/12 window comparison gives p = 0.414** — reproduced. The
"pessimistic window" note in `completion_sampler.gd:12` is noise, and taskblock-65 citing it as evidence
was wrong. **Pass A3 tested it directly rather than assuming either way: chi-square across ten scattered
windows gives 11.42 on 9 df against a critical value of 16.92 — no evidence the windows differ.** Both
file headers that carry the belief should be corrected; that is noted for the doc review rather than done
here.

Taskblock-65's 15.7× headline was bin-packed against a profile the next commit replaced, and described
the luckiest available draw. Accepted.

### `maps` and `floods` are gated counters that sharding inflates, and Pass C has to answer for it

Pass A1's equality test ran six files unsharded, then one-file-per-shard across six concurrent
processes. **Nine of eleven counters match exactly**, so the aggregation mechanism — the thing A1
actually gates on — is sound. Two do not:

| | bouts | turns | plans | candidates | planes | ui_builds | spawns | **floods** | **maps** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| unsharded | 5 | 16 | 16 | 24940 | 72 | 93 | 8 | **667** | **242** |
| summed shards | 5 | 16 | 16 | 24940 | 72 | 93 | 8 | **703** | **260** |

Traced per shard, it is `MapCorpus` duplication and nothing else:

```
test_map_navigability.gd   unsharded 0 maps / 0 floods    sharded 12 / 24
test_mag_lift.gd           unsharded 1 map  / 3 floods    sharded  8 / 17
```

**Both are in `SuiteBudget.GATED`.** A sharded gate therefore reports inflated values against baselines
measured unsharded, and the shard map's affinity choices move a gated counter. **Stated as a benefit as
well:** `maps` inflation is now a direct numeric measure of how badly a shard map splits corpora — a
perfect affinity map inflates it by zero — which makes C3's rule checkable rather than argued.

### The supervisor's map proposal: I evaluated the wrong version first

Asked why shards regenerate boards rather than being handed them, I evaluated **committed board
fixtures** and spent most of the answer on staleness. **That was not the proposal.** The supervisor's
design is *build fresh at gate start, then hand out* — which removes staleness entirely, because the
boards are as fresh as the generator that made them. Recorded because the correction changed the
conclusion, not just the emphasis.

**Measured**, with a full signature over heights, blocker `height`/`size`/`facing`, surfaces and spawn
markers:

| board | generate | load | round-trip | size |
|---|---:|---:|---:|---:|
| 32×24 | 389 ms | **62.5 ms** | **5/5 faithful** | 141 KB |
| 40×30 | 414 ms | **81.6 ms** | **5/5 faithful** | 219 KB |

*(Both under A3's load, so the ratio holds even though the absolute generate figures are inflated
against taskblock-65's 224/337 ms.)*

**Loading is 5–6× cheaper than generating and `MapSerializer` round-trips faithfully.** What it buys, in
order: **it deletes C3's affinity constraint** and drives A1's measured inflation to zero, because a
board that is an *input* costs nothing to share; and ~20 s on an unsharded gate.

**What it does not buy: the makespan.** The corpus shard's cost is `BoutCorpus` *playing missions* — at
the measured `p`, 4.06 seeds averaging 55 turns — not map generation. Boards-from-disk makes the other
fifteen shards cheaper and unconstrained; the gate still ends when the draw ends.

**A refinement worth considering over a prologue:** a **lazy shared disk cache wiped at gate start**.
`MapCorpus.read()` checks a scratch directory, loads if present, generates-and-saves if not. No prologue,
no need to know in advance which boards the suite wants, the wipe *is* the invalidation, races are benign
(identical content, atomic rename), and the unsharded path is unchanged because the in-process cache
short-circuits before touching disk.

**The one risk that survives the correction is `MapSerializer` fidelity.** `BR62.05` is precisely this
bug having happened once — it dropped blocker `height`/`size`/`offset`/`facing` on *both* ends and
"round-tripped because both ends discarded the same things". Fixed at tb63 D3, and the fields survive
today. But a future `Grid` field added without a serializer update silently changes what the whole suite
sees, where today it is an editor inconvenience. Under this design that is **cheaply guarded in-run**:
the board is generated and loaded in the same gate, so hashing before save and after load is nearly free.

## Tests that failed, then were corrected

*(none yet — Pass A adds no tests; its deliverable is measurement)*

## Open questions

### Pass A's measured inputs, and the model re-issued

| input | spec | **measured** | source |
|---|---|---|---|
| `p` | 0.15–0.25 | **0.220** (95% CI 0.139–0.301) | 100 seeds, windows at 0…9000 |
| `L` losing bout | 34.7 turns | **61.3 turns** | 78 losers, 30 of them at the 100-turn cap |
| `W` winning bout | 58.3 turns | **45.6 turns** | 22 winners |
| per-process floor | 1.05 s | **1.29 s** | 1.21 / 1.29 / 1.36 s |

| | turns | seconds |
|---|---:|---|
| E[draw] | 235 | **180–326 s** |
| cap draw (9 losers) | 552 | **424–766 s** |
| E[seeds played] | 4.06 | |
| P(cap, no win) | | **0.107 — 1 gate in 9.4** |

**A2's floor is 23% above taskblock-65's figure and is not material**: 20.6 s of total floor across 16
shards against 16.8 s, i.e. ~4 s against a makespan of 180–326 s. It does not move the shard count.

**A5 passes in the harder case.** All three subprocess-spawning files ran in *simultaneous* shards — 29
tests, 0 failures, 8 spawns each for 24 total, matching unsharded exactly. PID-keyed log paths held.

**A4's live draw agrees with the model but is a weak check by construction.** One clock-drawn escalation
won on its first seed (9711, EXTRACTED in 33 turns, 49.8 s). `P(N=1) = 0.22`, so a single observation
constrains almost nothing — it confirms the live path and the model describe the same thing, which is
what A4 is for, and it is not evidence about the distribution.

### `BR65.01` is less severe than filed, and Pass B's justification should be restated

The entry says `test_seeds_to_first_completion_stays_low` goes red on **P = 0.232, about one gate in
four**, computed from `p = 0.15`. **At the measured `p = 0.220` it is P = 0.107 — one gate in 9.4.**
Still a real flake and still worth Pass B, but the "one in four" figure should not survive into the fix,
and the cap arithmetic in the entry (28 for ~1%, 18 for ~1 in 20) is derived from the old `p` and wants
re-deriving before anyone sizes anything against it.

### Whether the boards-from-disk refinement lands in this block or its own

It simplifies Pass C materially and it is measured, but it changes how the suite gets its fixtures rather
than how it is scheduled. **Both C3 as specified and the refinement reach the same place**; the
refinement removes a constraint rather than satisfying it. Left as the supervisor's call.
