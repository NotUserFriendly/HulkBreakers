class_name SightSpans
extends RefCounted

## **What blocks sight, per cell, derived from the real boxes.** taskblock-58 Pass C.
##
## ## Why this exists, and what it is not
##
## `LoS.has_los` is a real march: the same reject, the same slab test and the same placement
## enumeration a round takes (`RayCaster.geometry_candidates`). That is the right answer and it is
## what every per-shot gate asks. It is also **662 usec per line** on a 32x24 generated board, and
## `VisibilityField.build` asks that question once per cell — measured at **535 ms per field
## build**, against a build that happens several times per AI turn. `PLAN.md` called this exactly:
## *"asking geometry is a ray... take the number before assuming it."* The number was taken and it
## rules out casting per cell.
##
## So the field is **built from geometry** rather than **cast per query**, and this is the derived
## structure it is built from: one pass over every blocker, placed surface and loose field item,
## reducing each to the vertical spans it occupies over the cells it fully covers. The measured
## build is 7.8 ms against the retired array's 3.7 ms — a little over twice, which is the half the
## taskblock calls affordable.
##
## **This is an index over the geometry, not a second opinion about it.** The spans come from
## `UnitGeometry.assembly_placements` — the same boxes `BoardView` draws and `RayCaster` marches.
## Nothing here is authored, nothing is flagged, and a destroyed wall vanishes from it because
## `BodyProjector.projects` says its boxes are gone.
##
## ## Deliberately weaker than the march, in the safe direction
##
## `VisibilityField`'s standing obligation is *never report "no line" for a cell that actually has
## one*. Over-inclusion is safe; under-inclusion is a bug. So every approximation here is chosen
## to under-report occlusion:
##
## - **A box only occupies a cell it FULLY covers.** A prop straddling two cells occupies neither,
##   where a bounding-box footprint would have blocked both. The full-cell case — a `wall` box is
##   a whole cell cube, a floor tile is a whole cell slab — is the one that actually matters, and
##   the partial case fails open. Measured on a generated board, the entire gap between this and
##   the march is scatter pillars, which are smaller than a cell.
## - **Spans are kept separate, never merged.** A floor at 2.0 over a wall spanning 0.0-1.0 is two
##   spans, so a line at 1.5 threads between them. Merging into one min/max would invent an
##   occluder in the gap.
## - **A grazing line does not block.** `_EPSILON` off each end of a span, so a sight line running
##   exactly along a wall's top face passes.
##
## `test_sight_geometry.gd` sweeps a real board asserting the containment this rests on: the field
## never reports blocked where the real march reports clear.

## How far inside a span a sight line has to be before it counts as blocked. Sized like
## `RayCaster.TIE_EPSILON` — well under any real geometry, well over float noise.
const _EPSILON := 0.001

## Half a cell, in world units. A cell's footprint is its centre plus or minus this on X and Z.
const _HALF_CELL := UnitGeometry.CELL_SIZE * 0.5

## `Vector2i` -> `PackedFloat32Array` of `[lo, hi, lo, hi, ...]`, world Y. Cells with no blocking
## geometry are absent rather than empty.
var _spans: Dictionary = {}


## Derives the spans for a whole board. One pass over the geometry; the caller reuses the result
## across every line it asks about, which is the entire point.
static func of(grid: Grid) -> SightSpans:
	var spans := SightSpans.new()
	for cell: Vector2i in grid.blockers:
		spans._absorb_assembly(
			grid.blocker_part_at(cell), cell, grid, UnitGeometry.blocker_height_for_cell(cell, grid)
		)
	for surface: Surface in grid.placements():
		spans._absorb(
			UnitGeometry.assembly_placements(
				surface.part, surface.cell, surface.facing, null, surface.height
			),
			surface.part
		)
	for cell: Vector2i in grid.field_items:
		for item: Variant in grid.field_items[cell]:
			if item is Part:
				spans._absorb_assembly(item, cell, grid)
	return spans


## True when geometry at `cell` occupies `height`. The per-cell question, once the spans are built.
func blocks(cell: Vector2i, height: float) -> bool:
	if not _spans.has(cell):
		return false
	var packed: PackedFloat32Array = _spans[cell]
	var i := 0
	while i < packed.size():
		if height > packed[i] + _EPSILON and height < packed[i + 1] - _EPSILON:
			return true
		i += 2
	return false


## True when geometry stands between two world points, sampled cell by cell along the supercover
## line between them.
##
## **The endpoints are exempt**, the same rule `LoS` has always kept: a unit in a doorway sees out
## of it, and the thing at the far end is what you are looking at rather than what is in the way.
## Expressed here as skipping the first and last cell of the walk, because at this granularity a
## cell *is* the endpoint.
##
## The sight line's height at each cell is read off the segment itself — the cell centre projected
## onto it — rather than assumed flat, which is the whole of "height comes for free": a line from
## a catwalk at 3.0 is at 3.0 where it crosses a 1.0 wall, and 1.0 is not in that wall's span.
func obstructs(from: Vector3, to: Vector3, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if from_cell == to_cell:
		return false
	var cells: Array[Vector2i] = Grid.line(from_cell, to_cell)
	var span: Vector3 = to - from
	var flat := Vector2(span.x, span.z)
	var flat_length_squared: float = flat.length_squared()
	for i in range(1, cells.size() - 1):
		var cell: Vector2i = cells[i]
		var height: float = to.y
		if flat_length_squared > _EPSILON:
			var offset := Vector2(
				float(cell.x) * UnitGeometry.CELL_SIZE - from.x,
				float(cell.y) * UnitGeometry.CELL_SIZE - from.z
			)
			height = from.y + span.y * clampf(offset.dot(flat) / flat_length_squared, 0.0, 1.0)
		if blocks(cell, height):
			return true
	return false


## taskblock-63 Pass D3: `height` is passed in rather than resolved here, because the two
## callers want different answers — a blocker carries its own placed height and a loose field
## item lies on the tile. Defaulted to `NAN` so a caller that says nothing still gets the tile,
## which is every caller this had before the record existed.
func _absorb_assembly(root: Part, cell: Vector2i, grid: Grid, height: float = NAN) -> void:
	if is_nan(height):
		height = UnitGeometry.true_height_for_cell(cell, grid)
	_absorb(UnitGeometry.assembly_placements(root, cell, 0.0, null, height), root)


## **`BodyProjector.projects` is the one gate on whether a part's boxes are still there.** A
## destroyed wall leaves the spans for the same reason it leaves the shot plane, decided in the
## same place — which is what makes "destroying the geometry is clearing the flag" true rather
## than aspirational.
func _absorb(placements: Array[BoxPlacement], root: Part) -> void:
	if not BodyProjector.projects(root):
		return
	for placement: BoxPlacement in placements:
		var box: AABB = _world_aabb(placement)
		var lo: float = box.position.y
		var hi: float = box.position.y + box.size.y
		# The cells this box FULLY covers on X and Z — never the ones it merely touches. See the
		# header: a partial cover failing open is the safe direction.
		#
		# **taskblock-58 Pass F gave this rule its first real content.** A resized wall can be
		# thinner than a cell — the taskblock's own example is 3 x 3 x 0.5 — and such a wall blocks
		# the real march while not registering here. That is the safe direction working as designed,
		# and it means the field's pre-filter gets weaker as authors use thin geometry. The measure
		# to watch is how much work the field still saves; the fix, if it stops saving enough, is a
		# finer occupancy than "fully covers a cell".
		#
		# **`_EPSILON` is on the inside of the `ceil`/`floor`, and it is load-bearing.** A wall's
		# box is exactly one cell across, so both bounds land exactly on an integer — where a
		# float a hair the wrong side of it flips `ceil` by a whole cell and the wall covers
		# nothing at all. Nudging the box outward by a thousandth of a cell before rounding makes
		# the exactly-touching case land where it obviously should, and is far too small to admit
		# a box that genuinely falls short.
		var x_start: int = int(
			ceil((box.position.x + _HALF_CELL - _EPSILON) / UnitGeometry.CELL_SIZE)
		)
		var x_end: int = int(
			floor((box.position.x + box.size.x - _HALF_CELL + _EPSILON) / UnitGeometry.CELL_SIZE)
		)
		var z_start: int = int(
			ceil((box.position.z + _HALF_CELL - _EPSILON) / UnitGeometry.CELL_SIZE)
		)
		var z_end: int = int(
			floor((box.position.z + box.size.z - _HALF_CELL + _EPSILON) / UnitGeometry.CELL_SIZE)
		)
		for z in range(z_start, z_end + 1):
			for x in range(x_start, x_end + 1):
				_add_span(Vector2i(x, z), lo, hi)


## A box's world-axis-aligned bounds. The transform's basis is orthonormal (unit facing and
## socket-chain rotations only, never a scale), so this is the rotated box's own corners, taken
## rather than approximated by the untransformed extent.
func _world_aabb(placement: BoxPlacement) -> AABB:
	var half: Vector3 = placement.box.size * 0.5
	var centre: Vector3 = placement.transform * placement.box.center
	var basis: Basis = placement.transform.basis
	var extent := Vector3(
		absf(basis.x.x) * half.x + absf(basis.y.x) * half.y + absf(basis.z.x) * half.z,
		absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z,
		absf(basis.x.z) * half.x + absf(basis.y.z) * half.y + absf(basis.z.z) * half.z
	)
	return AABB(centre - extent, extent * 2.0)


func _add_span(cell: Vector2i, lo: float, hi: float) -> void:
	if not _spans.has(cell):
		_spans[cell] = PackedFloat32Array()
	var packed: PackedFloat32Array = _spans[cell]
	packed.append(lo)
	packed.append(hi)
	_spans[cell] = packed
