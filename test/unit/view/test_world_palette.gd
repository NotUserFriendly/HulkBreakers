extends GutTest

## docs/10 "two palettes, not one": WorldPalette governs the 3D board,
## distinct from HulkTheme (terminal UI only). Real geometry is lit
## (PER_PIXEL); only overlays (reachable/ghost/rings/team markers) stay
## unshaded.


func test_world_environment_uses_the_void_background_and_ground_tinted_ambient() -> void:
	var world_environment: WorldEnvironment = WorldPalette.world_environment()
	assert_eq(world_environment.environment.background_mode, Environment.BG_COLOR)
	assert_eq(world_environment.environment.background_color, WorldPalette.VOID)
	assert_eq(world_environment.environment.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)
	assert_eq(world_environment.environment.ambient_light_color, WorldPalette.GROUND)
	assert_almost_eq(
		world_environment.environment.ambient_light_energy, WorldPalette.AMBIENT_ENERGY, 0.0001
	)
	world_environment.queue_free()


func test_void_and_ground_are_distinct_so_the_board_is_actually_visible() -> void:
	assert_ne(WorldPalette.VOID, WorldPalette.GROUND)


func test_directional_light_is_angled_off_axis() -> void:
	var light: DirectionalLight3D = WorldPalette.directional_light()
	assert_ne(light.rotation_degrees.x, 0.0, "an un-angled light would flatten every box face")
	light.queue_free()


func test_team_color_maps_squad_zero_to_a_and_others_to_b() -> void:
	assert_eq(WorldPalette.team_color(0), WorldPalette.TEAM_A)
	assert_eq(WorldPalette.team_color(1), WorldPalette.TEAM_B)
	assert_eq(WorldPalette.team_color(2), WorldPalette.TEAM_B)


func test_team_colors_are_distinct() -> void:
	assert_ne(WorldPalette.TEAM_A, WorldPalette.TEAM_B)


func test_lit_material_is_per_pixel_shaded() -> void:
	var material: StandardMaterial3D = WorldPalette.lit_material(Color.RED)
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	assert_eq(material.albedo_color, Color.RED)


func test_overlay_material_is_unshaded() -> void:
	var material: StandardMaterial3D = WorldPalette.overlay_material(Color.BLUE)
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(material.albedo_color, Color.BLUE)


func test_rim_outline_material_is_grown_and_back_face_only() -> void:
	var material: StandardMaterial3D = WorldPalette.rim_outline_material(WorldPalette.TEAM_A)
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(material.cull_mode, BaseMaterial3D.CULL_FRONT)
	assert_true(material.grow)
	assert_true(material.grow_amount > 0.0)
	assert_eq(material.albedo_color, WorldPalette.TEAM_A)
