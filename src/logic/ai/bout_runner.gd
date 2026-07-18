class_name BoutRunner
extends RefCounted

## taskblock-14 Pass C: drives an all-AI CombatState turn by turn — the
## SAME UnitAI.plan_turn + CombatState.resolve_until a human's own UI
## already uses for one squad, just called for every squad's own turn
## instead. Headless, no timer/view dependency of its own: a watch
## loop's own timer calls `step()` on a cadence for pacing (Pass C's own
## play/pause/step/speed controls); a test can call it in a tight while
## loop instead, same as test_full_mission.gd already does by hand.
##
## `step()` resolves exactly one unit's WHOLE turn (the natural
## indivisible unit CombatState.resolve_until already works in) — finer,
## true per-action pacing would need CombatState's own resolution loop
## restructured into a step generator, a much bigger change this block
## doesn't ask for. The combat log (already narrating every individual
## impact/consequence) is what gives a watcher per-action detail within
## a turn; `step()`'s own granularity is "whose turn is this," which is
## already watchable at a real pace.
##
## Terminal states, using MissionState's own EXISTING vocabulary,
## unchanged (docs comment there: "never set by 'the enemy squad is
## dead' — that was never an ending"):
## - STRANDED: `mission.is_stranded()` (no living unit on
##   `player_squad_id`) — involuntary, real.
## - EXTRACTED: the surviving squad's own AI naturally reaches this once
##   no enemy remains (UnitAI's existing gather -> extract branch) IF the
##   bout was configured with a real objective/extraction zone.
## - TERMINATED: this runner's own safety net — `turn_cap` guarantees
##   `step()` always eventually returns `finished`, never an infinite
##   loop, by calling the SAME voluntary "give up" `mission.terminate()`
##   a human player could choose, just triggered by the watcher instead.

const DEFAULT_TURN_CAP := 400

var state: CombatState
var mission: MissionState
var turn_cap: int
var turns_taken: int = 0
var finished: bool = false
## The last unit whose turn `step()` resolved, and the `resolve_until`
## outcome it produced — read by a view layer to decide what to frame/
## narrate after each step. Null/empty before the first `step()` call.
var last_unit: Unit = null
var last_outcome: Dictionary = {}


func _init(
	p_state: CombatState, p_mission: MissionState, p_turn_cap: int = DEFAULT_TURN_CAP
) -> void:
	state = p_state
	mission = p_mission
	turn_cap = p_turn_cap


## Resolves one unit's turn if the bout isn't already finished and it's
## an AI-controlled squad's turn (`CombatState.controller_for` — a bout
## sets every squad to AI, per this block's own scope, but this stays
## correct/inert if ever pointed at a mixed human/AI CombatState
## instead). Returns `finished` either way, so a driver knows whether to
## keep calling.
func step() -> bool:
	if finished:
		return true

	if mission.is_stranded():
		mission.strand()
		finished = true
		return true
	if turns_taken >= turn_cap:
		mission.terminate()
		finished = true
		return true

	var unit: Unit = state.current_unit()
	if state.controller_for(unit.squad_id) != Enums.SquadController.AI:
		return false

	var playstyle: StringName = unit.matrix.playstyle if unit.matrix != null else &"AGGRESSIVE"
	var queue: ActionQueue = UnitAI.plan_turn(unit, state, mission, playstyle)
	last_unit = unit
	last_outcome = state.resolve_until(queue)
	turns_taken += 1

	if mission.outcome != Enums.MissionOutcome.UNDECIDED:
		finished = true
	return finished


## Runs `step()` to completion in a tight loop — the headless-test/
## non-visual equivalent of a watch loop's own timer-paced calls. Never
## exceeds `turn_cap` steps (the same guarantee `step()` itself gives).
func run_to_completion() -> void:
	while not step():
		pass
