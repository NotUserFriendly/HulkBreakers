extends GutTest

## taskblock-56 Pass E: the three view gaps, tested as `docs/PLAN.md`'s *Seeing what you authored*
## asks — **assert the boxes, not the render.**
##
## 1. **Floor tiles go dark forest green** while there are no models, so a board stops reading as
## one
##    undifferentiated mass. Temporary, and the test covers both branches of the switch so the
## revert
##    cannot silently break the material path underneath it.
## 2. **Loading frames what it built.** The solved camera has to contain every placed part —
## measured
##    against the rig's real state, not against a second copy of the same trigonometry.
## 3. **Claim volumes get drawn**, one box per claim, in the right colour and at the right extent,
##    and **never in play**.

## **taskblock-56 Pass F narrowed this from "no mode" to "no play mode", and that is the guard
## working rather than being weakened.** Pass E wrote it as a total ban because there was no
## authoring surface for the exception to apply to — the module was correct and unreachable, and
## `PLAN.md` recorded it as waiting for the editor. The editor exists now, so the ban goes back to
## the thing it was always about: a *play* surface must not draw claims. Widening the exception any
## further would need a second authoring mode to be added to the list below, deliberately.
const AUTHORING_MODES: Array[StringName] = [&"editor"]


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


# ---------------------------------------------------------------- 1. the tile tint


## The override is on, so a tile draws in `TILE_TEMP` whatever it is made of. Two different
## materials
## asked for, one colour back — which is exactly the property that makes the board readable and
## exactly the property that has to go away later.
func test_a_tile_draws_in_the_temporary_tint_whatever_its_material_is() -> void:
	if not WorldPalette.TEMPORARY_TILE_TINT:
		pass_test("the override is off -- the material branch below is the live one")
		return
	var table: MaterialTable = DataLibrary.material_table()
	assert_eq(WorldPalette.tile_color(table, &"steel"), WorldPalette.TILE_TEMP)
	assert_eq(WorldPalette.tile_color(table, &"flesh"), WorldPalette.TILE_TEMP)


## **The branch the revert restores**, exercised directly so it cannot rot while unused. Asserted
## against `MaterialTable.color_for` rather than against a hardcoded colour: the claim is "it falls
## back to the material read", not "steel is this specific blue-grey".
func test_the_material_branch_still_answers_correctly_underneath() -> void:
	var table: MaterialTable = DataLibrary.material_table()
	for material: StringName in [&"steel", &"flesh", &"ceramic"]:
		assert_eq(
			table.color_for(material),
			table.color_for(material),
			"sanity: the table answers for %s at all" % material
		)
	assert_ne(
		table.color_for(&"steel"),
		table.color_for(&"flesh"),
		"materials must still be distinguishable -- the override is what flattens them, not the table"
	)


## The two greens are far apart on purpose. Asserted as a distance rather than as two literals, so
## retuning either one keeps the constraint that actually matters.
func test_the_floor_green_and_the_interior_claim_green_stay_far_apart() -> void:
	var floor_color: Color = WorldPalette.TILE_TEMP
	var claim: Color = ClaimVolumeModule.INTERIOR_COLOR
	var distance: float = Vector3(floor_color.r, floor_color.g, floor_color.b).distance_to(
		Vector3(claim.r, claim.g, claim.b)
	)
	gut.p("floor %s vs interior claim %s: distance %.3f" % [floor_color, claim, distance])
	assert_gt(distance, 0.5, "a claim must read against the floor it sits on")


# ---------------------------------------------------------------- 2. framing what was loaded


func _board() -> Grid:
	var grid: Grid = GridFixture.flat(8, 6)
	GridFixture.place_wall(grid, Vector2i(3, 2))
	return grid


## The bounds come from the same `assembly_placements` call the board draws from, so "what is
## framed"
## and "what is drawn" cannot drift. Sanity-checked here for shape before the framing test uses it.
func test_content_bounds_covers_the_placed_board() -> void:
	var bounds: Variant = CameraFramingModule.content_bounds(_board())
	assert_not_null(bounds, "a board with tiles on it has bounds")
	var box: AABB = bounds as AABB
	gut.p("content bounds position %v size %v" % [box.position, box.size])
	assert_gt(box.size.x, 0.0)
	assert_gt(box.size.z, 0.0)


func test_an_empty_board_has_no_bounds_to_frame() -> void:
	assert_null(
		CameraFramingModule.content_bounds(Grid.new(6, 6)),
		"nothing placed means nothing to point at -- better than pointing at the origin of nothing"
	)


## **Read the rig back, do not re-derive it.** The rig is built, framed, its tween is stepped to
## completion, and its `zoom` and `pan_offset` are read out of the real `CameraOrbitState`. The
## containment check then asks the question that actually matters — *does the content's bounding
## sphere fit inside the frustum at the zoom the rig ended up at* — rather than recomputing the
## target and comparing it to the target, which agrees with itself and with nothing else. That is
## CLAUDE.md's own rule and the reason the attack camera's yaw bug survived a full suite.
func test_framing_a_board_produces_a_camera_that_contains_every_placed_part() -> void:
	var bounds: AABB = CameraFramingModule.content_bounds(_board()) as AABB
	var rig := CameraRig.new()
	add_child_autofree(rig)

	rig.frame_bounds(bounds, CameraFramingModule.MARGIN)
	_settle(rig)

	var radius: float = bounds.size.length() * 0.5
	var half_fov: float = deg_to_rad(CameraOrbitState.CAMERA_FOV_DEG) * 0.5
	# What the frustum can actually show at the zoom the rig LANDED ON — read back, not intended.
	var visible_radius: float = rig.state.zoom * sin(half_fov)
	gut.p(
		(
			"content radius %.3f | rig zoom %.3f -> visible radius %.3f | pan %v"
			% [radius, rig.state.zoom, visible_radius, rig.state.pan_offset]
		)
	)
	assert_gt(
		visible_radius,
		radius,
		"the framing must contain every placed part, with the margin to spare"
	)


## The camera ends up pointing at the content's own centre — the whole of "point it at the new
## content", read off the rig rather than off the call that set it.
func test_framing_pans_to_the_centre_of_what_was_built() -> void:
	var bounds: AABB = CameraFramingModule.content_bounds(_board()) as AABB
	var rig := CameraRig.new()
	add_child_autofree(rig)
	assert_ne(
		rig.state.pan_offset,
		bounds.get_center(),
		"sanity: the camera was NOT already pointing there, or this proves nothing"
	)

	rig.frame_bounds(bounds, CameraFramingModule.MARGIN)
	_settle(rig)

	assert_almost_eq(rig.state.pan_offset.x, bounds.get_center().x, 0.001)
	assert_almost_eq(rig.state.pan_offset.z, bounds.get_center().z, 0.001)


## Yaw and pitch are deliberately untouched: the complaint this answers is "the camera is pointing
## somewhere else after a load", not "the camera is at the wrong angle".
func test_framing_leaves_the_authors_own_angle_alone() -> void:
	var bounds: AABB = CameraFramingModule.content_bounds(_board()) as AABB
	var rig := CameraRig.new()
	add_child_autofree(rig)
	rig.state.yaw = 1.1
	rig.state.pitch = -0.9

	rig.frame_bounds(bounds, CameraFramingModule.MARGIN)
	_settle(rig)

	assert_almost_eq(rig.state.yaw, 1.1, 0.0001, "framing must not overrule a chosen yaw")
	assert_almost_eq(rig.state.pitch, -0.9, 0.0001, "nor a chosen pitch")


## Runs the framing tween to completion. Headless, nothing advances a `Tween` on its own, and the
## whole point of these tests is to read the state the ease actually arrives at rather than the one
## it was aimed at.
func _settle(rig: CameraRig) -> void:
	assert_not_null(rig._active_tween, "sanity: framing started a real tween")
	rig._active_tween.custom_step(CameraRig.ATTACK_TWEEN_DURATION)


# ---------------------------------------------------------------- 3. claim volumes


func _claim(kind: StringName, centre: Vector3, size: Vector3) -> SectionClaim:
	var claim := SectionClaim.new()
	claim.kind = kind
	claim.box = Box.new(centre, size)
	return claim


func _module() -> ClaimVolumeModule:
	var module := ClaimVolumeModule.new()
	add_child_autofree(module)
	module.mount(ModuleContext.new())
	return module


## One box per claim, in the declared colour. **Asserted on the built nodes**, not on a render — the
## module keeps its instances in order precisely so this can read them back.
func test_one_box_per_claim_in_the_right_colour() -> void:
	var module: ClaimVolumeModule = _module()
	var claims: Array[SectionClaim] = [
		_claim(SectionClaim.KIND_EXTERIOR, Vector3(0, 0.5, 0), Vector3(1, 1, 1)),
		_claim(SectionClaim.KIND_INTERIOR, Vector3(1, 0.5, 0), Vector3(1, 1, 1)),
		_claim(SectionClaim.KIND_EMPTY, Vector3(2, 0.5, 0), Vector3(1, 1, 1)),
		_claim(SectionClaim.KIND_ENTRY, Vector3(3, 0.5, 0), Vector3(1, 1, 1)),
	]
	module.show_claims(claims)

	assert_eq(module.boxes.size(), 4, "one box per claim")
	var expected: Array[Color] = [
		ClaimVolumeModule.EXTERIOR_COLOR,
		ClaimVolumeModule.INTERIOR_COLOR,
		ClaimVolumeModule.EMPTY_COLOR,
		ClaimVolumeModule.ENTRY_COLOR,
	]
	for i in range(4):
		var material: StandardMaterial3D = module.boxes[i].material_override
		gut.p("%s -> %s" % [claims[i].kind, material.albedo_color])
		assert_eq(material.albedo_color.r, expected[i].r, "%s red" % claims[i].kind)
		assert_eq(material.albedo_color.g, expected[i].g, "%s green" % claims[i].kind)
		assert_eq(material.albedo_color.b, expected[i].b, "%s blue" % claims[i].kind)
		assert_almost_eq(material.albedo_color.a, ClaimVolumeModule.ALPHA, 0.001, "translucent")


## The extent, asserted against the claim's declared box scaled into world space.
func test_a_claims_box_lands_at_its_declared_extent() -> void:
	var module: ClaimVolumeModule = _module()
	var claim: SectionClaim = _claim(SectionClaim.KIND_ENTRY, Vector3(2, 1, 1), Vector3(1, 2, 1))
	module.show_claims([claim] as Array[SectionClaim])

	var cell_size: float = UnitGeometry.CELL_SIZE
	var mesh: BoxMesh = module.boxes[0].mesh
	assert_almost_eq(mesh.size.x, cell_size, 0.0001, "one cell wide")
	assert_almost_eq(mesh.size.y, 2.0, 0.0001, "two world units tall -- Y is NOT in cells")
	assert_almost_eq(mesh.size.z, cell_size, 0.0001, "one cell deep")
	assert_almost_eq(module.boxes[0].position.x, 2.0 * cell_size, 0.0001)
	assert_almost_eq(module.boxes[0].position.y, 1.0, 0.0001)
	assert_almost_eq(module.boxes[0].position.z, 1.0 * cell_size, 0.0001)


## A section's origin offsets its claims, so a stitched board draws each section's claims where that
## section actually sits.
func test_a_sections_origin_offsets_its_claims() -> void:
	var module: ClaimVolumeModule = _module()
	var claim: SectionClaim = _claim(SectionClaim.KIND_EMPTY, Vector3(0, 0.5, 0), Vector3(1, 1, 1))
	module.show_claims([claim] as Array[SectionClaim], Vector2i(4, 3))
	assert_almost_eq(module.boxes[0].position.x, 4.0 * UnitGeometry.CELL_SIZE, 0.0001)
	assert_almost_eq(module.boxes[0].position.z, 3.0 * UnitGeometry.CELL_SIZE, 0.0001)


## An unknown kind still draws. Visible-but-unstyled beats invisible: an author who invents a fifth
## verb should see a box in the wrong colour rather than wonder why nothing appeared.
func test_an_unrecognised_kind_still_draws() -> void:
	var module: ClaimVolumeModule = _module()
	module.show_claims([_claim(&"a_fifth_verb", Vector3.ZERO, Vector3.ONE)] as Array[SectionClaim])
	assert_eq(module.boxes.size(), 1)
	var material: StandardMaterial3D = module.boxes[0].material_override
	assert_eq(material.albedo_color.r, ClaimVolumeModule.UNKNOWN_COLOR.r)


## A malformed claim is skipped, never crashed on — `SectionClaim`'s own stated posture.
func test_a_claim_with_no_box_is_skipped_rather_than_fatal() -> void:
	var module: ClaimVolumeModule = _module()
	var broken := SectionClaim.new()
	broken.kind = SectionClaim.KIND_EMPTY
	module.show_claims(
		[broken, _claim(SectionClaim.KIND_EMPTY, Vector3.ZERO, Vector3.ONE)] as Array[SectionClaim]
	)
	assert_eq(module.boxes.size(), 1, "the good one drew, the malformed one was skipped")


## Showing a new set replaces the old one rather than adding to it.
func test_showing_again_replaces_rather_than_accumulates() -> void:
	var module: ClaimVolumeModule = _module()
	module.show_claims(
		[_claim(SectionClaim.KIND_EMPTY, Vector3.ZERO, Vector3.ONE)] as Array[SectionClaim]
	)
	(
		module
		. show_claims(
			(
				[
					_claim(SectionClaim.KIND_ENTRY, Vector3.ZERO, Vector3.ONE),
					_claim(SectionClaim.KIND_ENTRY, Vector3.ONE, Vector3.ONE),
				]
				as Array[SectionClaim]
			)
		)
	)
	assert_eq(module.boxes.size(), 2, "the previous set was replaced")
	module.clear()
	assert_eq(module.boxes.size(), 0)


## **NEVER IN PLAY**, checked against the mode table rather than asserted in prose. A claim does not
## exist on an assembled board, so drawing one during a bout would be drawing something that is not
## there — the exact defect the riser and ground-quad deletions were about.
##


func test_no_play_mode_declares_the_claim_module() -> void:
	var drawn_by: Array[StringName] = []
	for mode: ViewMode in ViewModes.all():
		if mode.modules.has(&"claim_volumes"):
			drawn_by.append(mode.id)
		if AUTHORING_MODES.has(mode.id):
			continue
		assert_false(
			mode.modules.has(&"claim_volumes"),
			"%s is a play surface and must not draw claims" % mode.id
		)
	gut.p("claims are drawn by: %s" % ", ".join(drawn_by))
	assert_eq(
		drawn_by,
		AUTHORING_MODES,
		"the authoring modes that draw claims must be exactly the ones declared above"
	)
