class_name PlacementGhostModule
extends ViewModule

## **What the next click will place, drawn before you make it.** taskblock-58 Pass E.
##
## The taskblock: *"Place Terrain... attaches to the struck face, with a **ghost** so the result is
## never a surprise"*, and *"the pass's real acceptance is that **what appears is what the ghost
## showed** — a placement that surprises is the defect this exists to prevent."*
##
## ## The acceptance is structural, not maintained
##
## This module does not work out where a placement will land. It asks `EditorModule.
## placement_target`, which is the **same call** `_place_with` makes when the click arrives — so the
## ghost and the placement cannot disagree, because there is one answer and they both read it.
## `test_parts_list.gd` asserts the transforms match, which checks the wiring is real rather than
## checking that two formulas agree.
##
## The boxes are `UnitGeometry.assembly_placements` too — the same call `BoardView` draws a real
## placement from. **The ghost is the thing, in a different colour**, rather than a stand-in shape
## that would have its own reasons to be wrong.
##
## ## It draws only while a place verb is armed
##
## `select`, `scale` and `delete` have nothing to preview, and a ghost that lingered under those
## would be showing a placement that is not going to happen. The gate is `EditorTools.
## is_place_tool`, so an eighth placing verb previews with no edit here.

## The ghost's colour and how much of it you can see through. Flagged, not designed — bright enough
## to read against the board's own palette, transparent enough to see what it is landing on, which
## is the whole reason it is a ghost rather than a placement.
const GHOST_COLOR := Color(0.45, 0.85, 1.0, 0.4)

## The meshes currently drawn. Public so a test reads back what was previewed rather than
## re-deriving it from a transform it computed itself.
var meshes: Array[MeshInstance3D] = []

## Where the ghost last drew, as `EditorModule.placement_target`'s own dict, or empty when nothing
## is previewed. **The number a test compares against the real placement.**
var target: Dictionary = {}

var _root: Node3D = null


func module_id() -> StringName:
	return &"placement_ghost"


func is_showing() -> bool:
	return not meshes.is_empty()


func _mount() -> void:
	_root = Node3D.new()
	var battle: BattleScene = context.battle if context != null else null
	if battle != null:
		battle.add_child(_root)
	else:
		add_child(_root)


func _unmount() -> void:
	clear()
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null


## Connects to the pick the board picker reports, which is where the struck face comes from.
func link() -> void:
	var picking: BoardInspectModule = _board_inspect()
	if picking != null and not picking.hovered_pick.is_connected(_on_hovered_pick):
		picking.hovered_pick.connect(_on_hovered_pick)


## Draws the ghost for `pick`, or clears it when there is nothing to preview.
##
## **An empty pick clears rather than leaving the last one up.** A ghost that stayed behind after
## the cursor left the board would be describing a click that would land somewhere else entirely,
## which is the surprise this exists to prevent rather than a cosmetic lag.
func _on_hovered_pick(pick: Dictionary) -> void:
	var editor: EditorModule = _editor()
	if editor == null or pick.is_empty() or not EditorTools.is_place_tool(editor.active_tool):
		clear()
		return
	var cell: Variant = pick.get("cell")
	if cell == null:
		clear()
		return
	# **The editor's own struck face, set for the duration of this preview**, so `placement_target`
	# takes the identical branch it takes on a click. Restored afterwards rather than left set: a
	# hover must not change what a later click without a face would do.
	var was: Variant = editor.struck_normal
	editor.struck_normal = pick.get("normal")
	target = editor.placement_target(cell as Vector2i)
	editor.struck_normal = was
	_draw(editor, target)


func clear() -> void:
	for mesh: MeshInstance3D in meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	meshes = []
	target = {}


## The transform a ghosted box would be drawn at, in world space. What the acceptance compares.
func ghost_transforms() -> Array[Transform3D]:
	var found: Array[Transform3D] = []
	for mesh: MeshInstance3D in meshes:
		if is_instance_valid(mesh):
			found.append(mesh.global_transform if mesh.is_inside_tree() else mesh.transform)
	return found


func _draw(editor: EditorModule, at: Dictionary) -> void:
	clear()
	target = at
	var part: Part = DataLibrary.get_part(editor.selected_part)
	if part == null or _root == null:
		return
	var placements: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		part, at["cell"], editor.facing(), null, at["height"]
	)
	for placement: BoxPlacement in placements:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = placement.box.size
		mesh.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = GHOST_COLOR
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material_override = material
		_root.add_child(mesh)
		mesh.transform = placement.transform.translated_local(placement.box.center)
		meshes.append(mesh)


func _board_inspect() -> BoardInspectModule:
	return context.module(&"board_inspect") as BoardInspectModule if context != null else null


func _editor() -> EditorModule:
	return context.module(&"editor") as EditorModule if context != null else null
