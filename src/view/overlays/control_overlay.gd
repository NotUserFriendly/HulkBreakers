class_name ControlOverlay
extends Node3D

## taskblock-15 Pass A: base for the four swappable control overlays
## (`SquadControlOverlay`, `SingleUnitOverlay`, `SpectatorOverlay`,
## `GenerateBoutOverlay`). `BattleScene` builds the world — `CameraRig`,
## `BoardView`, one `HitVolumeView` per unit, the combat-log sinks — exactly
## once; an overlay only ever decides HOW input maps to units and WHICH
## units a human drives. It never rebuilds the world, and it's the only
## thing that changes when the same battle is watched instead of played.
##
## The shared turn driver (`BoutRunner`, generalized this pass) never
## branches on which overlay is active: it only ever asks
## `wants_turn_for(unit)`. `wants_turn_for` true for the CURRENT unit means
## this overlay's own UI drives that turn (already wired in `setup()`, the
## same way `TacticsController`'s End Turn button already resolves a turn
## today); false means `UnitAI.plan_turn` drives it instead
## (taskblock-14).


## Wires this overlay's own UI onto the already-built world. Called once,
## right after `BattleScene.set_overlay()` swaps this overlay in.
func setup(_battle: BattleScene) -> void:
	pass


## True if a HUMAN drives `unit`'s turn under this overlay — the one
## question the shared turn driver (`BoutRunner`) ever asks. False means
## `UnitAI.plan_turn` drives it instead. The base default (false, always
## AI) is exactly `SpectatorOverlay`'s and `GenerateBoutOverlay`'s own
## answer — neither overrides this.
func wants_turn_for(_unit: Unit) -> bool:
	return false


## Whatever this overlay's own UI has ALREADY assembled for `unit` — a
## trailing `EndTurnAction` included — never blocks waiting for more
## input: by the time anything calls this, a human has already pressed
## whatever control (End Turn, today) triggered it. Exists for contract
## completeness and headless verification ("what would this overlay
## submit") — the two interactive overlays' own real submission path
## stays their existing, already-proven UI flow
## (`TacticsController.end_turn()`), not a second copy of it routed
## through here. Only ever meaningful when `wants_turn_for(unit)` was
## true for it; the base default (null) matches every overlay that never
## drives a human turn at all.
func build_queue(_unit: Unit, _state: CombatState, _mission: MissionState) -> ActionQueue:
	return null


## Cleans up this overlay's own UI/connections before `BattleScene` swaps
## to a different one (A2: generate-bout -> spectator) or frees it.
func teardown() -> void:
	pass


## The ONE shared "auto-advance AI turns" loop every interactive overlay
## (`SquadControlOverlay`, `SingleUnitOverlay`) drives after its own human
## turn resolves — auto-resolves consecutive units this overlay does NOT
## want (`UnitAI.plan_turn`, taskblock-14) starting at the current unit,
## stopping the instant either the mission reaches a real outcome or a
## unit this overlay DOES want control of comes up. `SpectatorOverlay`
## never calls this — it drives its own `BoutRunner` directly, at its own
## paced cadence, since `wants_turn_for` is unconditionally false there
## anyway. This is the literal, single turn-driver the taskblock asks for:
## every overlay that needs AI auto-advancement shares this one method,
## never a per-overlay reimplementation of it.
func advance_ai_turns(battle: BattleScene) -> void:
	var runner := BoutRunner.new(
		battle.combat_state, battle.mission, BoutRunner.DEFAULT_TURN_CAP, wants_turn_for
	)
	while not runner.finished and not wants_turn_for(battle.combat_state.current_unit()):
		if runner.step():
			break
	battle.refresh_unit_views()
