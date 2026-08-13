extends GutTest

## taskblock-69 Pass C — **the derived facing reaches a real click, and the ghost shows it.**
##
## `test_placement_facing.gd` pins the rule; this pins the wiring. The derivation is only worth
## anything if the click that authors a placement and the preview drawn before it are reading the
## same answer — which is the arrangement `placement_target` already has and the reason
## `placement_facing` is its counterpart rather than a second derivation inside the ghost.
##
## **The window matters and is easy to get wrong.** `PlacementGhostModule` sets the editor's
## `struck_normal` / `struck_point` for the duration of one preview and restores them immediately
## after. A facing asked outside that window sees `null` for both and falls back to the panel — so
## the ghost would quietly preview an unturned veneer for a click that will author a turned one.
## `test_the_ghost_previews_the_derived_facing` is what catches that.


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _overlay() -> ControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	var overlay: ControlOverlay = ControlOverlay.for_mode(ViewModes.editor())
	battle.set_overlay(overlay)
	return overlay


func _picking(overlay: ControlOverlay) -> BoardInspectModule:
	return overlay.module(&"board_inspect") as BoardInspectModule


func _armed(overlay: ControlOverlay, part: StringName) -> EditorModule:
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	editor.active_tool = &"place_terrain"
	editor.selected_part = part
	return editor


## **A side click authors a veneer facing back at the wall it was hung off.** Driven through the
## real click router, and read off the `MapPlacement` the click produced.
func test_a_side_click_authors_a_veneer_facing_the_piece_it_hangs_from() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _armed(overlay, &"ledge_veneer")
	editor.controller.place(Vector2i(3, 3), &"wall", MapPlacement.KIND_BLOCKER, 0.0)

	(
		_picking(overlay)
		. board_clicked
		. emit(
			{
				"kind": Enums.HitKind.PART,
				"unit": null,
				"part": null,
				"cell": Vector2i(3, 3),
				"normal": Vector3.RIGHT,
				"point": Vector3(3.5, 1.0, 3.0),
			}
		)
	)

	# The placement lands one step east of the wall, per `FacePlacement`.
	var authored: MapPlacement = null
	for placement: MapPlacement in editor.controller.placements_at(Vector2i(4, 3)):
		if placement.part_id == &"ledge_veneer":
			authored = placement
	assert_not_null(authored, "the click authored no veneer beside the wall")
	if authored == null:
		return

	var points: Vector2 = BodyProjector.forward_for(authored.facing)
	gut.p(
		"  authored facing %+.3f -> forward (%+.2f, %+.2f)" % [authored.facing, points.x, points.y]
	)
	assert_almost_eq(points.x, -1.0, 0.001, "the veneer must face back west, at the wall")
	assert_almost_eq(points.y, 0.0, 0.001, "and not off along Z")


## **A top click authors a ladder against the edge the author pointed at.** The same route, the
## other rule, and a part that is not a veneer — *"ladders may need this behavior as well"*, and the
## supervisor's answer was every blocker that has a facing.
func test_a_top_click_authors_a_ladder_on_the_edge_it_was_clicked_near() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _armed(overlay, &"ladder")
	editor.controller.place(Vector2i(2, 2), &"ship_floor", MapPlacement.KIND_SURFACE, 0.0)

	(
		_picking(overlay)
		. board_clicked
		. emit(
			{
				"kind": Enums.HitKind.PART,
				"unit": null,
				"part": null,
				"cell": Vector2i(2, 2),
				"normal": Vector3.UP,
				"point": Vector3(2.0, 0.0, 1.6),
			}
		)
	)

	var authored: MapPlacement = null
	for placement: MapPlacement in editor.controller.placements_at(Vector2i(2, 2)):
		if placement.part_id == &"ladder":
			authored = placement
	assert_not_null(authored, "the click authored no ladder")
	if authored == null:
		return

	var points: Vector2 = BodyProjector.forward_for(authored.facing)
	gut.p(
		"  authored facing %+.3f -> forward (%+.2f, %+.2f)" % [authored.facing, points.x, points.y]
	)
	assert_almost_eq(
		points.y, -1.0, 0.001, "the ladder must face the -Z edge that was clicked near"
	)
	assert_almost_eq(points.x, 0.0, 0.001, "and not the X one")


## **A surface keeps the panel's own facing**, which is what makes a ramp directional. The
## derivation fills in the kinds whose facing no author could ever mean anything by, and this is
## the assertion that it stops there.
func test_a_ramp_still_takes_the_authored_facing_from_the_panel() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _armed(overlay, &"ramp")
	editor.panel.facing_field.value = PI
	var wanted: float = editor.facing()
	assert_gt(absf(wanted), 0.1, "sanity: the panel carries a facing at all")

	(
		_picking(overlay)
		. board_clicked
		. emit(
			{
				"kind": Enums.HitKind.PART,
				"unit": null,
				"part": null,
				"cell": Vector2i(2, 2),
				"normal": Vector3.UP,
				"point": Vector3(2.4, 0.0, 2.0),
			}
		)
	)

	var authored: MapPlacement = null
	for placement: MapPlacement in editor.controller.placements_at(Vector2i(2, 2)):
		if placement.part_id == &"ramp":
			authored = placement
	assert_not_null(authored, "the click authored no ramp")
	if authored == null:
		return
	assert_almost_eq(
		authored.facing, wanted, 0.0001, "a ramp's direction is stated by the author, not derived"
	)


## **The ghost previews the derived facing, not the panel's.** The one that fails if the facing is
## asked outside the window where the struck face is set — see the file header.
func test_the_ghost_previews_the_derived_facing() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _armed(overlay, &"ledge_veneer")
	var ghost: PlacementGhostModule = overlay.module(&"placement_ghost") as PlacementGhostModule
	editor.controller.place(Vector2i(3, 3), &"wall", MapPlacement.KIND_BLOCKER, 0.0)

	(
		_picking(overlay)
		. hovered_pick
		. emit(
			{
				"unit": null,
				"part": null,
				"cell": Vector2i(3, 3),
				"t": 1.0,
				"normal": Vector3.RIGHT,
				"point": Vector3(3.5, 1.0, 3.0),
			}
		)
	)
	assert_true(ghost.is_showing(), "nothing was previewed")
	var shown: Array[Transform3D] = ghost.ghost_transforms()
	assert_false(shown.is_empty(), "the ghost drew no boxes")
	var previewed_cell: Vector2i = ghost.target["cell"]

	(
		_picking(overlay)
		. board_clicked
		. emit(
			{
				"kind": Enums.HitKind.PART,
				"unit": null,
				"part": null,
				"cell": Vector2i(3, 3),
				"normal": Vector3.RIGHT,
				"point": Vector3(3.5, 1.0, 3.0),
			}
		)
	)
	var authored: MapPlacement = null
	for placement: MapPlacement in editor.controller.placements_at(previewed_cell):
		if placement.part_id == &"ledge_veneer":
			authored = placement
	assert_not_null(authored, "the click authored no veneer where the ghost said")
	if authored == null:
		return

	# The boxes that placement really produces, against the boxes the ghost drew.
	var real: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		DataLibrary.get_part(&"ledge_veneer"),
		previewed_cell,
		authored.facing,
		null,
		authored.height
	)
	assert_eq(shown.size(), real.size(), "the ghost drew a different number of boxes")
	for i in range(mini(shown.size(), real.size())):
		var expected: Transform3D = real[i].transform.translated_local(real[i].box.center)
		gut.p("  ghost box %d at %s, placement at %s" % [i, shown[i].origin, expected.origin])
		assert_almost_eq(
			shown[i].origin.distance_to(expected.origin),
			0.0,
			0.0001,
			"ghost box %d is not where the placement is" % i
		)

	# And the half a ghost still reading the panel would pass: it is not the unturned position.
	var flat: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		DataLibrary.get_part(&"ledge_veneer"), previewed_cell, 0.0, null, authored.height
	)
	assert_gt(
		shown[0].origin.distance_to(flat[0].transform.translated_local(flat[0].box.center).origin),
		0.1,
		"the ghost previewed the veneer against the edge an underived facing would have used"
	)
