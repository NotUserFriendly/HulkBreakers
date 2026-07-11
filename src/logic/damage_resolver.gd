class_name DamageResolver
extends RefCounted

## Applies a resolved HitResult. Needs more than (hit, amount) to fulfil what
## PLAN.md describes (cover lives on a grid cell; destroying the TORSO ejects
## the matrix near an ally) — state and the target Unit are threaded through.

static func apply(hit: HitResult, amount: int, state: CombatState, target: Unit) -> void:
	if hit.part != null:
		_apply_to_part(hit.part, amount, state, target)
	elif hit.cover_object != null:
		Cover.apply_damage_to_object(state.grid, hit.cover_cell, amount)
	# blocked: terrain soaked the shot, no effect.


static func _apply_to_part(part: Part, amount: int, state: CombatState, target: Unit) -> void:
	part.hp = maxi(part.hp - amount, 0)
	if part.hp > 0:
		return

	target.chassis.remove(part.slot_type)
	_drop_contents(part, state, target.cell)

	if part.slot_type == Enums.SlotType.TORSO:
		_disable_chassis_and_eject(state, target)


## Destroyed parts drop their held contents as salvage on the ground where
## they fell.
static func _drop_contents(part: Part, state: CombatState, cell: Vector2i) -> void:
	if part.contents.is_empty():
		return
	if not state.grid.field_items.has(cell):
		state.grid.field_items[cell] = []
	for child: Part in part.contents:
		state.grid.field_items[cell].append(child)
	part.contents = []


## Disables the unit and ejects its matrix directly onto the free cell
## adjacent to it that's nearest the closest living ally (ties broken by
## lowest row-major cell index). With no living ally, falls back to the free
## neighbor nearest the unit's own cell; with no free neighbor at all, drops
## the matrix on the unit's own cell.
static func _disable_chassis_and_eject(state: CombatState, unit: Unit) -> void:
	var cell: Vector2i = unit.cell
	unit.alive = false
	state.grid.set_occupant_id(cell, -1)

	var candidates: Array[Vector2i] = []
	for n: Vector2i in state.grid.neighbors(cell):
		if state.grid.get_occupant_id(n) == -1:
			candidates.append(n)

	var drop_cell: Vector2i = cell
	if not candidates.is_empty():
		var ally: Unit = _closest_living_ally(state, unit)
		var reference: Vector2i = ally.cell if ally != null else cell
		drop_cell = _nearest_cell(candidates, reference, state.grid.width)

	if not state.grid.field_items.has(drop_cell):
		state.grid.field_items[drop_cell] = []
	state.grid.field_items[drop_cell].append(unit.matrix)


static func _closest_living_ally(state: CombatState, unit: Unit) -> Unit:
	var best: Unit = null
	var best_dist: int = -1
	for ally: Unit in state.squads.get(unit.squad_id, []):
		if ally == unit or not ally.alive:
			continue
		var d: int = Grid.distance_chebyshev(unit.cell, ally.cell)
		if best == null or d < best_dist:
			best = ally
			best_dist = d
	return best


static func _nearest_cell(candidates: Array[Vector2i], reference: Vector2i, grid_width: int) -> Vector2i:
	var best: Vector2i = candidates[0]
	var best_dist: int = Grid.distance_chebyshev(candidates[0], reference)
	var best_index: int = best.y * grid_width + best.x
	for i in range(1, candidates.size()):
		var c: Vector2i = candidates[i]
		var d: int = Grid.distance_chebyshev(c, reference)
		var idx: int = c.y * grid_width + c.x
		if d < best_dist or (d == best_dist and idx < best_index):
			best = c
			best_dist = d
			best_index = idx
	return best
