extends GutTest

## taskblock-07 Pass G/TESTS: "pip counts equal the resolved AP/MP; burning
## 1 AP for MP updates both rows in one step; a unit with 0 of either
## shows an empty row, not a missing one." Pure and headless-testable,
## same split as ActionCatalog/WeaponRows — the view only ever renders
## what this hands it.


func _make_unit(agility: float = 0.0) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	root.stat_mods = {"agility": agility}
	return Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0), 0)


func _count_lit(states: Array[bool]) -> int:
	var count := 0
	for lit: bool in states:
		if lit:
			count += 1
	return count


## "pip counts equal the resolved AP" — the lit count of ap_pip_states
## always equals unit.ap exactly, and the row's own length always equals
## max_ap regardless of how much is spent.
func test_ap_pip_states_length_and_lit_count_match_max_ap_and_ap() -> void:
	var unit := _make_unit()
	unit.max_ap = 6
	unit.ap = 4

	var states: Array[bool] = ApMpPips.ap_pip_states(unit)

	assert_eq(states.size(), 6)
	assert_eq(_count_lit(states), 4)


## "a unit with 0 [AP] shows an empty row, not a missing one" — still
## max_ap slots long, all dim, never an empty array.
func test_ap_pip_states_at_zero_ap_still_returns_max_ap_dim_slots() -> void:
	var unit := _make_unit()
	unit.max_ap = 6
	unit.ap = 0

	var states: Array[bool] = ApMpPips.ap_pip_states(unit)

	assert_eq(states.size(), 6)
	assert_eq(_count_lit(states), 0)


## "pip counts equal the resolved MP."
func test_mp_pip_count_equals_the_units_mp() -> void:
	var unit := _make_unit()
	unit.mp = 3.0

	assert_eq(ApMpPips.mp_pip_count(unit), 3)


## "a unit with 0 [MP] shows an empty row, not a missing one" — 0 is a
## legitimate, meaningful count, not null/omitted.
func test_mp_pip_count_at_zero_mp_is_zero_not_missing() -> void:
	var unit := _make_unit()
	unit.mp = 0.0

	assert_eq(ApMpPips.mp_pip_count(unit), 0)


## taskblock-04 B1 / docs/09: "MP is integral by design... pips are
## exact." mp_pip_count rounds only as the stated last-resort guard — for
## every value this economy actually produces (whole numbers), rounding
## is a no-op.
func test_mp_pip_count_matches_a_whole_mp_value_exactly() -> void:
	var unit := _make_unit()
	unit.mp = 5.0

	assert_eq(ApMpPips.mp_pip_count(unit), 5)


## taskblock-07 G/TESTS: "burning 1 AP for MP updates both rows in one
## step" — driven through a REAL MoveAction resolution (the same fixture
## test_move_action.gd's own "costs right mp and burns ap in chunks" test
## uses), not a synthetic direct field mutation. agility=0 -> mp_per_ap =
## BASE_MP = 2.0.
func test_a_real_move_actions_ap_burn_updates_both_pip_rows_together() -> void:
	var grid := Grid.new(10, 10)
	var unit := _make_unit()
	unit.max_ap = 2
	var state := CombatState.new(grid, [unit])
	# taskblock-08 Pass C grants free starting MP (mp_per_ap()) at turn
	# start — reset to a clean 0 so the AP-burn arithmetic below is
	# exercised from scratch, independent of that grant.
	unit.mp = 0.0

	var before_ap: Array[bool] = ApMpPips.ap_pip_states(unit)
	assert_eq(_count_lit(before_ap), 2)
	assert_eq(ApMpPips.mp_pip_count(unit), 0)

	# One step, starting at mp=0 < step_cost(1) -> burns 1 AP for +2.0 MP,
	# then spends 1 for the step itself: ap=1, mp=1.0.
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var action := MoveAction.new(unit, path)
	assert_true(state.try_apply(action))

	var after_ap: Array[bool] = ApMpPips.ap_pip_states(unit)
	assert_eq(_count_lit(after_ap), 1, "one AP pip must have gone dim")
	assert_eq(ApMpPips.mp_pip_count(unit), 1, "the MP row must show the AP->MP conversion")
