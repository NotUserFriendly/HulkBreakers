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


## BR27.06 investigation: every piece of the step-out pipeline already
## checks out in isolation (TacticsController's own state machine via both
## `click_cell` and a real raycast-driven click; ActionBar's own real
## click-to-arm, correct affordability either way). This is the one thing
## none of those narrower tests cover — the FULL production wiring
## (`SquadControlOverlay._build_ui`'s real `TacticsController`/`ActionBar`/
## `CameraRig` construction and signal wiring), driven the way a real
## player actually would: click the action-bar slot for real
## (`gui_input`), then a real raycast-driven board click on the covered
## enemy — never `tactics.arm_action()`/`tactics.click_cell()` called by
## hand. Same covered-corridor geometry as
## test_tactics_controller_step_out.gd's own `_setup_covered_scene()`.
func _covered_step_out_bout() -> Dictionary:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 5.0
	pistol.ap_cost = 1
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

	var grid := Grid.new(10, 10)
	for x in range(8):
		grid.set_terrain(Vector2i(x, 1), Enums.TerrainType.WALL)
	grid.set_terrain(Vector2i(3, 2), Enums.TerrainType.WALL)
	grid.set_opacity(Vector2i(3, 2), 1.0)

	var shooter := Unit.new(Matrix.new(), Shell.new(torso.duplicate(true)), Vector2i(3, 0), 0)
	var enemy_torso: Part = torso.duplicate(true)
	var enemy_hand: Part = hand.duplicate(true)
	enemy_hand.sockets[0].occupant = pistol.duplicate(true)
	enemy_torso.sockets[0].occupant = enemy_hand
	var enemy := Unit.new(Matrix.new(), Shell.new(enemy_torso), Vector2i(3, 9), 1)

	var state := CombatState.new(grid, [shooter, enemy])
	state.set_squad_controller(0, Enums.SquadController.HUMAN)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]
	return {"state": state, "mission": mission, "shooter": shooter, "enemy": enemy}


func test_the_real_production_wiring_enters_step_out_on_a_covered_enemy() -> void:
	var built: Dictionary = _covered_step_out_bout()
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(built.state, built.mission)
	battle.set_overlay(SquadControlOverlay.new())
	var overlay: SquadControlOverlay = battle.overlay as SquadControlOverlay
	assert_eq(
		built.state.current_unit(), built.shooter, "sanity: the shooter's own turn is current"
	)

	# 1) select the shooter — a real board click, same raycast path as step 3.
	var camera: Camera3D = overlay.tactics.camera
	var shooter_screen: Vector2 = camera.unproject_position(
		Vector3(built.shooter.cell.x, 0.5, built.shooter.cell.y) * UnitGeometry.CELL_SIZE
	)
	var select_click := InputEventMouseButton.new()
	select_click.button_index = MOUSE_BUTTON_LEFT
	select_click.pressed = true
	select_click.position = shooter_screen
	overlay.tactics._unhandled_input(select_click)
	assert_eq(overlay.tactics.selection.selected_unit, built.shooter, "sanity: selection took")

	# 2) arm SHOOT via a real ActionBar slot click — never tactics.arm_action().
	var shoot_index := -1
	for i in range(ActionCatalog.actions_for(built.shooter).size()):
		if ActionCatalog.actions_for(built.shooter)[i].id == &"shoot":
			shoot_index = i
	assert_true(shoot_index >= 0, "sanity: shoot must be a real slot on this unit")
	var panel: PanelContainer = overlay.action_bar._panels[shoot_index]
	var arm_click := InputEventMouseButton.new()
	arm_click.button_index = MOUSE_BUTTON_LEFT
	arm_click.pressed = true
	panel.gui_input.emit(arm_click)
	assert_not_null(overlay.tactics.armed_action, "sanity: the real action-bar click armed it")
	assert_eq(overlay.tactics.armed_action.id, &"shoot")

	# 3) click the covered enemy — a real raycast-driven click, same as
	# production. This is the actual claim under test.
	var enemy_screen: Vector2 = camera.unproject_position(
		Vector3(built.enemy.cell.x, 0.5, built.enemy.cell.y) * UnitGeometry.CELL_SIZE
	)
	var enemy_click := InputEventMouseButton.new()
	enemy_click.button_index = MOUSE_BUTTON_LEFT
	enemy_click.pressed = true
	enemy_click.position = enemy_screen
	overlay.tactics._unhandled_input(enemy_click)

	assert_eq(overlay.tactics.stepping_out_at, built.enemy, "the full real wiring must step out")
	assert_null(overlay.tactics.aiming_at, "a step out never also enters ordinary aim mode")


## taskblock-30: SquadControlOverlay's own debug-gated Inject affordance
## — the "surface a potential method for injection to also work on a
## player-controlled bout" follow-up. Same neutralize-then-swap sequence
## `_squad_control` uses, but WITHOUT its own `advance_turn()` call (that
## belongs only to the ordering tests above — this needs the player's own
## unit reachable as the live current/selectable unit).
func _squad_control_fresh(built: Dictionary) -> SquadControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(built.state, built.mission)
	battle.set_overlay(SquadControlOverlay.new())
	return battle.overlay as SquadControlOverlay


## This harness only ever runs as a debug build (Godot's own editor/CLI
## binary, never a release export) — `OS.is_debug_build()` reads true
## here, so the button must exist. The FALSE branch (a real release
## export) can't be exercised in this harness at all; it's proven
## structurally instead, by test_bout_injector_determinism.gd's own
## source-level gate check.
func test_inject_button_exists_exactly_when_this_is_a_debug_build() -> void:
	var overlay: SquadControlOverlay = _squad_control_fresh(_bout())

	assert_eq(overlay.inject_button != null, OS.is_debug_build())


func test_inject_with_nothing_selected_is_a_noop() -> void:
	var overlay: SquadControlOverlay = _squad_control_fresh(_bout())

	overlay._on_inject_pressed()

	assert_null(overlay._inject_menu, "nothing selected — no target to open the menu against")


func test_inject_with_a_unit_selected_opens_the_menu() -> void:
	var built: Dictionary = _bout()
	var overlay: SquadControlOverlay = _squad_control_fresh(built)
	var current: Unit = built.state.current_unit()
	overlay.tactics.click_cell(current.cell)

	overlay._on_inject_pressed()

	assert_not_null(overlay._inject_menu)
	assert_eq(overlay._inject_menu.item_count, InjectMenu.ITEMS.size())


## The actual claim: SquadControlOverlay's own menu handler calls the
## exact same BoutInjector API programmatic use (and SpectatorOverlay)
## already calls — never a bespoke, player-view-only mutation.
func test_inject_force_current_unit_calls_the_real_bout_injector_api() -> void:
	var built: Dictionary = _bout()
	var overlay: SquadControlOverlay = _squad_control_fresh(built)
	var initially_current: Unit = built.state.current_unit()
	overlay.tactics.click_cell(initially_current.cell)
	assert_eq(overlay.tactics.selection.selected_unit, initially_current, "sanity: selection took")
	var other: Unit = built.ai_unit if initially_current == built.player_unit else built.player_unit

	overlay._on_inject_menu_id_pressed(0, other)

	assert_eq(built.state.current_unit(), other)


## tempnotes review, note 1: "keep was_injected firing in player view... an
## injected player bout is no more a clean seed-replay than an AI one —
## easy to drop when the injection moves overlays." Pinned directly.
func test_inject_sets_was_injected_through_the_player_view_path() -> void:
	var built: Dictionary = _bout()
	var overlay: SquadControlOverlay = _squad_control_fresh(built)
	assert_false(built.state.was_injected, "sanity: a fresh bout is never pre-marked")

	overlay._on_inject_menu_id_pressed(0, built.player_unit)

	assert_true(built.state.was_injected)
