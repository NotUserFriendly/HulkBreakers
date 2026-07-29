# Taskblock 48 — Three rungs, a window on the run, then the collapse

*Advances `PLAN.md`'s *The suite's remaining cost* and *The supervisor-runnable test surface,
finished*. Depends on taskblock-47.*

taskblock-47 took the full gate to 537 s and made its cost legible. This block makes the loop cheap,
gives the supervisor an unmediated view of what CC actually runs, and then collapses the two files
that are 57% of what remains.

**Order is deliberate and the repeat work is intentional.** The tooling lands first because it pays
for itself during this block. The window lands before the collapse so the supervisor watches the
change happen against a baseline they took themselves, rather than being handed a result.

---

# PASS A — Three rungs, and every run reports what it cost

## A1. A targeted run

`run_tests.sh` accepts only `fast` or `full` and exits 2 on anything else, so **there is no way to run
one file.** GUT has supported `-gtest=` and `-gdir=` the whole time; this is a wrapper gap, not a
capability gap. The cost of the gap is the whole problem — `test_utility_planner.gd` alone is 7 s
against the full gate's 537 s, and most files are under a second.

```
./run_tests.sh test_foo.gd   # one file — the edit loop
./run_tests.sh fast          # everything that does not build a bout
./run_tests.sh               # everything. Green before a pass commits.
```

- **A bare filename resolves by search.** Nobody should type `res://test/unit/logic/ai/...`. If two
  files ever share a name, print both paths and exit — that is a repo mistake to fix, not a case to
  disambiguate cleverly.
- **A directory argument works too**, since `-gdir=` already does.
- **Measure the floor and report it.** Every invocation pays `gdlint src test`, the warm-up import and
  the parse guard before GUT starts. On a sub-second file that fixed cost probably dominates, and the
  honest answer may be "a targeted run costs 8 s, not 1." Still a large win — but find out rather than
  discover it later. If the overhead dominates, say which parts are safely skippable for a targeted
  run and which are not.

**A targeted run is never what a pass is green on.** It cannot see that a change broke a different
file, which is the entire reason the full suite exists.

## A2. The profiler becomes the runner

Work counts exist only in-process, and only `tools/profile_suite.gd` collects them — it hosts
`GutRunner` itself to get `start_script`/`end_script` boundaries. A normal run goes through
`gut_cmdln.gd` and produces **no counts at all**. So there are two entry points into one suite and
**only one of them fails the build**: `gut_cmdln.gd` has `-gexit`, while `profile_suite.gd` sets
`should_exit = false` and returns 0 after writing its JSON.

Collapse them. The profiler's own header already says the snapshots cost "a handful of integer reads —
the profiler is close to free," so this is nearly free counts on every run.

- **Failure must propagate as an exit code.** This is the actual work of A2 and it is a gate change:
  a runner that reports counts beautifully and exits 0 on a red suite is worse than no change at all.
  **Test it** — a deliberately failing test must fail the process.
- **Print counts always; write the artifacts only on request.** `SUITE-PROFILE.md` and
  `suite_profile.json` are committed, and rewriting them every run churns the tree and puts noise in
  unrelated diffs.
- **This also fixes a limitation taskblock-47 flagged.** The budgets currently read the committed
  profile, so they catch a regression when the profile is regenerated rather than when it lands. Counts
  from the live run close that gap.

## A3. The cost delta CC reports

**Per file touched, not per suite.** CC's pre-greenlight loop is targeted runs plus the fast gate — and
the fast gate skips exactly the bout files where turns come from, so a fast-gate run reports roughly
zero turns no matter what changed.

Running one file gives that file's counts, and the committed profile already holds its previous
numbers, so the diff is exact and cheap. **`+3 tests, +47 turns in test_utility_planner` is a
vetoable statement. `+47 turns somewhere` is not.**

**TESTS:** a bare filename resolves to the right file; an ambiguous name fails with both paths; a
failing test fails the process through the new runner (**this one is the pass's real acceptance**); a
clean run does not modify the committed profile artifacts; the per-file delta matches a hand-computed
diff against the profile.

---

# PASS B — A window on the run

## B1. It is a panel, not another overlay

**`WatchedRunOverlay` extends `SpectatorOverlay`** — a fifth subclass in a hierarchy `PLAN.md`'s *One
view, toggleable modules* exists to dissolve. Its reasoning is sound in isolation (a watched bout
should have every control a normal bout has) and it is the same reasoning that produced the hierarchy.

The precedent is already in the tree: **`CombatLogPanel` is a `VBoxContainer` that both
`SpectatorOverlay` and `SquadControlOverlay` instantiate.** It survives the collapse untouched because
it never joined the hierarchy.

- **The new surface is a panel**, hosted by whichever overlay is up.
- **Move `WatchedRunOverlay`'s two labels and its end-of-bout hook into a panel too**, so this block
  ends with one fewer overlay subclass rather than one more. The sequencing stays in `WatchedRun`,
  which is logic and already headless-testable.

## B2. Launch, tail, kill

The game launches the suite and watches it run. `OS.execute` blocks the calling thread, so use
`OS.create_process` for a non-blocking PID and tail the run's output; `OS.kill(pid)` is the stop
button. **Chopping a run early is the point**, so the kill path is not optional garnish.

What it shows, live: the file being run, elapsed, running totals, pass/fail as they land, and the work
counts A2 now emits. Which rung to launch is a choice on the panel.

**Unmediated, deliberately.** The value here is seeing what CC actually runs — a curated list would be
CC's selection of what is worth watching, which makes it the wrong instrument for checking CC's work.
**Curated mode is a saved filter over the same feed**, never a separate source, so it cannot drift from
what really happened.

## B3. Size it as a calibration instrument

The supervisor expects the most value from the first few runs they monitor, after which this likely
becomes a review step rather than a daily driver. **Build to that.** Legible, killable, honest about
what ran. No run history, no charting, no persistence beyond the current run unless something later
asks for it.

**TESTS:** the launcher reports the same pass/fail the shell run reports for the same rung (**if the
window and the terminal ever disagree, the window is worthless**); kill actually terminates the child;
the panel mounts under both overlays; `WatchedRun`'s existing headless coverage still passes after the
panel move.

---

# ⏸ SUPERVISOR CHECKPOINT — take the baseline

**Stop and hand over.** The supervisor runs the suite from the window, on the pre-collapse tree, and
takes their own baseline. Passes C and D change what that window shows; the point of this ordering is
that the change is watched rather than reported.

---

# PASS C — A shared bout corpus, and stubs where bouts are not the point

`test_completion_sampler.gd` (207 s, 24 bouts) and `test_full_mission.gd` (112 s, 8 bouts) are **57% of
the suite**, both driving `CompletionSampler`, each paying separately for the same kind of bout.

## C1. The corpus

Play N bouts once per suite run, cache the outcome records, and let every test that needs *outcomes*
read from it. Bouts are deterministic, so caching is sound by construction rather than by convention.

- **Draw the random seeds once, at corpus construction.** `test_full_mission` samples randomly on
  purpose; sharing a *fixed* set would quietly retire that property and undo what taskblock-46 spent a
  pass establishing. One random draw per run, played once, read by everyone.
- **Hand out records, never live state.** A test that mutates a cached `CombatState` corrupts every
  later reader and the failure surfaces somewhere unrelated to its cause. Records, or `dup()` at the
  boundary.
- **The other eight bout-building files are not candidates.** They build a specific board through
  `BoutSetup.build_bout` + `GridFixture` to exercise one rule, and that board *is* the test.

## C2. The stubs

Most of `test_completion_sampler.gd`'s thirteen tests assert **pure functions over outcomes** —
escalation thresholds, the `ceil`-driven non-monotonicity, seed drawing, rate arithmetic. Those run
against canned results in microseconds and need no engine.

**Keep one real end-to-end bout to prove the wiring.** Stub the rest. Then `test_full_mission` is the
only place bouts genuinely have to run, which is where the cost belongs — it is the number anyone
actually reads.

**TESTS:** the corpus plays its bouts exactly once per suite run (assert the bout counter, since paying
twice is the failure this pass exists to prevent); a test cannot mutate another's view of a cached
result; stubbed tests assert the same properties they did before — **the properties are not what is
being cut**; the end-to-end test still exercises the real path.

---

# PASS D — The two outliers

Distinct pass, because these are questions before they are cuts.

**`test_ai_batch_yield.gd` — 48 s for 3 bouts.** ~16 s a bout against the sampler's ~8.6, the worst
ratio in the file list. **Diagnose before touching it.** It may legitimately pay for the pacer's frame
yields in a way nothing else does, in which case the number is correct and the finding is that the
pacer costs that much. Report the cause; cut only if the cost is incidental.

**`test_spectator_overlay.gd` — 32 s, zero bouts, zero turns.** The largest non-bout file in the suite,
and **completely invisible to the work budgets**, which gate what the suite asks of the AI rather than
what it costs. That is deliberate, but it means a purely-view regression cannot fail a budget, and a
green budget can be read as "the suite did not get slower" when it did.

Two things worth separating: whether this file's cost is reducible, and whether the budgets should grow
a counter that can see non-AI cost at all. **The second is the more valuable answer** — report it even
if the first turns out to be no.

**TESTS:** whatever changes keeps its assertions; if a counter is added, it moves when a view-only test
is added and does not move when a bout test is.

---

# Workflow change — supervisor-applied

`CLAUDE.md` edits are handed separately and are the supervisor's to apply: the three-rung block under
*Your feedback loop*, the sentence about running the narrowest rung that could catch the change, and
Workflow step 2's targeted-then-full loop with the supervised-gate clause.

**The supervised gate is opt-in per taskblock, not standing.** Content and investigative blocks stay
free of it; major changes ask for it. When a taskblock does ask, CC stops at the pass boundary and
reports pass/fail plus the per-file cost delta, rather than committing on its own run.

# Not this block's job

- **Changing what any test asserts.** Retarget, share and stub — never weaken.
- **`MIN_COMPLETION_RATE`.** Measured 72% against a 0.35 floor; that constant is the supervisor's and
  it is not this block's business.
- **The remaining overlay collapse.** B1 removes one subclass because it is in the way; *One view,
  toggleable modules* is still its own item.
- **Running GUT inside the live scene tree.** The launcher drives a subprocess. GUT is a cmdline addon
  and hosting it in a running game buys nothing the subprocess does not.
