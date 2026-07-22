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
		var t: Variant = _nearest_t(grid.blockers[cell], cell, from, dir)
		if t != null and (t as float) < nearest_t:
			nearest_t = t as float
			nearest_unit = null
			nearest_part = grid.blockers[cell]
			nearest_cell = cell

	for cell: Vector2i in grid.field_items:
		for item: Variant in grid.field_items[cell]:
			if item is Part:
				var t: Variant = _nearest_t(item, cell, from, dir)
				if t != null and (t as float) < nearest_t:
					nearest_t = t as float
					nearest_unit = null
					nearest_part = item
					nearest_cell = cell

	if nearest_part == null:
		return {}
	return {"unit": nearest_unit, "part": nearest_part, "cell": nearest_cell, "t": nearest_t}


## The nearest ray-t across every box in `part`'s own assembly tree at
## `cell` (`UnitGeometry.assembly_placements`, the same boxes
## `BoardView._spawn_blocker` draws), or null if the ray misses all of
## them.
static func _nearest_t(part: Part, cell: Vector2i, from: Vector3, dir: Vector3) -> Variant:
	var nearest_t: float = INF
	var hit_something := false
	for placement: BoxPlacement in UnitGeometry.assembly_placements(part, cell):
		var t: Variant = UnitPicker.ray_box_t(placement, from, dir)
		if t != null and (t as float) < nearest_t:
			nearest_t = t as float
			hit_something = true
	return nearest_t if hit_something else null
