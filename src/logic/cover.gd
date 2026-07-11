class_name Cover
extends RefCounted

## Cover derived from blockers adjacent to the target along the incoming line
## of fire (Appendix C). A cell's cover comes from Grid.cover_value / Grid.blockers,
## populated by MapGen (terrain, permanent) or by combat placing/destroying
## objects (destructible, Part.is_destructible == true).

const HALF_PROFILE: Array[Enums.SlotType] = [Enums.SlotType.LEGS]
const FULL_PROFILE: Array[Enums.SlotType] = [
	Enums.SlotType.HEAD, Enums.SlotType.TORSO,
	Enums.SlotType.L_ARM, Enums.SlotType.R_ARM, Enums.SlotType.LEGS,
]


static func between(grid: Grid, from: Vector2i, to: Vector2i) -> CoverInfo:
	var info := CoverInfo.new()
	if from == to:
		return info

	var line: Array[Vector2i] = Grid.line(from, to)
	var best_level: CoverInfo.Level = CoverInfo.Level.NONE
	var best_cell: Vector2i = Vector2i.ZERO
	var found: bool = false

	for cell: Vector2i in _approach_cells(line, from, to):
		var cell_level: CoverInfo.Level = _level_at(grid, cell)
		if cell_level > best_level:
			best_level = cell_level
			best_cell = cell
			found = true

	if not found or best_level == CoverInfo.Level.NONE:
		return info

	info.level = best_level
	info.profile = (HALF_PROFILE.duplicate() if best_level == CoverInfo.Level.HALF else FULL_PROFILE.duplicate())
	info.object = grid.blockers.get(best_cell, null)
	info.cell = best_cell
	return info


## Cells in the line adjacent to `to`, excluding `from` itself and `to`.
## A straight approach yields one cell; an exact corner crossing (supercover)
## yields the two cells bordering that corner — capped at 2, since the
## algorithm never produces more than two consecutive corner-adjacent cells
## right before the target.
static func _approach_cells(line: Array[Vector2i], from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var i: int = line.size() - 2
	while i >= 1 and result.size() < 2:
		var cell: Vector2i = line[i]
		if cell == from or Grid.distance_chebyshev(cell, to) != 1:
			break
		result.append(cell)
		i -= 1
	return result


static func _level_at(grid: Grid, cell: Vector2i) -> CoverInfo.Level:
	if not grid.in_bounds(cell):
		return CoverInfo.Level.NONE
	var v: float = grid.get_cover_value(cell)
	if v >= 1.0:
		return CoverInfo.Level.FULL
	elif v > 0.0:
		return CoverInfo.Level.HALF
	return CoverInfo.Level.NONE


## Destroys the destructible cover object on `cell` (if any): removes it as a
## blocker and downgrades the cell's cover level to NONE. Terrain (non-destructible)
## objects are never touched by this — they have no hp to reduce, so they never
## reach hp <= 0 in the first place.
static func destroy_object(grid: Grid, cell: Vector2i) -> void:
	grid.blockers.erase(cell)
	grid.set_cover_value(cell, 0.0)


## Applies damage to the destructible cover object on `cell`, if present and
## destructible. Downgrades the cell's cover on hp <= 0.
static func apply_damage_to_object(grid: Grid, cell: Vector2i, amount: int) -> void:
	if not grid.blockers.has(cell):
		return
	var object: Part = grid.blockers[cell]
	if not object.is_destructible:
		return
	object.hp -= amount
	if object.hp <= 0:
		destroy_object(grid, cell)
