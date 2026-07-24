extends GutTest

## taskblock-38 Pass D: the ONE seam every legacy terrain/level fallback
## routes through — instrumented so the follow-up retirement block can
## work from a real burn-down list instead of a guess.


func before_each() -> void:
	GridLegacyBridge.reset()


func test_is_legacy_true_for_a_grid_with_no_surfaces_anywhere() -> void:
	var grid := Grid.new(3, 3)
	assert_true(GridLegacyBridge.is_legacy(grid))


func test_is_legacy_false_once_any_surface_exists() -> void:
	var grid := Grid.new(3, 3)
	GridPlacement.place(grid, Vector2i(0, 0), DataLibrary.get_part(&"ship_floor"), 0.0)
	assert_false(GridLegacyBridge.is_legacy(grid))


func test_reset_clears_accumulated_hits() -> void:
	GridLegacyBridge.terrain_cost(Grid.new(1, 1), Vector2i(0, 0), {}, 1.0, "test_caller")
	assert_eq(GridLegacyBridge.total_hits(), 1)
	GridLegacyBridge.reset()
	assert_eq(GridLegacyBridge.total_hits(), 0)
	assert_eq(GridLegacyBridge.hit_counts(), {})


func test_hits_are_tallied_per_caller() -> void:
	var grid := Grid.new(1, 1)
	GridLegacyBridge.terrain_cost(grid, Vector2i(0, 0), {}, 1.0, "caller_a")
	GridLegacyBridge.terrain_cost(grid, Vector2i(0, 0), {}, 1.0, "caller_a")
	GridLegacyBridge.height_for_cell(grid, Vector2i(0, 0), "caller_b")

	var counts: Dictionary = GridLegacyBridge.hit_counts()
	assert_eq(counts["caller_a"], 2)
	assert_eq(counts["caller_b"], 1)
	assert_eq(GridLegacyBridge.total_hits(), 3)


func test_terrain_cost_matches_the_pre_placement_formula() -> void:
	var grid := Grid.new(3, 3)
	grid.set_terrain(Vector2i(1, 1), 7)
	assert_almost_eq(
		GridLegacyBridge.terrain_cost(grid, Vector2i(1, 1), {7: 5.0}, 1.0, "c"), 5.0, 0.0001
	)
	assert_almost_eq(
		GridLegacyBridge.terrain_cost(grid, Vector2i(1, 1), {7: -1.0}, 1.0, "c"), -1.0, 0.0001
	)
	assert_almost_eq(
		GridLegacyBridge.terrain_cost(grid, Vector2i(2, 2), {7: 5.0}, 1.0, "c"), 1.0, 0.0001
	)


func test_move_cost_matches_the_pre_placement_ramp_and_climb_formula() -> void:
	var grid := Grid.new(2, 1)
	grid.set_terrain(Vector2i(1, 0), Enums.TerrainType.RAMP)
	grid.set_level(Vector2i(1, 0), 1)
	assert_almost_eq(
		GridLegacyBridge.move_cost(grid, Vector2i(0, 0), Vector2i(1, 0), 1.0, false, "c"),
		1.0,
		0.0001,
		"a ramp edge is ordinary movement, no climb capability needed"
	)

	var ledge_grid := Grid.new(2, 1)
	ledge_grid.set_level(Vector2i(1, 0), 1)
	assert_almost_eq(
		GridLegacyBridge.move_cost(ledge_grid, Vector2i(0, 0), Vector2i(1, 0), 1.0, true, "c"),
		Pathfinder.CLIMB_COST,
		0.0001
	)
	assert_almost_eq(
		GridLegacyBridge.move_cost(ledge_grid, Vector2i(0, 0), Vector2i(1, 0), 1.0, false, "c"),
		-1.0,
		0.0001,
		"a non-climber has no edge over an un-ramped ledge"
	)


func test_height_for_cell_matches_the_pre_placement_formula() -> void:
	var grid := Grid.new(3, 3)
	grid.set_level(Vector2i(1, 1), 2)
	assert_almost_eq(
		GridLegacyBridge.height_for_cell(grid, Vector2i(1, 1), "c"),
		2.0 * UnitGeometry.LEVEL_HEIGHT,
		0.0001
	)

	grid.set_terrain(Vector2i(1, 1), Enums.TerrainType.RAMP)
	assert_almost_eq(
		GridLegacyBridge.height_for_cell(grid, Vector2i(1, 1), "c"),
		2.0 * UnitGeometry.LEVEL_HEIGHT + UnitGeometry.LEVEL_HEIGHT * 0.5,
		0.0001,
		"the pre-Pass-C flat +0.5 ramp offset, untouched"
	)


func test_pathfinder_routes_legacy_hits_through_the_bridge_with_its_own_caller() -> void:
	var grid := Grid.new(2, 1)
	var pf := Pathfinder.new(grid)
	pf.move_cost(Vector2i(0, 0), Vector2i(1, 0))

	var counts: Dictionary = GridLegacyBridge.hit_counts()
	assert_true(counts.has("Pathfinder._base_cost"))
	assert_true(counts.has("Pathfinder.move_cost"))


func test_unit_geometry_routes_legacy_hits_through_the_bridge_with_its_own_caller() -> void:
	var grid := Grid.new(2, 1)
	UnitGeometry.true_height_for_cell(Vector2i(0, 0), grid)

	assert_true(GridLegacyBridge.hit_counts().has("UnitGeometry.true_height_for_cell"))
