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


## torso -[HAND]- hand(TRIGGER) -[GRIP]- pistol — the same shape
## test_tactics_controller_arm.gd uses, so the unit actually provides
## &"shoot" through a real, `ap_cost`-bearing part.
func _make_armed_unit(cell: Vector2i, ap_cost: int, squad: int = 0) -> Unit:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 5.0
	pistol.ap_cost = ap_cost
	pistol.scatter = [Ring.new(0.1, 1.0)]
	pistol.provides_actions = [&"shoot"]

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
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


func _setup_bar(unit: Unit) -> Dictionary:
	var state := CombatState.new(Grid.new(10, 10), [unit])
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
	controller.selection.select(unit)

	var bar := ActionBar.new()
	add_child_autofree(bar)
	bar.setup(controller, container, tooltip_view)
	return {"bar": bar, "controller": controller, "container": container}


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


## taskblock-27 Pass D3: "actions clickable without enough AP." An
## unaffordable action's own slot must dim, distinct from both an armed
## slot (HIGHLIGHT) and an ordinary affordable one (FOREGROUND) — but its
## initials still show, unlike a genuinely empty slot.
func test_an_unaffordable_action_dims_but_still_shows_its_initials() -> void:
	var unit: Unit = _make_armed_unit(Vector2i(0, 0), 3)
	var built: Dictionary = _setup_bar(unit)  # CombatState resets ap to max_ap on add
	var bar: ActionBar = built.bar
	var container: HBoxContainer = built.container
	unit.ap = 1  # below the pistol's own ap_cost (3)
	bar.refresh()

	var label: Label = (container.get_child(0) as PanelContainer).get_child(0)
	assert_eq(label.text, "SH", "sanity: shoot's own initials still show")
	assert_eq(label.modulate, HulkTheme.DIM, "unaffordable must dim, not read as ordinarily usable")


func test_an_affordable_action_shows_at_full_foreground() -> void:
	var unit: Unit = _make_armed_unit(Vector2i(0, 0), 1)
	var built: Dictionary = _setup_bar(unit)
	var container: HBoxContainer = built.container

	var label: Label = (container.get_child(0) as PanelContainer).get_child(0)
	assert_eq(label.modulate, HulkTheme.FOREGROUND)


## Clicking an unaffordable slot must not arm it — the disable is real,
## not just cosmetic dimming.
func test_clicking_an_unaffordable_action_does_not_arm_it() -> void:
	var unit: Unit = _make_armed_unit(Vector2i(0, 0), 3)
	var built: Dictionary = _setup_bar(unit)
	var bar: ActionBar = built.bar
	var container: HBoxContainer = built.container
	var controller: TacticsController = built.controller
	unit.ap = 1
	bar.refresh()

	var panel: PanelContainer = container.get_child(0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel.gui_input.emit(click)

	assert_null(controller.armed_action, "an unaffordable action must never arm")


func test_clicking_an_affordable_action_still_arms_it() -> void:
	var unit: Unit = _make_armed_unit(Vector2i(0, 0), 1)
	var built: Dictionary = _setup_bar(unit)
	var container: HBoxContainer = built.container
	var controller: TacticsController = built.controller

	var panel: PanelContainer = container.get_child(0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel.gui_input.emit(click)

	assert_not_null(controller.armed_action)
	assert_eq(controller.armed_action.id, &"shoot")
