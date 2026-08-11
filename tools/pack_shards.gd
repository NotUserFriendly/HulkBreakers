extends SceneTree

## tb66 Pass E — **generates the committed shard map from the committed profile.**
##
##     godot --headless --path . -s res://tools/pack_shards.gd
##
## Writes `test/shard_map.json`. **Run it when the profile moves and commit the diff**; the map is
## deliberately an artifact rather than a run-time computation — see `ShardMap` for why.
##
## ## The profile it reads must come from an unsharded run (Pass E6)
##
## The packer reads **per-file wall-clock**, and eight processes competing for cores inflate and
## scramble exactly that. A profile regenerated under sharding would degrade the packer's own input
## a little more on every regeneration, and the degradation would compound silently because each
## run looks locally reasonable. `run_tests.sh` writes the profile from the single-process path and
## that is where it must stay.
##
## ## The algorithm, and why it is the boring one
##
## Longest-processing-time-first into the emptiest bin. It is not optimal — bin packing is NP-hard
## — but it is deterministic, it is one screen of code, and at eight shards it balances the
## non-corpus half to within a second. **An optimal packer would buy nothing**: the makespan is the
## corpus shard, not the packing.

const PROFILE_PATH := "res://test/suite_profile.json"
const OUT_PATH := "res://test/shard_map.json"
const SHARD_COUNT := 8


func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not parsed is Dictionary:
		push_error("could not read %s" % PROFILE_PATH)
		quit(1)
		return
	var cost: Dictionary = {}
	for row: Dictionary in (parsed as Dictionary).get("files", []):
		cost[String(row.get("path", ""))] = float(row.get("usec", 0)) / 1_000_000.0

	var discovered: Array[String] = _discover("res://test")
	discovered.sort()

	# Shard 0 takes every corpus reader, whatever it costs — it is the makespan and the draw must
	# be paid exactly once. Everything else is packed to finish under it.
	var shards: Array[Array] = []
	var load_s: Array[float] = []
	for i: int in range(SHARD_COUNT):
		shards.append([] as Array)
		load_s.append(0.0)

	var rest: Array[String] = []
	for path: String in discovered:
		if path in SuiteTier.CORPUS_READERS:
			shards[ShardMap.CORPUS_SHARD].append(path)
			load_s[ShardMap.CORPUS_SHARD] += float(cost.get(path, ShardMap.UNKNOWN_FILE_COST))
		else:
			rest.append(path)

	# Co-located groups are packed as one unit, so a corpus's fill is paid once. Priced at Pass E3:
	# both `MapCorpus` keyspaces fit a bin with room to spare at eight shards.
	var groups: Array[Array] = _corpus_groups(rest)
	var grouped: Dictionary = {}
	for group: Array in groups:
		for path: Variant in group:
			grouped[path] = true

	var units: Array[Array] = []
	for group: Array in groups:
		var total := 0.0
		for path: Variant in group:
			total += float(cost.get(path, ShardMap.UNKNOWN_FILE_COST))
		units.append([total, group])
	for path: String in rest:
		if not grouped.has(path):
			units.append([float(cost.get(path, ShardMap.UNKNOWN_FILE_COST)), [path] as Array])

	units.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))

	for unit: Array in units:
		# Never shard 0 — it carries the draw and packing more onto it lengthens the gate directly.
		var best: int = 1
		for i: int in range(1, SHARD_COUNT):
			if load_s[i] < load_s[best]:
				best = i
		load_s[best] += float(unit[0])
		for path: Variant in unit[1]:
			shards[best].append(String(path))

	var out: Dictionary = {"shards": {}, "generated_from": PROFILE_PATH, "shard_count": SHARD_COUNT}
	for i: int in range(SHARD_COUNT):
		var listed: Array = shards[i]
		listed.sort()
		out["shards"][str(i)] = listed
		print(
			(
				"shard %d: %5.1f s, %3d files%s"
				% [i, load_s[i], listed.size(), "  (corpus)" if i == ShardMap.CORPUS_SHARD else ""]
			)
		)

	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("could not write %s" % OUT_PATH)
		quit(1)
		return
	file.store_line(JSON.stringify(out, "  "))
	file.close()
	print("wrote %s — %d files across %d shards" % [OUT_PATH, discovered.size(), SHARD_COUNT])
	quit()


## The reader sets that must not be split, per Pass E3. Named here rather than derived, because
## which files read which corpus is a fact about the tests and a derivation would go stale silently.
func _corpus_groups(available: Array[String]) -> Array[Array]:
	var names: Array[Array] = [
		[
			"test_map_gen.gd",
			"test_map_gen_raised_rooms.gd",
			"test_step_height.gd",
			"test_mag_lift.gd",
			"test_map_navigability.gd",
			"test_sight_cost_probe.gd",
			"test_cutout_feed_cost_probe.gd",
			"test_cutout_gate_cost_probe.gd",
			"test_cutout_gate_over_zoom.gd",
			"test_aim_cost_probe.gd",
			"test_aim_frame_probe.gd",
		],
		["test_map_gen_reachability.gd", "test_generation_heights.gd", "test_vertical_routes.gd"],
	]
	var groups: Array[Array] = []
	for group: Array in names:
		var resolved: Array = []
		for base: Variant in group:
			for path: String in available:
				if path.get_file() == String(base):
					resolved.append(path)
		if not resolved.is_empty():
			groups.append(resolved)
	return groups


func _discover(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var path: String = "%s/%s" % [root, name]
		if dir.current_is_dir():
			found.append_array(_discover(path))
		elif name.begins_with("test_") and name.ends_with(".gd"):
			found.append(path)
		name = dir.get_next()
	dir.list_dir_end()
	return found
