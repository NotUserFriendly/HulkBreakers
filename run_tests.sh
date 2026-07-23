#!/usr/bin/env bash
set -euo pipefail

# Set GODOT=/path/to/godot if 'godot' isn't on PATH.
GODOT="${GODOT:-godot}"

# 1. Lint gate — fast failure, no engine needed. `pip install gdtoolkit` to get
#    gdlint/gdformat. Project style overrides live in ./gdlintrc (max-returns
#    raised from the default 6 — this codebase's is_legal() validation gates
#    are deliberate early-return chains, not something to collapse for a
#    linter default; max-public-methods raised from 20, currently 37
#    (test_inspect_panel.gd keeps landing exactly the taskblock's own bundled/
#    single-fix tests that push it one over — taskblock-26 Pass E, then
#    taskblock-27 Pass D5) — a GUT test file's own `test_*` functions are
#    deliberately many small, focused cases, not something to split apart just
#    to satisfy a linter default; max-file-lines raised from 1000 to 1050 —
#    src/logic/ai/unit_ai.gd (a single cohesive planner class, "the block's own
#    spine") crossed 1000 re-diagnosing taskblock-26's own B2, splitting it is
#    a bigger, riskier undertaking than a linter default warrants; the
#    matching test file split instead, same as
#    test_damage_resolver_deflect_modes.gd already did; raised again to 1150
#    across tb35 Pass B's BR34.06 fallback, Pass A1's decision-log call
#    sites (the log emission itself lives in the new
#    src/logic/ai/ai_decision_log.gd rather than growing this file further),
#    and Pass A3's per-turn LOF memoisation — same file, same reasoning,
#    given headroom this time since tb35's own Pass C is scoped to touch
#    this file again).
gdlint src test

# 2. Warm-up import so class_name scripts register (required on cold checkouts).
#    This step can exit non-zero on benign import warnings, so don't let it abort.
"$GODOT" --headless --path . --import --quit || true

# 3. Run GUT fully headless. GODOT_DISABLE_LEAK_CHECKS avoids false failures from
#    leak logs printed on exit. -gexit makes a failing test fail the process.
GODOT_DISABLE_LEAK_CHECKS=1 "$GODOT" --headless -d \
  --display-driver headless --audio-driver Dummy \
  --path . \
  -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://test -ginclude_subdirs -gexit
