extends GutTest

## taskblock-30 follow-up (supervisor report): "removing a unit doesn't
## visually do anything." Split from test_bout_injector.gd (gdlint's own
## public-method cap on that file, already at 37 exactly) — same
## convention as test_bout_injector_move_object.gd.
##
## Root cause: `HitVolumeView.is_downed()`/the view's own DOWN pose read
## `Unit.resolve_matrix() == null`, never `alive` directly — the same
## thing a REAL kill leaves behind (`DamageResolver.eject_matrix_if_
## needed` nulls the hosting part's own `hosted_matrix` before ever
## calling `kill_unit`). `remove_unit` used to only flip `alive`, leaving
## the matrix still docked — `resolve_matrix()` kept finding it, so
## nothing about the render ever changed.


func _armed_unit(cell: Vector2i, squad: int) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var link := Matrix.new()
	link.id = &"link"
	torso.hosted_matrix = link
	torso.sockets = [Socket.new(&"MATRIX")]
	return Unit.new(link, Shell.new(torso), cell, squad)


func test_remove_unit_ejects_the_hosted_matrix_so_resolve_matrix_goes_null() -> void:
	var a := _armed_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)
	assert_not_null(a.resolve_matrix(), "sanity: a fresh unit has a real matrix docked")

	var ok: bool = injector.remove_unit(a)

	assert_true(ok)
	assert_null(a.resolve_matrix(), "the same check HitVolumeView.is_downed() makes")
	assert_null(a.shell.root.hosted_matrix, "the hosting part itself must be cleared")


func test_remove_unit_drops_the_ejected_matrix_as_a_real_loose_field_item() -> void:
	var a := _armed_unit(Vector2i(2, 2), 0)
	var link: Matrix = a.matrix
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	injector.remove_unit(a)

	assert_true(state.grid.field_items.has(Vector2i(2, 2)))
	assert_true(link in (state.grid.field_items[Vector2i(2, 2)] as Array))


func test_remove_unit_still_kills_through_the_real_combat_state_path() -> void:
	var a := _armed_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.remove_unit(a)

	assert_true(ok)
	assert_false(a.alive)
	assert_eq(state.grid.get_occupant_id(Vector2i(0, 0)), -1)


func test_remove_unit_on_a_matrixless_unit_still_kills_without_erroring() -> void:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	var a := Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.remove_unit(a)

	assert_true(ok)
	assert_false(a.alive)
	assert_false(state.grid.field_items.has(Vector2i(0, 0)), "nothing to eject, nothing to drop")
