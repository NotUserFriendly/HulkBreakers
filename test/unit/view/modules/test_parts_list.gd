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
