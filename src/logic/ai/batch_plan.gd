class_name BatchPlan
extends RefCounted

## taskblock-43 Pass C: where a batch's shared, ROUND-SCOPED plan lives — the
## leader's chosen destination, recorded once when the leader acts and read by
## every follower in the same batch for the rest of that round.
##
## **Pass C builds the store and the indicator; Pass D is what writes to it
## during planning.** Nothing in the planner records here yet, which is the whole
## point: the next pass gets built against something already testable and already
## visible on the board.
##
## **There is no `leader_id` field on `Unit`, and there must not be one.** Turn
## order is not a static list — `CombatState.advance_turn` calls
## `_fastest_by_initiative(candidates)` afresh each time — so the leader is a
## DERIVED value: **the first member of a batch to take a turn in the current
## round.** That is what `record()` captures, by virtue of being called on the
## first member to plan. Deriving it is what makes leader death free: when the
## leader dies, the next-fastest living member is simply first next round and is
## therefore the leader, with no promotion code, no staleness check, and no field
## to keep in sync across `dup()` or a mid-combat spawn.
##
## **Round-scoped, and staleness is answered by comparison rather than by
## clearing.** Every read passes the current round and gets nothing back if the
## record is from an earlier one, so no round-boundary hook has to remember to
## invalidate anything — a hook that exists is a hook that can be missed. A batch
## whose every member is dead therefore needs no special handling either: its
## record simply stops being refreshed and stops being read.
##
## This is a planner memo, not game state. It records what the AI decided; it
## never feeds back into resolution, and nothing outside planning and the board
## indicator reads it.

## The unit id `leader_id_for` returns when a batch has no plan this round —
## nobody in it has acted yet, or every member is `batch_id == 0`.
const NO_LEADER := -1
## What the board badge shows for a batch's leader, appended to its batch label.
## A member with no marker is a follower.
const LEADER_MARK := "*"

## batch_id(int) -> {"round": int, "leader_id": int, "destination": Vector2i}
var _plans: Dictionary = {}


## Records `leader_id`'s chosen destination as this batch's plan for
## `round_number`. Called by whichever member plans FIRST — a later call in the
## same round is refused rather than overwriting, because the first member to act
## IS the leader and a follower must never redirect the batch mid-manoeuvre.
## Returns true when the record was actually taken.
func record(batch_id: int, round_number: int, leader_id: int, destination: Vector2i) -> bool:
	if batch_id == 0:
		return false
	if not for_batch(batch_id, round_number).is_empty():
		return false
	_plans[batch_id] = {"round": round_number, "leader_id": leader_id, "destination": destination}
	return true


## This batch's plan for `round_number`, or an empty dictionary if it has none —
## never assigned, or assigned in an earlier round and therefore stale.
func for_batch(batch_id: int, round_number: int) -> Dictionary:
	var plan: Variant = _plans.get(batch_id)
	if plan == null:
		return {}
	var record_dict: Dictionary = plan
	if int(record_dict["round"]) != round_number:
		return {}
	return record_dict


## Who is leading `batch_id` this round, or `NO_LEADER` if nobody has acted yet.
func leader_id_for(batch_id: int, round_number: int) -> int:
	var plan: Dictionary = for_batch(batch_id, round_number)
	return int(plan["leader_id"]) if not plan.is_empty() else NO_LEADER


## The board indicator's text for one unit: empty for an independent unit (the
## overwhelming majority, which must stay visually unchanged), `"B2"` for a
## member of batch 2, and `"B2*"` for the member currently leading it.
##
## **A pure string derivation in the logic layer on purpose.** CC cannot see the
## screen, so the DECISION about what the badge says is testable headlessly and
## the view stays thin enough to be obviously correct — it assigns this string to
## a label and does nothing else (CLAUDE.md's golden rule).
func badge_for(unit: Unit, round_number: int) -> String:
	if unit == null or unit.batch_id == 0:
		return ""
	var label: String = "B%d" % unit.batch_id
	if leader_id_for(unit.batch_id, round_number) == unit.id:
		return label + LEADER_MARK
	return label
