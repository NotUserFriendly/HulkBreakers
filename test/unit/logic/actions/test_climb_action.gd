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
	var grid := GridFixture.flat(3, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
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


## A climb launched from a RAMP cell the mover is already resting on
## (`UnitGeometry.true_height_for_cell`'s own `RampGeometry.
## STANDING_OFFSET`), climbing onto an adjacent full ledge one level
## above the ramp's own lower-endpoint level.
##
## taskblock-39 Pass C: this fixture used to be a bare, hand-built
## `Grid` never routed through real placement, so it read `GridLegacy
## Bridge`'s own OLD flat +0.5 ramp offset (tb37) instead of the
## corrected +0.25 `RampGeometry.STANDING_OFFSET` tb38 Pass C actually
## shipped — the exact silent-drift failure mode this taskblock exists
## to catch. Migrated onto a real placed ramp Surface, the mover's true
## rest height is 0.25, not 0.5, so the climb's own real rise is 0.75
## (not 0.5) and its real cost is 3 MP (not 2) — a genuine behavior
## correction this migration surfaces, not a cosmetic fixture swap.
func test_a_climb_from_a_ramp_costs_3_mp_at_the_corrected_standing_height() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_ramp(grid, Vector2i(0, 0), 0)
	# ramp's own lower-endpoint level is 0; true rest height is 0.25. The
	# ledge at (1, 0) sits a full level above the ramp's own level -- a
	# real rise of 0.75 from the mover's true height.
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	unit.mp = 0.0

	assert_almost_eq(
		unit.height,
		RampGeometry.STANDING_OFFSET,
		0.0001,
		"sanity: the mover rests at the corrected standing height on the ramp"
	)

	var action := ClimbAction.new(unit, Vector2i(1, 0))
	assert_true(action.is_legal(state))
	assert_true(state.try_apply(action))

	assert_eq(unit.cell, Vector2i(1, 0))
	# 3 MP at mp_per_ap()=2.0 -> two AP burns (mp 0->2->4, spend 3, land at 1).
	assert_eq(unit.ap, unit.max_ap - 2)
	assert_almost_eq(unit.mp, 1.0, 0.0001)


## "a climb beyond 1 level is illegal" — capped at MAX_CLIMB_LEVELS
## regardless of climb capability, no fallback that allows it anyway.
func test_a_climb_beyond_1_level_is_illegal() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 2)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])

	assert_false(ClimbAction.new(unit, Vector2i(1, 0)).is_legal(state))


func test_a_non_climb_capable_unit_cannot_climb() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0), false)
	var state := CombatState.new(grid, [unit])

	assert_false(ClimbAction.new(unit, Vector2i(1, 0)).is_legal(state))


func test_climbing_onto_a_ramp_cell_is_illegal_thats_ordinary_movement() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_ramp(grid, Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])

	assert_false(ClimbAction.new(unit, Vector2i(1, 0)).is_legal(state))


func test_climbing_a_flat_cell_is_illegal_nothing_to_climb() -> void:
	var grid := GridFixture.flat(2, 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])

	assert_false(ClimbAction.new(unit, Vector2i(1, 0)).is_legal(state))


func test_climb_emits_a_climbed_event() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	state.try_apply(ClimbAction.new(unit, Vector2i(1, 0)))

	var events: Array[LogEvent] = sink.events_of_kind(&"climbed")
	assert_eq(events.size(), 1)
	assert_almost_eq(events[0].data.get("rise"), 1.0, 0.0001)
	assert_almost_eq(events[0].data.get("cost"), 4.0, 0.0001)
