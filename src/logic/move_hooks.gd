class_name MoveHooks
extends RefCounted

## taskblock-19 Pass E: `CombatState.resolve_until`'s own `mid_move_hook`
## slot is single-callable — this composes Suppression's attack-of-
## opportunity check (needs the cell just LEFT, computed here since
## MoveAction.apply_stepwise doesn't pass it) with Overwatch's real
## trigger check (needs the cell just ARRIVED at) into one Callable, so a
## caller wiring one wires both, never two independently-remembered hook
## registrations that could silently drift out of sync. `Overwatch.
## check_trigger`'s own `bool` return (unconditional freeze) still
## propagates untouched — Suppression's own check never forces a stop,
## it only applies its stub hit and keeps going.
##
## Deliberately NOT a `static func combined(unit) -> Callable` one-liner:
## a `Callable` bound to a freshly-`new()`'d RefCounted with no other
## reference does not keep that instance alive in this engine version —
## `SomeClass.new().method` used as a same-expression return value gets
## silently freed before the caller ever invokes it (`Callable.is_valid()`
## reads false, the hook is a no-op — confirmed the hard way, not a
## style guess). Callers must hold the instance in a local for as long as
## the `Callable` is in use, same as any other bound-method callback:
## `var hooks := MoveHooks.new(unit.cell); resolve_until(queue, hooks.check)`.

var _last_cell: Vector2i


func _init(starting_cell: Vector2i) -> void:
	_last_cell = starting_cell


func check(state: CombatState, actual: Unit) -> bool:
	var attackers: Array[Unit] = Suppression.would_trigger_opportunity_attack(
		state, actual, _last_cell, actual.cell
	)
	if not attackers.is_empty():
		Suppression.resolve_opportunity_attacks(state, actual, attackers)
	_last_cell = actual.cell
	return Overwatch.check_trigger(state, actual)
