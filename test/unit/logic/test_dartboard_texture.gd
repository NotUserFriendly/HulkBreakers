extends GutTest

## docs/09 taskblock06 Pass H: the ring image's own pixel math.


func test_center_pixel_is_the_innermost_band() -> void:
	var rings: Array[Ring] = [Ring.new(0.5, 1.0), Ring.new(1.0, 1.0)]
	var image: Image = DartboardTexture.build(rings, Color(1.0, 0.0, 0.0, 1.0), 64)

	var center_color: Color = image.get_pixel(32, 32)
	assert_almost_eq(center_color.a, DartboardTexture.BAND_ALPHA_A, 0.05)
	assert_almost_eq(center_color.r, 1.0, 0.0001)


func test_pixel_beyond_the_outer_ring_is_fully_transparent() -> void:
	var rings: Array[Ring] = [Ring.new(0.5, 1.0)]
	var image: Image = DartboardTexture.build(rings, Color(1.0, 0.0, 0.0, 1.0), 64)

	# The image's own corner sits well outside a ring whose radius only
	# reaches the image's half-width, never the half-diagonal.
	assert_almost_eq(image.get_pixel(0, 0).a, 0.0, 0.0001)


func test_adjacent_rings_alternate_band_alpha() -> void:
	var rings: Array[Ring] = [Ring.new(0.3, 1.0), Ring.new(1.0, 1.0)]
	var image: Image = DartboardTexture.build(rings, Color(1.0, 1.0, 1.0, 1.0), 64)

	var inner: Color = image.get_pixel(32, 32)  # dead center: ring 0
	var outer: Color = image.get_pixel(60, 32)  # near the right edge: ring 1
	assert_almost_eq(inner.a, DartboardTexture.BAND_ALPHA_A, 0.05)
	assert_almost_eq(outer.a, DartboardTexture.BAND_ALPHA_B, 0.05)


func test_empty_rings_produces_a_fully_transparent_image() -> void:
	var image: Image = DartboardTexture.build([], Color.WHITE, 32)

	assert_almost_eq(image.get_pixel(16, 16).a, 0.0, 0.0001)


func test_the_output_size_matches_the_requested_size() -> void:
	var rings: Array[Ring] = [Ring.new(1.0, 1.0)]
	var image: Image = DartboardTexture.build(rings, Color.WHITE, 40)

	assert_eq(image.get_width(), 40)
	assert_eq(image.get_height(), 40)
