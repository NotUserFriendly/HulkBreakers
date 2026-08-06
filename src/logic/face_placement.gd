class_name FacePlacement
extends RefCounted

## **Where a placement lands when you click a face.** taskblock-58 Pass E.
##
## The taskblock: *"Placing attaches to the struck face"*, with *"a ghost of the result before the
## click"*, and its real acceptance is that **what appears is what the ghost showed**.
##
## ## Why that acceptance is structural here rather than tested into existence
##
## A ghost that computes where a placement will go, and a placement that computes where it goes, are
## two answers to one question — the shape this project keeps deleting. So there is **one** answer:
## `target_for` is called by the preview to decide where to draw and by the click to decide where to
## author. They cannot disagree, because there is nothing to disagree with. The test asserting the
## ghost's transform equals the placement's is then a check that the wiring is real, not a check
## that two formulas match.
##
## ## Which face means what
##
## The struck normal points *out* of the surface that was hit, so it points back toward whoever
## clicked — which is exactly the direction the new thing goes.
##
## | struck face | lands |
## |---|---|
## | top (+Y) | **on top of** what was clicked: same cell, at the struck geometry's own top |
## | a side | **beside** it: the neighbouring cell that way, at the struck thing's height |
## | bottom (−Y) | **under** it, at the lowest point of what was clicked |
##
## **A side face uses the cell the normal points into, not the cell the ray happened to cross.**
## Those are the same thing for a wall filling its cell and different for anything narrower, and the
## normal is the honest one: it is the face you were looking at.
##
## ## Faces define connections
##
## This is the small end of that. Once positions are their own (Pass B) and grids are plural, a face
## is the only thing two placements can agree about — a cell reference cannot survive either change.
## `target_for` takes a struck cell and a normal and returns a cell and a height, which is still
## cell-shaped; **the input that matters is already the face**, and the output narrows when the rest
## of the world does.

## How far off an axis a normal can point and still count as that axis. Generous: the normals this
## receives come from `UnitPicker.ray_box_hit`, which reports exact axis normals for an unrotated
## box and a rotated one for a yawed placement, so the only thing in the gap is a genuinely
## diagonal surface — which nothing authors yet.
const _AXIS_EPSILON := 0.5


## `{cell, height}` for a part placed against the face `normal` on whatever was struck at `cell`.
##
## `struck_top` and `struck_bottom` are the world Y extent of the thing that was clicked; the caller
## has them because it just picked it. **Passed in rather than looked up** so this stays a
## `RefCounted` with no board in it, and so a ghost drawn against a hypothetical placement and a
## click against a real one take the identical path.
static func target_for(
	cell: Vector2i, normal: Vector3, struck_top: float, struck_bottom: float
) -> Dictionary:
	if normal.y >= _AXIS_EPSILON:
		return {"cell": cell, "height": struck_top}
	if normal.y <= -_AXIS_EPSILON:
		return {"cell": cell, "height": struck_bottom}
	return {"cell": cell + _side_step(normal), "height": struck_bottom}


## The neighbouring cell a horizontal normal points into.
##
## **Whichever of X or Z the normal leans further along**, so a normal that is not exactly on an
## axis still resolves to one cell rather than to a diagonal. A diagonal step would be a placement
## the attachment grammar has no orthogonal neighbour for (`GridPlacement`: *"a bridge span reads as
## N/E/S/W, never a corner graft"*), so this deliberately cannot produce one.
static func _side_step(normal: Vector3) -> Vector2i:
	if absf(normal.x) >= absf(normal.z):
		return Vector2i(1, 0) if normal.x > 0.0 else Vector2i(-1, 0)
	return Vector2i(0, 1) if normal.z > 0.0 else Vector2i(0, -1)


## **The whole question, in one call**: where does a part placed against `normal` at `cell` land,
## given what the author has already put there?
##
## `placements` is `EditorController.placements_at(cell)` — the authored rows, **not a built
## `Grid`**. Deliberately: a ghost is redrawn on every mouse move, and `EditorController.to_grid()`
## rebuilds the entire board, which is a whole-map serialization per frame to answer a question
## about one cell.
##
## `fallback_height` is what a caller wants when there is no struck face at all — a click that
## resolved off the ground plane rather than off geometry. That is the editor's authored height,
## and it is what the editor did before faces existed.
static func target_from(
	placements: Array[MapPlacement], cell: Vector2i, normal: Variant, fallback_height: float
) -> Dictionary:
	if normal is not Vector3:
		return {"cell": cell, "height": fallback_height}
	var span: Dictionary = span_of(placements)
	return target_for(cell, normal as Vector3, span["top"], span["bottom"])


## The world Y extent of a cell's authored placements, as `{top, bottom}`.
##
## Read off each part's own `volume` boxes at the placement's height — the same boxes `BoardView`
## draws — rather than through a built `Grid`. **An empty cell reports a zero-height span at the
## ground**, so clicking bare board places at 0.0 rather than refusing, which is what an author
## dropping the first floor expects.
static func span_of(placements: Array[MapPlacement]) -> Dictionary:
	var top: float = -INF
	var bottom: float = INF
	for placement: MapPlacement in placements:
		if placement == null:
			continue
		var part: Part = DataLibrary.get_part(placement.part_id)
		if part == null:
			continue
		for box: Box in part.volume:
			top = maxf(top, placement.height + box.center.y + box.size.y * 0.5)
			bottom = minf(bottom, placement.height + box.center.y - box.size.y * 0.5)
	if is_inf(top):
		return {"top": 0.0, "bottom": 0.0}
	return {"top": top, "bottom": bottom}
