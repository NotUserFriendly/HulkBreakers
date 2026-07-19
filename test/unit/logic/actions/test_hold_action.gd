extends GutTest

## taskblock-19 Pass F: HoldAction — "a unit with nowhere useful to go can
## wait, taking its turn after the next ally instead," carrying its own
## AP/MP forward with no regeneration.


func _unit(cell: Vector2i, personal_speed: float, squad: int = 0) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	var matrix := Matrix.new()
	matrix.personal_speed = personal_speed
	return Unit.new(matrix, Shell.new(root), cell, squad)


func test_is_legal_true_for_the_current_unit_with_another_living_unit() -> void:
	var a := _unit(Vector2i(0, 0), 10.0)
	var b := _unit(Vector2i(1, 0), 0.0)
	var state := CombatState.new(Grid.new(5, 5), [a, b])

	assert_true(HoldAction.new(a).is_legal(state))


func test_is_legal_false_when_no_other_living_unit_exists() -> void:
	var a := _unit(Vector2i(0, 0), 10.0)
	var state := CombatState.new(Grid.new(5, 5), [a])

	assert_false(HoldAction.new(a).is_legal(state))


func test_is_legal_false_for_a_non_current_unit() -> void:
	var a := _unit(Vector2i(0, 0), 10.0)
	var b := _unit(Vector2i(1, 0), 0.0)
	var state := CombatState.new(Grid.new(5, 5), [a, b])

	assert_false(HoldAction.new(b).is_legal(state))


## taskblock-19 Pass F: "take its turn after the next ally instead."
func test_holding_defers_the_units_turn_to_after_the_next_ally() -> void:
	var a := _unit(Vector2i(0, 0), 10.0)
	var b := _unit(Vector2i(1, 0), 5.0)
	var c := _unit(Vector2i(2, 0), 0.0)
	var state := CombatState.new(Grid.new(5, 5), [a, b, c])
	assert_eq(state.current_unit(), a, "sanity: a acts first")

	HoldAction.new(a).apply(state)

	assert_eq(state.current_unit(), b, "b (the next ally) acts as normal")
	state.advance_turn()  # b ends its own turn
	assert_eq(state.current_unit(), a, "a resumes right after b, not c")
	state.advance_turn()  # a ends its (resumed) turn
	assert_eq(state.current_unit(), c, "normal order continues from there")


## taskblock-19 Pass F: "carries all held AP and MP forward... regenerates
## none."
func test_held_ap_and_mp_carry_forward_exactly() -> void:
	var a := _unit(Vector2i(0, 0), 10.0)
	var b := _unit(Vector2i(1, 0), 0.0)
	var state := CombatState.new(Grid.new(5, 5), [a, b])
	a.ap -= 2
	a.mp = 0.5

	HoldAction.new(a).apply(state)
	state.advance_turn()  # b ends its own turn, a resumes

	assert_eq(state.current_unit(), a)
	assert_eq(a.ap, a.max_ap - 2, "AP carries forward exactly, not refilled")
	assert_almost_eq(a.mp, 0.5, 0.0001, "MP carries forward exactly, not the turn-start grant")


## The negative of the above, stated directly: a fresh (non-held) turn
## DOES regenerate — proving the held case is a real, deliberate exception,
## not just "nothing happened to touch it."
func test_no_regeneration_occurs_while_held_unlike_a_normal_turn() -> void:
	var a := _unit(Vector2i(0, 0), 10.0)
	var b := _unit(Vector2i(1, 0), 0.0)
	var state := CombatState.new(Grid.new(5, 5), [a, b])
	a.ap = 1
	a.mp = 0.0

	HoldAction.new(a).apply(state)
	state.advance_turn()

	assert_eq(state.current_unit(), a)
	assert_lt(a.ap, a.max_ap, "sanity: a real turn-start reset would have refilled this")
	assert_eq(a.ap, 1)


## taskblock-19 Pass F: "a held unit still acts within the same round."
func test_a_held_unit_still_acts_within_the_same_round() -> void:
	var a := _unit(Vector2i(0, 0), 10.0)
	var b := _unit(Vector2i(1, 0), 0.0)
	var state := CombatState.new(Grid.new(5, 5), [a, b])
	var round_at_hold: int = state.round_number

	HoldAction.new(a).apply(state)
	state.advance_turn()  # b ends, a resumes

	assert_eq(state.current_unit(), a)
	assert_eq(state.round_number, round_at_hold, "still the same round, just later in it")


## After the held unit's real, resumed turn ends, the round boundary
## behaves exactly as normal — no lingering hold state left over to
## corrupt the NEXT round.
func test_round_advances_normally_after_a_held_units_resumed_turn_ends() -> void:
	var a := _unit(Vector2i(0, 0), 10.0)
	var b := _unit(Vector2i(1, 0), 0.0)
	var state := CombatState.new(Grid.new(5, 5), [a, b])
	var starting_round: int = state.round_number

	HoldAction.new(a).apply(state)
	state.advance_turn()  # b ends, a resumes
	state.advance_turn()  # a (resumed) ends its own turn for real

	assert_eq(state.round_number, starting_round + 1, "everyone has now gone once")
	assert_eq(state.current_unit(), a, "round 2 starts fresh at the fastest unit again")
	assert_eq(a.ap, a.max_ap, "a genuinely new round DOES reset AP")


func test_holding_is_deterministic_from_the_same_starting_state() -> void:
	var results: Array = []
	for run in range(2):
		var a := _unit(Vector2i(0, 0), 10.0)
		var b := _unit(Vector2i(1, 0), 5.0)
		var c := _unit(Vector2i(2, 0), 0.0)
		var state := CombatState.new(Grid.new(5, 5), [a, b, c])
		HoldAction.new(a).apply(state)
		var order: Array[int] = [state.current_unit().id]
		state.advance_turn()
		order.append(state.current_unit().id)
		state.advance_turn()
		order.append(state.current_unit().id)
		results.append(order)

	assert_eq(results[0], results[1])
