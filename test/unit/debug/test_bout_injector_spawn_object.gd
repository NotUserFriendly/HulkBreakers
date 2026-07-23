extends GutTest

## taskblock-30 follow-up (supervisor): "spawn object (discrete from spawn
## unit) needs a debug option. (Currently cover items, and loose parts.)"
## Generalizes `place_cover` (a physical blocker) to also cover the other
## half `Grid` itself already models — `field_items`, loose dropped Parts
## — one verb either way via the `as_cover` switch. Own file (not
## test_bout_injector.gd, already at gdlint's own public-method cap) —
## same convention as test_bout_injector_move_object.gd.


func _make_unit(cell: Vector2i, squad: int) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func _cover_part(id: StringName) -> Part:
	var p := Part.new()
	p.id = id
	p.material = &"steel"
	p.hp = 4
	p.max_hp = 4
	p.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.5, 0.5))]
	return p


func test_spawn_object_as_cover_places_a_real_blocker() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var pool := {&"scrap_pile": _cover_part(&"scrap_pile")}
	var injector := BoutInjector.new(state)

	var ok: bool = injector.spawn_object(Vector2i(2, 2), &"scrap_pile", pool, true)

	assert_true(ok)
	assert_not_null(state.grid.blockers.get(Vector2i(2, 2)))
	assert_eq((state.grid.blockers[Vector2i(2, 2)] as Part).id, &"scrap_pile")
	assert_false(state.grid.field_items.has(Vector2i(2, 2)), "cover, not a loose item")


func test_spawn_object_as_cover_refuses_an_already_blocked_cell() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	state.grid.blockers[Vector2i(2, 2)] = _cover_part(&"existing")
	var pool := {&"scrap_pile": _cover_part(&"scrap_pile")}
	var injector := BoutInjector.new(state)

	var ok: bool = injector.spawn_object(Vector2i(2, 2), &"scrap_pile", pool, true)

	assert_false(ok)
	assert_eq((state.grid.blockers[Vector2i(2, 2)] as Part).id, &"existing")


func test_spawn_object_as_a_loose_item_adds_to_field_items_not_blockers() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var pool := {&"dropped_arm": _cover_part(&"dropped_arm")}
	var injector := BoutInjector.new(state)
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	assert_gt(pf.move_cost(Vector2i(0, 0), Vector2i(2, 2)), 0.0, "sanity: the cell starts passable")

	var ok: bool = injector.spawn_object(Vector2i(2, 2), &"dropped_arm", pool, false)

	assert_true(ok)
	assert_false(state.grid.blockers.has(Vector2i(2, 2)), "a loose item is never a blocker")
	assert_true(state.grid.field_items.has(Vector2i(2, 2)))
	var items: Array = state.grid.field_items[Vector2i(2, 2)]
	assert_eq(items.size(), 1)
	assert_eq((items[0] as Part).id, &"dropped_arm")
	assert_gt(
		Pathfinder.new(state.grid, state.terrain_costs).move_cost(Vector2i(0, 0), Vector2i(2, 2)),
		0.0,
		"a loose item must never block movement"
	)


func test_spawn_object_as_a_loose_item_appends_to_an_existing_pile() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var already_there := _cover_part(&"salvage")
	state.grid.field_items[Vector2i(2, 2)] = [already_there]
	var pool := {&"dropped_arm": _cover_part(&"dropped_arm")}
	var injector := BoutInjector.new(state)

	injector.spawn_object(Vector2i(2, 2), &"dropped_arm", pool, false)

	var items: Array = state.grid.field_items[Vector2i(2, 2)]
	assert_eq(items.size(), 2)
	assert_true(already_there in items)


func test_spawn_object_refuses_an_unknown_pool_id() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	assert_false(injector.spawn_object(Vector2i(2, 2), &"nonexistent", {}, true))
	assert_false(injector.spawn_object(Vector2i(2, 2), &"nonexistent", {}, false))


func test_spawn_object_logs_whether_it_was_cover_or_a_loose_item() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var pool := {&"scrap_pile": _cover_part(&"scrap_pile")}
	var injector := BoutInjector.new(state)

	injector.spawn_object(Vector2i(2, 2), &"scrap_pile", pool, true)

	var events: Array[LogEvent] = sink.events_of_kind(&"inject")
	assert_eq(events.size(), 1)
	assert_eq(events[0].data.get("verb"), &"spawn_object")
	assert_eq(events[0].data.get("as_cover"), true)
