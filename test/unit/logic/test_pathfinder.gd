extends GutTest

const TERRAIN_OPEN := 0
const TERRAIN_WALL := 1
const TERRAIN_DIFFICULT := 2


func _sum_path_cost(pf: Pathfinder, path: Array[Vector2i]) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += pf.move_cost(path[i])
	return total


func test_astar_straight_line_uniform_cost() -> void:
	var grid := Grid.new(5, 5)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(path, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)])
	assert_almost_eq(_sum_path_cost(pf, path), 4.0, 0.0001)


func test_astar_path_length_with_mixed_terrain_cost() -> void:
	# 1-row corridor forces the path straight through a costly cell — no detour possible.
	var grid := Grid.new(5, 1)
	grid.set_terrain(Vector2i(2, 0), TERRAIN_DIFFICULT)
	var pf := Pathfinder.new(grid, {TERRAIN_DIFFICULT: 5.0})
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(path, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)])
	# 1 (into x=1) + 5 (into difficult x=2) + 1 + 1 = 8
	assert_almost_eq(_sum_path_cost(pf, path), 8.0, 0.0001)


func test_astar_routes_around_single_blocked_cell() -> void:
	var grid := Grid.new(5, 5)
	grid.set_terrain(Vector2i(2, 2), TERRAIN_WALL)
	var pf := Pathfinder.new(grid, {TERRAIN_WALL: -1.0})
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 2), Vector2i(4, 2))
	assert_true(path.size() > 0, "a path should exist around the single obstacle")
	assert_does_not_have(path, Vector2i(2, 2))
	assert_eq(path[0], Vector2i(0, 2))
	assert_eq(path[path.size() - 1], Vector2i(4, 2))
	# Diagonal movement lets the detour cost the same as the straight 4-step path.
	assert_almost_eq(_sum_path_cost(pf, path), 4.0, 0.0001)


func test_astar_returns_empty_when_unreachable() -> void:
	var grid := Grid.new(3, 3)
	for y in range(3):
		grid.set_terrain(Vector2i(1, y), TERRAIN_WALL)
	var pf := Pathfinder.new(grid, {TERRAIN_WALL: -1.0})
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 1), Vector2i(2, 1))
	assert_eq(path, [] as Array[Vector2i])


func test_astar_same_cell_returns_single_cell_path() -> void:
	var grid := Grid.new(3, 3)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(1, 1), Vector2i(1, 1))
	assert_eq(path, [Vector2i(1, 1)])


func test_astar_succeeds_when_origin_cell_is_occupied_by_the_mover_itself() -> void:
	# The walking unit always occupies its own starting cell — that must never
	# block pathing away from it (regression: this broke real AI movement).
	var grid := Grid.new(5, 5)
	grid.set_occupant_id(Vector2i(0, 0), 7)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(path, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)])


func test_astar_rejects_occupied_destination() -> void:
	var grid := Grid.new(5, 5)
	grid.set_occupant_id(Vector2i(4, 0), 9)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(path, [] as Array[Vector2i])


func test_reachable_respects_mp_budget_exactly() -> void:
	var grid := Grid.new(5, 1)
	grid.set_terrain(Vector2i(2, 0), TERRAIN_DIFFICULT)
	var pf := Pathfinder.new(grid, {TERRAIN_DIFFICULT: 5.0})

	var r1: Array[Vector2i] = pf.reachable(Vector2i(0, 0), 2.0)
	assert_eq(r1, [Vector2i(0, 0), Vector2i(1, 0)])

	# Exact-budget boundary: cost to (1,0) is exactly 1.0, so mp=1.0 must include it.
	var r2: Array[Vector2i] = pf.reachable(Vector2i(0, 0), 1.0)
	assert_eq(r2, [Vector2i(0, 0), Vector2i(1, 0)])

	# Just under budget excludes it.
	var r3: Array[Vector2i] = pf.reachable(Vector2i(0, 0), 0.999)
	assert_eq(r3, [Vector2i(0, 0)])


func test_reachable_excludes_blocked_cells() -> void:
	var grid := Grid.new(5, 5)
	grid.set_terrain(Vector2i(1, 2), TERRAIN_WALL)
	var pf := Pathfinder.new(grid, {TERRAIN_WALL: -1.0})
	var r: Array[Vector2i] = pf.reachable(Vector2i(0, 2), 10.0)
	assert_does_not_have(r, Vector2i(1, 2))


func test_reachable_includes_origin_at_zero_cost() -> void:
	var grid := Grid.new(3, 3)
	var pf := Pathfinder.new(grid)
	var r: Array[Vector2i] = pf.reachable(Vector2i(1, 1), 0.0)
	assert_eq(r, [Vector2i(1, 1)])


func test_move_cost_treats_occupied_cell_as_blocked() -> void:
	var grid := Grid.new(3, 3)
	grid.set_occupant_id(Vector2i(1, 1), 42)
	var pf := Pathfinder.new(grid)
	assert_eq(pf.move_cost(Vector2i(1, 1)), -1.0)
	assert_false(pf.is_walkable(Vector2i(1, 1)))
