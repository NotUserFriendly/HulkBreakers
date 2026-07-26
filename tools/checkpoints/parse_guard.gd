extends SceneTree

## taskblock-41 Pass E: **the load-bearing piece of putting checkpoints back.**
##
## BR40.02 existed because visual checkpoints sit outside the headless gate by
## necessity — they need a real GPU frame, so `run_tests.sh` can never RUN one —
## and nothing re-ran them by hand either. A `UnitView` -> `HitVolumeView`
## rename orphaned two scenario scripts for roughly fifteen taskblocks, and
## nobody found out until one was finally run by hand during tb40.
##
## Rendering can't happen in CI. **Parsing can.** Loading every scenario
## headlessly turns silent rot into a red build for almost nothing, catching
## exactly the failure that actually happened: a renamed identifier, a changed
## signature, a deleted class.
##
## **Why a script rather than a GUT test.** This was written as a GUT test
## first. It works — but `run_tests.sh` runs GUT with `-d`, and under the
## debugger a parse error inside `load()` raises a Debugger Break that WAITS
## FOR INPUT. The guard would hang the build instead of failing it, which is a
## worse failure than the rot it exists to catch. Run without `-d`, ahead of
## GUT, it exits non-zero and names the file. Verified both ways by
## reintroducing BR40.02's exact `UnitView` reference and watching each behave.
##
## Deliberately does NOT instantiate or run anything: a scenario drives a real
## `BattleScene` through real frames, and running one here would need the very
## renderer this guard exists because we don't have.

const CHECKPOINT_DIR := "res://tools/checkpoints"


func _initialize() -> void:
	var failures: Array[String] = []
	var checked := 0

	for path: String in _scenario_paths():
		checked += 1
		var script: Resource = load(path)
		if script == null:
			failures.append("%s — failed to parse" % path)
			continue
		if script is not GDScript:
			failures.append("%s — did not compile to a GDScript" % path)
			continue
		# A scenario is launched with `godot -s <script>`, so it has to be a
		# SceneTree entry point. One that quietly stopped being one would never
		# run, and parsing alone would not notice.
		var base: StringName = (script as GDScript).get_instance_base_type()
		if base != &"SceneTree":
			failures.append("%s — extends %s, must extend SceneTree" % [path, base])

	if checked == 0:
		print("checkpoint parse guard: no scenarios found in %s" % CHECKPOINT_DIR)
		quit(1)
		return

	for failure: String in failures:
		printerr("checkpoint parse guard: %s" % failure)
	if failures.is_empty():
		print("checkpoint parse guard: %d scenario(s) OK" % checked)
		quit(0)
	else:
		printerr("checkpoint parse guard: %d of %d scenario(s) broken" % [failures.size(), checked])
		quit(1)


func _scenario_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(CHECKPOINT_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("checkpoint_") and entry.ends_with(".gd"):
			paths.append("%s/%s" % [CHECKPOINT_DIR, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths
