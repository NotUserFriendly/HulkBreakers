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
	problems.append_array(_declaration_problems(section))
	return problems


## taskblock-55 Pass C: the authoring vocabulary's own checks.
##
## **Still warnings, never load failures**, the same posture as everything above, and the same
## reason: an authored fragment may be deliberately incomplete, and the editor's job is to say so
## rather than refuse to open it.
##
## What these catch is specifically the class of mistake that is **invisible in the result** — a
## claim that could never fire, a garrison minimum nothing could reach. Those look exactly like a
## section that simply chose to do nothing, which is why they need saying out loud; a malformed
## *placement* already announces itself by the board coming out wrong.
static func _declaration_problems(section: SectionFile) -> Array[String]:
	var problems: Array[String] = []
	var known_kinds: Array[StringName] = [
		SectionClaim.KIND_EMPTY,
		SectionClaim.KIND_INTERIOR,
		SectionClaim.KIND_EXTERIOR,
		SectionClaim.KIND_ENTRY,
		SectionClaim.KIND_MERGE,
	]

	for index: int in range(section.claims.size()):
		var claim: SectionClaim = section.claims[index]
		if claim == null:
			problems.append("claim %d is empty" % index)
			continue
		if claim.box == null:
			problems.append("claim %d ('%s') has no volume to declare with" % [index, claim.kind])
			continue
		# **A zero-extent claim is the silent one.** It validates, serialises, overlaps nothing and
		# does nothing — indistinguishable in a finished board from never having been authored.
		if claim.box.size.x <= 0.0 or claim.box.size.y <= 0.0 or claim.box.size.z <= 0.0:
			problems.append(
				(
					"claim %d ('%s') has a non-positive extent %s; it could never claim anything"
					% [index, claim.kind, claim.box.size]
				)
			)
		if not known_kinds.has(claim.kind):
			problems.append(
				"claim %d names verb '%s', which no rule consumes" % [index, claim.kind]
			)

	for index: int in range(section.spawns.size()):
		var spawn: SectionSpawn = section.spawns[index]
		if spawn == null:
			problems.append("spawn %d is empty" % index)
			continue
		if (
			spawn.cell.x < 0
			or spawn.cell.x >= section.width
			or spawn.cell.y < 0
			or spawn.cell.y >= section.rows
		):
			problems.append(
				(
					"spawn %d sits at %s, outside the section's own %dx%d"
					% [index, spawn.cell, section.width, section.rows]
				)
			)
		if spawn.chance < 0.0 or spawn.chance > 1.0:
			problems.append(
				(
					"spawn %d at %s has a chance of %.2f, outside 0..1"
					% [index, spawn.cell, spawn.chance]
				)
			)
		if spawn.kind == SectionSpawn.KIND_CLUTTER and spawn.tag in section.banned_clutter:
			problems.append(
				(
					"spawn %d offers clutter '%s' at %s, which this section also bans"
					% [index, spawn.tag, spawn.cell]
				)
			)

	# **A garrison minimum nothing could reach means the section always spawns none.** That is a
	# legitimate thing to author deliberately and an easy thing to author by accident, and the two
	# are indistinguishable in the finished board — so it is said out loud either way.
	var spawner_cells := 0
	for spawn: SectionSpawn in section.spawns:
		if spawn != null and spawn.kind == SectionSpawn.KIND_SPAWNER:
			spawner_cells += 1
	if section.minimum_garrison > spawner_cells:
		problems.append(
			(
				(
					"minimum_garrison is %d but only %d cells could ever spawn one, so this section"
					+ " always spawns none"
				)
				% [section.minimum_garrison, spawner_cells]
			)
		)
	if section.maximum_garrison >= 0 and section.maximum_garrison < section.minimum_garrison:
		problems.append(
			(
				"maximum_garrison %d is below minimum_garrison %d; nothing could satisfy both"
				% [section.maximum_garrison, section.minimum_garrison]
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
	# taskblock-55 Pass D: **an entry at height 3 does not match an entry at height 0.** A door at
	# ground level and a door at the top of a staircase are different joins, and every other field
	# here would happily call them the same one — `openings` says where *along* a wall an opening
	# is and nothing about how far up it is.
	if absf(a_edge.opening_height - b_edge.opening_height) > 0.001:
		return {
			"ok": false,
			"reason":
			(
				"opening heights differ: '%s' opens at %.2f, '%s' opens at %.2f"
				% [a.section_name, a_edge.opening_height, b.section_name, b_edge.opening_height]
			)
		}
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

	# taskblock-55 Pass D: **a vertical join shares the cells and separates in Y.** Everything below
	# is written in cell offsets, which is the right shape for the four horizontal sides and says
	# nothing at all about a section stacked on another — so the vertical case is lifted out rather
	# than encoded as a cell offset of zero that happens to mean something else.
	if side == SectionEdge.SIDE_UP or side == SectionEdge.SIDE_DOWN:
		return _stack(a, side, b)

	var offset: Vector2i = offset_for(a, side)
	# A negative offset means `b` sits above or left of `a`, so the combined board's origin moves
	# to `b` and `a` shifts instead. Handling both directions here keeps every caller from having
	# to know which sides are the "forward" ones.
	var a_origin := Vector2i(maxi(0, -offset.x), maxi(0, -offset.y))
	var b_origin: Vector2i = a_origin + offset

	# taskblock-55 Pass C: **the claims are consumed here, and this is where the delegation to
	# `MapSerializer` becomes partial.** Everything above and the placement loop below is still
	# "a section is a tiny map"; a co-occupancy verb is not, and a `MapFile` has nowhere to put
	# one. Refused *before* building anything, for the same reason `can_join` refuses before
	# stitching: a board assembled over a conflict has defects that look like the format's fault.
	var conflicts: Array[String] = ClaimResolver.describe_conflicts(a, a_origin, b, b_origin)
	var merge_result: Dictionary = ClaimResolver.merges(a, a_origin, b, b_origin)
	conflicts.append_array(merge_result["problems"] as Array[String])
	if not conflicts.is_empty():
		return {"error": "; ".join(conflicts)}

	# **Unification, not deduplication.** The dropped half of each merged pair never reaches the
	# map, so two 0.2-thick walls become one 0.2-thick wall — one part, which damage, destruction
	# and shot resolution all see as one thing.
	var dropped: Array[MapPlacement] = []
	for pair: Dictionary in merge_result["pairs"]:
		dropped.append(pair["drop"])

	var map := MapFile.new()
	map.map_name = "%s + %s" % [a.section_name, b.section_name]
	map.width = maxi(a_origin.x + a.width, b_origin.x + b.width)
	map.rows = maxi(a_origin.y + a.rows, b_origin.y + b.rows)
	for placement: MapPlacement in a.placements:
		if placement not in dropped:
			map.placements.append(_shifted(placement, a_origin))
	for placement: MapPlacement in b.placements:
		if placement not in dropped:
			map.placements.append(_shifted(placement, b_origin))

	# **An entry connecting to nothing becomes a wall.** Otherwise doors overwrite paintings and
	# open into the back of an oven. Filled in both directions, since either section can be the
	# one whose opening found no partner.
	for orphan: SectionClaim in ClaimResolver.entries_becoming_walls(a, a_origin, b, b_origin):
		map.placements.append(_wall_filling(orphan, a_origin))
	for orphan: SectionClaim in ClaimResolver.entries_becoming_walls(b, b_origin, a, a_origin):
		map.placements.append(_wall_filling(orphan, b_origin))

	return MapSerializer.to_grid(map)


## The wall that fills an entry nobody met. Placed at the claim's own cell and its own base
## height, so the fill lands where the opening was rather than at ground level under it.
static func _wall_filling(claim: SectionClaim, origin: Vector2i) -> MapPlacement:
	var volume: AABB = claim.aabb()
	var cell := Vector2i(
		int(roundf(volume.get_center().x / UnitGeometry.CELL_SIZE)),
		int(roundf(volume.get_center().z / UnitGeometry.CELL_SIZE))
	)
	return MapPlacement.new(cell + origin, MapPlacement.KIND_BLOCKER, &"wall", volume.position.y)


## taskblock-55 Pass D: `a` with `b` stacked above or below it, as one board.
##
## **The two share every cell and are separated in Y**, which is what makes stacking a different
## operation from the four horizontal joins rather than a fifth direction of the same one. There
## is no cell offset; there is a **lift**, and the interval check is what decides whether the lift
## is enough.
##
## `b` is raised to sit on top of `a`'s own interval when joining through `a`'s `up` edge, and
## dropped below it for `down`. That is the only arithmetic here: the format already carried the
## vertical extents, so nothing new had to be declared to make sections stack.
static func _stack(a: SectionFile, side: StringName, b: SectionFile) -> Dictionary:
	var a_interval: Vector2 = ClaimResolver.interval_of(a)
	var b_interval: Vector2 = ClaimResolver.interval_of(b)
	var lift: float = (
		a_interval.y - b_interval.x if side == SectionEdge.SIDE_UP else a_interval.x - b_interval.y
	)

	var problems: Array[String] = ClaimResolver.describe_interval_overlap(a, 0.0, b, lift)
	problems.append_array(ClaimResolver.describe_conflicts(a, Vector2i.ZERO, b, Vector2i.ZERO))
	if not problems.is_empty():
		return {"error": "; ".join(problems)}

	var map := MapFile.new()
	map.map_name = (
		"%s over %s"
		% ([b, a] if side == SectionEdge.SIDE_UP else [a, b]).map(
			func(section: SectionFile) -> String: return section.section_name
		)
	)
	map.width = maxi(a.width, b.width)
	map.rows = maxi(a.rows, b.rows)
	for placement: MapPlacement in a.placements:
		map.placements.append(placement)
	for placement: MapPlacement in b.placements:
		map.placements.append(_lifted(placement, lift))
	return MapSerializer.to_grid(map)


## A copy of `placement` moved in Y. A copy rather than a mutation, for the same reason `_shifted`
## makes one: the sections are loaded resources and stacking one must not edit the file it came
## from.
static func _lifted(placement: MapPlacement, lift: float) -> MapPlacement:
	return MapPlacement.new(
		placement.cell, placement.kind, placement.part_id, placement.height + lift, placement.facing
	)


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
