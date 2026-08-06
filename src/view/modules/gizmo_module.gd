class_name GizmoModule
extends ViewModule

## taskblock-57 Pass H: **the manipulation gizmo — handles you can see, and a number you can
## read.**
##
## The taskblock: *"A 3D CAD-style handle set with a numeric readout, doing two jobs. Placement
## height: click a placed item, drag the up arrow, watch the readout show 0.3. Snap to 0.1.
## Claim volumes: one click selects and gives translate arrows; a second click swaps to resize
## handles."*
##
## ## The scene reads and draws; it decides nothing
##
## Every decision is `Gizmo`'s or `GizmoDrag`'s, in `src/logic`, tested with no scene at all.
## What is here is three meshes, a label, and the two things only a view can supply:
##
## - **the ray** a press means, from the live camera;
## - **`axis_on_screen`** — how many pixels one world unit along an axis covers right now, which is
## `unproject_position(origin + axis) - unproject_position(origin)` and cannot be answered
## without a projection.
##
## Both are handed straight to logic. There is no arithmetic in this file.
##
## ## It is armed by a tool, and that is what keeps it from being a second selection system
##
## *"Do not let this become a second selection system. A gizmo is a tool over the existing
## selection, not its own notion of what is selected."*
##
## So the gizmo does **not** pick its own subject off a raw click. `EditorModule.apply_tool_at`
## — the one router every board click in the editor takes — hands it a cell when
## the `gizmo` tool is active, and the gizmo focuses whatever is there. A click with any other
## tool active authors as it always did and the gizmo never hears about it.
##
## What the gizmo *does* take before the router is a press **on one of its own handles**,
## because a handle is drawn over the board and a grab must not also author on the cell
## underneath. That is the only event it consumes, and the editor mode declares this module
## before `board_inspect` so the offer reaches it first.
##
## ## The readout
##
## One label, showing the value the current drag is producing. It anchors along the bottom of
## the safe rect, above the bar — **a starting position, not a decision**, and the same band
## `AimReadoutModule` uses in the mode that has one. No mode has both.

## Where the readout sits and how big it is, before UI scale. Starting positions.
const READOUT_SIZE := Vector2(220, 28)

## Arrow colours by axis, so an author can tell which one they are dragging. Red/green/blue on
## X/Y/Z is the CAD convention this is named after, and matching it is worth more than a
## palette.
const AXIS_COLORS: Array[Color] = [
	Color("#D53A3A"),
	Color("#7BE02A"),
	Color("#3A7BD5"),
]

## The tools that arm the gizmo. Rows in `EditorTools.TOOLS` like every other verb, so the bar
## grows their buttons with no edit there.
##
## taskblock-58 Pass D: **two of them, one per handle set.** The single `gizmo` verb showed
## translate handles and swapped to resize on a second click of the same subject; arming *Select*
## or *Scale* says which set you want up front, because those are different intentions and a mode
## reached by re-clicking is a mode left by accident. `TOOL` remains the translate one, so a caller
## that just wants "the gizmo" still has a name for it.
const TOOL: StringName = &"select"
const TOOL_SCALE: StringName = &"scale"

## The tool over the selection. **Public and constructed here**, because it is the module's
## whole state and a test drives it directly rather than through meshes.
var gizmo := Gizmo.new()

## The drawn handles, one `MeshInstance3D` per entry of the current set, in the same order.
## Public so a test reads back what was produced instead of asserting against a render.
var meshes: Array[MeshInstance3D] = []
var readout: Label = null

## The handle set the meshes were built from, so picking and drawing cannot disagree about
## which handles exist.
var _handles: Array[Dictionary] = []


func module_id() -> StringName:
	return &"gizmo"


func _mount() -> void:
	readout = Label.new()
	readout.custom_minimum_size = UiLayout.scaled_size(READOUT_SIZE)
	readout.add_theme_color_override("font_color", HulkTheme.HIGHLIGHT)
	# A readout is text, never a target — it must not eat a press meant for a handle behind it.
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout.visible = false
	var root: Control = context.ui_root if context != null else null
	if root == null:
		# The stand-alone case taskblock-56 Pass C's acceptance requires: the label is real and the
		# gizmo still works; it simply has nowhere to be drawn.
		add_child(readout)
		return
	root.add_child(readout)
	var safe: Rect2 = UiLayout.safe_rect(root.size)
	readout.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	readout.grow_horizontal = Control.GROW_DIRECTION_BOTH
	readout.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var size: Vector2 = UiLayout.scaled_size(READOUT_SIZE)
	readout.position = Vector2(safe.get_center().x - size.x * 0.5, safe.end.y - size.y * 3.0)


## A click the editor's tool router resolved, when the `gizmo` tool is what is active.
##
## **The gizmo is told; it does not look.** Called from `EditorModule.apply_tool_at`, which is
## the one path every board click in the editor takes — so there is no second picking path and
## nothing here has an opinion about what a click means with any other tool active.
##
## Returns true if the click meant something to the gizmo, which is either focusing a subject
## or clearing one. *"A click elsewhere deselects"*, and deselecting is a real response.
func focus_at(cell: Vector2i) -> bool:
	var index: int = claim_index_at(cell)
	if index >= 0:
		gizmo.focus_claim(index)
	elif not _placements_at(cell).is_empty():
		gizmo.focus_placement(cell)
	else:
		gizmo.clear()
	reassert_ghost()
	redraw()
	return true


## taskblock-59 Pass B: **the focused placement is drawn see-through, so the handles inside it
## read.**
##
## *"The select gizmo sits inside items. Acceptable, but then it must be clickable and draggable
## there, and the selected part should render as a ghost."* The handles were always clickable —
## `Gizmo.hit` is a ray/box test with no occlusion in it, and this module takes the input walk ahead
## of `board_inspect` — so the defect was purely that a gizmo buried in a crate is a gizmo you
## cannot aim at.
##
## **Only a placement, never a claim.** A claim's volume is already drawn translucent by
## `ClaimVolumeModule`, so there is nothing to see through, and ghosting the cell under it would
## make a floor vanish for a reason the author has no way to connect to what they clicked.
## **Public because the board rebuild destroys it.** `EditorModule.refresh` runs after every edit
## and `BoardView.build` frees every mesh, so the ghost is re-stated against the new ones — the
## gizmo's focus is the source of truth and this is it re-asserting itself, not a second store of
## what is selected.
func reassert_ghost() -> void:
	var battle: BattleScene = context.battle if context != null else null
	if battle == null or battle.board_view == null:
		return
	var focused: bool = gizmo.subject == Gizmo.SUBJECT_PLACEMENT
	battle.board_view.ghosting.ghost(gizmo.cell if focused else null)


## The index of the claim whose volume covers `cell`, or -1.
##
## **Claims first, placements second**, because a claim is a volume drawn *over* the board and
## the thing you can see at that point; a placement under it is still reachable by clearing the
## claim's focus or by clicking a cell the claim does not cover.
##
## The topmost match wins when volumes overlap — claims *"overlap freely"* by design, so the
## last one authored being the one you grab matches what is drawn on top.
func claim_index_at(cell: Vector2i) -> int:
	var editor: EditorModule = _editor()
	if editor == null:
		return -1
	var point := Vector3(
		float(cell.x) * UnitGeometry.CELL_SIZE, 0.0, float(cell.y) * UnitGeometry.CELL_SIZE
	)
	var found: int = -1
	for index: int in range(editor.controller.claims.size()):
		var claim: SectionClaim = editor.controller.claims[index]
		if claim == null or claim.box == null:
			continue
		var volume: AABB = ClaimVolumeModule.world_aabb(claim, Vector2i.ZERO)
		# Compared on the ground plane only: a click carries a cell, not a height, so "is this cell
		# under the claim" is the question that can actually be asked of it.
		if point.x >= volume.position.x and point.x <= volume.end.x:
			if point.z >= volume.position.z and point.z <= volume.end.z:
				found = index
	return found


## **The only event this module consumes, and only when it grabbed something.** See the class
## note: a press on a handle must not also reach the board picker and author on the cell
## underneath.
func handle_input(event: InputEvent) -> bool:
	if not gizmo.has_subject():
		return false
	if event is InputEventMouseButton:
		return _on_button(event as InputEventMouseButton)
	if event is InputEventMouseMotion and gizmo.is_dragging():
		_drag_to((event as InputEventMouseMotion).position)
		return true
	return false


func _on_button(button: InputEventMouseButton) -> bool:
	if button.button_index != MOUSE_BUTTON_LEFT:
		return false
	if not button.pressed:
		if not gizmo.is_dragging():
			return false
		gizmo.cancel_drag()
		readout.visible = false
		return true
	var camera: Camera3D = _camera()
	if camera == null:
		return false
	var struck: Dictionary = Gizmo.hit(
		_handles,
		camera.project_ray_origin(button.position),
		camera.project_ray_normal(button.position)
	)
	if struck.is_empty():
		return false
	gizmo.begin_drag(
		struck["axis"] as int,
		struck["sign"] as float,
		_value_of(struck["axis"] as int),
		button.position
	)
	_show_readout(gizmo.start_value())
	return true


## Applies the drag at `screen_pos` to whatever is focused.
##
## **The value goes through `EditorController`, never into the model directly**, so the gizmo's
## edits are undoable exactly as an authored placement is — which is the whole reason the
## editor's verbs live one layer down.
func _drag_to(screen_pos: Vector2) -> void:
	var editor: EditorModule = _editor()
	if editor == null:
		return
	var axis: int = gizmo.dragging_axis
	var on_screen: Vector2 = axis_on_screen(axis)
	if gizmo.subject == Gizmo.SUBJECT_PLACEMENT:
		var height: float = gizmo.value_at(screen_pos, on_screen)
		# Only the up arrow means anything on a placement: a placement's cell is where it is, and
		# dragging it sideways would be a move the tool does not offer.
		if axis == Gizmo.AXIS_Y and editor.controller.set_height(gizmo.cell, height):
			_show_readout(height)
		redraw()
		return
	_drag_claim(editor, screen_pos, on_screen)


## The claim half: translate moves the whole box, resize moves one face.
##
## **A refused resize leaves the claim exactly as it was** — `Gizmo.resized_box` returns null
## for a drag that would collapse or invert the volume, and nothing is written. The taskblock
## asks for refusal rather than a silent clamp, and this is what that means at the call site:
## the face stops following the pointer and the readout stops moving, which is unambiguous.
func _drag_claim(editor: EditorModule, screen_pos: Vector2, on_screen: Vector2) -> void:
	var claim: SectionClaim = _claim()
	if claim == null or claim.box == null:
		return
	var axis: int = gizmo.dragging_axis
	var amount: float = gizmo.amount_at(screen_pos, on_screen)
	var box: Box = null
	if gizmo.handles == Gizmo.Handles.TRANSLATE:
		box = Gizmo.translated_box(claim.box, axis, amount)
	else:
		box = Gizmo.resized_box(claim.box, axis, gizmo.dragging_sign, amount)
	if box == null:
		return
	if not editor.controller.resize_claim(gizmo.claim_index, box):
		return
	_show_readout(box.size[axis] if gizmo.handles == Gizmo.Handles.RESIZE else box.center[axis])
	editor.refresh()
	redraw()


## **How many pixels one world unit along `axis` covers, right now.** The one thing `GizmoDrag`
## cannot work out for itself, and the reason it takes a vector rather than a scale factor.
##
## Read off the real camera by projecting two points — never re-derived from a field of view
## and a distance, which is the second copy of a projection that agrees with itself and with
## nothing on screen.
func axis_on_screen(axis: int) -> Vector2:
	var camera: Camera3D = _camera()
	if camera == null:
		return Vector2.ZERO
	var origin: Vector3 = gizmo_origin()
	return (
		camera.unproject_position(origin + Gizmo.axis_vector(axis))
		- camera.unproject_position(origin)
	)


## Where the handles are drawn, in world space: a claim's own centre, or the top of the
## placement's cell.
func gizmo_origin() -> Vector3:
	var editor: EditorModule = _editor()
	if editor == null:
		return Vector3.ZERO
	if gizmo.subject == Gizmo.SUBJECT_CLAIM:
		var claim: SectionClaim = _claim()
		if claim != null and claim.box != null:
			return ClaimVolumeModule.world_aabb(claim, Vector2i.ZERO).get_center()
		return Vector3.ZERO
	return Vector3(
		float(gizmo.cell.x) * UnitGeometry.CELL_SIZE,
		_value_of(Gizmo.AXIS_Y),
		float(gizmo.cell.y) * UnitGeometry.CELL_SIZE
	)


## Rebuilds the drawn handles from whatever is focused. **Rebuilt, never patched**: what is on
## screen is a pure function of the gizmo's state, so there is no add/remove bookkeeping to
## drift.
func redraw() -> void:
	for mesh: MeshInstance3D in meshes:
		mesh.queue_free()
	meshes.clear()
	_handles = []
	if not gizmo.has_subject():
		readout.visible = false
		return
	_handles = _current_handles()
	for handle: Dictionary in _handles:
		var placement: BoxPlacement = handle["placement"]
		var instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = placement.box.size
		instance.mesh = mesh
		instance.position = placement.box.center
		instance.material_override = WorldPalette.translucent_material(
			AXIS_COLORS[handle["axis"] as int]
		)
		add_child(instance)
		meshes.append(instance)


func _current_handles() -> Array[Dictionary]:
	if gizmo.handles == Gizmo.Handles.RESIZE:
		var claim: SectionClaim = _claim()
		if claim == null or claim.box == null:
			return [] as Array[Dictionary]
		return Gizmo.resize_handles(ClaimVolumeModule.world_aabb(claim, Vector2i.ZERO))
	return Gizmo.translate_handles(gizmo_origin())


## What a drag on `axis` starts from: a placement's height, a translating claim's centre on
## that axis, a resizing claim's extent on it.
func _value_of(axis: int) -> float:
	var editor: EditorModule = _editor()
	if editor == null:
		return 0.0
	if gizmo.subject == Gizmo.SUBJECT_CLAIM:
		var claim: SectionClaim = _claim()
		if claim == null or claim.box == null:
			return 0.0
		return (
			claim.box.size[axis]
			if gizmo.handles == Gizmo.Handles.RESIZE
			else claim.box.center[axis]
		)
	var here: Array[MapPlacement] = _placements_at(gizmo.cell)
	return here[here.size() - 1].height if not here.is_empty() else 0.0


## **The numeric readout the taskblock names.** One decimal, because one decimal is the whole
## grid: a readout showing 0.30000000000000004 would say the snap had failed when it had not.
func _show_readout(value: float) -> void:
	if readout == null:
		return
	readout.text = "%.1f" % value
	readout.visible = true


func _placements_at(cell: Vector2i) -> Array[MapPlacement]:
	var editor: EditorModule = _editor()
	return editor.controller.placements_at(cell) if editor != null else [] as Array[MapPlacement]


func _claim() -> SectionClaim:
	var editor: EditorModule = _editor()
	if editor == null or gizmo.claim_index < 0:
		return null
	if gizmo.claim_index >= editor.controller.claims.size():
		return null
	return editor.controller.claims[gizmo.claim_index]


func _editor() -> EditorModule:
	return context.module(&"editor") as EditorModule if context != null else null


func _camera() -> Camera3D:
	if context == null or context.battle == null or context.battle.camera_rig == null:
		return null
	return context.battle.camera_rig.camera()
