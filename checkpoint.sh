#!/usr/bin/env bash
set -euo pipefail

# Generates reviewable artifacts for checkpoint N (docs/09) into
# out/checkpoints/NN/, then stops. Checkpoints are hard stops — commit the
# artifacts and wait for a human go before proceeding.

N="${1:?Usage: checkpoint.sh N}"
PADDED=$(printf "%02d" "$N")
OUT_DIR="out/checkpoints/${PADDED}"
GODOT="${GODOT:-godot}"

mkdir -p "$OUT_DIR"

case "$N" in
  1)
    TEST_TARGET="res://test/checkpoints/test_checkpoint_1.gd"
    SUMMARY="ASCII maps across several seeds (docs/00 hulk gen). Look for: does the map read as a place? Are seeds actually different?"
    ;;
  *)
    echo "No checkpoint script wired for checkpoint ${N} yet." >&2
    exit 1
    ;;
esac

GODOT_DISABLE_LEAK_CHECKS=1 "$GODOT" --headless -d \
  --display-driver headless --audio-driver Dummy \
  --path . \
  -s res://addons/gut/gut_cmdln.gd \
  -gtest="$TEST_TARGET" -gexit > "${OUT_DIR}/output.txt" 2>&1 || true

cat > "${OUT_DIR}/README.md" <<EOF
# Checkpoint ${N}

Generated $(date -u +"%Y-%m-%dT%H:%M:%SZ").

${SUMMARY}

See \`output.txt\` for the full run.
EOF

echo "Wrote ${OUT_DIR}/README.md and ${OUT_DIR}/output.txt"
echo "Review, then commit. This is a hard stop — wait for a go before continuing."
