class_name TacticsController
extends Node

## docs/10 Phase 12.2/12.3: the thin shell over SelectionController/
## AimController — translates input into their calls and keeps
## BoardView/AimView in sync. Every actual decision (what's reachable, what
## queues, what resolves, what's being read) lives in the pure controllers;
## this Node only reads them. `click_cell`/`scroll_layer`/`confirm_shot`/
## `cancel_aim` are split out from the raw input handlers so a test can
## drive them directly, with no live camera required.

## Carries the events resolve_turn() actually emitted, for whoever plays
## back the resolution (docs/10 Phase 12.4's LogPlayback) to consume.
signal turn_ended(events: Array[LogEvent])
signal aim_changed
## Fires whenever `selection.selected_unit` might have changed — the stat
## panel (docs/08/10 Phase 12.5) redraws from this rather than polling.
signal selection_changed

## Reticle-follows-mouse sensitivity (docs/10 doesn't specify a plane-space
## mouse mapping — this is a flagged placeholder, not a design decision:
## raw screen-motion delta scaled into plane units).
const RETICLE_SENSITIVITY := 0.01

## docs/10 taskblock02 F3: Q/E step size — docs/10 doesn't pin an exact
## increment, a flagged placeholder like RETICLE_SENSITIVITY above, not a
## design decision. 45 degrees: enough turns to face any of 8 directions.
const FACE_STEP := PI / 4.0

var selection: SelectionController
var board_view: BoardView
var camera_rig: CameraRig
var camera: Camera3D

## Non-null while in Attack mode (docs/10): the enemy being aimed at.
var aiming_at: Unit = null
var layer_index: int = 0
var reticle_offset: Vector2 = Vector2.ZERO

## True for the whole of RESOLUTION (docs/10): set the instant End Turn
## resolves, cleared once whoever is playing back the log calls
## unlock_input(). The real mutation already happened synchronously by
## then — this only blocks further TACTICS input during the cosmetic
## replay, never delays the sim itself.
var input_locked: bool = false


func setup(state: CombatState, p_board_view: BoardView, p_camera_rig: CameraRig) -> void:
	selection = SelectionController.new(state)
	board_view = p_board_view
	camera_rig = p_camera_rig
	camera = p_camera_rig.camera()
	board_view.clear_overlays()


func _unhandled_input(event: InputEvent) -> void:
	if selection == null or input_locked:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and aiming_at != null:
		var raw: Vector2 = (event as InputEventMouseMotion).relative * RETICLE_SENSITIVITY
		# docs/10 taskblock03 C3: Godot's mouse Y is down-positive; the shot
		# plane's Y is world-up-positive (BodyProjector's own Rect2 convention).
		# Negate at this input boundary so dragging the mouse up moves the
		# reticle up, not down.
		move_reticle(Vector2(raw.x, -raw.y))
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed:
			return
		if key_event.keycode == KEY_ESCAPE:
			# docs/10 taskblock02 F2: Esc always backs out one level — out
			# of Attack mode first if aiming, otherwise a plain deselect.
			if aiming_at != null:
				cancel_aim()
			else:
				deselect()
		elif key_event.keycode == KEY_Q and aiming_at == null:
			turn_selected(-FACE_STEP)
		elif key_event.keycode == KEY_E and aiming_at == null:
			turn_selected(FACE_STEP)
		elif key_event.keycode == KEY_F and aiming_at != null:
			reset_framing()


func _handle_mouse_button(button_event: InputEventMouseButton) -> void:
	if not button_event.pressed:
		return
	if button_event.button_index == MOUSE_BUTTON_LEFT:
		var from: Vector3 = camera.project_ray_origin(button_event.position)
		var dir: Vector3 = camera.project_ray_normal(button_event.position)
		var cell: Variant = BoardPicker.cell_at_ray(from, dir)
		if cell != null:
			click_cell(cell)
		elif aiming_at == null:
			# docs/10 taskblock02 F2: clicking off the board entirely is
			# "away" — deselect. A click still on the board but out of
			# reach is a different thing (the player is aiming for a cell
			# they can't use yet, not backing out) and stays a no-op.
			deselect()
	elif button_event.button_index == MOUSE_BUTTON_RIGHT and aiming_at != null:
		cancel_aim()
	elif button_event.button_index == MOUSE_BUTTON_WHEEL_UP and aiming_at != null:
		scroll_layer(1)
	elif button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and aiming_at != null:
		scroll_layer(-1)


## While aiming: any click confirms the shot (docs/10: "click / confirm ->
## queue an AttackAction"), regardless of which cell was actually clicked.
## Otherwise: click your own (current-turn) unit to select it; with a unit
## selected, click a live enemy to enter Attack mode, or click a reachable
## cell to queue a move there. A click on a valid, on-board cell never
## cancels a selection by itself — that's `deselect()`'s job, reached via
## Esc or an off-board click (docs/10 taskblock02 F2), never a plain
## in-board click that just happens to be out of reach.
func click_cell(cell: Vector2i) -> void:
	if input_locked:
		return
	if aiming_at != null:
		confirm_shot()
		return

	var unit_here: Unit = _unit_at(cell)
	if unit_here != null and unit_here == selection.state.current_unit():
		selection.select(unit_here)
	elif unit_here != null and selection.selected_unit != null:
		_enter_aim_mode(unit_here)
	elif selection.selected_unit != null:
		selection.queue_move(cell)
	_refresh_overlay()


## docs/10 taskblock02 F2: "click away / Esc → deselect." A no-op if
## nothing's selected in the first place.
func deselect() -> void:
	if selection == null or selection.selected_unit == null:
		return
	selection.select(null)
	_refresh_overlay()


## docs/10 taskblock02 F3: Q/E — turns the selected unit by `delta` radians
## relative to whatever it would already be facing after every action
## queued so far this TACTICS pass, so repeated presses accumulate
## correctly instead of each one starting back from the pre-queue value.
func turn_selected(delta: float) -> void:
	if input_locked or selection == null or selection.selected_unit == null:
		return
	selection.queue_face(selection.previewed_orientation() + delta)
	_refresh_overlay()


func _unit_at(cell: Vector2i) -> Unit:
	for unit: Unit in selection.state.units:
		if unit.alive and unit.cell == cell:
			return unit
	return null


func _enter_aim_mode(target: Unit) -> void:
	aiming_at = target
	layer_index = 0
	reticle_offset = Vector2.ZERO
	camera_rig.zoom_enabled = false
	# docs/10 taskblock03 C1: ease to the over-the-shoulder attack framing —
	# never a cut. C2: a default, not a lock; orbit/pan/zoom stay live and
	# will interrupt this the instant the player touches them.
	camera_rig.ease_to_attack_framing(
		_world_pos(selection.selected_unit.cell), _world_pos(target.cell)
	)
	aim_changed.emit()


## docs/10 taskblock03 C1: a unit's cell as a ground-level world position —
## the same conversion BattleScene/BoardView already use elsewhere.
func _world_pos(cell: Vector2i) -> Vector3:
	return Vector3(cell.x, 0.0, cell.y) * UnitGeometry.CELL_SIZE


## docs/10 taskblock03 C2: the F "reset framing" key — eases back to the
## SAME over-the-shoulder default `_enter_aim_mode` eased to, after the
## player has orbited/panned/zoomed away from it. A no-op outside Attack
## mode (nothing to reset to).
func reset_framing() -> void:
	if input_locked or aiming_at == null or selection.selected_unit == null:
		return
	camera_rig.ease_to_attack_framing(
		_world_pos(selection.selected_unit.cell), _world_pos(aiming_at.cell)
	)


## Steps the read layer without moving the reticle (docs/10's load-bearing
## rule) — clamping to a valid layer is AimController's job, this just
## accumulates the raw step.
func scroll_layer(delta: int) -> void:
	if input_locked:
		return
	if aiming_at != null:
		layer_index += delta
		aim_changed.emit()


func move_reticle(delta: Vector2) -> void:
	if input_locked:
		return
	if aiming_at != null:
		reticle_offset += delta
		aim_changed.emit()


## The shot plane for the current shooter -> aiming_at line of fire, with
## the shooter's own body excluded — the same exclusion AttackAction's own
## first hit-lookup applies (its own body sits right at the ray's origin
## and would otherwise resolve as a phantom "nearest layer" the aim UI has
## no business reading).
func aim_plane() -> Array[Region]:
	if aiming_at == null or selection.selected_unit == null:
		return []
	var shooter: Unit = selection.selected_unit
	var origin := Vector2(shooter.cell.x, shooter.cell.y)
	var direction := Vector2(aiming_at.cell - shooter.cell)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), selection.state)
	var filtered: Array[Region] = []
	for region: Region in plane:
		if region.body != shooter:
			filtered.append(region)
	return filtered


## Queues an AttackAction carrying the reticle's current aim_offset, using
## whatever weapon the shooter can actually operate (docs/01 capability
## matching) — a no-op, silently, if the shooter has nothing operable.
func confirm_shot() -> void:
	if input_locked or aiming_at == null or selection.selected_unit == null:
		return
	var shooter: Unit = selection.selected_unit
	var weapon: Part = DeepStrike.find_operable_weapon(shooter)
	if weapon != null:
		selection.current_queue().enqueue(
			AttackAction.new(shooter, weapon.id, aiming_at.cell, reticle_offset), selection.state
		)
	cancel_aim()


func cancel_aim() -> void:
	aiming_at = null
	layer_index = 0
	reticle_offset = Vector2.ZERO
	camera_rig.zoom_enabled = true
	aim_changed.emit()
	_refresh_overlay()


## Queues ending the selected unit's turn and actually resolves it —
## RESOLUTION, not TACTICS, is what's allowed to mutate the real state.
## Locks input for the caller to hold through however long it plays the
## resulting events back (docs/10 Phase 12.4); call unlock_input() once
## that's done.
func end_turn() -> void:
	if input_locked or selection == null or selection.selected_unit == null:
		return
	if aiming_at != null:
		cancel_aim()

	input_locked = true
	var sink := MemorySink.new()
	selection.state.combat_log.add_sink(sink)
	selection.queue_end_turn()
	selection.state.resolve_turn(selection.current_queue())
	selection.state.combat_log.remove_sink(sink)

	selection.reset()
	board_view.clear_overlays()
	selection_changed.emit()
	turn_ended.emit(sink.events)


## Called once the resolution playback finishes — returns control to
## TACTICS input.
func unlock_input() -> void:
	input_locked = false


func _refresh_overlay() -> void:
	selection_changed.emit()
	if selection.selected_unit == null:
		board_view.clear_overlays()
		return
	board_view.show_reachable(selection.reachable_cells())
	board_view.show_ghost_paths(selection.ghost_paths())
