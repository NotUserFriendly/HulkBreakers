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
	var state := CombatState.new(GridFixture.flat(12, 5), [player_unit, ai_unit], 1)
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
func _squad_control(built: Dictionary) -> ControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(built.state, built.mission)
	battle.set_overlay(ControlOverlay.for_mode(ViewModes.player()))
	built.state.advance_turn()
	assert_eq(built.state.current_unit(), built.ai_unit, "sanity: setup left this turn untouched")
	return battle.overlay as ControlOverlay


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
	var overlay: ControlOverlay = _squad_control(built)
	# Slow enough that play() genuinely suspends instead of completing
	# inline — the whole point of this test is to observe the MIDDLE of
	# an in-flight animation.
	overlay.module(&"resolution").player.slide_ms = 10000.0
	overlay.module(&"resolution").player.bullet_ms = 10000.0

	overlay.unit_input()._on_turn_ended([_move_event(built.player_unit)])  # deliberately not awaited

	assert_eq(
		built.state.current_unit(),
		built.ai_unit,
		"still mid-animation — the AI batch must not have run yet"
	)


## Once the human's own turn actually finishes animating, the AI batch
## does run — this isn't "AI turns never happen," only "not yet."
func test_ai_turns_advance_once_the_players_own_animation_finishes() -> void:
	var built: Dictionary = _bout()
	var overlay: ControlOverlay = _squad_control(built)
	overlay.module(&"resolution").player.slide_ms = 0.0
	overlay.module(&"resolution").player.bullet_ms = 0.0

	await overlay.unit_input()._on_turn_ended([_move_event(built.player_unit)])

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

	var grid := GridFixture.flat(10, 10)
	# The row-1 wall band the AI-scorer fixtures need
	# (blocking the diagonal shortcut a greedy per-turn scorer would
	# otherwise take) is "irrelevant to TacticsController itself (it never
	# repositions)" per this function's own prior doc comment -- dropped
	# here rather than carried over for fixture parity.
	#
	# taskblock-39 Pass C: shooter/enemy/wall run EAST-WEST (varying x, a
	# fixed row) rather than the AI fixture's own NORTH-SOUTH layout
	# (varying y/z, a fixed column) -- a real placed wall Part (unlike the
	# old flat terrain code) is real 3D geometry the default camera can
	# actually occlude a click through, and this rig's own fixed pitch/yaw
	# makes a north-south line (parallel to the camera's own view axis)
	# the one orientation where an interposed wall's real box can end up
	# BETWEEN the camera and one of the two clicked units instead of
	# strictly between the units themselves. East-west keeps the same
	# wall-blocks-LOS-between-shooter-and-enemy geometry this test needs,
	# without that parallax risk.
	# The wall sits close to the shooter (2 cells away, matching the AI
	# fixture's own shooter(3,0)/wall(3,2) spacing) -- far enough away and
	# a single step off the direct line no longer shifts the ray's own
	# intersection with a lone wall cell enough to clear it, leaving every
	# candidate covered too.
	GridFixture.place_wall(grid, Vector2i(2, 3))  # blocks pathing AND LoS

	var shooter := Unit.new(Matrix.new(), Shell.new(torso.duplicate(true)), Vector2i(0, 3), 0)
	var enemy_torso: Part = torso.duplicate(true)
	var enemy_hand: Part = hand.duplicate(true)
	enemy_hand.sockets[0].occupant = pistol.duplicate(true)
	enemy_torso.sockets[0].occupant = enemy_hand
	var enemy := Unit.new(Matrix.new(), Shell.new(enemy_torso), Vector2i(9, 3), 1)

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
	battle.set_overlay(ControlOverlay.for_mode(ViewModes.player()))
	var overlay: ControlOverlay = battle.overlay as ControlOverlay
	assert_eq(
		built.state.current_unit(), built.shooter, "sanity: the shooter's own turn is current"
	)

	# 1) the shooter is ALREADY selected, and no click is needed to make it so.
	#
	# **taskblock-57 Pass D deleted this step rather than fixing it.** The player mode now
	# pre-selects the unit whose turn it is — *"clicking your own unit every turn is ungainly"* —
	# so the board click this test used to open with is exactly the click the pass removed the need
	# for. Worse, it is now actively wrong: `TacticsController` treats a press on the
	# **already-selected** unit's own body as the start of a facing drag, not as a selection, so
	# replaying it here armed nothing and this test found that first.
	var camera: Camera3D = overlay.tactics().camera
	assert_eq(
		overlay.tactics().selection.selected_unit,
		built.shooter,
		"the shooter is pre-selected at turn start -- no click needed"
	)

	# 2) arm SHOOT via a real ActionBar slot click — never tactics.arm_action().
	var shoot_index := -1
	for i in range(ActionCatalog.actions_for(built.shooter).size()):
		if ActionCatalog.actions_for(built.shooter)[i].id == &"shoot":
			shoot_index = i
	assert_true(shoot_index >= 0, "sanity: shoot must be a real slot on this unit")
	var panel: PanelContainer = overlay.module(&"action_bar").action_bar._panels[shoot_index]
	var arm_click := InputEventMouseButton.new()
	arm_click.button_index = MOUSE_BUTTON_LEFT
	arm_click.pressed = true
	panel.gui_input.emit(arm_click)
	assert_not_null(overlay.tactics().armed_action, "sanity: the real action-bar click armed it")
	assert_eq(overlay.tactics().armed_action.id, &"shoot")

	# 3) click the covered enemy — a real raycast-driven click, same as
	# production. This is the actual claim under test.
	var enemy_screen: Vector2 = camera.unproject_position(
		Vector3(built.enemy.cell.x, 0.5, built.enemy.cell.y) * UnitGeometry.CELL_SIZE
	)
	var enemy_click := InputEventMouseButton.new()
	enemy_click.button_index = MOUSE_BUTTON_LEFT
	enemy_click.pressed = true
	enemy_click.position = enemy_screen
	overlay.tactics()._unhandled_input(enemy_click)

	assert_eq(overlay.tactics().stepping_out_at, built.enemy, "the full real wiring must step out")
	assert_null(overlay.tactics().aiming_at, "a step out never also enters ordinary aim mode")


## taskblock-30: ControlOverlay's own debug-gated Inject affordance
## — the "surface a potential method for injection to also work on a
## player-controlled bout" follow-up. Same neutralize-then-swap sequence
## `_squad_control` uses, but WITHOUT its own `advance_turn()` call (that
## belongs only to the ordering tests above — this needs the player's own
## unit reachable as the live current/selectable unit).
func _squad_control_fresh(built: Dictionary) -> ControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(built.state, built.mission)
	battle.set_overlay(ControlOverlay.for_mode(ViewModes.player()))
	return battle.overlay as ControlOverlay


## This harness only ever runs as a debug build (Godot's own editor/CLI
## binary, never a release export) — `OS.is_debug_build()` reads true
## here, so the button AND panel must exist. The FALSE branch (a real
## release export) can't be exercised in this harness at all; it's proven
## structurally instead, by test_bout_injector_determinism.gd's own
## source-level gate check.
##
## **The UI review moved the way in.** Inject was a button in the top-left cluster; the cluster is
## retired from this mode and the debug menu is reached by the UI-buttons cluster's `DBG` square —
## *"Inject is already in the UI BUTTONS as debug."* What is asserted is unchanged in substance: in
## a debug build there is a panel and a way to open it, and in a release export there is neither.
func test_the_debug_menu_and_its_button_exist_exactly_when_this_is_a_debug_build() -> void:
	var overlay: ControlOverlay = _squad_control_fresh(_bout())
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule

	assert_eq(overlay.debug_panel_module().panel != null, OS.is_debug_build())
	assert_eq(buttons.debug_button != null, OS.is_debug_build())


func test_inject_toggles_the_debug_panels_own_visibility() -> void:
	var overlay: ControlOverlay = _squad_control_fresh(_bout())
	assert_false(overlay.debug_panel_module().panel.visible, "sanity: starts hidden")

	overlay.debug_panel_module().toggle()
	assert_true(overlay.debug_panel_module().panel.visible)

	overlay.debug_panel_module().toggle()
	assert_false(overlay.debug_panel_module().panel.visible)


func test_inject_wires_the_panel_against_the_real_bout_injector_and_tactics() -> void:
	var built: Dictionary = _bout()
	var overlay: ControlOverlay = _squad_control_fresh(built)

	overlay.debug_panel_module().toggle()

	assert_eq(overlay.debug_panel_module().panel.bout_injector, overlay.battle.bout_injector)
	assert_eq(overlay.debug_panel_module().panel.combat_state, built.state)
	assert_eq(overlay.debug_panel_module().panel.input_owner, overlay.tactics())


## **The shared-cluster claim moved to the spectator, which is the only mode that still has one.**
##
## tb31 Pass A made New Battle / Watch / Inject one construction path (`TopLeftControls`), and the
## test read the player view's aliases into it. The UI review retired all three from this mode —
## New Battle outright, Inject into the UI-buttons `DBG` square, Watch into the turn-control column
## — so the claim has no subject here any more. `test_three_bars.gd` asserts the surviving cluster
## is inside the spectator's bar, which is where tb57 G1 put it.
func test_the_player_view_no_longer_carries_a_top_left_cluster() -> void:
	var overlay: ControlOverlay = _squad_control_fresh(_bout())

	assert_null(overlay.module(&"top_left_controls"), "the cluster is retired from the player view")
	var toggle: ControlToggleModule = overlay.module(&"control_toggle") as ControlToggleModule
	assert_not_null(toggle.button, "Watch is the one piece that moved rather than going")
	assert_eq(toggle.button.text, "Watch")


## **Retired with the cluster it measured.** tb31 Pass A asserted the top-left cluster's rect never
## overlapped the debug menu's, because a panel with no anchor used to spawn on that exact corner.
## The player view has no cluster now (the UI review retired it), and the spectator's lives inside
## its bar — where `test_debug_panel_layout.gd` already checks the same non-overlap against the
## surface that still has both. Deleted rather than left asserting against a null.


## **The state moved from the label onto the sheet around it**, and that is the only change: the UI
## review wrapped the legend in a centred panel with a background and an `[x]`, so what is shown or
## hidden is the panel. `ControlsOverlay.is_open()` is the one place either surface reads it, which
## is the property this test has always been about.
func test_keybindings_button_toggles_the_same_state_the_h_key_does() -> void:
	var legend: ControlsLegendModule = (
		_squad_control_fresh(_bout()).module(&"controls_legend") as ControlsLegendModule
	)
	assert_false(legend.controls_overlay.is_open(), "sanity: hidden by default")

	legend.toggle()
	assert_true(legend.controls_overlay.is_open())

	legend.toggle()
	assert_false(legend.controls_overlay.is_open())


## tb31 Pass D: "a PART_PICKER action opens the picker... one path, no
## parallel logic." Same welder/battery/damaged-leg shape
## `test_battle_scene.gd::test_repair_button_queues_and_resolves_a_real_
## repair` already proves resolves correctly end to end — this proves the
## OTHER half: a real click on the action bar's own repair slot actually
## reaches that same `_on_repair_pressed()`, not a standalone button.
func _repair_capable_bout() -> Dictionary:
	var target := Part.new()
	target.id = &"leg"
	target.material = &"steel"
	target.hp = 5
	target.max_hp = 10

	var repair_battery := Part.new()
	repair_battery.id = &"tool_battery"
	repair_battery.hp = 3
	repair_battery.max_hp = 3
	repair_battery.battery_capacity = 6.0
	repair_battery.battery_power_out = 3.0
	repair_battery.battery_charge = 6.0
	repair_battery.tags = [&"POWER_SOURCE", &"BATTERY", &"TOOL_BATTERY"]

	var welder := Part.new()
	welder.id = &"welder"
	welder.hp = 4
	welder.max_hp = 4
	welder.attaches_to = [&"GRIP"]
	welder.requires = {&"TRIGGER": 1}
	welder.tags = [&"WELDER"]
	welder.provides_actions = [&"repair"]
	var battery_socket := Socket.new(&"TOOL_BATTERY")
	battery_socket.occupant = repair_battery
	welder.sockets = [battery_socket]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 4
	hand.max_hp = 4
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = welder
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	var leg_socket := Socket.new(&"LEG")
	leg_socket.occupant = target
	torso.sockets = [hand_socket, leg_socket]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0), 0)
	var state := CombatState.new(GridFixture.flat(10, 10), [unit])
	state.assign_all_to_human()
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.gather_resource(&"steel", 5)
	return {"state": state, "mission": mission}


func test_clicking_the_repair_slot_on_the_action_bar_opens_the_same_picker() -> void:
	var overlay: ControlOverlay = _squad_control_fresh(_repair_capable_bout())
	overlay.tactics().selection.select(overlay.battle.combat_state.units[0])
	overlay.module(&"action_bar").action_bar.refresh()
	assert_null(overlay.unit_input().repair_menu, "sanity: no picker open yet")

	var panel: PanelContainer = overlay.module(&"action_bar").action_bar._panels[0]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel.gui_input.emit(click)

	assert_not_null(
		overlay.unit_input().repair_menu, "the action bar's own repair slot must open the picker"
	)
	assert_eq(overlay.unit_input().repair_menu.item_count, 1, "the one damaged part must be listed")


## Finds `verb_id`'s own row in the panel's live verb table by index —
## `DebugVerbs.all()` is the one authority for ordering; a test must
## never hardcode an index.
func _verb_index(verb_id: StringName) -> int:
	var verbs: Array[DebugVerbSpec] = DebugVerbs.all()
	for i in range(verbs.size()):
		if verbs[i].id == verb_id:
			return i
	fail_test("no verb %s in DebugVerbs.all()" % verb_id)
	return -1


## Drives the panel exactly the way a real Apply press would — select the
## verb, fill in its own param controls by NAME (never by hardcoded
## widget layout), press Apply. The one thing every "the panel is a pure
## wrapper" claim rests on: this never touches BoutInjector directly.
func _apply_via_panel(panel: DebugControlPanel, verb_id: StringName, args: Dictionary) -> void:
	panel._select_verb(_verb_index(verb_id))
	for param_name: String in args:
		var control: Variant = panel._param_controls[param_name]
		var value: Variant = args[param_name]
		if control is Array:
			(control[0] as SpinBox).value = (value as Vector2i).x
			(control[1] as SpinBox).value = (value as Vector2i).y
		elif control is SpinBox:
			(control as SpinBox).value = value
		elif control is LineEdit:
			(control as LineEdit).text = String(value)
		elif control is CheckBox:
			(control as CheckBox).button_pressed = value
	panel._on_apply_pressed()


## The actual claim: ControlOverlay's own panel calls the exact same
## BoutInjector API programmatic use (and SpectatorOverlay) already
## calls — never a bespoke, player-view-only mutation.
func test_inject_panel_force_current_unit_calls_the_real_bout_injector_api() -> void:
	var built: Dictionary = _bout()
	var overlay: ControlOverlay = _squad_control_fresh(built)
	overlay.debug_panel_module().toggle()
	var target: Unit = built.ai_unit

	_apply_via_panel(overlay.debug_panel_module().panel, &"force_current_unit", {"unit": target.id})

	assert_eq(built.state.current_unit(), target)


## tempnotes review, note 1: "keep was_injected firing in player view... an
## injected player bout is no more a clean seed-replay than an AI one —
## easy to drop when the injection moves overlays." Pinned directly.
func test_inject_panel_sets_was_injected_through_the_player_view_path() -> void:
	var built: Dictionary = _bout()
	var overlay: ControlOverlay = _squad_control_fresh(built)
	overlay.debug_panel_module().toggle()
	assert_false(built.state.was_injected, "sanity: a fresh bout is never pre-marked")

	_apply_via_panel(
		overlay.debug_panel_module().panel, &"force_current_unit", {"unit": built.player_unit.id}
	)

	assert_true(built.state.was_injected)


## taskblock-30 follow-up (supervisor report): "spawn unit doesn't create a
## visual model, even though inspect shows it" — same wiring gap as
## SpectatorOverlay's own version of this test; `_on_debug_panel_applied`
## must call `battle.sync_unit_views()`, not just `refresh_unit_views()`,
## in the player-controlled view too.
func test_applying_a_debug_verb_syncs_a_view_for_a_unit_added_mid_bout() -> void:
	var built: Dictionary = _bout()
	var overlay: ControlOverlay = _squad_control_fresh(built)
	overlay.debug_panel_module().toggle()
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	var spawned := Unit.new(Matrix.new(), Shell.new(root), Vector2i(3, 3), 0)
	built.state.add_unit(spawned)
	assert_null(overlay.battle.find_unit_view(spawned.id), "sanity: no view yet")

	overlay.debug_panel_module().panel.applied.emit(&"spawn_unit", {}, [] as Array[LogEvent])

	var view: HitVolumeView = overlay.battle.find_unit_view(spawned.id)
	assert_not_null(view, "the applied handler must sync a view for a unit added mid-bout")
	assert_true(view.get_child_count() > 0)


## taskblock-30 follow-up (supervisor): "spawn object (discrete from spawn
## unit)... currently cover items, and loose parts" — same wiring proof as
## SpectatorOverlay's own version, in the player-controlled view too.
func test_inject_panel_spawn_object_as_cover_calls_the_real_bout_injector_api() -> void:
	var built: Dictionary = _bout()
	var overlay: ControlOverlay = _squad_control_fresh(built)
	overlay.debug_panel_module().toggle()

	_apply_via_panel(
		overlay.debug_panel_module().panel,
		&"spawn_object",
		{"cell": Vector2i(3, 3), "part_id": "scrap_pile", "as_cover": true}
	)

	assert_true(built.state.grid.blockers.has(Vector2i(3, 3)))


## taskblock-30 follow-up (supervisor): "remove can be generalized to
## objects, covers, and things on cells. Fully vanishing it." Same
## real-chain proof as ControlOverlay's own version, in the
## player-controlled view too.
func test_inject_panel_remove_object_on_a_unit_destroys_its_view_and_never_resurrects_it() -> void:
	var built: Dictionary = _bout()
	var overlay: ControlOverlay = _squad_control_fresh(built)
	var player_unit: Unit = built.player_unit
	overlay.debug_panel_module().toggle()
	overlay.debug_panel_module().panel._active = {
		"kind": Enums.HitKind.UNIT, "unit": player_unit, "cell": player_unit.cell
	}

	_apply_via_panel(overlay.debug_panel_module().panel, &"remove_object", {})

	assert_false(player_unit.alive)
	assert_null(overlay.battle.find_unit_view(player_unit.id), "the view must be gone entirely")

	_apply_via_panel(
		overlay.debug_panel_module().panel, &"force_current_unit", {"unit": built.ai_unit.id}
	)

	assert_null(
		overlay.battle.find_unit_view(player_unit.id), "still gone after an unrelated Apply"
	)


## `BR51.21` — **the far end of the injection channel: the events reach the resolution player.**
##
## `DebugControlPanel` captures what a verb caused, `DebugPanelModule` re-publishes it, and
## `PlaybackModule` hands it to `ResolutionModule.play`. This asserts the last hop, which is the
## one that was missing: `_on_verb_applied` called `refresh_status()` and nothing else, so no
## injection ever animated on any path.
##
## **Read synchronously off `_prime`, deliberately.** `ResolutionPlayer.play` is a chain of awaited
## timers, but `_prime(events)` runs before the first of them and seeds `_display_cell` for every
## unit the event list moves. So a test can prove the list arrived without waiting out an animation
## or racing a tween — the same "read the real node back" posture as the camera tests, applied to a
## player's own state rather than a transform.
func test_an_injection_hands_its_events_to_the_resolution_player() -> void:
	var built: Dictionary = _bout()
	var overlay: ControlOverlay = _squad_control(built)
	var resolution: ResolutionModule = overlay.module(&"resolution") as ResolutionModule
	assert_not_null(resolution, "sanity: the player mode mounts a resolution module")
	assert_null(
		overlay.module(&"playback"),
		(
			"sanity, and the whole reason the playback lives on DebugPanelModule: the PLAYER mode "
			+ "mounts no playback module, so a fix routed through that one animates nothing here"
		)
	)
	var unit: Unit = built.player_unit
	resolution.player._display_cell.clear()

	overlay.debug_panel_module().panel.applied.emit(
		&"move_object", {}, [_move_event(unit)] as Array[LogEvent]
	)

	gut.p("primed display cells: %s" % str(resolution.player._display_cell))
	assert_true(
		resolution.player._display_cell.has(unit.id),
		(
			"the injection's own events never reached ResolutionModule.play — this is BR51.21, "
			+ "where the handler refreshed a status line and animated nothing"
		)
	)


## The matching negative, and it is what stops the fix being worse than the bug: a verb that
## changed nothing must NOT start a resolution. `ResolutionPlayer.play` sets its banner and sits
## through `RESOLVE_LEAD_IN` before it looks at the list, so playing an empty one would put a
## visible pause on every Apply press — including the ones that only toggled a readout.
func test_an_injection_that_caused_nothing_does_not_start_a_resolution() -> void:
	var overlay: ControlOverlay = _squad_control(_bout())
	var resolution: ResolutionModule = overlay.module(&"resolution") as ResolutionModule
	resolution.player._display_cell.clear()

	overlay.debug_panel_module().panel.applied.emit(
		&"force_current_unit", {}, [] as Array[LogEvent]
	)

	assert_eq(
		resolution.player._display_cell.size(),
		0,
		"an empty event list must not reach the player at all"
	)


# --- taskblock-61 Pass E5 (BR51.16): the in-game log empties, the file keeps everything ---


## `BR51.16` — **reproduced with a count, which the entry asks for before anything is touched.**
##
## *"Nothing displayed"* versus *"the first N lines are gone"* are different bugs, and the panel's
## own row count against the sink's event count is what says which. This measures both across the
## action that triggers it.
##
## **The trigger is Assume Control.** `BattleScene.toggle_blue_control` calls `set_overlay`, which
## runs `ControlOverlay.teardown()` over every mounted module and builds a fresh set — so
## `CombatLogModule._mount` constructs a new `CombatLogPanel` and a new `HierarchicalUiSink` whose
## `LogFold` has never seen an event. **The `CombatState` and its `CombatLog` are the same object
## throughout**, which is exactly why `out/combat.log` keeps filling: `FileSink` is attached to the
## log, not to the overlay, and nothing tore it down.
##
## `view_modes.gd` already knew about this shape — `AIM_MODULES` keeps `combat_log` mounted with
## the note *"rebuilt empty on remount, so turning it off and on would clear the visible log every
## time anyone aimed."* That kept the aim path safe and left every overlay swap exposed.
func test_assume_control_does_not_empty_the_log_panel_the_stream_still_holds() -> void:
	var built: Dictionary = _bout()
	var overlay: ControlOverlay = _squad_control(built)
	var stream: CombatLog = built.state.combat_log
	var witness := MemorySink.new()
	stream.add_sink(witness)
	for i in range(6):
		stream.emit(LogEvent.new(0, Enums.Phase.RESOLUTION, -1, &"diagnostic", {}, "marker %d" % i))
	var before: String = _log_text(overlay)
	gut.p("before, %d events on the stream:\n%s" % [witness.events.size(), before])
	for i in range(6):
		assert_true(before.contains("marker %d" % i), "sanity: the panel is showing the stream")

	overlay.battle.toggle_blue_control()

	var after: String = _log_text(overlay.battle.overlay as ControlOverlay)
	gut.p("after, %d events on the stream:\n%s" % [witness.events.size(), after])
	assert_gte(
		witness.events.size(),
		6,
		"the stream itself lost nothing — this is why the file on disk stays un-cleared"
	)
	# **Asserted by marker, not by row count.** The swap logs a line or two of its own and the
	# rebuilt panel replays the whole retained history — including events emitted before the
	# original panel ever mounted — so it legitimately shows MORE rows than before. What must not
	# happen is the history vanishing, which is what "resetting to nothing displayed" was.
	for i in range(6):
		assert_true(
			after.contains("marker %d" % i),
			"row 'marker %d' was on screen before Assume Control and must still be" % i
		)


## **The half this fix deliberately does NOT change, recorded because a first draft did.**
##
## Resetting the fold on attach made a new bout start the panel clean, which reads sensible and is
## wrong: `test_battle_scene.gd::test_a_second_bout_logs_its_own_seed_not_the_first_bouts` pins the
## opposite on purpose — several bouts run under one scene and the panel accumulates them, the way
## `FileSink` appends them to one file. **Nobody reported the accumulation as a defect**, and the
## full gate caught the overreach because that test lives in a bout-building file the fast gate
## skips. This pins the behaviour that was kept.
func test_a_new_battle_appends_to_the_panel_rather_than_clearing_it() -> void:
	var overlay: ControlOverlay = _squad_control(_bout())
	var stream: CombatLog = overlay.battle.combat_state.combat_log
	for i in range(4):
		stream.emit(
			LogEvent.new(0, Enums.Phase.RESOLUTION, -1, &"diagnostic", {}, "earlier %d" % i)
		)
	assert_true(_log_text(overlay).contains("earlier 0"), "sanity: the first bout's log is showing")

	var fresh: Dictionary = _bout()
	overlay.battle.load_battle(fresh.state, fresh.mission)

	var rows: String = _log_text(overlay.battle.overlay as ControlOverlay)
	gut.p("after loading a second bout:\n%s" % rows)
	for i in range(4):
		assert_true(
			rows.contains("earlier %d" % i),
			"the previous bout's row 'earlier %d' must still be readable in one scene" % i
		)


## **A replay must not double what the panel already holds.** `rebind()` and
## `BattleScene.load_battle` can both reach `attach_to` for the same log during one load, and
## `add_sink` replays — so without the already-attached guard a single load would show every line
## twice.
func test_attaching_twice_to_the_same_log_does_not_double_the_rows() -> void:
	var built: Dictionary = _bout()
	var overlay: ControlOverlay = _squad_control(built)
	var module: CombatLogModule = overlay.module(&"combat_log") as CombatLogModule
	built.state.combat_log.emit(
		LogEvent.new(0, Enums.Phase.RESOLUTION, -1, &"diagnostic", {}, "once only")
	)
	var before: int = module.sink.lines.size()

	module.attach_to(built.state.combat_log, built.state)
	module.rebind()

	gut.p("%d rows before re-attaching, %d after" % [before, module.sink.lines.size()])
	assert_eq(module.sink.lines.size(), before, "re-attaching the same log must change nothing")


## The rows the combat-log panel is currently showing. Reads `HierarchicalUiSink.lines`, which is
## the sink's own headless surface and is rebuilt on every `emit()` — never the `RichTextLabel`,
## whose draw is deliberately deferred to a frame tick.
func _log_text(overlay: ControlOverlay) -> String:
	var module: ViewModule = overlay.module(&"combat_log")
	if module == null:
		return ""
	return "\n".join((module as CombatLogModule).sink.lines)


# --- taskblock-61 Pass G (BR61.07): the destroyed thing must outlive its own explosion ----


## `BR61.07` — **the board rebuild ran before the animation, so a barrel lost its mesh and the
## detonation then played at an empty cell.**
##
## The supervisor, confirming `BR51.21`: *"Explosion plays, destroyed things disappear before the
## explosion plays."*
##
## `sync_board_view` is a full `BoardView.build()`, and a blocker's mesh comes from
## `UnitGeometry.assembly_placements`, **which emits boxes under a bare `hp > 0`** — so a barrel at
## 0 hp produces no placements and the rebuild drops it.
##
## **Read synchronously, which is what makes the ordering provable.** `_on_debug_panel_applied` now
## awaits `_play_injection`, which suspends inside `ResolutionModule.play`; so when control returns
## here right after the emit, the handler is parked mid-animation and the board sync has not run
## yet. Before the fix the rebuild had already happened by this line, and the barrel's meshes were
## already gone.
func test_a_destroyed_blocker_keeps_its_mesh_until_its_explosion_has_played() -> void:
	var built: Dictionary = _bout()
	var overlay: ControlOverlay = _squad_control(built)
	var state: CombatState = built.state
	var cell := Vector2i(5, 2)
	var injector := BoutInjector.new(state)
	var barrel: Part = DataLibrary.get_part(&"goo_barrel")
	assert_not_null(barrel, "sanity: the shipped volatile barrel must load")
	assert_true(injector.place_cover(cell, &"goo_barrel", {&"goo_barrel": barrel.duplicate(true)}))
	overlay.battle.sync_board_view()
	var drawn_with_barrel: int = _board_mesh_count(overlay.battle)
	assert_gt(drawn_with_barrel, 0, "sanity: the board draws something")

	# Zero the barrel for real, capturing exactly what the verb caused — the same list
	# `DebugControlPanel._capture` would hand to `applied`.
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	assert_true(injector.set_part_hp({"kind": Enums.HitKind.CELL, "cell": cell}, &"", 0))
	state.combat_log.remove_sink(sink)
	var effects: Array[LogEvent] = InjectionEvents.effects(sink.events)
	assert_false(effects.is_empty(), "sanity: a forced detonation has something to animate")

	overlay.debug_panel_module().panel.applied.emit(&"set_part_hp", {}, effects)

	var drawn_while_playing: int = _board_mesh_count(overlay.battle)
	gut.p(
		(
			"%d board meshes before, %d while the explosion plays"
			% [drawn_with_barrel, drawn_while_playing]
		)
	)
	assert_eq(
		drawn_while_playing,
		drawn_with_barrel,
		(
			"the board was rebuilt before the detonation animated, so the barrel's mesh was already "
			+ "gone when its own explosion started — BR61.07"
		)
	)


## A verb that changed the board but animated nothing must NOT be made to wait — `_play_injection`
## returns immediately on an empty list, so the rebuild still lands in the same frame. Without this
## the fix would trade a visual bug for an unresponsive debug panel.
func test_a_board_verb_with_nothing_to_animate_still_rebuilds_immediately() -> void:
	var built: Dictionary = _bout()
	var overlay: ControlOverlay = _squad_control(built)
	var cell := Vector2i(6, 3)
	var barrel: Part = DataLibrary.get_part(&"goo_barrel")
	BoutInjector.new(built.state).place_cover(
		cell, &"goo_barrel", {&"goo_barrel": barrel.duplicate(true)}
	)
	var before: int = _board_mesh_count(overlay.battle)

	overlay.debug_panel_module().panel.applied.emit(&"spawn_object", {}, [] as Array[LogEvent])

	var after: int = _board_mesh_count(overlay.battle)
	gut.p("%d board meshes before the rebuild, %d after" % [before, after])
	assert_true(
		DebugVerbs.affects_board(&"spawn_object"), "sanity: this verb is a board-changing one"
	)
	assert_gt(after, before, "the newly placed barrel must be drawn without waiting for anything")


## Every `MeshInstance3D` under the board view, at any depth — the board's static geometry plus its
## overlays. A count rather than a per-cell lookup: what is being asserted is that the rebuild has
## or has not happened yet, and the rebuild replaces the lot.
func _board_mesh_count(battle: BattleScene) -> int:
	return _count_meshes(battle.board_view)


func _count_meshes(node: Node) -> int:
	var total: int = 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		total += _count_meshes(child)
	return total
