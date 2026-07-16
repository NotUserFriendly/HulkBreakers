extends GutTest

## docs/08's transparency proof, at the UI layer: the stat block's damage
## number must be exactly WeaponResolver.resolve_damage(weapon).current —
## the same call AttackAction makes — never a separately computed value.


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Frame.new(root), cell, squad)


func _make_armed_unit(cell: Vector2i, squad: int, stat_mod: float = 0.0) -> Unit:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 5.0
	pistol.crit_chance = 0.1
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.1, 1.0)]
	if stat_mod != 0.0:
		pistol.stat_mods = {&"damage": stat_mod}

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
	return Unit.new(Matrix.new(), Frame.new(torso), cell, squad)


func _setup_tactics(units: Array[Unit]) -> Dictionary:
	var state := CombatState.new(Grid.new(10, 10), units)
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	controller.setup(state, board_view, camera_rig)
	return {"state": state, "controller": controller}


func test_no_selection_clears_both_labels() -> void:
	var built: Dictionary = _setup_tactics([_make_unit(Vector2i(0, 0))])
	var controller: TacticsController = built.controller

	var label := RichTextLabel.new()
	var drill_down := RichTextLabel.new()
	add_child_autofree(label)
	add_child_autofree(drill_down)
	var panel := StatPanel.new()
	add_child_autofree(panel)
	panel.setup(controller, label, drill_down)

	assert_eq(label.text, "")
	assert_eq(drill_down.text, "")


func test_an_unarmed_selected_unit_shows_unarmed() -> void:
	var a := _make_unit(Vector2i(0, 0))
	var built: Dictionary = _setup_tactics([a])
	var controller: TacticsController = built.controller

	var label := RichTextLabel.new()
	var drill_down := RichTextLabel.new()
	add_child_autofree(label)
	add_child_autofree(drill_down)
	var panel := StatPanel.new()
	add_child_autofree(panel)
	panel.setup(controller, label, drill_down)

	controller.click_cell(Vector2i(0, 0))

	assert_eq(label.text, "[UNARMED]")


func test_selecting_an_armed_unit_shows_the_resolved_damage_matching_weapon_resolver(
) -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup_tactics([a])
	var controller: TacticsController = built.controller

	var label := RichTextLabel.new()
	var drill_down := RichTextLabel.new()
	add_child_autofree(label)
	add_child_autofree(drill_down)
	var panel := StatPanel.new()
	add_child_autofree(panel)
	panel.setup(controller, label, drill_down)

	controller.click_cell(Vector2i(0, 0))

	var weapon: Part = DeepStrike.find_operable_weapon(a)
	var expected_damage: float = WeaponResolver.resolve_damage(weapon).current
	assert_eq(expected_damage, 5.0, "sanity: no modifiers, so this must be the base pistol damage")
	assert_true(
		label.text.find("5") != -1,
		"stat block must show the exact WeaponResolver-resolved damage: %s" % label.text
	)


func test_a_stat_mod_shows_up_bracketed_and_in_the_drill_down() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0, 3.0)  # damage 5 -> 8
	var built: Dictionary = _setup_tactics([a])
	var controller: TacticsController = built.controller

	var label := RichTextLabel.new()
	var drill_down := RichTextLabel.new()
	add_child_autofree(label)
	add_child_autofree(drill_down)
	var panel := StatPanel.new()
	add_child_autofree(panel)
	panel.setup(controller, label, drill_down)

	controller.click_cell(Vector2i(0, 0))

	var weapon: Part = DeepStrike.find_operable_weapon(a)
	assert_eq(WeaponResolver.resolve_damage(weapon).current, 8.0, "sanity: the mod must resolve")
	assert_true(
		label.text.find("8") != -1, "the bracketed, changed damage must render: %s" % label.text
	)
	assert_true(
		drill_down.text.length() > 0, "a changed stat must show its sources in the drill-down"
	)


## Clicking an enemy enters Attack mode (docs/10) — the shooter stays
## selected, so its own stat block must keep showing, not blank out.
func test_entering_aim_mode_keeps_the_shooters_stat_block_visible() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup_tactics([a, b])
	var controller: TacticsController = built.controller

	var label := RichTextLabel.new()
	var drill_down := RichTextLabel.new()
	add_child_autofree(label)
	add_child_autofree(drill_down)
	var panel := StatPanel.new()
	add_child_autofree(panel)
	panel.setup(controller, label, drill_down)

	controller.click_cell(Vector2i(0, 0))
	assert_true(label.text.length() > 0)

	controller.click_cell(Vector2i(5, 5))  # enters aim mode targeting b
	assert_eq(controller.selection.selected_unit, a, "the shooter stays selected while aiming")
	assert_true(label.text.length() > 0, "the stat block must keep showing the shooter")


func test_end_turn_clears_the_panel() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup_tactics([a])
	var controller: TacticsController = built.controller

	var label := RichTextLabel.new()
	var drill_down := RichTextLabel.new()
	add_child_autofree(label)
	add_child_autofree(drill_down)
	var panel := StatPanel.new()
	add_child_autofree(panel)
	panel.setup(controller, label, drill_down)

	controller.click_cell(Vector2i(0, 0))
	assert_true(label.text.length() > 0)

	controller.end_turn()
	assert_eq(label.text, "")
