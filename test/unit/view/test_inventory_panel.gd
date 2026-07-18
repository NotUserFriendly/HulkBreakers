extends GutTest

## docs/10 taskblock03 H: InventoryPanel is a thin renderer over
## InventoryRows.build() — the row content itself is covered headlessly in
## test_inventory_rows.gd; this only checks the Tree/footer actually get
## built from those rows.
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
	var tooltip_view := TooltipView.new()
	add_child_autofree(panel)
	add_child_autofree(tree)
	add_child_autofree(footer)
	add_child_autofree(tooltip_view)
	panel.setup(controller, tree, footer, MaterialTable.default_table(), tooltip_view)

	return {
		"controller": controller,
		"panel": panel,
		"tree": tree,
		"footer": footer,
		"tooltip_view": tooltip_view
	}


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


## docs/10 taskblock04 E2: "Inventory... shows the currently controlled
## shell — and nothing else." Deselecting means there is no longer a
## controlled shell to show; the panel goes empty, not sticky (cut from
## the old runNotes.md "sticky inspection" behavior — that's the combat
## readout's job now, via hover, not the inventory panel's).
func test_deselecting_clears_the_panel() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var tree: Tree = built.tree
	controller.click_cell(Vector2i(0, 0))
	assert_not_null(tree.get_root())

	controller.deselect()

	assert_null(tree.get_root(), "no controlled shell left to show")


## docs/10 taskblock04 E2: "Inventory... and nothing else" — an enemy is
## never the currently controlled shell, so clicking one must never
## populate the inventory panel (cut from the old runNotes.md "clicking a
## red team unit should show their parts" behavior — the combat readout's
## hover now covers full enemy status instead, E1/E3).
func test_clicking_an_enemy_never_populates_the_inventory_panel() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var enemy_root := Part.new()
	enemy_root.id = &"enemy_torso"
	enemy_root.hp = 5
	enemy_root.max_hp = 5
	var b := Unit.new(Matrix.new(), Shell.new(enemy_root), Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var tree: Tree = built.tree

	controller.click_cell(Vector2i(5, 5))

	assert_null(controller.selection.selected_unit, "clicking the enemy must not select it")
	assert_null(tree.get_root(), "the inventory panel must never show an enemy's parts")


## runNotes.md: "pare the columns down to part name, condition, and mass."
func test_exactly_three_columns_part_condition_mass() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var tree: Tree = built.tree

	assert_eq(tree.columns, 3)
	assert_eq(tree.get_column_title(InventoryPanel.COL_PART), "Part")
	assert_eq(tree.get_column_title(InventoryPanel.COL_CONDITION), "Condition")
	assert_eq(tree.get_column_title(InventoryPanel.COL_MASS), "Mass")


## runNotes.md: "show all the stats of parts on hover, drawing a new small
## window" — Godot's own per-item tooltip.
## taskblock-07 Pass F1: the tooltip is now the shared TooltipView, driven
## by a real hover (gui_input mouse motion — a Tree has no per-item hover
## signal), not Godot's own plain-text set_tooltip_text().
func test_hovering_a_row_shows_the_full_stat_block_in_its_tooltip() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 8
	torso.max_hp = 10
	torso.material = &"steel"
	torso.mass = 4.0
	torso.bulk = 2.0
	var a := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var tree: Tree = built.tree
	var tooltip_view: TooltipView = built.tooltip_view
	tree.size = Vector2(400, 300)

	controller.click_cell(Vector2i(0, 0))

	var item: TreeItem = tree.get_root().get_child(0)
	var row_rect: Rect2 = tree.get_item_area_rect(item)
	var motion := InputEventMouseMotion.new()
	motion.position = row_rect.position + Vector2(5, row_rect.size.y / 2.0)
	tree.gui_input.emit(motion)
	_reveal(tooltip_view)

	var tooltip: String = tooltip_view._label.text
	assert_true(tooltip.contains("8/10"))
	assert_true(tooltip.contains("steel"))
	assert_true(tooltip.contains("4.0"), "mass must be in the tooltip even though it's dropped")
	assert_true(tooltip.contains("2.0"), "bulk must be in the tooltip since it's not a column")


## runNotes.md: "Mass and Condition are both 5 or less characters, while
## part names are long, adjust the columns to fit that behavior better." —
## Part expands to take whatever's left; Condition/Mass are fixed-width
## and don't expand (Tree exposes no getter for the minimum-width value
## itself, only the setter this drives, so expand behavior is the
## checkable contract here).
func test_condition_and_mass_columns_are_narrow_and_fixed_part_expands() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var tree: Tree = built.tree

	assert_true(tree.is_column_expanding(InventoryPanel.COL_PART))
	assert_false(tree.is_column_expanding(InventoryPanel.COL_CONDITION))
	assert_false(tree.is_column_expanding(InventoryPanel.COL_MASS))


## runNotes.md: "there's a dead top level tree... that doesn't need to be
## shown."
func test_the_tree_hides_its_own_internal_root_row() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var tree: Tree = built.tree

	assert_true(tree.hide_root)


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


## docs/10 taskblock04 E3: "clicking a part in the inventory panel fills
## the same readout with that part's detail" — selecting a row calls
## TacticsController.inspect_part() with that row's own Part.
func test_selecting_a_row_inspects_its_own_part() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var tree: Tree = built.tree
	controller.click_cell(Vector2i(0, 0))

	var item: TreeItem = tree.get_root().get_child(0)
	item.select(InventoryPanel.COL_PART)

	assert_eq(controller.inspected_part, a.shell.root)


## docs/10 taskblock05 C: bidirectional — the controller's own
## highlighted_part drives this row's background, not a click.
func test_a_highlighted_part_tints_its_own_row_and_no_other() -> void:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]
	var a := Unit.new(Matrix.new(), Shell.new(hand), Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var tree: Tree = built.tree
	controller.click_cell(Vector2i(0, 0))

	controller.hover_part(pistol)

	var hand_item: TreeItem = tree.get_root().get_child(0)
	var pistol_item: TreeItem = hand_item.get_child(0)
	var unset := Color(0.0, 0.0, 0.0, 1.0)
	assert_eq(
		pistol_item.get_custom_bg_color(InventoryPanel.COL_PART), HulkTheme.HIGHLIGHT.darkened(0.6)
	)
	assert_eq(
		hand_item.get_custom_bg_color(InventoryPanel.COL_PART), unset, "only the hovered row tints"
	)

	controller.hover_part(null)
	assert_eq(pistol_item.get_custom_bg_color(InventoryPanel.COL_PART), unset)


## docs/10 taskblock05 C: mouse leaving the tree entirely clears the
## highlight — a stale glow must never survive the cursor moving on.
func test_the_mouse_leaving_the_tree_clears_the_highlight() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var tree: Tree = built.tree
	controller.click_cell(Vector2i(0, 0))
	controller.hover_part(a.shell.root)
	assert_not_null(controller.highlighted_part)

	tree.mouse_exited.emit()

	assert_null(controller.highlighted_part)
