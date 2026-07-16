extends GutTest

## runNotes.md: WeaponPanel is a thin renderer over WeaponRows.build() — the
## row content itself is covered headlessly in test_weapon_rows.gd; this
## only checks the label actually gets built from those rows.


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func _make_armed_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 5.0

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


func _setup(units: Array[Unit]) -> Dictionary:
	var state := CombatState.new(Grid.new(10, 10), units)
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	controller.setup(state, board_view, camera_rig)

	var panel := WeaponPanel.new()
	var label := RichTextLabel.new()
	add_child_autofree(panel)
	add_child_autofree(label)
	panel.setup(controller, label)

	return {"controller": controller, "panel": panel, "label": label}


func test_nothing_selected_shows_an_empty_label() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var label: RichTextLabel = built.label

	assert_eq(label.text, "")


func test_an_unarmed_unit_shows_no_weapons_attached() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var label: RichTextLabel = built.label

	controller.click_cell(Vector2i(0, 0))

	assert_true(label.text.contains("no weapons attached"))


func test_an_operable_weapon_appears_without_dimming() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var label: RichTextLabel = built.label

	controller.click_cell(Vector2i(0, 0))

	assert_true(label.text.contains("pistol"))
	assert_false(label.text.contains("[color="), "an active weapon must not be greyed out")


## runNotes.md: "gray out 'inactive' weapons, with a 'why' attached."
func test_an_inactive_weapon_is_dimmed_and_shows_its_reason() -> void:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 5.0  # no TRIGGER-capable manipulator anywhere
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	torso.sockets = [grip]
	var a := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var label: RichTextLabel = built.label

	controller.click_cell(Vector2i(0, 0))

	assert_true(label.text.contains("[color="), "an inactive weapon must be dimmed")
	assert_true(label.text.contains("pistol"))
	assert_true(label.text.contains("TRIGGER"), "the reason must actually be shown")


## runNotes.md: "clicking on a red team unit should show their parts as
## well" — WeaponPanel reads the same sticky inspected_unit InventoryPanel
## does, not the TACTICS-restricted selected_unit.
func test_clicking_a_unit_that_is_not_the_current_turn_still_shows_its_weapons() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var label: RichTextLabel = built.label

	controller.click_cell(Vector2i(5, 5))

	assert_null(controller.selection.selected_unit, "clicking the enemy must not select it")
	assert_true(label.text.contains("pistol"))
