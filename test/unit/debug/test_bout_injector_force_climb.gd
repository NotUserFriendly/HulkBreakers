extends GutTest

## taskblock-37 Pass E: split out of test_bout_injector.gd purely to stay
## under gdlint's max-public-methods (same convention _set_cell_level.gd/
## _spawn_object.gd/etc. already use). `force_climb`/`force_hop_down` are
## `force_action` under a name the debug panel can surface with plain
## scalar params — the only way to actually SEE either action play out
## live, since no AI path queues one yet (docs/PLAN.md's own follow-up
## item). Real legality still applies: this forces WHEN, never WHETHER,
## same as `force_action` itself.


func _make_unit(cell: Vector2i, squad: int) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func test_force_climb_reuses_real_legality_a_non_climber_is_refused() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var grid := Grid.new(5, 5)
	grid.set_level(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.force_climb(a, Vector2i(1, 0))

	assert_false(ok, "a non-climbing unit must be refused, same as any ordinary ClimbAction")
	assert_false(state.was_injected)


func test_force_climb_applies_a_legal_climb_for_real() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	a.shell.root.tags = [&"CLIMBER"]
	var grid := Grid.new(5, 5)
	grid.set_level(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.force_climb(a, Vector2i(1, 0))

	assert_true(ok)
	assert_eq(a.cell, Vector2i(1, 0))
	assert_eq(a.level, 1)
	assert_true(state.was_injected)


func test_force_hop_down_applies_a_legal_drop_for_real() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var grid := Grid.new(5, 5)
	grid.set_level(Vector2i(0, 0), 1)
	var state := CombatState.new(grid, [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.force_hop_down(a, Vector2i(1, 0))

	assert_true(ok)
	assert_eq(a.cell, Vector2i(1, 0))
	assert_eq(a.level, 0)
	assert_true(state.was_injected)
