extends GutTest

## docs/01 "The Reference Humanoid": body-shape-driven mechanics can't be
## tested against a shapeless body. These tests exercise the composed,
## deterministic skeleton DeepStrike.assemble_reference_humanoid() builds —
## every one of them is a geometry fact, not a design choice.


func _reference_unit(cell: Vector2i = Vector2i(0, 0)) -> Unit:
	return DeepStrike.assemble_reference_humanoid(Matrix.new(), cell)


func _world_corners(placement: BoxPlacement) -> Array[Vector3]:
	var half: Vector3 = placement.box.size * 0.5
	var center: Vector3 = placement.box.center
	var corners: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var local: Vector3 = center + Vector3(sx * half.x, sy * half.y, sz * half.z)
				corners.append(placement.transform * local)
	return corners


func _find(regions: Array[Region], part_id: StringName) -> Region:
	for region: Region in regions:
		if region.part.id == part_id:
			return region
	fail_test("no region for part %s" % part_id)
	return null


## BodyProjector.project() does not sort by depth — only ShotPlane.build()
## does, for a whole-CombatState plane. resolve_projectile() assumes a
## depth-sorted array (it returns the first containing region, nearest
## first), so any test resolving against a single-unit BodyProjector.project()
## plane must sort it first, same as ShotPlane.build() does internally.
func _sorted(regions: Array[Region]) -> Array[Region]:
	var copy: Array[Region] = regions.duplicate()
	copy.sort_custom(func(a: Region, b: Region) -> bool: return a.depth < b.depth)
	return copy


func test_no_living_part_extends_below_the_floor() -> void:
	var unit := _reference_unit()
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		for corner: Vector3 in _world_corners(placement):
			assert_true(
				corner.y >= -0.0001,
				"%s extends below the floor: y=%f" % [placement.part.id, corner.y]
			)


func test_feet_touch_the_floor() -> void:
	var unit := _reference_unit()
	var min_y := INF
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		for corner: Vector3 in _world_corners(placement):
			min_y = minf(min_y, corner.y)
	assert_almost_eq(min_y, 0.0, 0.01)


func test_head_is_the_highest_part_a_leg_is_the_lowest() -> void:
	var unit := _reference_unit()
	var top_id: StringName = &""
	var top_y := -INF
	var bottom_id: StringName = &""
	var bottom_y := INF
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		for corner: Vector3 in _world_corners(placement):
			if corner.y > top_y:
				top_y = corner.y
				top_id = placement.part.id
			if corner.y < bottom_y:
				bottom_y = corner.y
				bottom_id = placement.part.id
	assert_eq(top_id, &"head")
	assert_eq(bottom_id, &"leg")


func test_arms_are_lateral_a_left_and_a_right_both_exist() -> void:
	var unit := _reference_unit()
	var saw_positive := false
	var saw_negative := false
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		if placement.part.id == &"arm":
			var world_x: float = (placement.transform * placement.box.center).x
			if world_x > 0.05:
				saw_positive = true
			elif world_x < -0.05:
				saw_negative = true
	assert_true(saw_positive and saw_negative, "both a left (-x) and right (+x) arm must exist")


func test_the_composed_body_fits_inside_one_cell_footprint() -> void:
	var unit := _reference_unit()
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		for corner: Vector3 in _world_corners(placement):
			min_x = minf(min_x, corner.x)
			max_x = maxf(max_x, corner.x)
			min_z = minf(min_z, corner.z)
			max_z = maxf(max_z, corner.z)
	assert_true(
		max_x - min_x <= UnitGeometry.CELL_SIZE, "width %f exceeds one cell" % (max_x - min_x)
	)
	assert_true(
		max_z - min_z <= UnitGeometry.CELL_SIZE, "depth %f exceeds one cell" % (max_z - min_z)
	)


func test_a_plates_rect_overlaps_its_parents_and_sits_at_lower_depth_from_the_front() -> void:
	var unit := _reference_unit()
	var regions: Array[Region] = BodyProjector.project(unit, Vector2(0, -1))
	var torso: Region = _find(regions, &"torso")
	var plate: Region = _find(regions, &"torso_plate_front")

	assert_true(plate.rect.intersects(torso.rect), "the plate must project over its parent")
	assert_lt(plate.depth, torso.depth, "the front plate must sit nearer the shooter")


## The load-bearing case (docs/01): the same shot resolves to the front
## plate head-on, and to the thin rear plate (or bare torso) once flanked —
## the front plate is never the frontmost hit once you're behind it, even
## though its own back face can still legitimately appear as an occluded
## region (BodyProjector projects per visible face, docs/02/03) rather than
## vanishing from the array outright.
func test_the_flank_test() -> void:
	var unit := _reference_unit()

	var front: Array[Region] = _sorted(BodyProjector.project(unit, Vector2(0, -1)))
	var plate_rect: Rect2 = _find(front, &"torso_plate_front").rect
	# Off-center (docs/01a's own BACK-socket ammo rack sits directly behind
	# the spine, narrower than the plates either side of it) — aim through
	# the plate's own body, not through whatever else happens to share its
	# lateral center.
	var aim_point: Vector2 = plate_rect.get_center() + Vector2(0.15, 0.0)
	var front_hit: Region = ShotPlane.resolve_projectile(front, aim_point)
	assert_eq(front_hit.part.id, &"torso_plate_front")

	var back: Array[Region] = _sorted(BodyProjector.project(unit, Vector2(0, 1)))
	var back_hit: Region = ShotPlane.resolve_projectile(back, aim_point)
	assert_true(
		back_hit.part.id == &"torso_plate_rear" or back_hit.part.id == &"torso",
		"flanking must reach the thin rear plate or bare torso, got %s" % back_hit.part.id
	)


func test_ammo_rack_is_occluded_from_the_front_but_frontmost_from_behind() -> void:
	var unit := _reference_unit()

	var front: Array[Region] = BodyProjector.project(unit, Vector2(0, -1))
	var front_rack: Region = _find(front, &"ammo_rack")
	var min_front_depth := INF
	for region: Region in front:
		min_front_depth = minf(min_front_depth, region.depth)
	assert_true(
		front_rack.depth > min_front_depth, "the rack must not be frontmost viewed from the front"
	)

	var back: Array[Region] = BodyProjector.project(unit, Vector2(0, 1))
	var back_rack: Region = _find(back, &"ammo_rack")
	var min_back_depth := INF
	for region: Region in back:
		min_back_depth = minf(min_back_depth, region.depth)
	assert_almost_eq(
		back_rack.depth, min_back_depth, 0.0001, "the rack must be frontmost viewed from behind"
	)


func test_half_cover_masks_the_legs_but_not_the_head() -> void:
	var shooter_cell := Vector2i(5, 0)
	var cover_cell := Vector2i(5, 3)
	var target_cell := Vector2i(5, 6)

	var cover := Part.new()
	cover.id = &"half_cover"
	cover.is_destructible = false
	cover.material = &"hull_plate"
	cover.volume = [
		Box.new(
			Vector3(0.0, MapGen.HALF_COVER_HEIGHT * 0.5, 0.0),
			Vector3(MapGen.COVER_FOOTPRINT, MapGen.HALF_COVER_HEIGHT, MapGen.COVER_FOOTPRINT)
		)
	]

	var grid := Grid.new(12, 12)
	grid.blockers[cover_cell] = cover
	var unit := _reference_unit(target_cell)
	var state := CombatState.new(grid, [unit])

	var origin := Vector2(shooter_cell.x, shooter_cell.y)
	var direction := Vector2(target_cell - shooter_cell).normalized()
	var plane: Array[Region] = ShotPlane.build(origin, direction, state)

	print("\n=== half cover: masks legs, not the head ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 4))

	var leg_region: Region = _find(plane, &"leg")
	var leg_point: Vector2 = leg_region.rect.get_center()
	var leg_hit: Region = ShotPlane.resolve_projectile(plane, leg_point)
	assert_eq(leg_hit.part.id, &"half_cover", "half cover must mask the legs")

	var head_region: Region = _find(plane, &"head")
	var head_point: Vector2 = head_region.rect.get_center()
	var head_hit: Region = ShotPlane.resolve_projectile(plane, head_point)
	assert_eq(head_hit.part.id, &"head", "half cover must not reach high enough to mask the head")


func test_destroying_a_plate_leaves_the_part_behind_bare_on_the_next_shot() -> void:
	var unit := _reference_unit()
	var plate: Part = unit.shell.find_part(&"torso_plate_front")

	var before: Array[Region] = _sorted(BodyProjector.project(unit, Vector2(0, -1)))
	var aim_point: Vector2 = _find(before, &"torso_plate_front").rect.get_center()
	assert_eq(ShotPlane.resolve_projectile(before, aim_point).part.id, &"torso_plate_front")

	plate.hp = 0
	var after: Array[Region] = _sorted(BodyProjector.project(unit, Vector2(0, -1)))
	for region: Region in after:
		assert_ne(region.part.id, &"torso_plate_front", "a destroyed plate must leave the plane")
	assert_eq(
		ShotPlane.resolve_projectile(after, aim_point).part.id,
		&"torso",
		"the same point must now resolve to the bare torso behind it"
	)


func test_no_pool_part_has_an_empty_material() -> void:
	for template: Part in DeepStrike.default_part_pool():
		assert_ne(template.material, &"", "%s must carry a real material (docs/10)" % template.id)


func test_the_pool_yields_at_least_three_distinct_colors() -> void:
	var table := MaterialTable.default_table()
	var colors: Array[Color] = []
	for template: Part in DeepStrike.default_part_pool():
		var color: Color = table.color_for(template.material)
		if not colors.has(color):
			colors.append(color)
	assert_true(colors.size() >= 3, "the pool must read as more than one or two flat colors")


func test_validate_assembly_flags_an_empty_material_same_as_a_missing_volume() -> void:
	var unit := _reference_unit()
	var torso: Part = unit.shell.root
	torso.material = &""

	var violations: Array[String] = DeepStrike.validate_assembly(unit)
	var found := false
	for violation: String in violations:
		if violation.contains("material"):
			found = true
	assert_true(found, "an empty material must be a validate_assembly violation: %s" % violations)
