#!/usr/bin/env bash
set -euo pipefail

# Drives a real, on-screen scenario (tools/checkpoints/checkpoint_N.gd) through
# an actual GPU frame and writes its artifacts into OUT_DIR. Not GUT-based:
# these exist precisely because `--headless` has only the no-op renderer and so
# cannot answer "does this LOOK right."
#
# taskblock-41 Pass E: generic. This script no longer knows anything about any
# individual checkpoint — it launches the scenario and gets out of the way. The
# scenario script writes its own README and checklist (see
# checkpoint_8.gd::_write_readme), because three per-checkpoint heredocs were
# ~200 of this file's previous 224 lines and every new scenario added ~70 more.
#
# Also gone: the "This is a hard stop — wait for a go before continuing" line
# this used to print. The stop-and-wait GATE is retired; the capability is not.
# CC authors a checkpoint whenever it judges one useful — no permission step —
# and the supervisor looks at it when convenient.

N="${1:?Usage: run_visual_checkpoint.sh N OUT_DIR}"
OUT_DIR="${2:?Usage: run_visual_checkpoint.sh N OUT_DIR}"
GODOT="${GODOT:-godot}"
DISPLAY_DRIVER="${CHECKPOINT_DISPLAY_DRIVER:-x11}"
SCRIPT="tools/checkpoints/checkpoint_${N}.gd"

if [ ! -f "$SCRIPT" ]; then
  echo "No scenario at ${SCRIPT}." >&2
  echo "Available scenarios:" >&2
  ls tools/checkpoints/checkpoint_*.gd 2>/dev/null >&2 || echo "  (none)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

"$GODOT" -d --display-driver "$DISPLAY_DRIVER" --audio-driver Dummy \
  --path . -s "res://${SCRIPT}" -- "$OUT_DIR" \
  2>&1 | tee "${OUT_DIR}/run.log"

echo
echo "Checkpoint ${N} artifacts are in ${OUT_DIR}/ — LOCAL ONLY (see .gitignore)."
echo "Read ${OUT_DIR}/README.md for what to look at."
echo "The durable artifact is the ANSWERS, not the images: they belong in"
echo "reports/Report-TaskblockN.md, which is committed. To keep a particular"
echo "image, copy it into out/checkpoints-kept/ — that directory is tracked."
