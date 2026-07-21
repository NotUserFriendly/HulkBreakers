extends GutTest

## taskblock-15 Pass A: SingleUnitOverlay — a thin SquadControlOverlay
## variant that drives exactly one unit, auto-selecting it (no click) the
## instant it's its turn, and auto-resolving every other unit via AI.


func _plain_unit(id: StringName, cell: Vector2i, squad_id: int) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var matrix := Matrix.new()
	matrix.id = StringName("%s_link" % id)
	return Unit.new(matrix, Shell.new(torso), cell, squad_id)


## `battle.set_overlay(ControlOverlay.new())` first neutralizes _ready()'s
## own default SquadControlOverlay before `load_battle()` runs — same
## reasoning as test_spectator_overlay.gd's own `_spectate()` helper:
## loading straight into a still-attached SquadControlOverlay would
## trigger ITS OWN advance_ai_turns() reactivity first. `controlled` is
## assigned before `set_overlay()` installs the real overlay, per this
## overlay's own documented "configure, then hand off" contract.
func _wire(units: Array[Unit], controlled: Unit) -> Dictionary:
	var state := CombatState.new(Grid.new(10, 5), units, 7)
	# tb31 Pass B: every squad needs a real (non-UNASSIGNED) controller
	# before a bout can run at all — SingleUnitOverlay's own wants_turn_for
	# never consults it (pure unit-identity), but BoutRunner._init() still
	# validates it regardless of which control paradigm is actually driving.
	state.assign_all_to_human()
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]

	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, mission)
	var overlay := SingleUnitOverlay.new()
	overlay.controlled_unit = controlled
	battle.set_overlay(overlay)
	return {"battle": battle, "overlay": overlay, "state": state}


func test_wants_turn_for_is_true_only_for_the_controlled_unit() -> void:
	var unit_a := _plain_unit(&"a", Vector2i(0, 0), 0)
	var unit_b := _plain_unit(&"b", Vector2i(5, 0), 1)
	var wired: Dictionary = _wire([unit_b, unit_a], unit_a)
	var overlay: SingleUnitOverlay = wired.overlay

	assert_true(overlay.wants_turn_for(unit_a))
	assert_false(overlay.wants_turn_for(unit_b))


## unit_b goes first in turn order and is NOT the controlled unit — its
## whole turn must auto-resolve via UnitAI with no End Turn press, landing
## on unit_a already selected with no click either ("no selection step").
func test_a_non_controlled_units_turn_auto_resolves_and_the_controlled_unit_auto_selects() -> void:
	var unit_a := _plain_unit(&"a", Vector2i(0, 0), 0)
	var unit_b := _plain_unit(&"b", Vector2i(5, 0), 1)
	var wired: Dictionary = _wire([unit_b, unit_a], unit_a)
	var overlay: SingleUnitOverlay = wired.overlay
	var state: CombatState = wired.state

	assert_eq(state.current_unit(), unit_a, "unit_b's own turn must have auto-resolved already")
	assert_eq(overlay.tactics.selection.selected_unit, unit_a, "no click should be needed")


## Safety guard: an overlay installed with no `controlled_unit` assigned
## yet must never auto-drive ANY unit (the unsafe reading — "nothing is
## ever wanted, so auto-resolve everything" — would blow through the
## whole battle the instant this overlay is installed).
func test_an_unconfigured_overlay_never_auto_drives_anything() -> void:
	var unit_a := _plain_unit(&"a", Vector2i(0, 0), 0)
	var unit_b := _plain_unit(&"b", Vector2i(5, 0), 1)
	var state := CombatState.new(Grid.new(10, 5), [unit_b, unit_a], 7)
	state.assign_all_to_human()  # tb31 Pass B: a real controller either way
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]

	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, mission)
	battle.set_overlay(SingleUnitOverlay.new())

	assert_eq(
		state.current_unit(), unit_b, "an unconfigured overlay must never auto-resolve anyone"
	)
