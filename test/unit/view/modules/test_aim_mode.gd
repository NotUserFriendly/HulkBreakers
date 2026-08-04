extends GutTest

## taskblock-57 Pass F — **aim is a mode.**
##
## *"Most modules turn off when the camera drops to over-the-shoulder or sniper view. That is a
## module set, so it is a mode — enter aim, switch; leave, switch back. No suspension mechanism, and
## 'what is visible while aiming' becomes a table entry someone can read."*
##
## ## The assertion that matters most is the one about what SURVIVES
##
## The switch is triggered *by* the aim, so a switch that rebuilt the surface would construct a new
## `UnitInputModule`, a new `TacticsController` and therefore a new `aiming_at` — **destroying the
## aim in order to render it.** That failure would look like "aiming does nothing", which is a long
## way from its cause, so it is pinned directly.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _armed_unit(cell: Vector2i, squad: int) -> Unit:
	return DeepStrike.assemble_reference_humanoid(Matrix.new(), cell, squad)


## A real player-mode surface over a real bout with two units in sight of each other.
func _overlay() -> ControlOverlay:
	var grid: Grid = GridFixture.flat(16, 16)
	var shooter: Unit = _armed_unit(Vector2i(2, 2), 0)
	var target: Unit = _armed_unit(Vector2i(6, 2), 1)
	var state := CombatState.new(grid, [shooter, target])
	state.assign_all_to_human()
	var mission := MissionState.new(RunState.new(), state)
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, mission)
	var overlay: ControlOverlay = ControlOverlay.for_mode(ViewModes.player())
	battle.set_overlay(overlay)
	await get_tree().process_frame
	return overlay


## Drives the real aim entry point rather than poking `aiming_at`, so the mode switch is reached the
## way the game reaches it.
func _start_aiming(overlay: ControlOverlay) -> void:
	var tactics: TacticsController = overlay.tactics()
	var shooter: Unit = overlay.battle.combat_state.units[0]
	var target: Unit = overlay.battle.combat_state.units[1]
	tactics.selection.select(shooter)
	# `arm_action` rather than assigning `armed_action`: it resolves the `ActionDef` off the unit's
	# own catalog, which is the path the action bar takes.
	tactics.arm_action(&"burst")
	tactics._enter_aim_mode(AimTarget.for_unit(target))


# ---------------------------------------------------------------- the table entry


## **THE STATED ACCEPTANCE**: *"the aim mode's module set is a table entry."* Asserted as data, with
## no surface built, because that is the claim — a set someone can read rather than behaviour hidden
## in a host.
func test_the_aim_modes_module_set_is_a_table_entry() -> void:
	var aim: ViewMode = ViewModes.aim()
	assert_eq(aim.id, &"aim")
	assert_eq(aim.modules, ViewModes.AIM_MODULES, "the set IS the constant, not a copy of it")
	gut.p("aim set: %s" % ", ".join(aim.modules))

	# **Most modules turn off**, which is the taskblock's own word and worth asserting as a
	# proportion rather than as a list nobody re-reads.
	var player: ViewMode = ViewModes.player()
	assert_lt(
		aim.modules.size(),
		player.modules.size() / 2,
		"'most modules turn off' -- the aim set must be a small minority of the player set"
	)
	for id: StringName in aim.modules:
		assert_true(
			player.modules.has(id), "%s is in the aim set but not the mode it comes from" % id
		)


## The mode is reachable by id like every other, so `by_id` and `all()` are not a second registry.
func test_the_aim_mode_is_in_the_table_like_every_other_mode() -> void:
	assert_not_null(ViewModes.by_id(&"aim"))
	var ids: Array[StringName] = []
	for mode: ViewMode in ViewModes.all():
		ids.append(mode.id)
	assert_true(ids.has(&"aim"), "all() must list it: %s" % ", ".join(ids))


## **Which mode to switch to is data, not a branch.** Only the mode that can aim names one.
func test_only_a_mode_that_can_aim_names_an_aim_mode() -> void:
	assert_eq(ViewModes.player().aim_mode_id, &"aim")
	assert_eq(ViewModes.spectator().aim_mode_id, &"", "a spectator cannot aim")
	assert_eq(ViewModes.editor().aim_mode_id, &"", "nor does an authoring surface")


# ---------------------------------------------------------------- entering and leaving


## **THE STATED ACCEPTANCE**: *"entering aim switches modes and leaving restores the previous one."*
func test_entering_aim_switches_the_mode_and_leaving_restores_it() -> void:
	var overlay: ControlOverlay = await _overlay()
	assert_eq(overlay.mode.id, &"player", "sanity: it starts in the mode it was built with")

	_start_aiming(overlay)
	await get_tree().process_frame
	assert_eq(overlay.mode.id, &"aim", "entering aim switches the mode")

	overlay.tactics().cancel_aim()
	await get_tree().process_frame
	assert_eq(overlay.mode.id, &"player", "and leaving restores the one it came from")


## **THE STATED ACCEPTANCE**: *"a module absent from the aim set is not mounted while aiming."*
func test_a_module_absent_from_the_aim_set_is_unmounted_while_aiming() -> void:
	var overlay: ControlOverlay = await _overlay()
	assert_not_null(overlay.module(&"action_bar"), "sanity: the bar is up before aiming")

	_start_aiming(overlay)
	await get_tree().process_frame

	for id: StringName in [&"action_bar", &"inspect", &"ui_buttons", &"turn_controls"]:
		assert_false(
			ViewModes.AIM_MODULES.has(id), "fixture: %s must be absent from the aim set" % id
		)
		assert_null(overlay.module(id), "%s is still mounted while aiming" % id)


## And they come back. A switch that unmounts without remounting is a surface that empties out the
## first time anyone aims.
func test_leaving_aim_brings_the_absent_modules_back() -> void:
	var overlay: ControlOverlay = await _overlay()
	_start_aiming(overlay)
	await get_tree().process_frame
	overlay.tactics().cancel_aim()
	await get_tree().process_frame

	for id: StringName in ViewModes.PLAYER_MODULES:
		assert_not_null(overlay.module(id), "%s did not come back after aiming" % id)


# ---------------------------------------------------------------- what must survive the switch


## **THE ASSERTION THIS FILE EXISTS FOR.** The switch is caused by the aim, so a switch that rebuilt
## the surface would replace the `TacticsController` holding `aiming_at` and cancel the aim it was
## reacting to. Identity is checked, not just non-nullness — a fresh controller would pass the
## weaker test and still be the bug.
func test_the_switch_does_not_replace_the_controller_that_owns_the_aim() -> void:
	var overlay: ControlOverlay = await _overlay()
	var before: TacticsController = overlay.tactics()
	var input_before: UnitInputModule = overlay.unit_input()

	_start_aiming(overlay)
	await get_tree().process_frame

	assert_eq(overlay.unit_input(), input_before, "a module in BOTH sets must not be rebuilt")
	assert_eq(overlay.tactics(), before, "the controller holding the aim must be the same object")
	assert_not_null(overlay.tactics().aiming_at, "and the aim itself must have survived the switch")


## The dartboard survives too, and for the same reason: it is owned by a module in both sets. This
## is what the aim mode switches *to*, so losing it would leave a surface with nothing on it.
func test_the_dartboard_survives_and_is_not_a_module() -> void:
	var overlay: ControlOverlay = await _overlay()
	var view_before: AimView = overlay.unit_input().aim_view
	assert_not_null(view_before, "sanity: the aim view exists before aiming")

	_start_aiming(overlay)
	await get_tree().process_frame

	assert_eq(overlay.unit_input().aim_view, view_before, "the same dartboard, not a rebuilt one")
	assert_false(
		ModuleCatalog.IDS.has(&"aim_view"),
		"the aim view must NOT be a module -- the taskblock says so outright"
	)


## A slot published by a module that leaves must leave with it. A `ModuleContext.slots` entry
## pointing at a freed `Control` is a crash with no obvious cause.
func test_a_departing_providers_slots_do_not_outlive_it() -> void:
	var overlay: ControlOverlay = await _overlay()
	assert_true(
		overlay.module_context.slots.has(ModuleSlots.ACTION_BAR_LEFT),
		"sanity: the bar published its slots before aiming"
	)

	_start_aiming(overlay)
	await get_tree().process_frame

	for slot: StringName in ModuleSlots.ACTION_BAR_SLOTS:
		assert_false(
			overlay.module_context.slots.has(slot),
			"%s outlived the action bar that published it" % slot
		)


# ---------------------------------------------------------------- the guard on chrome


## A switch does not rebuild chrome, so two modes with different chromes cannot be switched
## between — every slot under a surviving module would be wrong. Refused loudly, not half-applied.
func test_switching_to_a_mode_with_a_different_chrome_is_refused() -> void:
	var overlay: ControlOverlay = await _overlay()
	var elsewhere := ViewMode.new()
	elsewhere.id = &"a_mode_with_other_chrome"
	elsewhere.chrome = ModeChrome.TOP_LEFT_ROWS
	elsewhere.modules = [] as Array[StringName]

	var before: StringName = overlay.mode.id
	overlay.switch_mode(elsewhere)

	# The refusal is loud on purpose, so the test claims the error rather than tripping over it.
	assert_push_error("switch_mode refused")
	assert_eq(overlay.mode.id, before, "the mode must not have changed")
	assert_not_null(overlay.module(&"action_bar"), "and nothing may have been torn down")
