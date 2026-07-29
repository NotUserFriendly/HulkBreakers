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
    export HULK_FAST_GATE=1
    echo "== fast gate: skipping bout-building files =="
    ;;
  *)
    # A bare filename resolves by search — nobody should have to type
    # res://test/unit/logic/ai/... . Two files sharing a name is a repo mistake to
    # fix, not a case to disambiguate cleverly, so it prints both and stops.
    if [[ -e "$GATE" ]]; then
      TARGET="$GATE"
    else
      MATCHES=$(find test -name "$GATE" -o -type d -name "$GATE" | sort)
      COUNT=$(printf '%s' "$MATCHES" | grep -c . || true)
      if [[ "$COUNT" -eq 0 ]]; then
        echo "no test file or directory named '$GATE' under test/" >&2
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
#    taskblock-45 Pass E: **max-file-lines is back at its default 1000, and the
#    ~40 lines of bump rationale that used to sit here are deleted with it.**
#    It had been raised eight times — 1000 to 1050 to 1150 to 1200 to 1300 to
#    1400 — every single time for one file, src/logic/ai/unit_ai.gd, and every
#    time on the promise that "part two replaces this file". Part two landed and
#    the file is gone. The limit coming back down is the objective proof of that,
#    which is why it was taskblock-45 Pass E's acceptance rather than a tidy-up:
#    a planner that had truly been replaced could not need the headroom, and one
#    that had merely been added alongside would still need every line of it.
#    `test/unit/test_retired_planner_sweep.gd` asserts the 1000 directly, so this
#    cannot quietly drift back up without someone saying why in a test.
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

GODOT_DISABLE_LEAK_CHECKS=1 "$GODOT" --headless -d \
  --display-driver headless --audio-driver Dummy \
  --path . \
  -s res://tools/run_suite.gd \
  -- "$SCOPE" $WRITE_FLAG
