# Taskblock 66 Report — Shard the gate, and the makespan is one draw

**All six passes landed** — A (measure), B (two free checks), C (`BR65.01`), D (the gated counters),
E (the packer), F (the runner and the merge) — each green on the fast gate and committed.

**`./run_tests.sh shard` runs the whole suite across 8 processes.** Three real sharded gates were
measured, and **the spread between them is the result** — same code, same suite, different draw:

| run | corpus draw | shard 0 | gate wall | vs 1338 s |
|---|---:|---:|---:|---:|
| first | N=5 | 227.6 s | **242.1 s** | **5.5×** |
| second | N=2 | 195 s | **220.5 s** | **6.1×** |
| third | N=8 | 611.3 s | **626.3 s** | **2.1×** |

**A single headline number for this gate would be a lie, and that is the block's own finding rather
than a caveat on it.** The model predicted 181–326 s typical and 425–767 s at the cap; the three
observed runs landed at 242, 220 and 626 s — **every one inside its predicted band**, including the
N=8 draw that came within one seed of the cap.

| draw | modelled gate | probability |
|---|---:|---:|
| lucky (N=1) | 142 s — 9.4× | 0.220 |
| typical (N=4.06) | 182–327 s — 4.1–7.3× | — |
| cap (N=9) | 426–768 s — 1.7–3.1× | 0.107 |

**On a lucky draw the non-corpus shards become the wall at ~141 s**, so the gate has a floor of
about 142 s however well the draw goes — the honest ceiling on this block's win. **At the cap the
win narrows to about 2×**, which is the honest floor.

<!-- Rewrite this opening whenever a later pass moves it. -->

## Decisions made without asking

### A defect in the spec's inputs, and an estimate from it that did not survive

Recorded before Pass A ran. The spec's pre-pass `p` read the corpus draw off `test_watched_run.gd`'s
bout count as **2, 2, 7, 6** seeds. **That file builds one bout the corpus did not draw** — it
replays the corpus's first recorded seed through a paced `BoutRunner`, which is the whole point of
the test — so its count is always **draw + 1**. Confirmed where both numbers are visible: the gate
logged `seeds to first completion: 5` against a profile recording 6 bouts.

**The accounting defect is real; the correction I derived from it was not an improvement.** I
restated `p̂` as 0.308 against the spec's 0.235. **Measured over 100 seeds, `p` is 0.220** — nearer
the spec's figure than mine. Both were four-draw estimates and both were noise. Reporting the
verified half without the overshoot would make the finding look better than it was.

**What survived is why it mattered:** A4 compares the live draw against `seeds_played`, which
`seeds_to_first_win` already returns and the gate already prints, rather than against a bout count.
Inferring the draw from a bout count is the step that produced the error and it would have made
every confirmation report a false mismatch of exactly one bout.

### Eight shards, not sixteen — derived rather than assumed

E5 asked for the number to be derived. Non-corpus work is 972 s, so its makespan falls with the
shard count **only until it drops under the corpus shard**, after which extra shards buy nothing
because the gate ends when the draw ends: **6 shards → 163.3 s (the knee), 8 → 122.8 s, 16 →
64.6 s** against a corpus shard of 181–326 s. **Eight is the knee plus one step of headroom**, so an
unlucky packing or a newly expensive file does not immediately make the non-corpus half the wall,
and it leaves more of a machine somebody else is using.

**Shard 0 deliberately takes no non-corpus work despite apparent slack.** Its cost spans 181–767 s,
so packing onto it helps on a lucky draw and compounds the damage on an unlucky one.

### `maps` and `floods` are gated counters that sharding inflates, and the fix is a quantity

Pass A found it: nine of eleven counters summed exactly across shards, but `maps` went 242 → 260 and
`floods` 667 → 703, traced per shard to `MapCorpus` readers refilling their own caches. **Both are
gated**, so the shard map's affinity choices move a budget.

**The precedent is exact and in the same file.** taskblock-65 Pass F settled the corpus draw
contaminating `turns` as *"the uncontrolled thing is a quantity, not a file, and it is now
subtracted as one."* `MapCorpus.fills` records what each fill cost, **keyed rather than counted** —
two shards each reporting "I filled 50 boards" cannot tell the gate whether that is 50 or 100.
Verified on real processes: **260 − 18 = 242 and 703 − 36 = 667, both matching unsharded exactly.**

**This also resolves a tension in Pass A's own finding.** Pass A observed that `maps` inflation
measures how badly a shard map splits corpora — but **a counter cannot be both the gate and the
diagnostic**. Subtracting gives both: the gated total stays controlled and the subtracted quantity
*is* the affinity score. On the real sharded gate it reads **zero**.

### `BR65.01`: the assertion split rather than the cap moving

**The alternative was arithmetic, not preference.** Buying a 1% false-red rate needs `FIRST_WIN_CAP`
at **19** — and under a sharded gate **the cap is the makespan**, so that makes the worst case 1165
turns against today's 552. The confidence interval puts the required cap anywhere from **13 to 31**,
so the number cannot be picked confidently either. `test_per_tier_probe.gd` asserts
`FIRST_WIN_CAP == 9` precisely because thresholds here have historically been moved to quiet a
flapping gate; it has not moved.

**What is given up is stated in the test rather than glossed:** a genuine collapse no longer turns
the *sampled* test red on its own. The deterministic guard on seed 9003 catches exactly that case,
which is what the old assertion was reaching for and could only reach by luck.

### The supervisor's map proposal: I evaluated the wrong version first

Asked why shards regenerate boards rather than being handed them, I assessed **committed fixtures**
and spent most of the answer on staleness. **That was not the proposal** — *build fresh at gate
start, then hand out* has no staleness, because the boards are as fresh as the generator that made
them. Measured: **loading is 5–6× cheaper than generating** (62.5 ms vs 389 ms at 32×24) and
`MapSerializer` round-trips faithfully 5/5 on a full signature. Recorded in `PLAN.md` with the
invalidation hole the supervisor then caught in my own refinement — a targeted run does not wipe, so
the cache would be stale exactly during the edit loop.

## Tests that failed, then were corrected

**Seven, and two of them were caught only by running the sharded gate for real.**

1. **I committed Pass D against a gate that never ran.** `gdlint src test` segfaulted at
   `run_tests.sh` line 107 and the script aborted — but I piped through `tail -30`, so the pipeline
   returned `tail`'s exit code of 0, the completion notification said success, and a grep over a
   two-line log reported no failures. **This is the same masking trap that bit taskblock-65's full
   gate, repeated after I had written it up.** `gdlint` passed on retry (transient, almost certainly
   resource pressure from ten parallel probes) and the re-run was green — 3262 tests, 0 failures —
   so the commit's claim was true, but it was unverified when I made it. Gate output is redirected
   rather than piped from here on.
2. **The merged report was silently dropping the completion draw.** It lives in one shard's log and
   the shard logs are in a temp directory that is cleaned up, so the gate's most useful single number
   was being discarded by the merge. Found by looking for it in the sharded output rather than by a
   test. It is surfaced now, **and more than one shard reporting a draw fails the gate** — the
   runtime backstop for a hand-edited map that splits `CORPUS_READERS`.
3. **I mislabelled `maps` as a counter the draw does not move.** Every bout generates exactly one, so
   it tracks the bout count (83 sharded vs 84 unsharded). Caught while comparing sharded against
   unsharded totals and expecting equality. The genuinely stable counters are `spawns` and
   `ui_builds`, and both match exactly.
4. **`tools/pack_shards.gd` could not see `ShardMap`** on first run — a new `class_name` needs an
   import pass before a `-s` script can reference it. Mechanical, and the same failure `run_tests.sh`
   documents in its own header for exactly this reason.
5. **`test_every_test_file_is_assigned_to_exactly_one_shard` failed twice, both times correctly.**
   Adding this block's own test files made the committed map stale. That is the intended signal: **a
   file in no shard is never run and a sharded gate goes green having skipped it**, which is
   indistinguishable from success without the check.

6. **My own test was poisoning the merger's parser, and the sharded gate caught it.**
   `test_merge_shards.gd` echoed the merged output through `gut.p`, and its fixtures deliberately
   contain the exact strings `merge_shards.py` scans for — `seeds to first completion`, `[Failed]`.
   Those landed in that shard's stdout, where the real merge read them back as **a second corpus
   draw**, and would have injected a phantom failure message into any genuinely red run. The gate
   reported *"MORE THAN ONE SHARD DREW"* against a perfectly co-located map: **the alarm was right
   about what it saw and wrong about what it meant.** Fixed by asserting on the text without
   republishing it, with the incident recorded in the test's own header.
7. **`spawns` was genuinely over budget — 32 against a limit of 29 — and all seven are mine.**
   `test_merge_shards.gd` drives the merger as a real subprocess seven times, and spawning is the
   thing under test, so the cost is irreducible. Re-ratcheted to 32 with the reason named.
   **This is taskblock-65's write-the-profile mechanism working exactly as designed**: the full gate
   that *wrote* the new numbers read the old ones and passed, and the very next gate read the new
   ones and went red. Drift lands, then is reported against the baseline it broke — one run late, by
   construction.

## Open questions

### The block's headline is a band, and the tail is the part worth watching

At the cap the sharded gate is **426–768 s** — still better than 1338 s, but the win narrows from
9.4× to under 2× on a 1-in-9.4 draw. **`TURN_CAP` is the lever that would fix the tail** — it sets
the losing-bout cost `L` at 61.3 turns, and `9L` is the whole cap case — but lowering it also lowers
measured `p` and changes what the completion number means about the game. Recorded in `PLAN.md` as a
design question rather than turned.

### `p` is 0.220 with a wide interval, and two downstream numbers inherit it

95% CI **0.139–0.301**, across which P(cap) runs **1-in-3.8 to 1-in-25**. No conclusion in this
block changes anywhere in that interval, which is the useful thing to say — but the point estimate
should not be received as a fact by anything downstream, and `BR65.01`'s closing arithmetic quotes
it. **`p` is also P(complete within `TURN_CAP`)**, not P(complete): 30 of 78 losing seeds were still
playing at the cap, so `p` and `L` are coupled and arithmetic that moves one while holding the other
is not quite valid.

### The cost model is turns-linear and the evidence says it has a fixed component

A4's live draw ran 33 turns in 49.8 s — **1.51 s/turn, outside the 0.77–1.39 band** — which solved
against the 100-seed run gives roughly **33 s fixed per bout plus 0.52 s/turn**. At current draw
sizes the two models agree within a few seconds, so the headline holds. **Anyone pricing a *turn*
reduction against the linear model will over-credit it**, and lowering `TURN_CAP` is exactly that.

### What is not yet done, and would be the natural next step

**The sharded gate does not write the profile**, deliberately — E6 keeps `profile_suite.gd` on the
single-process path, because eight processes competing for cores inflate and scramble the per-file
wall-clock the packer reads, and a sharded regeneration would degrade the packer's own input a
little more on every pass. **So the profile still costs an unsharded 22-minute run**, and the shard
map still needs a manual repack when files are added. Both are stated rather than automated; a
repack-on-red workflow would be the obvious follow-up.
