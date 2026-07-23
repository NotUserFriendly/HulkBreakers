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
	assert_eq(
		path, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	)
	assert_almost_eq(_sum_path_cost(pf, path), 4.0, 0.0001)


## taskblock-36 Pass D: "Pathfinder produces identical paths whether or not
## levels are set — it genuinely ignores them this pass." Cells along and
## beside the straight-line path are given a real, varied elevation; the
## resolved path and its cost must not move.
func test_astar_ignores_cell_level_entirely() -> void:
	var grid := Grid.new(5, 5)
	var pf := Pathfinder.new(grid)
	var baseline: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))

	for y in range(grid.rows):
		for x in range(grid.width):
			grid.set_level(Vector2i(x, y), (x + y) % 3)

	var with_levels: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(with_levels, baseline, "a real, varied level must not change the resolved path")
	assert_almost_eq(_sum_path_cost(pf, with_levels), _sum_path_cost(pf, baseline), 0.0001)


func test_astar_path_length_with_mixed_terrain_cost() -> void:
	# 1-row corridor forces the path straight through a costly cell — no detour possible.
	var grid := Grid.new(5, 1)
	grid.set_terrain(Vector2i(2, 0), TERRAIN_DIFFICULT)
	var pf := Pathfinder.new(grid, {TERRAIN_DIFFICULT: 5.0})
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(
		path, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	)
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


func _direction_changes(path: Array[Vector2i]) -> int:
	var changes := 0
	for i in range(2, path.size()):
		if path[i - 1] - path[i - 2] != path[i] - path[i - 1]:
			changes += 1
	return changes


## docs/10 taskblock04 B: a per-cell MP cost plus a Chebyshev heuristic ties
## every ordering of the same step multiset — without a tie-break, the open
## set returns whichever ordering it happens to pop first. This is the
## reproduced case: the untouched frontier order sends the path diagonally
## PAST the destination's own column and back (2 turns); tie-broken on
## fewest direction changes, it goes diagonal-then-straight instead (1).
func test_astar_prefers_the_smoother_of_two_equal_cost_paths() -> void:
	var grid := Grid.new(15, 15)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(3, 8))

	assert_almost_eq(_sum_path_cost(pf, path), 8.0, 0.0001, "B1: cost must not change by a point")
	assert_eq(_direction_changes(path), 1, "the smoothest available equal-cost path")


## "No fractional MP, no irrational costs... this is cosmetic only: the
## path's MP cost must not change by one point" — asserted hard, across a
## corpus, not just the one case the tie-break was built to fix.
func test_astar_total_cost_is_unchanged_across_a_corpus_of_open_ground_paths() -> void:
	var grid := Grid.new(15, 15)
	var pf := Pathfinder.new(grid)
	var origin := Vector2i(0, 0)
	var destinations: Array[Vector2i] = [
		Vector2i(8, 3),
		Vector2i(3, 8),
		Vector2i(10, 4),
		Vector2i(4, 10),
		Vector2i(7, 2),
		Vector2i(2, 7),
		Vector2i(12, 12),
		Vector2i(1, 5),
	]
	for destination: Vector2i in destinations:
		var path: Array[Vector2i] = pf.astar(origin, destination)
		var expected_cost: float = float(Grid.distance_chebyshev(origin, destination))
		assert_almost_eq(
			_sum_path_cost(pf, path),
			expected_cost,
			0.0001,
			"cost to %s must equal the Chebyshev distance on open ground" % [destination]
		)


## A straight line has no diagonal shortcut to prefer over — the tie-break
## must never invent a detour where the direct path was already the unique
## shortest one.
func test_astar_with_no_diagonal_shortcut_is_unchanged() -> void:
	var grid := Grid.new(5, 5)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(
		path, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	)


func test_astar_is_deterministic() -> void:
	var grid := Grid.new(15, 15)
	var pf := Pathfinder.new(grid)
	var a: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(3, 8))
	var b: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(3, 8))
	assert_eq(a, b)


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
	assert_eq(
		path, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	)


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


## taskblock-16 Pass B1: "they occupy their cell -> block movement" — a
## cover object in `Grid.blockers` must block a cell exactly like an
## occupant does, not just render there.
func test_move_cost_treats_a_field_object_cell_as_blocked() -> void:
	var grid := Grid.new(3, 3)
	var crate := Part.new()
	crate.id = &"crate"
	grid.blockers[Vector2i(1, 1)] = crate
	var pf := Pathfinder.new(grid)
	assert_eq(pf.move_cost(Vector2i(1, 1)), -1.0)
	assert_false(pf.is_walkable(Vector2i(1, 1)))


## tb31 Pass C: a DESTROYED blocker must clear to fully passable — before
## this, a dead crate (or a destroyed wall, once walls became destructible
## cover) still walled off its own tile forever, since `move_cost` only
## ever checked whether `blockers` HAD an entry, never its `hp`.
## `ShotPlane`/`BodyProjector` already skip a 0-hp Part; this is the other
## half of the same fix.
func test_move_cost_treats_a_destroyed_field_object_as_passable() -> void:
	var grid := Grid.new(3, 3)
	var crate := Part.new()
	crate.id = &"crate"
	crate.hp = 0
	grid.blockers[Vector2i(1, 1)] = crate
	var pf := Pathfinder.new(grid)
	assert_true(pf.is_walkable(Vector2i(1, 1)), "a destroyed blocker must no longer block movement")
	assert_eq(pf.move_cost(Vector2i(1, 1)), Pathfinder.DEFAULT_COST)


## tb31 Pass C: VOID is non-navigable exactly like WALL always has been —
## `CombatState.terrain_costs`'s own default maps both to -1.0; this pins
## the terrain type itself against a Pathfinder built with that mapping,
## independent of whichever CombatState happens to own it.
func test_void_terrain_is_impassable() -> void:
	var grid := Grid.new(3, 3)
	grid.set_terrain(Vector2i(1, 1), Enums.TerrainType.VOID)
	var pf := Pathfinder.new(grid, {Enums.TerrainType.VOID: -1.0})
	assert_false(pf.is_walkable(Vector2i(1, 1)))


## tb31 Pass C: a wall (real data, `DataLibrary.get_part(&"wall")`) blocks
## movement exactly like any other living blocker while intact, and clears
## once destroyed — the shared fix applies to it the same as scatter cover.
func test_an_intact_wall_blocks_movement_a_destroyed_one_does_not() -> void:
	var grid := Grid.new(3, 3)
	var wall: Part = DataLibrary.get_part(&"wall")
	grid.blockers[Vector2i(1, 1)] = wall
	var pf := Pathfinder.new(grid)
	assert_false(pf.is_walkable(Vector2i(1, 1)), "an intact wall must block movement")

	wall.hp = 0

	assert_true(pf.is_walkable(Vector2i(1, 1)), "a destroyed wall must clear to passable")


func test_astar_routes_around_a_field_object() -> void:
	var grid := Grid.new(3, 3)
	var crate := Part.new()
	crate.id = &"crate"
	grid.blockers[Vector2i(1, 1)] = crate
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 1), Vector2i(2, 1))
	assert_does_not_have(path, Vector2i(1, 1), "the path must detour around the blocked cell")
	assert_eq(path[0], Vector2i(0, 1))
	assert_eq(path[-1], Vector2i(2, 1))


## tb33 Pass B (BR32.10): `nearest_matching` must return the genuinely
## NEAREST cell satisfying `stop_at`, by path cost — not merely the first one
## discovered by insertion order. A straight corridor with a costly detour
## cell in between (matching, but farther by path cost) versus a plain cell
## past it (also matching, cheaper to reach) proves the Dijkstra-pop-order
## claim, not just "found something."
func test_nearest_matching_returns_the_nearest_match_by_path_cost_not_discovery_order() -> void:
	var grid := Grid.new(6, 1)
	var pf := Pathfinder.new(grid)
	var matches: Array[Vector2i] = [Vector2i(4, 0), Vector2i(1, 0)]
	var found: Variant = pf.nearest_matching(
		Vector2i(0, 0), 10.0, func(cell: Vector2i) -> bool: return matches.has(cell)
	)
	assert_eq(found, Vector2i(1, 0), "the nearer match must win even if discovered later")


func test_nearest_matching_respects_the_radius_cap() -> void:
	var grid := Grid.new(10, 1)
	var pf := Pathfinder.new(grid)
	var found: Variant = pf.nearest_matching(
		Vector2i(0, 0), 3.0, func(cell: Vector2i) -> bool: return cell == Vector2i(9, 0)
	)
	assert_null(found, "a match outside the radius cap must not be found")


func test_nearest_matching_returns_null_when_nothing_matches() -> void:
	var grid := Grid.new(5, 1)
	var pf := Pathfinder.new(grid)
	var found: Variant = pf.nearest_matching(
		Vector2i(0, 0), 10.0, func(cell: Vector2i) -> bool: return false
	)
	assert_null(found)


func test_nearest_matching_never_crosses_a_blocked_cell() -> void:
	var grid := Grid.new(5, 1)
	grid.set_terrain(Vector2i(2, 0), TERRAIN_WALL)
	var pf := Pathfinder.new(grid, {TERRAIN_WALL: -1.0})
	var found: Variant = pf.nearest_matching(
		Vector2i(0, 0), 10.0, func(cell: Vector2i) -> bool: return cell == Vector2i(4, 0)
	)
	assert_null(found, "a 1-row corridor with no way around a wall must never reach past it")


func test_truncate_to_budget_stops_at_the_affordable_prefix() -> void:
	var grid := Grid.new(5, 1)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)
	]
	var truncated: Array[Vector2i] = pf.truncate_to_budget(path, 2.0)
	assert_eq(truncated, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])


func test_truncate_to_budget_stops_before_a_cell_it_cannot_afford_even_partially() -> void:
	var grid := Grid.new(5, 1)
	grid.set_terrain(Vector2i(2, 0), TERRAIN_DIFFICULT)
	var pf := Pathfinder.new(grid, {TERRAIN_DIFFICULT: 5.0})
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var truncated: Array[Vector2i] = pf.truncate_to_budget(path, 4.0)
	assert_eq(
		truncated,
		[Vector2i(0, 0), Vector2i(1, 0)],
		"the expensive cell can't be afforded, even though 4.0 MP remains"
	)


func test_truncate_to_budget_on_an_empty_path_returns_empty() -> void:
	var grid := Grid.new(3, 1)
	var pf := Pathfinder.new(grid)
	assert_eq(pf.truncate_to_budget([], 5.0), [] as Array[Vector2i])
