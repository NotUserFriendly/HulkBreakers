extends GutTest

## taskblock-26 Pass B1: "the opposing team appeared to jump to new
## positions before that unit's attack animation resolved." `_on_turn_
## ended` used to call `advance_ai_turns()` (which fast-forwards every AI
## turn with NO animation — a single instant refresh at its own end)
## BEFORE the human's own turn had even started its own animated
## `resolution_player.play()`, and that call wasn't even awaited. Fixed:
## the human's own turn now fully plays out before the AI batch runs.


func _armed_unit(
	id: StringName, cell: Vector2i, squad_id: int, weapon_id: StringName, torso_hp: int = 10
) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = torso_hp
	torso.max_hp = torso_hp
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var weapon := Part.new()
	weapon.id = weapon_id
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 6.0
	weapon.ap_cost = 1
	weapon.provides_actions = [&"shoot"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.max_range = 15.0
	weapon.scatter = [Ring.new(0.1, 1.0)]

	var hand := Part.new()
	hand.id = StringName("%s_hand" % id)
	hand.hp = 4
	hand.max_hp = 4
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)


## `current_unit()` starts as the squad-0 (human) unit — SquadControlOverlay's
## own setup-time `advance_ai_turns()` (`_on_battle_loaded`, fired the
## instant the overlay attaches to an already-loaded battle) reads a
## HUMAN-controlled current unit and correctly no-ops, so setup itself
## never consumes the AI's turn before the test gets to it.
func _bout() -> Dictionary:
	var player_unit := _armed_unit(&"player", Vector2i(0, 0), 0, &"rifle")
	var ai_unit := _armed_unit(&"ai", Vector2i(8, 0), 1, &"pistol")
	var state := CombatState.new(Grid.new(12, 5), [player_unit, ai_unit], 1)
	state.set_squad_controller(0, Enums.SquadController.HUMAN)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]
	return {"state": state, "mission": mission, "player_unit": player_unit, "ai_unit": ai_unit}


## Same neutralize-then-swap sequence test_spectator_overlay.gd's own
## `_spectate` uses: `load_battle` happens against a bare ControlOverlay
## first, so swapping to the REAL overlay under test doesn't retroactively
## trigger ITS OWN battle-loaded reactivity before the test is ready.
## `advance_turn()` afterward simulates what TacticsController's own real
## queue resolution already did before ever emitting `turn_ended` in
## production — the turn has moved on to the AI unit by the time `_on_
## turn_ended` is called, in the test exactly as it is for real.
func _squad_control(built: Dictionary) -> SquadControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(built.state, built.mission)
	battle.set_overlay(SquadControlOverlay.new())
	built.state.advance_turn()
	assert_eq(built.state.current_unit(), built.ai_unit, "sanity: setup left this turn untouched")
	return battle.overlay as SquadControlOverlay


func _move_event(unit: Unit) -> LogEvent:
	return LogEvent.new(
		0,
		Enums.Phase.RESOLUTION,
		unit.id,
		&"move",
		{"path": [unit.cell, unit.cell + Vector2i(1, 0)]},
		"moved"
	)


## The core ordering claim: while the human's own turn is still animating,
## the AI batch must not have run yet — `current_unit()` must still be the
## AI unit `advance_ai_turns` would otherwise have already resolved past.
func test_ai_turns_do_not_advance_until_the_players_own_animation_finishes() -> void:
	var built: Dictionary = _bout()
	var overlay: SquadControlOverlay = _squad_control(built)
	# Slow enough that play() genuinely suspends instead of completing
	# inline — the whole point of this test is to observe the MIDDLE of
	# an in-flight animation.
	overlay.resolution_player.slide_ms = 10000.0
	overlay.resolution_player.bullet_ms = 10000.0

	overlay._on_turn_ended([_move_event(built.player_unit)])  # deliberately not awaited

	assert_eq(
		built.state.current_unit(),
		built.ai_unit,
		"still mid-animation — the AI batch must not have run yet"
	)


## Once the human's own turn actually finishes animating, the AI batch
## does run — this isn't "AI turns never happen," only "not yet."
func test_ai_turns_advance_once_the_players_own_animation_finishes() -> void:
	var built: Dictionary = _bout()
	var overlay: SquadControlOverlay = _squad_control(built)
	overlay.resolution_player.slide_ms = 0.0
	overlay.resolution_player.bullet_ms = 0.0

	await overlay._on_turn_ended([_move_event(built.player_unit)])

	assert_ne(
		built.state.current_unit(),
		built.ai_unit,
		"a fully-finished human turn must let the AI batch actually run"
	)
