class_name Panic
extends RefCounted

## taskblock-46 Pass D: **what a unit does when the scorer wants nothing at all.**
##
## A utility planner can genuinely rate every option at or below the veto floor —
## a state the branch-cascade planner it replaced could not even express, because a
## cascade always falls through to its last branch whether or not that branch made
## sense. The approach fallback was the first narrow instance of this; this is the
## general one.
##
## ## The label is the point, not the escape
##
## Some escapes are necessarily cheats — shutting down, extracting off an
## extraction tile, teleporting later. **A player who sees one of those unlabelled
## learns the wrong rules about the game**, and starts planning around a mechanic
## that does not exist. An escape hatch nobody can see is also indistinguishable
## from a bug: "the AI just stood there" and "the AI panicked" look identical from
## outside and want completely different responses.
##
## So Panic emits a named event with a **reason**, every time, and the reason is
## the diagnostic: `nothing_offered` says the action pool has a hole in it for this
## unit (`docs/11`'s first failure mode, and `BR45.03`'s mechanism), while
## `all_vetoed` says the pool covered it and every option scored zero. Those want
## different fixes and used to be the same silent shrug.
##
## ## Shutting down is a real answer, and it has to be legal
##
## A stalled unit shutting down is the honest version of "this unit has nothing to
## contribute" — it is visible on the board, it is narratively true, and it stops
## the unit consuming turns. `ShutdownAction.is_legal` refuses an already-shutdown
## unit, so a unit that panics twice falls back to ending its turn rather than
## silently failing to enqueue anything, which is what would stall the board.

## The pool offered this unit nothing at all — no action's preconditions held
## anywhere. **A hole in the action pool**, not a judgement about the situation.
const REASON_NOTHING_OFFERED := &"nothing_offered"
## Actions were offered and every one of them scored at or below the veto floor.
## A real judgement: it looked, and it wanted none of it.
const REASON_ALL_VETOED := &"all_vetoed"
## The turn budget ran out before anything was chosen. Distinct from the other two
## because it is a statement about the CLOCK, not about the board — the same unit
## with more time might well have found something.
const REASON_BUDGET_ABORTED := &"budget_aborted"


## Why this unit found nothing. `offered_count` is how many candidates cleared
## their preconditions; `aborted` is whether the pacer cut the scan short.
##
## Budget first, because a cut-short scan cannot honestly claim to have looked at
## everything — reporting `all_vetoed` for a scan that stopped early would be a
## judgement the planner did not actually make.
static func reason_for(offered_count: int, aborted: bool) -> StringName:
	if aborted:
		return REASON_BUDGET_ABORTED
	return REASON_ALL_VETOED if offered_count > 0 else REASON_NOTHING_OFFERED


## The action a panicking unit takes. `ShutdownAction` when it is legal — a real,
## visible give-up — and `EndTurnAction` otherwise, which is always legal for the
## current unit and therefore always spins the board forward.
##
## **Never returns null.** A panic that produced nothing to enqueue would leave an
## empty queue, and an empty queue never calls `advance_turn`, which stalls the
## whole bout on the one unit that had the least to offer.
##
## ## A unit holding its extraction tile is not stalled, and this was re-learned
##
## `EndTurnAction.is_holding_position` is checked FIRST, because a unit standing on
## its own extraction tile with the objectives done looks identical to a stalled one
## from the scorer's side — nothing is offered, because there is nothing it should
## be doing except stand there. Shutting it down instead takes a unit that was about
## to extract cleanly out of the mission.
##
## The retired planner carried this exact guard and its own comment recording that
## it had been "caught live". Panic re-introduced the bug by preferring shutdown
## without it, and `test_a_winning_bout_runs_to_a_terminal_state` caught it again —
## which is the argument for that test existing rather than for trusting the
## reasoning.
static func action_for(unit: Unit, mission: MissionState, state: CombatState) -> CombatAction:
	if EndTurnAction.is_holding_position(unit, mission):
		return EndTurnAction.new(unit, mission)
	var shutdown := ShutdownAction.new(unit)
	if not unit.shutdown and shutdown.is_legal(state):
		return shutdown
	return EndTurnAction.new(unit, mission)


## Records the panic where a player and a reader can both see it.
##
## Goes to the combat log rather than to the decision log because those answer
## different questions: `ai_utility_decision` says what was considered, and this
## says that the considering came to nothing. A reader scanning for "why did that
## unit do nothing" should not have to reconstruct it from an empty winner index.
static func emit(state: CombatState, unit: Unit, reason: StringName, offered_count: int) -> void:
	state.combat_log.emit(
		LogEvent.new(
			state.round_number,
			Enums.Phase.TACTICS,
			unit.id,
			&"panic",
			{"reason": reason, "offered": offered_count},
			"unit %d panics: %s (%d option(s) offered)" % [unit.id, reason, offered_count]
		)
	)
