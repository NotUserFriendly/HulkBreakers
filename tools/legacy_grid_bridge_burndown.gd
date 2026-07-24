class_name LegacyGridBridgeBurndown
extends GutHookScript

## taskblock-38 Pass D: a GUT post-run hook — pass this as
## `-gpost_run_script=res://tools/legacy_grid_bridge_burndown.gd` alongside
## the normal suite run (see `run_tests.sh`). Dumps `GridLegacyBridge`'s
## accumulated hit counts once every test in the suite has run, in the
## SAME process, so the tally is the real thing, not a sample. Committed
## for reproducibility — re-run any time the follow-up retirement block
## (docs/PLAN.md) wants a fresh burn-down list before it starts.


func run() -> void:
	var counts: Dictionary = GridLegacyBridge.hit_counts()
	var callers: Array = counts.keys()
	callers.sort()
	print("\n=== taskblock-38 legacy-grid-bridge burn-down ===")
	print("total hits: ", GridLegacyBridge.total_hits())
	for caller: String in callers:
		print("  %s: %d" % [caller, counts[caller]])
	print("=== end burn-down ===\n")
