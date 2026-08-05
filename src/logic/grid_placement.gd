class_name GridPlacement
extends RefCounted

## taskblock-38 Pass A: the placement model's own attachment grammar —
## reuses the SAME `attaches_to`/Socket vocabulary body assembly already
## uses (docs/01), checked against the GRID instead of a parent part's own
## sockets. Two attachment shapes:
##
## - UNATTACHED: `GROUND` in a part's own `attaches_to` means the part
##   attaches to nothing and is legal only where nothing is placed yet.
##   taskblock-58 Pass B restated this: it used to be described as attaching
##   to the cell, which stopped being expressible once a placement carried
##   its own position instead of being a dictionary key. See `GROUND` below
##   for the decision and what was deliberately left alone.
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

## taskblock-58 Pass B: **`GROUND` means "attaches to nothing".**
##
## It used to mean "attaches to *the cell*" — the empty cell was described here as "the one
## implicit downward socket", which only worked while a cell owned its surfaces and a placement's
## position was a dictionary key. With a placement carrying its own position there is no cell
## object to be a socket, so the word had to come to mean one of two things (`PLAN.md`, *Floors
## reference a location*): attaches to nothing and is held up by its neighbours, or retires
## outright in favour of a support requirement.
##
## **Picked: attaches to nothing.** The other option needs the support graph, which this pass
## explicitly does not build — retiring `GROUND` in favour of a requirement nothing can yet
## evaluate would leave every floor on every map unplaceable.
##
## **The one-per-cell refusal survives, restated as occupancy rather than as attachment.** A part
## that attaches to nothing still may not be placed where something already is. That keeps the
## rule identical on every authored map, which is what makes this the reversible pick: it can be
## loosened later to "not where something already is *at this height*" — the change vertical
## stacking wants — in one line, and nothing today depends on either reading, because every
## `GROUND` caller clears the cell first.
##
## **Deliberately not loosened here.** Pass B is a storage inversion with no intended behavioural
## effect; letting two floors share a cell at different heights is a behaviour change wearing a
## refactor's clothes. Queued in `PLAN.md` instead.
const GROUND: StringName = &"GROUND"

## taskblock-53 Pass C: `ZERO` first, then the four orthogonals. **A stack is
## searched before a neighbour** so a ladder segment placed on a cell that
## already holds one attaches to the segment below rather than to whatever
## happens to be beside it — the nearer host is the more specific answer, and
## order is the only thing expressing that.
const _SIDE_OFFSETS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


## `height` is where the part would sit, and a side attachment needs it: the host must
## be at a DIFFERENT height (see `_find_attach_point`). Defaulted so every pre-existing
## caller is unchanged, and passed through by `place` below.
static func can_place(grid: Grid, cell: Vector2i, part: Part, height: float = 0.0) -> bool:
	if GROUND in part.attaches_to:
		return grid.surfaces_at(cell).is_empty()
	return not _find_attach_point(grid, cell, part, height).is_empty()


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

	var attach_point: Dictionary = _find_attach_point(grid, cell, part, height)
	if attach_point.is_empty():
		return null
	PartGraph.attach(part, attach_point.host, attach_point.socket)
	var side_surface := Surface.new(part, height, facing)
	grid.add_surface(cell, side_surface)
	return side_surface


## The `{host, socket}` a side-attaching `part` at `height` should occupy: the
## **nearest surface at a different height**, on an orthogonal neighbour of `cell`
## or on `cell` itself. `{}` when nothing qualifies.
##
## ## Own cell first, then the nearest neighbour by height
##
## A surface in your own cell at your own height is skipped — that is the ground
## under your feet. Anything else in your own cell wins outright, which is how "a
## segment side-attaches to the segment below it" falls out with no stacking rule.
## Failing that, the nearest neighbour by height. A neighbour at the SAME height is
## still legal: a catwalk spanning horizontally is the case tb38 built this for.
##
## ## taskblock-53 Pass C: the same cell is searched, and that is the whole
## ## stacking rule
##
## A ladder is *tileable to arbitrary height* — "a segment side-attaches to the
## segment below it, so a run of three spans three levels with no new rule."
## The segment below is in the **same cell**, not an orthogonal neighbour, so
## searching only neighbours made stacking impossible to express. `ZERO` is
## included in the offsets rather than special-cased, because a stack really is
## the ordinary side attachment with a zero displacement, and writing it as a
## second branch would be a second rule to keep in step with the first.
##
## ## Why the socket is direction-matched
##
## The grammar used to take the first free matching socket on any neighbour,
## which meant a part bolted to a platform's **west** face could occupy the
## socket authored on its **north** edge. Nothing read the socket transform, so
## nothing noticed. `ship_floor` now authors one `LEDGE` per edge with a real
## offset, so the socket a placement takes is the one it is physically against —
## and a platform cell can host four ladders, one per side, which is the reason
## to author four in the first place.
##
## **This is the answer to Pass C2's design question**, and it is the smaller of
## the two available answers: *facing plus attach points is enough, orientation
## does not need to enter the attachment vocabulary.* Adding a direction axis to
## `attaches_to` would double every socket type (`LEDGE_N`/`LEDGE_S`/...) — the
## same "one word carrying three unrelated axes" mistake `docs/SUPERSEDED.md`
## records against the retired playstyle vocabulary. Direction is geometry, and
## geometry is already on the socket.
static func _find_attach_point(grid: Grid, cell: Vector2i, part: Part, height: float) -> Dictionary:
	var same_cell: Dictionary = {}
	var same_cell_rise: float = INF
	var neighbour: Dictionary = {}
	var neighbour_rise: float = INF
	for offset: Vector2i in _SIDE_OFFSETS:
		var host_cell: Vector2i = cell + offset
		if not grid.in_bounds(host_cell):
			continue
		var is_same_cell: bool = offset == Vector2i.ZERO
		for surface: Surface in grid.surfaces_at(host_cell):
			var rise: float = absf(surface.height - height)
			# **The one exclusion: a surface in your own cell at your own height.** That is
			# the ground under your feet, not something to attach to — without this a ladder
			# binds to the floor it stands on and never reaches the ledge beside it. A
			# NEIGHBOUR at the same height stays perfectly legal: a catwalk spanning
			# horizontally is the case side attachment was built for (tb38).
			if is_same_cell and rise <= 0.001:
				continue
			if rise >= (same_cell_rise if is_same_cell else neighbour_rise):
				continue
			var socket: Socket = _best_socket_facing(part, surface.part, offset)
			if socket == null:
				continue
			if is_same_cell:
				same_cell_rise = rise
				same_cell = {"host": surface.part, "socket": socket}
			else:
				neighbour_rise = rise
				neighbour = {"host": surface.part, "socket": socket}
	# **Your own cell wins when it qualifies** — it is what you are physically resting on.
	# This is what makes "a segment side-attaches to the segment below it" fall out without a
	# stacking rule: the segment below is in your cell, a ledge further off is not.
	return same_cell if not same_cell.is_empty() else neighbour


## The free, matching socket on `host` that physically faces back toward the
## placing cell, or null. `offset` runs from the placed cell to the host, so the
## placed part sits on the host's `-offset` side.
##
## Falls back to the first free match when no socket carries a meaningful offset
## — a host authoring one central socket is not wrong, it simply has nothing to
## discriminate on, and refusing it would break every part that never needed
## edges.
static func _best_socket_facing(part: Part, host: Part, offset: Vector2i) -> Socket:
	var wanted := Vector3(-offset.x, 0.0, -offset.y)
	var best: Socket = null
	var best_score: float = -INF
	var fallback: Socket = null
	for socket: Socket in host.sockets:
		if not PartGraph.is_legal_attachment(part, socket):
			continue
		if fallback == null:
			fallback = socket
		var origin: Vector3 = socket.current_transform().origin
		var flat := Vector3(origin.x, 0.0, origin.z)
		if flat.length() < 0.001:
			continue
		var score: float = (
			flat.normalized().dot(wanted.normalized()) if wanted.length() > 0.001 else 0.0
		)
		if score > best_score:
			best_score = score
			best = socket
	# A same-cell stack has no direction to match (`offset` is zero), so the
	# fallback is the right answer there rather than a degenerate dot product.
	if best != null and best_score > 0.5:
		return best
	return fallback
