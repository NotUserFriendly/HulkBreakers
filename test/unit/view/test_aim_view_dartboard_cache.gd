extends GutTest

## taskblock-22 Pass I: "the dartboard is very laggy" — _ring_texture used
## to rebuild a fresh 128x128 image + GPU texture on every single call
## (twice per frame, window and decal, regardless of whether the rings
## actually changed). Cached now, keyed by ring CONTENT (Ring is a
## Resource — two separately-built instances with identical radius/
## weight are never `==` to each other; that's reference identity, never
## a real cache hit) rather than by object identity.
## tb34 Pass A: the key is the NORMALIZED shape (ratio to the outer ring),
## not absolute radius — a single ring is always ratio 1.0 to itself
## regardless of its absolute size, so every fixture below now uses at
## least two rings, the only way to distinguish "same shape, rescaled"
## from "genuinely different shape."


func _ring(radius: float, weight: float = 1.0) -> Ring:
	return Ring.new(radius, weight)


func test_calling_with_the_same_ring_content_returns_the_cached_texture() -> void:
	var view := AimView.new()
	add_child_autofree(view)
	var rings_a: Array[Ring] = [_ring(0.1), _ring(0.3)]
	var rings_b: Array[Ring] = [_ring(0.1), _ring(0.3)]  # different instances, same content

	var first: ImageTexture = view._ring_texture(rings_a)
	var second: ImageTexture = view._ring_texture(rings_b)

	assert_eq(first, second, "identical ring content must reuse the cached texture, not rebuild")


## tb34 Pass A: the whole point of the range-aware board — a pure uniform
## rescale (same ratios, different absolute distance) must NOT rebuild the
## pixel data at all, only the caller's own decal/quad world size changes.
func test_a_pure_uniform_rescale_reuses_the_cached_texture() -> void:
	var view := AimView.new()
	add_child_autofree(view)
	var near: Array[Ring] = [_ring(0.1, 0.5), _ring(0.3, 1.0)]
	var far: Array[Ring] = [_ring(0.2, 0.5), _ring(0.6, 1.0)]  # exactly 2x, same ratios

	var first: ImageTexture = view._ring_texture(near)
	var second: ImageTexture = view._ring_texture(far)

	assert_eq(first, second, "a uniform rescale is the same shape -- must reuse, never rebuild")


func test_calling_with_different_ring_ratios_rebuilds() -> void:
	var view := AimView.new()
	add_child_autofree(view)

	var first: ImageTexture = view._ring_texture([_ring(0.1, 0.5), _ring(0.3, 1.0)])
	# Same outer radius (0.3) but a different inner ring -- a genuine shape
	# change, not a rescale.
	var second: ImageTexture = view._ring_texture([_ring(0.2, 0.5), _ring(0.3, 1.0)])

	assert_ne(first, second, "different ring ratios must rebuild, never reuse a stale texture")


func test_rings_match_compares_normalized_shape_not_identity() -> void:
	var a: Array[Ring] = [_ring(0.1, 0.5), _ring(0.3, 1.0)]
	var b: Array[Ring] = [_ring(0.1, 0.5), _ring(0.3, 1.0)]
	var rescaled: Array[Ring] = [_ring(0.2, 0.5), _ring(0.6, 1.0)]  # 2x, same ratios
	var reshaped: Array[Ring] = [_ring(0.1, 0.5), _ring(0.35, 1.0)]  # different ratio

	assert_true(AimView._rings_match(a, b))
	assert_true(AimView._rings_match(a, rescaled), "a uniform rescale must still match")
	assert_false(AimView._rings_match(a, reshaped))
	assert_false(AimView._rings_match(a, []))


## tb34 Pass B: the recoil bound is baked into the same texture, so its
## own ratio to the outer ring is part of the cache key too — a pure
## range change (rings AND bound scale by the same factor) must still
## reuse; a genuine change in whether/how much the board bounds (a
## different burst size, or switching from armed-to-burst to armed-to-
## shoot) must still rebuild.
func test_rings_match_with_a_bound_reuses_across_a_pure_rescale() -> void:
	var a: Array[Ring] = [_ring(0.1, 0.5), _ring(0.3, 1.0)]
	var b: Array[Ring] = [_ring(0.2, 0.5), _ring(0.6, 1.0)]  # 2x, same ratios

	assert_true(
		AimView._rings_match(a, b, 0.45, 0.9),  # bound 1.5x outer on both sides
		"the bound's own ratio to outer is unchanged by a pure rescale -- must still reuse"
	)


func test_rings_match_with_a_bound_rebuilds_when_the_bound_ratio_changes() -> void:
	var a: Array[Ring] = [_ring(0.1, 0.5), _ring(0.3, 1.0)]
	var b: Array[Ring] = [_ring(0.1, 0.5), _ring(0.3, 1.0)]

	assert_false(
		AimView._rings_match(a, b, 0.45, 0.6),
		"a different bound ratio is a genuinely different shape -- must rebuild"
	)
	assert_false(
		AimView._rings_match(a, b, 0.45, 0.0),
		"switching between a bound and no bound at all must rebuild"
	)


func test_ring_texture_with_a_bound_reuses_across_a_pure_rescale() -> void:
	var view := AimView.new()
	add_child_autofree(view)
	var near: Array[Ring] = [_ring(0.1, 0.5), _ring(0.3, 1.0)]
	var far: Array[Ring] = [_ring(0.2, 0.5), _ring(0.6, 1.0)]  # 2x, same ratios

	var first: ImageTexture = view._ring_texture(near, 0.45)  # bound 1.5x outer
	var second: ImageTexture = view._ring_texture(far, 0.9)  # same 1.5x ratio

	assert_eq(first, second, "rings and bound scaling together is still a pure rescale")


func test_ring_texture_rebuilds_when_a_bound_appears_or_disappears() -> void:
	var view := AimView.new()
	add_child_autofree(view)
	var rings: Array[Ring] = [_ring(0.1, 0.5), _ring(0.3, 1.0)]

	var without_bound: ImageTexture = view._ring_texture(rings)
	var with_bound: ImageTexture = view._ring_texture(rings, 0.6)

	assert_ne(
		without_bound, with_bound, "a newly-armed burst adding a bound must rebuild, not reuse"
	)


## tb34 Pass E (BR26.02): "a headless regression pinning the cache
## behaviour (no rebuild across range sweep) so the win can't silently
## regress" — the real pipeline this time (ShotScatter.for_shot, the exact
## call AimController.resolve makes every frame while aiming), swept
## across every cell from adjacent to max range, standing in for a
## shooter/target repositioning throughout a live aim session. Counts
## actual `DartboardTexture.build` calls via the cached instance identity:
## if the shape (ratio-to-outer) never changes across the sweep, this
## must build exactly once, not once per distance.
func test_a_realistic_range_sweep_builds_the_texture_at_most_once() -> void:
	var view := AimView.new()
	add_child_autofree(view)
	var weapon := Part.new()
	weapon.id = &"rifle"
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.effective_range = 5.0
	weapon.weapon_def.max_range = 20.0
	weapon.scatter = [Ring.new(0.05, 2.0), Ring.new(0.15, 1.0)]
	var shooter_torso := Part.new()
	shooter_torso.id = &"torso"
	shooter_torso.hp = 1
	shooter_torso.max_hp = 1
	var shooter := Unit.new(Matrix.new(), Shell.new(shooter_torso), Vector2i(0, 0), 0)

	var textures: Array[ImageTexture] = []
	for range_cells in range(1, 21):
		var rings: Array[Ring] = ShotScatter.for_shot(
			shooter, weapon, Vector2i(range_cells, 0), null
		)
		textures.append(view._ring_texture(rings))

	var distinct: Array[ImageTexture] = []
	for texture: ImageTexture in textures:
		if not distinct.has(texture):
			distinct.append(texture)
	assert_eq(
		distinct.size(),
		1,
		"a continuous range sweep with no shape change must build the texture exactly once"
	)
