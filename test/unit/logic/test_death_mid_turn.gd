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


# --- taskblock-51: a corpse is a wreck, not a unit -----------------------------------------


## **The supervisor's decision, stated and implemented:** *"Dead units should not be selectable
## as units. They should be selectable in the same way parts on the ground or cover is."*
##
## Pass K is what made this expressible — a `PART` target already describes "a thing on the
## board with parts on it", so a wreck needs no fourth kind and nothing downstream changes.
func test_a_dead_unit_selects_as_a_wreck_not_as_a_unit() -> void:
	var state: CombatState = _bout()
	var selection := SelectionController.new(state)
	var acting: Unit = state.current_unit()
	state.kill_unit(acting)

	selection.select(acting)

	assert_null(selection.selected_unit, "not as a unit")
	assert_true(selection.selected_target.is_part(), "as a wreck")
	assert_eq(selection.selected_target.part, acting.shell.root, "and it is that unit's own shell")
	assert_eq(selection.selected_target.cell, acting.cell, "lying where it fell")


## **Nothing can be commanded through a wreck.** This is the property that makes the decision
## safe: only a `UNIT` target reaches the queue, so a corpse cannot be given orders however it
## was selected.
func test_a_wreck_cannot_be_given_orders() -> void:
	var state: CombatState = _bout()
	var selection := SelectionController.new(state)
	var acting: Unit = state.current_unit()
	state.kill_unit(acting)
	selection.select(acting)

	assert_null(selection.current_queue(), "no queue for a thing that is not a unit")
	assert_false(selection.queue_move(acting.cell + Vector2i(1, 0)), "and no move can be queued")
	assert_true(selection.reachable_cells().is_empty(), "nor is any reachability drawn")


## **And it is inspectable**, which is the point of selecting it at all — the same path cover
## already takes.
func test_a_wreck_can_be_inspected() -> void:
	var state: CombatState = _bout()
	var selection := SelectionController.new(state)
	var acting: Unit = state.current_unit()
	state.kill_unit(acting)

	selection.select(acting)

	assert_true(selection.can_inspect(), "a wreck has a body to describe")


## **A click resolves it the same way**, so the board and the debug panel agree without either
## special-casing death. Both dict shapes are covered because they are read by different
## constructors and one of them classified everything as a cell earlier in this block.
func test_both_click_shapes_resolve_a_corpse_to_its_wreck() -> void:
	var state: CombatState = _bout()
	var dead: Unit = state.current_unit()
	state.kill_unit(dead)

	var from_hit: SelectionTarget = SelectionTarget.from_hit(
		{"kind": Enums.HitKind.UNIT, "unit": dead, "cell": dead.cell}
	)
	var from_pick: SelectionTarget = SelectionTarget.from_pick(
		{"unit": dead, "part": dead.shell.root, "cell": dead.cell, "t": 1.0}
	)

	assert_true(from_hit.is_part(), "the board_clicked shape")
	assert_true(from_pick.is_part(), "and PartPicker's raw shape")


## A living unit is untouched by any of this.
func test_a_living_unit_still_selects_as_a_unit() -> void:
	var state: CombatState = _bout()
	var selection := SelectionController.new(state)

	selection.select(state.current_unit())

	assert_eq(selection.selected_unit, state.current_unit())
	assert_true(selection.selected_target.is_unit())
