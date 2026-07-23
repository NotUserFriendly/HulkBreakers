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


## docs/09 taskblock07 Pass A: resolve()'s own `shooter: Unit` — a plain
## torso is enough (UnitGeometry.muzzle_point falls back to the unit's own
## cell when the weapon has no placement in its shell, exactly the case
## here — the weapon fixtures below are bare, unattached Parts).
func _shooter_unit(cell: Vector2i) -> Unit:
	return _standing_unit(&"shooter", 0.5, cell)


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
	var shooter := _shooter_unit(Vector2i(2, 0))

	var at_layer_0: AimResult = AimController.resolve(
		plane, reticle, 0, weapon, shooter, far_unit.cell, state
	)
	var at_layer_1: AimResult = AimController.resolve(
		plane, reticle, 1, weapon, shooter, far_unit.cell, state
	)

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
	var shooter := _shooter_unit(Vector2i(2, 0))

	var too_far: AimResult = AimController.resolve(
		plane, Vector2(0, 0.5), 99, weapon, shooter, only_unit.cell, state
	)
	var negative: AimResult = AimController.resolve(
		plane, Vector2(0, 0.5), -5, weapon, shooter, only_unit.cell, state
	)

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
	var shooter := _shooter_unit(Vector2i(2, 0))

	var x := -2.0
	while x <= 2.0:
		var result: AimResult = AimController.resolve(
			plane, Vector2(x, 0.5), 1, weapon, shooter, far_unit.cell, state
		)
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
	var shooter := _shooter_unit(Vector2i(2, 0))

	var reading_near: AimResult = AimController.resolve(
		plane, Vector2(0.0, 0.5), 0, weapon, shooter, far_unit.cell, state
	)
	var reading_far: AimResult = AimController.resolve(
		plane, Vector2(0.0, 0.5), 1, weapon, shooter, far_unit.cell, state
	)

	assert_eq(reading_near.reading, near_unit)
	assert_eq(reading_far.reading, far_unit)
	assert_eq(
		reading_near.resolves.part.id,
		&"far",
		"reading the near layer must not change what resolves"
	)
	assert_eq(reading_far.resolves.part.id, &"far")

	# docs/09 taskblock07 Pass A: `reticle` is anchored at `target_cell`'s
	# own depth (AimPlaneGeometry.world_point's convention) — a REAL ray
	# from the muzzle necessarily diverges less at a shallower depth than
	# at a deeper one (perspective, not the old orthographic plane-space
	# lookup a fixed lateral offset used to mean at every depth alike).
	# Anchoring at near_unit's OWN cell, rather than far_unit's, is what
	# makes "-1.5" actually land on its left strip.
	var off_the_strip: AimResult = AimController.resolve(
		plane, Vector2(-1.5, 0.5), 0, weapon, shooter, near_unit.cell, state
	)
	assert_eq(off_the_strip.resolves.part.id, &"near")


func test_one_ring_and_five_ring_weapons_render_the_correct_ring_counts() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var solo := _standing_unit(&"solo", 1.0, Vector2i(2, 2))
	state.add_unit(solo)
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)
	var shooter := _shooter_unit(Vector2i(2, 0))

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

	assert_eq(
		(
			AimController
			. resolve(plane, Vector2(0, 0.5), 0, one_ring, shooter, solo.cell, state)
			. rings
			. size()
		),
		1
	)
	assert_eq(
		(
			AimController
			. resolve(plane, Vector2(0, 0.5), 0, five_ring, shooter, solo.cell, state)
			. rings
			. size()
		),
		5
	)


## tb34 Pass A (BR34's own root bug): the drawn board used to be flat
## 1.0x accuracy always — `resolve()` called `Dartboard.resolve_scatter`
## with no range multiplier at all, while every real shot (`AttackAction`/
## `BurstAction`) widened correctly with range. Asserted directly against
## `ShotScatter.for_shot` (the SAME primitive `resolve()` itself now calls),
## never a second re-derivation of the range math — the whole point is
## that the two can no longer independently disagree, by construction.
func test_resolve_widens_the_drawn_rings_to_match_a_fired_shots_scatter() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var far_unit := _standing_unit(&"far", 0.5, Vector2i(2, 8))
	state.add_unit(far_unit)
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)
	var shooter := _shooter_unit(Vector2i(2, 0))
	var weapon := _weapon([Ring.new(0.1, 1.0)])
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.effective_range = 2.0
	weapon.weapon_def.max_range = 10.0

	var result: AimResult = AimController.resolve(
		plane, Vector2(0, 0.5), 0, weapon, shooter, far_unit.cell, state
	)
	var expected: Array[Ring] = ShotScatter.for_shot(shooter, weapon, far_unit.cell, state)

	assert_gt(result.rings[0].radius, 0.1, "the drawn board must widen beyond effective range")
	assert_almost_eq(result.rings[0].radius, expected[0].radius, 0.0001)


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
	var shooter := _shooter_unit(Vector2i(2, 0))

	var result: AimResult = AimController.resolve(
		plane, Vector2(0, 0.5), 0, weapon, shooter, Vector2i(2, 6), state
	)
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


## docs/09 taskblock07 Pass A/TESTS: "the aim UI's RESOLVES equals
## resolve_ray for a corpus of reticle positions" — resolve()'s own
## `.resolves` must always agree with an independently-constructed
## resolve_ray call built the exact same way (muzzle_point + ray_from_muzzle
## + resolve_ray), never a second, drifted answer.
func test_resolves_equals_resolve_ray_for_a_corpus_of_reticle_positions() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	var far_unit := _standing_unit(&"far", 1.0, Vector2i(2, 6))
	state.add_unit(near_unit)
	state.add_unit(far_unit)
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)
	var weapon := _weapon([Ring.new(0.1, 1.0)])
	var shooter := _shooter_unit(Vector2i(2, 0))

	var reticles: Array[Vector2] = [
		Vector2(0.0, 0.5), Vector2(0.2, 0.5), Vector2(-0.3, 0.5), Vector2(5.0, 0.5)
	]
	for reticle: Vector2 in reticles:
		var result: AimResult = AimController.resolve(
			plane, reticle, 0, weapon, shooter, far_unit.cell, state
		)

		var muzzle: Vector3 = UnitGeometry.muzzle_point(shooter, weapon)
		var ray: Dictionary = AimPlaneGeometry.ray_from_muzzle(
			shooter.cell, far_unit.cell, reticle, muzzle
		)
		var expected: HitResult = ShotPlane.resolve_ray(ray["origin"], ray["dir"], state)

		if expected == null:
			assert_null(result.resolves, "reticle %s: expected a miss" % reticle)
		else:
			assert_not_null(result.resolves, "reticle %s: expected a hit" % reticle)
			assert_eq(result.resolves.part, expected.part)
			assert_eq(result.resolves.body, expected.body)
			assert_eq(result.resolves.distance, expected.distance)


## taskblock-08 B2/TESTS: "the window's depth is within epsilon of the
## target's nearest region and strictly less than it" — the normal case,
## where the target's own nearest depth is comfortably positive, must pass
## through unclamped.
func test_window_depth_uses_the_targets_own_nearest_depth_when_safe() -> void:
	var far := Region.new(Rect2(), 5.0)
	var near := Region.new(Rect2(), 2.0)
	var layers: Array[AimLayer] = [AimLayer.new(&"body", [far, near])]

	var depth: float = AimController.window_depth(layers, &"body", 6.0, 0.05, 0.3)

	assert_almost_eq(depth, 2.0 - 0.05, 0.0001)


## taskblock-08 B2: scrolling to READ a different layer (docs/09
## taskblock06 Pass H) must not drag the window off the target — the whole
## point of pinning it to `target_body` instead of `layer_index`. A far
## layer sitting well behind the target must never move the window.
func test_window_depth_ignores_other_layers_even_when_nearer_or_farther() -> void:
	var target_layer := AimLayer.new(&"target", [Region.new(Rect2(), 2.0)])
	var nearer_layer := AimLayer.new(&"other_near", [Region.new(Rect2(), 0.5)])
	var farther_layer := AimLayer.new(&"other_far", [Region.new(Rect2(), 8.0)])
	var layers: Array[AimLayer] = [nearer_layer, target_layer, farther_layer]

	var depth: float = AimController.window_depth(layers, &"target", 6.0, 0.05, 0.3)

	assert_almost_eq(
		depth, 2.0 - 0.05, 0.0001, "must anchor to the target's own layer, not any other"
	)


## taskblock-08 B2/TESTS: a target whose own nearest depth sits at or below
## zero (positioned behind the shooter along the fire line — still gets a
## Region) must never produce a window depth at or behind the muzzle.
func test_window_depth_never_lands_at_or_behind_the_muzzle() -> void:
	var corpus: Array[float] = [0.0, -0.5, -3.0, 0.02]
	for frontmost: float in corpus:
		var layers: Array[AimLayer] = [AimLayer.new(&"body", [Region.new(Rect2(), frontmost)])]
		var depth: float = AimController.window_depth(layers, &"body", 6.0, 0.05, 0.3)
		assert_true(
			depth > 0.0,
			"frontmost %f: window depth %f must be strictly forward" % [frontmost, depth]
		)
		assert_almost_eq(depth, 0.3, 0.0001, "frontmost %f: must clamp to the minimum" % frontmost)


## Adjacent shooter/target pairs (docs/09 taskblock07 Pass B2's own named
## case) — the corpus explicitly asked for.
func test_window_depth_for_a_corpus_of_adjacent_shooter_target_pairs() -> void:
	var pairs: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	for delta: Vector2i in pairs:
		var shooter_cell := Vector2i(5, 5)
		var target_cell := shooter_cell + delta
		if target_cell == shooter_cell:
			continue
		var target_depth: float = Vector2(target_cell - shooter_cell).length()
		# A target whose own nearest surface sits right at the shooter's
		# own cell (depth 0) — the adjacent-cell worst case.
		var layers: Array[AimLayer] = [AimLayer.new(&"body", [Region.new(Rect2(), 0.0)])]
		var depth: float = AimController.window_depth(layers, &"body", target_depth, 0.05, 0.3)
		assert_true(depth > 0.0, "delta %s: window depth must be strictly forward" % delta)


func test_window_depth_falls_back_to_target_depth_with_no_layers_to_read() -> void:
	var depth: float = AimController.window_depth([], &"body", 4.0, 0.05, 0.3)
	assert_almost_eq(depth, 4.0, 0.0001)


func test_window_depth_falls_back_to_target_depth_when_target_has_no_layer() -> void:
	var layers: Array[AimLayer] = [AimLayer.new(&"someone_else", [Region.new(Rect2(), 1.0)])]

	var depth: float = AimController.window_depth(layers, &"body", 4.0, 0.05, 0.3)

	assert_almost_eq(depth, 4.0, 0.0001, "the target has no region of its own in this plane")
