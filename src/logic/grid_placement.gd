class_name GridPlacement
extends RefCounted

## taskblock-38 Pass A: the placement model's own attachment grammar —
## reuses the SAME `attaches_to`/Socket vocabulary body assembly already
## uses (docs/01), checked against the GRID instead of a parent part's own
## sockets. Two attachment shapes:
##
## - DOWNWARD: `GROUND` in a part's own `attaches_to` is legal only on a
##   cell with NO surfaces at all yet — the empty cell itself is the one
##   implicit downward socket; nothing else on the grid ever offers it.
## - SIDE: any OTHER socket type in `attaches_to` must find a real, free,
##   matching `Socket` on an ORTHOGONAL neighbour cell's own surface — the
##   same `PartGraph.is_legal_attachment` check body assembly already uses,
##   just against a neighbour's Part instead of a parent's. Diagonal
##   neighbours don't count: a bridge span reads as N/E/S/W, never a corner
##   graft.
##
## This is the guard rail against drifting into a building-sandbox
## (docs/PLAN.md): placement is authored by `MapGen` and gated by these
## rules, a construction grammar rather than free placement. Keep the rules
## strict — a permissive shortcut here is very hard to walk back.

const GROUND: StringName = &"GROUND"

const _ORTHOGONAL_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


static func can_place(grid: Grid, cell: Vector2i, part: Part) -> bool:
	if GROUND in part.attaches_to:
		return grid.surfaces_at(cell).is_empty()
	return not _find_attach_point(grid, cell, part).is_empty()


## Places `part` at `cell` if `can_place` allows it, appending it to
## `Grid.surfaces` and returning the new `Surface` — or null on rejection.
## A side-attaching placement genuinely OCCUPIES the neighbour's socket via
## `PartGraph.attach`, not just a legality check, so a later pass can walk
## the graph a placed catwalk actually formed.
static func place(
	grid: Grid, cell: Vector2i, part: Part, height: float, facing: float = 0.0
) -> Surface:
	if GROUND in part.attaches_to:
		if not grid.surfaces_at(cell).is_empty():
			return null
		var surface := Surface.new(part, height, facing)
		grid.add_surface(cell, surface)
		return surface

	var attach_point: Dictionary = _find_attach_point(grid, cell, part)
	if attach_point.is_empty():
		return null
	PartGraph.attach(part, attach_point.host, attach_point.socket)
	var side_surface := Surface.new(part, height, facing)
	grid.add_surface(cell, side_surface)
	return side_surface


## The first free, matching `{host, socket}` a side-attaching `part` could
## occupy on an orthogonal neighbour of `cell`, or `{}` if none exists.
static func _find_attach_point(grid: Grid, cell: Vector2i, part: Part) -> Dictionary:
	for offset: Vector2i in _ORTHOGONAL_OFFSETS:
		var neighbor: Vector2i = cell + offset
		if not grid.in_bounds(neighbor):
			continue
		for surface: Surface in grid.surfaces_at(neighbor):
			for socket: Socket in surface.part.sockets:
				if PartGraph.is_legal_attachment(part, socket):
					return {"host": surface.part, "socket": socket}
	return {}
