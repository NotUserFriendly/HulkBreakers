extends GutTest

## taskblock-22 Pass I: "the dartboard is very laggy" — _ring_texture used
## to rebuild a fresh 128x128 image + GPU texture on every single call
## (twice per frame, window and decal, regardless of whether the rings
## actually changed). Cached now, keyed by ring CONTENT (Ring is a
## Resource — two separately-built instances with identical radius/
## weight are never `==` to each other; that's reference identity, never
## a real cache hit) rather than by object identity.


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


func test_calling_with_different_ring_content_rebuilds() -> void:
	var view := AimView.new()
	add_child_autofree(view)

	var first: ImageTexture = view._ring_texture([_ring(0.1)])
	var second: ImageTexture = view._ring_texture([_ring(0.5)])

	assert_ne(first, second, "different ring content must rebuild, never reuse a stale texture")


func test_rings_match_compares_content_not_identity() -> void:
	var a: Array[Ring] = [_ring(0.1, 0.5), _ring(0.3, 1.0)]
	var b: Array[Ring] = [_ring(0.1, 0.5), _ring(0.3, 1.0)]
	var c: Array[Ring] = [_ring(0.1, 0.5), _ring(0.35, 1.0)]

	assert_true(AimView._rings_match(a, b))
	assert_false(AimView._rings_match(a, c))
	assert_false(AimView._rings_match(a, []))
