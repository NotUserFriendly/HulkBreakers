extends GutTest

## docs/10 "render is hitbox": HitVolumeView must spawn exactly one mesh per
## living box UnitGeometry.placements() reports, at exactly that transform,
## and rebuild on refresh() so destroyed parts vanish. Team flagging
## (docs/10) adds a ground marker (child 0) and a facing wedge (docs/10
## taskblock02 F3, child 1) ahead of the part meshes — both overlays,
## never touching a part's own material.


## A torso with a docked matrix (a normal, piloted unit — not the docs/10
## taskblock03 G "bare shell" case, covered separately below).
func _torso_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var torso := _piloted_torso()
	return Unit.new(torso.hosted_matrix, Shell.new(torso), cell, squad)


func _torso_with_arm_unit(cell: Vector2i) -> Dictionary:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 4
	arm.volume = [Box.new(Vector3.ZERO, Vector3(0.4, 0.9, 0.4))]

	var torso := _piloted_torso()
	var shoulder := Socket.new(&"SHOULDER")
	shoulder.occupant = arm
	torso.sockets.append(shoulder)

	return {"unit": Unit.new(torso.hosted_matrix, Shell.new(torso), cell), "arm": arm}


func _piloted_torso() -> Part:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	torso.sockets = [Socket.new(&"MATRIX")]
	torso.dock_matrix(Matrix.new())
	return torso


## docs/10 taskblock03 G: "a unit with no matrix docked (a shell)."
func _shell_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


func test_setup_spawns_the_team_marker_plus_one_mesh_per_living_box() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	assert_eq(view.get_child_count(), 3, "team marker + facing wedge + one part mesh")


func test_refresh_after_a_part_is_destroyed_removes_its_mesh() -> void:
	var built: Dictionary = _torso_with_arm_unit(Vector2i(0, 0))
	var unit: Unit = built.unit
	var arm: Part = built.arm

	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	assert_eq(view.get_child_count(), 4, "team marker + facing wedge + torso + arm")

	arm.hp = 0
	view.refresh()
	assert_eq(view.get_child_count(), 3, "the destroyed arm's mesh must disappear")


func test_mesh_transform_matches_unit_geometry_exactly() -> void:
	var unit := _torso_unit(Vector2i(3, 4))
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	var expected: BoxPlacement = UnitGeometry.placements(unit)[0]
	var mesh_instance: MeshInstance3D = view.get_child(2)
	assert_eq(mesh_instance.transform, expected.transform.translated_local(expected.box.center))


func test_mesh_size_matches_the_box_size_exactly() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	var mesh_instance: MeshInstance3D = view.get_child(2)
	var box_mesh: BoxMesh = mesh_instance.mesh
	assert_eq(box_mesh.size, Vector3(2.0, 1.0, 0.6))


func test_part_material_is_lit_not_unshaded() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	var mesh_instance: MeshInstance3D = view.get_child(2)
	var box_mesh: BoxMesh = mesh_instance.mesh
	var material: StandardMaterial3D = box_mesh.material
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL)


func test_part_material_carries_a_rim_outline_next_pass() -> void:
	var unit := _torso_unit(Vector2i(0, 0), 0)
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	var mesh_instance: MeshInstance3D = view.get_child(2)
	var box_mesh: BoxMesh = mesh_instance.mesh
	var material: StandardMaterial3D = box_mesh.material
	assert_not_null(material.next_pass, "a rim outline pass must ride the part's own material")


## docs/10 taskblock02 F3: "a facing wedge on the ring."
func test_facing_wedge_sits_at_child_1_pointing_along_orientation() -> void:
	var unit := _torso_unit(Vector2i(2, 3), 0)
	unit.orientation = PI / 2.0
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	var wedge: MeshInstance3D = view.get_child(1)
	var forward: Vector2 = BodyProjector.forward_for(unit.orientation)
	var expected_xz := Vector2(2.0, 3.0) + forward * HitVolumeView.FACING_WEDGE_OFFSET
	assert_almost_eq(wedge.position.x, expected_xz.x, 0.0001)
	assert_almost_eq(wedge.position.z, expected_xz.y, 0.0001)


## docs/09 taskblock07 Pass B1/TESTS: "the wedge's position and rotation
## agree at every orientation across a full sweep" — the bug this pass
## fixes was invisible at any orientation sharing an axis with 0/90/180/
## 270 degrees (both the old and new conventions agree there); a full
## sweep over non-axis angles is what actually proves it.
func test_the_facing_wedges_position_and_rotation_agree_across_a_full_sweep() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	var view := HitVolumeView.new()
	add_child_autofree(view)

	const SAMPLES := 24
	for i in range(SAMPLES):
		unit.orientation = i * TAU / SAMPLES
		view.setup(unit, DataLibrary.material_table())
		var wedge: MeshInstance3D = view.get_child(1)
		var position_dir := Vector2(wedge.position.x, wedge.position.z).normalized()
		var rotation_dir_3d: Vector3 = wedge.basis * Vector3(0.0, 0.0, 1.0)
		var rotation_dir := Vector2(rotation_dir_3d.x, rotation_dir_3d.z).normalized()
		assert_almost_eq(
			position_dir.x,
			rotation_dir.x,
			0.001,
			"orientation %f: wedge position/rotation disagree on x" % unit.orientation
		)
		assert_almost_eq(
			position_dir.y,
			rotation_dir.y,
			0.001,
			"orientation %f: wedge position/rotation disagree on z" % unit.orientation
		)


## docs/10 taskblock03 E3: "the wedge shows committed state — it must show
## PREVIEW." Both the wedge and the part meshes must rotate to
## preview_orientation, never the committed unit.orientation, whenever one
## is set.
func test_preview_orientation_moves_both_the_wedge_and_the_part_meshes() -> void:
	var unit := _torso_unit(Vector2i(2, 3), 0)
	unit.orientation = 0.0
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	var committed_wedge_x: float = (view.get_child(1) as MeshInstance3D).position.x
	var committed_mesh_transform: Transform3D = (view.get_child(2) as MeshInstance3D).transform

	view.preview_orientation = PI / 2.0
	view.refresh()

	var preview_wedge_x: float = (view.get_child(1) as MeshInstance3D).position.x
	var preview_mesh_transform: Transform3D = (view.get_child(2) as MeshInstance3D).transform
	assert_ne(preview_wedge_x, committed_wedge_x, "the wedge must move to the preview")
	assert_ne(preview_mesh_transform, committed_mesh_transform, "the body itself must also rotate")
	assert_almost_eq(unit.orientation, 0.0, 0.0001, "the real unit is never mutated by a preview")


func test_null_preview_orientation_renders_the_committed_orientation() -> void:
	var unit := _torso_unit(Vector2i(2, 3), 0)
	unit.orientation = 0.5
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.preview_orientation = null
	view.setup(unit, DataLibrary.material_table())

	var expected: BoxPlacement = UnitGeometry.placements(unit)[0]
	var mesh_instance: MeshInstance3D = view.get_child(2)
	assert_eq(mesh_instance.transform, expected.transform.translated_local(expected.box.center))


func test_team_marker_sits_at_the_units_cell_and_matches_its_squad_color() -> void:
	var unit := _torso_unit(Vector2i(2, 3), 1)
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	var marker: MeshInstance3D = view.get_child(0)
	assert_almost_eq(marker.position.x, 2.0, 0.0001)
	assert_almost_eq(marker.position.z, 3.0, 0.0001)
	var material: StandardMaterial3D = marker.material_override
	assert_eq(material.albedo_color, WorldPalette.TEAM_B)


func test_set_selected_brightens_the_team_marker() -> void:
	var unit := _torso_unit(Vector2i(0, 0), 0)
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	var marker: MeshInstance3D = view.get_child(0)
	var before: Color = (marker.material_override as StandardMaterial3D).albedo_color

	view.set_selected(true)
	var after: Color = (marker.material_override as StandardMaterial3D).albedo_color

	assert_ne(before, after, "selecting must visibly brighten the marker")
	assert_eq(before, WorldPalette.TEAM_A, "sanity: unselected must be the plain team color")


## docs/10 taskblock03 G: "a unit with no matrix docked (a shell)... needs
## to read as down at a glance."
func test_is_downed_is_true_for_a_shell_and_false_for_a_piloted_unit() -> void:
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.unit = _shell_unit(Vector2i(0, 0))
	assert_true(view.is_downed())

	view.unit = _torso_unit(Vector2i(0, 0))
	assert_false(view.is_downed())


## taskblock-26 Pass A3 (re-fix): the first fix only checked the wedge
## against `EXTRACTION_TILE_HEIGHT`/`TEAM_MARKER_Y` — it genuinely
## interpenetrated `board_view.gd`'s own `OVERWATCH_ARC_HEIGHT` box (top
## face 0.05), which the first fix never checked against. Read the real
## node back (CLAUDE.md's own rule): the wedge's bottom face must clear
## every ground-tier marker's own top face, not just the two named in the
## original report.
func test_the_facing_wedge_clears_every_ground_tier_marker_including_the_overwatch_arc() -> void:
	var unit := _torso_unit(Vector2i(2, 3), 0)
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	var wedge: MeshInstance3D = view.get_child(1)
	var wedge_box: BoxMesh = wedge.mesh
	var wedge_bottom: float = wedge.position.y - wedge_box.size.y / 2.0
	# board_view.gd's own ground-tier markers, each a 0.02-thick box
	# centered on its own HEIGHT constant (_marker()) — top face is
	# height + 0.01. OVERWATCH_ARC_HEIGHT is the tallest of these (the
	# team marker disc is checked separately below — it's owned by
	# HitVolumeView itself, not board_view.gd).
	var marker_tops: Array[float] = [
		BoardView.REACHABLE_HEIGHT + 0.01,
		BoardView.GHOST_HEIGHT + 0.01,
		BoardView.OVERWATCH_ARC_HEIGHT + 0.01,
		BoardView.EXTRACTION_TILE_HEIGHT + 0.01,
		BoardView.WALL_INDICATOR_HEIGHT + 0.01,
	]
	for top: float in marker_tops:
		assert_true(
			wedge_bottom > top, "wedge bottom %f must clear marker top %f" % [wedge_bottom, top]
		)
	var team_marker_top: float = (
		HitVolumeView.TEAM_MARKER_Y + HitVolumeView.TEAM_MARKER_HEIGHT / 2.0
	)
	assert_true(
		wedge_bottom > team_marker_top,
		(
			"wedge bottom %f must clear the team marker's own top %f too"
			% [wedge_bottom, team_marker_top]
		)
	)


## taskblock-27 Pass C2: the tb26 A3 fix (and its own first re-fix) never
## checked the team marker at all — `TEAM_MARKER_Y` (0.01) was IDENTICAL
## to `BoardView.EXTRACTION_TILE_HEIGHT` (0.010), a real co-planar pair
## every unit standing on its own extraction tile hit, unreported until
## this pass enumerated the whole ground-overlay height ladder. Both are
## 0.02-thick (disc/box), so this checks the two spans don't overlap at
## all, not just that the centers differ.
func test_team_marker_no_longer_coplanar_with_the_extraction_tile_marker() -> void:
	var team_marker_bottom: float = (
		HitVolumeView.TEAM_MARKER_Y - HitVolumeView.TEAM_MARKER_HEIGHT / 2.0
	)
	var extraction_top: float = BoardView.EXTRACTION_TILE_HEIGHT + 0.01
	assert_gt(
		team_marker_bottom,
		extraction_top,
		"the team marker's own bottom face must clear the extraction tile's own top face"
	)


## tb32 Pass D (BR27.07): "only the current unit shows a facing marker at
## all — the marker's presence indicates whose turn it is, not a color."
## Supervisor clarification: "facing marker" means the WHOLE disk/facing-
## pip assembly (ground disk + wedge together), not the wedge alone —
## set_active_turn toggles both's visibility; neither is tinted for this
## anymore (plain team/selected color only).
func test_set_active_turn_true_shows_the_whole_disk_and_wedge_assembly() -> void:
	var unit := _torso_unit(Vector2i(0, 0), 0)
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	var marker: MeshInstance3D = view.get_child(0)
	var wedge: MeshInstance3D = view.get_child(1)
	marker.visible = false
	wedge.visible = false

	view.set_active_turn(true)

	assert_true(marker.visible)
	assert_true(wedge.visible)


func test_set_active_turn_false_hides_the_whole_disk_and_wedge_assembly() -> void:
	var unit := _torso_unit(Vector2i(0, 0), 0)
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	view.set_active_turn(true)
	view.set_active_turn(false)

	var marker: MeshInstance3D = view.get_child(0)
	var wedge: MeshInstance3D = view.get_child(1)
	assert_false(marker.visible, "only the current unit shows a facing marker at all")
	assert_false(wedge.visible, "only the current unit shows a facing marker at all")


func test_set_active_turn_never_recolors_the_ground_marker() -> void:
	var unit := _torso_unit(Vector2i(0, 0), 0)
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	view.set_active_turn(true)

	var marker: MeshInstance3D = view.get_child(0)
	var material: StandardMaterial3D = marker.material_override
	assert_eq(material.albedo_color, WorldPalette.team_color(unit.squad_id))


func test_refresh_reapplies_the_last_active_turn_visibility() -> void:
	var unit := _torso_unit(Vector2i(0, 0), 0)
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	view.set_active_turn(true)

	view.refresh()

	var marker: MeshInstance3D = view.get_child(0)
	var wedge: MeshInstance3D = view.get_child(1)
	assert_true(marker.visible, "a mid-turn refresh must not flash a non-active marker visible")
	assert_true(wedge.visible, "a mid-turn refresh must not flash a non-active wedge visible")


## tb32 Pass B (corrected design): the fade applies to this unit's own
## REAL body mesh — not a separate ghost drawn elsewhere, which left the
## real body fully opaque underneath a barely-visible decoy (confirmed
## live to read as "something faint happening," not an actual fade).
func test_set_occlusion_faded_true_applies_a_translucent_gray_override() -> void:
	var unit := _torso_unit(Vector2i(0, 0), 0)
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	var torso_mesh: MeshInstance3D = view.get_child(2)
	assert_null(torso_mesh.material_override, "sanity: nothing overridden yet")

	view.set_occlusion_faded(true)

	var material: StandardMaterial3D = torso_mesh.material_override
	assert_not_null(material, "the real body mesh must get a material_override")
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_almost_eq(material.albedo_color.a, HitVolumeView.OCCLUSION_FADE_ALPHA, 0.001)
	var team_color: Color = WorldPalette.team_color(0)
	assert_ne(
		Vector3(material.albedo_color.r, material.albedo_color.g, material.albedo_color.b),
		Vector3(team_color.r, team_color.g, team_color.b),
		"must be gray-tinted, not the team color"
	)


func test_set_occlusion_faded_false_clears_the_override() -> void:
	var unit := _torso_unit(Vector2i(0, 0), 0)
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	view.set_occlusion_faded(true)

	view.set_occlusion_faded(false)

	var torso_mesh: MeshInstance3D = view.get_child(2)
	assert_null(torso_mesh.material_override, "clearing the fade must restore the real material")


## `highlight_part()`'s own next_pass chain lives on `mesh.material`, not
## `material_override` — the two must never fight.
func test_occlusion_fade_never_touches_the_ground_marker_or_wedge() -> void:
	var unit := _torso_unit(Vector2i(0, 0), 0)
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	var marker: MeshInstance3D = view.get_child(0)
	var wedge: MeshInstance3D = view.get_child(1)
	# Both already carry their OWN material_override from construction
	# (`_build_team_marker`/`_build_facing_wedge`) — the fade must leave
	# those exact resources alone, not merely "some material or other."
	var marker_material_before: Material = marker.material_override
	var wedge_material_before: Material = wedge.material_override

	view.set_occlusion_faded(true)

	assert_eq(
		marker.material_override,
		marker_material_before,
		"the marker keeps its own team/active-turn material untouched"
	)
	assert_eq(
		wedge.material_override,
		wedge_material_before,
		"the wedge is never touched by the occlusion fade"
	)


func test_refresh_reapplies_a_live_occlusion_fade() -> void:
	var unit := _torso_unit(Vector2i(0, 0), 0)
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	view.set_occlusion_faded(true)

	view.refresh()

	var torso_mesh: MeshInstance3D = view.get_child(2)
	assert_not_null(
		torso_mesh.material_override, "a mid-fade refresh must not flash the real material back"
	)


func test_a_downed_unit_kills_its_facing_wedge() -> void:
	var unit := _shell_unit(Vector2i(0, 0))
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	assert_eq(view.get_child_count(), 2, "team marker + one part mesh, no wedge in between")


## docs/10 taskblock05 F3: DOWN is a real Pose now, passed to
## UnitGeometry.placements() explicitly (Unit.is_downed() decides whether
## to) — the view no longer applies any rotation of its own on top, so the
## rendered mesh's transform must match placements(unit, ..., Poses.down())
## exactly, and read as lying down relative to standing upright.
func test_a_downed_units_body_matches_its_own_posed_geometry_exactly() -> void:
	var unit := _shell_unit(Vector2i(2, 3))
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	var posed: BoxPlacement = UnitGeometry.placements(unit, null, Poses.down())[0]
	var expected: Transform3D = posed.transform.translated_local(posed.box.center)
	var actual: Transform3D = (view.get_child(1) as MeshInstance3D).transform

	assert_eq(actual, expected, "the view must render exactly what the posed geometry says")

	var upright: BoxPlacement = UnitGeometry.placements(unit)[0]
	assert_false(
		posed.transform.basis.is_equal_approx(upright.transform.basis),
		"DOWN must actually rotate the geometry relative to standing upright"
	)


func test_a_downed_units_team_marker_is_dimmer_than_a_piloted_units() -> void:
	var downed_view := HitVolumeView.new()
	add_child_autofree(downed_view)
	downed_view.setup(_shell_unit(Vector2i(0, 0), 0), DataLibrary.material_table())

	var piloted_view := HitVolumeView.new()
	add_child_autofree(piloted_view)
	piloted_view.setup(_torso_unit(Vector2i(0, 0), 0), DataLibrary.material_table())

	var downed_color: Color = (
		((downed_view.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D)
		. albedo_color
	)
	var piloted_color: Color = (
		((piloted_view.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D)
		. albedo_color
	)

	assert_almost_eq(downed_color.r, piloted_color.r * HitVolumeView.DOWNED_MARKER_DIM, 0.0001)
	assert_lt(downed_color.r, piloted_color.r, "the downed marker must actually read dimmer")


## docs/09 taskblock06 Pass I2: Part.mesh_scene / show_hit_volumes tests
## live in test_hit_volume_view_mesh_scene.gd — split out purely to stay
## under gdlint's max-public-methods.


func _rim_of(instance: MeshInstance3D) -> StandardMaterial3D:
	var box_mesh: BoxMesh = instance.mesh
	var material: StandardMaterial3D = box_mesh.material
	return material.next_pass


## docs/10 taskblock05 C: "hovering a part highlights it in the world" —
## chains one more grown-outline pass after the part's own team rim, and
## only that part's own meshes, never a sibling's.
func test_highlight_part_chains_a_glow_onto_only_that_parts_own_mesh() -> void:
	var built: Dictionary = _torso_with_arm_unit(Vector2i(0, 0))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	view.highlight_part(arm)

	var torso_mesh := view.get_child(2) as MeshInstance3D
	var arm_mesh := view.get_child(3) as MeshInstance3D
	assert_null(_rim_of(torso_mesh).next_pass)
	assert_not_null(_rim_of(arm_mesh).next_pass)
	assert_eq(
		(_rim_of(arm_mesh).next_pass as StandardMaterial3D).albedo_color,
		WorldPalette.HOVER_HIGHLIGHT
	)


func test_clear_highlight_removes_the_glow() -> void:
	var built: Dictionary = _torso_with_arm_unit(Vector2i(0, 0))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	view.highlight_part(arm)

	view.clear_highlight()

	var arm_mesh := view.get_child(3) as MeshInstance3D
	assert_null(_rim_of(arm_mesh).next_pass)


## A highlight must survive the rebuild refresh() does after damage — the
## hovered part hasn't changed just because something else on the unit did.
func test_a_highlight_survives_a_refresh() -> void:
	var built: Dictionary = _torso_with_arm_unit(Vector2i(0, 0))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	view.highlight_part(arm)

	view.refresh()

	var arm_mesh := view.get_child(3) as MeshInstance3D
	assert_not_null(_rim_of(arm_mesh).next_pass)
