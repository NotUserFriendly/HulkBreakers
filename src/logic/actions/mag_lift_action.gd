class_name MagLiftAction
extends CombatAction

## tb62 Pass B: **the third route up, and the only one that spends AP.**
##
## Steps and ladders both spend MP; this spends an action. That is the whole reason it
## exists beside them rather than above them — *steps are cheap and need short rises,
## ladders are slow and need MP, a lift is instant and needs AP.* A free lift would make
## the other two pointless, so the cost is the design, not a tax on it.
##
## ## It is a teleport between a pair, not a traversal
##
## A lift is two `mag_lift`-tagged pads placed by the same generator branch that would have
## stood a ladder: one on the low cell, one on the raised cell it serves. A unit standing on
## either pad pays 1 AP and **is at the other one** — there is no path between them, no
## intermediate position, and nothing to interrupt halfway. `Pathfinder` therefore knows
## nothing about lifts at all: a lift is not an edge, so a route "through" one cannot be
## costed as movement, and pretending otherwise would put a second mover in `move_cost`.
##
## ## It rides down as well as up
##
## The supervisor's call, 2026-08-09, correcting an earlier up-only reading of this action:
## *"Hop down's advantage is that it can happen anywhere, mag lift down is only in a few
## places but is 'cheaper'."* What separates the two verbs is **where they are available**,
## not which direction they run — so a lift that refused to descend was not protecting free
## descent from competition, it was just half a mechanic. `Surface.mag_lift_destination`
## holds the direction-agnostic pairing and the note on what "cheaper" does and does not
## mean in raw numbers.
##
## **No facing to get wrong**, which is the other reason this was worth building now. The
## ladder work kept running into facing — a ladder is a thing on a side of a cell, and a
## blocker's placement cannot carry an orientation yet (`PLAN.md`). A pad is flat and a
## teleport has no direction, so the whole question is absent rather than deferred.

## What one ride costs. **1 AP, from the taskblock — stated, not chosen here.**
const AP_COST: int = 1

const SPEED := 40.0

## Refusal reasons, as an open `StringName` per gate (`PLAN.md`: *"a legality check answers
## a bare boolean, so nothing can report why"*). **This action reports which gate said no**,
## because a lift refusing silently is exactly the defect that item describes: the unit is
## standing on the pad, the pad is visibly there, and "nothing happened" is unactionable.
##
## `REFUSAL_NONE` is the "it is legal" answer, so a caller has one call to make rather than
## a boolean plus a reason that only means something when the boolean is false.
const REFUSAL_NONE: StringName = &""
const REFUSAL_NOT_CURRENT: StringName = &"not_this_units_turn"
const REFUSAL_NO_PAD: StringName = &"no_mag_lift_pad_here"
const REFUSAL_NO_DESTINATION: StringName = &"lift_has_no_partner_pad"
const REFUSAL_LANDING_BLOCKED: StringName = &"partner_pad_is_occupied"
const REFUSAL_NO_AP: StringName = &"not_enough_ap"

var unit: Unit


func _init(p_unit: Unit) -> void:
	unit = p_unit


func is_legal(state: CombatState) -> bool:
	return refusal_reason(state) == REFUSAL_NONE


## **Why this action would refuse, or `REFUSAL_NONE` if it would not.** `is_legal` is this
## compared against nothing, so the boolean and the reason cannot disagree — the failure
## mode `BR32.07` cost three taskblocks was a view re-deriving a refusal and getting a
## different answer from the code that actually decided.
func refusal_reason(state: CombatState) -> StringName:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return REFUSAL_NOT_CURRENT
	if not Surface.has_mag_lift_at(state.grid, actual.cell):
		return REFUSAL_NO_PAD
	var destination: Variant = Surface.mag_lift_destination(state.grid, actual.cell)
	if destination == null:
		return REFUSAL_NO_DESTINATION
	# The landing is a real cell and a unit really arrives on it, so everything that makes a
	# cell unstandable applies — an occupant, a blocker, no floor. `Pathfinder.is_walkable`
	# is the one place that question is answered, and asking it here is what keeps a lift
	# from being the one way into a cell nothing else could enter.
	if not Pathfinder.for_unit(state.grid, actual).is_walkable(destination as Vector2i):
		return REFUSAL_LANDING_BLOCKED
	if actual.ap < AP_COST:
		return REFUSAL_NO_AP
	return REFUSAL_NONE


## **AP only, never converted from MP.** The AP-to-MP conversion runs one way (Appendix E) —
## AP buys MP, MP does not buy AP — so an action costing AP simply costs AP, and a unit with
## movement left and no actions left cannot ride. That is the trade the cost currency exists
## to create.
func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var origin_cell: Vector2i = actual.cell
	var destination: Vector2i = Surface.mag_lift_destination(state.grid, origin_cell) as Vector2i

	actual.ap -= AP_COST
	state.grid.set_occupant_id(actual.cell, -1)
	actual.cell = destination
	state.grid.set_occupant_id(actual.cell, actual.id)
	actual.height = UnitGeometry.true_height_for_cell(actual.cell, state.grid)
	actual.level = actual.height / UnitGeometry.LEVEL_HEIGHT

	# **No re-facing.** A move, a climb and a hop-down all face the way they travelled, which
	# is meaningful because they travelled. A lift has no direction of travel, so turning the
	# unit toward its destination would be inventing a facing the mechanic does not have —
	# and facing is what the unit's armour is presented by, so inventing one is not cosmetic.
	_log(state, actual, origin_cell, destination)


func _log(state: CombatState, actual: Unit, origin_cell: Vector2i, destination: Vector2i) -> void:
	var text: String = (
		"MagLiftAction: unit %d rode the lift from %s to %s" % [actual.id, origin_cell, destination]
	)
	state.log_action(text)
	if state.is_preview:
		return
	(
		state
		. combat_log
		. emit(
			(
				LogEvent
				. new(
					state.round_number,
					Enums.Phase.RESOLUTION,
					actual.id,
					&"mag_lifted",
					# `path`, the same shape a `move`/`climbed` event carries, so
					# `ResolutionPlayer`'s generic slide playback moves the unit with no
					# dedicated animation code. A teleport played as a fast slide is a
					# presentation choice the log does not have to make.
					{
						"cell": destination,
						"cost_ap": AP_COST,
						"path": [origin_cell, destination] as Array[Vector2i],
					},
					"unit %d rode the mag lift to %s" % [actual.id, destination]
				)
			)
		)
	)


func describe() -> String:
	return "MagLiftAction(unit=%d)" % unit.id


func speed(_state: CombatState) -> float:
	return SPEED


func unit_id() -> int:
	return unit.id
