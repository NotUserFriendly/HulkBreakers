#!/usr/bin/env bash
set -euo pipefail

# One-click launch of the actual game (BattleScene, project.godot's own
# run/main_scene) — a real on-screen window, never --headless. Press B
# once battle_scene is up to reach the Simulate Bout menu (taskblock-14
# Pass D).

GODOT="${GODOT:-godot}"
DISPLAY_DRIVER="${GAME_DISPLAY_DRIVER:-x11}"

exec "$GODOT" --display-driver "$DISPLAY_DRIVER" --path .
