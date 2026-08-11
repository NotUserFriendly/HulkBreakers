# Taskblock 65 — A map is a map, and the suite stops paying twice

*Depends on taskblock-64. The full gate is **1429 s** against taskblock-56's 527 s — 2.7× wall clock
on 1.38× the turns, so **a turn now costs twice what it did** and a great deal is being regenerated.*

**Two jobs.** One is a correctness change that happens to unlock the other: **generation must not depend
on who is going to play there.** The other is the suite paying for the same work repeatedly.

**Pass A is a survey with a hard stop.** taskblock-50 built `BoutCorpus` on a premise that turned out
wrong — thirteen files needed *live boards* where the corpus handed out *outcome records* — and the
estimate that motivated it was never checkable. **Do not repeat that.** Measure first, and if the answer
is not what this block expects, stop and report rather than adapting the work to fit.

---

# PASS A — Survey, then stop

**`MapCorpus` already exists.** taskblock-50 Pass E2 built it for this exact reason and **six files read
it.** So the question is not whether to build one; it is why four expensive files still do not use it.

## A1. The holdouts, one at a time

`MapGen.generate` is called **42 times across 19 test files.** The expensive holdouts:

| file | calls | cost | bouts |
|---|---|---|---|
| `test_step_height.gd` | 7 | — | — |
| `test_map_gen.gd` | 7 | 34.9 s | 0 |
| `test_generation_heights.gd` | 4 | 42.4 s | 0 |
| `test_generated_board_sight_sweep.gd` | 3 | 33.9 s | 0 |
| `test_sight_geometry.gd` | 3 | — | — |

**For each one, answer three questions in writing:**

1. **What boards does it need** — which seeds, which dimensions?
2. **Does `MapCorpus` already hold them**, or would it have to widen?
3. **Does it mutate the grid?** `MapCorpus.read()` hands back the cached `Grid` **with no copy**, so a
   mutating reader must call `copy()` or corrupt every later test. That escape hatch exists; a file
   needing it is still a corpus reader.

**A holdout may keep its own boards — with a stated reason.** A test that genuinely needs a board the
corpus does not have is correct as it stands. **A test that regenerates boards the corpus already holds
is not**, and *"it was written before the corpus"* is not a reason.

## A2. The hard stop

**This block expects: most of those calls regenerate boards `MapCorpus` already has, and retrofitting
them recovers on the order of a hundred seconds.**

**Stop and report if any of these is false:**

- The holdouts need **materially different** boards — other dimensions, other seed ranges, or grids they
  mutate in ways `copy()` does not cover.
- The corpus would have to **widen substantially** to serve them, which is a different job from pointing
  files at it.
- **The saving is small** once measured. A retrofit worth twenty seconds is not worth the churn, and
  saying so is the right outcome.

**Report the measured per-file saving before changing anything.** An estimate that cannot be checked is
what taskblock-50 shipped.

**TESTS:** none. This pass produces a written survey.

---

# PASS B — Generation stops depending on who plays there

**`MapGen.generate(map_seed, width, rows, step_height)` takes the roster's stride**, and it is threaded
through six places: `_author_levels`, `_repair_stranded_elevation`, `_ensure_spawns_connected`,
`guarantee_navigability`, `_reach_unreachable_ground`, `MapNavigability.stranding_cells`.

**So map 4242 is a different board for a long-legged squad than for a short one.** That is a misbuild:
**no unit or part feature may affect map generation.** A seed is the whole address of a board.

## B1. Remove the parameter

**Author and repair at a fixed design baseline** — `Unit.BASE_STEP_HEIGHT` as a constant, not an
argument. `generate(map_seed, width, rows)`.

## B2. Navigability becomes a check, not an input

**Split the question by what it is a property of:**

| | property of | becomes |
|---|---|---|
| Is this board internally connected? | the **map** | guaranteed at the baseline, in generation |
| Can **this squad** get around it? | the **pairing** | a **reported check**, never a reshaping input |

**And this restores a failure mode that was engineered away.** Today the generator *guarantees* the
roster can navigate, so **a unit unable to reach somewhere never occurs in a generated bout** — while
the pace-and-shutdown mitigation, the one-way hop-down awareness and Panic all exist to handle exactly
that. **A squad struggling on a board is a finding, not a defect in the board.**

## B3. Record what is being given up

`Unit.lowest_step_height(units)` was introduced in taskblock-62 **so the invariant assumed the worst
case in play.** Removing it means the generator stops promising *every* roster can cross and starts
promising *a standard chassis* can.

**That is a deliberate reversal and it wants a `SUPERSEDED.md` row**, not a quiet edit — the reasoning
that put it there was sound and the reason it is going is different.

**TESTS:** `generate(seed, w, h)` produces an identical `Grid` regardless of any roster in play (**this
is the whole point — assert board equality across two different rosters**); a roster that cannot cross a
generated board is **reported** rather than prevented; existing generation tests pass at the baseline.

---

# PASS C — Adopt the corpus where Pass A says to

Only where A1 justified it. **No test changes what it asserts** — this is where boards come from, not
what is checked.

**Mutating readers call `copy()`.** `read()` returns the cached `Grid` itself; the sharing is the whole
saving, and the hazard is real.

**Re-measure per file.** Pass A predicted; this reports.

**TESTS:** every retrofitted file asserts what it asserted before; a test that mutates a corpus grid
without `copy()` is caught (**assert the hazard, since a silent corruption would surface somewhere
unrelated**).

---

# PASS D — `test_ai_batch_yield` is a fifth of the suite

**279.9 s — 19.6% of the entire gate**, up from 37.4 s at taskblock-56. **7.5×.** Its turns went 136 →
493 across **3 bouts: 164 turns per bout, where the suite average is 14.**

**It tests that a yielding batch produces the identical bout, and that frames pass during the batch.**
Neither claim needs a mission-length bout — **the fingerprint equality is provable in a handful of
turns**, and a longer bout proves it no harder.

- **Cut bout length to something near the suite average**, and keep the fingerprint comparison intact.
- **Do not weaken the equality.** That assertion is the test; the length is not.
- **Its budget was raised in taskblock-58** so wall-clock aborts stopped being its hidden variable.
  Check that the raised budget is still not reached at the shorter length, or the fix silently
  reintroduces what it removed.

**TESTS:** the fingerprint equality passes at the shorter length; the raised budget is demonstrably not
reached; frames still pass during the batch.

---

# PASS E — Find the rest of the repeated work

**Two corpora exist because two people noticed the same pattern twice.** `BoutCorpus` (taskblock-48) and
`MapCorpus` (taskblock-50) both came from *N files each redoing the same expensive thing.* **Nobody has
looked for a third.**

**Sweep for it.** Candidates by shape rather than by name:

- **Repeated identical construction** — the same fixture, preset, shell or board built independently by
  several files.
- **Repeated sweeps over the same range** — the `SEED_COUNT` pattern, wherever else it appears.
- **Subprocess spawning.** `test_suite_run` and `test_run_suite` cost **36 s between them** spawning
  real processes to test the runner. One spawn may serve several assertions.

**Report what was found and what it would cost to share** — including anything found and judged not
worth sharing. **A list is the deliverable; acting on it can be a later block.**

**TESTS:** none required beyond whatever a retrofit needs.

---

# PASS F — A counter the budgets can see

**`test_suite_budget.gd` gates on bouts, turns, candidates, floods, plans and shot planes.** A file that
runs no bout contributes **zero to every one of them.**

**308 files and 640 s — 45% of the suite — are currently invisible to every gate**, and that half grew
**3.3×** since taskblock-56 with the budget green throughout. The largest arrivals are all zero-bout:
`test_generation_heights` 42 s, `test_generated_board_sight_sweep` 34 s, `test_layout_review` 27 s,
`test_three_bars` 21 s.

**Not a wall-clock gate.** taskblock-47 settled that: wall-clock is machine-dependent, it flakes, and
the recorded response to a flaky threshold in this project is to raise the constant.

**Something deterministic that moves when a zero-bout file grows.** Options worth weighing rather than
picking blind: **maps generated**, **scenes mounted**, **modules instantiated**, **subprocesses
spawned**. Each is countable and machine-independent, and each covers a different slice of the invisible
half.

**Pick one or two, say why, and set the budget from the measurement rather than from a guess.**

**TESTS:** the counter moves when a zero-bout file is added and does not move when a bout test is;
exceeding the budget names the file and the delta.

---

# Close-out

**Regenerate `suite_profile.json` and the audit CSV.** They were eight blocks stale before taskblock-64
rebuilt them, which made every suite-cost conversation since taskblock-56 partly guesswork.

**And decide how they stay current** — a line in the workflow, or `run_tests.sh` writing the profile
when the full gate runs. **The staleness is the recurring defect, not this instance of it.**

**Report the gate before and after, with turns and candidates alongside**, so the saving is attributable
to passes rather than to the week.

# When to stop and report

- **Pass A's expectation is wrong** — see A2. This is the designed stop.
- **Pass B changes a generated board** at the baseline step height. It should not; the parameter's
  default *is* the baseline. A difference means something else was reading it.
- **Pass D's shorter bout stops proving the claim.** The equality is the test.

# Acceptance

- `generate(seed, w, h)` produces the same board for any roster.
- Roster navigability is reported, not engineered away.
- Every holdout either reads `MapCorpus` or carries a written reason.
- `test_ai_batch_yield` is near the suite's average bout length with its equality intact.
- A deterministic counter covers zero-bout cost.
- The profile is current and the gate's before/after is reported with its counters.

# Not this block's job

- **`BoutSetup` taking a pre-made board.** Pass B makes it possible — the bout stops drawing
  `rng.randi()` for a map seed — but it is a **determinism change**, and it should not ride on a
  performance block.
- **Deleting tests.** Nothing here cuts coverage; it stops paying twice for the same work.
- **The UI layout tests.** They assert real module-system invariants and they are cheap per test.
  Several assert *declaration* properties by mounting a scene, which is worth noting and not worth a
  pass.
