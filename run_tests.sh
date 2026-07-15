#!/usr/bin/env bash
set -euo pipefail

# Set GODOT=/path/to/godot if 'godot' isn't on PATH.
GODOT="${GODOT:-godot}"

# 1. Lint gate — fast failure, no engine needed. `pip install gdtoolkit` to get
#    gdlint/gdformat. Project style overrides live in ./gdlintrc (max-returns
#    raised from the default 6 — this codebase's is_legal() validation gates
#    are deliberate early-return chains, not something to collapse for a
#    linter default).
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
