extends GutTest

## **A toggle press must read what is on screen, not what it last did.**
##
## `ViewModule.is_showing`'s own note already draws this distinction for the *border*: *"the cluster
## reads this every frame rather than remembering what it did... a module whose surface can be
## opened by something else overrides it to read the surface."* The **press** did not — it flipped
## `collapsed`, which nothing updates when a surface is opened by other means.
##
## Reported as *"it takes two clicks of the PL UI button to actually dismiss the pick-a-thing
## pop up."*


func before_each() -> void:
	DataLibrary.reset()
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


func _parts_button(overlay: ControlOverlay) -> UiButton:
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule
	return buttons.toggles.get(&"parts_list") as UiButton


## **The reported sequence, exactly.** Dismiss with the button once (which leaves `collapsed` true),
## then open the list from a tool button (which does not touch the flag), then press to dismiss.
func test_one_press_dismisses_a_list_that_was_opened_by_a_tool_button() -> void:
	var overlay: ControlOverlay = _overlay()
	var parts: PartsListModule = overlay.module(&"parts_list") as PartsListModule
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule
	var button: UiButton = _parts_button(overlay)
	assert_not_null(button, "the parts list has no toggle in the cluster")

	bar.open_list_for(&"place_terrain")
	button.pressed.emit()
	assert_false(parts.is_showing(), "sanity: the first dismiss worked")

	# Opened by something that is not the button — which is the whole case.
	bar.open_list_for(&"place_terrain")
	assert_true(parts.is_showing(), "sanity: the tool button opened it again")

	button.pressed.emit()

	assert_false(parts.is_showing(), "it took a second press to dismiss what the bar opened")


## And the reverse: one press summons a list the bar closed.
func test_one_press_summons_a_list_that_was_closed_by_something_else() -> void:
	var overlay: ControlOverlay = _overlay()
	var parts: PartsListModule = overlay.module(&"parts_list") as PartsListModule
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule
	var button: UiButton = _parts_button(overlay)
	bar.open_list_for(&"place_terrain")
	parts.close()
	assert_false(parts.is_showing(), "sanity")

	button.pressed.emit()

	assert_true(parts.is_showing(), "one press should summon it back")


## From a fresh mount, one press opens it — the list starts closed and `collapsed` starts false, so
## a flag-flipping press closed an already-closed list and looked like nothing happened.
func test_one_press_opens_the_list_from_a_fresh_mount() -> void:
	var overlay: ControlOverlay = _overlay()
	var parts: PartsListModule = overlay.module(&"parts_list") as PartsListModule
	assert_false(parts.is_showing(), "sanity: nothing is up yet")

	_parts_button(overlay).pressed.emit()

	assert_true(parts.is_showing(), "the first press did nothing visible")


## The property stated generally, because the defect is not the parts list's: **a press must always
## flip what is on screen**, for every module in the cluster.
func test_a_press_always_flips_what_is_on_screen() -> void:
	var overlay: ControlOverlay = _overlay()
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule
	for id: StringName in buttons.toggles:
		var module: ViewModule = overlay.module(id)
		var before: bool = module.is_showing()
		(buttons.toggles[id] as UiButton).pressed.emit()
		assert_ne(module.is_showing(), before, "%s did not change on a press" % id)
