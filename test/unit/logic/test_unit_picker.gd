extends GutTest

## docs/10 taskblock03 D1: ray-vs-body hit testing is pure math against
## UnitGeometry.placements() — the same boxes a HitVolumeView renders.


func _make_unit(cell: Vector2i, box_size: Vector3 = Vector3.ONE) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	root.volume = [Box.new(Vector3(0.0, 0.5, 0.0), box_size)]
	return Unit.new(Matrix.new(), Shell.new(root), cell, 0)


func test_a_straight_down_ray_through_a_units_box_hits_that_unit() -> void:
	var a := _make_unit(Vector2i(2, 3))
	var units: Array[Unit] = [a]

	var result: Dictionary = UnitPicker.hit(units, Vector3(2.0, 5.0, 3.0), Vector3(0.0, -1.0, 0.0))

	assert_eq(result.get("unit"), a)


## docs/10 taskblock05 C: the same nearest-box search already knows which
## Part it hit, not just which Unit — the same search Pass C's 3D-hover
## highlight needs, exposed rather than re-derived.
func test_hit_reports_the_specific_part_whose_box_was_struck() -> void:
	var head := Part.new()
	head.id = &"head"
	head.hp = 5
	head.max_hp = 5
	head.volume = [Box.new(Vector3(0.0, 1.8, 0.0), Vector3(0.4, 0.4, 0.4))]
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	torso.volume = [Box.new(Vector3(0.0, 1.0, 0.0), Vector3(0.4, 0.4, 0.4))]
	var neck := Socket.new(&"NECK")
	neck.occupant = head
	torso.sockets = [neck]
	var a := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0), 0)
	var units: Array[Unit] = [a]

	var result: Dictionary = UnitPicker.hit(units, Vector3(0.0, 1.8, 0.0), Vector3(0.0, -1.0, 0.0))

	assert_eq(result.get("unit"), a)
	assert_eq(result.get("part"), head)


func test_a_ray_that_misses_every_box_returns_nothing() -> void:
	var a := _make_unit(Vector2i(2, 3))
	var units: Array[Unit] = [a]

	var result: Dictionary = UnitPicker.hit(
		units, Vector3(20.0, 5.0, 20.0), Vector3(0.0, -1.0, 0.0)
	)

	assert_true(result.is_empty())


func test_the_nearer_of_two_units_along_the_same_ray_wins() -> void:
	var near := _make_unit(Vector2i(0, 0))
	var far := _make_unit(Vector2i(0, 5))
	var units: Array[Unit] = [far, near]  # order must not matter

	# A ray along -Z through both cells' X == 0 column.
	var result: Dictionary = UnitPicker.hit(units, Vector3(0.0, 0.5, -5.0), Vector3(0.0, 0.0, 1.0))

	assert_eq(result.get("unit"), near)


func test_dead_units_are_never_hit() -> void:
	var a := _make_unit(Vector2i(2, 3))
	a.alive = false
	var units: Array[Unit] = [a]

	var result: Dictionary = UnitPicker.hit(units, Vector3(2.0, 5.0, 3.0), Vector3(0.0, -1.0, 0.0))

	assert_true(result.is_empty())


func test_hit_t_is_comparable_to_board_pickers_plane_hit_t_on_the_same_ray() -> void:
	# A unit box at (0,0.5,0) with size (1,1,1) sits between y=0 and y=1;
	# a straight-down ray from y=5 must hit the box (t=4) before it would
	# ever reach the ground plane at y=0 (t=5).
	var a := _make_unit(Vector2i(0, 0))
	var units: Array[Unit] = [a]
	var from := Vector3(0.0, 5.0, 0.0)
	var dir := Vector3(0.0, -1.0, 0.0)

	var unit_hit: Dictionary = UnitPicker.hit(units, from, dir)
	var ground_t: Variant = BoardPicker.plane_hit_t(from, dir)

	assert_almost_eq(unit_hit.get("t"), 4.0, 0.0001)
	assert_almost_eq(ground_t, 5.0, 0.0001)
	assert_lt(unit_hit.get("t"), ground_t, "the body is nearer than the ground behind it")
