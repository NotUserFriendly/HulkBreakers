class_name ShutdownAction
extends CombatAction

## taskblock-22 Pass C: "a unit that cannot move and cannot act can
## shutdown — the player equivalent of matrix ejection, available to both
## sides." Legal for ANY unit at ANY time ("any unit may shutdown — it's a
## choice"); "NPCs use it when they can't move or act" is `UnitAI`'s own
## POLICY for when to queue this, never a legality restriction here — a
## human player can shut a perfectly healthy unit down too, the same way
## nothing stops a human from voluntarily ejecting a matrix.
##
## Deliberately does NOT set `alive = false`: "out of the fight, inert on
## the board... it still occludes/blocks as geometry" — matches
## `Unit.shutdown`'s own doc comment. Free of AP cost, same posture
## `HoldAction`/`EndTurnAction` already have for "this just ends the
## turn," never a tactical maneuver a unit budgets AP around.

var unit: Unit


func _init(p_unit: Unit) -> void:
	unit = p_unit


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	return not actual.shutdown


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	actual.shutdown = true
	var text: String = "ShutdownAction: unit %d shuts down" % actual.id
	state.log_action(text)
	if not state.is_preview:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number, Enums.Phase.RESOLUTION, actual.id, &"shutdown", {}, text
			)
		)
		_trigger_primed_meltdown(actual, state)
	state.advance_turn()


## "A wounded unit that shuts down may trigger its reactor's MELTDOWN if
## the reactor is in that state" — fires only when
## `DamageResolver.trigger_primed_meltdowns` actually finds a live
## countdown; a healthy unit's own shutdown is a complete no-op here.
func _trigger_primed_meltdown(actual: Unit, state: CombatState) -> void:
	for entry: Dictionary in DamageResolver.trigger_primed_meltdowns(actual, state):
		var part: Part = entry.part
		var affected: Array[Unit] = entry.units
		var affected_ids: Array = []
		for affected_unit: Unit in affected:
			affected_ids.append(affected_unit.id)
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				actual.id,
				&"detonate",
				{"source_part": part.id, "units": affected_ids, "cause": "shutdown"},
				"%s meltdown triggered by shutdown" % part.id
			)
		)


func describe() -> String:
	return "ShutdownAction(unit=%d)" % unit.id
