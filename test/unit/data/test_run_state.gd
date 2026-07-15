extends GutTest

## docs/07: roster, stash, resource counters (data-driven ids), credits,
## seed — persistent meta-progression, and it must save/load round-trip.


func test_add_resource_accumulates_by_id() -> void:
	var run_state := RunState.new()
	run_state.add_resource(&"organics", 5)
	run_state.add_resource(&"organics", 3)
	run_state.add_resource(&"metals", 2)

	assert_eq(run_state.resource_count(&"organics"), 8)
	assert_eq(run_state.resource_count(&"metals"), 2)
	assert_eq(run_state.resource_count(&"unseen_resource"), 0)


func test_save_load_round_trips_roster_stash_and_resources() -> void:
	var run_state := RunState.new()
	var jerry := Matrix.new()
	jerry.id = &"jerry"
	jerry.level = 4
	run_state.roster = [jerry]

	var spare_arm := Part.new()
	spare_arm.id = &"spare_arm"
	spare_arm.hp = 5
	spare_arm.max_hp = 5
	run_state.stash = [spare_arm]

	run_state.add_resource(&"minerals", 12)
	run_state.credits = 500
	run_state.run_seed = 42

	var path := "user://tmp_test_run_state.tres"
	assert_eq(ResourceSaver.save(run_state, path), OK)
	var loaded: RunState = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	assert_eq(loaded.roster.size(), 1)
	assert_eq(loaded.roster[0].id, &"jerry")
	assert_eq(loaded.roster[0].level, 4)
	assert_eq(loaded.stash.size(), 1)
	assert_eq(loaded.stash[0].id, &"spare_arm")
	assert_eq(loaded.resource_count(&"minerals"), 12)
	assert_eq(loaded.credits, 500)
	assert_eq(loaded.run_seed, 42)
