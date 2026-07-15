extends GutTest


func _socketed_part(id: StringName, socket_types: Array[StringName] = []) -> Part:
	var p := Part.new()
	p.id = id
	p.hp = 1
	p.max_hp = 1
	for st: StringName in socket_types:
		p.sockets.append(Socket.new(st))
	return p


func test_all_parts_walks_the_whole_assembly() -> void:
	var torso := _socketed_part(&"torso", [&"SHOULDER"])
	var arm := _socketed_part(&"arm", [])
	arm.attaches_to = [&"SHOULDER"]
	torso.sockets[0].occupant = arm

	var frame := Frame.new(torso)
	assert_eq(frame.all_parts().size(), 2)


func test_living_parts_excludes_destroyed() -> void:
	var torso := _socketed_part(&"torso", [&"SHOULDER"])
	var arm := _socketed_part(&"arm")
	arm.hp = 0
	torso.sockets[0].occupant = arm

	var frame := Frame.new(torso)
	var living: Array[Part] = frame.living_parts()
	assert_eq(living.size(), 1)
	assert_eq(living[0], torso)


func test_aggregate_stats_sums_across_the_whole_tree() -> void:
	var torso := _socketed_part(&"torso", [&"SHOULDER"])
	torso.stat_mods = {"armor": 5}
	var arm := _socketed_part(&"arm")
	arm.stat_mods = {"armor": 2, "reach": 1}
	torso.sockets[0].occupant = arm

	var frame := Frame.new(torso)
	var stats: Dictionary = frame.aggregate_stats()
	assert_eq(stats["armor"], 7)
	assert_eq(stats["reach"], 1)


func test_save_load_round_trips_a_frame() -> void:
	var torso := _socketed_part(&"torso", [&"SHOULDER"])
	var arm := _socketed_part(&"arm")
	arm.attaches_to = [&"SHOULDER"]
	torso.sockets[0].occupant = arm

	var frame := Frame.new(torso)
	frame.max_mass = 150.0
	frame.max_ram = 10.0

	var path := "user://tmp_test_frame.tres"
	assert_eq(ResourceSaver.save(frame, path), OK)
	var loaded: Frame = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	assert_eq(loaded.max_mass, 150.0)
	assert_eq(loaded.max_ram, 10.0)
	assert_eq(loaded.root.id, &"torso")
	assert_eq(loaded.all_parts().size(), 2)
