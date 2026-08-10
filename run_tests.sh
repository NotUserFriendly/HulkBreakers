#!/usr/bin/env bash
set -euo pipefail

# Set GODOT=/path/to/godot if 'godot' isn't on PATH.
GODOT="${GODOT:-godot}"

# taskblock-47 Pass C / taskblock-48 Pass A1: **three rungs**, because they answer
# different questions and cost an order of magnitude apart.
#
#   ./run_tests.sh test_foo.gd   one file (or a directory) — the edit loop
#   ./run_tests.sh fast          everything that does not build a bout
#   ./run_tests.sh               everything. Green before a pass commits.
#
# **A targeted run is never what a pass is green on.** It cannot see that a change
# broke a different file, which is the entire reason the full suite exists.
#
# The full gate is a strict superset of the fast one; nothing exists only in the fast
# tier. Which files the fast gate skips is `SuiteTier.BOUT_FILES`, and it is NOT a
# directory rule: eleven of the twelve bout-building files live under test/unit/,
# including the single most expensive file in the suite, so "skip integration/" would
# have declared the fast gate bout-free while it played almost all of them.
#
# The tier list is checked against the profile's own bout counter on every run
# (test_suite_tier.gd), so adding a bout to a unit test fails a test rather than
# quietly making the fast gate slow.
#
# ## The fixed floor, measured rather than assumed (taskblock-48 A1)
#
#   gdlint src test   6.14 s
#   import            2.32 s
#   parse guard       0.82 s
#   GUT startup      ~1.20 s
#   ---------------------------
#   floor            10.5 s
#
# On a sub-second file that floor is the entire cost, so **a targeted run narrows what
# it can honestly narrow**: gdlint runs over the target only (0.21 s), and the
# checkpoint parse guard is skipped because it guards checkpoint scenarios and has
# nothing to do with the file under test. The import step STAYS — it is what registers
# a `class_name`, and skipping it makes a newly added script invisible in a way that
# looks like a broken test. That takes a targeted run's floor to about 3.7 s.
GATE="${1:-full}"
TARGET=""
case "$GATE" in
  full) ;;
  fast)
    export HB_FAST_GATE=1
    echo "== fast gate: skipping bout-building files =="
    ;;
  *)
    # A bare filename resolves by search — nobody should have to type
    # res://test/unit/logic/ai/... . Two files sharing a name is a repo mistake to
    # fix, not a case to disambiguate cleverly, so it prints both and stops.
    if [[ -e "$GATE" ]]; then
      TARGET="$GATE"
    else
      # HB_TEST_ROOT is a test-only seam. `test_run_suite.gd` has to prove that two
      # same-named files are reported rather than silently disambiguated, and doing
      # that against the real tree meant writing a duplicate .gd into test/ — which
      # races Godot's importer and orphans a .uid, the exact failure that broke the
      # full gate once already. Pointed at a throwaway directory, the resolver can be
      # exercised without touching the project at all.
      SEARCH_ROOT="${HB_TEST_ROOT:-test}"
      MATCHES=$(find "$SEARCH_ROOT" -name "$GATE" -o -type d -name "$GATE" | sort)
      COUNT=$(printf '%s' "$MATCHES" | grep -c . || true)
      if [[ "$COUNT" -eq 0 ]]; then
        echo "no test file or directory named '$GATE' under ${HB_TEST_ROOT:-test}/" >&2
        echo "usage: $0 [fast|full|<file.gd>|<directory>]" >&2
        exit 2
      elif [[ "$COUNT" -gt 1 ]]; then
        echo "'$GATE' is ambiguous — rename one of these:" >&2
        printf '%s\n' "$MATCHES" >&2
        exit 2
      fi
      TARGET="$MATCHES"
    fi
    echo "== targeted run: $TARGET =="
    ;;
esac

# 1. Lint gate — fast failure, no engine needed. `pip install gdtoolkit` to get
#    gdlint/gdformat. Project style overrides live in ./gdlintrc (max-returns
#    raised from the default 6 — this codebase's is_legal() validation gates
#    are deliberate early-return chains, not something to collapse for a
#    linter default; max-public-methods raised from 20 — a GUT test file's own
#    `test_*` functions are deliberately many small, focused cases, not
#    something to split apart just to satisfy a linter default).
#
#    taskblock-63 Pass A: **max-file-lines is 2500, and that number is the
#    project's rather than gdlint's.** The 1000 it replaced was the tool's own
#    default — inherited, never argued for — and a line count cannot tell code
#    from comments, so it penalised exactly the files that carry their rules in
#    doc comments, which is this project's standing convention. BR62.02 records
#    it biting three source files in one taskblock with the cost coming out of
#    documentation twice. Everything else gdlint does is unchanged.
#    `test/unit/test_lint_config.gd` asserts the 2500 directly, so this cannot
#    drift without someone saying why in a test — the mechanism taskblock-45
#    Pass E introduced, kept, with a number that was decided rather than
#    inherited. (That pass's own reason for the 1000 — the cap coming back down
#    being the objective proof `src/logic/ai/unit_ai.gd` was truly replaced after
#    eight bumps taken on its behalf — was delivered and cannot be delivered
#    twice; `test_retired_planner_sweep.gd` is what keeps the planner gone now.)
if [[ -n "$TARGET" ]]; then
  gdlint "$TARGET"
else
  gdlint src test
fi

# 2. Warm-up import so class_name scripts register (required on cold checkouts).
#    This step can exit non-zero on benign import warnings, so don't let it abort.
"$GODOT" --headless --path . --import --quit || true

# 3. Checkpoint parse guard (taskblock-41 Pass E). Visual checkpoints need a
#    real GPU frame, so they can never RUN here — but they can be PARSED, and
#    that is exactly what BR40.02 needed: a UnitView -> HitVolumeView rename
#    orphaned two scenario scripts for ~15 taskblocks because nothing re-ran
#    them. Deliberately NOT under `-d`: a parse error inside load() raises a
#    Debugger Break there and would hang the build instead of failing it. Runs
#    ahead of GUT so a broken scenario fails fast, before the debugger-enabled
#    step below could hit the same script.
#    Skipped for a targeted run: it guards checkpoint SCENARIOS, which have nothing
#    to do with whichever test file is under the cursor, and it is 0.8 s of a ~3.7 s
#    floor. The full and fast gates still pay it, which is where it earns its place.
if [[ -z "$TARGET" ]]; then
  "$GODOT" --headless --path . -s res://tools/checkpoints/parse_guard.gd
fi

# 4. Run the suite through `tools/run_suite.gd` (taskblock-48 Pass A2).
#
#    **Not `gut_cmdln.gd` any more, and the difference is the exit code.** Work
#    counts exist only in-process and only a runner that hosts `GutRunner` itself can
#    collect them, so there used to be two entry points into one suite — and only one
#    of them failed the build. They are collapsed; this one both counts and fails.
#
#    Artifacts (`SUITE-PROFILE.md`, `suite_profile.json`) are committed, so they are
#    rewritten only when asked for with `--write`. Counts print on every run either
#    way.
#
#    GODOT_DISABLE_LEAK_CHECKS avoids false failures from leak logs printed on exit.
if [[ -n "$TARGET" ]]; then
  SCOPE="--test=res://$TARGET"
  [[ -d "$TARGET" ]] && SCOPE="--dir=res://$TARGET"
else
  SCOPE="--dir=res://test"
fi

# **Only the full gate may write the artifacts, whatever WRITE_PROFILE says.**
#
# `SUITE-PROFILE.md` and `suite_profile.json` describe the WHOLE suite, so a run that
# saw part of it cannot honestly produce them. This is not hypothetical: exporting
# WRITE_PROFILE=1 leaks it into every subprocess, and `test_run_suite.gd` shells out
# to a targeted run — which promptly overwrote the committed profile with a single
# file's data, mid-run, while `test_suite_budget.gd` and `test_suite_tier.gd` were
# still reading it. The outer run rewrote it correctly at the end, so the damage was
# invisible in the final tree and showed up only as two unrelated tests failing.
WRITE_FLAG=""
if [[ -n "${WRITE_PROFILE:-}" ]]; then
  if [[ -z "$TARGET" && "$GATE" != "fast" ]]; then
    WRITE_FLAG="--write"
  else
    echo "== WRITE_PROFILE ignored: only the full gate can write a whole-suite profile =="
  fi
fi

# 5. **The completion guard, and it is not belt-and-braces.**
#
#    The suite runs under `-d`, which GUT needs to notice unexpected engine errors. A
#    runtime script error therefore raises a Debugger Break, and a Debugger Break ENDS
#    THE RUN — `run_suite.gd` never reaches `_on_end_run`, never computes an exit code,
#    and the process exits 0. **A green gate that saw three quarters of the suite is
#    worse than a red one**, and this is not hypothetical: taskblock-57 Pass C3 moved
#    some fields, two test files still reached for them, and the full gate reported
#    success from a log with no totals in it at all.
#
#    A runner that has vanished cannot report its own absence, so the caller checks for
#    the summary line the runner prints last. Missing marker, failed build.
#
#    **The other shape is a hang, and it is deliberately not handled here.** `-d` opens
#    an interactive debugger on stdin; with a long queue of scripts behind it the break
#    is stepped past and the run truncates (the case above), but a break in the LAST
#    script sits at a `debug>` prompt waiting for input that never comes. A hang is
#    loud — it never returns — where a truncated green run is silent, so the silent one
#    is what needs a guard. Adding a timeout here would put a wall-clock number on a
#    suite whose runtime is the thing being measured.
SUITE_LOG="$(mktemp)"
trap 'rm -f "$SUITE_LOG"' EXIT
set +e
GODOT_DISABLE_LEAK_CHECKS=1 "$GODOT" --headless -d \
  --display-driver headless --audio-driver Dummy \
  --path . \
  -s res://tools/run_suite.gd \
  -- "$SCOPE" $WRITE_FLAG 2>&1 | tee "$SUITE_LOG"
SUITE_STATUS=${PIPESTATUS[0]}
set -e

if ! grep -q -- "--- suite cost ---" "$SUITE_LOG"; then
  echo "" >&2
  echo "the suite did not finish — no '--- suite cost ---' summary was printed." >&2
  echo "a Debugger Break (a runtime script error under -d) ends the run before" >&2
  echo "run_suite.gd can compute an exit code, so the process would otherwise" >&2
  echo "report success having skipped everything after the error." >&2
  exit 1
fi

exit "$SUITE_STATUS"
