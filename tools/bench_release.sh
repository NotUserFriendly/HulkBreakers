#!/usr/bin/env bash
set -euo pipefail

# taskblock-44 Pass A — the release-versus-debug AI planning measurement.
#
# Every performance figure this project had recorded before this script existed
# came from an editor/tools binary, which carries GDScript's per-line debug
# overhead. Nobody had ever checked how much of the hitch was the game and how
# much was the harness. This runs the same bench, same seeds, same steps, on both
# builds and prints the ratio.
#
#   ./tools/bench_release.sh
#
# DELIBERATELY NOT IN run_tests.sh. An export takes real time and this is a
# measurement, not a gate — the same reasoning that keeps visual checkpoints off
# the test path.
#
# Requirements, both of which fail loudly rather than silently degrading:
#   1. Export templates matching the engine version. Editor > Manage Export
#      Templates > Download and Install, or unzip the
#      Godot_v<version>-stable_export_templates.tpz release asset into
#      ~/.local/share/godot/export_templates/<version>.stable/.
#   2. export_presets.cfg — copy export_presets.cfg.example. It is gitignored
#      because export paths are per-machine; the .example carries the preset
#      NAME and the `bench` custom feature, which are not.
#
# The bench cannot be driven with `-s res://...` in an exported build: that flag
# is tools-only and an export template ignores it, booting its main scene
# instead. project.godot overrides run/main_scene for the `bench` feature, which
# the preset declares, so the exported build boots straight into the bench.

GODOT="${GODOT:-godot}"
PRESET="${PRESET:-Linux Bench Release}"
BENCH_ARGS=("${@:---no-compare}")

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/hb_bench.x86_64"

say() { printf '\n=== %s ===\n' "$1"; }

# The guard that makes the whole exercise trustworthy. BuildIdentity classifies
# the running build and prints it as the bench's first line; if a release export
# ever silently fell back to a debug binary, the number would look plausible and
# be wrong. Checking the string the binary itself reports is the only way to know
# — inspecting the export command is not evidence about what actually ran.
require_build() {
	local output="$1" expected="$2"
	if ! grep -q "build=$expected" <<<"$output"; then
		echo "FAILED: expected 'build=$expected', got:" >&2
		grep '^build=' <<<"$output" >&2 || echo "  (no build line at all)" >&2
		exit 1
	fi
}

ms_of() { grep '^ms per' <<<"$1" | awk '{print $NF}'; }

say "debug (editor/tools binary — how every historical number was taken)"
DEBUG_OUT="$("$GODOT" --headless --path . -s res://tools/bench_ai_planning.gd -- "${BENCH_ARGS[@]}" 2>/dev/null)"
require_build "$DEBUG_OUT" "editor_debug"
echo "$DEBUG_OUT"

say "exporting release build"
"$GODOT" --headless --path . --export-release "$PRESET" "$BIN" >/dev/null 2>&1 || {
	echo "Export failed. Check export templates are installed and export_presets.cfg exists." >&2
	echo "See the header of this script." >&2
	exit 1
}

say "release (exported — what a player actually runs)"
RELEASE_OUT="$("$BIN" --headless -- "${BENCH_ARGS[@]}" 2>/dev/null)"
require_build "$RELEASE_OUT" "exported_release"
echo "$RELEASE_OUT"

DEBUG_MS="$(ms_of "$DEBUG_OUT")"
RELEASE_MS="$(ms_of "$RELEASE_OUT")"
say "ratio"
printf 'debug   : %s ms per AI step\n' "$DEBUG_MS"
printf 'release : %s ms per AI step\n' "$RELEASE_MS"
awk -v d="$DEBUG_MS" -v r="$RELEASE_MS" 'BEGIN {
	if (r > 0) printf "release is %.2fx faster (%.0f%% of debug cost)\n", d/r, 100*r/d
}'
