extends GutTest

## docs/05's tool tiers, priced in AP against the 6 AP baseline.


func test_angle_grinder_costs_a_full_turn() -> void:
	assert_eq(ToolParts.angle_grinder().ap_cost, 6)


func test_metal_saw_replaces_a_hand_and_costs_two_ap() -> void:
	var saw := ToolParts.metal_saw()
	assert_eq(saw.ap_cost, 2)
	assert_true(&"WRIST" in saw.attaches_to, "it takes the socket a hand would use")


func test_power_saw_requires_specialized_integration_and_costs_one_ap_per_limb() -> void:
	var saw := ToolParts.power_saw()
	assert_eq(saw.ap_cost, 1)
	assert_true(&"INTERNAL" in saw.attaches_to)


func test_a_swap_part_action_can_be_priced_directly_from_a_tools_ap_cost() -> void:
	var tool := ToolParts.metal_saw()  # "replaces a hand" -> fits the WRIST a hand would use

	var old_hand := Part.new()
	old_hand.id = &"old_hand"
	old_hand.hp = 5
	old_hand.max_hp = 5
	old_hand.attaches_to = [&"WRIST"]
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = old_hand
	torso.sockets = [wrist]
	var frame := Frame.new(torso)
	frame.max_mass = 1000.0
	var unit := Unit.new(Matrix.new(), frame, Vector2i(0, 0))

	var grid := Grid.new(5, 5)
	grid.field_items[Vector2i(0, 0)] = [tool]
	var state := CombatState.new(grid, [unit])

	var action := SwapPartAction.new(unit, &"torso", &"WRIST", &"metal_saw", tool.ap_cost)
	assert_true(action.is_legal(state))
	action.apply(state)
	assert_eq(unit.ap, unit.max_ap - 2)
