class_name Gizmo
extends RefCounted

## taskblock-57 Pass H: **a CAD-style handle set, as a tool over something already chosen.**
##
## The taskblock, twice, in its own words:
##
## - *"Do not let this become a second selection system. A gizmo is a tool over the existing
## selection, not its own notion of what is selected. This project has produced two visibility
## systems, two aiming paths and two overlay hierarchies; that is the shape this takes if it
## drifts."*
## - *"Keep the drag math in logic... The scene reads and draws; it decides nothing."*
##
## So this class holds **what the gizmo is pointed at, which handle set is showing, and where
## the boxes are** — and `GizmoDrag` holds the arithmetic. Neither touches a `Node`.
##
## ## It points at a subject; it does not own one
##
## `focus_*` is told what was clicked by whoever already resolved the click — in the editor
## that is `BoardInspectModule`'s pick, which is the same click that authors a placement.
## **Nothing here writes to any selection**, and the acceptance says so outright: *"the gizmo
## never changes what is selected."* `clear()` is the gizmo forgetting, not a deselect of
## anything else.
##
## `subject` is an open `StringName`, so a third kind of thing to drag is data plus a rule, not
## a new enum value and a new branch in every reader.
##
## ## Two handle sets, one gizmo
##
## *"One click selects and gives translate arrows; a second click swaps to resize handles. Same
## gizmo, two handle sets."* A second click on the **same** claim toggles; a click on a
## different one starts that one over at translate, because arriving at a new subject already
## in resize mode is a state nobody asked for and the first drag would be a surprise.
##
## ## The handles are boxes, which is the whole reason picking is free
##
## *"`PartPicker.hit` and `UnitPicker.hit` are analytic ray-vs-box in `src/logic`, and gizmo
## handles are boxes — the same primitive, not a new one."* `handle_boxes` returns real
## `BoxPlacement`s and `hit` runs `UnitPicker.ray_box_t` over them. No second ray test exists.

## The two handle sets. **An enum, not an open vocabulary** — this is a closed engine state
## (which of two sets is showing), exactly the distinction CLAUDE.md's standing rule draws.
enum Handles { TRANSLATE, RESIZE }

## Nothing is focused.
const SUBJECT_NONE: StringName = &""
## A placed item on a cell. The only value it has to give is its height, so only the Y arrow
## means anything on one.
const SUBJECT_PLACEMENT: StringName = &"placement"
## A claim volume, by index into the controller's own list.
const SUBJECT_CLAIM: StringName = &"claim"

const AXIS_X := 0
const AXIS_Y := 1
const AXIS_Z := 2

## How far an arrow reaches from the gizmo's origin, in world units. A starting position the
## supervisor's tuning pass owns, not a decision — big enough to grab over a one-unit cell.
const ARM_LENGTH := 0.9
## How thick an arrow's own pickable box is. Deliberately fatter than the arrow is drawn: a
## handle you can see and cannot hit is worse than one that is slightly generous.
const ARM_THICKNESS := 0.22
## The side of a resize handle's cube.
const RESIZE_HANDLE_SIZE := 0.28

## What the gizmo is pointed at, or `SUBJECT_NONE`.
var subject: StringName = SUBJECT_NONE
## The cell, for a `SUBJECT_PLACEMENT`.
var cell: Vector2i = Vector2i.ZERO
## The index into the controller's claims, for a `SUBJECT_CLAIM`.
var claim_index: int = -1
## Which set is showing. Always `TRANSLATE` on a freshly focused subject.
var handles: Handles = Handles.TRANSLATE

## The axis currently being dragged, or -1. `AXIS_X` / `AXIS_Y` / `AXIS_Z`.
var dragging_axis: int = -1
## Which face of a resize box is being dragged: +1 for the positive side, -1 for the negative.
## Meaningless while translating, and left at +1 there.
var dragging_sign: float = 1.0

## Where the pointer was when the handle was grabbed, and what the value was then. **The drag
## is a pure function of these two and the current pointer**, never an accumulation of
## per-frame deltas — see `GizmoDrag.value_after`.
var _drag_start_screen: Vector2 = Vector2.ZERO
var _drag_start_value: float = 0.0


## The unit vector for `axis`. One place, so a caller never spells out a basis vector.
static func axis_vector(axis: int) -> Vector3:
	match axis:
		AXIS_X:
			return Vector3.RIGHT
		AXIS_Y:
			return Vector3.UP
		AXIS_Z:
			return Vector3.BACK
	return Vector3.ZERO


## The translate arrows: three boxes reaching out from `origin` along +X, +Y and +Z.
##
## Each entry is `{"axis": int, "sign": float, "placement": BoxPlacement}` — the same shape the
## resize set produces, so `hit` does not care which set it was handed.
static func translate_handles(origin: Vector3) -> Array[Dictionary]:
	var built: Array[Dictionary] = []
	for axis: int in [AXIS_X, AXIS_Y, AXIS_Z]:
		var along: Vector3 = axis_vector(axis)
		# The arm's own box: long on its axis, thin on the other two, centred half way along.
		var size: Vector3 = Vector3(ARM_THICKNESS, ARM_THICKNESS, ARM_THICKNESS)
		size[axis] = ARM_LENGTH
		var centre: Vector3 = origin + along * (ARM_LENGTH * 0.5)
		var arm: Dictionary = {"axis": axis, "sign": 1.0, "placement": _placement_at(centre, size)}
		built.append(arm)
	return built


## The resize handles: one cube at the centre of each of `volume`'s six faces.
##
## **Six, not three.** A claim is resized by moving one face, and which face is the whole of
## what the author is saying — dragging the top up and dragging the bottom down are different
## edits with the same axis and the same direction.
static func resize_handles(volume: AABB) -> Array[Dictionary]:
	var built: Array[Dictionary] = []
	var centre: Vector3 = volume.get_center()
	var half: Vector3 = volume.size * 0.5
	for axis: int in [AXIS_X, AXIS_Y, AXIS_Z]:
		for sign_of: float in [1.0, -1.0]:
			var face: Vector3 = centre
			face[axis] = centre[axis] + half[axis] * sign_of
			var cube: BoxPlacement = _placement_at(face, Vector3.ONE * RESIZE_HANDLE_SIZE)
			built.append({"axis": axis, "sign": sign_of, "placement": cube})
	return built


## The nearest handle a ray strikes, as `{"axis", "sign", "t"}`, or `{}` for a miss.
##
## **`UnitPicker.ray_box_t`, which is the project's one ray-vs-box test.** The taskblock names
## this reuse explicitly; a second slab test written here is the parallel system it warns
## about, one primitive down.
static func hit(handle_set: Array[Dictionary], from: Vector3, dir: Vector3) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_t: float = INF
	for handle: Dictionary in handle_set:
		var t: Variant = UnitPicker.ray_box_t(handle["placement"] as BoxPlacement, from, dir)
		if t == null or (t as float) >= nearest_t:
			continue
		nearest_t = t as float
		nearest = {"axis": handle["axis"], "sign": handle["sign"], "t": nearest_t}
	return nearest


## `box` moved by `amount` along `axis`. The translate half, and it changes no extent.
static func translated_box(box: Box, axis: int, amount: float) -> Box:
	var centre: Vector3 = box.center
	centre[axis] = GizmoDrag.snap(centre[axis] + amount)
	return Box.new(centre, box.size)


## `box` with the face named by `axis`/`sign` moved by `amount`, or **null if that would not be
## a volume**.
##
## *"Resizing a claim produces a valid volume and an invalid drag is refused rather than
## clamped silently."* So a drag that would collapse or invert the box returns null and the
## caller leaves the claim exactly as it was. **Clamping is the tempting wrong answer**: it
## makes the handle stop following the pointer with no explanation, and the author cannot tell
## a refusal from a laggy drag — where a face that simply does not move is unambiguous.
##
## The floor is one snap step, because that is the smallest extent the grid can express. A
## claim thinner than the precision it is authored at is a claim nobody can reproduce.
##
## ## **The dragged FACE is what gets snapped, and that is a correction**
##
## The first version snapped the extent and the centre independently, which looks equivalent and is
## not: growing a box by an odd number of steps moves its centre by half a step, and snapping that
## half-step centre shifts the box — so **the face nobody dragged moved**. Measured, not reasoned:
## dragging the bottom of a 2.0-tall claim down by 0.5 left its top at 2.05.
##
## Snapping the moving face and deriving the rest keeps the fixed face exactly where it was, which
## is the whole promise of a face handle. The extent then follows from two faces rather than being
## rounded on its own.
static func resized_box(box: Box, axis: int, sign_of: float, amount: float) -> Box:
	var half: float = box.size[axis] * 0.5
	# The face the author is NOT dragging. It must come out of this function untouched.
	var anchored_face: float = box.center[axis] - half * sign_of
	var dragged_face: float = GizmoDrag.snap(box.center[axis] + half * sign_of + amount)
	var extent: float = (dragged_face - anchored_face) * sign_of
	if extent < GizmoDrag.SNAP - 0.0001:
		return null
	var size: Vector3 = box.size
	var centre: Vector3 = box.center
	size[axis] = extent
	centre[axis] = anchored_face + extent * 0.5 * sign_of
	return Box.new(centre, size)


# --- what is focused --------------------------------------------------------------------------


## A placed item was clicked. Always arrives at the translate arrows: a placement's only
## draggable value is its height, and there is no second handle set for one.
func focus_placement(p_cell: Vector2i) -> void:
	subject = SUBJECT_PLACEMENT
	cell = p_cell
	claim_index = -1
	handles = Handles.TRANSLATE
	cancel_drag()


## A claim was clicked. **A second click on the same claim swaps handle sets**; a click on a
## different one starts that one at translate.
func focus_claim(index: int) -> void:
	var same_claim: bool = subject == SUBJECT_CLAIM and claim_index == index
	subject = SUBJECT_CLAIM
	claim_index = index
	cell = Vector2i.ZERO
	if same_claim:
		handles = (Handles.RESIZE if handles == Handles.TRANSLATE else Handles.TRANSLATE)
	else:
		handles = Handles.TRANSLATE
	cancel_drag()


## A click landed on nothing the gizmo can drive. **Forgetting, not deselecting** — this class
## has no opinion about what else is selected and never touches it.
func clear() -> void:
	subject = SUBJECT_NONE
	claim_index = -1
	cell = Vector2i.ZERO
	handles = Handles.TRANSLATE
	cancel_drag()


func has_subject() -> bool:
	return subject != SUBJECT_NONE


# --- the drag ----------------------------------------------------------------------------------


## A handle was grabbed. `start_value` is whatever the drag is going to change — a placement's
## height, or a claim's centre or extent along the axis.
func begin_drag(axis: int, sign_of: float, start_value: float, screen_pos: Vector2) -> void:
	dragging_axis = axis
	dragging_sign = sign_of
	_drag_start_value = start_value
	_drag_start_screen = screen_pos


func is_dragging() -> bool:
	return dragging_axis >= 0


func cancel_drag() -> void:
	dragging_axis = -1
	dragging_sign = 1.0


## The value the pointer currently means, snapped. `axis_on_screen` is the screen-space vector
## one world unit along the dragged axis covers — see `GizmoDrag`, which is where the
## arithmetic is.
##
## Returns the untouched start value when nothing is being dragged, so a caller polling this on
## every mouse motion cannot silently author a change nobody grabbed a handle for.
func value_at(screen_pos: Vector2, axis_on_screen: Vector2) -> float:
	if not is_dragging():
		return _drag_start_value
	return GizmoDrag.value_after(_drag_start_value, screen_pos - _drag_start_screen, axis_on_screen)


## How far the drag has reached along the axis, snapped — the same number `value_at` produces,
## expressed as a delta. What a resize wants, since a face moves by an amount rather than to a
## coordinate.
func amount_at(screen_pos: Vector2, axis_on_screen: Vector2) -> float:
	return value_at(screen_pos, axis_on_screen) - _drag_start_value


## The value the handle was grabbed at. Public so a caller can put the drag back if it is
## cancelled.
func start_value() -> float:
	return _drag_start_value


static func _placement_at(centre: Vector3, size: Vector3) -> BoxPlacement:
	# **Identity transform, and the box carries the position.** `BoxPlacement` is built for a part
	# whose transform is a socket chain; a gizmo handle has no body, so the whole placement is its
	# own box in world space — which is exactly what `ray_box_t` reduces to when the basis is
	# identity.
	return BoxPlacement.new(null, Box.new(centre, size), Transform3D.IDENTITY)


## The axis `normal` points along, or -1 when it points along none of them clearly.
##
## taskblock-59 Pass C: **the Scale tool needs to know which face was grabbed**, because the handle
## perpendicular to that face behaves differently from the ones parallel to it. Shares
## `FacePlacement`'s own epsilon rather than choosing a second one: the normals both receive come
## from the same `UnitPicker.ray_box_hit`, so a disagreement about what counts as "along X" would be
## two answers to one question.
static func axis_of(normal: Vector3) -> int:
	var best: int = -1
	var best_dot: float = FacePlacement.AXIS_EPSILON
	for axis: int in [AXIS_X, AXIS_Y, AXIS_Z]:
		var dot: float = absf(normal[axis])
		if dot > best_dot:
			best_dot = dot
			best = axis
	return best
