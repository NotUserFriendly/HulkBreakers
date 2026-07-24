extends GutTest


func _make_unit(cell: Vector2i, climber: bool = true) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	if climber:
		root.tags = [&"CLIMBER"]
	return Unit.new(Matrix.new(), Shell.new(root), cell, 0)


## "a climb-up action moves a unit one level and costs 4 MP" (taskblock-37
## Pass D's own TESTS).
func test_climb_up_a_full_level_moves_the_unit_and_costs_4_mp() -> void:
	var grid := Grid.new(3, 1)
	grid.set_level(Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	unit.mp = 0.0

	var action := ClimbAction.new(unit, Vector2i(1, 0))
	assert_true(action.is_legal(state))
	assert_true(state.try_apply(action))

	assert_eq(unit.cell, Vector2i(1, 0))
	assert_eq(unit.level, 1)
	assert_almost_eq(unit.height, UnitGeometry.LEVEL_HEIGHT, 0.0001)
	# 4 MP at mp_per_ap()=2.0 (agility 0) -> two AP burns, mp lands at 0.
	assert_eq(unit.ap, unit.max_ap - 2)
	assert_almost_eq(unit.mp, 0.0, 0.0001)


## "a half-level climb costs 2" — launched from a RAMP tile the mover is
## already resting on (`UnitGeometry.true_height_for_cell`'s own +0.5),
## climbing onto an adjacent full ledge one level above the ramp's own
## discrete `Grid.level`.
func test_a_half_level_climb_from_a_ramp_costs_2_mp() -> void:
	var grid := Grid.new(2, 1)
	grid.set_terrain(Vector2i(0, 0), Enums.TerrainType.RAMP)
	# ramp's own Grid.level is its LOWER endpoint (0); true rest height is
	# 0.5. The ledge at (1, 0) sits a full level above the ramp's own
	# Grid.level -- a real rise of only 0.5 from the mover's true height.
	grid.set_level(Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	unit.mp = 0.0

	assert_almost_eq(unit.height, 0.5, 0.0001, "sanity: the mover rests at half height on the ramp")

	var action := ClimbAction.new(unit, Vector2i(1, 0))
	assert_true(action.is_legal(state))
	assert_true(state.try_apply(action))

	assert_eq(unit.cell, Vector2i(1, 0))
	# 2 MP at mp_per_ap()=2.0 -> one AP burn, mp lands at 0.
	assert_eq(unit.ap, unit.max_ap - 1)
	assert_almost_eq(unit.mp, 0.0, 0.0001)


## "a climb beyond 1 level is illegal" — capped at MAX_CLIMB_LEVELS
## regardless of climb capability, no fallback that allows it anyway.
func test_a_climb_beyond_1_level_is_illegal() -> void:
	var grid := Grid.new(2, 1)
	grid.set_level(Vector2i(1, 0), 2)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])

	assert_false(ClimbAction.new(unit, Vector2i(1, 0)).is_legal(state))


func test_a_non_climb_capable_unit_cannot_climb() -> void:
	var grid := Grid.new(2, 1)
	grid.set_level(Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0), false)
	var state := CombatState.new(grid, [unit])

	assert_false(ClimbAction.new(unit, Vector2i(1, 0)).is_legal(state))


func test_climbing_onto_a_ramp_tile_is_illegal_thats_ordinary_movement() -> void:
	var grid := Grid.new(2, 1)
	grid.set_terrain(Vector2i(1, 0), Enums.TerrainType.RAMP)
	grid.set_level(Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])

	assert_false(ClimbAction.new(unit, Vector2i(1, 0)).is_legal(state))


func test_climbing_a_flat_cell_is_illegal_nothing_to_climb() -> void:
	var grid := Grid.new(2, 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])

	assert_false(ClimbAction.new(unit, Vector2i(1, 0)).is_legal(state))


func test_climb_emits_a_climbed_event() -> void:
	var grid := Grid.new(2, 1)
	grid.set_level(Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	state.try_apply(ClimbAction.new(unit, Vector2i(1, 0)))

	var events: Array[LogEvent] = sink.events_of_kind(&"climbed")
	assert_eq(events.size(), 1)
	assert_almost_eq(events[0].data.get("rise"), 1.0, 0.0001)
	assert_almost_eq(events[0].data.get("cost"), 4.0, 0.0001)
