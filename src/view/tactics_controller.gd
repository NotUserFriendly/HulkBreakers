class_name TacticsController
extends Node

## docs/10 Phase 12.2: the thin shell over SelectionController — translates
## left-click input into selection/queue calls and keeps BoardView's overlay
## in sync. Every actual decision (what's reachable, what queues, what
## resolves) lives in SelectionController; this Node only reads it and
## drives BoardView from it. `_click_cell` is split out from the raw input
## handler so a test can drive it directly, with no live camera required.

signal turn_ended

var selection: SelectionController
var board_view: BoardView
var camera: Camera3D


func setup(state: CombatState, p_board_view: BoardView, p_camera: Camera3D) -> void:
	selection = SelectionController.new(state)
	board_view = p_board_view
	camera = p_camera
	board_view.clear_overlays()


func _unhandled_input(event: InputEvent) -> void:
	if selection == null or not (event is InputEventMouseButton):
		return
	var button_event := event as InputEventMouseButton
	if not (button_event.pressed and button_event.button_index == MOUSE_BUTTON_LEFT):
		return
	var from: Vector3 = camera.project_ray_origin(button_event.position)
	var dir: Vector3 = camera.project_ray_normal(button_event.position)
	var cell: Variant = BoardPicker.cell_at_ray(from, dir)
	if cell != null:
		click_cell(cell)


## Click your own (current-turn) unit to select it; click a reachable cell,
## with a unit already selected, to queue a move there. Anything else is a
## no-op — a plain click never cancels a selection (docs/10: right-click/Esc
## does that).
func click_cell(cell: Vector2i) -> void:
	var unit_here: Unit = _unit_at(cell)
	if unit_here != null and unit_here == selection.state.current_unit():
		selection.select(unit_here)
	elif selection.selected_unit != null:
		selection.queue_move(cell)
	_refresh_overlay()


func _unit_at(cell: Vector2i) -> Unit:
	for unit: Unit in selection.state.units:
		if unit.alive and unit.cell == cell:
			return unit
	return null


## Queues ending the selected unit's turn and actually resolves it —
## RESOLUTION, not TACTICS, is what's allowed to mutate the real state.
func end_turn() -> void:
	if selection == null or selection.selected_unit == null:
		return
	selection.queue_end_turn()
	selection.state.resolve_turn(selection.current_queue())
	selection.reset()
	board_view.clear_overlays()
	turn_ended.emit()


func _refresh_overlay() -> void:
	if selection.selected_unit == null:
		board_view.clear_overlays()
		return
	board_view.show_reachable(selection.reachable_cells())
	board_view.show_ghost_paths(selection.ghost_paths())
