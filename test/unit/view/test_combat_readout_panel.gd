extends GutTest

## docs/10 taskblock04 E2/E3: CombatReadoutPanel is a thin renderer over
## TileInspection.inspect() / a clicked Part — the data itself is covered
## headlessly in test_tile_inspection.gd; this only checks the label
## actually gets built from `hovered_cell`/`inspected_part`.


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

	var panel := CombatReadoutPanel.new()
	var label := RichTextLabel.new()
	add_child_autofree(panel)
	add_child_autofree(label)
	panel.setup(controller, label)

	return {"state": state, "controller": controller, "panel": panel, "label": label}


func test_nothing_hovered_or_inspected_shows_an_empty_label() -> void:
	var built: Dictionary = _setup([])
	var label: RichTextLabel = built.label
	assert_eq(label.text, "")


func test_hovering_a_cell_shows_its_terrain() -> void:
	var built: Dictionary = _setup([])
	var controller: TacticsController = built.controller
	var label: RichTextLabel = built.label

	controller.hovered_cell = Vector2i(2, 3)
	controller.hover_changed.emit()

	assert_true(label.text.contains("cell (2, 3)"))
	assert_true(label.text.contains("terrain"))


## docs/10 taskblock04 E1: "enemy parts, HP, materials and DT are fully
## visible this pass" — an enemy-squad unit's own status shows in full via
## hover, exactly as a friendly unit's would.
func test_hovering_an_enemy_shows_its_full_status() -> void:
	var enemy := _make_unit(Vector2i(4, 4), 1)
	var built: Dictionary = _setup([enemy])
	var controller: TacticsController = built.controller
	var label: RichTextLabel = built.label

	controller.hovered_cell = Vector2i(4, 4)
	controller.hover_changed.emit()

	assert_true(label.text.contains("squad 1"))
	assert_true(label.text.contains("5/5"))


func test_hovering_a_field_object_shows_its_own_detail() -> void:
	var built: Dictionary = _setup([])
	var controller: TacticsController = built.controller
	var label: RichTextLabel = built.label
	var scrap: Part = FieldObjects.scrap_pile()
	built.state.grid.blockers[Vector2i(1, 1)] = scrap

	controller.hovered_cell = Vector2i(1, 1)
	controller.hover_changed.emit()

	assert_true(label.text.contains("Scrap Pile"))
	assert_true(label.text.contains("metals"))


func test_an_inspected_part_wins_over_a_hovered_cell() -> void:
	var built: Dictionary = _setup([])
	var controller: TacticsController = built.controller
	var label: RichTextLabel = built.label
	var part := Part.new()
	part.id = &"widget"
	part.hp = 2
	part.max_hp = 2

	controller.hovered_cell = Vector2i(0, 0)
	controller.inspected_part = part
	controller.hover_changed.emit()

	assert_true(label.text.contains("widget"))
	assert_false(label.text.contains("cell (0, 0)"))
