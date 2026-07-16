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

## docs/10 taskblock02 F3: Q/E step size — docs/10 doesn't pin an exact
## increment, a flagged placeholder, not a design decision. 45 degrees:
## enough turns to face any of 8 directions.
const FACE_STEP := PI / 4.0

## docs/10 taskblock03 E1: mouse-drag facing sensitivity — same flagged-
## placeholder status as FACE_STEP above, docs/10 asks for "continuous, any
## angle," not an exact mapping.
const FACE_DRAG_SENSITIVITY := 0.01

var selection: SelectionController
var board_view: BoardView
var camera_rig: CameraRig
var camera: Camera3D

## Non-null while in Attack mode (docs/10): the enemy being aimed at.
var aiming_at: Unit = null
var layer_index: int = 0
var reticle_offset: Vector2 = Vector2.ZERO

## runNotes.md: "clicking on a red team unit should show their parts as
## well, even during the blue team's turn." Deliberately separate from
## `selection.selected_unit`, which stays gated to "the unit whose turn it
## is" (the only unit any action can legally queue against) — inspecting a
## unit's inventory is a read, never a TACTICS decision, so it has no
## business being restricted the same way. Sticky across deselection: a
## human still looking at what they just clicked on shouldn't lose that
## view just because they clicked away from the board.
var inspected_unit: Unit = null

## True for the whole of RESOLUTION (docs/10): set the instant End Turn
## resolves, cleared once whoever is playing back the log calls
## unlock_input(). The real mutation already happened synchronously by
## then — this only blocks further TACTICS input during the cosmetic
## replay, never delays the sim itself.
var input_locked: bool = false

## docs/10 taskblock03 E1: press-and-hold on the already-selected unit's own
## body starts a facing drag; live for as long as LMB stays down.
var _facing_drag_active: bool = false
## The one FaceAction this drag gesture owns, so every subsequent motion
## event mutates it in place instead of queuing a fresh one per pixel of
## mouse movement — see drag_face().
var _drag_face_action: FaceAction = null

## runNotes.md: "keep both things on RMB, but make undo last action only on
## click, while a drag doesn't cancel the action." RMB also drives camera
## orbit (CameraRig, independently, via Input.is_mouse_button_pressed) — the
## undo/cancel-aim side only fires on release, and only if no motion event
## arrived while the button was down.
var _rmb_pressed: bool = false
var _rmb_dragged: bool = false


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
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _rmb_pressed:
			# runNotes.md: any motion while RMB is held marks this a drag
			# (an orbit gesture, CameraRig's own concern) rather than a
			# click — checked unconditionally, alongside whichever branch
			# below also fires for this same event, so dragging RMB while
			# aiming (say) still registers as a drag even though the
			# reticle branch handles the event too.
			_rmb_dragged = true
		if aiming_at != null:
			# runNotes.md: "isn't following the cursor exactly instead being
			# offset" — a raycast onto the dartboard's own plane through the
			# literal cursor position, not an accumulated relative delta.
			aim_reticle_at_screen(motion.position)
		elif _facing_drag_active:
			drag_face(motion.relative.x)
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed:
			return
		if key_event.keycode == ControlBindings.DESELECT_KEY:
			# docs/10 taskblock02 F2: Esc always backs out one level — out
			# of Attack mode first if aiming, otherwise a plain deselect.
			if aiming_at != null:
				cancel_aim()
			else:
				deselect()
		elif key_event.keycode == ControlBindings.FACE_NUDGE_CCW_KEY and aiming_at == null:
			turn_selected(-FACE_STEP)
		elif key_event.keycode == ControlBindings.FACE_NUDGE_CW_KEY and aiming_at == null:
			turn_selected(FACE_STEP)
		elif key_event.keycode == ControlBindings.RESET_FRAMING_KEY and aiming_at != null:
			reset_framing()
		elif key_event.keycode == ControlBindings.RESET_TURN_KEY:
			reset_turn()


func _handle_mouse_button(button_event: InputEventMouseButton) -> void:
	if not button_event.pressed:
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			# docs/10 taskblock03 E1: releasing LMB ends a facing drag, if
			# one was active — a plain click never started one.
			_facing_drag_active = false
			_drag_face_action = null
		elif button_event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_rmb_release()
		return
	if button_event.button_index == MOUSE_BUTTON_LEFT:
		var from: Vector3 = camera.project_ray_origin(button_event.position)
		var dir: Vector3 = camera.project_ray_normal(button_event.position)
		var cell: Variant = _cell_at(from, dir)
		if (
			cell != null
			and aiming_at == null
			and selection.selected_unit != null
			and _unit_at(cell) == selection.selected_unit
		):
			# docs/10 taskblock03 E1: press-and-hold on the already-selected
			# unit's own body starts a facing drag — a plain click_cell()
			# here would just be a no-op reselect anyway.
			_facing_drag_active = true
			return
		if cell != null:
			click_cell(cell)
		elif aiming_at == null:
			# docs/10 taskblock02 F2: clicking off the board entirely is
			# "away" — deselect. A click still on the board but out of
			# reach is a different thing (the player is aiming for a cell
			# they can't use yet, not backing out) and stays a no-op.
			deselect()
	elif button_event.button_index == MOUSE_BUTTON_RIGHT:
		# runNotes.md: RMB also orbits the camera (CameraRig, independently)
		# — only start tracking here; the actual undo/cancel-aim decision
		# waits for release, once we know whether it turned into a drag.
		_rmb_pressed = true
		_rmb_dragged = false
	elif button_event.button_index == MOUSE_BUTTON_WHEEL_UP and aiming_at != null:
		scroll_layer(1)
	elif button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and aiming_at != null:
		scroll_layer(-1)


## runNotes.md: "make undo last action only on click, while a drag doesn't
## cancel the action" — same rule covers cancel-aim, the other thing RMB
## already does (docs/10 taskblock03 D3/C2).
func _handle_rmb_release() -> void:
	var was_drag: bool = _rmb_dragged
	_rmb_pressed = false
	_rmb_dragged = false
	if was_drag:
		return
	if aiming_at != null:
		cancel_aim()
		return
	# docs/10 taskblock03 D3: RMB pops the last queued action; with
	# nothing left to pop, it's a plain deselect.
	if not selection.undo_last():
		deselect()
	else:
		_drag_face_action = null
		_refresh_overlay()


## docs/10 taskblock03 D1: "click the body, not just the tile" — nearest hit
## wins between a unit's own boxes and the ground plane, so a click square
## on a unit's mesh selects it even when the ray would also cross the tile
## underneath at a farther distance (impossible here, but a mesh that
## overhangs a neighboring tile is exactly the case this guards).
func _cell_at(from: Vector3, dir: Vector3) -> Variant:
	var unit_hit: Dictionary = UnitPicker.hit(selection.state.units, from, dir)
	var ground_t: Variant = BoardPicker.plane_hit_t(from, dir)
	if not unit_hit.is_empty():
		if ground_t == null or (unit_hit["t"] as float) <= (ground_t as float):
			return (unit_hit["unit"] as Unit).cell
	if ground_t == null:
		return null
	return BoardPicker.cell_at_ray(from, dir)


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
	if unit_here != null:
		# runNotes.md: inspecting a unit's inventory is independent of
		# whether this click also selects it or enters aim mode below.
		inspected_unit = unit_here
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


## docs/10 taskblock03 D4: Reset Turn — button + R. Cancels any live aim
## (there's nothing left to aim from once the queue that led here is gone)
## and hands off to SelectionController.reset_turn(), which is the entire
## fix (docs/09: TACTICS never mutated authoritative state in the first
## place, so there's nothing else to roll back).
func reset_turn() -> void:
	if input_locked or selection == null or selection.selected_unit == null:
		return
	if aiming_at != null:
		cancel_aim()
	selection.reset_turn()
	_drag_face_action = null
	_refresh_overlay()


## docs/10 taskblock03 E1: mouse-drag facing — continuous, any angle, no
## steps. The FIRST motion event of a drag queues one real FaceAction,
## through the same MP/AP legality gate a manual Q/E press goes through;
## every motion event after that mutates that SAME action's `direction` in
## place, so one drag gesture is always exactly one queued action — never a
## pile of micro-turns RMB would have to undo one pixel at a time.
func drag_face(delta_x: float) -> void:
	if input_locked or selection == null or selection.selected_unit == null or aiming_at != null:
		return
	var target: float = selection.previewed_orientation() + delta_x * FACE_DRAG_SENSITIVITY
	if _drag_face_action != null:
		_drag_face_action.direction = target
		_refresh_overlay()
		return
	if selection.queue_face(target):
		var queue: ActionQueue = selection.current_queue()
		_drag_face_action = queue.actions[queue.actions.size() - 1] as FaceAction
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
	# docs/10 taskblock04 A3: wheel still steps the dartboard layer instead
	# of zooming while aiming (unrelated, pre-existing) — but orbit/pan (and
	# now the ease itself) stay live: the attack camera orbits the target's
	# own bounding sphere as a stable pivot, so swinging around it mid-aim
	# is just the inspection camera taskblock-03 C2 always wanted, not
	# something that can break the reticle anymore (aim_reticle_at_screen
	# raycasts against the live camera, whatever angle it's at).
	camera_rig.zoom_enabled = false
	camera_rig.ease_to_attack_framing(selection.selected_unit, target)
	aim_changed.emit()


## docs/10 taskblock03 C2: the F "reset framing" key — eases back to the
## SAME solved framing `_enter_aim_mode` eased to, after the player has
## orbited/panned/zoomed away from it. A no-op outside Attack mode (nothing
## to reset to).
func reset_framing() -> void:
	if input_locked or aiming_at == null or selection.selected_unit == null:
		return
	camera_rig.ease_to_attack_framing(selection.selected_unit, aiming_at)


## Steps the read layer without moving the reticle (docs/10's load-bearing
## rule) — clamping to a valid layer is AimController's job, this just
## accumulates the raw step.
func scroll_layer(delta: int) -> void:
	if input_locked:
		return
	if aiming_at != null:
		layer_index += delta
		aim_changed.emit()


## A relative nudge, still used by anything that isn't a live cursor
## (keyboard/controller input, or a test driving the reticle directly with
## no camera in play) — see aim_reticle_at_screen() for the real mouse path.
func move_reticle(delta: Vector2) -> void:
	if input_locked:
		return
	if aiming_at != null:
		reticle_offset += delta
		aim_changed.emit()


## runNotes.md: "Dartboard isn't following the cursor exactly instead being
## offset." The old mouse path accumulated `motion.relative` deltas scaled
## by a fixed sensitivity, a screen-space stand-in for the shot plane that
## silently stopped matching the screen the moment the camera wasn't at its
## exact default orientation. This instead raycasts from the camera through
## the cursor's actual screen position and intersects it with the
## dartboard's real plane (AimPlaneGeometry, shared with AimView's own
## rendering of that same plane) — wherever the cursor visibly points,
## that's where the reticle actually is, at any camera angle. (This is also
## what makes docs/10 taskblock04 A3's "keep orbit live during aim" safe —
## there's no fixed-angle assumption left to break.)
func aim_reticle_at_screen(screen_pos: Vector2) -> void:
	if input_locked or aiming_at == null or camera == null:
		return
	var aim: Dictionary = aim_state()
	if aim.is_empty():
		return
	var shooter: Unit = aim["shooter"]
	var target: Unit = aim["target"]
	var plane: Array[Region] = aim["plane"]
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var hit: Variant = AimPlaneGeometry.aim_point_from_ray(
		shooter.cell, target.cell, ray_origin, ray_dir
	)
	if hit == null:
		return
	reticle_offset = (hit as Vector2) - ShotPlane.center_of(plane, target)
	aim_changed.emit()


## docs/10 taskblock03 D5: "aim from where the unit WILL BE." Everything the
## aim UI needs, read from ONE speculative preview clone — the same one
## TACTICS already previews every queued action against
## (SelectionController.previewed_unit()'s own source), never the
## authoritative `selection.state` — so a queued move behind cover changes
## what the reticle resolves to before the human commits anything.
## `{"shooter": Unit, "target": Unit, "plane": Array[Region]}`, or an empty
## Dictionary while not aiming. All three MUST come from the same preview:
## calling `.preview()` a second time to fetch shooter/target separately
## would hand back an unrelated clone whose Parts never object-match the
## first clone's Regions, silently breaking anything that matches
## Region.part/body identity (ShotPlane.center_of, AimController.resolve).
## That clone already carries every unit (allies included), just with only
## the shooter's own queued actions replayed onto it — nothing extra is
## needed for "other units who have also queued moves" until this
## architecture ever lets more than one unit queue at once.
func aim_state() -> Dictionary:
	if aiming_at == null or selection.selected_unit == null:
		return {}
	var preview: CombatState = selection.current_queue().preview(selection.state)
	var shooter: Unit = preview.find_unit(selection.selected_unit.id)
	var target: Unit = preview.find_unit(aiming_at.id)
	if shooter == null or target == null:
		return {}
	var origin := Vector2(shooter.cell.x, shooter.cell.y)
	var direction := Vector2(target.cell - shooter.cell)
	var raw: Array[Region] = ShotPlane.build(origin, direction.normalized(), preview)
	# The shooter's own body sits right at the ray's origin and would
	# otherwise resolve as a phantom "nearest layer" the aim UI has no
	# business reading — the same exclusion AttackAction's own first
	# hit-lookup applies.
	var plane: Array[Region] = []
	for region: Region in raw:
		if region.body != shooter:
			plane.append(region)
	return {"shooter": shooter, "target": target, "plane": plane}


## Convenience for a caller that only needs the plane itself — see
## aim_state() when shooter/target identity matters too.
func aim_plane() -> Array[Region]:
	var aim: Dictionary = aim_state()
	if aim.is_empty():
		return []
	return aim["plane"]


## runNotes.md: "the controlled unit ghost should face the aimed-at unit
## while aiming is happening, and if aiming is cancelled, then they
## 'unface'." A display-only override — never a queued FaceAction, so
## cancelling requires no cleanup: aiming_at just goes null, this starts
## returning null again, and both the previewed body/wedge (UnitView) and
## the end-position ghost fall straight back to whatever WAS queued.
## Reads from the same speculative preview aim_state() itself uses, so it
## agrees with D5's "aim from where the unit WILL BE" for position too.
func aim_facing() -> Variant:
	var aim: Dictionary = aim_state()
	if aim.is_empty():
		return null
	var shooter: Unit = aim["shooter"]
	var target: Unit = aim["target"]
	return FaceAction.orientation_toward(shooter.cell, target.cell)


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
	board_view.show_ghost_paths(selection.ghost_paths(), selection.leg_costs())
	board_view.show_unit_ghost(_end_position_ghost())


## docs/10 taskblock03 F1: only worth drawing once a move is actually
## queued (the previewed CELL differs from where the unit already,
## visibly, is) — "ghost of the unit where it will end up after the
## queued path." runNotes.md: a plain in-place rotation (no move queued)
## used to ALSO spawn a ghost sitting right on top of the real unit,
## showing the same turn twice — that case is now the live model's job
## alone (see BattleScene._on_selection_changed()), so the ghost only ever
## exists once there's an actual "where it will end up" to show. While
## aiming, the ghost's own orientation is overridden to face the target —
## `previewed` is a disposable clone fresh off SelectionController.
## previewed_unit() each call, so mutating its orientation here can never
## leak back onto anything real.
func _end_position_ghost() -> Unit:
	if not has_queued_move():
		return null
	var previewed: Unit = selection.previewed_unit()
	var facing: Variant = aim_facing()
	if facing != null:
		previewed.orientation = facing
	return previewed


## runNotes.md: true once the selected unit's queue has actually moved it
## somewhere — the dividing line between "the live model previews its own
## future" (nothing queued yet) and "the ghost previews it instead" (a
## move is queued, so the live model stays put at its committed facing
## until it actually gets there). Never both at once.
func has_queued_move() -> bool:
	if selection == null or selection.selected_unit == null:
		return false
	var previewed: Unit = selection.previewed_unit()
	return previewed != null and previewed.cell != selection.selected_unit.cell
