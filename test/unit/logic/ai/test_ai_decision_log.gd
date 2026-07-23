extends GutTest

## tb35 Pass A1: "make cost and decisions into logged numbers, not felt
## ones" — `plan_turn` now emits one `&"ai_decision"` event per unit-turn
## via `AiDecisionLog`. These tests read it back off a real `MemorySink`
## attached to `state.combat_log`, the same sink convention
## `test_combat_log.gd` already uses, never a re-derived expectation of
## what the planner "should" have decided.


func _armed_unit(id: StringName, cell: Vector2i, squad_id: int, weapon_id: StringName) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	if weapon_id != &"":
		var weapon := Part.new()
		weapon.id = weapon_id
		weapon.hp = 3
		weapon.max_hp = 3
		weapon.attaches_to = [&"GRIP"]
		weapon.requires = {&"TRIGGER": 1}
		weapon.damage = 5.0
		weapon.ap_cost = 1
		weapon.provides_actions = [&"shoot"]
		weapon.weapon_def = WeaponDef.new()
		weapon.weapon_def.max_range = 15.0
		weapon.scatter = [Ring.new(0.1, 1.0)]
		var hand := Part.new()
		hand.id = StringName("%s_hand" % id)
		hand.hp = 5
		hand.max_hp = 5
		hand.attaches_to = [&"HAND"]
		hand.capabilities = [&"TRIGGER"]
		var grip := Socket.new(&"GRIP")
		grip.occupant = weapon
		hand.sockets = [grip]
		var hand_socket := Socket.new(&"HAND")
		hand_socket.occupant = hand
		torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)


func test_firing_without_moving_logs_fired_in_place() -> void:
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"rifle")
	var enemy := _armed_unit(&"enemy", Vector2i(3, 0), 1, &"")
	var state := CombatState.new(Grid.new(10, 5), [self_unit, enemy])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	UnitAI.plan_turn(self_unit, state, null)

	var decisions: Array[LogEvent] = sink.events_of_kind(&"ai_decision")
	assert_eq(decisions.size(), 1)
	assert_eq(decisions[0].data.branch, &"fired_in_place")
	assert_true(decisions[0].data.fired)
	assert_false(decisions[0].data.held)


## Same fixture `test_unit_ai.gd`'s own
## `test_an_ai_holds_rather_than_just_facing_when_walled_into_the_allys_line`
## uses — a one-tile-wide corridor with an ally squarely in the only line,
## nowhere to route around. Must hold, and the log must say why.
func test_holding_because_an_ally_blocks_the_line_logs_the_reason() -> void:
	var grid := Grid.new(20, 3)
	for x in range(20):
		grid.set_terrain(Vector2i(x, 0), Enums.TerrainType.WALL)
		grid.set_terrain(Vector2i(x, 2), Enums.TerrainType.WALL)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 1), 0, &"rifle")
	var ally := _armed_unit(&"ally", Vector2i(5, 1), 0, &"")
	var enemy := _armed_unit(&"enemy", Vector2i(10, 1), 1, &"")
	var state := CombatState.new(grid, [self_unit, ally, enemy])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	UnitAI.plan_turn(self_unit, state, null)

	var decisions: Array[LogEvent] = sink.events_of_kind(&"ai_decision")
	assert_eq(decisions.size(), 1)
	assert_false(decisions[0].data.fired)
	assert_true(decisions[0].data.held)
	assert_eq(decisions[0].data.hold_reason, &"ally_in_line")


## `plan_turn`'s own purity/determinism contract must survive the added log
## side effect — same input, same returned queue, regardless of how many
## sinks are attached or how many times it is called.
func test_decision_logging_does_not_disturb_plan_turns_own_determinism() -> void:
	var results: Array = []
	for run in range(2):
		var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"rifle")
		var enemy := _armed_unit(&"enemy", Vector2i(6, 0), 1, &"")
		var state := CombatState.new(Grid.new(10, 5), [self_unit, enemy], 42)
		var sink := MemorySink.new()
		state.combat_log.add_sink(sink)

		var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)
		results.append(queue.actions.map(func(a: CombatAction) -> String: return a.describe()))

	assert_eq(results[0], results[1])
