extends GutTest

## taskblock-53 Pass B: the placeholder map loader, `BoutInjector.load_map`.
##
## Crude by design (`PLAN.md` sequences the real menu after the editors), so what is tested
## is not ergonomics but the two things a placeholder still has to get right: it must not
## leave units inside geometry, and it must refuse a bad file with a sentence rather than a
## crash.

const MAP_PATH := "res://data/maps/proving_ground.tres"


func _state() -> CombatState:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.8, 1.0, 0.6))]
	var a := Unit.new(Matrix.new(), Shell.new(torso.duplicate(true)), Vector2i(1, 1), 0)
	var b := Unit.new(Matrix.new(), Shell.new(torso.duplicate(true)), Vector2i(2, 1), 1)
	var state := CombatState.new(GridFixture.flat(6, 6), [a, b])
	state.assign_all_to_human()
	return state


func test_loading_the_committed_map_replaces_the_board_and_places_units_on_spawns() -> void:
	var state: CombatState = _state()
	var injector := BoutInjector.new(state)
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	assert_true(injector.load_map(MAP_PATH), "the committed map loads")
	assert_eq(state.grid.width, 21, "the board is the loaded one")
	assert_eq(state.grid.rows, 12)

	for unit: Unit in state.units:
		var cell: Vector2i = unit.cell
		assert_true(state.grid.in_bounds(cell), "unit %d is on the board" % unit.id)
		assert_false(state.grid.blockers.has(cell), "unit %d is not inside a wall" % unit.id)
		assert_not_null(
			Surface.first_walkable(state.grid.surfaces_at(cell)),
			"unit %d has something to stand on" % unit.id
		)
		assert_eq(
			state.grid.get_occupant_id(cell),
			unit.id,
			"and the grid knows unit %d is there" % unit.id
		)

	# `_log_injection` emits a uniform `&"inject"` event carrying the verb in its data —
	# every injector verb shares that shape, so this asks for the kind the injector actually
	# emits rather than for one named after the verb.
	var injects: Array[LogEvent] = sink.events_of_kind(&"inject")
	var loads: Array[LogEvent] = []
	for event: LogEvent in injects:
		if event.data.get("verb") == &"load_map":
			loads.append(event)
	assert_eq(loads.size(), 1, "the load is logged")
	# **Bail rather than index an empty array** (`BR52.02`): an out-of-bounds read is a
	# runtime error, and a runtime error under `-d` opens a debugger break that HANGS the
	# headless run instead of failing it. This exact line hung a 300-second run once already.
	if loads.is_empty():
		return
	gut.p("logged: %s" % loads[0].text)


## **Squad membership picks the marker.** Squad 0 goes to SPAWN_A, anything else to SPAWN_B —
## the two squads must not pile onto one side of the map.
func test_each_squad_lands_on_its_own_spawn_marker() -> void:
	var state: CombatState = _state()
	BoutInjector.new(state).load_map(MAP_PATH)
	for unit: Unit in state.units:
		var wanted: int = (
			Enums.SpawnMarker.SPAWN_A if unit.squad_id == 0 else Enums.SpawnMarker.SPAWN_B
		)
		assert_eq(
			state.grid.get_spawn_marker(unit.cell),
			wanted,
			"unit %d (squad %d) landed on its own marker" % [unit.id, unit.squad_id]
		)


func test_a_path_that_is_not_a_map_is_refused_without_touching_the_board() -> void:
	var state: CombatState = _state()
	var before_width: int = state.grid.width
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	assert_false(BoutInjector.new(state).load_map("res://data/parts/wall.tres"))
	assert_eq(state.grid.width, before_width, "a refused load changes nothing")
	assert_gt(sink.events.size(), 0, "and says so in the log")


func test_a_missing_path_is_refused_rather_than_crashing() -> void:
	var state: CombatState = _state()
	assert_false(BoutInjector.new(state).load_map("res://data/maps/no_such_map.tres"))
	assert_eq(state.grid.width, 6, "the board is untouched")


## The verb is registered, and registered as board-changing — `BR35.03`'s fix gates board
## rebuilds on `affects_board`, so a verb that replaces the whole board and is missing from
## that list would swap the geometry under a view still drawing the old one.
func test_the_verb_is_registered_and_rebuilds_the_board() -> void:
	var ids: Array[StringName] = []
	for spec: DebugVerbSpec in DebugVerbs.all():
		ids.append(spec.id)
	assert_true(ids.has(&"load_map"), "the verb is on the panel")
	assert_true(DebugVerbs.affects_board(&"load_map"), "and it rebuilds the board")
