extends GutTest

## tb32 Passes A/B: the wall-cutout shader's own uniform feed and the
## friendly-fade occlusion ghost — split out of test_board_view.gd purely
## to stay under gdlint's max-public-methods (same convention
## test_tactics_controller_aim.gd's own header already documents).


func _torso_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


## tb32 Pass A: replaces tb31 Pass C's per-wall alpha loop — the wall
## mesh now shares ONE `ShaderMaterial` (`wall_cutout.gdshader`), fed a
## per-unit screen position/depth/radius array every frame instead of
## having its own alpha set directly. GUT can't read GPU discard output
## back, so these tests read the UNIFORM VALUES `update_wall_cutout` fed
## the material — the shader's own per-fragment logic is exercised by the
## shader file itself, and its pure radius/depth math by
## `test_wall_legibility.gd`.
func _cutout_material(view: BoardView) -> ShaderMaterial:
	var instance: MeshInstance3D = view._wall_mesh_instances[0]
	return instance.mesh.material as ShaderMaterial


func test_update_wall_cutout_feeds_the_focal_units_own_screen_position() -> void:
	var grid := Grid.new(5, 8)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())
	assert_eq(view._wall_mesh_instances.size(), 1, "sanity: exactly one wall mesh spawned")

	var unit := _torso_unit(Vector2i(2, 6))
	view.wall_cutout_units = [unit]
	var unit_position: Vector3 = UnitGeometry.bounding_sphere(unit).center

	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(2, 5, -5)
	camera.look_at(unit_position, Vector3.UP)

	view.update_wall_cutout(camera)

	var material: ShaderMaterial = _cutout_material(view)
	assert_eq(material.get_shader_parameter("unit_count"), 1)
	var screen_positions: PackedVector2Array = material.get_shader_parameter(
		"unit_screen_positions"
	)
	assert_almost_eq(
		screen_positions[0].distance_to(camera.unproject_position(unit_position)),
		0.0,
		0.01,
		"the fed screen position must be the unit's own real projection"
	)
	var depths: PackedFloat32Array = material.get_shader_parameter("unit_depths")
	assert_almost_eq(
		depths[0],
		camera.global_position.distance_to(unit_position),
		0.01,
		"the fed depth must be the real camera-to-unit distance"
	)
	var radii: PackedFloat32Array = material.get_shader_parameter("unit_radii_px")
	assert_gt(radii[0], 0.0, "a unit on screen must get a positive cutout radius")


func test_update_wall_cutout_feeds_zero_units_with_an_empty_list() -> void:
	var grid := Grid.new(5, 8)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(2, 5, -5)
	camera.look_at(Vector3(2, 0, 6), Vector3.UP)

	view.update_wall_cutout(camera)

	assert_eq(
		_cutout_material(view).get_shader_parameter("unit_count"),
		0,
		"nothing to protect (no units fed, e.g. spectator view) — the shader must never cut"
	)


## "the hole scales with zoom" — a unit farther from the camera (same
## tile-radius, greater depth) must project to a SMALLER pixel radius,
## read back against a real `Camera3D`, not re-derived by hand.
func test_update_wall_cutout_radius_shrinks_as_the_camera_moves_away() -> void:
	var grid := Grid.new(5, 20)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var unit := _torso_unit(Vector2i(2, 6))
	view.wall_cutout_units = [unit]
	var unit_position: Vector3 = UnitGeometry.bounding_sphere(unit).center

	var near_camera := Camera3D.new()
	add_child_autofree(near_camera)
	near_camera.global_position = Vector3(2, 5, -5)
	near_camera.look_at(unit_position, Vector3.UP)
	view.update_wall_cutout(near_camera)
	var near_radius: float = (
		_cutout_material(view).get_shader_parameter("unit_radii_px") as PackedFloat32Array
	)[0]

	var far_camera := Camera3D.new()
	add_child_autofree(far_camera)
	far_camera.global_position = Vector3(2, 15, -15)
	far_camera.look_at(unit_position, Vector3.UP)
	view.update_wall_cutout(far_camera)
	var far_radius: float = (
		_cutout_material(view).get_shader_parameter("unit_radii_px") as PackedFloat32Array
	)[0]

	assert_lt(far_radius, near_radius, "zoomed/panned further out must shrink the porthole")


func test_wall_material_shading_path_is_unchanged_lit() -> void:
	var grid := Grid.new(5, 8)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var shader: Shader = _cutout_material(view).shader
	assert_false(
		"render_mode unshaded" in shader.code,
		"docs/10: real geometry (walls) must stay lit, not switch to the unshaded overlay path"
	)


## A real, reported bug: an extracted unit (docs/07) never clears its own
## stale `.cell` and stays in `combat_state.units` forever — an
## unfiltered feed here cut a permanent, unit-less hole at wherever it
## left the board from.
func test_update_wall_cutout_skips_an_extracted_unit() -> void:
	var grid := Grid.new(5, 8)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var unit := _torso_unit(Vector2i(2, 6))
	unit.extracted = true
	view.wall_cutout_units = [unit]

	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(2, 5, -5)
	camera.look_at(UnitGeometry.bounding_sphere(unit).center, Vector3.UP)

	view.update_wall_cutout(camera)

	assert_eq(
		_cutout_material(view).get_shader_parameter("unit_count"),
		0,
		"an extracted unit's stale cell must never cut a hole"
	)


## The other real case: a unit whose own HitVolumeView was explicitly
## destroyed (`BattleScene.remove_unit_view()`, the debug-only "make it
## fully vanish" verb) but which stays in `combat_state.units` — same
## stray-hole symptom, different cause (not `.extracted`, just a
## view-level removal `BattleScene` tracks and reports here).
func test_update_wall_cutout_skips_a_unit_excluded_via_remove_unit_view() -> void:
	var grid := Grid.new(5, 8)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var unit := _torso_unit(Vector2i(2, 6))
	view.wall_cutout_units = [unit]
	view.exclude_unit_from_occlusion(unit.id)

	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(2, 5, -5)
	camera.look_at(UnitGeometry.bounding_sphere(unit).center, Vector3.UP)

	view.update_wall_cutout(camera)

	assert_eq(
		_cutout_material(view).get_shader_parameter("unit_count"),
		0,
		"an explicitly-removed unit's stale cell must never cut a hole"
	)


func test_build_clears_previously_excluded_units_for_a_fresh_battle() -> void:
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(Grid.new(5, 8), DataLibrary.material_table())
	view.exclude_unit_from_occlusion(7)
	assert_true(view.is_excluded_from_occlusion(7), "sanity: excluded before the rebuild")

	view.build(Grid.new(5, 8), DataLibrary.material_table())

	assert_false(
		view.is_excluded_from_occlusion(7), "a fresh battle must not inherit a stale exclusion"
	)

## tb32 Pass B was redesigned: the friendly-fade decision and its actual
## effect (fading a unit's own real body) now live on `HitVolumeView`/
## `BattleScene` (`test_hit_volume_view.gd`/`test_battle_scene_occlusion_
## fade.gd`) — the first version drew a separate ghost overlay here,
## leaving the friendly's own body fully opaque underneath it, which read
## as "something faint happening" rather than an actual fade (confirmed
## live). `BoardView` no longer owns any part of this mechanism; only
## `aim_active_unit`/`wall_cutout_units` (read by `BattleScene` now)
## remain here.
