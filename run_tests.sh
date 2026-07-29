#!/usr/bin/env bash
set -euo pipefail

# Set GODOT=/path/to/godot if 'godot' isn't on PATH.
GODOT="${GODOT:-godot}"

# taskblock-47 Pass C: two gates, because they answer different questions.
#
#   ./run_tests.sh fast   the per-change loop — everything that does not build a bout
#   ./run_tests.sh        the per-pass loop — everything. Green before a pass commits.
#
# The full gate is a strict superset; nothing exists only in the fast tier. Which
# files the fast gate skips is `SuiteTier.BOUT_FILES`, and it is NOT a directory rule:
# eleven of the twelve bout-building files live under test/unit/, including the single
# most expensive file in the suite, so "skip integration/" would have declared the
# fast gate bout-free while it played almost all of them.
#
# The tier list is checked against the profile's own bout counter on every run
# (test_suite_tier.gd), so adding a bout to a unit test fails a test rather than
# quietly making the fast gate slow.
GATE="${1:-full}"
if [[ "$GATE" == "fast" ]]; then
  export HULK_FAST_GATE=1
  echo "== fast gate: skipping bout-building files =="
elif [[ "$GATE" != "full" ]]; then
  echo "usage: $0 [fast|full]" >&2
  exit 2
fi

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
gdlint src test

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
"$GODOT" --headless --path . -s res://tools/checkpoints/parse_guard.gd

# 4. Run GUT fully headless. GODOT_DISABLE_LEAK_CHECKS avoids false failures from
#    leak logs printed on exit. -gexit makes a failing test fail the process.
GODOT_DISABLE_LEAK_CHECKS=1 "$GODOT" --headless -d \
  --display-driver headless --audio-driver Dummy \
  --path . \
  -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://test -ginclude_subdirs -gexit
