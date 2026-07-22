extends GutTest

## BR27.08: this whole panel used to be a `Tree` -- click a row to set a
## stop marker, then press a separate global "Resolve to Here" button. A
## real click's `item_selected` signal never fired reliably in the live
## game despite checking out in every headless reproduction tried
## (including a real `InputEventMouseButton` pushed through a real
## `Viewport` against the real, correctly-sized production `Tree`) -- the
## root cause was never conclusively identified. Rebuilt on plain
## `Button`/`Label`/`Container` instead -- no marker state, no `Tree`, each
## row resolves through itself directly on press. Every test below drives
## a REAL synthetic click through a real Viewport at the row's own real
## Button rect, not a shortcut -- there is no reason to trust this
## mechanism any more than the one it replaced without the same proof.


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
	var rows_container := VBoxContainer.new()
	var tooltip_view := TooltipView.new()
	add_child_autofree(panel)
	add_child_autofree(rows_container)
	add_child_autofree(tooltip_view)
	panel.setup(controller, rows_container, tooltip_view)
	# BR27.08: the default headless test viewport is tiny (64x64) -- a
	# row built to the right of an unconstrained VBoxContainer lands well
	# outside that, and a real click there is legitimately outside the
	# viewport's own bounds, not a real bug. Matches the existing
	# `test_tooltip_view.gd` convention for the same reason.
	rows_container.get_viewport().size = Vector2i(1920, 1080)

	return {
		"controller": controller,
		"panel": panel,
		"rows_container": rows_container,
		"tooltip_view": tooltip_view,
	}


## The resolve button is always a row's LAST child (`QueuePanel._entry_row`:
## What/AP/MP labels, then the button) -- reading it back by position
## rather than re-deriving the row's own layout.
func _resolve_button(rows_container: VBoxContainer, index: int) -> Button:
	var row: HBoxContainer = rows_container.get_child(index)
	return row.get_child(row.get_child_count() - 1) as Button


func _click_at(viewport: Viewport, screen_pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = screen_pos
	viewport.push_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = screen_pos
	viewport.push_input(up)


func test_empty_queue_has_no_rows() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var rows_container: VBoxContainer = built.rows_container

	controller.click_cell(Vector2i(0, 0))  # selects the unit, nothing queued yet

	assert_eq(rows_container.get_child_count(), 0, "nothing queued, nothing to show")


func test_queuing_actions_creates_one_row_per_entry() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var rows_container: VBoxContainer = built.rows_container

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	controller.click_cell(Vector2i(2, 0))

	assert_eq(rows_container.get_child_count(), 2, "two queued move legs, two rows")


## BR27.08: a real InputEventMouseButton at the row's own real Button rect
## through the real Viewport -- the same simple technique already proven
## for End Turn in test_battle_scene_input.gd. No `get_item_area_rect()`
## gymnastics needed anymore -- a real Button's own screen rect is
## directly reliable.
func test_a_real_click_on_a_rows_resolve_button_resolves_through_it() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var rows_container: VBoxContainer = built.rows_container

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	controller.click_cell(Vector2i(2, 0))
	assert_eq(a.cell, Vector2i(0, 0), "sanity: nothing has resolved yet")

	# Anchored/laid-out Controls only resolve a real global_rect after a
	# live frame runs (tb32 Pass D's own diagnostic note).
	await get_tree().process_frame
	await get_tree().process_frame

	var button: Button = _resolve_button(rows_container, 0)
	_click_at(button.get_viewport(), button.get_global_rect().get_center())

	assert_eq(a.cell, Vector2i(1, 0), "a real click on row 0's own button resolves only that leg")
	assert_eq(rows_container.get_child_count(), 0, "the resolved queue is empty, no rows left")


func test_a_real_click_on_the_second_rows_resolve_button_resolves_through_both() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var rows_container: VBoxContainer = built.rows_container

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	controller.click_cell(Vector2i(2, 0))

	await get_tree().process_frame
	await get_tree().process_frame

	var button: Button = _resolve_button(rows_container, 1)
	_click_at(button.get_viewport(), button.get_global_rect().get_center())

	assert_eq(a.cell, Vector2i(2, 0), "row 1's own button resolves the whole prefix through it")


## Every row (button included) is destroyed and rebuilt fresh on every
## `refresh()` -- proves a later click targets the NEW queue's own index,
## not a stale one left over from before the resolve.
func test_refresh_rebuilds_rows_so_a_later_click_targets_the_fresh_queue() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var rows_container: VBoxContainer = built.rows_container

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))

	await get_tree().process_frame
	await get_tree().process_frame

	var first_button: Button = _resolve_button(rows_container, 0)
	_click_at(first_button.get_viewport(), first_button.get_global_rect().get_center())
	assert_eq(a.cell, Vector2i(1, 0))

	controller.unlock_input()  # stands in for a real ResolutionPlayer's own unlock
	controller.click_cell(Vector2i(2, 0))  # queue a fresh move after the resolve

	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(rows_container.get_child_count(), 1, "one fresh row, not a stale leftover")
	var second_button: Button = _resolve_button(rows_container, 0)
	_click_at(second_button.get_viewport(), second_button.get_global_rect().get_center())

	assert_eq(a.cell, Vector2i(2, 0), "the fresh row's own button resolves the fresh queue")
