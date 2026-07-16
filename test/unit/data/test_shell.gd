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

	var shell := Shell.new(torso)
	assert_eq(shell.all_parts().size(), 2)


func test_living_parts_excludes_destroyed() -> void:
	var torso := _socketed_part(&"torso", [&"SHOULDER"])
	var arm := _socketed_part(&"arm")
	arm.hp = 0
	torso.sockets[0].occupant = arm

	var shell := Shell.new(torso)
	var living: Array[Part] = shell.living_parts()
	assert_eq(living.size(), 1)
	assert_eq(living[0], torso)


func test_stat_resolver_sums_a_stat_across_the_whole_tree() -> void:
	# Shell itself no longer sums stats directly (Phase 2: StatResolver is the
	# only place a final stat is computed) — this proves all_parts() feeds it
	# correctly across a real socket tree, not just a flat list.
	var torso := _socketed_part(&"torso", [&"SHOULDER"])
	torso.stat_mods = {&"armor": 5}
	var arm := _socketed_part(&"arm")
	arm.stat_mods = {&"armor": 2, &"reach": 1}
	torso.sockets[0].occupant = arm

	var shell := Shell.new(torso)
	var context := ResolverContext.new()
	context.parts = shell.all_parts()

	assert_eq(StatResolver.resolve(&"armor", context).current, 7.0)
	assert_eq(StatResolver.resolve(&"reach", context).current, 1.0)


func test_total_ram_sums_ram_cost_across_the_whole_assembly() -> void:
	var torso := _socketed_part(&"torso", [&"SHOULDER"])
	torso.ram_cost = 1.0
	var arm := _socketed_part(&"arm")
	arm.ram_cost = 0.5
	torso.sockets[0].occupant = arm

	var shell := Shell.new(torso)
	assert_almost_eq(shell.total_ram(), 1.5, 0.0001)


func test_total_ram_also_counts_items_carried_in_a_container() -> void:
	var torso := _socketed_part(&"torso", [&"BACK"])
	var bag := _socketed_part(&"bag")
	bag.is_container = true
	bag.max_bulk = 10.0
	torso.sockets[0].occupant = bag

	var gadget := Part.new()
	gadget.id = &"gadget"
	gadget.hp = 1
	gadget.max_hp = 1
	gadget.ram_cost = 2.0
	bag.contents = [gadget]

	var shell := Shell.new(torso)
	assert_almost_eq(
		shell.total_ram(), 2.0, 0.0001, "a bagged item's RAM must not be discounted away"
	)


## docs/05 taskblock04 D1: "anything body-attached is discounted to at
## least 0.8. Wearing it beats dragging it, always." A container that
## forgot to author a real mass_multiplier (left at the default, 1.0 — no
## discount at all) must still get AT LEAST an 0.8 ceiling once worn.
func test_carried_mass_applies_the_worn_discount_ceiling_even_with_no_authored_discount() -> void:
	var torso := _socketed_part(&"torso", [&"BACK"])
	var bag := _socketed_part(&"bag")
	bag.is_container = true
	bag.max_bulk = 100.0
	# mass_multiplier left at Part's own default: 1.0.
	torso.sockets[0].occupant = bag

	var gear := Part.new()
	gear.id = &"gear"
	gear.hp = 1
	gear.max_hp = 1
	gear.mass = 20.0
	bag.contents = [gear]

	var shell := Shell.new(torso)
	assert_almost_eq(
		shell.carried_mass(),
		16.0,
		0.0001,
		"20 * 0.8 ceiling, not 20 * 1.0 — worn always beats a forgotten discount"
	)


## A container's OWN, more generous multiplier (a backpack's 0.5) must
## still win — the ceiling only ever rescues a bad/missing number, it
## never makes a genuinely better container worse.
func test_carried_mass_never_worsens_a_containers_own_better_discount() -> void:
	var torso := _socketed_part(&"torso", [&"BACK"])
	var backpack: Part = Containers.backpack()
	torso.sockets[0].occupant = backpack

	var gear := Part.new()
	gear.id = &"gear"
	gear.hp = 1
	gear.max_hp = 1
	gear.mass = 20.0
	backpack.contents = [gear]

	var shell := Shell.new(torso)
	assert_almost_eq(
		shell.carried_mass(),
		backpack.mass + 10.0,
		0.0001,
		"backpack's own 0.5 (better than the 0.8 ceiling) must still apply"
	)


func test_save_load_round_trips_a_shell() -> void:
	var torso := _socketed_part(&"torso", [&"SHOULDER"])
	var arm := _socketed_part(&"arm")
	arm.attaches_to = [&"SHOULDER"]
	torso.sockets[0].occupant = arm

	var shell := Shell.new(torso)
	shell.max_mass = 150.0
	shell.max_ram = 10.0

	var path := "user://tmp_test_shell.tres"
	assert_eq(ResourceSaver.save(shell, path), OK)
	var loaded: Shell = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	assert_eq(loaded.max_mass, 150.0)
	assert_eq(loaded.max_ram, 10.0)
	assert_eq(loaded.root.id, &"torso")
	assert_eq(loaded.all_parts().size(), 2)
