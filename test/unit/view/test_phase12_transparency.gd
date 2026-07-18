extends GutTest

## docs/08's transparency proof, exercised through the actual Phase 12 UI
## path (not just the pure logic test_transparency_proof.gd already
## covers): the stat panel's predicted damage — what a player would read
## before firing — must equal what the combat log reports once
## TacticsController actually confirms and resolves that shot.


func _armed_unit(cell: Vector2i, squad: int, damage: float) -> Unit:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = damage
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.02, 1.0)]  # tight: lands on the target's one part every time
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
	torso.hp = 1000
	torso.max_hp = 1000
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


func test_the_stat_panels_predicted_damage_equals_the_logs_actual_damage() -> void:
	var shooter := _armed_unit(Vector2i(0, 0), 0, 7.0)
	var target := _armed_unit(Vector2i(2, 0), 1, 3.0)
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])

	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	controller.setup(state, board_view, camera_rig)

	var label := RichTextLabel.new()
	var drill_down := RichTextLabel.new()
	add_child_autofree(label)
	add_child_autofree(drill_down)
	var panel := StatPanel.new()
	add_child_autofree(panel)
	panel.setup(controller, label, drill_down)

	# What the player reads before firing.
	controller.click_cell(shooter.cell)
	var weapon: Part = DeepStrike.find_operable_weapon(shooter)
	var predicted: float = WeaponResolver.resolve_damage(weapon).current
	assert_true(label.text.find("7") != -1, "sanity: the panel must show the predicted damage")

	# Actually fire, through the same click/confirm path a player would use.
	controller.arm_action(&"shoot")
	controller.click_cell(target.cell)  # enters aim mode
	controller.confirm_shot()

	var captured: Array[LogEvent] = []
	controller.turn_ended.connect(
		func(events: Array[LogEvent]) -> void: captured.append_array(events)
	)
	controller.end_turn()

	var impacts: Array[LogEvent] = []
	for event: LogEvent in captured:
		if event.kind == &"impact":
			impacts.append(event)
	assert_eq(impacts.size(), 1, "the tight scatter must land exactly one impact")
	assert_eq(
		float(impacts[0].data.get("damage")),
		predicted,
		"what the panel predicted must be exactly what the log reports for that shot"
	)
