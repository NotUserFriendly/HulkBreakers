extends GutTest

## docs/09 taskblock07 Pass C: "the bidirectional highlight (taskblock-05
## C) landed half the intent... hover a part in the world -> its inventory
## row highlights. What was actually wanted, and is missing: hover an
## inventory row -> highlight that part in the world."
##
## taskblock-22 Pass I: InspectPanel (taskblock-21 Pass A) supersedes
## InventoryPanel everywhere, including this bidirectional wiring — same
## investigation-before-code posture this file's own history already
## established (docs/09 "ask, don't invent"): both directions live in
## InspectPanel now (`_on_tree_gui_input` calls `tactics.hover_part()`,
## `_on_highlight_changed` colors the row back), reusing the exact same
## `BattleScene._on_highlight_changed()` glue reproduced below rather than
## a second path. No new production mechanism — InventoryPanel's own is
## ported, not reinvented.


func _make_unit(cell: Vector2i, squad: int = 0) -> Dictionary:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 3
	arm.max_hp = 3
	arm.volume = [Box.new(Vector3.ZERO, Vector3(0.3, 0.3, 0.3))]

	var leg := Part.new()
	leg.id = &"leg"
	leg.hp = 4
	leg.max_hp = 4
	leg.volume = [Box.new(Vector3.ZERO, Vector3(0.4, 0.6, 0.4))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	torso.volume = [Box.new(Vector3.ZERO, Vector3(1.0, 1.0, 1.0))]
	var arm_socket := Socket.new(&"ARM")
	arm_socket.occupant = arm
	var leg_socket := Socket.new(&"LEG")
	leg_socket.occupant = leg
	torso.sockets = [arm_socket, leg_socket]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, squad)
	return {"unit": unit, "arm": arm, "leg": leg}


## Builds InspectPanel + HitVolumeView against the SAME TacticsController —
## each is only ever tested in isolation elsewhere, so this is the one
## place the actual cross-panel wiring gets exercised at all.
func _setup(built: Dictionary) -> Dictionary:
	var unit: Unit = built.unit
	var state := CombatState.new(Grid.new(10, 10), [unit])
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	controller.setup(state, board_view, camera_rig)
	controller.click_cell(unit.cell)

	var panel := InspectPanel.new()
	add_child_autofree(panel)
	panel.setup(DataLibrary.material_table(), null, Callable(), controller)
	panel.open(unit)
	# A real, laid-out Tree has real dimensions by the time a human could
	# ever hover it; a freshly constructed one in a synchronous test does
	# not (no layout pass has run). Setting a real size directly gets the
	# same real hit-testing without needing an async awaited frame.
	panel._inventory_tree.size = Vector2(400, 300)

	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	# BattleScene._on_highlight_changed()'s own one-line glue, reproduced
	# here rather than standing up a whole BattleScene just to prove the
	# signal is enough.
	controller.highlight_changed.connect(
		func() -> void: view.highlight_part(controller.highlighted_part)
	)

	return {"controller": controller, "tree": panel._inventory_tree, "view": view, "panel": panel}


func _row_for(tree: Tree, part: Part) -> TreeItem:
	var item: TreeItem = tree.get_root()
	while item != null:
		if item.get_metadata(0) == part:
			return item
		item = item.get_next_in_tree()
	return null


## docs/09 taskblock07 Pass C/TESTS: "hovering a tree row highlights
## exactly that part's boxes in 3D."
func test_hovering_a_tree_row_highlights_exactly_that_part_in_3d() -> void:
	var built: Dictionary = _make_unit(Vector2i(0, 0))
	var arm: Part = built.arm
	var leg: Part = built.leg
	var wired: Dictionary = _setup(built)
	var controller: TacticsController = wired.controller
	var tree: Tree = wired.tree
	var view: HitVolumeView = wired.view

	var arm_item: TreeItem = _row_for(tree, arm)
	assert_not_null(arm_item)
	var row_rect: Rect2 = tree.get_item_area_rect(arm_item)
	var motion := InputEventMouseMotion.new()
	motion.position = row_rect.position + Vector2(5, row_rect.size.y / 2.0)
	tree.gui_input.emit(motion)

	assert_eq(controller.highlighted_part, arm, "hovering the arm's own row must highlight the arm")
	assert_eq(view._highlighted_part, arm)
	assert_ne(view._highlighted_part, leg, "hovering the arm must never highlight the leg too")


## docs/09 taskblock07 Pass C/TESTS: "hovering a part in 3D highlights
## exactly that row" — the direction that already existed, re-verified
## here alongside the other one now that both panels are wired together.
func test_hovering_a_part_in_3d_highlights_exactly_that_row() -> void:
	var built: Dictionary = _make_unit(Vector2i(0, 0))
	var arm: Part = built.arm
	var leg: Part = built.leg
	var wired: Dictionary = _setup(built)
	var controller: TacticsController = wired.controller
	var tree: Tree = wired.tree

	controller.hover_part(leg)

	var leg_item: TreeItem = _row_for(tree, leg)
	var arm_item: TreeItem = _row_for(tree, arm)
	assert_eq(leg_item.get_custom_bg_color(0), HulkTheme.HIGHLIGHT.darkened(0.6))
	assert_eq(
		arm_item.get_custom_bg_color(0),
		Color(0, 0, 0, 1),
		"hovering the leg must never also tint the arm's own row"
	)


## docs/09 taskblock07 Pass C/TESTS: "neither direction highlights
## anything else" — clearing back to null via the world-hover side must
## also clear the row side (one shared path, not two independent states
## that could disagree).
func test_clearing_the_world_hover_clears_the_row_too() -> void:
	var built: Dictionary = _make_unit(Vector2i(0, 0))
	var arm: Part = built.arm
	var wired: Dictionary = _setup(built)
	var controller: TacticsController = wired.controller
	var tree: Tree = wired.tree
	var view: HitVolumeView = wired.view

	controller.hover_part(arm)
	assert_eq(view._highlighted_part, arm)

	controller.hover_part(null)

	assert_null(view._highlighted_part)
	var arm_item: TreeItem = _row_for(tree, arm)
	assert_eq(arm_item.get_custom_bg_color(0), Color(0, 0, 0, 1))
