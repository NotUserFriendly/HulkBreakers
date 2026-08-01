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


static func hit(units: Array[Unit], grid: Grid, from: Vector3, dir: Vector3) -> Dictionary:
	var nearest_unit: Unit = null
	var nearest_part: Part = null
	var nearest_cell: Vector2i = Vector2i.ZERO
	var nearest_t: float = INF

	var unit_hit: Dictionary = UnitPicker.hit(units, from, dir)
	if not unit_hit.is_empty():
		nearest_unit = unit_hit["unit"]
		nearest_part = unit_hit["part"]
		nearest_cell = (nearest_unit as Unit).cell
		nearest_t = unit_hit["t"]

	for cell: Vector2i in grid.blockers:
		if not near_ray(cell, from, dir, UnitGeometry.true_height_for_cell(cell, grid)):
			continue
		var t: Variant = _nearest_t(grid.blockers[cell], cell, grid, from, dir)
		if t != null and (t as float) < nearest_t:
			nearest_t = t as float
			nearest_unit = null
			nearest_part = grid.blockers[cell]
			nearest_cell = cell

	for cell: Vector2i in grid.field_items:
		if not near_ray(cell, from, dir, UnitGeometry.true_height_for_cell(cell, grid)):
			continue
		for item: Variant in grid.field_items[cell]:
			if item is Part:
				var t: Variant = _nearest_t(item, cell, grid, from, dir)
				if t != null and (t as float) < nearest_t:
					nearest_t = t as float
					nearest_unit = null
					nearest_part = item
					nearest_cell = cell

	if nearest_part == null:
		return {}
	return {"unit": nearest_unit, "part": nearest_part, "cell": nearest_cell, "t": nearest_t}


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


## The nearest ray-t across every box in `part`'s own assembly tree at
## `cell` (`UnitGeometry.assembly_placements`, the same boxes
## `BoardView._spawn_blocker` draws), or null if the ray misses all of
## them.
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
static func _nearest_t(
	part: Part, cell: Vector2i, grid: Grid, from: Vector3, dir: Vector3
) -> Variant:
	var nearest_t: float = INF
	var hit_something := false
	var height: float = UnitGeometry.true_height_for_cell(cell, grid)
	for placement: BoxPlacement in UnitGeometry.assembly_placements(part, cell, 0.0, null, height):
		var t: Variant = UnitPicker.ray_box_t(placement, from, dir)
		if t != null and (t as float) < nearest_t:
			nearest_t = t as float
			hit_something = true
	return nearest_t if hit_something else null
