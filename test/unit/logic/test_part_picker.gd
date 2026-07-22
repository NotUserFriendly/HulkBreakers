extends GutTest

## tb32 Pass C: generalizes UnitPicker (units only) to also ray-test every
## Grid.blockers/field_items Part, using the same box geometry BoardView
## renders (UnitGeometry.assembly_placements — "render is hitbox").


func _make_unit(cell: Vector2i, box_size: Vector3 = Vector3.ONE) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	root.volume = [Box.new(Vector3(0.0, 0.5, 0.0), box_size)]
	return Unit.new(Matrix.new(), Shell.new(root), cell, 0)


func _make_blocker(id: StringName, box_size: Vector3 = Vector3.ONE) -> Part:
	var part := Part.new()
	part.id = id
	part.hp = 5
	part.max_hp = 5
	part.volume = [Box.new(Vector3(0.0, 0.5, 0.0), box_size)]
	return part


func test_a_straight_down_ray_through_a_units_box_still_hits_that_unit() -> void:
	var a := _make_unit(Vector2i(2, 3))
	var grid := Grid.new(10, 10)

	var result: Dictionary = PartPicker.hit(
		[a], grid, Vector3(2.0, 5.0, 3.0), Vector3(0.0, -1.0, 0.0)
	)

	assert_eq(result.get("unit"), a, "the unit path must stay completely unchanged")
	assert_eq(result.get("cell"), Vector2i(2, 3))


func test_a_ray_through_a_blocker_reports_the_blocker_part_with_a_null_unit() -> void:
	var wall := _make_blocker(&"wall")
	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(2, 3)] = wall

	var result: Dictionary = PartPicker.hit(
		[], grid, Vector3(2.0, 5.0, 3.0), Vector3(0.0, -1.0, 0.0)
	)

	assert_null(result.get("unit"), "a blocker hit is never mistaken for a unit")
	assert_eq(result.get("part"), wall)
	assert_eq(result.get("cell"), Vector2i(2, 3))


func test_a_ray_through_a_loose_field_part_reports_it_with_a_null_unit() -> void:
	var dropped := _make_blocker(&"dropped_arm")
	var grid := Grid.new(10, 10)
	grid.field_items[Vector2i(4, 4)] = [Matrix.new(), dropped]

	var result: Dictionary = PartPicker.hit(
		[], grid, Vector3(4.0, 5.0, 4.0), Vector3(0.0, -1.0, 0.0)
	)

	assert_null(result.get("unit"))
	assert_eq(result.get("part"), dropped)


func test_a_loose_matrix_field_item_is_never_a_candidate() -> void:
	var grid := Grid.new(10, 10)
	grid.field_items[Vector2i(4, 4)] = [Matrix.new()]

	var result: Dictionary = PartPicker.hit(
		[], grid, Vector3(4.0, 5.0, 4.0), Vector3(0.0, -1.0, 0.0)
	)

	assert_true(result.is_empty(), "a Matrix has no volume/boxes to hit")


func test_the_nearer_of_a_unit_and_a_blocker_along_the_same_ray_wins() -> void:
	var near_unit := _make_unit(Vector2i(0, 0))
	var far_wall := _make_blocker(&"wall")
	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(0, 5)] = far_wall

	# A ray along +Z through both cells' X == 0 column.
	var result: Dictionary = PartPicker.hit(
		[near_unit], grid, Vector3(0.0, 0.5, -5.0), Vector3(0.0, 0.0, 1.0)
	)

	assert_eq(result.get("unit"), near_unit)


func test_the_nearer_blocker_wins_over_a_farther_unit() -> void:
	var near_wall := _make_blocker(&"wall")
	var far_unit := _make_unit(Vector2i(0, 5))
	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(0, 0)] = near_wall

	var result: Dictionary = PartPicker.hit(
		[far_unit], grid, Vector3(0.0, 0.5, -5.0), Vector3(0.0, 0.0, 1.0)
	)

	assert_null(result.get("unit"))
	assert_eq(result.get("part"), near_wall)


func test_a_ray_that_misses_everything_returns_nothing() -> void:
	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(2, 3)] = _make_blocker(&"wall")

	var result: Dictionary = PartPicker.hit(
		[], grid, Vector3(20.0, 5.0, 20.0), Vector3(0.0, -1.0, 0.0)
	)

	assert_true(result.is_empty())
