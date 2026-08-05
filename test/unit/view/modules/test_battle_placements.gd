extends GutTest

## taskblock-57 Pass C — **every surface in the placement table is in its declared place.**
##
## `test_battle_layout.gd` asserts the arithmetic; this asserts that the modules actually landed on
## it. Those are different claims and the gap between them is where a layout bug lives: a rect can
## be perfect while the panel that was supposed to use it anchors itself into a corner.
##
## ## Read the real node back; never re-derive the position
##
## CLAUDE.md's rule, and the reason every assertion here goes through `get_global_rect()` on a
## panel built by the real mode rather than through a second call to `BattleLayout`. A test that
## recomputes the formula agrees with the formula and with nothing else — which is exactly how the
## attack camera's yaw bug survived a full suite.
##
## The chain under test is three links long and each one can break independently:
##
##     BattleLayout (arithmetic) -> ModeChrome (a Control per rect) -> the module (mounts into it)
##
## so the assertions compare a **mounted panel's global rect** against **the layout's answer for its
## slot**, which only holds if all three agree.

## The viewport headless actually has (`project.godot`: 1920x1080). **Asserted against the real
## `ui_root.size` in `_overlay`, never forced onto it** — `docs/TEST-AUDIT.md` records the previous
## attempt at forcing a size here: headless has no real window, so writing `root.size` leaves every
## reported rect identical and a loop over four resolutions measures one layout four times. Worse,
## writing it at all trips Godot's "non-equal opposite anchors will have their size overridden"
## error, which GUT counts as a failure.
##
## **Resolution variation therefore stays uncovered by this file**, exactly as it does in
## `test_debug_panel_layout.gd`. The arithmetic across ratios is covered headlessly in
## `test_battle_layout.gd`; what is unproven is that a *live window* resize re-lays-out, which needs
## a visual checkpoint.
const SCREEN := Vector2(1920, 1080)

## Godot's layout lands positions to whole pixels in places, and a container's own separation can
## add a pixel. Nothing here is asserting sub-pixel precision.
const TOLERANCE := 2.0


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()
	UiLayout.scale = 1.0


## A real battle under a real player-mode surface, sized and laid out. **Not a hand-built context**:
## the whole point is that the mode's own declaration order, chrome and slot publishing are what put
## these panels where they are.
func _overlay() -> ControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	var overlay: ControlOverlay = ControlOverlay.for_mode(ViewModes.player())
	battle.set_overlay(overlay)
	# Two frames: the first lets the chrome's regions take their sizes, the second lets the panels
	# inside them settle against those sizes.
	await get_tree().process_frame
	await get_tree().process_frame
	# **The fixture's own sanity check.** Every expectation below is `BattleLayout.*(SCREEN)`, so if
	# the real root is not that size the whole file is comparing against a layout nobody built.
	assert_eq(
		overlay.ui_root.size, SCREEN, "the headless viewport is not the size this file assumes"
	)
	return overlay


func _assert_at(actual: Rect2, expected: Rect2, what: String) -> void:
	gut.p("%s: at %v, expected %v" % [what, actual.position, expected.position])
	assert_almost_eq(actual.position.x, expected.position.x, TOLERANCE, "%s: wrong x" % what)
	assert_almost_eq(actual.position.y, expected.position.y, TOLERANCE, "%s: wrong y" % what)


# ---------------------------------------------------------------- the screen-anchored surfaces


## **THE ACCEPTANCE for the table's screen-anchored rows.** Inspect and the debug menu are the two
## surfaces the chrome places directly, and both were self-positioning before this pass — Inspect
## re-centred itself on every open, the debug menu re-centred on every viewport resize. Reading the
## real rect back is what proves those two habits are actually off.
func test_inspect_fills_its_declared_slot_rather_than_centring_itself() -> void:
	var overlay: ControlOverlay = await _overlay()
	var panel: InspectPanel = overlay.inspect().panel

	assert_true(panel.placed_by_host, "the mode published a slot, so the panel must not re-centre")
	_assert_at(panel.get_global_rect(), BattleLayout.inspect_rect(SCREEN), "inspect")
	assert_almost_eq(
		panel.get_global_rect().size.x,
		BattleLayout.inspect_rect(SCREEN).size.x,
		TOLERANCE,
		"and it fills the slot's width -- the table says square, and the slot is where that lives"
	)


## The menu is positioned by the slot and sized by its own content, which is stated in the module
## and asserted here so the difference from Inspect is deliberate rather than an oversight.
func test_the_debug_menu_sits_at_its_declared_slots_corner() -> void:
	var overlay: ControlOverlay = await _overlay()
	var panel: DebugControlPanel = overlay.debug_panel_module().panel
	if panel == null:
		# A release export never constructs it at all. Nothing to place, and saying so beats a
		# silently green run.
		gut.p("no debug panel in this build -- nothing to place")
		pass_test("release build: the debug menu is not constructed")
		return

	assert_true(panel.placed_by_host, "the mode published a slot, so the panel must not re-centre")
	_assert_at(panel.get_global_rect(), BattleLayout.debug_menu_rect(SCREEN), "debug menu")


## **Click-through and hard into the corner**, both of which the table states outright. The size is
## the panel's own, so only the corner it grows from is asserted.
func test_the_perf_monitor_grows_from_the_true_bottom_right_corner() -> void:
	var overlay: ControlOverlay = await _overlay()
	var monitor: PerfMonitorModule = overlay.module(&"perf_monitor") as PerfMonitorModule
	assert_not_null(monitor, "the player mode declares a performance readout")
	monitor.panel.visible = true
	await get_tree().process_frame

	var rect: Rect2 = monitor.panel.get_global_rect()
	# `%v` formats a Vector2 but NOT a Rect2 — passing the rect itself fails the format call, which
	# lands as an engine error and reads as a mysterious assertion failure three lines later.
	gut.p("perf monitor corner: %v, screen %v" % [rect.end, SCREEN])
	assert_almost_eq(rect.end.x, SCREEN.x, TOLERANCE, "hard against the right edge, no padding")
	assert_almost_eq(rect.end.y, SCREEN.y, TOLERANCE, "and the bottom")
	assert_eq(
		monitor.panel.mouse_filter,
		Control.MOUSE_FILTER_IGNORE,
		"a readout over the board must not eat a camera drag"
	)


# ---------------------------------------------------------------- the action bar's satellites


## **THE ACCEPTANCE for Pass B's mechanism, seen end to end.** Four surfaces pin to the bar rather
## than to the screen, so the test that matters is not "did they get a slot" but "are they where the
## bar is". Asserted by ancestry through the bar's own root, which is the property that makes them
## move when it moves — and read off real nodes, not recomputed.
func test_the_four_satellites_are_children_of_the_bar_rather_than_of_the_screen() -> void:
	var overlay: ControlOverlay = await _overlay()
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule

	for id: StringName in [&"combat_log", &"turn_controls", &"unit_resources", &"ui_buttons"]:
		var module: ViewModule = overlay.module(id)
		assert_not_null(module, "the player mode declares %s" % id)
		var root: Control = _first_control_under(module)
		assert_not_null(root, "%s built no Control to place" % id)
		assert_true(
			bar.bar_root.is_ancestor_of(root),
			"%s is anchored to the screen -- moving the bar would leave it behind" % id
		)


## The bar itself lands on the layout's rect, which is what the four above inherit their position
## from. Asserted separately so a failure says which link broke.
func test_the_action_bar_lands_on_the_layouts_own_rect() -> void:
	var overlay: ControlOverlay = await _overlay()
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	var slot: Control = overlay.module_context.slots.get(ModuleSlots.ACTION_ROW)

	assert_not_null(slot, "the battle layout publishes the action row")
	_assert_at(slot.get_global_rect(), BattleLayout.action_bar_rect(SCREEN), "action row")
	assert_true(slot.is_ancestor_of(bar.bar_root), "and the bar mounted into it")


## **Moving the bar moves its dependants** — the whole reason a module may publish slots. Stepped
## through a real layout and read back, rather than asserted by shared parentage alone.
func test_moving_the_bar_moves_every_surface_pinned_to_it() -> void:
	var overlay: ControlOverlay = await _overlay()
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	var logs: CombatLogModule = overlay.module(&"combat_log") as CombatLogModule
	var before: Vector2 = logs.panel.get_global_rect().position

	bar.bar_root.get_parent().position += Vector2(0.0, -120.0)
	await get_tree().process_frame

	var after: Vector2 = logs.panel.get_global_rect().position
	gut.p("combat log moved from %v to %v" % [before, after])
	assert_almost_eq(after.y, before.y - 120.0, TOLERANCE, "the log followed the bar")


# ---------------------------------------------------------------- the budge, wired to Inspect


## **The one-off, end to end: it budges, and only for Inspect.** `test_battle_layout.gd` proves the
## distance; this proves the wiring — opening Inspect moves the menu and closing it puts the menu
## back, with nothing else on the surface touched.
func test_the_debug_menu_budges_when_inspect_opens_and_returns_when_it_closes() -> void:
	var overlay: ControlOverlay = await _overlay()
	var menu: Control = overlay.module_context.slots.get(ModuleSlots.DEBUG_MENU)
	var inspect: InspectModule = overlay.inspect()
	assert_not_null(menu, "the battle layout publishes a debug menu slot")
	var home: float = menu.position.x

	inspect.opened.emit()
	await get_tree().process_frame
	var budged: float = menu.position.x
	gut.p("debug menu: home %.1f, budged %.1f" % [home, budged])
	assert_almost_eq(
		budged,
		home - BattleLayout.debug_menu_budge_distance(SCREEN),
		TOLERANCE,
		"it moved by the budge distance, out of Inspect's way"
	)

	inspect.panel.close()
	await get_tree().process_frame
	assert_almost_eq(menu.position.x, home, TOLERANCE, "and closing Inspect puts it exactly back")


## **And nothing else budges for anything.** The taskblock calls this "a one-off, not a mechanism"
## and asks to be told if a second case appears; this is what would notice.
func test_nothing_but_the_debug_menu_moves_when_inspect_opens() -> void:
	var overlay: ControlOverlay = await _overlay()
	var watched: Array[StringName] = [
		ModuleSlots.ACTION_ROW, ModuleSlots.PERF_MONITOR, ModuleSlots.ANNOUNCEMENTS
	]
	var before: Dictionary = {}
	for slot: StringName in watched:
		before[slot] = (overlay.module_context.slots.get(slot) as Control).position

	overlay.inspect().opened.emit()
	await get_tree().process_frame

	for slot: StringName in watched:
		var now: Vector2 = (overlay.module_context.slots.get(slot) as Control).position
		assert_eq(now, before[slot] as Vector2, "%s budged, and only the debug menu may" % slot)


# ---------------------------------------------------------------- the collapse rule, reachable


## **A2's rule with an affordance.** Every module that reports itself collapsible must have a toggle
## a player can actually press — a rule whose control does not exist is one nobody can use.
func test_every_collapsible_module_gets_a_toggle_in_the_ui_buttons_cluster() -> void:
	var overlay: ControlOverlay = await _overlay()
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule
	var collapsible: Array[StringName] = []
	for id: StringName in overlay.module_context.modules:
		var module: ViewModule = overlay.module_context.modules[id]
		if module != buttons and module.is_collapsible():
			collapsible.append(id)

	gut.p("collapsible: %s" % ", ".join(collapsible))
	assert_false(
		collapsible.is_empty(),
		"the player mode has collapsible surfaces, or this sweep proves none"
	)
	for id: StringName in collapsible:
		assert_true(buttons.toggles.has(id), "%s is collapsible with no way to collapse it" % id)


## The toggle drives the flag, and the flag actually hides something. Asserted on the action bar
## because it is the one collapsible surface that is visible by default — the other two start off.
func test_a_toggle_folds_its_module_away_and_unfolds_it() -> void:
	var overlay: ControlOverlay = await _overlay()
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	var toggle: UiButton = buttons.toggles[&"action_bar"]

	assert_true(bar.bar_root.visible, "the bar starts shown -- nothing is collapsed by default")
	toggle.button_pressed = false
	assert_true(bar.collapsed, "pressing the toggle collapses the module")
	assert_false(bar.bar_root.visible, "and the surface is actually gone, not just flagged")
	toggle.button_pressed = true
	assert_false(bar.collapsed)
	assert_true(bar.bar_root.visible, "and it comes back")


# ---------------------------------------------------------------- what moved off the log


## taskblock-57 Pass C: *"Takes the FPS readout off the combat log."* Asserted because a leftover
## second meter is invisible until two readouts disagree by a frame and someone loses an afternoon.
func test_the_combat_log_no_longer_carries_its_own_framerate_readout() -> void:
	var panel := CombatLogPanel.new()
	add_child_autofree(panel)
	for child: Node in panel.title_bar.get_child(0).get_children():
		if child is Label:
			assert_false(
				(child as Label).text.to_lower().contains("fps"),
				"the log is still drawing a framerate -- the perf monitor is the one surface now"
			)


## The first `Control` this module actually built, wherever it put it. Modules place different
## kinds of node, so ancestry is asked of whatever they made rather than of a field named per
## module — which would be a list this file has to be kept in step with.
func _first_control_under(module: ViewModule) -> Control:
	for name: StringName in [&"panel", &"column", &"row", &"bar_root"]:
		var found: Variant = module.get(name)
		if found is Control:
			return found as Control
	return null


# ---------------------------------------------------------------- the viewer, in its own corner


## **THE ACCEPTANCE for Pass C3.** The table: *"top-left, ~2/3 tall, half as wide — the 3D view,
## split out so the centre stays clear."* Split out means it is genuinely somewhere else, so the
## assertion is that it lands on the layout's own viewer rect and that Inspect is not its ancestor.
func test_the_inspect_viewer_sits_in_its_own_top_left_slot() -> void:
	var overlay: ControlOverlay = await _overlay()
	var module: InspectViewerModule = overlay.module(&"inspect_viewer") as InspectViewerModule
	assert_not_null(module, "the player mode declares an inspect viewer")

	module.viewer.visible = true
	await get_tree().process_frame
	_assert_at(module.viewer.get_global_rect(), BattleLayout.inspect_viewer_rect(SCREEN), "viewer")
	assert_false(
		overlay.inspect().panel.is_ancestor_of(module.viewer),
		"the viewer is still inside the panel -- the centre of the screen is not clear"
	)


## **One viewer, driven by the panel** — not a second 3D preview path. This project has had to
## delete a duplicated system three times; the whole reason `BotViewer` is one class with two
## placements is that a docked-only second implementation is the shape that starts it.
func test_inspect_drives_the_slotted_viewer_rather_than_building_a_second_one() -> void:
	var overlay: ControlOverlay = await _overlay()
	var module: InspectViewerModule = overlay.module(&"inspect_viewer") as InspectViewerModule

	assert_eq(
		overlay.inspect().panel.viewer,
		module.viewer,
		"the panel must drive the slotted viewer, not one of its own"
	)


## Opening and closing Inspect must take the viewer with it. It is no longer a child of the panel,
## so hiding the panel no longer hides it — which would leave a spinning subject in the corner over
## a closed inspector.
func test_closing_inspect_hides_the_viewer_it_no_longer_contains() -> void:
	var overlay: ControlOverlay = await _overlay()
	var module: InspectViewerModule = overlay.module(&"inspect_viewer") as InspectViewerModule
	var unit: Unit = overlay.battle.combat_state.current_unit()

	overlay.inspect().panel.open(unit)
	await get_tree().process_frame
	assert_true(module.viewer.visible, "opening Inspect shows the viewer")

	overlay.inspect().panel.close()
	await get_tree().process_frame
	assert_false(module.viewer.visible, "and closing it takes the viewer away too")
