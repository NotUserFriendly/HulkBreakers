extends GutTest

## taskblock-07 Pass F2: replaces test_combat_readout_panel.gd — same 5
## cases that file covered, now asserted against the shared TooltipView
## instead of a RichTextLabel.
##
## taskblock-08 Pass D2: TooltipView no longer reveals instantly — advance
## past its own hover delay the same way CameraRig's tween tests advance a
## tween (`custom_step`), a direct `_process(delta)` call, never a real
## wall-clock wait.


func _reveal(view: TooltipView) -> void:
	view._process(TooltipView.HOVER_DELAY_SEC + 0.001)


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	root.volume = [Box.new(Vector3.ZERO, Vector3(1.0, 1.0, 1.0))]
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func _setup(units: Array[Unit]) -> Dictionary:
	var state := CombatState.new(Grid.new(10, 10), units)
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	var tooltip_view := TooltipView.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	add_child_autofree(tooltip_view)
	controller.setup(state, board_view, camera_rig)

	var tooltip_controller := TooltipController.new()
	add_child_autofree(tooltip_controller)
	tooltip_controller.setup(controller, tooltip_view, MaterialTable.default_table())

	return {
		"state": state,
		"controller": controller,
		"tooltip_view": tooltip_view,
		"tooltip_controller": tooltip_controller
	}


func test_nothing_hovered_or_inspected_hides_the_tooltip() -> void:
	var built: Dictionary = _setup([])
	var tooltip_view: TooltipView = built.tooltip_view

	assert_false(tooltip_view.visible)


func test_hovering_a_cell_shows_its_terrain() -> void:
	var built: Dictionary = _setup([])
	var controller: TacticsController = built.controller
	var tooltip_view: TooltipView = built.tooltip_view

	controller.hovered_cell = Vector2i(3, 3)
	controller.hover_changed.emit()
	_reveal(tooltip_view)

	assert_true(tooltip_view.visible)
	assert_true(tooltip_view._label.text.contains("cell (3, 3)"))


## taskblock-04 E1: "enemy parts, HP, materials and DT are fully visible —
## no gating." A different squad than the (nonexistent, here) selection
## still gets its full status.
func test_hovering_an_enemy_shows_its_full_status() -> void:
	var enemy: Unit = _make_unit(Vector2i(4, 4), 1)
	var built: Dictionary = _setup([enemy])
	var controller: TacticsController = built.controller
	var tooltip_view: TooltipView = built.tooltip_view

	controller.hovered_cell = Vector2i(4, 4)
	controller.hover_changed.emit()
	_reveal(tooltip_view)

	assert_true(tooltip_view._label.text.contains("unit %d — squad 1" % enemy.id))
	assert_true(tooltip_view._label.text.contains("5/5"))


func test_hovering_a_field_object_shows_its_own_detail() -> void:
	var built: Dictionary = _setup([])
	var state: CombatState = built.state
	var controller: TacticsController = built.controller
	var tooltip_view: TooltipView = built.tooltip_view
	var crate: Part = FieldObjects.crate()
	state.grid.blockers[Vector2i(5, 5)] = crate

	controller.hovered_cell = Vector2i(5, 5)
	controller.hover_changed.emit()
	_reveal(tooltip_view)

	var expected_title: String = (
		crate.display_name if crate.display_name != "" else String(crate.id)
	)
	assert_true(tooltip_view._label.text.contains(expected_title))


func test_an_inspected_part_wins_over_a_hovered_cell() -> void:
	var built: Dictionary = _setup([])
	var controller: TacticsController = built.controller
	var tooltip_view: TooltipView = built.tooltip_view
	var part := Part.new()
	part.id = &"pistol"
	part.hp = 3
	part.max_hp = 3

	controller.hovered_cell = Vector2i(1, 1)
	controller.hover_changed.emit()
	controller.inspect_part(part)
	_reveal(tooltip_view)

	assert_true(tooltip_view._label.text.contains("pistol"))
	assert_false(tooltip_view._label.text.contains("cell (1, 1)"))
