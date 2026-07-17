extends GutTest

## docs/10 Phase 12.3, "the signature screen." Fixtures follow
## test_shot_plane.gd's own conventions (a shooter at (2,0) firing +Y).


func _part(id: StringName, box: Box) -> Part:
	var part := Part.new()
	part.id = id
	part.hp = 5
	part.max_hp = 5
	part.volume = [box]
	return part


func _standing_unit(id: StringName, half_width: float, cell: Vector2i) -> Unit:
	var body := _part(id, Box.new(Vector3(0.0, 0.5, 0.0), Vector3(half_width * 2.0, 1.0, 0.6)))
	return Unit.new(Matrix.new(), Shell.new(body), cell)


func _weapon(rings: Array[Ring]) -> Part:
	var weapon := Part.new()
	weapon.id = &"weapon"
	weapon.hp = 1
	weapon.max_hp = 1
	weapon.scatter = rings
	return weapon


## The load-bearing test (PLAN.md Phase 12.3): scrolling changes what's
## being read, never what the reticle actually resolves to.
func test_scrolling_changes_reading_and_never_changes_resolves() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	var far_unit := _standing_unit(&"far", 1.0, Vector2i(2, 6))
	state.add_unit(near_unit)
	state.add_unit(far_unit)
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)
	var reticle := Vector2(0.2, 0.5)  # squarely over the near unit
	var weapon := _weapon([Ring.new(0.1, 1.0)])

	var at_layer_0: AimResult = AimController.resolve(plane, reticle, 0, weapon)
	var at_layer_1: AimResult = AimController.resolve(plane, reticle, 1, weapon)

	assert_eq(at_layer_0.reading, near_unit)
	assert_eq(at_layer_1.reading, far_unit)
	# Each resolve() call builds its own HitResult (docs/09 taskblock06 Pass
	# A), so this compares what it resolved to, not object identity.
	assert_eq(
		at_layer_0.resolves.part, at_layer_1.resolves.part, "scrolling must never change resolves"
	)
	assert_eq(at_layer_0.resolves.part.id, &"near")


func test_layer_index_clamps_instead_of_going_out_of_bounds() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var only_unit := _standing_unit(&"solo", 0.5, Vector2i(2, 2))
	state.add_unit(only_unit)
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)
	var weapon := _weapon([Ring.new(0.1, 1.0)])

	var too_far: AimResult = AimController.resolve(plane, Vector2(0, 0.5), 99, weapon)
	var negative: AimResult = AimController.resolve(plane, Vector2(0, 0.5), -5, weapon)

	assert_eq(too_far.reading, only_unit)
	assert_eq(negative.reading, only_unit)


func test_a_near_body_fully_occluding_a_far_one_never_resolves_to_the_far_body() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 2.0, Vector2i(2, 2))  # wide: spans [-2, 2]
	var far_unit := _standing_unit(&"far", 0.5, Vector2i(2, 6))  # narrow: spans [-0.5, 0.5]
	state.add_unit(near_unit)
	state.add_unit(far_unit)
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)
	var weapon := _weapon([Ring.new(0.1, 1.0)])

	var x := -2.0
	while x <= 2.0:
		var result: AimResult = AimController.resolve(plane, Vector2(x, 0.5), 1, weapon)
		if result.resolves != null:
			assert_ne(
				result.resolves.part.id, &"far", "the near body must fully occlude the far one"
			)
		x += 0.1


## The sniper thread: punch a gap in the near body and a reticle placed in
## it resolves to the far body regardless of which layer is being read.
func test_a_gap_in_the_near_body_lets_the_reticle_resolve_to_the_far_body() -> void:
	var gappy := Part.new()
	gappy.id = &"near"
	gappy.hp = 5
	gappy.max_hp = 5
	gappy.volume = [
		Box.new(Vector3(-1.5, 0.5, 0.0), Vector3(1.0, 1.0, 0.6)),  # left strip
		Box.new(Vector3(1.5, 0.5, 0.0), Vector3(1.0, 1.0, 0.6)),  # right strip, gap at x==0
	]
	var near_unit := Unit.new(Matrix.new(), Shell.new(gappy), Vector2i(2, 2))
	var far_unit := _standing_unit(&"far", 2.0, Vector2i(2, 6))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [near_unit, far_unit])
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)
	var weapon := _weapon([Ring.new(0.1, 1.0)])

	var reading_near: AimResult = AimController.resolve(plane, Vector2(0.0, 0.5), 0, weapon)
	var reading_far: AimResult = AimController.resolve(plane, Vector2(0.0, 0.5), 1, weapon)

	assert_eq(reading_near.reading, near_unit)
	assert_eq(reading_far.reading, far_unit)
	assert_eq(
		reading_near.resolves.part.id,
		&"far",
		"reading the near layer must not change what resolves"
	)
	assert_eq(reading_far.resolves.part.id, &"far")

	var off_the_strip: AimResult = AimController.resolve(plane, Vector2(-1.5, 0.5), 0, weapon)
	assert_eq(off_the_strip.resolves.part.id, &"near")


func test_one_ring_and_five_ring_weapons_render_the_correct_ring_counts() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	state.add_unit(_standing_unit(&"solo", 1.0, Vector2i(2, 2)))
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)

	var one_ring := _weapon([Ring.new(1.0, 1.0)])
	var five_ring := _weapon(
		[
			Ring.new(0.2, 1.0),
			Ring.new(0.4, 1.0),
			Ring.new(0.6, 1.0),
			Ring.new(0.8, 1.0),
			Ring.new(1.0, 1.0),
		]
	)

	assert_eq(AimController.resolve(plane, Vector2(0, 0.5), 0, one_ring).rings.size(), 1)
	assert_eq(AimController.resolve(plane, Vector2(0, 0.5), 0, five_ring).rings.size(), 5)


func test_layer_count_matches_the_number_of_distinct_bodies() -> void:
	var grid := Grid.new(10, 10)
	var state := (
		CombatState
		. new(
			grid,
			[
				_standing_unit(&"a", 0.5, Vector2i(2, 2)),
				_standing_unit(&"b", 0.5, Vector2i(2, 4)),
				_standing_unit(&"c", 0.5, Vector2i(2, 6)),
			]
		)
	)
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)
	var weapon := _weapon([Ring.new(0.1, 1.0)])

	var result: AimResult = AimController.resolve(plane, Vector2(0, 0.5), 0, weapon)
	assert_eq(result.layers.size(), 3)


func test_layers_are_ordered_nearest_first() -> void:
	var grid := Grid.new(10, 10)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	var far_unit := _standing_unit(&"far", 0.5, Vector2i(2, 6))
	var state := CombatState.new(grid, [far_unit, near_unit])  # deliberately out of order
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)

	var layers: Array[AimLayer] = AimController.layers_for(plane)

	assert_eq(layers[0].body, near_unit)
	assert_eq(layers[1].body, far_unit)
