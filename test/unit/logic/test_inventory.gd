extends GutTest


func _make_container(
	volume: float, max_volume: float, mass: float = 0.0, mult: float = 1.0
) -> Part:
	var c := Part.new()
	c.is_container = true
	c.volume = volume
	c.max_volume = max_volume
	c.mass = mass
	c.mass_multiplier = mult
	return c


func _make_item(volume: float, mass: float = 0.0) -> Part:
	var p := Part.new()
	p.volume = volume
	p.mass = mass
	return p


func test_attach_succeeds_within_volume_limit() -> void:
	var bag := _make_container(1.0, 10.0)
	var item := _make_item(4.0)
	assert_true(Inventory.attach(item, bag))
	assert_true(bag.contents.has(item))


func test_attach_rejects_over_volume() -> void:
	var bag := _make_container(1.0, 5.0)
	var existing := _make_item(3.0)
	bag.contents = [existing]
	var too_big := _make_item(3.0)  # 3 + 3 = 6 > max_volume 5
	assert_false(Inventory.attach(too_big, bag))
	assert_false(bag.contents.has(too_big))


func test_nested_container_occupies_parent_by_own_volume_not_contents() -> void:
	var backpack := _make_container(1.0, 10.0)
	var pouch := _make_container(3.0, 100.0)  # pouch's own external volume is 3.0
	var bulky_item := _make_item(50.0)  # huge, but it's inside the pouch, not the backpack
	assert_true(Inventory.attach(bulky_item, pouch))
	# Only the pouch's own volume (3.0) counts against the backpack's max_volume.
	assert_true(Inventory.attach(pouch, backpack))
	assert_true(backpack.contents.has(pouch))


func test_attach_rejects_cycle_when_target_already_contains_source() -> void:
	var outer := _make_container(1.0, 10.0)
	var inner := _make_container(1.0, 10.0)
	assert_true(Inventory.attach(inner, outer))
	# outer already contains inner; attaching outer into inner would cycle.
	assert_false(Inventory.attach(outer, inner))


func test_attach_rejects_self_attachment() -> void:
	var container := _make_container(1.0, 10.0)
	assert_false(Inventory.attach(container, container))


func test_attach_rejects_non_container_target() -> void:
	var not_a_container := _make_item(1.0)
	var item := _make_item(1.0)
	assert_false(Inventory.attach(item, not_a_container))


func test_attach_respects_chassis_max_mass() -> void:
	var chassis := Chassis.new()
	chassis.max_mass = 20.0
	var bag := _make_container(1.0, 100.0, 2.0, 1.0)
	chassis.install(bag)  # slot_type default TORSO; fine, only one part

	var light := _make_item(1.0, 5.0)
	assert_true(Inventory.attach(light, bag, chassis))  # 2 (bag) + 5 = 7 <= 20

	var heavy := _make_item(1.0, 50.0)
	assert_false(Inventory.attach(heavy, bag, chassis))  # 2 + 5 + 50 = 57 > 20
	assert_false(bag.contents.has(heavy))


func test_detach_removes_part_and_returns_true() -> void:
	var bag := _make_container(1.0, 10.0)
	var item := _make_item(1.0)
	Inventory.attach(item, bag)
	assert_true(Inventory.detach(item, bag))
	assert_false(bag.contents.has(item))


func test_detach_returns_false_when_not_present() -> void:
	var bag := _make_container(1.0, 10.0)
	var stray := _make_item(1.0)
	assert_false(Inventory.detach(stray, bag))


func test_walk_visits_root_and_all_descendants() -> void:
	var root := _make_container(1.0, 10.0)
	var mid := _make_container(1.0, 10.0)
	var leaf := _make_item(1.0)
	Inventory.attach(mid, root)
	Inventory.attach(leaf, mid)

	var visited: Array[Part] = Inventory.walk(root)
	assert_eq(visited.size(), 3)
	assert_has(visited, root)
	assert_has(visited, mid)
	assert_has(visited, leaf)


func test_flatten_excludes_root_but_includes_all_depths() -> void:
	var root := _make_container(1.0, 10.0)
	var mid := _make_container(1.0, 10.0)
	var leaf := _make_item(1.0)
	Inventory.attach(mid, root)
	Inventory.attach(leaf, mid)

	var flat: Array[Part] = Inventory.flatten(root)
	assert_eq(flat.size(), 2)
	assert_does_not_have(flat, root)
	assert_has(flat, mid)
	assert_has(flat, leaf)


func test_carried_mass_appendix_d_worked_example() -> void:
	var chassis := Chassis.new()
	chassis.max_mass = 1000.0
	var backpack := _make_container(1.0, 100.0, 2.0, 0.5)
	chassis.install(backpack)

	var gear := _make_item(1.0, 50.0)
	assert_true(Inventory.attach(gear, backpack, chassis))
	# 2 (bag, full) + 50 * 0.5 = 27
	assert_almost_eq(chassis.carried_mass(), 27.0, 0.0001)

	var pouch := _make_container(1.0, 100.0, 1.0, 0.8)
	assert_true(Inventory.attach(pouch, backpack, chassis))
	var pouch_item := _make_item(1.0, 10.0)
	assert_true(Inventory.attach(pouch_item, pouch, chassis))
	# pouch's 0.8 is ignored (not directly worn): pouch(1) + item(10) = 11, flat,
	# discounted only by the backpack's 0.5 -> 5.5. Total: 2 + 25 + 5.5 = 32.5
	assert_almost_eq(chassis.carried_mass(), 32.5, 0.0001)
