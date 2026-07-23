extends GutTest

## tb34 Pass A: `ShotScatter.for_shot` is the one place `range_cells ->
## RangeModel.dartboard_radius_scale -> Dartboard.resolve_scatter` gets
## assembled — every consumer (the drawn board, a fired shot, a burst pull,
## a melee strike) calls this instead of reassembling the chain by hand, so
## the drawn board and the fired board can never again independently
## disagree (the root of BR34's own dartboard-lies bug: the view silently
## dropped the range multiplier the actions never did).


func _shooter(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


func _weapon(effective: float, max_r: float, rings: Array[Ring]) -> Part:
	var weapon := Part.new()
	weapon.id = &"gun"
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.effective_range = effective
	weapon.weapon_def.max_range = max_r
	weapon.scatter = rings
	return weapon


func test_for_shot_matches_full_accuracy_at_or_under_effective_range() -> void:
	var weapon: Part = _weapon(2.0, 8.0, [Ring.new(0.1, 1.0)])
	var shooter := _shooter(Vector2i(0, 0))

	var rings: Array[Ring] = ShotScatter.for_shot(shooter, weapon, Vector2i(2, 0), null)

	assert_almost_eq(rings[0].radius, 0.1, 0.0001, "at effective range, no widening at all")


## The taskblock's own explicit ask: `for_shot` widens past `effective_range`
## and its factor matches `1.0 / RangeModel.accuracy_multiplier` exactly —
## not a re-derivation, the literal reciprocal relationship
## `RangeModel.dartboard_radius_scale` itself is defined as.
func test_for_shot_widens_past_effective_range_matching_one_over_accuracy_multiplier() -> void:
	var weapon: Part = _weapon(2.0, 8.0, [Ring.new(0.1, 1.0)])
	var shooter := _shooter(Vector2i(0, 0))
	var target_cell := Vector2i(8, 0)

	var rings: Array[Ring] = ShotScatter.for_shot(shooter, weapon, target_cell, null)

	var range_cells: int = Grid.distance_chebyshev(shooter.cell, target_cell)
	var expected_scale: float = 1.0 / RangeModel.accuracy_multiplier(weapon, range_cells)
	assert_gt(rings[0].radius, 0.1, "beyond effective range, the ring must widen")
	assert_almost_eq(rings[0].radius, 0.1 * expected_scale, 0.0001)


## The regression this pass exists to make permanently impossible: the
## rings a caller gets from `for_shot` must be identical whether that
## caller is "drawing" or "sampling" — there is no second code path left
## to independently disagree, since both now call the exact same function.
func test_for_shot_gives_the_same_answer_regardless_of_which_consumer_asks() -> void:
	var weapon: Part = _weapon(3.0, 10.0, [Ring.new(0.05, 2.0), Ring.new(0.2, 1.0)])
	var shooter := _shooter(Vector2i(0, 0))
	var target_cell := Vector2i(7, 0)

	var drawn: Array[Ring] = ShotScatter.for_shot(shooter, weapon, target_cell, null)
	var sampled: Array[Ring] = ShotScatter.for_shot(shooter, weapon, target_cell, null)

	assert_eq(drawn.size(), sampled.size())
	for i in range(drawn.size()):
		assert_almost_eq(drawn[i].radius, sampled[i].radius, 0.0001)
		assert_almost_eq(drawn[i].weight, sampled[i].weight, 0.0001)


func test_for_shot_with_an_unauthored_weapon_def_never_widens() -> void:
	var weapon := Part.new()
	weapon.id = &"gun"
	weapon.scatter = [Ring.new(0.1, 1.0)]
	var shooter := _shooter(Vector2i(0, 0))

	var rings: Array[Ring] = ShotScatter.for_shot(shooter, weapon, Vector2i(50, 0), null)

	assert_almost_eq(rings[0].radius, 0.1, 0.0001, "no authored range band -- full accuracy always")
