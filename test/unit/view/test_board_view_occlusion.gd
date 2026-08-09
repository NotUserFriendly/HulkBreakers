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
	var grid := GridFixture.flat(5, 8)
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
	# BR32.02: FRAGCOORD and unproject_position() are BOTH top-left-
	# origin, Y-down — confirmed live, empirically (a hardcoded-corner
	# diagnostic build landed in the window's own top-left corner). No
	# flip needed; the fed position is unproject_position()'s own output,
	# unchanged.
	assert_almost_eq(
		screen_positions[0].distance_to(camera.unproject_position(unit_position)),
		0.0,
		0.01,
		"the fed screen position must be the unit's own real projection, unconverted"
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
	var grid := GridFixture.flat(5, 8)
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
## cell-radius, greater depth) must project to a SMALLER pixel radius,
## read back against a real `Camera3D`, not re-derived by hand.
func test_update_wall_cutout_radius_shrinks_as_the_camera_moves_away() -> void:
	var grid := GridFixture.flat(5, 20)
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
	var grid := GridFixture.flat(5, 8)
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
	var grid := GridFixture.flat(5, 8)
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
	var grid := GridFixture.flat(5, 8)
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
	view.build(GridFixture.flat(5, 8), DataLibrary.material_table())
	view.exclude_unit_from_occlusion(7)
	assert_true(view.is_excluded_from_occlusion(7), "sanity: excluded before the rebuild")

	view.build(GridFixture.flat(5, 8), DataLibrary.material_table())

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


## `BR32.05`, taskblock-61 Pass C1 — the supervisor's gate, read back off the real uniform feed.
## Same board and same unit as `test_update_wall_cutout_feeds_the_focal_units_own_screen_position`
## above, with the camera moved to the unit's OWN side of the wall. Before this gate the feed did
## not look at the board at all: every unit on screen was fed, and the shader's screen-space test
## decided alone — which is how a wall nothing was hiding behind still got cut.
func test_update_wall_cutout_skips_a_unit_with_nothing_between_it_and_the_camera() -> void:
	var grid := GridFixture.flat(5, 12)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var unit := _torso_unit(Vector2i(2, 6))
	view.wall_cutout_units = [unit]

	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(2, 5, 10)
	camera.look_at(UnitGeometry.bounding_sphere(unit).center, Vector3.UP)

	view.update_wall_cutout(camera)

	assert_eq(
		_cutout_material(view).get_shader_parameter("unit_count"),
		0,
		"the wall is behind the unit from here — nothing is hidden, so nothing may be cut"
	)


## `BR32.08`, supervisor's rule: "if it gets a turn, it gets a cutout, if not, then no cutout."
## `CombatState.kill_unit` only flips `alive` — the body stays in `units` forever — so every
## corpse cut its own permanent full-radius hole and a long firefight progressively opened the
## level up. The camera here is the one from the passing feed test above, so the ONLY thing under
## test is the unit being dead.
func test_update_wall_cutout_skips_a_dead_unit() -> void:
	var grid := GridFixture.flat(5, 8)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var unit := _torso_unit(Vector2i(2, 6))
	unit.alive = false
	view.wall_cutout_units = [unit]

	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(2, 5, -5)
	camera.look_at(UnitGeometry.bounding_sphere(unit).center, Vector3.UP)

	view.update_wall_cutout(camera)

	assert_eq(
		_cutout_material(view).get_shader_parameter("unit_count"),
		0,
		"a corpse does not take turns, so it does not get a cutout"
	)


## The other half of the same predicate: a shut-down unit stays `alive` and still blocks as
## geometry, but `CombatState.can_take_a_turn` excludes it and so does the cutout.
func test_update_wall_cutout_skips_a_shut_down_unit() -> void:
	var grid := GridFixture.flat(5, 8)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var unit := _torso_unit(Vector2i(2, 6))
	unit.shutdown = true
	view.wall_cutout_units = [unit]

	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(2, 5, -5)
	camera.look_at(UnitGeometry.bounding_sphere(unit).center, Vector3.UP)

	view.update_wall_cutout(camera)

	assert_eq(
		_cutout_material(view).get_shader_parameter("unit_count"),
		0,
		"a shut-down unit gets no turn"
	)


## **The rule's own explicit exception, pinned so nobody "tidies" it into the dead case.** The
## supervisor: "downed needs cutouts though, because a downed unit may be only a turn from being
## back to normal." `Unit.is_downed()` is "no matrix docked" — orthogonal to `alive`/`shutdown` —
## so a downed unit still takes turns and must still cut. `_torso_unit`'s own torso hosts no
## matrix, so this fixture is genuinely downed rather than merely asserted to be.
func test_update_wall_cutout_still_cuts_for_a_downed_unit() -> void:
	var grid := GridFixture.flat(5, 8)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var unit := _torso_unit(Vector2i(2, 6))
	assert_true(unit.is_downed(), "sanity: this fixture docks no matrix, so it reads as downed")
	assert_true(CombatState.can_take_a_turn(unit), "sanity: downed is not dead and not shut down")
	view.wall_cutout_units = [unit]

	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(2, 5, -5)
	camera.look_at(UnitGeometry.bounding_sphere(unit).center, Vector3.UP)

	view.update_wall_cutout(camera)

	assert_eq(
		_cutout_material(view).get_shader_parameter("unit_count"),
		1,
		"a downed unit is a turn from standing back up — it keeps its cutout"
	)


## **The `BR32.05` diagnostic, pinned.** A gate that disagrees with what the supervisor sees on
## screen is only settleable by naming the geometry it found, so the cutout line records the cell
## it blamed for every unit it kept. Without this the next report is another adjudication.
func test_the_cutout_log_names_the_cell_it_blamed() -> void:
	var grid := GridFixture.flat(5, 12)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())
	var sink := MemorySink.new()
	view.build_log = CombatLog.new()
	view.build_log.add_sink(sink)

	var unit := _torso_unit(Vector2i(2, 6))
	view.wall_cutout_units = [unit]
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(2, 5, -5)
	camera.look_at(UnitGeometry.bounding_sphere(unit).center, Vector3.UP)

	view.update_wall_cutout(camera)

	var lines: Array[LogEvent] = sink.events.filter(
		func(event: LogEvent) -> bool: return event.kind == &"wall_cutout"
	)
	assert_eq(lines.size(), 1, "one cutout line for one meaningful change")
	assert_eq(
		lines[0].data.get("blocked_by"),
		"2.3",
		"the log must name the wall cell the gate actually found, not just that it found one"
	)


## **`BR32.04`: the hole must follow the body it is cutting for, not the model's already-arrived
## cell.** `resolve_to_marker()` mutates `unit.cell` synchronously, so the logical body is at the
## destination the frame Resolve is clicked while `ResolutionPlayer` is still tweening the visible
## one across it — the cutout jumped ahead and cut around a body that was not there yet.
##
## Driven the way the real thing drives it: `ResolutionPlayer._apply_display_transform` writes
## `HitVolumeView.position`/`basis` on every tween tick, so this sets that same transform on a real
## node and reads the fed uniform back out (`docs/00`: read the real node back). The expected screen
## position is stated as a world point the test itself chose, not recomputed with the same formula.
func test_the_cutout_follows_the_rendered_body_mid_slide() -> void:
	var grid := GridFixture.flat(5, 12)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var unit := _torso_unit(Vector2i(2, 6))
	var body := HitVolumeView.new()
	add_child_autofree(body)
	body.setup(unit, DataLibrary.material_table())
	view.wall_cutout_units = [unit]
	view.wall_cutout_views = [body]

	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(2, 5, -5)
	camera.look_at(UnitGeometry.bounding_sphere(unit).center, Vector3.UP)

	# Still at rest: the view transform is identity, so nothing about the fed position changes.
	view.update_wall_cutout(camera)
	var at_rest: Vector2 = (
		_cutout_material(view).get_shader_parameter("unit_screen_positions") as PackedVector2Array
	)[0]
	assert_almost_eq(
		at_rest.distance_to(camera.unproject_position(UnitGeometry.bounding_sphere(unit).center)),
		0.0,
		0.01,
		"an unanimated unit must feed exactly what it fed before this existed"
	)

	# Mid-slide: the body is drawn two cells short of the cell the model already holds.
	var lagging: Vector3 = UnitGeometry.bounding_sphere(unit).center - Vector3(0, 0, 2)
	body.position = Vector3(0, 0, -2)
	view.update_wall_cutout(camera)
	var mid_slide: Vector2 = (
		_cutout_material(view).get_shader_parameter("unit_screen_positions") as PackedVector2Array
	)[0]

	assert_almost_eq(
		mid_slide.distance_to(camera.unproject_position(lagging)),
		0.0,
		0.01,
		"the hole must be cut where the body is DRAWN, two cells back from its logical cell"
	)
	assert_gt(
		mid_slide.distance_to(at_rest),
		1.0,
		"sanity: the two positions must actually differ, or this test proves nothing"
	)


## The fallback has to be total, not partial: a `BoardView` with no view array (a spectator load
## before views exist, every headless fixture) must behave exactly as it did before `BR32.04`.
func test_a_unit_with_no_rendered_view_falls_back_to_its_logical_position() -> void:
	var grid := GridFixture.flat(5, 12)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var unit := _torso_unit(Vector2i(2, 6))
	view.wall_cutout_units = [unit]
	assert_true(view.wall_cutout_views.is_empty(), "sanity: no views wired at all")

	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(2, 5, -5)
	camera.look_at(UnitGeometry.bounding_sphere(unit).center, Vector3.UP)

	view.update_wall_cutout(camera)

	assert_eq(
		_cutout_material(view).get_shader_parameter("unit_count"),
		1,
		"no view is not a reason to stop cutting — membership never came from the view array"
	)


## **The view array must be shared, not copied.** `BattleScene.load_battle` hands
## `board_view.wall_cutout_views = unit_views` once, and `sync_unit_views()` appends to that same
## array for every unit spawned afterwards. If the assignment copied — which a typed-array mismatch
## would silently cause — every later unit would fall back to its logical position and `BR32.04`
## would quietly come back for exactly the units nobody thought to check.
func test_the_view_array_is_shared_with_the_scene_not_copied() -> void:
	var view := BoardView.new()
	add_child_autofree(view)
	var scene_views: Array[HitVolumeView] = []
	view.wall_cutout_views = scene_views

	var body := HitVolumeView.new()
	add_child_autofree(body)
	scene_views.append(body)

	assert_eq(
		view.wall_cutout_views.size(),
		1,
		"appending to the scene's own array must be visible here — a copy would read 0"
	)
