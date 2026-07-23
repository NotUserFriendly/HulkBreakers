extends GutTest

## docs/09 taskblock06 Pass H / taskblock07 Pass D: the ring image's own
## pixel math — a central aiming dot plus weight-scaled ring bands.


func test_center_pixel_is_the_aiming_dot_at_full_opacity() -> void:
	var rings: Array[Ring] = [Ring.new(0.5, 1.0), Ring.new(1.0, 1.0)]
	var image: Image = DartboardTexture.build(rings, Color(1.0, 0.0, 0.0, 1.0), 64)

	var center_color: Color = image.get_pixel(32, 32)
	assert_almost_eq(center_color.a, DartboardTexture.DOT_ALPHA, 0.0001)
	assert_almost_eq(center_color.r, 1.0, 0.0001)


func test_pixel_beyond_the_outer_ring_is_fully_transparent() -> void:
	var rings: Array[Ring] = [Ring.new(0.5, 1.0)]
	var image: Image = DartboardTexture.build(rings, Color(1.0, 0.0, 0.0, 1.0), 64)

	# The image's own corner sits well outside a ring whose radius only
	# reaches the image's half-width, never the half-diagonal.
	assert_almost_eq(image.get_pixel(0, 0).a, 0.0, 0.0001)


## docs/09 taskblock07 Pass D: "ring weight should read visually... the
## majority ring is the one the player's eye should land on."
func test_the_majority_ring_renders_more_opaque_than_a_lighter_one() -> void:
	var rings: Array[Ring] = [
		Ring.new(0.2, 1.0),  # tight, low weight — inner ring, but not the dot
		Ring.new(0.6, 10.0),  # the majority ring
		Ring.new(1.0, 1.0),  # loose, low weight
	]
	var image: Image = DartboardTexture.build(rings, Color(1.0, 1.0, 1.0, 1.0), 128)

	# Sample well inside each band's own span (never near an edge, where
	# the crisp boundary rim always wins regardless of weight).
	var tight: Color = image.get_pixel(64 + 6, 64)  # inside ring 0's own span
	var majority: Color = image.get_pixel(64 + 28, 64)  # inside ring 1's own span
	var loose: Color = image.get_pixel(64 + 55, 64)  # inside ring 2's own span

	assert_true(
		majority.a > tight.a, "the majority ring must read more prominent than the tight ring"
	)
	assert_true(
		majority.a > loose.a, "the majority ring must read more prominent than the loose ring"
	)
	assert_almost_eq(tight.a, loose.a, 0.05, "two equal-weight rings must render equally prominent")


## docs/09 taskblock07 Pass D: band separation must hold even where two
## adjacent rings happen to share the same weight — the crisp edge rim,
## not fill alone, is what draws the boundary.
func test_adjacent_equal_weight_rings_still_show_a_crisp_boundary() -> void:
	var rings: Array[Ring] = [Ring.new(0.5, 1.0), Ring.new(1.0, 1.0)]
	var image: Image = DartboardTexture.build(rings, Color(1.0, 1.0, 1.0, 1.0), 128)

	# Exactly at ring 0's own outer boundary (world radius 0.5, at 64 px
	# per unit for a 128px image / outer_radius 1.0).
	var edge: Color = image.get_pixel(64 + 62, 64)
	var mid_span: Color = image.get_pixel(64 + 40, 64)
	assert_almost_eq(edge.a, DartboardTexture.EDGE_ALPHA, 0.1)
	assert_true(edge.a > mid_span.a, "the edge rim must read brighter than the mid-band fill")


func test_empty_rings_produces_a_fully_transparent_image() -> void:
	var image: Image = DartboardTexture.build([], Color.WHITE, 32)

	assert_almost_eq(image.get_pixel(16, 16).a, 0.0, 0.0001)


func test_the_output_size_matches_the_requested_size() -> void:
	var rings: Array[Ring] = [Ring.new(1.0, 1.0)]
	var image: Image = DartboardTexture.build(rings, Color.WHITE, 40)

	assert_eq(image.get_width(), 40)
	assert_eq(image.get_height(), 40)


## docs/09 taskblock07 Pass D/TESTS: "a 1-ring and a 5-ring weapon both
## draw the right count" — never assume 3. Verified by walking outward
## along one transect and counting distinct ring bands actually crossed
## (dot excluded), for both a minimal and a maximal weapon.
func _bands_crossed(rings: Array[Ring], size: int) -> int:
	var image: Image = DartboardTexture.build(rings, Color.WHITE, size)
	var center: int = size / 2
	var last_index := -2
	var bands := 0
	for x in range(center, size):
		var dx: float = (x + 0.5) - size / 2.0
		var world_dist: float = dx / (size / 2.0 / rings[rings.size() - 1].radius)
		var index: int = DartboardTexture._ring_index_at(rings, world_dist)
		if index >= 0 and index != last_index:
			bands += 1
			last_index = index
	return bands


func test_a_one_ring_weapon_draws_exactly_one_band() -> void:
	var rings: Array[Ring] = [Ring.new(1.0, 1.0)]
	assert_eq(_bands_crossed(rings, 128), 1)


func test_a_five_ring_weapon_draws_exactly_five_bands() -> void:
	var rings: Array[Ring] = [
		Ring.new(0.2, 1.0),
		Ring.new(0.4, 1.0),
		Ring.new(0.6, 1.0),
		Ring.new(0.8, 1.0),
		Ring.new(1.0, 1.0),
	]
	assert_eq(_bands_crossed(rings, 128), 5)


## tb34 Pass A: `build()` normalizes every distance by `outer_radius`
## (`px_per_unit = center / outer_radius`) and `dot_radius` is itself a
## fraction of `outer_radius` — so scaling every ring by a uniform factor
## scales `world_dist` and every ring boundary identically, and the
## resulting image is byte-for-byte the same. This is what makes it safe
## for `AimView`'s own cache to key on ring RATIOS instead of absolute
## radius (a range change costs a decal resize, never a pixel rebuild).
func test_output_is_byte_identical_for_rings_scaled_by_a_uniform_factor() -> void:
	var near: Array[Ring] = [Ring.new(0.2, 0.5), Ring.new(0.5, 1.0), Ring.new(1.0, 2.0)]
	var far: Array[Ring] = [Ring.new(0.6, 0.5), Ring.new(1.5, 1.0), Ring.new(3.0, 2.0)]  # 3x

	var near_image: Image = DartboardTexture.build(near, Color(1.0, 0.5, 0.25, 1.0), 96)
	var far_image: Image = DartboardTexture.build(far, Color(1.0, 0.5, 0.25, 1.0), 96)

	assert_eq(near_image.get_data(), far_image.get_data())


## tb34 Pass B: a recoil bound beyond the weighted rings' own outer radius
## draws a crisp ring at exactly that radius, extending the canvas so it
## isn't clipped -- and the SAME uniform-scale invariance Pass A relies on
## must still hold with a bound present (both rings and bound scale
## together, since the bound is `outer_radius * a weapon-constant factor`).
func test_a_bound_beyond_the_rings_draws_a_visible_ring_there() -> void:
	var rings: Array[Ring] = [Ring.new(0.5, 1.0)]
	var image: Image = DartboardTexture.build(rings, Color(1.0, 1.0, 1.0, 1.0), 128, 1.0)

	# At world radius 1.0 (the bound), on a 128px image whose canvas now
	# spans out to 1.0 (64 px per unit) -- the last valid pixel (127) sits
	# just inside that edge, still within the bound's own crisp band.
	var at_bound: Color = image.get_pixel(127, 64)
	# Between the weighted ring (0.5) and the bound (1.0) -- otherwise
	# empty space the bound now reads clearly against.
	var dead_zone: Color = image.get_pixel(64 + 48, 64)
	assert_true(at_bound.a > 0.5, "the bound ring itself must be clearly visible")
	assert_almost_eq(dead_zone.a, 0.0, 0.01, "between the rings and the bound must stay empty")


func test_no_bound_ring_drawn_when_bound_radius_is_within_the_weighted_rings() -> void:
	var rings: Array[Ring] = [Ring.new(1.0, 1.0)]
	var with_bound: Image = DartboardTexture.build(rings, Color(1.0, 1.0, 1.0, 1.0), 128, 0.5)
	var without_bound: Image = DartboardTexture.build(rings, Color(1.0, 1.0, 1.0, 1.0), 128, 0.0)

	assert_eq(
		with_bound.get_data(),
		without_bound.get_data(),
		"a bound that doesn't reach past the weighted rings must draw nothing extra"
	)


func test_output_with_a_bound_is_still_byte_identical_under_a_uniform_rescale() -> void:
	var near: Array[Ring] = [Ring.new(0.2, 0.5), Ring.new(0.5, 1.0)]
	var far: Array[Ring] = [Ring.new(0.6, 0.5), Ring.new(1.5, 1.0)]  # 3x, same as the bound below

	var near_image: Image = DartboardTexture.build(near, Color(1.0, 0.5, 0.25, 1.0), 96, 0.8)
	var far_image: Image = DartboardTexture.build(far, Color(1.0, 0.5, 0.25, 1.0), 96, 2.4)

	assert_eq(near_image.get_data(), far_image.get_data())


func test_build_solid_dot_is_fully_opaque_inside_and_transparent_outside() -> void:
	var image: Image = DartboardTexture.build_solid_dot(Color(1.0, 0.0, 0.0, 1.0), 64)

	assert_almost_eq(image.get_pixel(32, 32).a, 1.0, 0.0001, "dead center must be fully opaque")
	assert_almost_eq(image.get_pixel(0, 0).a, 0.0, 0.0001, "the image's own corner must stay empty")
