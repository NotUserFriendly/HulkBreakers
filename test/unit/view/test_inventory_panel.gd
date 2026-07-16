extends GutTest

## docs/10 taskblock03 H: InventoryPanel is a thin renderer over
## InventoryRows.build() — the row content itself is covered headlessly in
## test_inventory_rows.gd; this only checks the Tree/footer actually get
## built from those rows.


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

	var panel := InventoryPanel.new()
	var tree := Tree.new()
	var footer := Label.new()
	add_child_autofree(panel)
	add_child_autofree(tree)
	add_child_autofree(footer)
	panel.setup(controller, tree, footer, MaterialTable.default_table())

	return {"controller": controller, "panel": panel, "tree": tree, "footer": footer}


func test_nothing_selected_shows_an_empty_tree_and_footer() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var tree: Tree = built.tree
	var footer: Label = built.footer

	assert_null(tree.get_root())
	assert_eq(footer.text, "")


func test_selecting_a_unit_populates_the_tree_with_one_item_per_row() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var tree: Tree = built.tree

	controller.click_cell(Vector2i(0, 0))

	var expected: Array[InventoryRow] = InventoryRows.build(a, MaterialTable.default_table())
	var count := 0
	# tree.get_root() is the Tree control's own hidden container, not a row
	# — the shell root's own row is its first (and, here, only) child.
	var item: TreeItem = tree.get_root().get_child(0)
	while item != null:
		count += 1
		item = item.get_next_in_tree()
	assert_eq(count, expected.size())


func test_selecting_a_unit_fills_in_the_mass_and_ram_footer() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var footer: Label = built.footer

	controller.click_cell(Vector2i(0, 0))

	assert_true(footer.text.contains("mass"))
	assert_true(footer.text.contains("ram"))


func test_deselecting_clears_the_tree_and_footer_again() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var tree: Tree = built.tree
	var footer: Label = built.footer
	controller.click_cell(Vector2i(0, 0))

	controller.deselect()

	assert_null(tree.get_root())
	assert_eq(footer.text, "")


func test_the_socket_id_appears_in_the_part_column() -> void:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	var grip := Socket.new(&"GRIP", Transform3D.IDENTITY, &"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var a := Unit.new(Matrix.new(), Shell.new(hand), Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var tree: Tree = built.tree

	controller.click_cell(Vector2i(0, 0))

	# tree.get_root() is the Tree control's own hidden container; its first
	# child is the shell root's row (hand), whose own first child is pistol.
	var pistol_item: TreeItem = tree.get_root().get_child(0).get_child(0)
	assert_true(pistol_item.get_text(InventoryPanel.COL_PART).contains("GRIP"))
	assert_true(pistol_item.get_text(InventoryPanel.COL_PART).contains("pistol"))
