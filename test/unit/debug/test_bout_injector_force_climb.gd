extends GutTest

## taskblock-37 Pass E: split out of test_bout_injector.gd purely to stay
## under gdlint's max-public-methods (same convention _set_cell_level.gd/
## _spawn_object.gd/etc. already use). `force_climb`/`force_hop_down` are
## `force_action` under a name the debug panel can surface with plain
## scalar params. Real legality still applies: this forces WHEN, never
## WHETHER, same as `force_action` itself.
##
## tb62 Pass C1: **the verbs survive; what they build changed.** They force a one-step
## `MoveAction` now, because `ClimbAction`/`HopDownAction` are retired — they were legal in
## exactly the situations `MoveAction` already handled, at exactly the same cost, and the
## planner had been going up ladders through `MoveAction` all along. The old header's claim
## that this was *"the only way to actually SEE either action play out live"* was true of the
## classes and never true of the movement.


func _make_unit(cell: Vector2i, squad: int) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func test_force_climb_reuses_real_legality_a_non_climber_is_refused() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var grid := GridFixture.flat(5, 5)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.force_climb(a, Vector2i(1, 0))

	assert_false(ok, "a non-climbing unit has no upward edge, so the forced step is refused")
	assert_false(state.was_injected)


func test_force_climb_applies_a_legal_climb_for_real() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	a.shell.root.tags = [&"CLIMBER"]
	var grid := GridFixture.flat(5, 5)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.force_climb(a, Vector2i(1, 0))

	assert_true(ok)
	assert_eq(a.cell, Vector2i(1, 0))
	assert_eq(a.level, 1)
	assert_true(state.was_injected)


func test_force_hop_down_applies_a_legal_drop_for_real() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var grid := GridFixture.flat(5, 5)
	GridFixture.place_floor(grid, Vector2i(0, 0), 1)
	var state := CombatState.new(grid, [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.force_hop_down(a, Vector2i(1, 0))

	assert_true(ok)
	assert_eq(a.cell, Vector2i(1, 0))
	assert_eq(a.level, 0)
	assert_true(state.was_injected)


## tb62 Pass C1: the two verbs build the same action, so **the direction check is what keeps
## them distinct** — asking to climb onto something below you is a refusal that names the
## mistake rather than a silent drop in the wrong direction.
func test_the_verbs_refuse_a_target_on_the_wrong_side() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	a.shell.root.tags = [&"CLIMBER"]
	var grid := GridFixture.flat(5, 5)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a])
	var injector := BoutInjector.new(state)

	assert_false(injector.force_hop_down(a, Vector2i(1, 0)), "that cell is above, not below")
	assert_false(state.was_injected, "and nothing was applied")
	assert_false(injector.force_climb(a, Vector2i(2, 0)), "and that one is level, not above")
	assert_false(state.was_injected)
