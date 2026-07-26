#!/usr/bin/env bash
set -euo pipefail

# Runs visual checkpoint N — a real, on-screen scenario driven through an actual
# GPU frame — and writes its artifacts into out/checkpoints/NN/.
#
# taskblock-41 Pass E: "checkpoints return as an ordinary tool." What was retired
# was the GATE, not the capability. There is no hard stop here any more, and no
# permission step: CC authors a checkpoint whenever it judges one useful, and the
# supervisor looks at it when convenient.
#
# The old GUT-based checkpoints 1-5 are gone from this script. They were never
# really checkpoints — they are ordinary regression tests that run every
# ./run_tests.sh, and they now live under test/baselines/ with names that say so
# (test_map_generation_baseline.gd and friends). Running them through a separate
# ritual only ever produced a second, staler copy of what the suite already
# prints.
#
# Artifacts are LOCAL ONLY (.gitignore). The durable record is the answers to a
# checkpoint's own checklist, which belong in reports/Report-TaskblockN.md. To
# keep a specific image, copy it into out/checkpoints-kept/ — that is tracked.

N="${1:?Usage: checkpoint.sh N   (N is a scenario in tools/checkpoints/checkpoint_N.gd)}"
PADDED=$(printf "%02d" "$N")
OUT_DIR="out/checkpoints/${PADDED}"

mkdir -p "$OUT_DIR"
exec ./tools/checkpoints/run_visual_checkpoint.sh "$N" "$OUT_DIR"
