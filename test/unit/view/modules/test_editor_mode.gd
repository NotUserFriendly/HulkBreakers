extends GutTest

## taskblock-56 Pass F — **THE ACCEPTANCE, and the block's own most valuable question.**
##
## *"This is the collapse's proof. The editor mode should be a module set plus one new authoring
## module. If it is not — if it needs to subclass, or reach into another mode, or duplicate a
## panel — say so plainly in the report. That is the block's most valuable possible finding and it
## must not be quietly worked around."*
##
## So the first four tests in this file ARE that question, asked four ways, and each one would fail
## if the answer were no:
##
## 1. **Exactly one module in the editor's set is new.** Counted against every other mode's
##    declaration rather than asserted as a number, so adding a second authoring module to the mode
##    later fails this rather than quietly widening the claim.
## 2. **No new chrome.** The editor reuses the player mode's own layout, byte for byte.
## 3. **No subclass.** The surface is a `ControlOverlay`, the same class every other mode mounts
##    through.
## 4. **It does not reach into another mode.** Every module it declares is one the catalog already
##    builds for anyone, and the editor module mounts against an empty context like every other.
##
## The rest is the editor working: a click authors, a save round-trips through the catalog
## directory, the claim module finally draws something, and **an authored board launches a bout
## through the same path a generated one does**.

const SAVED_MAP := "user://test_editor_mode_saved.tres"

## Every `ViewModule` that existed before Pass F opened. **Pinned deliberately**, because the claim
## the pass has to make good on is historical — *"the editor mode should be a module set plus one
## new authoring module"* — and a claim about what a pass cost cannot be measured from the tree the
## pass already changed.
##
## Two of these, `claim_volumes` and `camera_framing`, are mounted by no mode but the editor. That
## is not the editor bringing them: Pass E built and tested both, and `PLAN.md` recorded
## `ClaimVolumeModule` as "correct and unreachable" until an authoring surface existed. They were
## waiting; Pass F did not write them.
const MODULES_BEFORE_PASS_F: Array[StringName] = [
	&"unit_input",
	&"tooltip",
	&"resolution",
	&"combat_log",
	&"debug_panel",
	&"replay",
	&"inspect",
	&"action_bar",
	&"turn_controls",
	&"controls_legend",
	&"playback",
	&"board_inspect",
	&"bout_setup",
	&"claim_volumes",
	&"camera_framing",
]

## **taskblock-57's own modules, written for the battle surface and not for the editor.**
##
## The pin above is a snapshot of one moment, and the claim it serves is *"what did the editor
## cost"* — so a module written for the **player's** surface during this block must not be counted
## against the editor merely because the editor later found a use for it. `announcements` is Pass
## E's, built for a bout; `ui_buttons` is Pass C's, built to make the collapse rule reachable. The
## editor declaring them in G2 is reuse, which is the thing being measured, not an addition to the
## bill.
##
## Kept as its own list rather than folded into the pin above, so the two claims stay separable: one
## is "what existed before Pass F", the other is "what this block built for somebody else".
const MODULES_BUILT_FOR_OTHER_SURFACES: Array[StringName] = [
	&"unit_resources",
	&"ui_buttons",
	&"perf_monitor",
	&"inspect_viewer",
	&"aim_readout",
	&"announcements",
	&"spectator_bar",
]


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()
	if FileAccess.file_exists(SAVED_MAP):
		DirAccess.remove_absolute(SAVED_MAP)


func _battle() -> BattleScene:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	# `_ready()` installs the player mode; a bare surface neutralises it so nothing drives a turn
	# out from under the mode under test.
	battle.set_overlay(ControlOverlay.new())
	return battle


func _editor_overlay() -> ControlOverlay:
	var battle: BattleScene = _battle()
	var overlay: ControlOverlay = ControlOverlay.for_mode(ViewModes.editor())
	battle.set_overlay(overlay)
	return overlay


func _editor(overlay: ControlOverlay) -> EditorModule:
	return overlay.module(&"editor") as EditorModule


func _bar(overlay: ControlOverlay) -> EditorBarModule:
	return overlay.module(&"editor_bar") as EditorBarModule


# ---------------------------------------------------------------- the acceptance


## **THE CENTRAL CLAIM, and taskblock-57 Passes G and H move it from one module to four.**
##
## Pass F's answer was "a module set plus one authoring module". Pass G's subject is that the editor
## needs surfaces of its own shape and Pass H's is the gizmo, and the taskblock names every one of
## the three outright — *"three action bars, not one with three contents"* for `editor_bar`, *"a
## coordinate readout replaces Unit Resources in editor mode"* for `editor_coords`, and *"a 3D
## CAD-style handle set"* for `gizmo`. So the answer is a module set plus **four**, each named here
## rather than allowed to arrive as a nameless increment.
##
## **Still counted rather than stated**, and against a denominator that stayed honest: `ui_buttons`
## and `announcements` also arrived after Pass F, and are excluded because they were built for the
## battle surface — see `MODULES_BUILT_FOR_OTHER_SURFACES`. A fifth editor-only module, or a
## bespoke copy of an existing panel, reports the real number and fails, which is the property that
## made this test worth writing and is unchanged by the number being four.
func test_the_editor_is_a_module_set_plus_exactly_four_new_modules() -> void:
	var written_for_the_editor: Array[StringName] = []
	for id: StringName in ViewModes.editor().modules:
		if MODULES_BEFORE_PASS_F.has(id) or MODULES_BUILT_FOR_OTHER_SURFACES.has(id):
			continue
		written_for_the_editor.append(id)

	gut.p("editor modules: %s" % ", ".join(ViewModes.editor().modules))
	gut.p("written for it: %s" % ", ".join(written_for_the_editor))
	assert_eq(
		written_for_the_editor,
		[&"editor_bar", &"gizmo", &"editor", &"editor_coords"] as Array[StringName],
		"the authoring module, the bar, the gizmo and the coordinate readout, and no more"
	)


## **The other half of that honesty: it stops the exclusion list above being a loophole.**
## Every module named in `MODULES_BUILT_FOR_OTHER_SURFACES` must genuinely be declared by some mode
## that is not the editor — otherwise "built for another surface" is just a place to hide an
## editor-only module.
func test_every_excluded_module_is_really_declared_by_another_mode() -> void:
	for id: StringName in MODULES_BUILT_FOR_OTHER_SURFACES:
		var declared_elsewhere: bool = false
		for mode: ViewMode in ViewModes.all():
			if mode.id != &"editor" and mode.modules.has(id):
				declared_elsewhere = true
		assert_true(
			declared_elsewhere,
			"%s is excluded as another surface's module and no other surface declares it" % id
		)


## The other half of the same fact, and the one that keeps the pin above honest: every module the
## editor names is one `ModuleCatalog` builds for anybody, with no editor-only construction path.
func test_the_editor_declares_nothing_the_catalog_does_not_build_for_everyone() -> void:
	for id: StringName in ViewModes.editor().modules:
		assert_true(
			ModuleCatalog.IDS.has(id), "%s must be a registered module, not a private one" % id
		)
		var built: ViewModule = ModuleCatalog.build(id)
		assert_not_null(built, "%s builds through the ordinary catalog" % id)
		built.free()


## **No new chrome.** Layout belongs to the mode, and the editor asked for one that already
## existed — which is a second, independent way of saying it did not need a surface of its own.
##
## **taskblock-57 Pass C: asserted against the declared layouts, not against the player mode.**
## The original wrote this as "the editor's chrome equals the player's", which was true only because
## both happened to name `PLAYER_COLUMNS`. Pass C moved the player mode to `BATTLE_LAYOUT` and the
## editor stayed put — and the test failed, reporting a seventh layout that nobody had added. It was
## measuring *sameness* when the claim is *reuse*. Pass G is where the editor's own surfaces land
## and where its chrome is revisited; until then this asserts the thing that is actually meant.
func test_the_editor_reuses_an_existing_layout_rather_than_declaring_one() -> void:
	var declared: Array[StringName] = [
		ModeChrome.PLAYER_COLUMNS,
		ModeChrome.TOP_LEFT_ROWS,
		ModeChrome.CENTERED_MENU,
		ModeChrome.BATTLE_LAYOUT,
	]
	assert_true(
		declared.has(ViewModes.editor().chrome),
		(
			"the editor named a layout of its own (%s); it must reuse one that already exists"
			% ViewModes.editor().chrome
		)
	)


## **No subclass.** The thing `SquadControlOverlay` and `SpectatorOverlay` used to be. If the editor
## had needed one, this is where it would show.
func test_the_editor_mounts_through_the_one_overlay_class() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	assert_eq(
		overlay.get_script().resource_path,
		"res://src/view/overlays/control_overlay.gd",
		"the editor is a mode, not a sixth overlay in all but name"
	)
	assert_eq(overlay.mode.id, &"editor")


## It composes exactly what it declared, in order — the same property every other mode owes.
func test_the_editor_mode_composes_the_module_set_it_declares() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var produced: Array[StringName] = []
	for mounted: ViewModule in overlay.modules:
		produced.append(mounted.module_id())
	assert_eq(produced, ViewModes.editor().modules)
	assert_not_null(_editor(overlay))


## An authoring surface drives no unit's turn, and queues nothing against one. Asserted from the
## declaration and from the mounted surface, because those are two facts.
func test_the_editor_drives_no_unit_and_queues_nothing() -> void:
	assert_false(ViewModes.editor().has_unit_input(), "an editor is not a way to play the battle")
	var overlay: ControlOverlay = _editor_overlay()
	assert_false(overlay.has_unit_input())
	assert_null(overlay.tactics(), "no TacticsController means no path from a click to the queue")
	assert_eq(ViewModes.editor().turn_policy, ViewMode.TurnPolicy.NONE)


## The editor module obeys the same stand-alone contract as every other — which is the concrete
## meaning of "it does not reach into another mode". Covered exhaustively by
## `test_view_modules_stand_alone.gd`; restated here because it is one of Pass F's four claims.
func test_the_editor_module_mounts_against_a_context_with_nothing_in_it() -> void:
	var module := EditorModule.new()
	add_child_autofree(module)
	var context := ModuleContext.new()
	module.mount(context)
	module.link()
	module.rebind()
	assert_eq(module.context, context, "no battle, no ui_root, no host, no sibling modules")
	assert_eq(module.controller.placements.size(), 0)
	module.unmount()


## **The editor is reachable, and that is asserted rather than assumed.** Pass E shipped
## `ClaimVolumeModule` correct, tested and mounted by nothing, and `PLAN.md` had to carry it as an
## open item for a whole block. Shipping an authoring *surface* nothing can open would have been
## the same mistake one level up, so the key that opens it is a test rather than a hope.
##
## It also measures what the mode table bought: opening a whole new surface costs a keycode and two
## lines in `BattleScene._unhandled_input`, the same as the Simulate Bout menu.
func test_the_editor_key_installs_the_editor_mode() -> void:
	var battle: BattleScene = _battle()
	assert_ne(battle.overlay.mode.id, &"editor", "sanity: not already in the editor")

	var pressed := InputEventKey.new()
	pressed.keycode = ControlBindings.EDITOR_KEY
	pressed.pressed = true
	battle._unhandled_input(pressed)

	assert_eq(battle.overlay.mode.id, &"editor", "the key opens the editor")
	assert_not_null(battle.overlay.module(&"editor"))


## The legend is generated from `ControlBindings.all()`, so a bound key nobody can discover is a
## binding that does not exist as far as a player is concerned.
func test_the_editor_key_is_listed_in_the_bindings_legend() -> void:
	var triggers: Array[String] = []
	for row: Dictionary in ControlBindings.all(""):
		triggers.append(row["trigger"] as String)
	assert_true(
		triggers.has(OS.get_keycode_string(ControlBindings.EDITOR_KEY)),
		"the editor key must appear in the legend, or nobody finds it"
	)


# ---------------------------------------------------------------- authoring


## A board click reaches the controller through whichever tool is active. **The whole of what the
## module adds** — the verb it calls is `EditorController`'s, which is tested with no scene at all.
func test_a_board_click_authors_through_the_active_tool() -> void:
	var editor: EditorModule = _editor(_editor_overlay())
	editor.active_tool = &"place"
	editor.selected_part = &"ship_floor"

	assert_true(editor.apply_tool_at(Vector2i(2, 2)))

	assert_eq(editor.controller.placements_at(Vector2i(2, 2)).size(), 1)
	assert_eq(editor.controller.placements_at(Vector2i(2, 2))[0].part_id, &"ship_floor")
	assert_eq(editor.last_cell, Vector2i(2, 2))


func test_every_tool_the_bar_offers_is_one_the_router_answers() -> void:
	var editor: EditorModule = _editor(_editor_overlay())
	editor.selected_part = &"ship_floor"
	# A floor first, so the tools that need a surface under them have one.
	editor.active_tool = &"place"
	editor.apply_tool_at(Vector2i(1, 1))

	for tool: StringName in EditorModule.TOOLS:
		editor.active_tool = tool
		assert_eq(editor.active_tool, tool, "the bar and the router agree on %s" % tool)
		assert_true(editor.apply_tool_at(Vector2i(1, 1)), "%s did nothing at all" % tool)


func test_the_spawn_tools_mark_and_unmark_a_cell() -> void:
	var editor: EditorModule = _editor(_editor_overlay())
	editor.active_tool = &"spawn_a"
	editor.apply_tool_at(Vector2i(1, 1))
	assert_eq(editor.controller.spawn_markers.get(Vector2i(1, 1)), Enums.SpawnMarker.SPAWN_A)

	editor.active_tool = &"spawn_none"
	editor.apply_tool_at(Vector2i(1, 1))
	assert_false(editor.controller.spawn_markers.has(Vector2i(1, 1)))


## taskblock-58 Pass C retired the `sight_blocking` tool along with `Grid.opacity` — sight is
## geometry, so a wall already says everything the tool used to author. What is left to pin is
## that the verb is gone from the vocabulary, since the buttons are generated from it.
func test_the_sight_blocking_tool_is_gone_from_the_vocabulary() -> void:
	assert_does_not_have(
		EditorModule.TOOLS, &"sight_blocking", "the verb retired with the array it authored"
	)


func test_the_edge_button_declares_the_selected_side() -> void:
	var editor: EditorModule = _editor(_editor_overlay())
	editor.edge_side_dropdown.selected = EditorModule.EDGE_SIDES.find(SectionEdge.SIDE_EAST)
	editor.edge_kind_dropdown.selected = 1  # KIND_OPEN
	editor.join_tag_field.text = "corridor_2w"

	editor.apply_edge()

	var edge: SectionEdge = editor.controller.to_section_file().edge_for(SectionEdge.SIDE_EAST)
	assert_not_null(edge)
	assert_eq(edge.kind, SectionEdge.KIND_OPEN)
	assert_eq(edge.join_tag, &"corridor_2w")


func test_undo_from_the_panel_walks_the_controller_back() -> void:
	var editor: EditorModule = _editor(_editor_overlay())
	editor.selected_part = &"ship_floor"
	editor.apply_tool_at(Vector2i(1, 1))
	assert_eq(editor.controller.placements.size(), 1)
	assert_true(editor.undo())
	assert_eq(editor.controller.placements.size(), 0)


# ---------------------------------------------------------------- claims finally draw


## **The payoff for Pass E's dangling module.** `PLAN.md` recorded that `ClaimVolumeModule` "exists,
## is tested, and is asserted *not* to appear in any play mode — but the authoring surface that
## would turn it on is *Map and section editors*". This is that surface, and this is it turned on.
func test_authoring_a_claim_draws_it_through_the_claim_module() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var editor: EditorModule = _editor(overlay)
	var volumes: ClaimVolumeModule = overlay.module(&"claim_volumes") as ClaimVolumeModule
	assert_not_null(volumes, "the editor mode mounts the claim module")
	assert_eq(volumes.boxes.size(), 0, "sanity: nothing drawn before anything is authored")

	editor.active_tool = &"claim"
	editor.selected_claim_kind = SectionClaim.KIND_INTERIOR
	editor.apply_tool_at(Vector2i(3, 2))

	assert_eq(volumes.boxes.size(), 1, "the authored claim is drawn")
	var material: StandardMaterial3D = volumes.boxes[0].material_override
	assert_eq(material.albedo_color.g, ClaimVolumeModule.INTERIOR_COLOR.g, "in the interior colour")
	assert_almost_eq(volumes.boxes[0].position.x, 3.0 * UnitGeometry.CELL_SIZE, 0.001)


func test_removing_the_claim_stops_drawing_it() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var editor: EditorModule = _editor(overlay)
	var volumes: ClaimVolumeModule = overlay.module(&"claim_volumes") as ClaimVolumeModule
	editor.active_tool = &"claim"
	editor.apply_tool_at(Vector2i(1, 1))
	assert_eq(volumes.boxes.size(), 1)

	editor.controller.remove_claim(0)
	editor.refresh()
	assert_eq(volumes.boxes.size(), 0)


# ---------------------------------------------------------------- save, open, launch


func _authored_board(editor: EditorModule) -> void:
	editor.name_field.text = "Editor Mode Board"
	editor.controller.set_size(4, 3)
	for y: int in range(3):
		for x: int in range(4):
			editor.controller.place(Vector2i(x, y), &"ship_floor")
	editor.controller.set_spawn_marker(Vector2i(0, 0), Enums.SpawnMarker.SPAWN_A)
	editor.controller.set_spawn_marker(Vector2i(3, 2), Enums.SpawnMarker.SPAWN_B)
	editor.refresh()


## Save as map writes a real `.tres`, and `open` reads the same board back into the editor.
func test_a_board_saved_as_a_map_opens_again_as_the_board_that_was_authored() -> void:
	var editor: EditorModule = _editor(_editor_overlay())
	_authored_board(editor)
	editor.name_field.text = SAVED_MAP
	var saved: Dictionary = editor.save_as_map()
	assert_eq(saved["error"], "", "it wrote")

	var reopened: EditorModule = _editor(_editor_overlay())
	assert_eq(reopened.open(SAVED_MAP)["error"], "")
	assert_eq(reopened.controller.placements.size(), 12)
	assert_eq(reopened.controller.width, 4)
	assert_eq(reopened.controller.spawn_markers.size(), 2)
	# **The name survives the reopen**, which it did not while `refresh()` wrote the name field back
	# into the model: the load set it from the file and the next redraw overwrote it with whatever
	# the widget still held.
	assert_eq(reopened.controller.board_name, SAVED_MAP, "the board kept its own name")
	assert_eq(reopened.name_field.text, SAVED_MAP, "and the field shows what was loaded")


func test_saving_without_a_name_refuses_and_says_why() -> void:
	var editor: EditorModule = _editor(_editor_overlay())
	editor.name_field.text = "   "
	assert_ne(editor.save_as_map()["error"], "", "an unnamed board is one nobody can find again")


func test_opening_something_that_is_not_on_disk_refuses() -> void:
	var editor: EditorModule = _editor(_editor_overlay())
	assert_ne(editor.open("Nothing Called This")["error"], "")


## **F3, the half that matters.** The authored board reaches combat through
## `BoutInjector.load_map_file` — `load_map` with the file-reading half taken off — so it is the
## same route a generated board takes and not a second entry into a bout.
func test_an_authored_board_launches_a_bout_through_the_ordinary_injector_path() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var editor: EditorModule = _editor(overlay)
	_authored_board(editor)
	var state: CombatState = overlay.battle.combat_state
	# **The board being previewed is not the same fact as the board being launched.** Authoring
	# already swaps the live grid so the author can see their work, so the thing that distinguishes
	# a launch is that it went through the injector — which is exactly what `was_injected` records.
	assert_false(state.was_injected, "sanity: nothing has injected anything yet")

	var launched: Dictionary = editor.run_test_bout()

	assert_eq(launched["error"], "", "the board launched")
	assert_eq(overlay.battle.combat_state.grid.width, 4, "the live board IS the authored board")
	assert_eq(overlay.battle.combat_state.grid.rows, 3)
	assert_true(state.was_injected, "and it went through the injector, which marks the bout")


## Every living unit lands somewhere real on the authored board — the relocation `BoardSwap`
## already owned, reached down the same route.
func test_launching_puts_the_units_that_were_playing_onto_the_authored_board() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var editor: EditorModule = _editor(overlay)
	_authored_board(editor)
	editor.run_test_bout()

	var grid: Grid = overlay.battle.combat_state.grid
	for unit: Unit in overlay.battle.combat_state.units:
		if not unit.alive:
			continue
		assert_true(grid.in_bounds(unit.cell), "unit %d stands on the new board" % unit.id)


## **F4 at the surface: warn, never block.** A board with a pit nothing can climb out of launches,
## and the warning is a list the author reads rather than a gate.
func test_a_board_that_fails_navigability_still_launches_and_still_warns() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var editor: EditorModule = _editor(overlay)
	var sink := MemorySink.new()
	overlay.battle.combat_state.combat_log.add_sink(sink)
	editor.name_field.text = "Pit"
	editor.controller.set_size(5, 5)
	for y: int in range(5):
		for x: int in range(5):
			editor.controller.place(Vector2i(x, y), &"ship_floor", MapPlacement.KIND_SURFACE, 3.0)
	editor.controller.clear_cell(Vector2i(2, 2))
	editor.controller.place(Vector2i(2, 2), &"ship_floor", MapPlacement.KIND_SURFACE, 1.0)
	editor.controller.set_spawn_marker(Vector2i(0, 0), Enums.SpawnMarker.SPAWN_A)
	editor.refresh()

	# **Told in the combat log, which is where G2 put the warnings and where the UI review left
	# them.** The panel used to carry its own orange copy of the same list; the review asked what it
	# was (*"It looks like repeated info from the combat log"*) and it was exactly that.
	var told: Array[String] = []
	for event: LogEvent in sink.events:
		if event.kind == EditorLog.WARNING:
			told.append(event.text)
	gut.p("logged: %s" % ", ".join(told))
	assert_true("".join(told).contains("walked into and not back out of"), "the author is told")
	assert_false(_bar(overlay).file_buttons["Run Test Bout"].disabled, "and is not stopped")
	assert_eq(editor.run_test_bout()["error"], "", "the broken board launches, as F4 requires")


## Editing the model redraws the live board, so the author sees what they authored rather than
## whatever the last bout left behind.
func test_authoring_replaces_the_live_board_with_what_was_authored() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var editor: EditorModule = _editor(overlay)
	_authored_board(editor)
	assert_eq(overlay.battle.combat_state.grid.width, 4, "the board being drawn is the model's")
	assert_eq(
		(
			Surface.first_walkable(overlay.battle.combat_state.grid.surfaces_at(Vector2i(1, 1)))
			!= null
		),
		true,
		"and the authored floor is really on it"
	)
