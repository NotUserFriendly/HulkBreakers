class_name BoutRunner
extends RefCounted

## taskblock-14 Pass C: drives a CombatState turn by turn — the SAME
## UnitAI.plan_turn + CombatState.resolve_until a human's own UI already
## uses for one squad, just called for every AI-driven unit's own turn
## instead. Headless, no timer/view dependency of its own: a watch loop's
## own timer calls `step()` on a cadence for pacing (Pass C's own
## play/pause/step/speed controls); a test can call it in a tight while
## loop instead, same as test_full_mission.gd already does by hand.
##
## taskblock-19 Pass J: "headless vs. viewed, reconciled — one sim,
## optionally observed, never two sims that could disagree." Audited:
## this was already true by construction (taskblock-14/15's own work,
## above) — `GenerateBoutOverlay` builds a bout through the same headless
## `BoutSetup.build_bout()` a test would, `SpectatorOverlay` steps this
## SAME class, and `ResolutionPlayer`/`refresh_unit_views()` only ever
## READ `combat_state` afterward to animate/redraw (never call anything
## that mutates it — `test_playback_never_mutates_the_real_combat_
## states_own_unit_fields` locks that half in directly). No second,
## divergent simulation path was found to merge.
## `test_a_spectated_bout_matches_a_bare_bout_runner_for_the_same_seed`
## (test_spectator_overlay.gd) is the end-to-end regression proving it.
##
## taskblock-15 Pass A: generalized into the ONE turn driver every
## `ControlOverlay` shares ("the turn loop never branches on scene type").
## `wants_turn_for`, if supplied, answers "should THIS caller drive this
## unit instead of the AI" per unit — a `SpectatorOverlay` never supplies
## one (an all-AI bout is exactly this class's original, still-default
## behaviour: `CombatState.controller_for(unit.squad_id) != AI`); a
## `SquadControlOverlay`/`SingleUnitOverlay` supplies one so `step()` stops
## and returns control the instant a human-driven unit comes up, instead
## of only ever recognizing squad-level AI/HUMAN. A bare `Callable` (not a
## `ControlOverlay` reference) keeps this file's own zero-SceneTree-
## dependency intact (CLAUDE.md) — logic never imports a view-layer type.
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
## taskblock-15 Pass B: exactly the events THIS step's own resolve_until
## call emitted — a temporary MemorySink wired and torn down around it,
## the same pattern TacticsController.end_turn() already uses to hand a
## view layer "what just happened" for cosmetic playback. A pure data
## capture, symmetrical with last_unit/last_outcome above — this changes
## nothing about what step() computes or how fast it runs (B0: "never wire
## animation TIMING into BoutRunner or any headless path"); it only
## remembers the same events every other sink on `state.combat_log`
## already saw.
var last_events: Array[LogEvent] = []

## `Callable(unit: Unit) -> bool` — "does someone other than the AI drive
## this unit." An invalid Callable (the default) falls back to today's
## exact squad-controller check, so every existing caller (a bout, this
## class's own tests) is byte-for-byte unaffected.
var _wants_turn_for: Callable


func _init(
	p_state: CombatState,
	p_mission: MissionState,
	p_turn_cap: int = DEFAULT_TURN_CAP,
	p_wants_turn_for: Callable = Callable()
) -> void:
	state = p_state
	mission = p_mission
	turn_cap = p_turn_cap
	_wants_turn_for = p_wants_turn_for


## Resolves one unit's turn if the bout isn't already finished and the
## caller's own `wants_turn_for` (or, absent one, `CombatState.
## controller_for`) says this unit isn't someone else's to drive. Returns
## `finished` either way, so a driver knows whether to keep calling.
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
	var someone_else_wants_it: bool = (
		_wants_turn_for.call(unit)
		if _wants_turn_for.is_valid()
		else state.controller_for(unit.squad_id) != Enums.SquadController.AI
	)
	if someone_else_wants_it:
		return false

	var playstyle: StringName = unit.matrix.playstyle if unit.matrix != null else &"AGGRESSIVE"
	var queue: ActionQueue = UnitAI.plan_turn(unit, state, mission, playstyle)
	last_unit = unit
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	# taskblock-24 Pass C: the mid_move_hook was never wired here at all —
	# `Overwatch.check_trigger` (the same Callable test_reaction_window.gd
	# and every other real trigger test already threads through
	# `resolve_until` by hand) is what makes a HELD overwatch (Pass C: the
	# AI can now genuinely hold one) actually able to fire against a real,
	# moving unit in an ordinary bout — without this, declaring overwatch
	# was a real action with no way to ever actually trigger in AI-vs-AI
	# play, "the dormant layer" in the most literal sense.
	last_outcome = state.resolve_until(queue, Overwatch.check_trigger)
	state.combat_log.remove_sink(sink)
	last_events = sink.events
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
