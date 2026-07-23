extends GutTest

## taskblock-36 Pass D: "BoutInjector can set a cell's level — the
## supervisor can then force a height scenario and watch it, which is the
## only way this gets visually confirmed before movement verbs exist."
## Its own file, matching every other verb family's own split-out test
## (test_bout_injector_move_object.gd, _kill.gd, _spawn_object.gd, ...).


func _make_unit(cell: Vector2i, squad: int) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func test_set_cell_level_forces_the_grid() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.set_cell_level(Vector2i(2, 2), 3)

	assert_true(ok)
	assert_eq(state.grid.get_level(Vector2i(2, 2)), 3)


## Forcing a level a unit is ALREADY standing on must not require
## respawning it — the supervisor forces a height scenario onto whatever
## bout is already running.
func test_set_cell_level_resyncs_a_unit_already_standing_there() -> void:
	var a := _make_unit(Vector2i(2, 2), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.set_cell_level(Vector2i(2, 2), 2)

	assert_true(ok)
	assert_eq(a.level, 2, "a unit already on the forced cell must pick up the new level too")


func test_set_cell_level_rejected_while_resolving() -> void:
	var state := CombatState.new(Grid.new(5, 5))
	var injector := BoutInjector.new(state)
	state.is_resolving = true

	assert_false(injector.set_cell_level(Vector2i(2, 2), 1))
	assert_push_error("mid-resolution")
	assert_eq(state.grid.get_level(Vector2i(2, 2)), 0)


func test_set_cell_level_out_of_bounds_returns_false() -> void:
	var state := CombatState.new(Grid.new(5, 5))
	var injector := BoutInjector.new(state)

	assert_false(injector.set_cell_level(Vector2i(99, 99), 1))


func test_set_cell_level_logs_the_injection() -> void:
	var state := CombatState.new(Grid.new(5, 5))
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var injector := BoutInjector.new(state)

	injector.set_cell_level(Vector2i(2, 2), 3)

	var events: Array[LogEvent] = sink.events_of_kind(&"inject")
	assert_eq(events.size(), 1)
	assert_eq(events[0].data.get("verb"), &"set_cell_level")
