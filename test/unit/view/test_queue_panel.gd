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
	# BR27.08: matches the real production sizing (`squad_control_overlay.
	# gd`'s own `queue_tree.custom_minimum_size`) -- an unsized bare Tree
	# lays out too small, and `get_item_area_rect()` can report a row
	# extending past the Tree's own visible rect, which a real click then
	# legitimately misses (`Control.has_point()` says no) for a reason
	# that has nothing to do with any real bug. Confirmed by hand before
	# this was added: the exact same click test failed against a
	# same-shaped but UNSIZED Tree, and passed once sized like this.
	tree.custom_minimum_size = Vector2(320, 100)
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


## BR27.08: this does NOT drive "the same path a real click does" despite
## what this comment used to claim -- it sets the Tree's own selection
## state directly and then manually calls the panel's handler, skipping
## the Tree's own hit-testing and its `item_selected` signal entirely. A
## real click could, in principle, fail to reach the Tree at all (wrong
## screen position, something else eating the input) while this helper
## would still happily proceed -- it was never actually proof that the
## click-to-select path itself works. Convenient for every test below that
## only cares about marker/refresh behavior once a row IS selected, one
## way or another. `test_a_real_click_on_a_queue_row_enables_resolve_to_
## here` below is the one test that drives an actual synthetic click
## through the real Viewport instead, and is what actually proves the path
## this comment used to just assert.
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


## BR27.08 ("Resolve to Here" reported grayed out and unclickable in real
## play): every test above drives the marker through `_select_row()`,
## documented as driving "the same path a real click does... without
## needing a live viewport" -- an assumption never actually proven. A real
## click has to go through the Tree's OWN hit-testing and emit
## `item_selected` on its own; `.select()` + a manual `_on_item_selected()`
## call skips that entirely. This pushes a genuine InputEventMouseButton at
## the row's own real screen rect through the real Viewport -- the same
## technique test_battle_scene_input.gd already uses for BR31.01 -- to
## prove or disprove that the signal fires from an actual click.
func test_a_real_click_on_a_queue_row_enables_resolve_to_here() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var tree: Tree = built.tree
	var button: Button = built.button

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	assert_true(button.disabled, "sanity: nothing selected yet")

	# Anchored/laid-out Controls only resolve a real global_rect after a
	# live frame runs (tb32 Pass D's own diagnostic note) -- read too early
	# and this returns a garbage pre-layout rect.
	await get_tree().process_frame
	await get_tree().process_frame

	var item: TreeItem = tree.get_root().get_child(0)
	var row_rect: Rect2 = tree.get_item_area_rect(item)
	var screen_pos: Vector2 = (
		tree.get_global_rect().position
		+ row_rect.position
		+ Vector2(row_rect.size.x / 2.0, row_rect.size.y / 2.0)
	)

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = screen_pos
	tree.get_viewport().push_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = screen_pos
	tree.get_viewport().push_input(up)

	assert_false(
		button.disabled,
		(
			"a real click on a queue row must enable Resolve to Here -- "
			+ "not just a manual .select() + _on_item_selected() call"
		)
	)


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
