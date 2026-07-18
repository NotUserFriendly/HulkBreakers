#!/usr/bin/env bash
set -euo pipefail

# Launches the Resource Editor (taskblock-11) as its own process, a real
# on-screen window — never --headless, and never the running game's own
# process (that's the whole point: a stable window to tune data in while
# the game reboots or CC runs sims beside it). Not a Godot EditorPlugin —
# a plugin is stripped from exports and can never ship to players; this
# scene can.
#
# Writes land in user://data/ (mod-ready, read/write); res://data/ is
# read-only once exported. No live hot-reload — the running game picks up
# a save on its own next boot/sim run.

GODOT="${GODOT:-godot}"
DISPLAY_DRIVER="${RESOURCE_EDITOR_DISPLAY_DRIVER:-x11}"

exec "$GODOT" --display-driver "$DISPLAY_DRIVER" --path . \
  res://src/resource_editor/resource_editor.tscn
