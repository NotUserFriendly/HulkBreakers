extends GutTest

## docs/09 taskblock06 Pass H: frontmost_depth() is what places the aim
## window "just in front of the READ layer's frontmost part."


func test_frontmost_depth_is_the_nearest_regions_depth() -> void:
	var far := Region.new(Rect2(), 5.0)
	var near := Region.new(Rect2(), 2.0)
	var layer := AimLayer.new(null, [far, near])

	assert_almost_eq(layer.frontmost_depth(), 2.0, 0.0001)


func test_frontmost_depth_with_a_single_region() -> void:
	var only := Region.new(Rect2(), 3.5)
	var layer := AimLayer.new(null, [only])

	assert_almost_eq(layer.frontmost_depth(), 3.5, 0.0001)


func test_frontmost_depth_with_no_regions_defaults_to_zero() -> void:
	var layer := AimLayer.new(null, [])

	assert_almost_eq(layer.frontmost_depth(), 0.0, 0.0001)
