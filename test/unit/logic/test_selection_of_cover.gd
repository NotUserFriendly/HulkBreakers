extends GutTest

## taskblock-51 Pass K: **clicking cover selects the cover.**
##
## These drive `SelectionController` and `TacticsController`'s real click entry rather than
## constructing a target and asserting it round-trips. `BR51.02` was closed once on a
## hand-built `{kind: CELL}` dict that the click path never produces, and the supervisor found
## it broken the same day — **a test that constructs its own input cannot tell you the caller
## never produces it.**


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _barrel() -> Part:
	var barrel := Part.new()
	barrel.id = &"goo_barrel"
	barrel.hp = 4
	barrel.max_hp = 4
	return barrel


## A live bout with a barrel standing beside the current unit.
func _state_with_cover(cover_cell: Vector2i = Vector2i(4, 2)) -> CombatState:
	var grid: Grid = GridFixture.flat(10, 10)
	grid.blockers[cover_cell] = _barrel()
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(2, 2), 0)
	var state := CombatState.new(grid, [unit])
	state.assign_rest_to_ai([] as Array[int])
	return state


func test_selecting_cover_selects_the_prop_not_the_cell_beneath_it() -> void:
	var state: CombatState = _state_with_cover()
	var selection := SelectionController.new(state)

	selection.select_target(
		SelectionTarget.for_part(state.grid.blockers[Vector2i(4, 2)], Vector2i(4, 2))
	)

	assert_true(selection.selected_target.is_part(), "the prop is what is selected")
	assert_eq(selection.selected_target.part.id, &"goo_barrel")
	assert_null(selection.selected_unit, "and no unit is selected while a prop is")


## **The unit gate is unchanged.** Only the current, living unit may be selected — that rule
## is what makes "you may only queue against whoever's turn it is" true, and Pass K must not
## have loosened it while widening what else can be held.
func test_a_prop_is_selectable_but_a_non_current_unit_still_is_not() -> void:
	var grid: Grid = GridFixture.flat(10, 10)
	grid.blockers[Vector2i(5, 5)] = _barrel()
	var first: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(2, 2), 0)
	var second: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(3, 3), 1)
	var state := CombatState.new(grid, [first, second])
	state.assign_rest_to_ai([] as Array[int])
	var selection := SelectionController.new(state)

	var other: Unit = second if state.current_unit() == first else first
	selection.select(other)
	assert_null(selection.selected_unit, "a unit whose turn it is not stays unselectable")

	selection.select_target(SelectionTarget.for_part(grid.blockers[Vector2i(5, 5)], Vector2i(5, 5)))
	assert_true(selection.selected_target.is_part(), "but a prop has no such gate")


## **`selected_unit` is derived, and that is the point.** Eighty-one readers across the view
## ask this question and every one still means it; a second stored field would drift.
func test_selected_unit_is_derived_from_the_target() -> void:
	var state: CombatState = _state_with_cover()
	var selection := SelectionController.new(state)

	selection.select(state.current_unit())
	assert_eq(selection.selected_unit, state.current_unit())

	selection.select_target(SelectionTarget.for_cell(Vector2i(7, 7)))
	assert_null(selection.selected_unit, "a cell selection is not a unit selection")
	assert_true(selection.selected_target.is_cell(), "but it is still a selection")


## `BR51.10`, asked of the selection rather than of "has anything been clicked".
func test_can_inspect_follows_what_is_selected() -> void:
	var state: CombatState = _state_with_cover()
	var selection := SelectionController.new(state)

	assert_false(selection.can_inspect(), "nothing selected, nothing to inspect")

	selection.select(state.current_unit())
	assert_true(selection.can_inspect())

	selection.select_target(SelectionTarget.for_cell(Vector2i(7, 7)))
	assert_false(selection.can_inspect(), "a bare cell has no body to describe")

	selection.select_target(
		SelectionTarget.for_part(state.grid.blockers[Vector2i(4, 2)], Vector2i(4, 2))
	)
	assert_true(selection.can_inspect(), "a prop does")


# --- the real click path ------------------------------------------------------------------


func _tactics(state: CombatState) -> TacticsController:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, MissionState.new(RunState.new(), state))
	battle.set_overlay(ControlOverlay.for_mode(ViewModes.player()))
	return (battle.overlay as ControlOverlay).tactics()


## **Driven through `click_cell`, the caller's own entry**, not by calling `select_target`.
func test_a_board_click_on_cover_selects_it() -> void:
	var state: CombatState = _state_with_cover()
	var tactics: TacticsController = _tactics(state)
	tactics.selection.select(state.current_unit())

	tactics.click_cell(Vector2i(4, 2))

	assert_true(tactics.selection.selected_target.is_part(), "the barrel is selected")
	assert_null(tactics.selection.selected_unit, "and the unit selection gave way to it")


## **A cell click with a unit selected is still a move order.** Pass K adds cell selection
## where there was nothing; it must take nothing away.
func test_clicking_a_reachable_cell_still_queues_a_move() -> void:
	var state: CombatState = _state_with_cover()
	var tactics: TacticsController = _tactics(state)
	tactics.selection.select(state.current_unit())

	tactics.click_cell(Vector2i(3, 2))

	var queue: ActionQueue = tactics.selection.current_queue()
	assert_true(
		queue != null and not queue.actions.is_empty(), "the move was queued, not a selection"
	)
	assert_eq(
		tactics.selection.selected_unit, state.current_unit(), "and the unit is still selected"
	)


## **The debug panel can be handed cover now** — `BR51.02`'s remaining defect. The cell-driven
## capture path reported every non-unit click as a bare `CELL`, so every OBJECT-target verb
## inherited the hole while the ray path resolved `PART` correctly. Two paths disagreeing
## about what a click means is the bug, not a difference to tune.
func test_capture_mode_reports_cover_as_a_part() -> void:
	var state: CombatState = _state_with_cover()
	var tactics: TacticsController = _tactics(state)
	var captured: Array[Dictionary] = []
	tactics.board_clicked.connect(func(hit: Dictionary) -> void: captured.append(hit))
	tactics.input_capture_mode = true

	tactics.click_cell(Vector2i(4, 2))

	assert_eq(captured.size(), 1)
	assert_eq(captured[0]["kind"], Enums.HitKind.PART, "cover is a PART, not the floor")
	assert_eq((captured[0]["part"] as Part).id, &"goo_barrel")
	assert_eq(captured[0]["cell"], Vector2i(4, 2))


func test_capture_mode_still_reports_a_bare_cell_as_a_cell() -> void:
	var state: CombatState = _state_with_cover()
	var tactics: TacticsController = _tactics(state)
	var captured: Array[Dictionary] = []
	tactics.board_clicked.connect(func(hit: Dictionary) -> void: captured.append(hit))
	tactics.input_capture_mode = true

	tactics.click_cell(Vector2i(8, 8))

	assert_eq(captured[0]["kind"], Enums.HitKind.CELL)
	assert_null(captured[0]["part"], "nothing is standing there")
