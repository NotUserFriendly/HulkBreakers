class_name PartPicker
extends RefCounted

## tb32 Pass C: "cast the aim ray against all parts in the scene — unit
## parts, scatter cover, walls, downed bots, field objects — and return
## the nearest part struck along with its root object." Generalizes
## `UnitPicker` (units only): reuses its own ray-vs-box math
## (`UnitPicker.ray_box_t`, `UnitPicker.hit` itself for the unit case
## unchanged) against the SAME geometry `BoardView` renders for blockers/
## field items (`UnitGeometry.assembly_placements`) — the "render is
## hitbox" contract (docs/10) applies here too.
##
## A blocker/field-item hit reports the CELL's own ROOT Part (whatever
## `Grid.blockers`/`field_items` actually holds), not a specific box deep
## inside its assembly tree, even though the ray test itself checks every
## box in that tree: `ShotPlane.build` tags every region of one assembly
## with the SAME `region.body` identity (the root Part), so matching that
## same granularity here is what lets the aim UI's body-identity checks
## (`AimController.window_depth`, `ShotPlane.center_of_part`) work for a
## PART target exactly the way they already do for a Unit one — and a
## queued action only ever carries a target CELL anyway (docs/09), so
## resolution could never have re-derived a deeper sub-part regardless.
## A loose Matrix field item has no volume/boxes to hit — never a
## candidate. Pure math, no SceneTree, same as `UnitPicker`.

## `BR35.01`: the bound for the cheap reject in `_near_ray` — the perpendicular distance from a
## cell's centre to the ray, beyond which the full assembly test is skipped. Deliberately
## generous: a cell is one unit across and a part's boxes can overhang it, so this has to clear
## the largest assembly that could still be struck. **A conservative reject, not a tight one** —
## it may admit a cell the real test then rejects, and must never do the reverse.
const SKIP_RADIUS := 3.0


## taskblock-58 Pass A: the returned dict carries **`normal`, the world normal of
## the face the ray entered through**. Nothing new is computed — `UnitPicker.
## ray_box_hit` has reported it since taskblock-52 and both search loops here
## discarded it, so a caller wanting to know which face it clicked (the editor's
## place-on-a-face tools) had to cast its own ray and would have been free to
## disagree with this one. **There has only ever been one computation of a face
## normal in this codebase**; this is that value reaching a caller.
##
## **A miss returns `{}` and therefore carries no normal**, rather than reporting
## `Vector3.ZERO` — a zero vector survives a `dot` and reads as an answer.
## taskblock-59 follow-up: **`include_surfaces` lets a click strike a floor.**
##
## This has only ever considered units, `Grid.blockers` and `Grid.field_items` — its own header
## lists *"unit parts, scatter cover, walls, downed bots, field objects"* and floors are in none of
## them. So a click on a plain tile returned `{}`, the editor read that as *"no face"*, and
## `FacePlacement` fell back to the authored height in the **same cell** — which is the reported
## *"it looks like floors can be placed in a tile with a floor already there."* The author had
## clicked a floor and struck nothing.
##
## **Off by default, because the aim path shares this call.** `TacticsController` uses `hit` to
## resolve what a shot is pointed at, and making the ground a target there is a real change to
## targeting rather than a fix. The editor's own picking asks for it; nothing else does.
##
## `RayCaster._consider_surface` already marches exactly this geometry — same
## `UnitGeometry.assembly_placements`, same boxes — so this is that question asked by the picker,
## not a second surface model.
static func hit(
	units: Array[Unit], grid: Grid, from: Vector3, dir: Vector3, include_surfaces: bool = false
) -> Dictionary:
	var nearest_unit: Unit = null
	var nearest_part: Part = null
	var nearest_cell: Vector2i = Vector2i.ZERO
	var nearest_t: float = INF
	var nearest_normal := Vector3.ZERO

	var unit_hit: Dictionary = UnitPicker.hit(units, from, dir)
	if not unit_hit.is_empty():
		nearest_unit = unit_hit["unit"]
		nearest_part = unit_hit["part"]
		nearest_cell = (nearest_unit as Unit).cell
		nearest_t = unit_hit["t"]
		nearest_normal = unit_hit["normal"]

	for cell: Vector2i in grid.blockers:
		if not near_ray(cell, from, dir, UnitGeometry.true_height_for_cell(cell, grid)):
			continue
		var box_hit: Dictionary = _nearest_hit(grid.blockers[cell], cell, grid, from, dir)
		if not box_hit.is_empty() and float(box_hit["t"]) < nearest_t:
			nearest_t = box_hit["t"]
			nearest_unit = null
			nearest_part = grid.blockers[cell]
			nearest_cell = cell
			nearest_normal = box_hit["normal"]

	for cell: Vector2i in grid.field_items:
		if not near_ray(cell, from, dir, UnitGeometry.true_height_for_cell(cell, grid)):
			continue
		for item: Variant in grid.field_items[cell]:
			if item is Part:
				var box_hit: Dictionary = _nearest_hit(item, cell, grid, from, dir)
				if not box_hit.is_empty() and float(box_hit["t"]) < nearest_t:
					nearest_t = box_hit["t"]
					nearest_unit = null
					nearest_part = item
					nearest_cell = cell
					nearest_normal = box_hit["normal"]

	if include_surfaces:
		for surface: Surface in grid.placements():
			if not near_ray(surface.cell, from, dir, surface.height):
				continue
			var surface_hit: Dictionary = _nearest_surface_hit(surface, from, dir)
			if surface_hit.is_empty() or float(surface_hit["t"]) >= nearest_t:
				continue
			nearest_t = surface_hit["t"]
			nearest_unit = null
			nearest_part = surface.part
			nearest_cell = surface.cell
			nearest_normal = surface_hit["normal"]

	if nearest_part == null:
		return {}
	return {
		"unit": nearest_unit,
		"part": nearest_part,
		"cell": nearest_cell,
		"t": nearest_t,
		"normal": nearest_normal,
		# taskblock-59 follow-up: **the world point struck**, so a caller can tell *which* of a cell's
		# stacked placements it hit. The cell alone cannot: a column of floors is one cell, and every
		# editor verb that resolved a click to "the cell" then acted on the wrong one of them —
		# placing against the bottom of the stack, deleting the top, selecting the wall over a floor.
		# Derived from `t` rather than recomputed, so it is the same hit the normal came from.
		"point": from + dir.normalized() * nearest_t,
	}


## The nearest box of `surface`'s own assembly the ray strikes, as `{t, normal}`, or `{}`.
##
## The same shape `_nearest_hit` produces for a blocker, against the same
## `UnitGeometry.assembly_placements` call `BoardView` draws a tile from — *render is hitbox*
## (`docs/10`), which is what makes a struck face a real answer rather than an approximation.
static func _nearest_surface_hit(surface: Surface, from: Vector3, dir: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_t: float = INF
	var placements: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		surface.part, surface.cell, surface.facing, null, surface.height
	)
	for placement: BoxPlacement in placements:
		var box_hit: Dictionary = UnitPicker.ray_box_hit(placement, from, dir)
		if box_hit.is_empty() or float(box_hit["t"]) >= best_t:
			continue
		best_t = box_hit["t"]
		best = {"t": best_t, "normal": box_hit["normal"]}
	return best


## `BR35.01`: **a cheap reject before the per-box test.** `hit` ran a full assembly ray test
## against every entry in `blockers` and `field_items` regardless of where the ray went — fine
## when those held a handful of scattered props, and 200+ wall cells on a real generated map
## since tb31 C. This runs on every mouse motion.
##
## Behind the ray counts as far: a `t` below zero is discarded downstream anyway, so a blocker
## the shooter has walked past is not a candidate.
##
## taskblock-52 Pass B: public. `RayCaster` needs the identical reject in front of the identical
## per-box test, and two copies of "is this cell worth testing" would be free to drift — the one
## that matters being the direction they drift in, since admitting a cell the real test rejects
## only costs time while rejecting one that would have been hit is a shot through a wall.
##
## `BR52.01`, second half: **`height` is the cell's own real elevation**, and it used to be
## hard-coded to zero. That made the reject measure the perpendicular distance from the ray to a
## point on the ground rather than to the object, so a blocker on a cell raised by 2.0 was
## **rejected outright** for any ray passing above ~3.0 — the exact failure this reject's own doc
## comment says must never happen. Found by a test that fired at a raised wall at the height
## `BoardView` draws it and got nothing back.
## taskblock-58 Pass C: **the same reject with the height taken out**, as a first filter in front
## of `near_ray` itself.
##
## `near_ray` needs the cell's own real elevation (`BR52.01`), and getting it costs a
## `Surface.first_walkable` scan per cell — measured at **142 usec across a generated board's 218
## blockers**, paid on every sight line whether or not the cell was anywhere near it. This answers
## the same question in the ground plane only, so the height is not needed to ask it.
##
## **Provably weaker, which is the only property that matters.** The XZ-plane perpendicular
## distance minimised over the line is at most the 3D perpendicular distance to any point on that
## column, so a cell this rejects is one `near_ray` would reject at every height. It may admit
## cells the real test then rejects — which costs time — and can never do the reverse, which would
## be a shot through a wall. The behind-the-shooter half is deliberately not repeated here: it
## needs the same height, and leaving it out only admits more.
static func near_ray_flat(cell: Vector2i, from: Vector3, dir: Vector3) -> bool:
	var to_centre := Vector2(
		float(cell.x) * UnitGeometry.CELL_SIZE - from.x,
		float(cell.y) * UnitGeometry.CELL_SIZE - from.z
	)
	var flat := Vector2(dir.x, dir.z)
	var flat_length_squared: float = flat.length_squared()
	if flat_length_squared < 0.000001:
		# A vertical ray has no ground-plane direction to project onto; the distance from the
		# column to the ray is just the distance from the column to the ray's own foot.
		return to_centre.length() <= SKIP_RADIUS * UnitGeometry.CELL_SIZE
	var along: float = to_centre.dot(flat) / flat_length_squared
	var perpendicular: Vector2 = to_centre - flat * along
	return perpendicular.length() <= SKIP_RADIUS * UnitGeometry.CELL_SIZE


static func near_ray(cell: Vector2i, from: Vector3, dir: Vector3, height: float = 0.0) -> bool:
	var centre := Vector3(
		float(cell.x) * UnitGeometry.CELL_SIZE, height, float(cell.y) * UnitGeometry.CELL_SIZE
	)
	var to_centre: Vector3 = centre - from
	var along: float = to_centre.dot(dir)
	if along < -SKIP_RADIUS * UnitGeometry.CELL_SIZE:
		return false
	var perpendicular: Vector3 = to_centre - dir * along
	return perpendicular.length() <= SKIP_RADIUS * UnitGeometry.CELL_SIZE


## The nearest hit across every box in `part`'s own assembly tree at
## `cell` (`UnitGeometry.assembly_placements`, the same boxes
## `BoardView._spawn_blocker` draws) as `{t, normal}`, or an empty Dictionary if
## the ray misses all of them.
##
## taskblock-58 Pass A: was `_nearest_t`, returning a bare `Variant` distance.
## The normal belongs to **the specific box that won**, which is why it is
## carried alongside `t` through the same comparison rather than looked up again
## afterwards — a second lookup would have to re-decide which box was nearest.
##
## `BR52.01` (taskblock-52 Pass B): **at the cell's real height.**
## `assembly_placements` defaults `height` to 0.0, and this call took that
## default while `BoardView._spawn_blocker` passes `_height_for(cell)` — its own
## comment saying exactly why ("a cover object or wall on a raised cell now needs
## to actually sit ON that cell's own real ground, not float at world level 0").
## So on any raised cell the clickable volume sat at world zero while the mesh
## stood above it, which contradicts `docs/10`'s "render is hitbox" and was
## invisible on a flat map. `ShotPlane.build` already used
## `true_height_for_cell` for the same objects, making this the odd one of three.
static func _nearest_hit(
	part: Part, cell: Vector2i, grid: Grid, from: Vector3, dir: Vector3
) -> Dictionary:
	var nearest_t: float = INF
	var nearest_normal := Vector3.ZERO
	var hit_something := false
	var height: float = UnitGeometry.true_height_for_cell(cell, grid)
	for placement: BoxPlacement in UnitGeometry.assembly_placements(part, cell, 0.0, null, height):
		var box_hit: Dictionary = UnitPicker.ray_box_hit(placement, from, dir)
		if box_hit.is_empty():
			continue
		var t: float = box_hit["t"]
		if t < nearest_t:
			nearest_t = t
			nearest_normal = box_hit["normal"]
			hit_something = true
	if not hit_something:
		return {}
	return {"t": nearest_t, "normal": nearest_normal}
