# Taskblock 67 Report — the gate stops depending on which rung somebody remembered to type

**All four passes landed** — A (the sharded gate enforces the work budget), B (a sharded fast gate,
measured before adoption), C (`fast` and the bare gate become sharded; `profile` names the
single-process rung), D (the loud, recorded fallback) — each green and committed. **A close-out
after them took the evidence half of `BR67.01`**, so a shard that dies now keeps its log; the
entry is `Suspected` — the death itself is one unexplained observation.

| rung | before | after |
|---|---:|---:|
| `./run_tests.sh fast` | 684.4 s, one process | **108–141 s**, sharded |
| `./run_tests.sh` | 1115–1687 s, one process | **180–202 s**, sharded, work budget enforced |
| `./run_tests.sh profile` | — | 1687.7 s, one process, writes the artifacts |
| `./run_tests.sh shard` | the sharded full gate | **retired** |

**The per-pass rung is ~5× faster and, more importantly, it has no corpus draw.** Six controlled
runs — sequential, idle machine — put serial `fast` at 684.7/684.1 s and the sharded fast gate at
113.3/113.8 s, every spread under 1%. The sharded *full* gate on the same tree ran 177.1, 357.5,
499.2 and 733.2 s, a **4.1× spread**, because it ends when the draw ends.

**The sub-1% figure is a controlled measurement and should not be read as what the rung costs on any
given day.** Ad-hoc fast gates run through the rest of the block, on a machine also doing other
work, came in at **108.2, 120.0, 136.5 and 140.5 s** — a 30% range over essentially the same suite.
Nothing there is a draw: it is machine state, and one of them included a self-repack. **The claim
that survives is the structural one** — no bouts, so no distribution — not a promise of 113 s.

**Two things were found rather than built, and both changed what the block did.** The tree was
**already red when the block started** — `floods` over budget — and it was not drift but the corpus
draw, which cost Pass A a counter-subtraction it was not scoped for. And a taskblock-66 finding that
Pass A relied on turned out not to generalise, which moved two baselines after they had been set.

---

## Decisions made without asking

### Pass A: the budget rule stayed in one place, at the cost of an engine start

The spec offered two shapes. The merge could check `SuiteBudget.BASELINE` itself, in Python — fewer
moving parts. **It does not.** `HEADROOM`, `GATED` and the sampled subtractions are one rule argued
across four taskblocks, and a second copy of it drifts in the direction that costs: **a stale Python
baseline passes a run the real rule fails**, and a drift guard that reads low looks exactly like a
suite that did not drift. So `merge_shards.py` writes the totals in `violations()`'s own input shape
and `tools/check_budget.gd` runs the real rule over them. The price is ~2 s of engine start per
gate, against 180 s.

**`files` is written empty and the checker says so where it prints.** A sharded run has no
trustworthy per-file half, so `PER_FILE` is not evaluated — and a green verdict printed without that
sentence would be claiming a check nobody ran.

### Pass A: `floods` and `maps` got the `sampled_turns` treatment, which was not in the block

The first sharded gate with the budget wired was red on `floods`, and stashing proved it red at
clean `HEAD`. **It was the draw, not drift**: the committed profile measured 5972 at a draw of 496
sampled turns, the 5128 baseline came from a draw of 312, and a sharded gate over essentially the
same suite at a draw of 131 measured 4567 — **a 1405 swing, 24%, against 15% headroom.** Three
numbers describing three different quantities, which is exactly the error `suite_budget.gd`'s own
`turns` note names.

**The alternative was re-ratcheting `floods` to 5972**, which is one line and calibrates the budget
to a single draw — the *"raise the number until it stops"* failure the file is written against. The
supervisor chose the subtraction. `CompletionSampler.sampled_floods` and `sampled_maps` now bracket
the whole of `run_seed`, because a sampled bout floods while its board is generated *and* every time
the planner asks a reachability question, so there is no single call site.

**Demonstrated rather than asserted, across four gates.** Raw `floods` spans 4361–6182 (42%);
controlled, two sharded runs sit 2.4% apart. Controlled `maps` read **974 on two profile runs whose
draws differed by 2.4×** — identical, while raw moved 13.6%.

### Pass A: an un-evaluable counter is announced, not skipped and not failed

Adding a counter to the budget **deadlocks the gate**: the profile cannot carry `sampled_floods`
until a green full gate writes it, and the gate cannot go green while `floods` is judged against a
baseline the profile cannot support. Silently skipping is a hole; failing is the deadlock.
`SuiteBudget.unevaluable()` reports it as **`NOT CHECKED`**, and a source sweep over
`tools/run_suite.gd` stops the skip becoming permanent — **that reads the runner rather than the
artifact**, which is the only way to tell *this counter was removed* from *this profile is one gate
old*. Built as a mechanism rather than a one-off because `PLAN` queues `bouts` and `candidates` for
the same treatment and each hits the identical wall.

### Pass C: `shard` was removed against the spec, on instruction

taskblock-67 C1 keeps `shard` as an explicit alias and the acceptance list requires it to resolve.
**The supervisor asked for it to go.** Worth recording that the spec's own reason does not survive
the pass: it keeps the alias so taskblock-66's sharded-versus-single-process equivalence check stays
possible, and after Pass C the bare gate *is* the sharded side and `profile` *is* the single-process
side. It is **refused by name** rather than falling through to *"no test file or directory named
'shard'"* — true, useless, and how a ninth entry joins the taskblock-66 census of eight stale claims.

### Pass C: the fast gate does not run the budget check

It skips 21 bout-building files, so its totals are a fraction of the suite's and every gated counter
reads low against a whole-suite baseline. **A check that cannot fail is worse than no check** — it
prints a reassuring line nobody should trust — so it prints *"not checked: a fast gate measures part
of the suite"* where the verdict would be.

### Pass D: a third test seam exists purely to stop the gate editing the repo

`HB_SHARD_MAP` and `HB_DRY_RUN` are the obvious two. **`HB_REPACK_CMD` is the one worth flagging:**
without it, a test driving the stale-map branch would repack the two committed maps as a side
effect — the gate rewriting the repo because a test asked it a question. `HB_DRY_RUN` exits **3,
never 0**, so a stray export cannot be mistaken for a pass.

### Pass B: bout files are removed from the fast map, not costed at zero

B3 says *costed at zero*; the TESTS say *no bout file is in the fast map*. Removal is what makes the
second true, and it is also better: a zero-costed file is still loaded and parsed by whichever shard
holds it. **Eight shards not seven, derived** — every corpus reader is a bout file, so removing them
removes the reason to reserve shard 0, which goes from 0.5 s to 92.3 s of work.

---

## Tests that failed, then were corrected

**Five, and two of them were mine being wrong about what I had just built.**

1. **`test_suite_budget.gd` was red before the block started**, on `floods` 5972 over 5898. Verified
   at clean `HEAD` by stashing rather than reasoned about. Root cause was the draw, not drift; fixed
   by subtracting the draw's own floods, not by moving the number. **This is taskblock-66's
   write-the-profile mechanism landing one run late, as designed** — the gate that wrote the numbers
   read the old ones and passed.
2. **`test_suite_run.gd` failed under sharding and passed alone.** It counted **every** Godot on the
   machine and compared before against during; the first sharded gate read `before 8, during 8`
   because a sibling shard exited inside its six-second wait and masked the new engine exactly.
   Alone it read `before 1, during 2, after 1`. **A relative measure over a number the test does not
   own** — now scoped to the run's own process group, which makes the assertions absolute (some,
   then none) and asks precisely what its docstring always claimed.
3. **Three of my own new budget tests failed at once, all the same fixture error.** They were written
   before `unevaluable()` existed, so their synthetic profiles had no `sampled_*` keys and were
   silently exercising the *skip* instead of the budget. Fixed by making `_synthetic()` default
   those keys to zero, with one test that omits them on purpose. **The tests were wrong, not the
   code** — and they were wrong in the direction that passes, which is why the default matters.
4. **`test_shard_map.gd` failed twice for the intended reason**, both times because a new file made
   the committed map stale. That is the signal — a file in no shard is never run — and Pass D is
   what turned it from a manual repack into the gate fixing its own input.
5. **A sharded gate went red on `shard 0: DID NOT FINISH` and could not be explained.** Filed as
   `BR67.01`. The merge behaved correctly; what failed was the ability to investigate.

---

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** This block closed no entry and moved none to `Pending`. It opened one, `BR67.01`, which is
`CC`-owned.

---

## Open questions

### `BR67.01` — a shard died and the evidence was deleted before anyone could read it

One sharded gate in four went red on `shard 0: DID NOT FINISH` with the other seven green at 0
failures. Shard 0 is green in isolation (288.9 s) and was green on the next gate at a near-cap N=8
draw. No OOM; the machine has 61 GB and 32 cores. **The reportable part is structural rather than
bad luck: `run_tests.sh` writes shard logs to `mktemp -d` under a cleanup trap, so the one artifact
that would name the cause is deleted at the moment the gate reports the failure.** The taskblock-66
addendum hit the same wall from the other side and had to mirror the shard block by hand.

**The evidence half was fixed in a close-out after the passes, on the supervisor's instruction.** A
shard with no summary now has its log copied to `out/logs/gate/<utc>/`, the path printed, and the
incident recorded. **Verified against a real death rather than a fixture** —
`TestExitCodeProbe.FORCE_DEATH_ENV` makes a shard kill its own process, reproducing the signature
exactly, and the preserved log ends at the last test the shard entered, which is what was missing.

**The entry is `Suspected`, and I first set it to `Active` wrongly.** What is fixed is the ability
to investigate; the cause is **one observation with no reproduction and no mechanism** — green in
isolation, green on the next gate, no recurrence in the ~10 sharded gates since. That is what
`Suspected` is for, and `BR66.01` is the precedent: it sat `Suspected` until reproduced in
isolation, then moved to `Active`.

**The reasoning error is worth recording because it is repeatable.** I tested `Active` only against
the two *closing* statuses — not `Resolved`, not `Obsolete`, therefore `Active` — and never against
`Suspected`. Ruling out closure says nothing about whether a lead has been confirmed. `Suspected`
also carries an obligation `Active` does not: refine it at a review pass rather than letting it sit.

### The sharded and unsharded gates disagree about `maps` and `floods` by 10–14%

**taskblock-66 Pass D's finding that counts are process-count-invariant once duplication is
subtracted does not generalise to these two at whole-suite scale.** It was verified on one case and
holds there; measured across the whole suite, controlled `floods` reads 4687 unsharded against
4273–4462 sharded, and `maps` 974 against 857.

The leading explanation is that **`MapCorpus.forget()` has process-local scope** — two files call it,
in different shards, and in one process each wipe forces every later reader of all 155 keys to
refill where sharded a wipe reaches only its own shard. Direction and rough size match; **it has not
been isolated experimentally.**

**The baselines are taken from the unsharded profile deliberately**, being the higher of the two, so
a sharded gate measures under budget rather than red. **The price is that a sharded gate carries
10–14% more slack on those two counters** — it sees systemic growth and would miss a small drift an
unsharded gate catches. Worth an hour to isolate, and worth knowing before anyone tightens
`HEADROOM`.

### The profile mispredicts the sharded makespan by 11% in both directions

Full map: predicted 139.5 s, measured 124.5 s. Fast map: predicted 89.0 s, measured 99.0 s. Per-file
`usec` is measured single-process, and the full map leaves shard 0 empty with uneven loads so its
wall shard finishes among fewer competitors than the profile assumed — while the fast map keeps all
eight busy, which is **maximum contention**. **Perfect balance maximises contention**, so a packer
minimising predicted makespan is optimising the wrong quantity by a knowable margin. Whether that
margin is stable is not known, and it bears on whether the packer is worth improving at all.

### A methodology error in Pass B's measurement

I edited `test_shard_map.gd` while serial run 1 of six was still in flight. That run reports 3280
tests and the other five report 3283 — exactly the three tests added. The two serial runs agree to
0.65 s, so no conclusion depends on it, **but the six runs were not all over an identical suite** and
the 3280 would otherwise sit in the log unexplained.
