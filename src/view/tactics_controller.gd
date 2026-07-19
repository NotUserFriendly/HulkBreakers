# gdlint:disable=max-public-methods
# docs/10 taskblock06 G2: this is the one class in the project that adds a
# public method per interaction primitive by design (one per input/UI entry
# point — see the class doc comment below) — gdlintrc's project-wide
# max-public-methods stays a meaningful gate for every other class, so the
# override is scoped to this file alone rather than raised globally.
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
## docs/10 taskblock06 G1/G2: "Resolve to Here" — carries whatever events
## the partial resolve emitted, same shape as turn_ended but the turn
## itself has NOT ended (the unit stays selected, current_unit() is
## unchanged unless the resolved prefix itself contained an EndTurnAction).
signal queue_partially_resolved(events: Array[LogEvent])
signal aim_changed
## Fires whenever `selection.selected_unit` might have changed — the stat
## panel (docs/08/10 Phase 12.5) redraws from this rather than polling.
signal selection_changed
## docs/10 taskblock04 E3: fires whenever `hovered_cell` or `inspected_part`
## changes — the combat readout redraws from this rather than polling.
signal hover_changed
## taskblock-08 D1: fires on EVERY board mouse-motion `update_hover()`
## handles, unconditionally — unlike `hover_changed` (change-gated on
## purpose, test_tactics_controller_hover.gd's own invariant), this is
## purely "the cursor moved," for the one caller that needs to track it
## continuously even while the hovered cell/part stays the same: the
## tooltip (TooltipController), so it can keep pinning itself to the
## cursor (D1) rather than the item, without re-triggering a full readout
## rebuild on every pixel of motion the way listening on `hover_changed`
## alone would require.
signal mouse_moved
## docs/10 taskblock05 C: "hovering a part highlights it in the world,
## bidirectionally." Meaningful only for the currently selected unit's own
## parts (the only body the inventory tree has rows for at all). Shared by
## a real 3D hover (`update_hover`) and the inventory panel's own row
## hover — one mechanism, two triggers, distinct from `inspected_part`
## below (that one's click-driven and feeds the text readout; this one's
## hover-driven and feeds the 3D glow + tree-row highlight).
signal highlight_changed

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
## taskblock-08 A: non-null while an action-bar action is armed and
## waiting for its target click — "SHOOT armed -> the next enemy click is
## the target." Always non-null whenever `aiming_at` is (arming is the
## only way to enter aim mode now); can be non-null on its own, between
## arming and the target click.
var armed_action: ActionDef = null
var layer_index: int = 0
var reticle_offset: Vector2 = Vector2.ZERO

## taskblock-18 D2/D4: non-null while choosing a step-out firing cell — the
## enemy that's not directly attackable from here but IS from a legal
## step-out cell. Mirrors `aiming_at`'s own two-step "arm, then click to
## confirm" shape, just choosing a firing cell instead of a reticle
## offset; never both non-null at once. A step out's own shot is always
## center-mass/automated — there is no reticle/dartboard step for it.
var stepping_out_at: Unit = null

## docs/10 taskblock04 E3: "hover, don't click" — the cell the combat
## readout currently reads (terrain, any unit regardless of squad, any
## field object — TileInspection.inspect()). null off the board entirely
## (e.g. the cursor sitting over a UI panel, where board hover never
## fires). Superseded the old click-based `inspected_unit` (runNotes.md)
## once hover covered "any unit, full detail" more directly — cutting the
## inventory panel back to the currently controlled shell only (E2) is
## what made that click-based mechanism redundant here.
var hovered_cell: Variant = null
## Set by clicking a row in the inventory panel (E3: "clicking a part in
## the inventory panel fills the same readout with that part's detail") —
## one readout, three sources. Cleared the instant the board is hovered
## again (`update_hover`): whatever the player is actually pointing at
## wins over a stale click.
var inspected_part: Part = null
## Set by `highlight_changed`'s own two triggers — see the signal's own doc
## comment above.
var highlighted_part: Part = null

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

## Every legal step-out cell for `stepping_out_at`, safest-first (D2: "default to
## the safest legal firing cell... mouse-wheel cycles other valid
## cells") — computed once on entering step-out mode, never while cycling.
var _step_out_candidates: Array[Vector2i] = []
var _step_out_cell_index: int = 0


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
		else:
			# docs/10 taskblock04 E3: "hover, don't click" — plain idle
			# movement over the board updates what the combat readout
			# shows. Only reached here, never while aiming/dragging: the
			# reticle and the facing drag are both a more specific, more
			# urgent read of the same motion event.
			update_hover(motion.position)
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed:
			return
		if key_event.keycode == ControlBindings.DESELECT_KEY:
			# docs/10 taskblock02 F2: Esc always backs out one level — out of
			# Attack mode first if aiming, then out of an armed action if one
			# is armed but not yet aimed (taskblock-08 A1), otherwise a plain
			# deselect.
			if aiming_at != null:
				cancel_aim()
			elif stepping_out_at != null:
				cancel_step_out()
			elif armed_action != null:
				disarm_action()
			else:
				deselect()
		elif (
			key_event.keycode == ControlBindings.FACE_NUDGE_CCW_KEY
			and aiming_at == null
			and stepping_out_at == null
		):
			turn_selected(-FACE_STEP)
		elif (
			key_event.keycode == ControlBindings.FACE_NUDGE_CW_KEY
			and aiming_at == null
			and stepping_out_at == null
		):
			turn_selected(FACE_STEP)
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
		var hit: Variant = _cell_at(from, dir)
		var hit_dict: Dictionary = hit as Dictionary if hit != null else {}
		if (
			not hit_dict.is_empty()
			and aiming_at == null
			and stepping_out_at == null
			and selection.selected_unit != null
			and hit_dict["kind"] == Enums.HitKind.UNIT
			and hit_dict["unit"] == selection.selected_unit
		):
			# docs/10 taskblock03 E1: press-and-hold on the already-selected
			# unit's own body starts a facing drag — a plain click here
			# would just be a no-op reselect anyway.
			_facing_drag_active = true
			return
		# docs/10 taskblock05 A1: dispatch on the actual hit directly — a
		# unit ray-hit is never collapsed into a cell and re-derived.
		if aiming_at != null or stepping_out_at != null:
			confirm_shot()
		elif hit_dict.is_empty():
			# docs/10 taskblock02 F2: clicking off the board entirely is
			# "away" — deselect. A click still on the board but out of
			# reach is a different thing (the player is aiming for a cell
			# they can't use yet, not backing out) and stays a no-op.
			deselect()
		elif hit_dict["kind"] == Enums.HitKind.UNIT:
			_click_unit(hit_dict["unit"])
		else:
			if selection.selected_unit != null:
				selection.queue_move(hit_dict["cell"])
			_refresh_overlay()
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
	elif button_event.button_index == MOUSE_BUTTON_WHEEL_UP and stepping_out_at != null:
		cycle_step_out_cell(1)
	elif button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and stepping_out_at != null:
		cycle_step_out_cell(-1)


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
	if stepping_out_at != null:
		cancel_step_out()
		return
	# taskblock-08 A1: "Esc / RMB disarms the action and returns to normal
	# selection" — same early-out shape as the aiming_at case above, one
	# step earlier in the arm-then-click sequence.
	if armed_action != null:
		disarm_action()
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
##
## docs/10 taskblock05 A1: returns what was actually hit — `{kind, unit,
## cell}` — never just a bare cell. A caller that collapsed a unit hit into
## its cell and then re-derived the unit from that cell (`_unit_at(cell)`)
## was a lossy round-trip: the identity of the specific Unit a ray struck
## has to survive to the click handler unchanged, not be thrown away and
## guessed back at from a coordinate. Null off the board entirely.
func _cell_at(from: Vector3, dir: Vector3) -> Variant:
	var unit_hit: Dictionary = UnitPicker.hit(selection.state.units, from, dir)
	var ground_t: Variant = BoardPicker.plane_hit_t(from, dir)
	if not unit_hit.is_empty():
		if ground_t == null or (unit_hit["t"] as float) <= (ground_t as float):
			var unit: Unit = unit_hit["unit"]
			# docs/10 taskblock05 C: UnitPicker's own nearest-box search
			# already knows which Part it struck — carried through here so a
			# 3D hover can highlight that exact part, not just its unit.
			return {
				"kind": Enums.HitKind.UNIT,
				"unit": unit,
				"part": unit_hit["part"],
				"cell": unit.cell
			}
	if ground_t == null:
		return null
	return {"kind": Enums.HitKind.CELL, "unit": null, "cell": BoardPicker.cell_at_ray(from, dir)}


## docs/10 taskblock04 E3: "hover, don't click" — the combat readout's own
## live cursor read. `screen_pos` off the board entirely (no ground/unit
## hit at all — e.g. the cursor is over a UI panel) sets `hovered_cell` to
## null rather than leaving a stale cell behind.
func update_hover(screen_pos: Vector2) -> void:
	if selection == null or camera == null:
		return
	mouse_moved.emit()
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var hit: Variant = _cell_at(from, dir)
	var hit_dict: Dictionary = hit as Dictionary if hit != null else {}
	var cell: Variant = hit_dict.get("cell") if hit != null else null
	if cell != hovered_cell or inspected_part != null:
		hovered_cell = cell
		inspected_part = null
		hover_changed.emit()

	# docs/10 taskblock05 C: "hovering a part in 3D highlights its row in
	# the tree" — meaningful only for the currently selected unit's own
	# parts, the only body the inventory tree has rows for at all
	# (taskblock04 E2). Hovering anything else (empty ground, a different
	# unit) clears it.
	var hovered_part: Variant = null
	if hit_dict.get("kind") == Enums.HitKind.UNIT and hit_dict["unit"] == selection.selected_unit:
		hovered_part = hit_dict["part"]
	hover_part(hovered_part)


## docs/10 taskblock04 E3: "clicking a part in the inventory panel fills
## the same readout with that part's detail" — one readout, three sources.
func inspect_part(part: Part) -> void:
	inspected_part = part
	hover_changed.emit()


## docs/10 taskblock05 C: sets the currently glowing part — called by a
## real 3D hover (`update_hover`) and by the inventory panel's own row
## hover. `part` may be null (nothing hovered, or hovering something this
## mechanism has no row/box for).
func hover_part(part: Variant) -> void:
	if part == highlighted_part:
		return
	highlighted_part = part
	highlight_changed.emit()


## While aiming: any click confirms the shot (docs/10: "click / confirm ->
## queue an AttackAction"), regardless of which cell was actually clicked.
## Otherwise: click your own (current-turn) unit to select it; with a unit
## selected AND an action armed (taskblock-08 A1 — `arm_action()`, from the
## action bar), click a live enemy to enter Attack mode with that action's
## own weapon; with nothing armed, a bare enemy click does nothing (hover
## already inspects it — taskblock04 E3). A click on a reachable cell
## always queues a move there regardless of arming. A click on a valid,
## on-board cell never cancels a selection by itself — that's
## `deselect()`'s job, reached via Esc or an off-board click (docs/10
## taskblock02 F2), never a plain in-board click that just happens to be
## out of reach.
##
## Cell-only API: for a real mouse click, `_handle_mouse_button` dispatches
## on `_cell_at`'s own hit directly (docs/10 taskblock05 A1) rather than
## routing through here, so a specific Unit a ray struck is never re-derived
## by coordinate. This stays as the coarser, cell-driven entry point tests
## and other callers already use.
func click_cell(cell: Vector2i) -> void:
	if input_locked:
		return
	if aiming_at != null or stepping_out_at != null:
		confirm_shot()
		return

	var unit_here: Unit = _unit_at(cell)
	if unit_here != null:
		_click_unit(unit_here)
		return
	if selection.selected_unit != null:
		selection.queue_move(cell)
	_refresh_overlay()


## docs/10 taskblock05 A1: the branch table for "a unit's own body was hit"
## — every (unit x selection state) pair resolves here, explicitly, rather
## than some combinations silently falling through to nothing. Only the
## active unit can ever actually be selected (SelectionController.select);
## a non-current unit hit with nothing selected has nowhere to go — full
## detail on any unit already comes from hover (taskblock04 E1/E3), so a
## bare click on one has no further job to do.
##
## taskblock-08 A1: "clicking an enemy no longer starts an attack" — a
## non-current unit only ever enters Attack mode while an action is armed
## (`armed_action != null`); a bare enemy click with nothing armed is
## explicitly a no-op (Pass A: "since hover already inspects").
func _click_unit(unit_here: Unit) -> void:
	if unit_here == selection.state.current_unit():
		selection.select(unit_here)
		armed_action = null
	elif armed_action != null and selection.selected_unit != null:
		_enter_aim_or_step_out_mode(unit_here)
	_refresh_overlay()


## docs/10 taskblock02 F2: "click away / Esc → deselect." A no-op if
## nothing's selected in the first place.
func deselect() -> void:
	if selection == null or selection.selected_unit == null:
		return
	selection.select(null)
	armed_action = null
	_refresh_overlay()


## taskblock-08 A1: "selecting an action arms a targeting mode... the
## armed action decides what a click means." `action_id` must be one
## ActionCatalog.actions_for(selected_unit) actually lists right now — the
## same source the action bar itself renders from — and must need a target
## at all (ActionDef.requires_target); anything else is a no-op, silently,
## same posture as confirm_shot()'s own "nothing operable" case. This is
## the ONE arming entry point regardless of which box called it — no
## per-action special-casing here or in the click handler.
func arm_action(action_id: StringName) -> void:
	if input_locked or selection == null or selection.selected_unit == null:
		return
	if aiming_at != null or stepping_out_at != null:
		return
	var def: ActionDef = null
	for candidate: ActionDef in ActionCatalog.actions_for(selection.selected_unit):
		if candidate.id == action_id:
			def = candidate
			break
	if def == null or not def.requires_target:
		return
	armed_action = def
	aim_changed.emit()


## taskblock-08 A1: "Esc / RMB disarms the action and returns to normal
## selection" — armed-but-not-yet-aimed only; `cancel_aim()` is the aiming
## case (and clears `armed_action` itself, so this is never needed there).
func disarm_action() -> void:
	armed_action = null
	aim_changed.emit()


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
	if stepping_out_at != null:
		cancel_step_out()
	armed_action = null
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
	if (
		input_locked
		or selection == null
		or selection.selected_unit == null
		or aiming_at != null
		or stepping_out_at != null
	):
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


## taskblock-18 D2: "clicking SHOOT on an enemy the unit can't see but
## could from a legal step-out cell builds the triple automatically." A
## direct shot (the origin is NOT covered from this target — D1's own
## trigger condition) enters ordinary aim mode, unchanged; a target only
## reachable via a step out enters step-out-choice mode instead, and never falls
## through to aim mode's own reticle/dartboard UI, which a step out's own
## automated, center-mass shot has no use for. Falls back to plain aim
## mode when neither applies (no operable weapon, or no legal step out
## exists) — confirm_shot()'s own existing "nothing operable" no-op is
## what actually catches that case, same as it always has.
func _enter_aim_or_step_out_mode(target: Unit) -> void:
	var shooter: Unit = selection.selected_unit
	var weapon: Part = (
		ActionCatalog.provider_for(shooter, armed_action.id) if armed_action != null else null
	)
	if weapon != null:
		var origin_covered: bool = UnitAI.is_covered_from(
			shooter.cell, target.cell, selection.state, shooter
		)
		if origin_covered:
			var candidates: Array[Vector2i] = StepOutPlanner.candidate_step_out_cells(
				selection.state, shooter, shooter.cell, target
			)
			if not candidates.is_empty():
				_enter_step_out_mode(
					target, StepOutPlanner.sort_by_safety(selection.state, shooter, candidates)
				)
				return
	_enter_aim_mode(target)


func _enter_aim_mode(target: Unit) -> void:
	aiming_at = target
	layer_index = 0
	reticle_offset = Vector2.ZERO
	# Aiming routes every subsequent mouse motion to aim_reticle_at_screen()
	# instead of update_hover() (below) — the only two call sites that ever
	# emit hover_changed/mouse_moved go quiet for the whole aim/confirm-shot
	# sequence. A tooltip already on screen from hovering before this click
	# would otherwise sit there, stale, until the player moves the mouse
	# over the board again post-resolution. Clearing it here mirrors
	# update_hover()'s own "nothing hit" reset exactly.
	if hovered_cell != null or inspected_part != null:
		hovered_cell = null
		inspected_part = null
		hover_changed.emit()
	# taskblock-08 B3a: orbit/pan/zoom lock the instant aim mode is
	# entered — aim is a committed framing now, inspection happens by
	# backing out (Esc). Reverses taskblock-04 A3's "keep orbit/pan/zoom
	# live during aim": the attack camera also LOOKS at the dartboard now
	# (B3b/B3c), which a live orbit would fight every frame.
	camera_rig.start_aiming()
	camera_rig.ease_to_attack_framing(_framing_shooter(), target)
	aim_changed.emit()


## taskblock-18 D2/D4: enters step-out-choice mode — safest candidate
## selected by default, mouse-wheel cycles the rest (cycle_step_out_cell).
## No camera framing/dartboard of its own: a step out's shot is always
## automated center-mass, there is nothing here for the player to aim.
func _enter_step_out_mode(target: Unit, candidates_by_safety: Array[Vector2i]) -> void:
	stepping_out_at = target
	_step_out_candidates = candidates_by_safety
	_step_out_cell_index = 0
	if hovered_cell != null or inspected_part != null:
		hovered_cell = null
		inspected_part = null
		hover_changed.emit()
	aim_changed.emit()
	_refresh_overlay()


func cancel_step_out() -> void:
	stepping_out_at = null
	_step_out_candidates = []
	_step_out_cell_index = 0
	armed_action = null
	aim_changed.emit()
	_refresh_overlay()


## D2: "mouse-wheel cycles other valid cells" — wraps both directions,
## a no-op with zero or one candidate.
func cycle_step_out_cell(delta: int) -> void:
	if input_locked or stepping_out_at == null or _step_out_candidates.is_empty():
		return
	var count: int = _step_out_candidates.size()
	_step_out_cell_index = ((_step_out_cell_index + delta) % count + count) % count
	aim_changed.emit()
	_refresh_overlay()


## taskblock-08 B1: "the camera frames the origin, not the ghost." The
## attack camera must read the shooter's QUEUED end cell, same speculative
## clone the ghost and the aim preview already read (taskblock-03 D5) —
## never `selection.selected_unit`'s own committed cell, which is where the
## unit still visibly stands until resolution actually moves it.
## `UnitGeometry.bounding_sphere()` only reads `.cell` (and the boxes'
## composed geometry) off whatever it's handed, so a disposable preview
## clone works exactly like the real Unit would.
func _framing_shooter() -> Unit:
	var previewed: Unit = selection.previewed_unit()
	return previewed if previewed != null else selection.selected_unit


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
	# docs/10 taskblock05 A3: "aim from where the unit WILL BE" applies to
	# facing too — the projected shot plane must be built from the facing
	# the shooter will actually have (AttackAction's own free face at
	# apply() time), or the preview lies about which side of the body
	# faces the target. Free, and applied only to this scratch clone —
	# never the real ActionQueue — so it costs nothing, never persists, and
	# can never collide with AttackAction.apply()'s own free face on the
	# real (entirely separate) resolution clone later.
	if shooter.cell != target.cell:
		FaceAction.face_for_free(
			preview,
			shooter,
			FaceAction.orientation_toward(shooter.cell, target.cell),
			&"free_with_aim"
		)
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
	# docs/09 taskblock07 Pass A: AimController.resolve()'s own RESOLVES side
	# now casts a real ray (ShotPlane.resolve_ray) against this same preview
	# — the exact state `plane` was itself built from, never a second,
	# separately-fetched clone (that would silently stop object-matching
	# `plane`'s own Regions, the same trap this function's own shooter/
	# target/plane triple already guards against).
	return {"shooter": shooter, "target": target, "plane": plane, "state": preview}


## runNotes.md: "the controlled unit ghost should face the aimed-at unit
## while aiming is happening, and if aiming is cancelled, then they
## 'unface'." A display-only override — never a queued FaceAction, so
## cancelling requires no cleanup: aiming_at just goes null, this starts
## returning null again, and both the previewed body/wedge (HitVolumeView) and
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
## whatever part actually provides `armed_action` (taskblock-08 A1: "the
## armed action decides what a click means" — SHOOT picks the shoot
## provider, SAW picks the saw provider, never just any weapon) — a no-op,
## silently, if the shooter has nothing operable for it right now.
func confirm_shot() -> void:
	if input_locked or selection == null or selection.selected_unit == null:
		return
	if stepping_out_at != null:
		_confirm_step_out()
		return
	if aiming_at == null:
		return
	var shooter: Unit = selection.selected_unit
	if armed_action != null:
		var weapon: Part = ActionCatalog.provider_for(shooter, armed_action.id)
		if weapon != null:
			selection.current_queue().enqueue(
				AttackAction.new(shooter, weapon.id, aiming_at.cell, reticle_offset),
				selection.state
			)
	cancel_aim()


## taskblock-18 D2: commits the step-out triple at whichever candidate cell
## is CURRENTLY selected (default: safest; the player may have cycled
## with the wheel first) — through StepOutPlanner.build_triple(), the same
## shared assembly AI step-outs use, queued onto this unit's own real
## TACTICS queue exactly like any other action (real MP/AP cost for both
## legs, no discount). A silent no-op if the shooter has nothing
## operable, same posture confirm_shot() itself already has.
func _confirm_step_out() -> void:
	var shooter: Unit = selection.selected_unit
	var weapon: Part = (
		ActionCatalog.provider_for(shooter, armed_action.id) if armed_action != null else null
	)
	if weapon != null and not _step_out_candidates.is_empty():
		var firing_cell: Vector2i = _step_out_candidates[_step_out_cell_index]
		StepOutPlanner.build_triple(
			selection.current_queue(),
			selection.state,
			shooter,
			weapon.id,
			stepping_out_at,
			shooter.cell,
			firing_cell
		)
	cancel_step_out()


func cancel_aim() -> void:
	aiming_at = null
	armed_action = null
	layer_index = 0
	reticle_offset = Vector2.ZERO
	camera_rig.stop_aiming()
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
	if stepping_out_at != null:
		cancel_step_out()
	armed_action = null

	input_locked = true
	var sink := MemorySink.new()
	selection.state.combat_log.add_sink(sink)
	selection.queue_end_turn()
	# docs/09 taskblock06 Pass F: the real mid-move interrupt check
	# (Overwatch.check_trigger) plugs into resolve_until's own seam here —
	# taskblock06 Pass D built it, Pass F is the first real caller.
	selection.state.resolve_until(selection.current_queue(), Overwatch.check_trigger)
	selection.state.combat_log.remove_sink(sink)

	selection.reset()
	board_view.clear_overlays()
	selection_changed.emit()
	turn_ended.emit(sink.events)


## docs/10 taskblock06 G1: "resolve_until with a player-placed stop marker
## instead of an interrupt — one mechanism, two triggers." `marker_index`
## is a caller-tracked index into the selected unit's own queue.actions
## (docs/10 taskblock06 G2: the queue-display panel owns clicking an entry
## to pick one — a UI-local read, not state this controller has to carry,
## since it's only ever needed at the instant this is called). Resolves
## only the queued prefix through `marker_index` (inclusive) for real
## against the authoritative state, through the exact same resolve_until()
## call end_turn() itself makes (Overwatch.check_trigger and all — an
## overwatcher doesn't care whether this is a partial or a full resolve).
## Unlike end_turn(), the unit STAYS selected and the turn does NOT end:
## nothing here calls advance_turn() unless the resolved prefix itself
## happened to contain one. Out-of-range `marker_index` (including "nothing
## queued") is a no-op.
func resolve_to_marker(marker_index: int) -> void:
	if input_locked or selection == null or selection.selected_unit == null:
		return
	var queue: ActionQueue = selection.current_queue()
	if marker_index < 0 or marker_index >= queue.actions.size():
		return
	if aiming_at != null:
		cancel_aim()
	if stepping_out_at != null:
		cancel_step_out()
	armed_action = null

	input_locked = true
	var prefix := ActionQueue.new(selection.selected_unit)
	prefix.actions = queue.actions.slice(0, marker_index + 1)
	var sink := MemorySink.new()
	selection.state.combat_log.add_sink(sink)
	selection.state.resolve_until(prefix, Overwatch.check_trigger)
	selection.state.combat_log.remove_sink(sink)

	# docs/10 taskblock06 G1: "then start queuing again" — reset_turn()
	# (docs/10 taskblock03 D4) is exactly "erase the queue, keep the unit
	# selected," the same bookkeeping a partial resolve needs; G3's own
	# default (Reset Turn after a partial resolve returns to the resolve
	# point, not turn start) falls out of this for free too, since
	# reset_turn() only ever erases the queue — it never tracked "turn
	# start" separately in the first place, so there's nothing left behind
	# to roll further back to.
	selection.reset_turn()
	_drag_face_action = null
	_refresh_overlay()
	# input_locked stays true here — exactly like end_turn(), whoever plays
	# the resulting events back (docs/10 Phase 12.4) owns calling
	# unlock_input() once that cosmetic replay finishes.
	queue_partially_resolved.emit(sink.events)


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
	board_view.show_overwatch_arc(
		Overwatch.all_threatened_cells(selection.state, selection.selected_unit)
	)


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
	if stepping_out_at != null:
		return _step_out_position_ghost()
	if not has_queued_move():
		return null
	var previewed: Unit = selection.previewed_unit()
	var facing: Variant = aim_facing()
	if facing != null:
		previewed.orientation = facing
	return previewed


## taskblock-18 D4: "the ghost must disclose exposure" starts with
## actually previewing the right POSITION first — a disposable clone
## of the shooter (display-only, same convention _end_position_ghost
## itself already uses for orientation overrides) relocated to
## whichever candidate cell is currently selected, facing the target.
## Never a queued MoveAction; cycling with the wheel must be free to
## look at every candidate without committing to any of them.
func _step_out_position_ghost() -> Unit:
	if _step_out_candidates.is_empty():
		return null
	var previewed: Unit = selection.previewed_unit()
	if previewed == null:
		return null
	previewed.cell = _step_out_candidates[_step_out_cell_index]
	previewed.orientation = FaceAction.orientation_toward(previewed.cell, stepping_out_at.cell)
	return previewed


## taskblock-18 D4: "is it in a known overwatch arc, what can see it" —
## every overwatcher that would trigger at the CURRENTLY selected step-out
## candidate, the exact same Overwatch.would_trigger_at() query the
## safest-cell pick itself used to rank candidates in the first place
## (never a second, re-derived notion of exposure). Empty while not
## stepping out, or with nothing yet threatening this specific cell.
func step_out_exposure() -> Array[Unit]:
	if stepping_out_at == null or _step_out_candidates.is_empty():
		return []
	var shooter: Unit = selection.selected_unit
	var firing_cell: Vector2i = _step_out_candidates[_step_out_cell_index]
	return Overwatch.would_trigger_at(selection.state, shooter, firing_cell)


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
