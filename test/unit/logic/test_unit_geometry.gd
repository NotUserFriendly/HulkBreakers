extends GutTest

## docs/10 "render is hitbox": UnitGeometry.placements() must expose exactly
## the same boxes BodyProjector would hit, fully placed in world space.


func test_no_root_produces_no_placements() -> void:
	var unit := Unit.new(Matrix.new(), Shell.new(null), Vector2i(0, 0))
	assert_eq(UnitGeometry.placements(unit), [] as Array[BoxPlacement])


func test_a_single_box_root_places_at_the_units_cell() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(3, 4))
	var placements: Array[BoxPlacement] = UnitGeometry.placements(unit)

	assert_eq(placements.size(), 1)
	var world_center: Vector3 = placements[0].transform * placements[0].box.center
	assert_almost_eq(world_center.x, 3.0, 0.0001)
	assert_almost_eq(world_center.z, 4.0, 0.0001)
	assert_almost_eq(world_center.y, 0.5, 0.0001)


## docs/10 taskblock03 E3: `orientation_override` replaces `unit.orientation`
## for this placement pass only, so a view can render TACTICS' speculative
## preview without cloning the whole Unit.
func test_orientation_override_replaces_the_units_own_orientation() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(1.0, 0.0, 0.0), Vector3(0.2, 0.2, 0.2))]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	unit.orientation = 0.0
	var default_placements: Array[BoxPlacement] = UnitGeometry.placements(unit)
	var overridden: Array[BoxPlacement] = UnitGeometry.placements(unit, PI / 2.0)

	var default_center: Vector3 = default_placements[0].transform * default_placements[0].box.center
	var overridden_center: Vector3 = overridden[0].transform * overridden[0].box.center

	assert_almost_eq(unit.orientation, 0.0, 0.0001, "the real unit must never be mutated")
	assert_false(
		default_center.is_equal_approx(overridden_center),
		"a 90-degree override must actually move the box",
	)


func test_a_null_orientation_override_is_the_same_as_omitting_it() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(1.0, 0.0, 0.0), Vector3(0.2, 0.2, 0.2))]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	unit.orientation = 1.2
	var explicit_null: Array[BoxPlacement] = UnitGeometry.placements(unit, null)
	var omitted: Array[BoxPlacement] = UnitGeometry.placements(unit)

	assert_eq(
		explicit_null[0].transform * explicit_null[0].box.center,
		omitted[0].transform * omitted[0].box.center
	)


func test_dead_parts_produce_no_placements() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 0
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(1, 1, 1))]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	assert_eq(UnitGeometry.placements(unit), [] as Array[BoxPlacement])


func test_a_destroyed_child_part_disappears_but_its_living_siblings_remain() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 0
	arm.max_hp = 4
	arm.volume = [Box.new(Vector3.ZERO, Vector3(0.4, 0.9, 0.4))]

	var leg := Part.new()
	leg.id = &"leg"
	leg.hp = 4
	leg.max_hp = 4
	leg.volume = [Box.new(Vector3.ZERO, Vector3(0.4, 1.0, 0.4))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	var shoulder := Socket.new(&"SHOULDER")
	shoulder.occupant = arm
	var hip := Socket.new(&"HIP")
	hip.occupant = leg
	torso.sockets = [shoulder, hip]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var placements: Array[BoxPlacement] = UnitGeometry.placements(unit)

	var placed_ids: Array[StringName] = []
	for placement: BoxPlacement in placements:
		placed_ids.append(placement.part.id)

	assert_true(placed_ids.has(&"torso"))
	assert_true(placed_ids.has(&"leg"))
	assert_false(placed_ids.has(&"arm"), "a destroyed part must not be placed")


func test_a_socket_transform_offsets_the_child_from_the_root() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 4
	arm.volume = [Box.new(Vector3.ZERO, Vector3(0.4, 0.9, 0.4))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	var shoulder := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(1.0, 0.5, 0.0)))
	shoulder.occupant = arm
	torso.sockets = [shoulder]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var placements: Array[BoxPlacement] = UnitGeometry.placements(unit)

	var arm_placement: BoxPlacement = null
	for placement: BoxPlacement in placements:
		if placement.part.id == &"arm":
			arm_placement = placement
	assert_not_null(arm_placement)
	var arm_world: Vector3 = arm_placement.transform * arm_placement.box.center
	assert_almost_eq(arm_world.x, 1.0, 0.0001)
	assert_almost_eq(arm_world.y, 0.5, 0.0001)
