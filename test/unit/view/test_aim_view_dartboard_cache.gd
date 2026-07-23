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
