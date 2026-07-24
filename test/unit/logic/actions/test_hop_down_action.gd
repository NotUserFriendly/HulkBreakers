extends GutTest


func _make_unit(cell: Vector2i) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, 0)


## "hop-down costs 1 MP and is legal to 2 levels" (taskblock-37 Pass D's
## own TESTS) — no climb capability needed at all.
func test_hop_down_2_levels_moves_the_unit_and_costs_1_mp() -> void:
	var grid := Grid.new(2, 1)
	grid.set_level(Vector2i(0, 0), 2)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	unit.mp = 0.0

	var action := HopDownAction.new(unit, Vector2i(1, 0))
	assert_true(action.is_legal(state))
	assert_true(state.try_apply(action))

	assert_eq(unit.cell, Vector2i(1, 0))
	assert_eq(unit.level, 0)
	assert_almost_eq(unit.height, 0.0, 0.0001)
	# 1 MP at mp_per_ap()=2.0 (agility 0) -> one AP burn, mp lands at 1.0.
	assert_eq(unit.ap, unit.max_ap - 1)
	assert_almost_eq(unit.mp, 1.0, 0.0001)


func test_hop_down_1_level_is_legal() -> void:
	var grid := Grid.new(2, 1)
	grid.set_level(Vector2i(0, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])

	assert_true(HopDownAction.new(unit, Vector2i(1, 0)).is_legal(state))


## "illegal at 3" — a deeper drop is simply not a legal edge this pass, no
## fallback and no consequence modeling.
func test_hop_down_3_levels_is_illegal() -> void:
	var grid := Grid.new(2, 1)
	grid.set_level(Vector2i(0, 0), 3)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])

	assert_false(HopDownAction.new(unit, Vector2i(1, 0)).is_legal(state))


func test_hopping_up_is_illegal_thats_a_climb_not_a_hop() -> void:
	var grid := Grid.new(2, 1)
	grid.set_level(Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])

	assert_false(HopDownAction.new(unit, Vector2i(1, 0)).is_legal(state))


func test_hopping_onto_a_ramp_tile_is_illegal_thats_ordinary_movement() -> void:
	var grid := Grid.new(2, 1)
	grid.set_terrain(Vector2i(1, 0), Enums.TerrainType.RAMP)
	grid.set_level(Vector2i(0, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])

	assert_false(HopDownAction.new(unit, Vector2i(1, 0)).is_legal(state))


func test_hop_down_emits_a_hopped_down_event() -> void:
	var grid := Grid.new(2, 1)
	grid.set_level(Vector2i(0, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	state.try_apply(HopDownAction.new(unit, Vector2i(1, 0)))

	var events: Array[LogEvent] = sink.events_of_kind(&"hopped_down")
	assert_eq(events.size(), 1)
	assert_almost_eq(events[0].data.get("cost"), 1.0, 0.0001)
