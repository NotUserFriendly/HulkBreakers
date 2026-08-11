# Taskblock 66 Report — Shard the gate, and the makespan is one draw

**In progress.** This opening is a placeholder and is rewritten when the passes land.

<!-- Rewrite this opening whenever a later pass moves it. -->

## Decisions made without asking

**A defect in the spec's own inputs, found while evaluating it and recorded before Pass A ran.**

The block's pre-pass estimates of `p` come from four "real draws" recovered from committed profiles,
read as **2, 2, 7 and 6 corpus seeds** off `test_watched_run.gd`'s bout count. **That file builds one
bout the corpus did not draw.**
`test_a_watched_seed_matches_what_the_headless_path_reported` reads `BoutCorpus.rows()` and then builds
its own — `CompletionSampler.build_for_seed(recorded[0].seed)`, replayed through a paced `BoutRunner`
— because the whole point of the test is to compare a *watched* run against the corpus's headless
record. So the file's bout count is always **corpus draw + 1**.

**Confirmed by direct observation rather than inferred**, on one run where both numbers are visible:

```
taskblock-65 fullgate3 log:   seeds to first completion: 5
profile that run wrote:        test_watched_run.gd bouts = 6
```

So the four draws were **1, 1, 6, 5** corpus seeds, not 2, 2, 7, 6:

| estimator | spec | corrected |
|---|---:|---:|
| MLE, uncensored (4 wins / seeds) | 0.235 (4/17) | **0.308** (4/13) |
| with taskblock-65's censored cap-9 no-win | 0.154 (4/26) | **0.182** (4/22) |

It moves the cost inputs too, and in opposite directions. Two of those draws won on their **first**
seed, so their watched replay re-ran a *winner* — 2 winners in 88 turns and 2 in 82, implying
**`W` ≈ 42 rather than 58.3**, and pushing `L` up to compensate.

**Nothing was changed in the spec and no pass was reordered.** A3 measures `p`, `L` and `W` properly
and replaces every one of these numbers, so the correction only governs the pre-pass table. **What it
does change is two things inside Pass A**, and both are acted on:

- **A4's confirmation draw would report a false mismatch.** The live path shows one more bout than the
  model predicts, every time. It is compared against `seeds_played`, not against a bout count.
- **`seeds_played` is already returned by `seeds_to_first_win` and already printed by the gate**
  (`"seeds to first completion: N"`). A3 and A4 read that rather than inferring the draw from a file's
  bout count — which is the exact inference that produced this error.

**The alternative was to run Pass A against the spec's numbers and correct them afterwards**, which
would have left A4's confirmation looking like a disagreement between model and reality when it is an
accounting difference.

**Two things the spec corrects in taskblock-65's report, accepted rather than argued.** Fisher exact on
the recorded 5/12 vs 8/12 window comparison gives **p = 0.414** — verified — so the "pessimistic
window" note is noise, and citing it as evidence was wrong. And taskblock-65's 15.7× headline was
bin-packed against a profile the next commit replaced; the number described the luckiest available
draw. Both are the spec's findings, not this report's.

## Open questions

*(pending — the passes have not run)*
