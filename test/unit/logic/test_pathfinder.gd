extends GutTest


func _sum_path_cost(pf: Pathfinder, path: Array[Vector2i]) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += pf.move_cost(path[i - 1], path[i])
	return total


func test_astar_straight_line_uniform_cost() -> void:
	var grid := GridFixture.flat(5, 5)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(
		path, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	)
	assert_almost_eq(_sum_path_cost(pf, path), 4.0, 0.0001)


## taskblock-36 Pass D's own acceptance test claimed "Pathfinder produces
## identical paths whether or not levels are set — it genuinely ignores
## them this pass." taskblock-37 Pass C deliberately makes that false:
## level-blindness was the gap this pass exists to close, so the old test
## (a real, VARIED elevation across the whole grid) is replaced by the two
## things that must both hold now instead — a UNIFORM level shift (no cell
## ever differs from its neighbor) still carries no cost anywhere, since
## every real edge sees a zero delta; a genuinely varied level, by
## contrast, is covered by the dedicated climb/hop/ramp tests below, which
## prove the pathfinder now REACTS to it rather than ignoring it.
func test_astar_is_unaffected_by_a_uniform_level_shift() -> void:
	var grid := GridFixture.flat(5, 5)
	var pf := Pathfinder.new(grid)
	var baseline: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))

	for y in range(grid.rows):
		for x in range(grid.width):
			# every cell raised together -- no edge ever tilts
			GridFixture.place_floor(grid, Vector2i(x, y), 3)

	var uniformly_raised: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(uniformly_raised, baseline, "a uniform raise carries no level DELTA anywhere")
	assert_almost_eq(_sum_path_cost(pf, uniformly_raised), _sum_path_cost(pf, baseline), 0.0001)


## taskblock-37 Pass C: the direct replacement for what tb36's acceptance
## test used to claim — a genuinely varied level (a real, unramped ledge
## with no alternate route at all, a 2x1 grid leaves no row to detour
## through) now removes a non-climbing mover's only path entirely, proof
## that level is no longer ignored.
func test_astar_now_reacts_to_a_genuine_ledge() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var pf := Pathfinder.new(grid)  # default: cannot climb

	assert_eq(pf.astar(Vector2i(0, 0), Vector2i(1, 0)), [] as Array[Vector2i])


## taskblock-37 Pass C: "climbing is capability-gated, and it is a real
## graph edge when present" (docs/PLAN.md) — a climb-capable unit gets the
## edge at its real, settled cost.
func test_climb_capable_unit_routes_over_a_1_level_ledge_at_4_mp() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var pf := Pathfinder.new(grid, true)

	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(1, 0))

	assert_eq(path, [Vector2i(0, 0), Vector2i(1, 0)])
	assert_almost_eq(_sum_path_cost(pf, path), Pathfinder.CLIMB_COST, 0.0001)


## "A unit that genuinely can't reach a target is correct behaviour, not
## stranding" — no fallback that lets a non-climber climb anyway; an empty
## path, not an illegal one.
func test_non_climb_capable_unit_has_no_path_over_a_ledge() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var pf := Pathfinder.new(grid)  # default: cannot climb

	assert_eq(pf.astar(Vector2i(0, 0), Vector2i(1, 0)), [] as Array[Vector2i])


## "The weighting resolves itself; don't add heuristics" — a climb-capable
## unit still takes a cheaper stair-mediated route over paying to climb a
## ledge directly, with no tiebreaker needed beyond real edge costs. Reads
## the actual resolved path's own cost back rather than hand-picking an
## expected route: 8-directional movement can find a cheaper way through a
## stair tread than the route this test set out to build — asserting the
## real number is honest about that, asserting a specific path array would
## not be.
##
## tb60 Pass A: the detour is a real STAIR now (treads at 0.25/0.5/0.75,
## each step within the default 0.3 step height) rather than three cells
## labelled `ramp`. The route is cheaper for a reason the pathfinder can
## see in the heights, not because of a tag.
func test_climb_capable_unit_prefers_a_cheaper_stair_route_over_climbing() -> void:
	var grid := GridFixture.flat(3, 2)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)  # the ledge -- a direct climb, no stair
	GridFixture.place_floor(grid, Vector2i(2, 0), 1)  # target, already level 1 past the ledge
	# The stair: three treads at 0.25/0.5/0.75, every step inside the default 0.3.
	GridFixture.place_floor(grid, Vector2i(0, 1), 0.25)
	GridFixture.place_floor(grid, Vector2i(1, 1), 0.5)
	GridFixture.place_floor(grid, Vector2i(2, 1), 0.75)
	var pf := Pathfinder.new(grid, true)

	var direct_climb_cost: float = (
		pf.move_cost(Vector2i(0, 0), Vector2i(1, 0)) + pf.move_cost(Vector2i(1, 0), Vector2i(2, 0))
	)
	assert_almost_eq(direct_climb_cost, 5.0, 0.0001, "sanity: the direct climb route costs 5 MP")

	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(2, 0))
	assert_lt(
		_sum_path_cost(pf, path),
		direct_climb_cost,
		"a climb-capable unit still finds something cheaper than climbing the ledge directly"
	)


## tb60 Pass A: **a step within the step height costs 1 MP and changes height** — the
## replacement for "a ramp cell costs 1 MP", and the same guarantee stated about geometry
## instead of about a label. No climb capability needed at all, and the cell's own real
## height genuinely changes underneath the ordinary cost.
func test_a_step_within_step_height_costs_1_mp_and_changes_height() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), Unit.BASE_STEP_HEIGHT)
	var pf := Pathfinder.new(grid)  # no climb capability -- a short step is ordinary movement

	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(1, 0))

	assert_eq(path, [Vector2i(0, 0), Vector2i(1, 0)])
	assert_almost_eq(_sum_path_cost(pf, path), Pathfinder.DEFAULT_COST, 0.0001)
	assert_almost_eq(
		UnitGeometry.true_height_for_cell(Vector2i(1, 0), grid),
		Unit.BASE_STEP_HEIGHT * UnitGeometry.LEVEL_HEIGHT,
		0.0001,
		"the cell's own height genuinely changes"
	)


## "Hop-down is a path edge too — 1 MP, valid for a drop of up to 2
## levels" — legal for every mover, no capability gate at all.
func test_a_2_level_drop_is_a_legal_1_mp_edge() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(0, 0), 2)
	var pf := Pathfinder.new(grid)  # hop-down needs no capability

	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(1, 0))

	assert_eq(path, [Vector2i(0, 0), Vector2i(1, 0)])
	assert_almost_eq(_sum_path_cost(pf, path), Pathfinder.HOP_DOWN_COST, 0.0001)


## "Deeper drops don't exist yet. A drop past 2 levels is simply not a
## legal edge this pass" — not free, not modeled, just absent.
func test_a_3_level_drop_is_not_a_legal_edge() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(0, 0), 3)
	var pf := Pathfinder.new(grid)

	assert_eq(pf.astar(Vector2i(0, 0), Vector2i(1, 0)), [] as Array[Vector2i])


func test_astar_routes_around_single_blocked_cell() -> void:
	var grid := GridFixture.flat(5, 5)
	GridFixture.place_wall(grid, Vector2i(2, 2))
	var pf := Pathfinder.new(grid)
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
	var grid := GridFixture.flat(15, 15)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(3, 8))

	assert_almost_eq(_sum_path_cost(pf, path), 8.0, 0.0001, "B1: cost must not change by a point")
	assert_eq(_direction_changes(path), 1, "the smoothest available equal-cost path")


## "No fractional MP, no irrational costs... this is cosmetic only: the
## path's MP cost must not change by one point" — asserted hard, across a
## corpus, not just the one case the tie-break was built to fix.
func test_astar_total_cost_is_unchanged_across_a_corpus_of_open_ground_paths() -> void:
	var grid := GridFixture.flat(15, 15)
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
	var grid := GridFixture.flat(5, 5)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(
		path, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	)


func test_astar_is_deterministic() -> void:
	var grid := GridFixture.flat(15, 15)
	var pf := Pathfinder.new(grid)
	var a: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(3, 8))
	var b: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(3, 8))
	assert_eq(a, b)


func test_astar_returns_empty_when_unreachable() -> void:
	var grid := GridFixture.flat(3, 3)
	for y in range(3):
		GridFixture.place_wall(grid, Vector2i(1, y))
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 1), Vector2i(2, 1))
	assert_eq(path, [] as Array[Vector2i])


func test_astar_same_cell_returns_single_cell_path() -> void:
	var grid := GridFixture.flat(3, 3)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(1, 1), Vector2i(1, 1))
	assert_eq(path, [Vector2i(1, 1)])


func test_astar_succeeds_when_origin_cell_is_occupied_by_the_mover_itself() -> void:
	# The walking unit always occupies its own starting cell — that must never
	# block pathing away from it (regression: this broke real AI movement).
	var grid := GridFixture.flat(5, 5)
	grid.set_occupant_id(Vector2i(0, 0), 7)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(
		path, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	)


func test_astar_rejects_occupied_destination() -> void:
	var grid := GridFixture.flat(5, 5)
	grid.set_occupant_id(Vector2i(4, 0), 9)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = pf.astar(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(path, [] as Array[Vector2i])


## taskblock-39 Pass C: budget-exactness no longer needs a variable-cost
## terrain to construct a non-1.0 edge — the terrain-cost-override
## mechanism this used (`{TERRAIN_DIFFICULT: 5.0}`) is retired outright
## (`Pathfinder`/`CombatState` no longer have any such dial at all; nothing
## in the placement model ever varied movement cost by cell, only by
## walkable/not). A climb-capable mover stepping onto a raised cell
## (`Pathfinder.CLIMB_COST`, not `DEFAULT_COST`) gives the same "some edge
## costs more than 1 MP" shape this test actually needs, without pinning
## the retired mechanism.
func test_reachable_respects_mp_budget_exactly() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var pf := Pathfinder.new(grid, true)  # climb-capable

	var r1: Array[Vector2i] = pf.reachable(Vector2i(0, 0), Pathfinder.CLIMB_COST + 1.0)
	assert_eq(r1, [Vector2i(0, 0), Vector2i(1, 0)])

	# Exact-budget boundary: cost onto (1,0) is exactly CLIMB_COST.
	var r2: Array[Vector2i] = pf.reachable(Vector2i(0, 0), Pathfinder.CLIMB_COST)
	assert_eq(r2, [Vector2i(0, 0), Vector2i(1, 0)])

	# Just under budget excludes it.
	var r3: Array[Vector2i] = pf.reachable(Vector2i(0, 0), Pathfinder.CLIMB_COST - 0.001)
	assert_eq(r3, [Vector2i(0, 0)])


func test_reachable_excludes_blocked_cells() -> void:
	var grid := GridFixture.flat(5, 5)
	GridFixture.place_wall(grid, Vector2i(1, 2))
	var pf := Pathfinder.new(grid)
	var r: Array[Vector2i] = pf.reachable(Vector2i(0, 2), 10.0)
	assert_does_not_have(r, Vector2i(1, 2))


func test_reachable_includes_origin_at_zero_cost() -> void:
	var grid := GridFixture.flat(3, 3)
	var pf := Pathfinder.new(grid)
	var r: Array[Vector2i] = pf.reachable(Vector2i(1, 1), 0.0)
	assert_eq(r, [Vector2i(1, 1)])


func test_move_cost_treats_occupied_cell_as_blocked() -> void:
	var grid := GridFixture.flat(3, 3)
	grid.set_occupant_id(Vector2i(1, 1), 42)
	var pf := Pathfinder.new(grid)
	assert_eq(pf.move_cost(Vector2i(0, 0), Vector2i(1, 1)), -1.0)
	assert_false(pf.is_walkable(Vector2i(1, 1)))


## taskblock-16 Pass B1: "they occupy their cell -> block movement" — a
## cover object in `Grid.blockers` must block a cell exactly like an
## occupant does, not just render there.
func test_move_cost_treats_a_field_object_cell_as_blocked() -> void:
	var grid := GridFixture.flat(3, 3)
	var crate := Part.new()
	crate.id = &"crate"
	grid.blockers[Vector2i(1, 1)] = crate
	var pf := Pathfinder.new(grid)
	assert_eq(pf.move_cost(Vector2i(0, 0), Vector2i(1, 1)), -1.0)
	assert_false(pf.is_walkable(Vector2i(1, 1)))


## tb31 Pass C: a DESTROYED blocker must clear to fully passable — before
## this, a dead crate (or a destroyed wall, once walls became destructible
## cover) still walled off its own cell forever, since `move_cost` only
## ever checked whether `blockers` HAD an entry, never its `hp`.
## `ShotPlane`/`BodyProjector` already skip a 0-hp Part; this is the other
## half of the same fix.
func test_move_cost_treats_a_destroyed_field_object_as_passable() -> void:
	var grid := GridFixture.flat(3, 3)
	var crate := Part.new()
	crate.id = &"crate"
	crate.hp = 0
	grid.blockers[Vector2i(1, 1)] = crate
	var pf := Pathfinder.new(grid)
	assert_true(pf.is_walkable(Vector2i(1, 1)), "a destroyed blocker must no longer block movement")
	assert_eq(pf.move_cost(Vector2i(0, 0), Vector2i(1, 1)), Pathfinder.DEFAULT_COST)


## tb31 Pass C: a wall (real data, `DataLibrary.get_part(&"wall")`) blocks
## movement exactly like any other living blocker while intact, and clears
## once destroyed — the shared fix applies to it the same as scatter cover.
func test_an_intact_wall_blocks_movement_a_destroyed_one_does_not() -> void:
	var grid := GridFixture.flat(3, 3)
	var wall: Part = GridFixture.place_wall(grid, Vector2i(1, 1))
	var pf := Pathfinder.new(grid)
	assert_false(pf.is_walkable(Vector2i(1, 1)), "an intact wall must block movement")

	wall.hp = 0

	assert_true(pf.is_walkable(Vector2i(1, 1)), "a destroyed wall must clear to passable")


func test_astar_routes_around_a_field_object() -> void:
	var grid := GridFixture.flat(3, 3)
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
	var grid := GridFixture.flat(6, 1)
	var pf := Pathfinder.new(grid)
	var matches: Array[Vector2i] = [Vector2i(4, 0), Vector2i(1, 0)]
	var found: Variant = pf.nearest_matching(
		Vector2i(0, 0), 10.0, func(cell: Vector2i) -> bool: return matches.has(cell)
	)
	assert_eq(found, Vector2i(1, 0), "the nearer match must win even if discovered later")


func test_nearest_matching_respects_the_radius_cap() -> void:
	var grid := GridFixture.flat(10, 1)
	var pf := Pathfinder.new(grid)
	var found: Variant = pf.nearest_matching(
		Vector2i(0, 0), 3.0, func(cell: Vector2i) -> bool: return cell == Vector2i(9, 0)
	)
	assert_null(found, "a match outside the radius cap must not be found")


func test_nearest_matching_returns_null_when_nothing_matches() -> void:
	var grid := GridFixture.flat(5, 1)
	var pf := Pathfinder.new(grid)
	var found: Variant = pf.nearest_matching(
		Vector2i(0, 0), 10.0, func(cell: Vector2i) -> bool: return false
	)
	assert_null(found)


func test_nearest_matching_never_crosses_a_blocked_cell() -> void:
	var grid := GridFixture.flat(5, 1)
	GridFixture.place_wall(grid, Vector2i(2, 0))
	var pf := Pathfinder.new(grid)
	var found: Variant = pf.nearest_matching(
		Vector2i(0, 0), 10.0, func(cell: Vector2i) -> bool: return cell == Vector2i(4, 0)
	)
	assert_null(found, "a 1-row corridor with no way around a wall must never reach past it")


func test_truncate_to_budget_stops_at_the_affordable_prefix() -> void:
	var grid := GridFixture.flat(5, 1)
	var pf := Pathfinder.new(grid)
	var path: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)
	]
	var truncated: Array[Vector2i] = pf.truncate_to_budget(path, 2.0)
	assert_eq(truncated, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])


## taskblock-39 Pass C: same replacement reasoning as
## `test_reachable_respects_mp_budget_exactly` above — a climb edge stands
## in for the retired variable-terrain-cost mechanism, preserving "an
## expensive edge can't be partially afforded" rather than pinning
## `{TERRAIN_DIFFICULT: 5.0}` itself.
func test_truncate_to_budget_stops_before_a_cell_it_cannot_afford_even_partially() -> void:
	var grid := GridFixture.flat(3, 1)
	GridFixture.place_floor(grid, Vector2i(2, 0), 1)
	var pf := Pathfinder.new(grid, true)  # climb-capable
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var truncated: Array[Vector2i] = pf.truncate_to_budget(path, 3.0)
	assert_eq(
		truncated,
		[Vector2i(0, 0), Vector2i(1, 0)],
		"the climb can't be afforded even though 2.0 MP remains after the first ordinary step"
	)


func test_truncate_to_budget_on_an_empty_path_returns_empty() -> void:
	var grid := GridFixture.flat(3, 1)
	var pf := Pathfinder.new(grid)
	assert_eq(pf.truncate_to_budget([], 5.0), [] as Array[Vector2i])


func test_placement_mode_an_unfloored_cell_has_no_inbound_edge() -> void:
	var grid := GridFixture.flat(3, 1)
	grid.clear_surfaces(Vector2i(1, 0))  # left deliberately unfloored -- no edge at all
	var pf := Pathfinder.new(grid)

	assert_false(pf.is_walkable(Vector2i(1, 0)), "an unfloored cell has no edge into it at all")
	assert_eq(pf.astar(Vector2i(0, 0), Vector2i(2, 0)), [] as Array[Vector2i])


func test_placement_mode_rejects_a_surface_missing_the_walkable_tag() -> void:
	var grid := GridFixture.flat(2, 1)
	var decorative := Part.new()
	decorative.id = &"decorative"
	decorative.attaches_to = [GridPlacement.GROUND]
	grid.clear_surfaces(Vector2i(1, 0))
	GridPlacement.place(grid, Vector2i(1, 0), decorative, 0.0)
	var pf := Pathfinder.new(grid)

	assert_false(
		pf.is_walkable(Vector2i(1, 0)), "a surface without the walkable tag isn't standable"
	)


## "Partial MP costs round up" (docs/PLAN.md, settled) — a 1.8 MP climb
## (CLIMB_COST 4.0 * a 0.45-level rise) charges 2, not 1.8.
##
## tb60 Pass A: **the rise has moved twice, and both moves are the pass working.** It was 0.3,
## which stopped being a climb when `step_height` arrived; then 0.4, which stopped being a
## climb when the supervisor set the step height there. **Derived off the constant now rather
## than written as a literal**, so the next retune moves it automatically instead of going red.
func test_placement_mode_partial_climb_cost_rounds_up() -> void:
	var grid := GridFixture.flat(2, 1)
	# Just above the step height, and derived so this cannot silently become a walk again.
	var rise: float = Unit.BASE_STEP_HEIGHT + 0.05
	GridFixture.place_floor(grid, Vector2i(1, 0), rise)
	var pf := Pathfinder.new(grid, true)

	assert_almost_eq(
		pf.move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		ceil(Pathfinder.CLIMB_COST * rise),
		0.0001,
		"a %.2f rise is a climb costing ceil(%.1f * %.2f)" % [rise, Pathfinder.CLIMB_COST, rise]
	)


## **The inversion of the rule this replaced, and the whole of the ramp retirement in one
## assertion** (tb60 Pass A). A ramp-tagged surface used to make its edge ordinary movement
## *regardless of how large the height delta was* — five levels, free, no capability. It now
## earns nothing at all from the tag: a 5.0 rise is not an edge for a non-climber, ramp or
## not, and the identical rise on a plain floor behaves identically.
##
## Keeping the ramp part in the fixture is the point. The cosmetic part still exists, is
## still placeable, and still renders as a slope; what it no longer does is grant traversal.
func test_placement_mode_a_ramp_tag_buys_no_traversal_the_geometry_did_not_earn() -> void:
	var ramp_grid := GridFixture.flat(2, 1)
	GridFixture.place_ramp(ramp_grid, Vector2i(1, 0), 5.0)
	var floor_grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(floor_grid, Vector2i(1, 0), 5.0)

	var ramp_pf := Pathfinder.new(ramp_grid)  # cannot climb
	var floor_pf := Pathfinder.new(floor_grid)  # cannot climb

	assert_almost_eq(
		ramp_pf.move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		-1.0,
		0.0001,
		"a 5-level rise is no edge for a non-climber, whatever the surface is labelled"
	)
	assert_almost_eq(
		floor_pf.move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		ramp_pf.move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		0.0001,
		"and the plain floor at the same height behaves identically"
	)
