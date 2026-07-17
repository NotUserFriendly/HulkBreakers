extends GutTest

## docs/09 taskblock07 Pass B3: "Resolve to Here" never enabled — the fix
## makes the button's enabled state a pure function of (queue, marker),
## recomputed in refresh() alongside everything else, never left standing
## from whatever a past click set it to.


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func _setup(units: Array[Unit]) -> Dictionary:
	var state := CombatState.new(Grid.new(10, 10), units)
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	controller.setup(state, board_view, camera_rig)

	var panel := QueuePanel.new()
	var tree := Tree.new()
	var button := Button.new()
	var tooltip_view := TooltipView.new()
	add_child_autofree(panel)
	add_child_autofree(tree)
	add_child_autofree(button)
	add_child_autofree(tooltip_view)
	panel.setup(controller, tree, button, tooltip_view)

	return {
		"controller": controller,
		"panel": panel,
		"tree": tree,
		"button": button,
		"tooltip_view": tooltip_view
	}


## Selects the Tree row at `index` and drives the same path a real click
## does (Tree's own selection state, then the panel's own handler) without
## needing a live viewport to deliver the click.
func _select_row(panel: QueuePanel, tree: Tree, index: int) -> void:
	tree.get_root().get_child(index).select(QueuePanel.COL_WHAT)
	panel._on_item_selected()


func test_button_starts_disabled_with_nothing_queued() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var button: Button = built.button

	assert_true(button.disabled)


## docs/09 taskblock07 Pass B3/TESTS: "queuing an action with a row
## selected leaves the button enabled after refresh()."
func test_queuing_an_action_with_a_row_selected_leaves_the_button_enabled_after_refresh() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var tree: Tree = built.tree
	var button: Button = built.button
	var panel: QueuePanel = built.panel

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	_select_row(panel, tree, 0)
	assert_false(button.disabled, "sanity: selecting a valid row must enable the button")

	# Queuing a SECOND action fires selection_changed -> refresh() again —
	# the marker (still pointing at the first, still-present entry) must
	# survive this, not get silently wiped the instant anything else
	# changes about the queue.
	controller.click_cell(Vector2i(2, 0))

	assert_false(button.disabled, "the marker must survive a refresh that doesn't invalidate it")


## docs/09 taskblock07 Pass B3/TESTS: "clearing the queue disables it."
func test_clearing_the_queue_disables_the_button() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var tree: Tree = built.tree
	var button: Button = built.button
	var panel: QueuePanel = built.panel

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	_select_row(panel, tree, 0)
	assert_false(button.disabled)

	controller.reset_turn()

	assert_true(button.disabled, "an empty queue must never leave the button enabled")


## docs/09 taskblock07 Pass B3/TESTS: "the enabled state is a pure function
## of (queue, marker), not of event ordering" — setting the marker BEFORE
## the queue exists (an ordering a real click could never actually
## produce) must still resolve correctly once refresh() runs, proving the
## state isn't tracking "did a click happen after the last change."
func test_the_enabled_state_is_a_pure_function_of_queue_and_marker() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var button: Button = built.button
	var panel: QueuePanel = built.panel

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))

	panel._marker_index = 0
	panel.refresh()
	assert_false(button.disabled, "marker 0 with 1 queued entry: must be enabled")

	panel._marker_index = 5  # out of range for a 1-entry queue
	panel.refresh()
	assert_true(button.disabled, "an out-of-range marker must never leave the button enabled")


func test_a_valid_marker_selects_the_matching_row_after_refresh() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var tree: Tree = built.tree
	var panel: QueuePanel = built.panel

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	controller.click_cell(Vector2i(2, 0))
	_select_row(panel, tree, 0)

	controller.click_cell(Vector2i(2, 1))  # a third action — triggers another refresh()

	var selected: TreeItem = tree.get_selected()
	assert_not_null(selected, "the marked row must stay visibly selected across a refresh")
	assert_eq(selected.get_metadata(QueuePanel.COL_WHAT), 0)
