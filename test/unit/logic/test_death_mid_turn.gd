extends GutTest

## taskblock-51 Pass L: **death is not a lifecycle event anything listens for.**
##
## Four symptoms across three supervisor sessions, one root: `SelectionController` never
## referenced `alive` anywhere, and `selected_unit` was a raw reference that outlived the unit
## it pointed at. `BR51.04` made `kill_unit` advance the turn and stopped there — which moved
## the symptom rather than removing it, and is `BR51.09`, filed against CC.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _bout() -> CombatState:
	var grid: Grid = GridFixture.flat(10, 10)
	var first: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(2, 2), 0)
	var second: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(6, 6), 1)
	var state := CombatState.new(grid, [first, second])
	state.assign_rest_to_ai([] as Array[int])
	return state


## **`BR51.09`.** The turn advances (`BR51.04`) but the corpse stayed selected, so its
## reachable-cell overlay kept drawing into the next unit's turn.
func test_killing_the_selected_unit_clears_the_selection() -> void:
	var state: CombatState = _bout()
	var selection := SelectionController.new(state)
	var acting: Unit = state.current_unit()
	selection.select(acting)
	assert_eq(selection.selected_unit, acting, "sanity: it is selected")

	state.kill_unit(acting)

	assert_null(selection.selected_unit, "the corpse is not selected")
	assert_true(selection.selected_target.empty, "and nothing is")


## **Everything keyed to the unit goes, not just the pointer.** A queue left behind would be
## handed back if that id were ever current again.
func test_the_dead_units_queued_plan_does_not_survive_it() -> void:
	var state: CombatState = _bout()
	var selection := SelectionController.new(state)
	var acting: Unit = state.current_unit()
	selection.select(acting)
	selection.queue_move(acting.cell + Vector2i(1, 0))
	assert_false(selection.current_queue().actions.is_empty(), "sanity: a plan exists")

	state.kill_unit(acting)

	assert_null(selection.current_queue(), "no queue, because nothing is selected")
	assert_true(selection.reachable_cells().is_empty(), "and no reachability is drawn")


## **The guard is on read, not on an event.** Nothing subscribes to death — a unit can stop
## being valid by more routes than `kill_unit`, and a call site that forgot to subscribe would
## be the next instance of this bug. Asserted by killing the unit behind the controller's back
## and never telling it.
func test_the_selection_invalidates_without_being_notified() -> void:
	var state: CombatState = _bout()
	var selection := SelectionController.new(state)
	var acting: Unit = state.current_unit()
	selection.select(acting)

	# Straight to the field, bypassing `kill_unit` entirely.
	acting.alive = false

	assert_null(selection.selected_unit, "read-time invalidation needs no notification")


## A death that is not the selected unit must not disturb the selection.
func test_another_units_death_leaves_the_selection_alone() -> void:
	var state: CombatState = _bout()
	var selection := SelectionController.new(state)
	var acting: Unit = state.current_unit()
	selection.select(acting)
	var other: Unit = null
	for unit: Unit in state.units:
		if unit != acting:
			other = unit

	state.kill_unit(other)

	assert_eq(selection.selected_unit, acting, "the wrong death cleared nothing")


## **Death during its own turn ends that turn** (`BR51.04`), asserted here because Pass L owns
## the whole lifecycle and a regression in either half reads identically from the chair.
func test_killing_the_current_unit_ends_its_turn() -> void:
	var state: CombatState = _bout()
	var acting: Unit = state.current_unit()

	state.kill_unit(acting)

	assert_ne(state.current_unit(), acting, "the turn moved on")


## **But not while RESOLUTION is running.** Advancing the turn mid-resolve would reorder the
## queue being resolved underneath itself — the two-phase rule (docs/09) says RESOLUTION owns
## its own mutation order.
func test_a_death_during_resolution_does_not_advance_the_turn_underneath_it() -> void:
	var state: CombatState = _bout()
	var acting: Unit = state.current_unit()
	state.is_resolving = true

	state.kill_unit(acting)

	assert_eq(state.current_unit(), acting, "the resolve finishes on its own terms")
	assert_false(acting.alive, "though the unit is certainly dead")
