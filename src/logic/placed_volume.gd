class_name PlacedVolume
extends RefCounted

## **A part authored at a size that is not its own, and the hp that follows.** taskblock-58 Pass F.
##
## The taskblock: *"Walls resize on X, Y and Z. A 3 x 3 x 0.5 wall exists as **one part**, and
## destroying it leaves a hole of a designed size — which is the point: map failure becomes
## something an author shapes rather than something that emerges a cell at a time."*
##
## ## HP is linear in volume, and the density is authored
##
## *"HP scales by volume. The alternative is three walls pretending to be one, and this keeps a big
## wall meaningfully tougher than a small one without authoring a number per size."*
##
## **Linear, on the supervisor's call**, against the alternative of a sub-linear curve that would
## give big walls diminishing returns: *"diminishing returns on more mass is the opposite of how
## armor works in real life."* Twice the wall is twice the hp.
##
## **The knob is `Part.hp_per_volume`, in data, and it is opt-in.** A part that authors none keeps
## its authored `hp` at every size — so nothing in the existing content rebalanced when this landed,
## and a designer opts a part into volume-scaled hp by adding one number to a `.tres`. `wall`
## authors **25.0**, which is exactly its own 60 hp over its own 2.4 m³: **the default size of the
## default wall is unchanged to the hitpoint**, which is what makes this safe to turn on.
##
## ## What a size means
##
## `Vector3.ZERO` means *"the part's own"*, so an unsized placement is the part exactly as authored
## and every existing map loads unchanged. A non-zero size scales the part's boxes about their own
## centres, so a 3 x 3 x 0.5 wall is one box three cells across and half a cell thick, not three
## boxes pretending.
##
## **Only the root's own boxes scale.** A socketed child is a separate part at its own size, and
## stretching a wall should not stretch whatever is bolted to it — the same reason
## `BodyProjector` composes a socket chain rather than scaling through it.


## The boxes `part` occupies when placed at `size`, shifted by `offset`, in part-local space.
##
## Returns the part's own boxes untouched when both are zero, which is both the common case and the
## one every pre-existing map takes.
##
## taskblock-59 Pass C: **the offset is applied after the scale, not before.** It is a displacement
## of the finished thing, not of the shape being scaled — so scaling a wall does not multiply how
## far it has been nudged, and the two are independent in the way an author expects when they drag
## one face and then another.
static func boxes_for(part: Part, size: Vector3, offset: Vector3 = Vector3.ZERO) -> Array[Box]:
	if part == null:
		return [] as Array[Box]
	if size.is_zero_approx() and offset.is_zero_approx():
		return part.volume
	var natural: Vector3 = natural_size(part)
	if natural.is_zero_approx():
		return part.volume
	var scale := Vector3(
		size.x / natural.x if natural.x > 0.0 and size.x > 0.0 else 1.0,
		size.y / natural.y if natural.y > 0.0 and size.y > 0.0 else 1.0,
		size.z / natural.z if natural.z > 0.0 and size.z > 0.0 else 1.0
	)
	var scaled: Array[Box] = []
	for box: Box in part.volume:
		scaled.append(Box.new(box.center * scale + offset, box.size * scale))
	return scaled


## The part's own overall extent, from its authored boxes. `Vector3.ZERO` for a part with no volume.
static func natural_size(part: Part) -> Vector3:
	return natural_bounds(part).size


## The part's own bounds in part-local space — **where its geometry sits, not just how big it is.**
##
## taskblock-59 Pass C: the Scale tool needs the position as well as the extent, and the difference
## is not academic. `boxes_for` scales each box about the part's **origin**, so where a face ends up
## depends on where the part authored its boxes: `wall` sits with its base at y=0, so scaling Y
## grows it upward and leaves the base put, while its X boxes straddle zero and scale symmetrically.
## **That is content, not a rule** — a part authored around its own centre would behave differently
## on every axis — so the tool computes the offset that produces the face movement it intends rather
## than assuming the content anchors the way `wall` happens to.
static func natural_bounds(part: Part) -> AABB:
	if part == null or part.volume.is_empty():
		return AABB()
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for box: Box in part.volume:
		var half: Vector3 = box.size * 0.5
		low = Vector3(
			minf(low.x, box.center.x - half.x),
			minf(low.y, box.center.y - half.y),
			minf(low.z, box.center.z - half.z)
		)
		high = Vector3(
			maxf(high.x, box.center.x + half.x),
			maxf(high.y, box.center.y + half.y),
			maxf(high.z, box.center.z + half.z)
		)
	return AABB(low, high - low)


## The cubic volume of `part` at `size` — the sum of its boxes, not its bounding extent, so a part
## authored as several boxes around a gap does not get credit for the gap.
## **The offset is not a parameter here on purpose**: moving a thing does not change how much of it
## there is, so hp cannot depend on where it was nudged to.
static func cubic_volume(part: Part, size: Vector3) -> float:
	var total: float = 0.0
	for box: Box in boxes_for(part, size):
		total += box.size.x * box.size.y * box.size.z
	return total


## The hp `part` has when placed at `size`.
##
## **A part with no `hp_per_volume` keeps its authored `hp`** at any size — opt-in, so turning this
## on changed nothing that had not asked for it. Floored at 1: a part thin enough to round to zero
## is still a thing that has to be destroyed rather than one that arrives already broken.
static func hp_for(part: Part, size: Vector3) -> int:
	if part == null:
		return 0
	if part.hp_per_volume <= 0.0:
		return part.hp
	return maxi(1, int(round(cubic_volume(part, size) * part.hp_per_volume)))
