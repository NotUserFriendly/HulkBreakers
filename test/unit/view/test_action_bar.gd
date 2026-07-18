extends GutTest

## taskblock-08 E1/TESTS: "the action bar has 10 square slots." Pips,
## action provisioning, and enable/disable logic are already covered
## (test_action_catalog.gd, test_tactics_controller_arm.gd) — this is
## layout only (E4).


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func test_slot_count_is_ten() -> void:
	assert_eq(ActionBar.SLOT_COUNT, 10)


func test_box_size_is_square() -> void:
	assert_eq(ActionBar.BOX_SIZE.x, ActionBar.BOX_SIZE.y)


func test_setup_builds_ten_square_panels() -> void:
	var state := CombatState.new(Grid.new(10, 10), [_make_unit(Vector2i(0, 0))])
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	var tooltip_view := TooltipView.new()
	var container := HBoxContainer.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	add_child_autofree(tooltip_view)
	add_child_autofree(container)
	controller.setup(state, board_view, camera_rig)

	var bar := ActionBar.new()
	add_child_autofree(bar)
	bar.setup(controller, container, tooltip_view)

	assert_eq(container.get_child_count(), ActionBar.SLOT_COUNT)
	for i in range(ActionBar.SLOT_COUNT):
		var panel: PanelContainer = container.get_child(i)
		assert_eq(panel.custom_minimum_size, ActionBar.BOX_SIZE)
		assert_eq(
			panel.custom_minimum_size.x, panel.custom_minimum_size.y, "slot %d must be square" % i
		)
