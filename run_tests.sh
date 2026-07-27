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
#    to satisfy a linter default; raised again to 45 across taskblock-38 Pass
#    C — test_pathfinder.gd's own placement-mode migration-bridge coverage
#    (walkable-tag gating, ramp-tagged edges, MP round-up) landed alongside
#    every existing terrain-based test rather than replacing any of them,
#    same reasoning as every prior bump; max-file-lines raised from 1000 to
#    1050 —
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
#    this file again); raised again to 1200 across taskblock-43 Pass A — the
#    score early-out's own soundness argument (the enumeration of which terms
#    can raise a score) belongs next to the code it constrains, since a future
#    term added without joining that list silently changes which cell the AI
#    picks. Same file, same reasoning as every prior bump.
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
