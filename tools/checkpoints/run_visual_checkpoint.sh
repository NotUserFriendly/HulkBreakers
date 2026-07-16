#!/usr/bin/env bash
set -euo pipefail

# Drives the real, on-screen BattleScene (docs/10 Phase 12) through
# tools/checkpoints/checkpoint_{6,7}.gd and writes the resulting artifacts
# + README into OUT_DIR. Not GUT-based like checkpoints 1-5: these need an
# actual rendered frame, so they run against a real display driver instead
# of --headless. Called by ./checkpoint.sh 6|7 — not meant to be run
# directly, though it can be (./tools/checkpoints/run_visual_checkpoint.sh 6
# out/checkpoints/06).

N="${1:?Usage: run_visual_checkpoint.sh N OUT_DIR}"
OUT_DIR="${2:?Usage: run_visual_checkpoint.sh N OUT_DIR}"
GODOT="${GODOT:-godot}"
DISPLAY_DRIVER="${CHECKPOINT_DISPLAY_DRIVER:-x11}"

mkdir -p "$OUT_DIR"

GENERATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LAUNCH_NOTE="by launching the real project (\`godot --path .\`, a real GPU frame via \
\`--display-driver ${DISPLAY_DRIVER}\`) and driving \`BattleScene\`/\`TacticsController\`/\
\`CameraRig\` exactly as a player would, then reading back the rendered frame — not a mockup."

case "$N" in
  6)
    "$GODOT" -d --display-driver "$DISPLAY_DRIVER" --audio-driver Dummy \
      --path . -s res://tools/checkpoints/checkpoint_6.gd -- "$OUT_DIR" \
      2>&1 | tee "${OUT_DIR}/run.log"

    cat > "${OUT_DIR}/README.md" <<EOF
# Checkpoint 6

Generated ${GENERATED}, ${LAUNCH_NOTE}

Phase 12.1 (docs/10, PLAN.md): the battle renders. \`BoardView\` draws a ground plane sized to
the grid plus a box per blocker; \`UnitView\` walks each unit's socket tree via
\`UnitGeometry.placements()\` and emits one \`BoxMesh\` per living \`Box\` at its fully composed
transform — "render is hitbox," so what's on screen is exactly what the shot plane can hit.
\`CameraRig\` is a two-pivot orbit rig (yaw around world Y, pitch around its own local X) driven
by a pure, headless-tested \`CameraOrbitState\` — pitch is clamped to \`(-80°, -6°)\` so it can
never reach a pole and gimbal-lock.

Look for:
- **\`board_wide.png\`** — the default seeded battle (seed \`20260715\`, a 12x10 grid): two
  deep-struck cyborgs at their assigned cells, each rendering as a torso box with whatever limbs
  its random assembly attached. The "New Battle" button (top-left) is live UI, not a mockup.
- **\`cyborg_closeup.png\`** — the near cyborg framed close: whatever limbs its own composed
  socket transforms placed there, not hand-placed.
- **\`twelve_arm_rig.png\`** — the acceptance case from PLAN.md Phase 12.0/12.1 made visible: a
  \`steel\` torso with 12 \`SHOULDER\` sockets, each hosting a duplicated \`arm\` template
  (\`sheet_steel\`), evenly spaced and **not overlapping** — the bug this phase exists to fix
  (one arm template, two-plus shoulder sockets, all landing at identical coordinates) is gone.

Regenerate with \`./checkpoint.sh 6\` — see \`tools/checkpoints/checkpoint_6.gd\` for the driver
script and \`run.log\` for its stdout (checked for script errors on launch).

Headless coverage for everything screenshots can't show — exact box sizes/transforms,
destroyed-part removal, camera clamp math, deterministic reseeding — lives in
\`test/unit/logic/test_unit_geometry.gd\`, \`test/unit/logic/test_camera_orbit_state.gd\`, and
\`test/unit/view/{test_board_view,test_unit_view,test_camera_rig,test_battle_scene}.gd\`.
EOF
    ;;
  7)
    AVI="${OUT_DIR}/playthrough.avi"
    "$GODOT" -d --display-driver "$DISPLAY_DRIVER" --audio-driver Dummy \
      --path . --write-movie "$AVI" \
      -s res://tools/checkpoints/checkpoint_7.gd -- "$OUT_DIR" \
      2>&1 | tee "${OUT_DIR}/run.log"

    if command -v ffmpeg >/dev/null 2>&1 && [ -f "$AVI" ]; then
      ffmpeg -y -loglevel error -i "$AVI" -c:v libx264 -pix_fmt yuv420p \
        "${OUT_DIR}/playthrough.mp4"
      rm -f "$AVI"
    fi

    cat > "${OUT_DIR}/README.md" <<EOF
# Checkpoint 7

Generated ${GENERATED}, ${LAUNCH_NOTE} Recorded with \`--write-movie\`, converted from Godot's
native \`.avi\` output via \`ffmpeg -c:v libx264\` for a small file instead of the raw AVI.

Phase 12 (docs/10, PLAN.md): "a human launches the game, selects a cyborg, queues a move and an
aimed shot... ends the turn, watches the burst fire and ricochet, and reads the log —
repeatedly, until one side is down." This recording exercises that loop for real: two hand-armed
cyborgs (\`jerry\`, \`raider\`) trade pistol fire across several rounds until one side is down or
the script ends. Phase 12.5's terminal shell (real OFL monospace font, six-color palette,
rolling combat log via \`UISink\`, selected-unit stat block via \`StatBlockView\`/
\`WeaponResolver\`, one \`Theme\` resource) is visible and live throughout.

**\`playthrough.mp4\`** — the full recording. Watch for:
- The \`RESOLUTION\` banner (docs/10 Phase 12.4) holding through each turn's playback window,
  during which a muzzle-to-impact tracer fires for every "impact" cue, then returning to
  \`TACTICS\`.
- The combat log panel streaming real events live — \`impact\`/\`PENETRATE\`, \`turn_end\`,
  \`turn_start\` — as they're emitted, not scripted text.
- Both units alternating turns across multiple rounds, each actually taking damage.

Three stills pulled from the same run for a quick look without playing the video:
- **\`frame_first_impact.png\`** — captured \`RESOLVE_LEAD_IN\` after the very first shot, while
  its tracer is on screen.
- **\`frame_round1_exchange.png\`** / **\`frame_round2_exchange.png\`** — the log panel after the
  2nd and 4th turns, both units alternating turn order correctly.

Regenerate with \`./checkpoint.sh 7\` — see \`tools/checkpoints/checkpoint_7.gd\` for the driver
script and \`run.log\` for its stdout (checked for script errors on launch).

## What this closes out
- Phase 12.2 (selection/movement), 12.3 (aim UI), 12.4 (resolution playback, including the
  per-cue tracer visuals — no longer deferred), and 12.5 (terminal shell) all wired together and
  exercised live, not just headlessly.
- docs/08's transparency proof holds at the UI layer, not just the pure-logic layer
  (\`test_transparency_proof.gd\`): \`test/unit/view/test_phase12_transparency.gd\` proves the
  stat panel's predicted damage — read through \`WeaponResolver\`, the same call \`AttackAction\`
  makes — is exactly what the combat log reports once that shot actually resolves.

## Known simplifications (flagged, not silent)
- Font: docs/08 names JetBrains Mono/IBM Plex Mono/Share Tech Mono/VT323 as examples of the
  actual criterion (OFL/free, monospace); none of the four ship with this repo and there's no
  network fetch available. Anonymous Pro (OFL, monospace, already vendored under
  \`addons/gut/fonts\` for GUT's own UI) satisfies the same criterion — copied into
  \`res://assets/fonts/\` with its \`OFL.txt\` rather than left pointing into a third-party addon's
  private folder. Swapping in one of the docs-named fonts later is a one-line change in
  \`HulkTheme.build()\`.
EOF
    ;;
  *)
    echo "run_visual_checkpoint.sh only handles checkpoints 6 and 7." >&2
    exit 1
    ;;
esac

echo "Wrote ${OUT_DIR}/README.md"
echo "Review, then commit. This is a hard stop — wait for a go before continuing."
