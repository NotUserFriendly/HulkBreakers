extends GutTest

## taskblock-18 Pass C: turn order within a round is by resolution speed
## (fastest first — the SAME axis Pass A/B use, not a second stat), and a
## band of equal-speed units forms one queryable "simultaneous" group.
## test_combat_state.gd's own existing turn/round tests all use default
## (personal_speed 0.0) matrices, so they're unaffected: with every
## candidate tied on speed, the tie-break falls through to unit.id
## ascending, which for sequentially-auto-assigned ids reproduces the old
## squad-insertion-order walk exactly — these tests are what actually
## exercise the NEW axis.


func _unit(cell: Vector2i, personal_speed: float, squad: int = 0) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	var matrix := Matrix.new()
	matrix.personal_speed = personal_speed
	return Unit.new(matrix, Shell.new(root), cell, squad)


func test_turn_order_is_by_resolution_speed_fastest_first() -> void:
	var slow := _unit(Vector2i(0, 0), 0.0)
	var fast := _unit(Vector2i(1, 0), 25.0)
	var mid := _unit(Vector2i(2, 0), 10.0)
	# Deliberately inserted slowest-first — turn order must reorder it.
	var state := CombatState.new(Grid.new(5, 5), [slow, mid, fast])

	assert_eq(state.current_unit(), fast, "the highest personal_speed unit must act first")
	state.advance_turn()
	assert_eq(state.current_unit(), mid)
	state.advance_turn()
	assert_eq(state.current_unit(), slow)


## The taskblock's own literal phrasing: "a faster unit acts before a
## slower one" — same fact as above, isolated to just two units so the
## claim is as direct as possible.
func test_a_faster_unit_acts_before_a_slower_one() -> void:
	var slow := _unit(Vector2i(0, 0), 2.0)
	var fast := _unit(Vector2i(1, 0), 8.0)
	var state := CombatState.new(Grid.new(5, 5), [slow, fast])

	assert_eq(state.current_unit(), fast)


func test_tied_resolution_speed_breaks_by_unit_id_ascending() -> void:
	var high_id := _unit(Vector2i(0, 0), 5.0)
	high_id.id = 9
	var low_id := _unit(Vector2i(1, 0), 5.0)
	low_id.id = 3
	# Inserted with the higher-id unit first — id tie-break, not insertion
	# order, must decide it.
	var state := CombatState.new(Grid.new(5, 5), [high_id, low_id])

	assert_eq(state.current_unit(), low_id, "unit id 3 must win the tie over unit id 9")


func test_initiative_order_is_deterministic() -> void:
	var orders: Array = []
	for run in range(2):
		var units: Array[Unit] = [
			_unit(Vector2i(0, 0), 3.0), _unit(Vector2i(1, 0), 12.0), _unit(Vector2i(2, 0), 7.0)
		]
		var state := CombatState.new(Grid.new(5, 5), units)
		var order: Array[int] = []
		for i in range(3):
			order.append(state.current_unit().id)
			state.advance_turn()
		orders.append(order)

	assert_eq(orders[0], orders[1])


func test_advance_turn_still_skips_dead_units_under_initiative_order() -> void:
	var slow := _unit(Vector2i(0, 0), 0.0)
	var fast := _unit(Vector2i(1, 0), 25.0)
	var mid := _unit(Vector2i(2, 0), 10.0)
	var state := CombatState.new(Grid.new(5, 5), [slow, mid, fast])
	mid.alive = false

	state.advance_turn()  # fast (current) -> skip dead mid -> slow

	assert_eq(state.current_unit(), slow)


## "A pack of equal-speed units resolves as one simultaneous group" —
## same initiative value, same band, all returned together.
func test_a_pack_of_equal_speed_units_forms_one_simultaneous_group() -> void:
	var a := _unit(Vector2i(0, 0), 10.0)
	var b := _unit(Vector2i(1, 0), 10.0)
	var c := _unit(Vector2i(2, 0), 10.0)
	var loner := _unit(Vector2i(3, 0), 500.0)
	var state := CombatState.new(Grid.new(5, 5), [a, b, c, loner])

	var group: Array[Unit] = state.simultaneous_group(a)

	assert_eq(group, [a, b, c], "the tied trio, ordered fastest-then-id, excluding the outlier")


func test_simultaneous_group_excludes_units_outside_the_band_tolerance() -> void:
	var a := _unit(Vector2i(0, 0), 10.0)
	var just_outside := _unit(Vector2i(1, 0), 10.0 + CombatState.SIMULTANEOUS_BAND_TOLERANCE + 0.5)
	var state := CombatState.new(Grid.new(5, 5), [a, just_outside])

	assert_eq(state.simultaneous_group(a), [a])


func test_simultaneous_group_excludes_the_dead() -> void:
	var a := _unit(Vector2i(0, 0), 10.0)
	var b := _unit(Vector2i(1, 0), 10.0)
	b.alive = false
	var state := CombatState.new(Grid.new(5, 5), [a, b])

	assert_eq(state.simultaneous_group(a), [a])


## "The existing squad-based flows still terminate" — a mixed-speed,
## multi-squad roster keeps cycling fairly (every unit gets turns, round
## number keeps climbing) rather than stalling or fixating on one unit.
func test_a_mixed_speed_multi_squad_roster_keeps_cycling_fairly() -> void:
	var units: Array[Unit] = [
		_unit(Vector2i(0, 0), 0.0, 0),
		_unit(Vector2i(1, 0), 15.0, 0),
		_unit(Vector2i(2, 0), 5.0, 1),
		_unit(Vector2i(3, 0), -5.0, 1)
	]
	var state := CombatState.new(Grid.new(5, 5), units)

	var seen_ids: Dictionary = {}
	for i in range(12):  # 3 full rounds of 4 units each
		seen_ids[state.current_unit().id] = true
		state.advance_turn()

	assert_eq(state.round_number, 3, "12 turns across 4 units must be exactly 3 full rounds")
	for unit: Unit in units:
		assert_true(seen_ids.has(unit.id), "unit %d must have gotten at least one turn" % unit.id)
