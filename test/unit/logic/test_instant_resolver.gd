extends GutTest

## taskblock-18 Pass B: InstantResolver.resolve_instant() — proven against
## small, self-contained fixture CombatActions rather than the production
## ones (AttackAction/MoveAction/FaceAction all gate is_legal() on "must
## be the CombatState's own current_unit," a single-actor-per-turn
## assumption; threading real, out-of-turn overwatch contenders through
## this resolver is Pass D's own job — leans are explicitly "through the
## B resolver, not a special case" there, not here). These fixtures
## isolate exactly what THIS pass owns: fastest-first popping,
## re-validation after every pop, the tie-break chain, and determinism.


## Legal as long as its own `unit` is still alive (the one invalidation
## condition every case below needs) — `apply()` optionally kills a
## second unit outright, modeling "Zeke's shot kills Andy mid-instant."
class _TestAction:
	extends CombatAction

	var applied: bool = false
	var _unit: Unit
	var _speed: float
	var _kills: Unit

	func _init(p_unit: Unit, p_speed: float, p_kills: Unit = null) -> void:
		_unit = p_unit
		_speed = p_speed
		_kills = p_kills

	func is_legal(state: CombatState) -> bool:
		var actual: Unit = state.find_unit(_unit.id)
		return actual != null and actual.alive

	func apply(state: CombatState) -> void:
		applied = true
		if _kills != null:
			var target: Unit = state.find_unit(_kills.id)
			if target != null:
				state.kill_unit(target)

	func speed(_state: CombatState) -> float:
		return _speed

	func unit_id() -> int:
		return _unit.id


func _unit(id: int, personal_speed: float = 0.0) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	var matrix := Matrix.new()
	matrix.personal_speed = personal_speed
	var built := Unit.new(matrix, Shell.new(torso), Vector2i(id, 0))
	built.id = id
	return built


func test_contenders_resolve_fastest_first() -> void:
	var a: Unit = _unit(0)
	var b: Unit = _unit(1)
	var c: Unit = _unit(2)
	var state := CombatState.new(Grid.new(5, 5), [a, b, c])

	var slow := _TestAction.new(a, 30.0)
	var fast := _TestAction.new(b, 10.0)
	var mid := _TestAction.new(c, 20.0)

	var result: Dictionary = InstantResolver.resolve_instant([slow, mid, fast], state)

	assert_eq(result.resolved, [fast, mid, slow])
	assert_eq(result.dropped, [] as Array[CombatAction])


## The taskblock's own worked case: "Andy leans into a cell Zeke and
## Xavier both overwatch... Zeke fires first; if Zeke kills Andy, Andy's
## queued shot is now illegal and is dropped — no ghost bullet. Xavier
## then resolves against whatever's left." Zeke (speed 5) kills Andy
## before Andy's own queued action (speed 10) ever gets popped; Xavier
## (speed 20, unrelated) still resolves normally afterward.
func test_a_resolution_that_kills_a_contender_drops_that_contenders_own_queued_action() -> void:
	var zeke: Unit = _unit(0)
	var andy: Unit = _unit(1)
	var xavier: Unit = _unit(2)
	var state := CombatState.new(Grid.new(5, 5), [zeke, andy, xavier])

	var zeke_shot := _TestAction.new(zeke, 5.0, andy)
	var andy_shot := _TestAction.new(andy, 10.0)
	var xavier_shot := _TestAction.new(xavier, 20.0)
	# Deliberately queued out of resolution order.
	var contenders: Array[CombatAction] = [andy_shot, xavier_shot, zeke_shot]

	var result: Dictionary = InstantResolver.resolve_instant(contenders, state)

	assert_eq(result.resolved, [zeke_shot, xavier_shot], "Andy's own shot never resolves")
	assert_eq(result.dropped, [andy_shot])
	assert_false(andy_shot.applied, "no ghost bullet — Andy's shot must never actually apply")
	assert_true(zeke_shot.applied)
	assert_true(xavier_shot.applied)
	assert_false(state.find_unit(andy.id).alive)


func test_a_tied_resolution_speed_breaks_by_the_higher_personal_speed() -> void:
	var reflexive: Unit = _unit(0, 20.0)
	var sluggish: Unit = _unit(1, 5.0)
	var state := CombatState.new(Grid.new(5, 5), [reflexive, sluggish])

	# Both fixture actions report the SAME raw speed() — ResolutionSpeed
	# still separates them by each unit's own personal_speed.
	var reflexive_action := _TestAction.new(reflexive, 10.0)
	var sluggish_action := _TestAction.new(sluggish, 10.0)

	var result: Dictionary = InstantResolver.resolve_instant(
		[sluggish_action, reflexive_action], state
	)

	assert_eq(
		result.resolved,
		[reflexive_action, sluggish_action],
		"the higher personal_speed (faster reflexes) must win an exact tie"
	)


func test_a_full_tie_breaks_deterministically_by_unit_id() -> void:
	var high_id: Unit = _unit(5)
	var low_id: Unit = _unit(2)
	var state := CombatState.new(Grid.new(5, 5), [high_id, low_id])

	var action_a := _TestAction.new(high_id, 10.0)
	var action_b := _TestAction.new(low_id, 10.0)

	var order_1: Dictionary = InstantResolver.resolve_instant([action_a, action_b], state)
	var order_2: Dictionary = InstantResolver.resolve_instant([action_b, action_a], state)

	assert_eq(order_1.resolved[0], action_b, "unit id 2 must win the tie over unit id 5")
	assert_eq(order_2.resolved[0], action_b, "the same tie-break regardless of the input order")


func test_the_instant_is_deterministic_across_independent_runs() -> void:
	var results: Array = []
	for run in range(2):
		var zeke: Unit = _unit(0)
		var andy: Unit = _unit(1)
		var xavier: Unit = _unit(2)
		var state := CombatState.new(Grid.new(5, 5), [zeke, andy, xavier])
		var zeke_shot := _TestAction.new(zeke, 5.0, andy)
		var andy_shot := _TestAction.new(andy, 10.0)
		var xavier_shot := _TestAction.new(xavier, 20.0)
		var contenders: Array[CombatAction] = [andy_shot, xavier_shot, zeke_shot]

		var result: Dictionary = InstantResolver.resolve_instant(contenders, state)
		results.append(
			{
				"resolved": result.resolved.map(func(a: CombatAction) -> int: return a.unit_id()),
				"dropped": result.dropped.map(func(a: CombatAction) -> int: return a.unit_id()),
			}
		)

	assert_eq(results[0], results[1])


## "no regression to single-action resolution" — one contender behaves
## exactly like a bare `apply()` would.
func test_a_lone_contender_resolves_unchanged() -> void:
	var unit: Unit = _unit(0)
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var action := _TestAction.new(unit, 10.0)

	var result: Dictionary = InstantResolver.resolve_instant([action], state)

	assert_eq(result.resolved, [action])
	assert_eq(result.dropped, [] as Array[CombatAction])
	assert_true(action.applied)


func test_an_already_illegal_contender_is_dropped_without_resolving() -> void:
	var dead_unit: Unit = _unit(0)
	var state := CombatState.new(Grid.new(5, 5), [dead_unit])
	state.kill_unit(dead_unit)
	var action := _TestAction.new(dead_unit, 10.0)

	var result: Dictionary = InstantResolver.resolve_instant([action], state)

	assert_eq(result.dropped, [action])
	assert_false(action.applied)
