extends GutTest


func _open_grid(size: int) -> Grid:
	return Grid.new(size, size)


func _set_terrain_cover(grid: Grid, cell: Vector2i, value: float) -> Part:
	grid.set_cover_value(cell, value)
	var part := Part.new()
	part.id = &"terrain_cover"
	part.is_destructible = false
	grid.blockers[cell] = part
	return part


func _set_destructible_cover(grid: Grid, cell: Vector2i, value: float, hp: int) -> Part:
	grid.set_cover_value(cell, value)
	var part := Part.new()
	part.id = &"crate"
	part.is_destructible = true
	part.hp = hp
	part.max_hp = hp
	grid.blockers[cell] = part
	return part


func test_no_cover_on_open_ground() -> void:
	var grid := _open_grid(7)
	var info: CoverInfo = Cover.between(grid, Vector2i(0, 3), Vector2i(6, 3))
	assert_eq(info.level, CoverInfo.Level.NONE)
	assert_eq(info.profile, [] as Array[Enums.SlotType])
	assert_null(info.object)


func test_half_cover_profile_is_legs_only() -> void:
	var grid := _open_grid(7)
	var cover_part: Part = _set_terrain_cover(grid, Vector2i(3, 3), 0.5)
	var info: CoverInfo = Cover.between(grid, Vector2i(0, 3), Vector2i(4, 3))
	assert_eq(info.level, CoverInfo.Level.HALF)
	assert_eq(info.profile, [Enums.SlotType.LEGS])
	assert_eq(info.object, cover_part)


func test_full_cover_profile_is_all_slots() -> void:
	var grid := _open_grid(7)
	var cover_part: Part = _set_terrain_cover(grid, Vector2i(3, 3), 1.0)
	var info: CoverInfo = Cover.between(grid, Vector2i(0, 3), Vector2i(4, 3))
	assert_eq(info.level, CoverInfo.Level.FULL)
	assert_eq(info.profile.size(), 6)
	assert_has(info.profile, Enums.SlotType.HEAD)
	assert_has(info.profile, Enums.SlotType.TORSO)
	assert_has(info.profile, Enums.SlotType.CORE)
	assert_has(info.profile, Enums.SlotType.L_ARM)
	assert_has(info.profile, Enums.SlotType.R_ARM)
	assert_has(info.profile, Enums.SlotType.LEGS)
	assert_eq(info.object, cover_part)


func test_terrain_cover_is_not_destructible() -> void:
	var grid := _open_grid(7)
	_set_terrain_cover(grid, Vector2i(3, 3), 1.0)
	var info: CoverInfo = Cover.between(grid, Vector2i(0, 3), Vector2i(4, 3))
	assert_false(info.object.is_destructible)


func test_destructible_cover_object_is_flagged() -> void:
	var grid := _open_grid(7)
	_set_destructible_cover(grid, Vector2i(3, 3), 1.0, 5)
	var info: CoverInfo = Cover.between(grid, Vector2i(0, 3), Vector2i(4, 3))
	assert_true(info.object.is_destructible)
	assert_eq(info.object.hp, 5)


func test_destroying_destructible_cover_downgrades_level_and_empties_profile() -> void:
	var grid := _open_grid(7)
	_set_destructible_cover(grid, Vector2i(3, 3), 1.0, 5)

	Cover.apply_damage_to_object(grid, Vector2i(3, 3), 3)
	var mid_info: CoverInfo = Cover.between(grid, Vector2i(0, 3), Vector2i(4, 3))
	assert_eq(mid_info.level, CoverInfo.Level.FULL, "still standing at hp 2")

	Cover.apply_damage_to_object(grid, Vector2i(3, 3), 2)
	var final_info: CoverInfo = Cover.between(grid, Vector2i(0, 3), Vector2i(4, 3))
	assert_eq(final_info.level, CoverInfo.Level.NONE)
	assert_eq(final_info.profile, [] as Array[Enums.SlotType])
	assert_null(final_info.object)
	assert_false(grid.blockers.has(Vector2i(3, 3)))


func test_terrain_cover_never_downgrades() -> void:
	var grid := _open_grid(7)
	_set_terrain_cover(grid, Vector2i(3, 3), 1.0)

	Cover.apply_damage_to_object(grid, Vector2i(3, 3), 9999)

	var info: CoverInfo = Cover.between(grid, Vector2i(0, 3), Vector2i(4, 3))
	assert_eq(info.level, CoverInfo.Level.FULL)
	assert_true(grid.blockers.has(Vector2i(3, 3)))


func test_slot_not_in_profile_is_unaffected_by_cover() -> void:
	# HALF cover only protects LEGS — this is exercised fully by Targeting in
	# Phase 8, but Phase 6 just needs the profile to be exactly [LEGS].
	var grid := _open_grid(7)
	_set_terrain_cover(grid, Vector2i(3, 3), 0.5)
	var info: CoverInfo = Cover.between(grid, Vector2i(0, 3), Vector2i(4, 3))
	assert_does_not_have(info.profile, Enums.SlotType.TORSO)
	assert_does_not_have(info.profile, Enums.SlotType.HEAD)


func test_attackers_own_cell_is_never_treated_as_cover() -> void:
	var grid := _open_grid(7)
	# Even if the attacker's own cell happens to carry a cover value, it must
	# never leak into the target's cover when the attacker is adjacent.
	_set_terrain_cover(grid, Vector2i(3, 3), 1.0)
	var info: CoverInfo = Cover.between(grid, Vector2i(3, 3), Vector2i(4, 3))
	assert_eq(info.level, CoverInfo.Level.NONE)


func test_corner_crossing_picks_strongest_bordering_cover() -> void:
	# Grid.line(0,0 -> 2,2) borders the corner with (2,1) and (1,2).
	var grid := _open_grid(5)
	_set_terrain_cover(grid, Vector2i(2, 1), 0.5)
	var info: CoverInfo = Cover.between(grid, Vector2i(0, 0), Vector2i(2, 2))
	assert_eq(info.level, CoverInfo.Level.HALF)


func test_corner_crossing_prefers_full_over_half() -> void:
	var grid := _open_grid(5)
	_set_terrain_cover(grid, Vector2i(2, 1), 0.5)
	_set_terrain_cover(grid, Vector2i(1, 2), 1.0)
	var info: CoverInfo = Cover.between(grid, Vector2i(0, 0), Vector2i(2, 2))
	assert_eq(info.level, CoverInfo.Level.FULL)


func test_same_cell_returns_no_cover() -> void:
	var grid := _open_grid(5)
	var info: CoverInfo = Cover.between(grid, Vector2i(2, 2), Vector2i(2, 2))
	assert_eq(info.level, CoverInfo.Level.NONE)
