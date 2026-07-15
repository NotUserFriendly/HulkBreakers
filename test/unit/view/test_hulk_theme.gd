extends GutTest

## docs/08: six colors, one Theme resource, no per-scene styling.


func test_exactly_six_named_colors() -> void:
	# background, foreground, dim, highlight, warn, damage — docs/08's own
	# list, no more.
	var colors: Array[Color] = [
		HulkTheme.BACKGROUND,
		HulkTheme.FOREGROUND,
		HulkTheme.DIM,
		HulkTheme.HIGHLIGHT,
		HulkTheme.WARN,
		HulkTheme.DAMAGE,
	]
	assert_eq(colors.size(), 6)
	for i in range(colors.size()):
		for j in range(i + 1, colors.size()):
			assert_ne(colors[i], colors[j], "each of the six colors must be distinct")


func test_build_returns_a_real_theme_resource() -> void:
	var theme: Theme = HulkTheme.build()
	assert_true(theme is Theme)
	assert_eq(theme.get_color("default_color", "RichTextLabel"), HulkTheme.FOREGROUND)


func test_color_for_material_uses_only_the_six_named_colors() -> void:
	var table := MaterialTable.default_table()
	var six: Array[Color] = [
		HulkTheme.BACKGROUND,
		HulkTheme.FOREGROUND,
		HulkTheme.DIM,
		HulkTheme.HIGHLIGHT,
		HulkTheme.WARN,
		HulkTheme.DAMAGE,
	]
	for material_id: StringName in [
		&"", &"flesh", &"sheet_steel", &"steel", &"ceramic_composite", &"reactive", &"unknown_material"
	]:
		assert_true(
			six.has(HulkTheme.color_for_material(material_id, table)),
			"color for %s must be one of the six named colors" % material_id
		)


func test_color_for_material_climbs_with_dt() -> void:
	var table := MaterialTable.default_table()
	assert_eq(HulkTheme.color_for_material(&"", table), HulkTheme.DIM, "bare part")
	assert_eq(HulkTheme.color_for_material(&"flesh", table), HulkTheme.FOREGROUND, "dt 0")
	assert_eq(HulkTheme.color_for_material(&"sheet_steel", table), HulkTheme.DIM, "dt 3")
	assert_eq(HulkTheme.color_for_material(&"steel", table), HulkTheme.HIGHLIGHT, "dt 6")
	assert_eq(HulkTheme.color_for_material(&"reactive", table), HulkTheme.WARN, "dt 12")


func test_world_environment_uses_the_theme_background_color() -> void:
	var world_environment: WorldEnvironment = HulkTheme.world_environment()
	assert_eq(world_environment.environment.background_mode, Environment.BG_COLOR)
	assert_eq(world_environment.environment.background_color, HulkTheme.BACKGROUND)
	world_environment.queue_free()


func test_flat_material_is_unshaded_and_uses_the_given_color() -> void:
	var material: StandardMaterial3D = HulkTheme.flat_material(HulkTheme.WARN)
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(material.albedo_color, HulkTheme.WARN)
