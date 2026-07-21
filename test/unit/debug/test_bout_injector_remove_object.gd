extends GutTest

## taskblock-30 follow-up (supervisor): "remove can be generalized to
## objects, covers, and things on tiles. Fully vanishing it." One
## active-target-driven verb (`target` is the same hit-shaped `{kind,
## unit, cell}` dict `move_object` already consumes) covers all three —
## distinct from `kill` (test_bout_injector_kill.gd), a REAL, narratively
## true death. `remove_object` on a unit is debug-only cleanup: the DATA
## side here just marks it dead through the real `CombatState.kill_unit`
## path (bare, no matrix ejection — that's `kill`'s own job); making the
## unit's VIEW actually vanish is `BattleScene.remove_unit_view`'s job
## (view-layer, covered in test_battle_scene.gd/the overlay test files —
## BoutInjector itself is view-agnostic and can't touch the SceneTree).


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


func test_remove_object_on_a_unit_kills_it_through_the_real_combat_state_path() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.remove_object({"kind": Enums.HitKind.UNIT, "unit": a, "cell": a.cell})

	assert_true(ok)
	assert_false(a.alive)
	assert_eq(state.grid.get_occupant_id(Vector2i(0, 0)), -1)


func test_remove_object_on_a_unit_never_ejects_the_matrix_thats_kills_own_job() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var link := Matrix.new()
	link.id = &"link"
	torso.hosted_matrix = link
	torso.sockets = [Socket.new(&"MATRIX")]
	var a := Unit.new(link, Shell.new(torso), Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	injector.remove_object({"kind": Enums.HitKind.UNIT, "unit": a, "cell": a.cell})

	assert_not_null(a.resolve_matrix(), "remove_object is not kill — no matrix ejection")


func test_remove_object_on_a_unit_always_succeeds_even_if_already_dead() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	state.kill_unit(a)
	var injector := BoutInjector.new(state)

	var ok: bool = injector.remove_object({"kind": Enums.HitKind.UNIT, "unit": a, "cell": a.cell})

	assert_true(ok, "a corpse can still be made to vanish, not just a living unit")


func test_remove_object_on_a_cell_erases_the_blocker_there() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	state.grid.blockers[Vector2i(2, 2)] = _cover_part(&"scrap_pile")
	var injector := BoutInjector.new(state)

	var ok: bool = injector.remove_object(
		{"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(2, 2)}
	)

	assert_true(ok)
	assert_false(state.grid.blockers.has(Vector2i(2, 2)))


func test_remove_object_on_a_cell_erases_loose_field_items_there_too() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	state.grid.field_items[Vector2i(2, 2)] = [_cover_part(&"salvage")]
	var injector := BoutInjector.new(state)

	var ok: bool = injector.remove_object(
		{"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(2, 2)}
	)

	assert_true(ok)
	assert_false(state.grid.field_items.has(Vector2i(2, 2)))


func test_remove_object_on_a_cell_erases_both_a_blocker_and_field_items_at_once() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	state.grid.blockers[Vector2i(2, 2)] = _cover_part(&"scrap_pile")
	state.grid.field_items[Vector2i(2, 2)] = [_cover_part(&"salvage")]
	var injector := BoutInjector.new(state)

	injector.remove_object({"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(2, 2)})

	assert_false(state.grid.blockers.has(Vector2i(2, 2)))
	assert_false(state.grid.field_items.has(Vector2i(2, 2)))


func test_remove_object_refuses_a_cell_with_neither_a_blocker_nor_field_items() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.remove_object(
		{"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(2, 2)}
	)

	assert_false(ok)


func test_remove_object_refuses_mid_resolution() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)
	state.is_resolving = true

	var ok: bool = injector.remove_object({"kind": Enums.HitKind.UNIT, "unit": a, "cell": a.cell})

	assert_false(ok)
	assert_push_error("mid-resolution")
