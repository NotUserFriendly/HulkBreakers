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
## taskblock-45 Pass D (BR45.02): **every tool, not just the checkpoints.**
##
## This guard was built for BR40.02 — a rename orphaning two scenario scripts for
## fifteen taskblocks because nothing re-ran them — and then scoped to the one
## directory that bug happened in. `tools/` itself stayed unguarded, and the exact
## same thing happened again: taskblock-44 changed the planner's helpers to take a
## `WorldView` and made `_pick_engagement_position` a coroutine, and
## `ai_planning_bench.gd` stopped compiling. Nobody found out until Pass D tried to
## use it, because a bench is run by hand and by hand is not a schedule.
##
## **A guard covering one directory documents which directory was on someone's
## mind, not which ones can rot.** Tools are the whole class: nothing in
## `run_tests.sh` imports them, so nothing else will ever notice them breaking.
const TOOLS_DIR := "res://tools"
## taskblock-53 Pass A: **the audit tree, for exactly the reason `tools/` is here.**
##
## The audit is deliberately disjoint from the suite — nothing under `res://test/` reads
## it, and it is not run by any rung of `run_tests.sh`. That is what makes it rot-prone in
## precisely the way `ai_planning_bench.gd` did: the next audit could be six months away,
## and finding out then that it stopped compiling turns a question into a debugging
## session. **Compiling is the only obligation the audit keeps**, so it is the only one
## worth guarding.
##
## **Absence is not a failure.** The block's own acceptance is that this directory can be
## deleted outright and the ordinary suite still passes, so a missing audit tree
## contributes zero paths rather than an error — the same way `_tool_paths()` already
## treats an unopenable directory.
const AUDIT_DIR := "res://audit"
## What a tool writes in its own doc comment to declare that it is expected never
## to compile again. See `_is_retired`.
const RETIRED_MARKER := "@retired-tool"


func _initialize() -> void:
	var failures: Array[String] = []
	var checked := 0
	var retired := 0

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

	# Tools are parse-only: they legitimately extend SceneTree, Node or RefCounted
	# depending on how each is launched, so there is no single base type to demand.
	# Parsing is the whole check, and parsing is what actually rotted.
	for path: String in _tool_paths():
		if _is_retired(path):
			retired += 1
			continue
		checked += 1
		if not _parses(path):
			failures.append("%s — failed to parse" % path)

	# taskblock-53 Pass A: the audit, parse-only for the same reason tools are. It extends
	# GutTest rather than SceneTree — it is run by pointing the ordinary runner at its own
	# directory — so there is no base type to demand here either.
	for path: String in _gd_paths_in(AUDIT_DIR):
		checked += 1
		if not _parses(path):
			failures.append("%s — failed to parse" % path)

	if checked == 0:
		print("checkpoint parse guard: no scenarios found in %s" % CHECKPOINT_DIR)
		quit(1)
		return

	for failure: String in failures:
		printerr("checkpoint parse guard: %s" % failure)
	if failures.is_empty():
		print("checkpoint parse guard: %d script(s) OK, %d retired" % [checked, retired])
		quit(0)
	else:
		printerr("checkpoint parse guard: %d of %d script(s) broken" % [failures.size(), checked])
		quit(1)


## **`load()` is not the check, and finding that out is why this widening was worth
## doing.** Godot hands back a `GDScript` object for a script that failed to
## compile — the resource loads, the compile fails, and the two are separate
## events. A guard testing `load(path) == null` therefore passes on a broken
## script, which this one did: it reported "16 script(s) OK" with a deliberate
## syntax error sitting in `migrate_data.gd`. `reload()` returns the parse result
## itself, which is the thing actually being asserted.
##
## Verified in both directions rather than reasoned about, the same way
## taskblock-41 Pass E verified the original: a deliberate break makes this fail,
## and removing it makes it pass.
func _parses(path: String) -> bool:
	var script: Resource = load(path)
	if script == null or script is not GDScript:
		return false
	return (script as GDScript).reload() == OK


## A tool that is **meant** to have stopped compiling, marked in its own source.
##
## `tools/migrate_data.gd` is the case: a one-time taskblock-10 migration whose own
## doc comment records that "the hardcoded generators it reads from are deleted in
## the same pass that lands this tool's output". It is a tombstone, kept as a
## historical record, and it can never parse again. That is not rot and a guard
## that reported it as rot every build would be noise teaching everyone to ignore
## the guard.
##
## **The marker lives in the retired file, not in a list here**, so the exemption
## and its reason cannot drift apart, and so adding one is a decision made while
## looking at the file being exempted.
func _is_retired(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	return file.get_as_text().contains(RETIRED_MARKER)


## Every `.gd` directly under `res://tools/`. Deliberately not recursive: the one
## subdirectory is `tools/checkpoints/`, which the scan above already covers with a
## stricter check, and parsing it twice would double-report a single break.
## Every `.gd` directly under `dir_path`, or an empty list if the directory is not there
## at all. **A missing directory is a legitimate state, not an error** — the audit tree is
## removable by design (taskblock-53 Pass A), so this cannot be the thing that fails when
## someone removes it.
func _gd_paths_in(dir_path: String) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.ends_with(".gd") and not dir.current_is_dir():
			paths.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


func _tool_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(TOOLS_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.ends_with(".gd") and not dir.current_is_dir():
			paths.append("%s/%s" % [TOOLS_DIR, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


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
