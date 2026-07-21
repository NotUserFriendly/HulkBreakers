extends GutTest

## taskblock-30 follow-up (supervisor): "generalize move unit to move
## object, so I can move cover, units, or dropped objects." Split from
## test_bout_injector.gd (gdlint's own public-method cap on that file) —
## same convention as test_bout_injector_determinism.gd. `move_object`
## dispatches on the same hit-shaped `{kind, unit, cell}` dict
## `board_clicked` already emits, so the debug panel's own "active target"
## is exactly this verb's own object param.


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


func test_move_object_moves_a_unit_the_same_as_set_position() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.move_object(
		{"kind": Enums.HitKind.UNIT, "unit": a, "cell": a.cell}, Vector2i(5, 5)
	)

	assert_true(ok)
	assert_eq(a.cell, Vector2i(5, 5))
	assert_eq(state.grid.get_occupant_id(Vector2i(5, 5)), a.id)
	assert_eq(state.grid.get_occupant_id(Vector2i(0, 0)), -1)


func test_move_object_on_a_unit_logs_its_own_verb_name_not_set_positions() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var injector := BoutInjector.new(state)

	injector.move_object({"kind": Enums.HitKind.UNIT, "unit": a, "cell": a.cell}, Vector2i(5, 5))

	var events: Array[LogEvent] = sink.events_of_kind(&"inject")
	assert_eq(events.size(), 1)
	assert_eq(events[0].data.get("verb"), &"move_object")


func test_move_object_refuses_a_unit_move_onto_an_occupied_cell() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [a, b])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.move_object(
		{"kind": Enums.HitKind.UNIT, "unit": a, "cell": a.cell}, Vector2i(5, 5)
	)

	assert_false(ok)
	assert_eq(a.cell, Vector2i(0, 0), "a refused move must never mutate the unit's own cell")


func test_move_object_moves_a_cover_blocker_preserving_its_own_state() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var cover := _cover_part(&"scrap_pile")
	cover.hp = 2
	state.grid.blockers[Vector2i(2, 2)] = cover
	var injector := BoutInjector.new(state)

	var ok: bool = injector.move_object(
		{"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(2, 2)}, Vector2i(3, 3)
	)

	assert_true(ok)
	assert_false(state.grid.blockers.has(Vector2i(2, 2)))
	assert_eq(state.grid.blockers[Vector2i(3, 3)], cover, "the SAME Part, not a fresh duplicate")
	assert_eq((state.grid.blockers[Vector2i(3, 3)] as Part).hp, 2, "damage state must travel too")


func test_move_object_refuses_a_cover_move_onto_an_occupied_blocker_cell() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	state.grid.blockers[Vector2i(2, 2)] = _cover_part(&"scrap_pile")
	state.grid.blockers[Vector2i(3, 3)] = _cover_part(&"existing")
	var injector := BoutInjector.new(state)

	var ok: bool = injector.move_object(
		{"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(2, 2)}, Vector2i(3, 3)
	)

	assert_false(ok)
	assert_true(
		state.grid.blockers.has(Vector2i(2, 2)), "a refused move must never mutate anything"
	)
	assert_eq((state.grid.blockers[Vector2i(3, 3)] as Part).id, &"existing")


func test_move_object_moves_loose_field_items_merging_into_an_occupied_destination() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var dropped := _cover_part(&"dropped_arm")
	var already_there := _cover_part(&"salvage")
	state.grid.field_items[Vector2i(2, 2)] = [dropped]
	state.grid.field_items[Vector2i(3, 3)] = [already_there]
	var injector := BoutInjector.new(state)

	var ok: bool = injector.move_object(
		{"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(2, 2)}, Vector2i(3, 3)
	)

	assert_true(ok)
	assert_false(state.grid.field_items.has(Vector2i(2, 2)))
	var merged: Array = state.grid.field_items[Vector2i(3, 3)]
	assert_eq(merged.size(), 2)
	assert_true(already_there in merged)
	assert_true(dropped in merged)


func test_move_object_refuses_a_cell_with_neither_a_blocker_nor_field_items() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.move_object(
		{"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(2, 2)}, Vector2i(3, 3)
	)

	assert_false(ok)


func test_move_object_refuses_when_source_and_destination_are_the_same_cell() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	state.grid.field_items[Vector2i(2, 2)] = [_cover_part(&"salvage")]
	var injector := BoutInjector.new(state)

	var ok: bool = injector.move_object(
		{"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(2, 2)}, Vector2i(2, 2)
	)

	assert_false(ok)
	assert_eq(
		(state.grid.field_items[Vector2i(2, 2)] as Array).size(), 1, "a no-op must not drop data"
	)


func test_move_object_refuses_mid_resolution() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var injector := BoutInjector.new(state)
	state.is_resolving = true

	var ok: bool = injector.move_object(
		{"kind": Enums.HitKind.UNIT, "unit": a, "cell": a.cell}, Vector2i(5, 5)
	)

	assert_false(ok)
	assert_push_error("mid-resolution")
