class_name SectionSerializer
extends RefCounted

## taskblock-54 Pass C: **`SectionFile` <-> board, and whether two sections may join.**
##
## Pure logic, zero SceneTree. Placements are applied by **delegating to `MapSerializer`** — a
## section previewed alone genuinely is a tiny map, so building a second placement loop would be
## two answers to one question and the first thing to drift.


## `{"grid": Grid, "error": ""}` — a section on an otherwise empty board, which is what
## previewing one means. `{"error": "<reason>"}` with no `grid` key on a file that cannot
## describe a board at all.
##
## **Every "does not describe a board" rejection is `MapSerializer`'s**, unchanged: unknown part
## id, out-of-bounds cell, non-positive dimensions, two blockers on one cell. A section adds
## edge rules on top and takes none away.
static func to_grid(section: SectionFile) -> Dictionary:
	if section == null:
		return {"error": "no section resource"}
	var map := MapFile.new()
	map.map_name = section.section_name
	map.width = section.width
	map.rows = section.rows
	map.placements = section.placements
	return MapSerializer.to_grid(map)


## **Authoring warnings, never load failures** — the same posture `MapSerializer` takes, and the
## same reason: an authored fragment may be deliberately incomplete, and the editor's job is to
## say so rather than refuse to open it. Empty when clean.
##
## **What is NOT checked, deliberately:** whether the section contains anything walkable. A
## square of empty cells with one exterior wall is the taskblock's own example of a legitimate
## section — an edge piece of a very large room. `MapSerializer.describe_problems` rejects that
## shape, correctly, because a *map* with nothing to stand on is broken. A section is not a map.
static func describe_problems(section: SectionFile) -> Array[String]:
	var problems: Array[String] = []
	if section == null:
		problems.append("no section resource")
		return problems
	if section.width <= 0 or section.rows <= 0:
		problems.append(
			(
				"section '%s' has non-positive dimensions %dx%d"
				% [section.section_name, section.width, section.rows]
			)
		)
		return problems

	var grid_result: Dictionary = to_grid(section)
	var grid: Grid = grid_result.get("grid")

	var seen_sides: Dictionary = {}
	for index: int in range(section.edges.size()):
		var edge: SectionEdge = section.edges[index]
		if edge == null:
			problems.append("edge %d is empty" % index)
			continue
		if SectionEdge.opposite(edge.side) == &"":
			problems.append(
				"edge %d names side '%s', which is not one of the four" % [index, edge.side]
			)
			continue
		if seen_sides.has(edge.side):
			problems.append("two edges declared on the %s side; a side has one" % edge.side)
			continue
		seen_sides[edge.side] = true

		if edge.kind != SectionEdge.KIND_OPEN:
			continue
		# **An open edge that names nothing can never be satisfied.** A join is decided by
		# matching tags, so an untagged opening is a doorway no neighbour can be checked against.
		if edge.join_tag == &"":
			problems.append(
				"the %s edge is open but names no join_tag; nothing could match it" % edge.side
			)
		var span: int = section.span_of(edge.side)
		var cells: Array[Vector2i] = section.cells_along(edge.side)
		for opening: int in edge.openings:
			if opening < 0 or opening >= span:
				problems.append(
					(
						"the %s edge opens at %d, outside its own span of %d"
						% [edge.side, opening, span]
					)
				)
				continue
			# **An opening with nothing to walk on can never be satisfied either.** This is the
			# check that makes an edge mean something: you may declare a doorway anywhere, but
			# not where there is no floor, because no neighbour could ever join through it.
			if grid != null and Surface.first_walkable(grid.surfaces_at(cells[opening])) == null:
				problems.append(
					(
						"the %s edge opens at %d (%s), where nothing is walkable"
						% [edge.side, opening, cells[opening]]
					)
				)
	return problems


## `{"ok": bool, "reason": String}` — whether `b` may sit on `a`'s `side`.
##
## **Both edges must agree, and neither is the host.** That is the first place the socket
## analogy breaks: `PartGraph.is_legal_attachment` asks one question of one socket, because a
## part attaches *to* a host. Two sections are peers, so this reads both sides and either can
## refuse.
static func can_join(a: SectionFile, side: StringName, b: SectionFile) -> Dictionary:
	if a == null or b == null:
		return {"ok": false, "reason": "a section is missing"}
	var facing: StringName = SectionEdge.opposite(side)
	if facing == &"":
		return {"ok": false, "reason": "'%s' is not a side" % side}

	var a_edge: SectionEdge = a.edge_for(side)
	var b_edge: SectionEdge = b.edge_for(facing)
	if a_edge == null or a_edge.kind != SectionEdge.KIND_OPEN:
		return {"ok": false, "reason": "'%s' is not open on its %s side" % [a.section_name, side]}
	if b_edge == null or b_edge.kind != SectionEdge.KIND_OPEN:
		return {"ok": false, "reason": "'%s' is not open on its %s side" % [b.section_name, facing]}
	if a_edge.join_tag != b_edge.join_tag:
		return {
			"ok": false,
			"reason":
			(
				"join tags differ: '%s' offers '%s', '%s' offers '%s'"
				% [a.section_name, a_edge.join_tag, b.section_name, b_edge.join_tag]
			)
		}
	# The two sides must be the same length or the openings cannot be lined up at all. A
	# richer model — offsetting a short section along a long edge — is a layout decision and
	# belongs to whatever assembles boards, not to the format.
	if a.span_of(side) != b.span_of(facing):
		return {
			"ok": false,
			"reason":
			(
				"edge spans differ: %s is %d, %s is %d"
				% [a.section_name, a.span_of(side), b.section_name, b.span_of(facing)]
			)
		}
	if _openings_of(a_edge, a.span_of(side)) != _openings_of(b_edge, b.span_of(facing)):
		return {
			"ok": false, "reason": "openings do not line up across the %s/%s seam" % [side, facing]
		}
	return {"ok": true, "reason": ""}


## An edge's openings as an explicit sorted list. An empty `openings` array means the whole side
## is open, and expanding it here is what lets two edges be compared without each caller
## remembering that convention.
static func _openings_of(edge: SectionEdge, span: int) -> Array[int]:
	var out: Array[int] = []
	if edge.openings.is_empty():
		for i: int in range(span):
			out.append(i)
		return out
	for opening: int in edge.openings:
		if not out.has(opening):
			out.append(opening)
	out.sort()
	return out


## The cell offset `b` sits at when placed on `a`'s `side`. Sections are placed flush: a section
## on the east side starts one column past `a`'s last, never overlapping it.
static func offset_for(a: SectionFile, side: StringName) -> Vector2i:
	match side:
		SectionEdge.SIDE_EAST:
			return Vector2i(a.width, 0)
		SectionEdge.SIDE_WEST:
			return Vector2i(-a.width, 0)
		SectionEdge.SIDE_SOUTH:
			return Vector2i(0, a.rows)
		SectionEdge.SIDE_NORTH:
			return Vector2i(0, -a.rows)
		_:
			return Vector2i.ZERO


## `{"grid": Grid, "error": ""}` — `a` with `b` placed on its `side`, as one board.
##
## **This is not a generator and is deliberately not the beginning of one.** No library
## selection, no layout algorithm, no whole-board assembly. It answers exactly one question:
## *is the edge metadata sufficient to decide that two sections may join, and to place the second
## correctly relative to the first?* If it were not, that would be the block's most valuable
## finding and the format would change before anything was built on it.
##
## Refuses with `can_join`'s own reason rather than stitching something the edges forbid — a
## seam that was never legal produces a board whose defects are the layout's fault and look like
## the format's.
static func stitch(a: SectionFile, side: StringName, b: SectionFile) -> Dictionary:
	var verdict: Dictionary = can_join(a, side, b)
	if not verdict.ok:
		return {"error": verdict.reason}

	var offset: Vector2i = offset_for(a, side)
	# A negative offset means `b` sits above or left of `a`, so the combined board's origin moves
	# to `b` and `a` shifts instead. Handling both directions here keeps every caller from having
	# to know which sides are the "forward" ones.
	var a_origin := Vector2i(maxi(0, -offset.x), maxi(0, -offset.y))
	var b_origin: Vector2i = a_origin + offset

	var map := MapFile.new()
	map.map_name = "%s + %s" % [a.section_name, b.section_name]
	map.width = maxi(a_origin.x + a.width, b_origin.x + b.width)
	map.rows = maxi(a_origin.y + a.rows, b_origin.y + b.rows)
	for placement: MapPlacement in a.placements:
		map.placements.append(_shifted(placement, a_origin))
	for placement: MapPlacement in b.placements:
		map.placements.append(_shifted(placement, b_origin))
	return MapSerializer.to_grid(map)


## A copy of `placement` moved by `offset`. A copy rather than a mutation, because the sections
## are loaded resources and stitching one must not edit the file it came from.
static func _shifted(placement: MapPlacement, offset: Vector2i) -> MapPlacement:
	return MapPlacement.new(
		placement.cell + offset,
		placement.kind,
		placement.part_id,
		placement.height,
		placement.facing
	)
