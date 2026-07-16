extends GutTest

## docs/02: ShotPlane.build flattens every unit and cover part along one line
## of fire into a single depth-sorted Array[Region]; resolve_projectile is
## the entire hit-resolution system — it only ever asks "does this rect
## contain the point," nearest first. Fixtures are authored symmetric about
## x == 0 (the line of fire) since that's the natural body-space origin;
## AsciiRender.recenter() shifts a copy into positive space for the printed
## dumps only, it never touches the coordinates assertions run against.


func _part(id: StringName, box: Box) -> Part:
	var part := Part.new()
	part.id = id
	part.hp = 5
	part.max_hp = 5
	part.volume = [box]
	return part


func test_plate_over_part_returns_the_plate_and_uncovered_point_returns_the_part_beneath() -> void:
	var arm := _part(&"arm", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6)))
	var plate := _part(&"plate", Box.new(Vector3(-0.5, 0.5, 0.4), Vector3(1.0, 1.0, 0.2)))

	var dir := Vector2(0, -1)
	var plane: Array[Region] = []
	plane.append_array(BodyProjector.project_part(plate, dir))
	plane.append_array(BodyProjector.project_part(arm, dir))
	plane.sort_custom(func(a: Region, b: Region) -> bool: return a.depth < b.depth)

	print("\n=== plate over part (left half only) ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 2))

	var over_plate := ShotPlane.resolve_projectile(plane, Vector2(-0.5, 0.5))
	assert_eq(over_plate.part.id, &"plate")

	var over_uncovered_arm := ShotPlane.resolve_projectile(plane, Vector2(0.5, 0.5))
	assert_eq(over_uncovered_arm.part.id, &"arm")


func test_point_with_nothing_in_the_plane_returns_null() -> void:
	var arm := _part(&"arm", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6)))
	var plane: Array[Region] = BodyProjector.project_part(arm, Vector2(0, -1))

	print("\n=== a shot slipping clean past the only part on the plane ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 2))

	assert_null(ShotPlane.resolve_projectile(plane, Vector2(5.0, 0.5)))


func test_shield_authored_as_boxes_around_a_hole_lets_a_point_in_the_hole_hit_the_part_behind(
) -> void:
	var shield := Part.new()
	shield.id = &"shield"
	shield.hp = 5
	shield.max_hp = 5
	shield.volume = [
		Box.new(Vector3(-1.5, 2.0, 0.5), Vector3(1.0, 4.0, 0.2)),  # left strip
		Box.new(Vector3(1.5, 2.0, 0.5), Vector3(1.0, 4.0, 0.2)),  # right strip
		Box.new(Vector3(0.0, 0.5, 0.5), Vector3(2.0, 1.0, 0.2)),  # bottom strip
		Box.new(Vector3(0.0, 3.5, 0.5), Vector3(2.0, 1.0, 0.2)),  # top strip
	]
	var body := _part(&"body", Box.new(Vector3(0.0, 2.0, 0.0), Vector3(4.0, 4.0, 0.6)))

	var dir := Vector2(0, -1)
	var plane: Array[Region] = []
	plane.append_array(BodyProjector.project_part(shield, dir))
	plane.append_array(BodyProjector.project_part(body, dir))
	plane.sort_custom(func(a: Region, b: Region) -> bool: return a.depth < b.depth)

	print("\n=== shield with a hole ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 4))

	var through_the_hole := ShotPlane.resolve_projectile(plane, Vector2(0.0, 2.0))
	assert_eq(through_the_hole.part.id, &"body")

	var off_the_strip := ShotPlane.resolve_projectile(plane, Vector2(-1.5, 2.0))
	assert_eq(off_the_strip.part.id, &"shield")


func _standing_unit(id: StringName, half_width: float, cell: Vector2i) -> Unit:
	var body := _part(id, Box.new(Vector3(0.0, 0.5, 0.0), Vector3(half_width * 2.0, 1.0, 0.6)))
	return Unit.new(Matrix.new(), Shell.new(body), cell)


func test_layered_targets_a_gap_in_the_near_unit_falls_through_to_the_far_unit() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	var far_unit := _standing_unit(&"far", 1.0, Vector2i(2, 6))
	state.add_unit(near_unit)
	state.add_unit(far_unit)

	var origin := Vector2(2, 0)
	var direction := Vector2(0, 1)
	var plane: Array[Region] = ShotPlane.build(origin, direction, state)

	print("\n=== layered targets: a narrow near unit, a wide far unit ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 2))

	var missed_near_hit_far := ShotPlane.resolve_projectile(plane, Vector2(0.8, 0.5))
	assert_eq(missed_near_hit_far.part.id, &"far")

	var hit_near := ShotPlane.resolve_projectile(plane, Vector2(0.2, 0.5))
	assert_eq(hit_near.part.id, &"near")


## docs/08: a UI must be able to show a stat panel for a partially obscured
## target deeper in the plane, not only the one a shot at a given point
## would actually hit.
func test_units_along_lists_every_layered_target_nearest_first() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	var far_unit := _standing_unit(&"far", 1.0, Vector2i(2, 6))
	state.add_unit(near_unit)
	state.add_unit(far_unit)

	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)
	var units: Array[Unit] = ShotPlane.units_along(plane, state)

	assert_eq(units, [near_unit, far_unit])


func test_units_along_excludes_a_dead_unit_with_no_region_in_the_plane() -> void:
	# BodyProjector/ShotPlane.build project every *alive* unit regardless of
	# how far off-axis it sits (there's no distance culling) — the one
	# thing that actually removes a unit from the plane entirely is not
	# being alive.
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var visible_unit := _standing_unit(&"visible", 0.5, Vector2i(2, 2))
	var dead_unit := _standing_unit(&"dead", 0.5, Vector2i(2, 4))
	dead_unit.alive = false
	state.add_unit(visible_unit)
	state.add_unit(dead_unit)

	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)
	assert_eq(ShotPlane.units_along(plane, state), [visible_unit])


func test_destroying_cover_removes_its_region_from_the_plane() -> void:
	var grid := Grid.new(5, 5)
	var state := CombatState.new(grid)
	var crate := _part(&"crate", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6)))
	grid.blockers[Vector2i(2, 2)] = crate

	var origin := Vector2(2, 0)
	var direction := Vector2(0, 1)

	var before: Array[Region] = ShotPlane.build(origin, direction, state)
	print("\n=== cover, standing ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(before, 2.0), 4, 2))
	assert_eq(ShotPlane.resolve_projectile(before, Vector2(0.0, 0.5)).part.id, &"crate")

	crate.hp = 0
	var after: Array[Region] = ShotPlane.build(origin, direction, state)
	print("\n=== cover, destroyed ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(after, 2.0), 4, 2))
	assert_null(ShotPlane.resolve_projectile(after, Vector2(0.0, 0.5)))


## docs/10 Phase 12.3: AimController groups the plane into layers by owning
## body — a unit's regions all point back to that Unit, cover's own regions
## point back to the cover Part itself.
func test_build_tags_every_region_with_its_owning_body() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	state.add_unit(near_unit)
	var crate := _part(&"crate", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6)))
	grid.blockers[Vector2i(2, 4)] = crate

	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)

	for region: Region in plane:
		if region.part == crate:
			assert_eq(region.body, crate)
		else:
			assert_eq(region.body, near_unit)


func test_center_of_returns_the_frontmost_regions_rect_center() -> void:
	var grid := Grid.new(10, 10)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	var state := CombatState.new(grid, [near_unit])
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)

	var center: Vector2 = ShotPlane.center_of(plane, near_unit)
	var expected: Region = ShotPlane.resolve_projectile(plane, center)
	assert_eq(
		expected.part.id, &"near", "the returned point must land inside the unit's own region"
	)


func test_center_of_falls_back_to_the_targets_cell_with_no_regions() -> void:
	var no_volume := Part.new()
	no_volume.id = &"ghost"
	no_volume.hp = 5
	no_volume.max_hp = 5
	var ghost_unit := Unit.new(Matrix.new(), Shell.new(no_volume), Vector2i(4, 4))
	var state := CombatState.new(Grid.new(10, 10), [ghost_unit])
	var plane: Array[Region] = ShotPlane.build(Vector2(4, 0), Vector2(0, 1), state)

	assert_eq(ShotPlane.center_of(plane, ghost_unit), Vector2(4, 4))
