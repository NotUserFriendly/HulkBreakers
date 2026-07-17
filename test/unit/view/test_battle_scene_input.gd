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

	# The unit's own actual bounding-sphere center, not a guessed height —
	# a random deep-struck loadout's real geometry doesn't necessarily
	# occupy any fixed height, and UnitPicker needs the ray to actually
	# cross a box, not just the unit's own cell column.
	var sphere: Dictionary = UnitGeometry.bounding_sphere(current)
	var camera: Camera3D = scene.camera_rig.camera()
	var screen_pos: Vector2 = camera.unproject_position(sphere.center)

	_click_at(scene, screen_pos)

	assert_eq(
		scene.tactics.selection.selected_unit,
		current,
		"a real click at the current unit's own screen position must select it, not be swallowed"
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
func _scan_for_stop_filters(node: Node, offenders: Array[String]) -> void:
	if node is Control:
		var control := node as Control
		var interactive: bool = (
			control is Tree or control is Button or control is ItemList or control is ScrollBar
		)
		var is_log: bool = control is RichTextLabel and (control as RichTextLabel).scroll_following
		if not interactive and not is_log and control.mouse_filter == Control.MOUSE_FILTER_STOP:
			offenders.append("%s (%s)" % [control.name, control.get_class()])
	for child: Node in node.get_children():
		_scan_for_stop_filters(child, offenders)
