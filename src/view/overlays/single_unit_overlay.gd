class_name SingleUnitOverlay
extends SquadControlOverlay

## taskblock-15 Pass A: "controls exactly one unit... clicks act on that
## unit implicitly; no selection step." A thin variant of
## `SquadControlOverlay` — inherits its whole UI/TacticsController wiring
## verbatim (scope fence: "no new tactical abilities," so this is
## control-plumbing on top of the existing panels, never a second input
## system) — narrowing `wants_turn_for` from "this unit's whole squad is
## HUMAN" down to "this exact unit," and auto-selecting that unit the
## instant it becomes the current one, so a player never has to click
## their own body first.
##
## `controlled_unit` must be set BEFORE `BattleScene.set_overlay()`
## installs this overlay (its own `setup()`/`_on_battle_loaded()` may
## already auto-drive several units' worth of turns via
## `advance_ai_turns()` before this script gets a chance to run again) —
## the same "configure, then hand off" convention `GenerateBoutOverlay`
## itself follows for its own fields.

var controlled_unit: Unit


## Unset (null) never means "auto-drive everything" — that would blow
## through the whole battle the instant this overlay is installed before
## a caller gets around to assigning `controlled_unit`. It means "nothing
## configured yet, drive nothing automatically," the same fail-safe
## direction every other unconfigured-input case in this codebase takes.
func wants_turn_for(unit: Unit) -> bool:
	if controlled_unit == null:
		return true
	return unit == controlled_unit


func _on_battle_loaded() -> void:
	super._on_battle_loaded()
	_auto_select_if_current()


func _on_turn_ended(events: Array[LogEvent]) -> void:
	# tb32 Pass D (BR27.07 compounding bug): `super._on_turn_ended()` now
	# awaits the resolution animation before flipping the active-turn
	# indicator (SquadControlOverlay's own fix) — called without `await`
	# here, that coroutine was left to run in the background while
	# `_auto_select_if_current()` raced ahead of it immediately.
	await super._on_turn_ended(events)
	_auto_select_if_current()


func _auto_select_if_current() -> void:
	if controlled_unit == null:
		return
	if battle.combat_state.current_unit() == controlled_unit:
		tactics.selection.select(controlled_unit)
