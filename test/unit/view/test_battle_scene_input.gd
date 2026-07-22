extends GutTest

## docs/09 taskblock07 Pass B4: "a headless click at a viewport coordinate
## over the board reaches TacticsController with every panel present and
## populated." Godot's default Control.mouse_filter is STOP, not IGNORE —
## a new panel that forgets to set it swallows every click that lands over
## its own rect before TacticsController's own _unhandled_input ever sees
## it. Unlike test_tactics_controller.gd's own convention (click_cell()
## driven directly, no live camera/viewport needed for the ray->cell
## math itself), THIS is exactly the one thing that convention can't catch
## — it never routes an event through the real Control tree at all. This
## test pushes a genuine InputEventMouseButton through the real Viewport,
## with the full BattleScene (every panel, populated) present, and proves
## it still reaches the board.


## taskblock-15 Pass A: TacticsController/ActionBar moved from BattleScene
## itself into SquadControlOverlay (its default overlay) — every test
## below reaches through this instead.
func _overlay(scene: BattleScene) -> SquadControlOverlay:
	return scene.overlay as SquadControlOverlay


func _click_at(scene: BattleScene, screen_pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = screen_pos
	scene.get_viewport().push_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = screen_pos
	scene.get_viewport().push_input(up)


func test_a_real_click_over_the_board_selects_the_current_unit_through_every_panel() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	# The board's own center is where camera_rig.center_on() (new_battle())
	# points the camera — open board space, deliberately away from every
	# corner/edge-anchored panel, so a fixed-size panel happening to cover
	# an arbitrary seeded unit's own cell can never produce a false
	# failure here. Relocates the current unit there directly (matching
	# this project's own established live-probe convention) rather than
	# trusting wherever DeepStrike happened to seed it.
	var current: Unit = scene.combat_state.current_unit()
	var board_center := Vector2i(
		scene.combat_state.grid.width / 2, scene.combat_state.grid.height / 2
	)
	scene.combat_state.grid.set_occupant_id(current.cell, -1)
	current.cell = board_center
	scene.combat_state.grid.set_occupant_id(current.cell, current.id)
	scene.unit_views[scene.combat_state.units.find(current)].refresh()

	# The unit's own actual TORSO box center, not the bounding-sphere
	# center — a real, reported bug: a random deep-struck loadout carrying
	# a long weapon (a sniper rifle, say) elongates the bounding sphere far
	# enough along one axis that its geometric CENTER lands in empty space
	# behind the torso, never inside any actual hitbox at all — UnitPicker
	# then legitimately finds nothing there, no matter how many times the
	# click is retried. The torso is always real, solid geometry every
	# reference-humanoid assembly has; its own box center is guaranteed to
	# be inside it by construction.
	var torso_center: Vector3 = Vector3.ZERO
	for placement: BoxPlacement in UnitGeometry.placements(current):
		if placement.part.id == &"torso":
			torso_center = placement.transform * placement.box.center
			break
	var camera: Camera3D = scene.camera_rig.camera()
	var screen_pos: Vector2 = camera.unproject_position(torso_center)

	_click_at(scene, screen_pos)

	assert_eq(
		_overlay(scene).tactics.selection.selected_unit,
		current,
		"a real click at the current unit's own screen position must select it, not be swallowed"
	)


## "Clicking the action bar also clicks things behind it" — the box was
## sitting at MOUSE_FILTER_PASS: gui_input fired (arming the box's own
## action) but the event was never marked handled, so it also reached
## TacticsController._unhandled_input. A click landing off the board
## (which the action bar's own bottom-right corner is) makes that handler
## call deselect() — the sharpest, most visible symptom: a click meant to
## arm an action bar slot would silently drop the player's own selection.
func test_a_click_on_an_action_bar_box_never_reaches_the_board_underneath() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	var overlay: SquadControlOverlay = _overlay(scene)
	var current: Unit = scene.combat_state.current_unit()
	overlay.tactics.selection.select(current)

	var box: PanelContainer = overlay.action_bar._panels[0]
	var screen_pos: Vector2 = box.get_global_rect().get_center()
	_click_at(scene, screen_pos)

	assert_eq(
		overlay.tactics.selection.selected_unit,
		current,
		"a click on the action bar must never also deselect/reselect through the board underneath"
	)


## The negative-space check: a click over the readout cluster's own screen
## rect (bottom-right — aim/stat/combat-readout labels, the exact class of
## control this pass fixed) must be consumed there, never fall through to
## unrelated board clicks. Kept as a sanity companion, not the load-bearing
## assertion above.
func test_every_richtextlabel_panel_ignores_the_mouse_except_the_log() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	var offenders: Array[String] = []
	_scan_for_stop_filters(scene, offenders)

	assert_eq(
		offenders,
		[] as Array[String],
		"non-interactive Controls must not default to STOP: %s" % [offenders]
	)


## Every Tree/Button/ItemList (genuinely interactive — clicking them is the
## point) is expected to keep STOP; everything else (Label, RichTextLabel,
## plain layout Controls) must be IGNORE or the board loses clicks under
## it. The log is the one deliberate exception (a real, wanted scrollbar).
## A plain Control wired to a real `gui_input` handler (the action bar's
## own boxes, ActionBar.setup) is interactive by construction too — that's
## a structural fact about the node, not something a type whitelist can
## see, and checking it directly is what would have caught the action bar
## sitting at PASS (arms an action via gui_input, but never consumed the
## click, so it fell through to the board underneath) in the first place.
func _scan_for_stop_filters(node: Node, offenders: Array[String]) -> void:
	if node is Control:
		var control := node as Control
		var interactive: bool = (
			control is Tree
			or control is Button
			or control is ItemList
			or control is ScrollBar
			or control.gui_input.get_connections().size() > 0
		)
		var is_log: bool = control is RichTextLabel and (control as RichTextLabel).scroll_following
		if not interactive and not is_log and control.mouse_filter == Control.MOUSE_FILTER_STOP:
			offenders.append("%s (%s)" % [control.name, control.get_class()])
	for child: Node in node.get_children():
		_scan_for_stop_filters(child, offenders)


## BR31.01 (tb32 Pass D): "the bottom-right turn controls and the tooltip
## popup fight over clicks." Confirmed via a real click before changing
## anything (docs/10 standing rule 2) — `TooltipView`/its label already
## carry MOUSE_FILTER_IGNORE, so a click lands on the button underneath
## regardless of whether the tooltip is visually covering it; the real
## bug is that nothing ever hides a STALE tooltip once the cursor moves
## off the 3D board and onto a Control (TacticsController._unhandled_
## input's own hover tracking simply never fires there) — the same class
## QueuePanel's own rows/ApMpPipRow's containers already guard against via
## mouse_exited/mouse_entered, but turn_controls_column's own buttons
## never got it.
func test_a_real_click_on_end_turn_reaches_it_even_with_the_tooltip_visually_covering_it() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var overlay: SquadControlOverlay = _overlay(scene)
	# Anchored Controls (turn_controls_column included) only resolve their
	# real, laid-out `global_rect` after a live frame actually runs —
	# reading it on the same frame the scene was built returns a garbage
	# (viewport_size, 0x0) rect, off-screen by construction.
	await get_tree().process_frame
	await get_tree().process_frame
	var end_turn_button: Button = overlay.end_turn_button
	var screen_pos: Vector2 = end_turn_button.get_global_rect().get_center()

	overlay.tooltip_view.show_data(
		TooltipData.new("test", [{"label": "a", "value": "b", "changed": false}]), screen_pos
	)
	overlay.tooltip_view._process(TooltipView.HOVER_DELAY_SEC)
	assert_true(overlay.tooltip_view.visible, "sanity: the tooltip is actually showing")

	var fired: Array[bool] = [false]
	end_turn_button.pressed.connect(func() -> void: fired[0] = true)
	_click_at(scene, screen_pos)

	assert_true(fired[0], "a click on End Turn must reach it, tooltip visually overlapping or not")


## BR27.08 ("Resolve to Here" reported grayed out and unclickable in real
## play — the reported symptom was never reproduced headlessly across an
## extensive investigation, so the whole `Tree`+marker+global-button
## mechanism was retired and rebuilt on plain `Button`/`Label`/`Container`
## instead — see `docs/SUPERSEDED.md`). Each queued action is now its own
## row with its own real "Resolve" button, wired directly to
## `tactics.resolve_to_marker(index)`. This pushes a genuine
## `InputEventMouseButton` at that button's own real, laid-out screen rect
## through the real Viewport, inside the FULL real `BattleScene`/
## `SquadControlOverlay` construction — proving the whole path end to end,
## not a shortcut. (This is also what caught a real layout bug while this
## was being built: the row's own expanding label had no width bound
## inside its `ScrollContainer`, landing the button hundreds of pixels
## past the right edge of the viewport — fixed by disabling the scroll
## container's own horizontal scrolling.)
func test_a_real_click_on_a_queue_rows_resolve_button_resolves_through_it() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var overlay: SquadControlOverlay = _overlay(scene)
	var current: Unit = scene.combat_state.current_unit()
	overlay.tactics.selection.select(current)

	var reachable: Array[Vector2i] = overlay.tactics.selection.reachable_cells()
	reachable = reachable.filter(func(c: Vector2i) -> bool: return c != current.cell)
	assert_gt(reachable.size(), 0, "sanity: the current unit must have somewhere to move")
	overlay.tactics.click_cell(reachable[0])
	var start_cell: Vector2i = current.cell

	assert_eq(overlay.queue_panel.rows_container.get_child_count(), 1, "sanity: one row now queued")

	# Anchored/laid-out Controls only resolve a real global_rect after a
	# live frame runs (tb32 Pass D's own diagnostic note) — read too early
	# and this returns a garbage pre-layout rect.
	await get_tree().process_frame
	await get_tree().process_frame

	var row: HBoxContainer = overlay.queue_panel.rows_container.get_child(0)
	var resolve_button: Button = row.get_child(row.get_child_count() - 1) as Button
	_click_at(scene, resolve_button.get_global_rect().get_center())

	assert_ne(
		current.cell,
		start_cell,
		"a real click on the row's own Resolve button must actually resolve the move"
	)
	assert_eq(
		overlay.queue_panel.rows_container.get_child_count(),
		0,
		"the resolved queue is empty — no rows left"
	)


## The actual fix: entering ANY turn-control button must hide a stale
## tooltip left over from hovering the board right before crossing onto
## it — not wait for the click, which (proven above) already worked.
func test_entering_a_turn_control_button_hides_a_stale_tooltip() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var overlay: SquadControlOverlay = _overlay(scene)
	var end_turn_button: Button = overlay.end_turn_button

	overlay.tooltip_view.show_data(
		TooltipData.new("test", [{"label": "a", "value": "b", "changed": false}]), Vector2(10, 10)
	)
	overlay.tooltip_view._process(TooltipView.HOVER_DELAY_SEC)
	assert_true(overlay.tooltip_view.visible, "sanity: the tooltip is actually showing")

	end_turn_button.mouse_entered.emit()

	assert_false(
		overlay.tooltip_view.visible,
		"a stale board tooltip must not linger over a turn-control button"
	)
