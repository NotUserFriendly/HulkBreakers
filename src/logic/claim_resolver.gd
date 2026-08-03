class_name ClaimResolver
extends RefCounted

## taskblock-55 Pass C: **the four co-occupancy verbs, applied where two sections meet.**
##
## Pure logic, zero SceneTree. Every rule here is about the same question asked four ways: given
## that this volume is claimed and a neighbour wants to put something in it, what happens?
##
## | verb | answer |
## |---|---|
## | `empty` | **forbid** — nothing may co-occupy |
## | `interior` / `exterior` | **require** — co-occupants inside / outside the hulk |
## | `entry` | **negotiate** — an opening may exist; overlapping entries intersect |
## | `merge` | **permit and unify** — identical content collapses to one part |
##
## ## Geometry decides, and metadata does not get a vote
##
## The recurring temptation in a system like this is a ranking: whose door wins, which section is
## the host, which declaration is stronger. Almost none of that exists here, and where it looked
## necessary it turned out to be geometry wearing a costume:
##
## - **A big entry meeting a small one yields the small one** because that is what the
##   intersection *is*. No comparison, no priority field.
## - **Walls beside a door force a small-to-small connection** for the same reason — the wall is
##   not an entry, so it is simply not part of the shared region.
## - The one genuine ranking left is `SectionClaim.face_area`, for the rare case two entries must
##   be ordered rather than intersected. Even that is measured, not declared.
##
## `stitch` is where these are consumed; nothing here mutates a section, because two joined
## sections are still two files (`SectionEdge`'s own note).


## Every conflict between `a`'s claims and `b`'s content, and vice versa. Empty when the two may
## sit together. Each reason **names both sides**, because a refusal a reader cannot attribute is
## a refusal they will work around rather than fix.
##
## `a_origin`/`b_origin` are where each section sits in the combined board, in cells — the same
## offsets `SectionSerializer.stitch` computes.
static func describe_conflicts(
	a: SectionFile, a_origin: Vector2i, b: SectionFile, b_origin: Vector2i
) -> Array[String]:
	var problems: Array[String] = []
	problems.append_array(_one_way(a, a_origin, b, b_origin))
	problems.append_array(_one_way(b, b_origin, a, a_origin))
	problems.append_array(_opposed_claims(a, a_origin, b, b_origin))
	return problems


## `claimer`'s forbidding claims against `other`'s placements. Run both ways by the caller: a
## claim is a statement about space, not about a direction, so whichever section made it, the
## other section's content is what it is measured against.
static func _one_way(
	claimer: SectionFile, claimer_origin: Vector2i, other: SectionFile, other_origin: Vector2i
) -> Array[String]:
	var problems: Array[String] = []
	var claim_offset: Vector3 = _to_world(claimer_origin)
	for claim: SectionClaim in claimer.claims:
		if claim == null or claim.box == null or claim.kind != SectionClaim.KIND_EMPTY:
			continue
		var volume: AABB = claim.aabb(claim_offset)
		for placement: MapPlacement in other.placements:
			var placed: AABB = placement_aabb(placement, other_origin)
			if placed == AABB() or not _overlaps(volume, placed):
				continue
			problems.append(
				(
					"'%s' claims %s empty, but '%s' places %s at %s inside it"
					% [
						claimer.section_name,
						_describe(volume),
						other.section_name,
						placement.part_id,
						placement.cell + other_origin
					]
				)
			)
	return problems


## `interior` against `exterior` — the only pair of verbs that contradict each other directly.
## **Interior conflicts specifically with a neighbour asserting Exterior in the same volume**, and
## with nothing else: two interiors agree, and an interior overlapping an entry or a merge is
## ordinary and legal.
static func _opposed_claims(
	a: SectionFile, a_origin: Vector2i, b: SectionFile, b_origin: Vector2i
) -> Array[String]:
	var problems: Array[String] = []
	var a_offset: Vector3 = _to_world(a_origin)
	var b_offset: Vector3 = _to_world(b_origin)
	for a_claim: SectionClaim in a.claims:
		if a_claim == null or a_claim.box == null:
			continue
		if (
			a_claim.kind != SectionClaim.KIND_INTERIOR
			and a_claim.kind != SectionClaim.KIND_EXTERIOR
		):
			continue
		for b_claim: SectionClaim in b.claims:
			if b_claim == null or b_claim.box == null:
				continue
			if b_claim.kind == a_claim.kind:
				continue
			var opposed: bool = (
				(
					a_claim.kind == SectionClaim.KIND_INTERIOR
					and b_claim.kind == SectionClaim.KIND_EXTERIOR
				)
				or (
					a_claim.kind == SectionClaim.KIND_EXTERIOR
					and b_claim.kind == SectionClaim.KIND_INTERIOR
				)
			)
			if not opposed:
				continue
			var a_volume: AABB = a_claim.aabb(a_offset)
			var b_volume: AABB = b_claim.aabb(b_offset)
			if not _overlaps(a_volume, b_volume):
				continue
			problems.append(
				(
					"'%s' claims %s %s but '%s' claims %s %s, and they overlap"
					% [
						a.section_name,
						_describe(a_volume),
						a_claim.kind,
						b.section_name,
						_describe(b_volume),
						b_claim.kind
					]
				)
			)
	return problems


## **The shared opening two entries permit: the region both of them do.**
##
## Returns a zero-size `AABB` when they do not meet at all, which is the "an entry connecting to
## nothing" case — see `entries_becoming_walls`. A big entry meeting a small one yields the small
## one with no comparison anywhere in this function, because the intersection *is* the answer.
static func entry_intersection(
	a: SectionClaim, a_origin: Vector2i, b: SectionClaim, b_origin: Vector2i
) -> AABB:
	if a == null or b == null or a.box == null or b.box == null:
		return AABB()
	if a.kind != SectionClaim.KIND_ENTRY or b.kind != SectionClaim.KIND_ENTRY:
		return AABB()
	return a.aabb(_to_world(a_origin)).intersection(b.aabb(_to_world(b_origin)))


## **An entry connecting to nothing becomes a wall.** Every one of `a`'s entry claims that no
## entry of `b`'s meets, returned so the caller can fill it rather than leave a hole.
##
## Without this a door opens into the back of an oven, and a neighbour's larger door overwrites a
## painting on the other side of the same surface. An opening is only an opening if something is
## on the other side of it agreeing.
static func entries_becoming_walls(
	a: SectionFile, a_origin: Vector2i, b: SectionFile, b_origin: Vector2i
) -> Array[SectionClaim]:
	var orphaned: Array[SectionClaim] = []
	for a_claim: SectionClaim in a.claims:
		if a_claim == null or a_claim.box == null or a_claim.kind != SectionClaim.KIND_ENTRY:
			continue
		var connected := false
		for b_claim: SectionClaim in b.claims:
			if b_claim == null or b_claim.kind != SectionClaim.KIND_ENTRY:
				continue
			if entry_intersection(a_claim, a_origin, b_claim, b_origin).has_volume():
				connected = true
				break
		if not connected:
			orphaned.append(a_claim)
	return orphaned


## `{"pairs": Array[Dictionary], "problems": Array[String]}` — content that co-occupies inside a
## `merge` volume, resolved.
##
## **Unification, not deduplication.** Two enclosed rooms side by side share one wall, not two,
## and two 0.2-thick walls merge to **0.2** — never 0.4. One part, so damage, destruction and
## shot resolution all see one thing. That is also how flush-mounted entries mesh, since the
## walls they sit in overlap.
##
## **Differing types refuse the join, with a reason.** A silently doubled wall is the invisible
## defect this whole system exists to prevent: it looks right, it is twice as thick, and nothing
## reports it. Merging them into one arbitrary winner would be worse — it would pick.
##
## Each pair is `{"keep": MapPlacement, "drop": MapPlacement}`; the caller keeps the first and
## discards the second, which is what makes it one part at the original thickness.
static func merges(
	a: SectionFile, a_origin: Vector2i, b: SectionFile, b_origin: Vector2i
) -> Dictionary:
	var pairs: Array[Dictionary] = []
	var problems: Array[String] = []
	var volumes: Array[AABB] = []
	for section: SectionFile in [a, b]:
		var offset: Vector3 = _to_world(a_origin if section == a else b_origin)
		for claim: SectionClaim in section.claims:
			if claim != null and claim.box != null and claim.kind == SectionClaim.KIND_MERGE:
				volumes.append(claim.aabb(offset))
	if volumes.is_empty():
		return {"pairs": pairs, "problems": problems}

	for a_placement: MapPlacement in a.placements:
		var a_volume: AABB = placement_aabb(a_placement, a_origin)
		if a_volume == AABB():
			continue
		for b_placement: MapPlacement in b.placements:
			var b_volume: AABB = placement_aabb(b_placement, b_origin)
			if b_volume == AABB() or not _overlaps(a_volume, b_volume):
				continue
			if not _inside_any(volumes, a_volume, b_volume):
				continue
			if a_placement.part_id != b_placement.part_id:
				(
					problems
					. append(
						(
							(
								"'%s' places %s and '%s' places %s in the same merge volume;"
								+ " differing types cannot unify"
							)
							% [
								a.section_name,
								a_placement.part_id,
								b.section_name,
								b_placement.part_id,
							]
						)
					)
				)
				continue
			pairs.append({"keep": a_placement, "drop": b_placement})
	return {"pairs": pairs, "problems": problems}


## **A door auto-declares an entry volume over its own face**, which is what makes a door a join
## point without the author having to say so twice.
##
## The returned claim is an ordinary `SectionClaim` and is **adjustable**: expand it and a
## neighbour's larger door may overwrite yours; leave it at face size and only a fitting door can
## join. The rule that matters is that you adjust *this* claim rather than adding a second entry
## volume beside it — two entries over one door is two declarations of one fact, and they will
## disagree.
##
## **Deleting it makes the door furniture** — not a join point, not overwritable. That is a real
## authoring verb, not an oversight: a door that is scenery is a door nothing may negotiate over.
static func entry_for_door(placement: MapPlacement, door: Part) -> SectionClaim:
	if placement == null or door == null or door.volume.is_empty():
		return null
	var extent: AABB = _union_of(door.volume)
	var center := Vector3(
		placement.cell.x * UnitGeometry.CELL_SIZE,
		placement.height,
		placement.cell.y * UnitGeometry.CELL_SIZE
	)
	return SectionClaim.new(
		SectionClaim.KIND_ENTRY, Box.new(center + extent.position + extent.size * 0.5, extent.size)
	)


## taskblock-55 Pass D: **a section's own vertical interval** — the lowest and highest world Y
## anything it declares or places occupies, as `Vector2(low, high)`.
##
## **Intervals, not voxels.** taskblock-37 made height continuous on purpose and the collapse case
## reaffirmed it: a voxel grid quantizes to its resolution, so 0.5 voxels cannot express a 0.3 step
## and 0.1 voxels are twenty mostly-empty layers per cell. An interval expresses any height
## exactly and costs one comparison.
##
## Claims count toward it as much as placements do, because a claim's box *is* its vertical
## extent — that is the whole reason the whole-column question needed no separate answer.
static func interval_of(section: SectionFile, origin: Vector2i = Vector2i.ZERO) -> Vector2:
	var low := INF
	var high := -INF
	for placement: MapPlacement in section.placements:
		var volume: AABB = placement_aabb(placement, origin)
		if volume == AABB():
			continue
		low = minf(low, volume.position.y)
		high = maxf(high, volume.end.y)
	for claim: SectionClaim in section.claims:
		if claim == null or claim.box == null:
			continue
		var volume: AABB = claim.aabb()
		low = minf(low, volume.position.y)
		high = maxf(high, volume.end.y)
	if low == INF:
		return Vector2.ZERO
	return Vector2(low, high)


## **Whether two sections may occupy the same cells**, given each one's interval. Empty when they
## may; a reason **naming both intervals** when they may not.
##
## Stacking is exactly this one comparison — an observation room on top of a staircase is legal
## because their intervals are disjoint, and a second tall room is refused because it needs space
## the staircase already occupies.
##
## **Except where a `merge` volume says overlap is legal**, which is the shared-wall case. That
## exception is not a special case bolted on: `merge` *means* identical content may co-occupy, and
## the stacking check has to know it or **every adjacent pair of rooms is refused** — two rooms
## sharing a wall overlap by exactly that wall.
static func describe_interval_overlap(
	a: SectionFile, a_lift: float, b: SectionFile, b_lift: float
) -> Array[String]:
	var problems: Array[String] = []
	var a_interval: Vector2 = interval_of(a) + Vector2(a_lift, a_lift)
	var b_interval: Vector2 = interval_of(b) + Vector2(b_lift, b_lift)
	var shared_low: float = maxf(a_interval.x, b_interval.x)
	var shared_high: float = minf(a_interval.y, b_interval.y)
	if shared_high - shared_low <= 0.0001:
		return problems

	# The merge exception, asked of the overlapping band specifically: a merge volume anywhere in
	# the shared span is what makes the shared span legal.
	for section: SectionFile in [a, b]:
		var lift: float = a_lift if section == a else b_lift
		for claim: SectionClaim in section.claims:
			if claim == null or claim.box == null or claim.kind != SectionClaim.KIND_MERGE:
				continue
			var volume: AABB = claim.aabb(Vector3(0.0, lift, 0.0))
			if volume.position.y <= shared_high and volume.end.y >= shared_low:
				return problems

	(
		problems
		. append(
			(
				(
					"'%s' occupies %.2f..%.2f and '%s' occupies %.2f..%.2f; the intervals overlap and no"
					+ " merge volume permits it"
				)
				% [
					a.section_name,
					a_interval.x,
					a_interval.y,
					b.section_name,
					b_interval.x,
					b_interval.y,
				]
			)
		)
	)
	return problems


## One placement's real world volume, in the combined board's own space.
##
## **Built from `UnitGeometry.assembly_placements`**, which is the same call `RayCaster` marches
## and `BoardView` draws — so what a claim measures itself against is the geometry that will
## actually exist, not a cell-shaped approximation of it. A placement whose part id is unknown
## returns an empty `AABB`; that is `MapSerializer`'s error to report, not this one's.
static func placement_aabb(placement: MapPlacement, origin: Vector2i) -> AABB:
	if placement == null:
		return AABB()
	var part: Part = DataLibrary.get_part(placement.part_id)
	if part == null:
		return AABB()
	var boxes: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		part, placement.cell + origin, placement.facing, null, placement.height
	)
	var total := AABB()
	var first := true
	for box: BoxPlacement in boxes:
		var center: Vector3 = box.transform * box.box.center
		var one := AABB(center - box.box.size * 0.5, box.box.size)
		total = one if first else total.merge(one)
		first = false
	return total


static func _union_of(boxes: Array[Box]) -> AABB:
	var total := AABB()
	var first := true
	for box: Box in boxes:
		var one := AABB(box.center - box.size * 0.5, box.size)
		total = one if first else total.merge(one)
		first = false
	return total


## Cells to world units. Height is already in world units on both a placement and a claim, so
## only the two horizontal axes are converted.
static func _to_world(origin: Vector2i) -> Vector3:
	return Vector3(origin.x * UnitGeometry.CELL_SIZE, 0.0, origin.y * UnitGeometry.CELL_SIZE)


## **Touching is not overlapping.** Two boxes sharing exactly a face are flush, which is the
## ordinary case for adjacent sections and must never read as a conflict — `AABB.intersects`
## treats a shared face as an intersection, so the overlap is measured and required to have real
## volume instead.
static func _overlaps(one: AABB, other: AABB) -> bool:
	var shared: AABB = one.intersection(other)
	return shared.size.x > 0.0001 and shared.size.y > 0.0001 and shared.size.z > 0.0001


## True when the region the two placements share lies inside any merge volume. Asked of the
## *shared* region rather than of either placement, because a merge volume marks where overlap is
## legal — a wall may extend well outside it and still merge over the part that does not.
static func _inside_any(volumes: Array[AABB], one: AABB, other: AABB) -> bool:
	var shared: AABB = one.intersection(other)
	for volume: AABB in volumes:
		if _overlaps(volume, shared):
			return true
	return false


static func _describe(volume: AABB) -> String:
	return (
		"(%.2f,%.2f,%.2f)+(%.2f,%.2f,%.2f)"
		% [
			volume.position.x,
			volume.position.y,
			volume.position.z,
			volume.size.x,
			volume.size.y,
			volume.size.z
		]
	)
