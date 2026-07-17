extends GutTest

## taskblock-07 Pass G: ApMpPipRow is a thin renderer over ApMpPips — the
## pip-count math itself is covered headlessly in test_ap_mp_pips.gd;
## this only checks the row actually gets built from those states and
## responds to selection/hover.


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
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

	var row := ApMpPipRow.new()
	var ap_container := HBoxContainer.new()
	var mp_container := HBoxContainer.new()
	var tooltip_view := TooltipView.new()
	add_child_autofree(row)
	add_child_autofree(ap_container)
	add_child_autofree(mp_container)
	add_child_autofree(tooltip_view)
	row.setup(controller, ap_container, mp_container, tooltip_view)

	return {
		"controller": controller,
		"row": row,
		"ap_container": ap_container,
		"mp_container": mp_container,
		"tooltip_view": tooltip_view
	}


func test_nothing_selected_shows_no_pips_in_either_row() -> void:
	var built: Dictionary = _setup([])
	var ap_container: HBoxContainer = built.ap_container
	var mp_container: HBoxContainer = built.mp_container

	assert_eq(ap_container.get_child_count(), 0)
	assert_eq(mp_container.get_child_count(), 0)


func test_selecting_a_unit_builds_max_ap_pips_and_mp_pips() -> void:
	var a := _make_unit(Vector2i(0, 0))
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var ap_container: HBoxContainer = built.ap_container
	var mp_container: HBoxContainer = built.mp_container
	# CombatState's own constructor already ran _start_turn() on `a`
	# (ap = max_ap, mp = 0.0) — set the values this test actually wants
	# to see AFTER that, or they'd be silently overwritten.
	a.max_ap = 6
	a.ap = 4
	a.mp = 3.0

	controller.click_cell(Vector2i(0, 0))

	assert_eq(ap_container.get_child_count(), 6, "the AP row always shows max_ap slots")
	assert_eq(mp_container.get_child_count(), 3)


func test_hovering_the_ap_row_shows_its_tooltip() -> void:
	var a := _make_unit(Vector2i(0, 0))
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var ap_container: HBoxContainer = built.ap_container
	var tooltip_view: TooltipView = built.tooltip_view
	a.ap = 5  # after _setup(): CombatState's own constructor already ran
	# _start_turn() on `a`, which would otherwise overwrite this.

	controller.click_cell(Vector2i(0, 0))
	ap_container.mouse_entered.emit()

	assert_true(tooltip_view.visible)
	assert_true(tooltip_view._label.text.contains("AP"))


func test_hovering_the_mp_row_shows_its_tooltip() -> void:
	var a := _make_unit(Vector2i(0, 0))
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var mp_container: HBoxContainer = built.mp_container
	var tooltip_view: TooltipView = built.tooltip_view
	a.mp = 2.0  # after _setup(): see the AP test's own comment above.

	controller.click_cell(Vector2i(0, 0))
	mp_container.mouse_entered.emit()

	assert_true(tooltip_view.visible)
	assert_true(tooltip_view._label.text.contains("MP"))
