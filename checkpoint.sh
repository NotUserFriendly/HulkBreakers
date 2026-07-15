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
  2)
    TEST_TARGET="res://test/checkpoints/test_checkpoint_2.gd"
    SUMMARY="One cyborg's shot plane dumped from 12 angles swept continuously (docs/02 projection). Look for: do the boxes track the angle sanely? Does the rear ammo rack appear only from behind? Any pop or discontinuity between adjacent angles is a bug."
    ;;
  3)
    TEST_TARGET="res://test/checkpoints/test_checkpoint_3.gd"
    SUMMARY="A seeded 10-round burst fired at a steel-plated torso (docs/03 armor and ricochet). Look for: does the deflection retain a plausible fraction of damage? Does the ricochet land somewhere plausible — here, tagging a bystander standing in its path? Is the spray chaotic but not insane?"
    ;;
  *)
    echo "No checkpoint script wired for checkpoint ${N} yet." >&2
    exit 1
    ;;
esac

RAW_OUTPUT=$(mktemp)
GODOT_DISABLE_LEAK_CHECKS=1 "$GODOT" --headless -d \
  --display-driver headless --audio-driver Dummy \
  --path . \
  -s res://addons/gut/gut_cmdln.gd \
  -gtest="$TEST_TARGET" -gdisable_colors -gexit > "$RAW_OUTPUT" 2>&1 || true

# -gdisable_colors misses GUT's own pre-option startup log line, so strip any
# leftover ANSI escapes unconditionally — committed artifacts must be plain
# text, not terminal-colored bytes.
sed -E 's/\x1b\[[0-9;]*m//g' "$RAW_OUTPUT" > "${OUT_DIR}/output.txt"
rm -f "$RAW_OUTPUT"

cat > "${OUT_DIR}/README.md" <<EOF
# Checkpoint ${N}

Generated $(date -u +"%Y-%m-%dT%H:%M:%SZ").

${SUMMARY}

See \`output.txt\` for the full run.
EOF

echo "Wrote ${OUT_DIR}/README.md and ${OUT_DIR}/output.txt"
echo "Review, then commit. This is a hard stop — wait for a go before continuing."
