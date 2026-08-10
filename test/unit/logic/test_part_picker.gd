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
	grid.place_blocker(Vector2i(2, 3), wall)

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
	grid.place_blocker(Vector2i(0, 5), far_wall)

	# A ray along +Z through both cells' X == 0 column.
	var result: Dictionary = PartPicker.hit(
		[near_unit], grid, Vector3(0.0, 0.5, -5.0), Vector3(0.0, 0.0, 1.0)
	)

	assert_eq(result.get("unit"), near_unit)


func test_the_nearer_blocker_wins_over_a_farther_unit() -> void:
	var near_wall := _make_blocker(&"wall")
	var far_unit := _make_unit(Vector2i(0, 5))
	var grid := Grid.new(10, 10)
	grid.place_blocker(Vector2i(0, 0), near_wall)

	var result: Dictionary = PartPicker.hit(
		[far_unit], grid, Vector3(0.0, 0.5, -5.0), Vector3(0.0, 0.0, 1.0)
	)

	assert_null(result.get("unit"))
	assert_eq(result.get("part"), near_wall)


func test_a_ray_that_misses_everything_returns_nothing() -> void:
	var grid := Grid.new(10, 10)
	grid.place_blocker(Vector2i(2, 3), _make_blocker(&"wall"))

	var result: Dictionary = PartPicker.hit(
		[], grid, Vector3(20.0, 5.0, 20.0), Vector3(0.0, -1.0, 0.0)
	)

	assert_true(result.is_empty())


## taskblock-58 Pass A. **Fired at a box that was built, from six directions, and the reported
## normal must point back the way the ray came** — the same shape as
## `test_ray_box_hit_reports_the_face_it_entered_through`, one layer up. Re-deriving the entry
## face from the hit point here would agree with the arithmetic under test and with nothing else.
func test_a_pick_reports_the_face_it_struck() -> void:
	var grid := Grid.new(10, 10)
	grid.place_blocker(Vector2i(4, 4), _make_blocker(&"wall"))
	# The blocker's own box: a 1.0 cube centred at (4.0, 0.5, 4.0) in world space.
	var centre := Vector3(4.0, 0.5, 4.0)
	var faces: Array[Vector3] = [
		Vector3.UP,
		Vector3.DOWN,
		Vector3.LEFT,
		Vector3.RIGHT,
		Vector3.FORWARD,
		Vector3.BACK,
	]

	for face: Vector3 in faces:
		var from: Vector3 = centre + face * 2.0
		var result: Dictionary = PartPicker.hit([], grid, from, -face)
		assert_false(result.is_empty(), "a ray fired straight at the box hits it (face %s)" % face)
		var normal: Vector3 = result["normal"]
		print("  from %-20s dir %-20s -> normal %s" % [from, -face, normal])
		assert_almost_eq(
			normal.distance_to(face),
			0.0,
			0.0001,
			"the struck face's normal points back toward the picker (face %s)" % face
		)


## The pick and the march are the same question asked by two callers, and Pass A's entire claim is
## that there is **one** computation of a face normal behind both. Asserted rather than assumed:
## "it delegates" is exactly the sort of statement a test can check.
func test_the_normal_a_pick_reports_is_the_one_the_march_reports() -> void:
	var grid: Grid = GridFixture.flat(11, 11)
	var wall: Part = GridFixture.place_wall(grid, Vector2i(5, 5))
	var state := CombatState.new(grid, [])
	var centre := Vector3(5.0, 0.5, 5.0)
	var compared := 0

	for angle in range(0, 360, 29):
		var rad: float = deg_to_rad(float(angle))
		var from: Vector3 = centre + Vector3(cos(rad), 0.0, sin(rad)) * 4.0
		var dir: Vector3 = (centre - from).normalized()

		var picked: Dictionary = PartPicker.hit([] as Array[Unit], grid, from, dir)
		var marched: RayHit = RayCaster.cast(state, from, dir)
		assert_false(picked.is_empty(), "the picker finds the wall at %d degrees" % angle)
		assert_not_null(marched, "and so does the march at %d degrees" % angle)
		assert_eq(picked["part"], wall, "both report the wall at %d degrees" % angle)
		assert_eq(marched.part, wall, "both report the wall at %d degrees" % angle)
		var picked_normal: Vector3 = picked["normal"]
		print("  %3d deg -> picked %s / marched %s" % [angle, picked_normal, marched.normal])
		assert_almost_eq(
			picked_normal.distance_to(marched.normal),
			0.0,
			0.0001,
			"one computation, so one answer, at %d degrees" % angle
		)
		compared += 1

	assert_gt(compared, 10, "the sweep actually ran")


## **A zero vector is a direction.** It survives a `dot`, it survives a `distance_to`, and a caller
## that treats it as the struck face gets a plausible-looking answer to a question that had none.
## So an absent face is an absent key, not a zeroed one.
func test_a_miss_reports_no_normal_rather_than_a_zero_vector() -> void:
	var grid := Grid.new(10, 10)
	grid.place_blocker(Vector2i(2, 3), _make_blocker(&"wall"))

	var result: Dictionary = PartPicker.hit(
		[], grid, Vector3(20.0, 5.0, 20.0), Vector3(0.0, -1.0, 0.0)
	)

	assert_true(result.is_empty(), "the miss reports nothing at all")
	assert_false(result.has("normal"), "and specifically not a normal")
	assert_null(result.get("normal"), "a reader asking for one gets null, never Vector3.ZERO")


## The unit half of the same widening — `PartPicker` reads `UnitPicker.hit`'s dict for the unit
## case and cannot report a face the inner search discarded.
func test_a_pick_against_a_unit_reports_the_struck_face_too() -> void:
	var target: Unit = _make_unit(Vector2i(3, 3))
	var grid := Grid.new(10, 10)

	var result: Dictionary = PartPicker.hit(
		[target], grid, Vector3(3.0, 5.0, 3.0), Vector3(0.0, -1.0, 0.0)
	)

	assert_eq(result.get("unit"), target)
	var normal: Vector3 = result["normal"]
	print("  straight down onto a unit -> normal %s" % normal)
	assert_almost_eq(normal.distance_to(Vector3.UP), 0.0, 0.0001, "the top of its box")
