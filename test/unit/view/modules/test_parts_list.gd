extends GutTest

## taskblock-58 Pass E: **the parts list in the Inspect slot, and the exclusion that makes the
## share safe.**
##
## *"It goes where Inspect goes because while placing you cannot be selecting."* Pass D turned that
## from a claim about the author's intent into a claim about the code — `select` and the three
## `place_*` verbs are entries in one vocabulary and `active_tool` holds exactly one — so what is
## asserted here is that the two surfaces are never up together, not merely that they usually are
## not.


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _overlay() -> ControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	# `_ready()` installs the player mode; a bare surface neutralises it before the editor goes on.
	battle.set_overlay(ControlOverlay.new())
	var overlay: ControlOverlay = ControlOverlay.for_mode(ViewModes.editor())
	battle.set_overlay(overlay)
	return overlay


func _parts(overlay: ControlOverlay) -> PartsListModule:
	return overlay.module(&"parts_list") as PartsListModule


func _inspect(overlay: ControlOverlay) -> InspectModule:
	return overlay.module(&"inspect") as InspectModule


func _bar(overlay: ControlOverlay) -> EditorBarModule:
	return overlay.module(&"editor_bar") as EditorBarModule


## The editor mode mounts it, and it takes the slot the taskblock names.
func test_the_editor_mounts_the_parts_list_in_the_inspect_slot() -> void:
	var overlay: ControlOverlay = _overlay()
	var parts: PartsListModule = _parts(overlay)

	assert_not_null(parts, "the editor mode declares no parts list")
	assert_eq(parts.preferred_slot(), ModuleSlots.INSPECT_PANEL)
	assert_eq(
		_inspect(overlay).preferred_slot(),
		parts.preferred_slot(),
		"sanity: the two really do share a slot, which is what the exclusion is for"
	)
	assert_false(parts.is_showing(), "it starts closed rather than covering the inspector")


## **THE ACCEPTANCE.** Whichever way round they are opened, only one is ever up.
func test_the_list_and_inspect_are_never_up_together() -> void:
	var overlay: ControlOverlay = _overlay()
	var parts: PartsListModule = _parts(overlay)
	var inspect: InspectModule = _inspect(overlay)

	inspect.open_cell(Vector2i(1, 1), DataLibrary.get_part(&"wall"))
	assert_true(inspect.is_showing(), "sanity: the inspector opened")

	parts.open("terrain", [&"wall"] as Array[StringName])

	assert_true(parts.is_showing(), "the list opened")
	assert_false(inspect.is_showing(), "and took the slot rather than stacking in it")
	assert_false(
		parts.is_showing() and inspect.is_showing(), "two surfaces in one rect is the collision"
	)


## Opening a place tool from the bar is the real route in, so it is the route tested — not just the
## module's own `open`.
func test_arming_a_place_tool_opens_the_list_on_that_tools_parts() -> void:
	var overlay: ControlOverlay = _overlay()
	var bar: EditorBarModule = _bar(overlay)
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	var parts: PartsListModule = _parts(overlay)

	(bar.tool_buttons[&"place_terrain"] as Button).pressed.emit()

	assert_true(parts.is_showing(), "arming a place verb opened nothing")
	var offered: Array[StringName] = EditorTools.part_ids_for(
		&"place_terrain", editor.placeable_part_ids()
	)
	assert_eq(bar.list.shown_ids(), offered, "the list must offer the active tool's parts")
	assert_has(offered, &"wall", "sanity: terrain is offered")
	assert_does_not_have(offered, &"crate", "and a crate is not terrain")


## The list is searchable in its new home — the taskblock asks for it and moving a widget is exactly
## the change that can quietly cost it.
func test_the_list_is_still_searchable_where_it_now_lives() -> void:
	var overlay: ControlOverlay = _overlay()
	var bar: EditorBarModule = _bar(overlay)

	(bar.tool_buttons[&"place_part"] as Button).pressed.emit()
	var before: int = bar.list.shown_ids().size()
	bar.list.apply_filter("crate")

	assert_gt(before, 1, "sanity: there was something to narrow")
	assert_true(bar.list.shown_ids().has(&"crate"), "searching lost the thing searched for")
	assert_lt(bar.list.shown_ids().size(), before, "it did not narrow")


## **One widget, two callers**, which is what the supervisor chose over a second list for Load. It
## opens in the same slot, which is the one oddity of the arrangement and is deliberate.
func test_load_opens_the_same_widget() -> void:
	var overlay: ControlOverlay = _overlay()
	var bar: EditorBarModule = _bar(overlay)
	var parts: PartsListModule = _parts(overlay)

	(bar.tool_buttons[&"place_terrain"] as Button).pressed.emit()
	var placing: SearchableList = bar.list

	bar.load_button.pressed.emit()

	assert_same(bar.list, placing, "Load built a second list instead of reusing the one")
	assert_true(parts.is_showing(), "and it opens in the parts list's own slot")


func _ghost(overlay: ControlOverlay) -> PlacementGhostModule:
	return overlay.module(&"placement_ghost") as PlacementGhostModule


func _picking(overlay: ControlOverlay) -> BoardInspectModule:
	return overlay.module(&"board_inspect") as BoardInspectModule


## **THE PASS'S REAL ACCEPTANCE**: *"what appears is what the ghost showed — a placement that
## surprises is the defect this exists to prevent."*
##
## Asserted as the ghost's own transform against the authored placement's, both read back rather
## than re-derived. It cannot fail while the wiring is real, because `EditorModule.placement_target`
## is the single answer both of them ask — which is the point: the test checks the wiring, not that
## two formulas agree.
##
## **taskblock-59 Pass A: this was hovering the wall's TOP face, and that case never worked.** The
## ghost drew a wall stacked on a wall, the model accepted it, and the board refused it — a second
## blocker on one cell, which `Grid.blockers` cannot hold. The test passed throughout because it
## compared the ghost against `EditorController.placements`, which is the model, and never against
## the board. **The acceptance is "what appears", and nothing appeared.** It hovers a SIDE face now,
## which lands in the neighbouring cell and is a placement the board really draws; the top face has
## its own test below, asserting the ghost declines to promise it.
func test_what_the_ghost_showed_is_what_gets_placed() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	var ghost: PlacementGhostModule = _ghost(overlay)
	editor.active_tool = &"place_terrain"
	editor.selected_part = &"wall"

	# A wall already standing, so there is a face to click and a top to land on.
	editor.struck_normal = null
	editor.controller.place(Vector2i(3, 3), &"wall", MapPlacement.KIND_BLOCKER, 0.0)

	# Hover its east face: the pick the board picker would report. A side normal lands the placement
	# in the neighbouring cell, which is empty and can hold it.
	_picking(overlay).hovered_pick.emit(
		{"unit": null, "part": null, "cell": Vector2i(3, 3), "t": 1.0, "normal": Vector3.RIGHT}
	)

	assert_true(ghost.is_showing(), "nothing was previewed")
	var previewed: Dictionary = ghost.target.duplicate()
	var shown: Array[Transform3D] = ghost.ghost_transforms()
	assert_false(shown.is_empty(), "the ghost drew no boxes")

	# Now the click, through the real router.
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
			}
		)
	)

	var authored: MapPlacement = null
	for placement: MapPlacement in editor.controller.placements_at(previewed["cell"]):
		if placement.part_id == &"wall" and is_equal_approx(placement.height, previewed["height"]):
			authored = placement
	gut.p(
		(
			"  ghost at %s h=%.2f -> authored %s"
			% [previewed["cell"], previewed["height"], "yes" if authored != null else "NO"]
		)
	)
	assert_not_null(authored, "the click did not author where the ghost said it would")

	# And the drawn boxes sit exactly where that placement's own geometry does.
	var real: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		DataLibrary.get_part(&"wall"), previewed["cell"], editor.facing(), null, authored.height
	)
	assert_eq(shown.size(), real.size(), "the ghost drew a different number of boxes")
	for i in range(mini(shown.size(), real.size())):
		var expected: Transform3D = real[i].transform.translated_local(real[i].box.center)
		assert_almost_eq(
			shown[i].origin.distance_to(expected.origin),
			0.0,
			0.0001,
			"ghost box %d is not where the placement is" % i
		)


## A ghost that lingered would be describing a click that lands somewhere else — the surprise this
## exists to prevent rather than a cosmetic lag.
func test_the_ghost_clears_when_there_is_nothing_to_preview() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	var ghost: PlacementGhostModule = _ghost(overlay)
	editor.active_tool = &"place_terrain"
	editor.selected_part = &"wall"

	_picking(overlay).hovered_pick.emit(
		{"unit": null, "part": null, "cell": Vector2i(2, 2), "t": 1.0, "normal": Vector3.UP}
	)
	assert_true(ghost.is_showing(), "sanity: something was previewed")

	_picking(overlay).hovered_pick.emit({})

	assert_false(ghost.is_showing(), "the cursor left the board and the ghost stayed")
	assert_true(ghost.target.is_empty(), "and it still claims a target")


## Nothing to preview under a verb that places nothing, so nothing is drawn.
func test_no_ghost_under_a_tool_that_places_nothing() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	var ghost: PlacementGhostModule = _ghost(overlay)
	editor.selected_part = &"wall"

	for tool: StringName in [&"select", &"scale", &"delete", &"place_map_thing"]:
		editor.active_tool = tool
		_picking(overlay).hovered_pick.emit(
			{"unit": null, "part": null, "cell": Vector2i(2, 2), "t": 1.0, "normal": Vector3.UP}
		)
		assert_false(ghost.is_showing(), "%s previewed a placement it will not make" % tool)


## taskblock-59 Pass A: **the ghost does not promise a placement the board cannot hold.**
##
## Clicking the top face of a wall reads as "stack another one on it" and is not expressible — a
## cell holds one blocker, and `MapPlacement.height` is a surface's field. The preview drew it
## anyway, which is how *"clicking a support pillar on top of another support pillar makes an
## invisible pillar"* looked from the author's side: the editor showed them the thing, took the
## click, and then drew nothing ever again.
##
## **Both halves are asserted**, because either alone would be a half-fixed lie: nothing is
## previewed, and nothing is authored.
func test_no_ghost_where_the_placement_would_be_refused() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	var ghost: PlacementGhostModule = _ghost(overlay)
	editor.active_tool = &"place_terrain"
	editor.selected_part = &"wall"
	editor.controller.place(Vector2i(3, 3), &"wall", MapPlacement.KIND_BLOCKER, 0.0)

	_picking(overlay).hovered_pick.emit(
		{"unit": null, "part": null, "cell": Vector2i(3, 3), "t": 1.0, "normal": Vector3.UP}
	)

	gut.p("refusal: %s" % editor.placement_refusal(Vector2i(3, 3)))
	assert_false(ghost.is_showing(), "the ghost promised a wall the board has nowhere to put")
	assert_eq(
		editor.controller.placements_at(Vector2i(3, 3)).size(),
		1,
		"sanity: nothing was authored by the hover itself"
	)
	assert_false(editor.apply_tool_at(Vector2i(3, 3)), "and the click that follows authors nothing")
	assert_eq(editor.controller.placements_at(Vector2i(3, 3)).size(), 1, "the model took it anyway")


## **taskblock-69 Pass B: the ghost shows the facing the placement will get.**
##
## `_drawn_facing` returned `0.0` for a blocker, and that was correct while `BoardView._spawn_
## blocker` discarded the facing too — a ghost showing a rotation the board was about to throw away
## would have been the surprise the module exists to prevent. Pass A took the board to
## `UnitGeometry.blocker_placements`, which reads the record, so `0.0` became the answer that lies.
##
## Asserted the same way `test_what_the_ghost_showed_is_what_gets_placed` above is: the ghost's own
## transforms read back off its meshes, against the placement the click really authored. **The
## facing is set on the real panel spinbox**, so it travels the route an author's does.
func test_the_ghost_shows_a_blockers_authored_facing() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	var ghost: PlacementGhostModule = _ghost(overlay)
	editor.active_tool = &"place_terrain"
	editor.selected_part = &"ledge_veneer"
	editor.panel.facing_field.value = PI / 2.0
	# **Read back rather than assumed.** The spinbox has a 0.01 step measured from its own `-TAU`
	# minimum, so it snaps a quarter turn to 1.5668 — close enough to be a quarter turn and not
	# equal to `PI / 2.0`. The panel is the authority on what the author asked for, so it is asked.
	var wanted: float = editor.facing()
	assert_almost_eq(wanted, PI / 2.0, 0.01, "sanity: the panel carries about a quarter turn")
	assert_gt(absf(wanted), 0.1, "and it is emphatically not zero")

	editor.struck_normal = null
	_picking(overlay).hovered_pick.emit(
		{"unit": null, "part": null, "cell": Vector2i(2, 2), "t": 1.0, "normal": Vector3.UP}
	)

	assert_true(ghost.is_showing(), "nothing was previewed")
	var previewed: Dictionary = ghost.target.duplicate()
	var shown: Array[Transform3D] = ghost.ghost_transforms()
	assert_false(shown.is_empty(), "the ghost drew no boxes")

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
			}
		)
	)

	var authored: MapPlacement = null
	for placement: MapPlacement in editor.controller.placements_at(previewed["cell"]):
		if placement.part_id == &"ledge_veneer":
			authored = placement
	assert_not_null(authored, "the click authored no veneer")
	if authored == null:
		return
	assert_almost_eq(
		authored.facing, wanted, 0.0001, "the placement must carry the facing the panel said"
	)

	# The boxes the board will draw for that placement, and the boxes the ghost drew, compared as
	# world positions rather than as two spellings of one formula.
	var real: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		DataLibrary.get_part(&"ledge_veneer"),
		previewed["cell"],
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

	# And the half a facing-blind ghost would still pass: it is not at the unturned position.
	var unturned: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		DataLibrary.get_part(&"ledge_veneer"), previewed["cell"], 0.0, null, authored.height
	)
	var flat: Transform3D = unturned[0].transform.translated_local(unturned[0].box.center)
	assert_gt(
		shown[0].origin.distance_to(flat.origin),
		0.1,
		"the ghost drew the veneer against the edge it would have used unturned"
	)
