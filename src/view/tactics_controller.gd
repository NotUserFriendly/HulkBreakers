# gdlint:disable=max-public-methods,max-file-lines
# docs/10 taskblock06 G2: this is the one class in the project that adds a
# public method per interaction primitive by design (one per input/UI entry
# point — see the class doc comment below) — gdlintrc's project-wide
# max-public-methods stays a meaningful gate for every other class, so the
# override is scoped to this file alone rather than raised globally. Same
# reasoning extends the override to max-file-lines (taskblock-19 Pass F):
# one more primitive is one more method, and this file's own line count
# grows with the interaction surface it's the single thin shell for, not
# with sloppiness — splitting it is a real refactor to consider, not
# something to force through a line-count gate one taskblock at a time.
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
## taskblock-30/31: fires on every real LEFT click `_handle_mouse_button`/
## `click_cell` resolves, carrying the same `{"kind", "unit", "cell"}`
## shape `_cell_at` already produces — a generic "something was clicked"
## signal, deliberately knowing nothing about WHY a listener wants it (a
## debug panel's own board-picking mode, say). This class must never
## reference the debug injection channel at all
## (test_bout_injector_determinism.gd's own routing/guard test proves it
## from source, checking for the literal class name this comment is
## deliberately avoiding) — this signal is how a debug tool borrows a
## real click without this file knowing debug tooling exists.
signal board_clicked(hit: Dictionary)

## tb31 Pass D: the `Enums.TargetingMode.PART_PICKER` counterpart to
## `arm_action`/`queue_untargeted_action` — `ActionBar`'s own click handler
## emits this instead of arming/queuing directly; whichever overlay owns
## the actual picker UI (`SquadControlOverlay`'s repair popup today)
## connects to it. Never armed/queued from here — a picker needs the
## player to choose something first.
signal picker_action_requested(action_id: StringName)

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

## Non-null while in Attack mode (docs/10): what's being aimed at — a
## live unit (the original, unchanged case) or, since tb32 Pass C, a
## non-unit Part (wall/cover/downed object/field item, `PartPicker`'s new
## HitKind.PART) via `AimTarget`'s `cell`-always-populated wrapper.
var aiming_at: AimTarget = null
## taskblock-08 A: non-null while an action-bar action is armed and
## waiting for its target click — "SHOOT armed -> the next enemy click is
## the target." Always non-null whenever `aiming_at` is (arming is the
## only way to enter aim mode now); can be non-null on its own, between
## arming and the target click.
var armed_action: ActionDef = null
var layer_index: int = 0
var reticle_offset: Vector2 = Vector2.ZERO
## tb34 Pass C: the Part the cursor currently sits over inside the aim
## window, independent of `reticle_offset`/`resolves` — "hovering reads,
## it never re-aims" (the same discipline the scroll/READING split already
## enforces). Updated alongside the reticle in `aim_reticle_at_screen`
## (same cursor-derived plane point, one more read, never fed back into
## where the reticle sits or what the shot resolves against).
var aim_hovered_part: Part = null

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

## taskblock-30/31: while true, the NEXT real left click is captured —
## `_handle_mouse_button`'s own LEFT branch and `click_cell()` do nothing
## but emit `board_clicked` and return (no select, no move, no aim, no
## step-out). A generic capture mode, not a debug-specific one (see
## `board_clicked`'s own doc comment) — a caller sets this true, listens
## for one `board_clicked`, then sets it false again.
var input_capture_mode: bool = false

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

## taskblock-27 Pass B: non-null from the moment a step-out's own free
## outbound leg is queued (`_confirm_step_out`) until the whole triple
## either finishes (a real shot fired, the free return leg appended) or
## the player cancels aim mid-step-out — the cell to path the free return
## leg back to. `stepping_out_at`/`_step_out_candidates` are already gone
## by then (the player is in ordinary `aiming_at` mode, dartboard open,
## same as any other shot), so this is the one thing carried across that
## transition.
var _step_out_origin_cell: Vector2i = Vector2i.ZERO
var _returning_from_step_out: bool = false


## taskblock-22 Pass A2: `mission`, optional (default null, every existing
## caller/test unaffected) — threaded straight through to
## `SelectionController`, the one thing that actually needs it (the player
## squad's own passive extraction hold, checked when `queue_end_turn()`
## resolves).
func setup(
	state: CombatState,
	p_board_view: BoardView,
	p_camera_rig: CameraRig,
	p_mission: MissionState = null
) -> void:
	selection = SelectionController.new(state, p_mission)
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
		if input_capture_mode:
			board_clicked.emit(hit_dict)
			return
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
		elif hit_dict["kind"] == Enums.HitKind.PART:
			_click_part(hit_dict["part"], hit_dict["cell"])
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
##
## tb32 Pass C: `PartPicker` generalizes the ray test to blockers/field
## items too — a non-unit hit returns the new `Enums.HitKind.PART` kind
## instead of falling through to bare `CELL`, so a wall/cover/downed
## object/field item can be targeted at all (today, `CELL` clicks only
## ever queue a move).
func _cell_at(from: Vector3, dir: Vector3) -> Variant:
	var part_hit: Dictionary = PartPicker.hit(
		selection.state.units, selection.state.grid, from, dir
	)
	var ground_t: Variant = BoardPicker.plane_hit_t(from, dir)
	if not part_hit.is_empty():
		if ground_t == null or (part_hit["t"] as float) <= (ground_t as float):
			var unit: Unit = part_hit["unit"]
			if unit != null:
				# docs/10 taskblock05 C: the nearest-box search already knows
				# which Part it struck — carried through here so a 3D hover can
				# highlight that exact part, not just its unit.
				return {
					"kind": Enums.HitKind.UNIT,
					"unit": unit,
					"part": part_hit["part"],
					"cell": unit.cell
				}
			return {
				"kind": Enums.HitKind.PART,
				"unit": null,
				"part": part_hit["part"],
				"cell": part_hit["cell"]
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
	if input_capture_mode:
		var captured: Unit = _unit_at(cell)
		(
			board_clicked
			. emit(
				{
					"kind": Enums.HitKind.UNIT if captured != null else Enums.HitKind.CELL,
					"unit": captured,
					"cell": cell,
				}
			)
		)
		return
	if aiming_at != null or stepping_out_at != null:
		confirm_shot()
		return

	var unit_here: Unit = _unit_at(cell)
	if unit_here != null:
		_click_unit(unit_here)
		return
	# tb32 Pass C: the `PartPicker` counterpart — the same "coarser,
	# cell-driven" convenience `_unit_at` above already gives this API,
	# so a test can drive a PART click with a bare cell too, no real ray
	# needed.
	var part_here: Part = selection.state.grid.shootable_part_at(cell)
	if part_here != null:
		_click_part(part_here, cell)
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


## taskblock-08 A1 (tb31 Pass D): "selecting an action arms a targeting
## mode... the armed action decides what a click means." `action_id` must
## be one `ActionCatalog.actions_for(selected_unit)` actually lists right
## now — the same source the action bar itself renders from — and must be
## `Enums.TargetingMode.BOARD` (`ActionBar`'s own click handler is what
## routes NONE/PART_PICKER actions elsewhere now — see
## `queue_untargeted_action`/`picker_action_requested` below — so a
## non-BOARD id reaching here at all would already be a caller bug);
## anything else is a no-op, silently, same posture as confirm_shot()'s
## own "nothing operable" case. This is the ONE arming entry point for
## board-targeted actions regardless of which box called it — no
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
	if def == null or def.targeting_mode != Enums.TargetingMode.BOARD:
		return
	armed_action = def
	aim_changed.emit()


## tb31 Pass D: the `Enums.TargetingMode.NONE` counterpart to `arm_action`
## — queues the action immediately, no board target at all (overwatch:
## "declared, not aimed"). Silent no-op with nothing operable, same
## posture every other queuing entry point here already has.
func queue_untargeted_action(action_id: StringName) -> void:
	if input_locked or selection == null or selection.selected_unit == null:
		return
	var shooter: Unit = selection.selected_unit
	var weapon: Part = ActionCatalog.provider_for(shooter, action_id)
	if weapon == null:
		return
	var action: CombatAction = ActionCatalog.build_untargeted_action(action_id, shooter, weapon.id)
	if action != null:
		selection.current_queue().enqueue(action, selection.state)


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


## taskblock-18 D2 (taskblock-27 Pass B: dartboard added): "clicking SHOOT
## on an enemy the unit can't see but could from a legal step-out cell
## builds the triple automatically." A direct shot (the origin is NOT
## covered from this target — D1's own trigger condition) enters ordinary
## aim mode, unchanged; a target only reachable via a step out enters
## step-out-CELL-choice mode instead (picking which candidate cell to
## step out to) — confirming that choice then hands off into this SAME
## ordinary aim mode from the stepped-out position (`_confirm_step_out`),
## rather than auto-resolving a center-mass shot. Falls back to plain aim
## mode when neither applies (no operable weapon, or no legal step out
## exists) — confirm_shot()'s own existing "nothing operable" no-op is
## what actually catches that case, same as it always has.
func _enter_aim_or_step_out_mode(target: Unit) -> void:
	# BR27.06: must read the PREVIEWED shooter, not the raw selected one —
	# same reasoning as BR27.05's own ActionBar fix. docs/09's "queuing
	# mutates nothing" means selected_unit.cell stays at wherever the
	# shooter started THIS turn until the queue actually resolves; a
	# player who moves toward/into cover and then arms a shot had that
	# move still only queued, so evaluating cover from the stale
	# turn-start cell silently fell through to ordinary aim mode instead
	# of the step-out the shooter's real, about-to-be-true position
	# warrants. `previewed_unit()` is the same source `reachable_cells()`
	# already reads for the identical reason.
	var shooter: Unit = selection.previewed_unit()
	if shooter == null:
		_enter_aim_mode(AimTarget.for_unit(target))
		return
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
	_enter_aim_mode(AimTarget.for_unit(target))


## tb32 Pass C: the `PartPicker` counterpart to `_click_unit` — a click
## that resolved to a non-unit Part (wall/cover/downed object/field
## item). No selection concept for a Part (only a Unit can ever be
## "selected") and no step-out consideration (step-out is about breaking
## LOS from a live threat; there's no LOS-avoidance concept against inert
## cover) — armed, with a shooter already selected, goes straight into
## ordinary aim mode.
func _click_part(part: Part, cell: Vector2i) -> void:
	if armed_action != null and selection.selected_unit != null:
		_enter_aim_mode(AimTarget.for_part(part, cell))
	_refresh_overlay()


func _enter_aim_mode(target: AimTarget) -> void:
	aiming_at = target
	layer_index = 0
	reticle_offset = Vector2.ZERO
	aim_hovered_part = null
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
	# tb32 Pass C: the sphere to frame on is computed HERE, not inside
	# CameraRig — a Unit target reads `UnitGeometry.bounding_sphere()`
	# same as always; a Part target reads `bounding_sphere_for_part()`,
	# keeping CameraRig itself completely decoupled from which kind of
	# thing it's framing.
	var target_sphere: Dictionary = (
		UnitGeometry.bounding_sphere(target.unit)
		if target.unit != null
		else UnitGeometry.bounding_sphere_for_part(target.part, target.cell)
	)
	# tb34 Pass D: sniper framing beyond CameraOrbitState.SNIPER_FRAME_
	# DISTANCE cells — Chebyshev, the same distance convention every
	# range/threshold check elsewhere in this codebase already uses.
	var distance_cells: int = Grid.distance_chebyshev(_framing_shooter().cell, target.cell)
	camera_rig.ease_to_framing(
		UnitGeometry.bounding_sphere(_framing_shooter()), target_sphere, distance_cells
	)
	aim_changed.emit()
	_dump_aim_fps()


## tb35 Pass A1 (BR26.02): `Engine.get_frames_per_second()`, 200ms after
## THIS specific transition into aim mode — past the entry transient, into
## the steady-state sweep — logged into the same combat_log every other
## per-turn FPS dump uses (`FpsDumpSink`), so "aim is slow" is a
## greppable number in `out/combat.log`, not a felt impression. Fired
## once per `_enter_aim_mode()` call, never per reticle nudge
## (`aim_changed` alone fires on those too) — this is a separate function
## specifically so re-entering aim on a new target restarts the window.
func _dump_aim_fps() -> void:
	await get_tree().create_timer(0.2).timeout
	if not is_inside_tree() or selection == null:
		return
	var fps: float = Engine.get_frames_per_second()
	selection.state.combat_log.emit(
		LogEvent.new(
			selection.state.round_number,
			Enums.Phase.RESOLUTION,
			selection.selected_unit.id if selection.selected_unit != null else -1,
			&"fps_dump",
			{"context": "aim", "fps": fps},
			"Aim FPS (200ms after entering aim): %.1f" % fps
		)
	)


## taskblock-18 D2/D4: enters step-out-CELL-choice mode — safest candidate
## selected by default, mouse-wheel cycles the rest (cycle_step_out_cell).
## No camera framing/dartboard of its own yet: this phase is only for
## picking WHICH cell to step out to, before any move is queued — the
## real aim/dartboard step happens after confirming (`_confirm_step_out`),
## once the free outbound leg is actually queued (taskblock-27 Pass B).
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
	var target: AimTarget = aim["target"]
	var plane: Array[Region] = aim["plane"]
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var hit: Variant = AimPlaneGeometry.aim_point_from_ray(
		shooter.cell, target.cell, ray_origin, ray_dir
	)
	if hit == null:
		return
	var center: Vector2 = (
		ShotPlane.center_of(plane, target.unit)
		if target.unit != null
		else ShotPlane.center_of_part(plane, target.part, target.cell)
	)
	reticle_offset = (hit as Vector2) - center
	aim_changed.emit()
	# tb34 Pass C: hover reads, never re-aims -- called AFTER reticle_offset
	# is already set and its own aim_changed already emitted, from the same
	# screen position, but a fully independent function: update_aim_hover()
	# never writes reticle_offset or anything `resolves` reads, and is
	# itself directly callable/testable with no reticle side effect at all.
	update_aim_hover(screen_pos)


## tb34 Pass C: "mousing over a part while aiming should say what that part
## is" — maps the cursor to an aim-plane point (`AimPlaneGeometry.
## aim_point_from_ray`, the same conversion `aim_reticle_at_screen` uses)
## and finds the containing Region (`ShotPlane.region_at`, the same rect-
## containment `resolves` itself is built from — reused, never a second,
## re-derived hit test). Writes only `aim_hovered_part`: never
## `reticle_offset`, never anything `resolves` reads — "hovering reads, it
## never re-aims," the same discipline the scroll/READING split already
## enforces, made structural rather than just documented by living in its
## own function with no other side effect.
func update_aim_hover(screen_pos: Vector2) -> void:
	aim_hovered_part = null
	if input_locked or aiming_at == null or camera == null:
		return
	var aim: Dictionary = aim_state()
	if aim.is_empty():
		return
	var shooter: Unit = aim["shooter"]
	var target: AimTarget = aim["target"]
	var plane: Array[Region] = aim["plane"]
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var hit: Variant = AimPlaneGeometry.aim_point_from_ray(
		shooter.cell, target.cell, ray_origin, ray_dir
	)
	if hit == null:
		return
	var hovered_region: Region = ShotPlane.region_at(plane, hit as Vector2)
	aim_hovered_part = hovered_region.part if hovered_region != null else null
	aim_changed.emit()


## docs/10 taskblock03 D5: "aim from where the unit WILL BE." Everything the
## aim UI needs, read from ONE speculative preview clone — the same one
## TACTICS already previews every queued action against
## (SelectionController.previewed_unit()'s own source), never the
## authoritative `selection.state` — so a queued move behind cover changes
## what the reticle resolves to before the human commits anything.
## `{"shooter": Unit, "target": AimTarget, "plane": Array[Region]}`, or an
## empty Dictionary while not aiming. All three MUST come from the same
## preview: calling `.preview()` a second time to fetch shooter/target
## separately would hand back an unrelated clone whose Parts never
## object-match the first clone's Regions, silently breaking anything that
## matches Region.part/body identity (ShotPlane.center_of, AimController.
## resolve). That clone already carries every unit (allies included), just
## with only the shooter's own queued actions replayed onto it — nothing
## extra is needed for "other units who have also queued moves" until this
## architecture ever lets more than one unit queue at once.
##
## tb32 Pass C: a Part target (wall/cover/downed object/field item) never
## needs re-resolving against the preview the way a Unit target does —
## queuing mutates nothing (docs/09), so a blocker/field-item Part is
## exactly as true in the preview as in `selection.state`; only a Unit
## target gets the `preview.find_unit()` re-lookup, same reason the
## shooter itself always has.
func aim_state() -> Dictionary:
	if aiming_at == null or selection.selected_unit == null:
		return {}
	var preview: CombatState = selection.current_queue().preview(selection.state)
	var shooter: Unit = preview.find_unit(selection.selected_unit.id)
	if shooter == null:
		return {}
	var target: AimTarget = aiming_at
	if aiming_at.unit != null:
		var preview_target: Unit = preview.find_unit(aiming_at.unit.id)
		if preview_target == null:
			return {}
		target = AimTarget.for_unit(preview_target)
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
	# taskblock-37 Pass A: no specific weapon is in view for the aim
	# PREVIEW itself (armed but not yet resolved) — ground level of the
	# shooter's own cell, same no-muzzle convention `LineOfFire.first_hit`
	# uses, real elevation still reaches `BodyProjector`'s visibility test.
	var origin_height: float = preview.grid.get_level(shooter.cell) * UnitGeometry.LEVEL_HEIGHT
	var elevation: Dictionary = ShotPlane.elevation_for(
		origin, origin_height, shooter.cell, target.cell, preview.grid
	)
	var raw: Array[Region] = ShotPlane.build(elevation.origin, elevation.direction, preview)
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
	var target: AimTarget = aim["target"]
	return FaceAction.orientation_toward(shooter.cell, target.cell)


## Queues the firing action `armed_action` actually is, carrying the
## reticle's current aim_offset, using whatever part actually provides it
## (taskblock-08 A1: "the armed action decides what a click means" —
## SHOOT picks the shoot provider, SAW picks the saw provider, never just
## any weapon) — a no-op, silently, if the shooter has nothing operable
## for it right now.
## taskblock-24 Pass A: `ActionCatalog.build_firing_action` — never a
## hardcoded `AttackAction` regardless of `armed_action.id` (arming and
## clicking BURST used to queue a plain single shot; the button never
## actually reached `BurstAction` at all).
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
			var action: CombatAction = ActionCatalog.build_firing_action(
				armed_action.id, shooter, weapon.id, aiming_at.cell, reticle_offset
			)
			if action != null and selection.current_queue().enqueue(action, selection.state):
				# taskblock-27 Pass B: a real shot just queued from a
				# step-out's own firing cell — the free return leg (the
				# triple's own third leg) only ever gets appended here, on
				# an ACTUAL fired shot, never on a bare cancel.
				if _returning_from_step_out:
					_append_step_out_return_leg()
	_returning_from_step_out = false
	cancel_aim()


## taskblock-27 Pass B: the step-out triple's own third leg — pathed from
## wherever the queue's own preview says the shooter now stands (the
## firing cell, unless the firing action itself somehow also moved it)
## back to `_step_out_origin_cell`, against the preview's OWN grid
## (`StepOutPlanner.build_triple`'s exact same "origin reads occupied on
## the raw grid until the out-leg's preview vacates it" reasoning) —
## free, the same `MoveAction` flag the outbound leg used.
func _append_step_out_return_leg() -> void:
	var shooter: Unit = selection.selected_unit
	var preview: CombatState = selection.current_queue().preview(selection.state)
	var previewed_shooter: Unit = preview.find_unit(shooter.id)
	if previewed_shooter == null:
		return
	var back_pf := Pathfinder.new(preview.grid, preview.terrain_costs, shooter.shell.can_climb())
	var back_path: Array[Vector2i] = back_pf.astar(previewed_shooter.cell, _step_out_origin_cell)
	if back_path.size() < 2:
		return
	selection.current_queue().enqueue(MoveAction.new(shooter, back_path, true), selection.state)


## taskblock-27 Pass B: commits to whichever candidate cell is CURRENTLY
## selected (default: safest; the player may have cycled with the wheel
## first) — but only the free OUTBOUND leg, queued the same way
## StepOutPlanner.build_triple's own out-leg is (MoveAction's own `free`
## flag, tb27 Pass B2 — no MP/AP either way now). Rather than
## auto-resolving a center-mass shot immediately (the old behavior), this
## then hands off into ORDINARY aim mode from the stepped-out position —
## `_framing_shooter()`/`aim_state()` both already read
## `selection.previewed_unit()`, so the camera and dartboard naturally
## follow the just-queued move with no extra plumbing. `confirm_shot()`'s
## own ordinary firing branch appends the free return leg once a real shot
## is actually queued (`_append_step_out_return_leg`); `cancel_aim()`
## unwinds the free out-leg if the player backs out before firing. A
## silent no-op if the shooter has nothing operable or the outbound leg
## itself doesn't queue legally, same posture confirm_shot() itself
## already has.
func _confirm_step_out() -> void:
	# Pass D audit (BR27.05/BR27.06 parent pattern): the outbound path must
	# be pathed from the PREVIEWED cell, not `shooter.cell` directly — a
	# prior queued (not yet resolved) move leaves `shooter.cell` stale, and
	# `MoveAction.is_legal()` requires `path[0] == actual.cell` against
	# wherever the unit ACTUALLY previews to by the time the queue
	# validates it. Pathing from the stale cell silently failed `enqueue()`
	# and fell through to `cancel_step_out()` — the same "no visible
	# step-out" symptom BR27.06 chased one function over, in a spot that
	# function's own fix never reached. `_append_step_out_return_leg()`
	# already gets this right; matched here.
	var shooter: Unit = selection.selected_unit
	var weapon: Part = (
		ActionCatalog.provider_for(shooter, armed_action.id) if armed_action != null else null
	)
	var target: Unit = stepping_out_at
	if weapon == null or _step_out_candidates.is_empty():
		cancel_step_out()
		return
	var firing_cell: Vector2i = _step_out_candidates[_step_out_cell_index]
	var preview: CombatState = selection.current_queue().preview(selection.state)
	var previewed_shooter: Unit = preview.find_unit(shooter.id)
	if previewed_shooter == null:
		cancel_step_out()
		return
	var pf := Pathfinder.new(preview.grid, preview.terrain_costs, shooter.shell.can_climb())
	var out_path: Array[Vector2i] = pf.astar(previewed_shooter.cell, firing_cell)
	if (
		out_path.size() < 2
		or not selection.current_queue().enqueue(
			MoveAction.new(shooter, out_path, true), selection.state
		)
	):
		cancel_step_out()
		return
	_step_out_origin_cell = previewed_shooter.cell
	_returning_from_step_out = true
	stepping_out_at = null
	_step_out_candidates = []
	_step_out_cell_index = 0
	_enter_aim_mode(AimTarget.for_unit(target))


func cancel_aim() -> void:
	# taskblock-27 Pass B: backing out of aim mid-step-out (before a real
	# shot ever queued, i.e. before confirm_shot's own firing branch
	# reached `_append_step_out_return_leg` and cleared this) must undo
	# the free outbound leg too — otherwise the unit is left standing at
	# the firing cell with no shot fired and no return leg ever coming.
	if _returning_from_step_out:
		selection.current_queue().actions.pop_back()
		_returning_from_step_out = false
	aiming_at = null
	armed_action = null
	layer_index = 0
	reticle_offset = Vector2.ZERO
	aim_hovered_part = null
	camera_rig.stop_aiming()
	aim_changed.emit()
	_refresh_overlay()


## Queues ending the selected unit's turn and actually resolves it —
## RESOLUTION, not TACTICS, is what's allowed to mutate the real state.
## Locks input for the caller to hold through however long it plays the
## resulting events back (docs/10 Phase 12.4); call unlock_input() once
## that's done.
func end_turn() -> void:
	_queue_final_action_and_resolve(selection.queue_end_turn)


## taskblock-19 Pass F: "available to AI and player." Same shape as
## end_turn() — a no-op if holding isn't legal (HoldAction.is_legal()
## decides that, never duplicated here).
func hold() -> void:
	_queue_final_action_and_resolve(selection.queue_hold)


## Shared by end_turn()/hold(): queue the one action that ends this
## unit's say in TACTICS, then resolve the whole queue for real —
## MoveHooks wires both Overwatch's real trigger and Suppression's
## attack-of-opportunity onto resolve_until's mid_move_hook seam (kept in
## a local; see MoveHooks' own doc comment on why the Callable can't
## stand alone).
func _queue_final_action_and_resolve(queue_final_action: Callable) -> void:
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
	queue_final_action.call()
	var move_hooks := MoveHooks.new(selection.selected_unit.cell)
	selection.state.resolve_until(selection.current_queue(), move_hooks.check)
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
	var move_hooks := MoveHooks.new(selection.selected_unit.cell)
	selection.state.resolve_until(prefix, move_hooks.check)
	selection.state.combat_log.remove_sink(sink)

	# BR27.08 (supervisor follow-up): "then start queuing again" used to
	# mean reset_turn() — erase the WHOLE queue, prefix and suffix alike.
	# Now only the resolved prefix is dropped; whatever was still queued
	# past the marker survives, replayed against the just-updated real
	# state. Reset Turn's own G3 default (returns to the resolve point,
	# not turn start) is untouched — Reset Turn still erases the queue
	# outright, kept-suffix included, same as it always has.
	selection.keep_queue_suffix(marker_index + 1)
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
