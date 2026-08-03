extends GutTest

## taskblock-55 Pass C: **the section authoring vocabulary** — declarations consumed at assembly
## and never present in an assembled map.
##
## Every test here is about one of the four co-occupancy verbs, or about the whole-section
## declarations that go with them. The thing they collectively pin is that **geometry decides**:
## a big entry meeting a small one yields the small one because that is what an intersection is,
## not because anything ranked them.


func _floored(name: String, width: int, rows: int) -> SectionFile:
	var section := SectionFile.new()
	section.section_name = name
	section.width = width
	section.rows = rows
	for y: int in range(rows):
		for x: int in range(width):
			section.placements.append(
				MapPlacement.new(Vector2i(x, y), MapPlacement.KIND_SURFACE, &"ship_floor", 0.0)
			)
	return section


func _claim(kind: StringName, center: Vector3, size: Vector3) -> SectionClaim:
	return SectionClaim.new(kind, Box.new(center, size))


# --- C1: the forbidding verbs -------------------------------------------------------------


## **Empty refuses any neighbour placement in its volume.** The strongest verb and the simplest:
## it does not care what the thing is, only that something is there.
func test_empty_refuses_any_neighbour_placement_in_its_volume() -> void:
	var claimer: SectionFile = _floored("Clear Approach", 2, 2)
	# Over the neighbour's own first cell once it sits two columns east.
	claimer.claims = [_claim(SectionClaim.KIND_EMPTY, Vector3(2.0, 0.0, 0.0), Vector3(1, 2, 1))]
	var neighbour: SectionFile = _floored("Cargo Stack", 2, 2)

	var problems: Array[String] = ClaimResolver.describe_conflicts(
		claimer, Vector2i.ZERO, neighbour, Vector2i(2, 0)
	)
	gut.p("\n".join(problems))
	assert_gt(problems.size(), 0, "a floor inside an empty claim is a conflict")
	assert_true(problems[0].contains("Clear Approach"), "the reason names the claimer")
	assert_true(problems[0].contains("Cargo Stack"), "and the section whose content offended")


## The inertness half: **the same claim over space nobody uses is not a conflict.** Without this,
## "empty refuses" could equally be "empty always refuses", which would be a different and useless
## rule.
func test_empty_over_unused_space_refuses_nothing() -> void:
	var claimer: SectionFile = _floored("Clear Approach", 2, 2)
	# Well above anything either section places.
	claimer.claims = [_claim(SectionClaim.KIND_EMPTY, Vector3(2.0, 8.0, 0.0), Vector3(1, 2, 1))]
	var neighbour: SectionFile = _floored("Cargo Stack", 2, 2)

	assert_eq(
		ClaimResolver.describe_conflicts(claimer, Vector2i.ZERO, neighbour, Vector2i(2, 0)).size(),
		0,
		"a claim over space nobody uses says nothing"
	)


## **An Interior claim overlapping a neighbour's Exterior claim is refused, and the reason names
## both.** They are the only two verbs that contradict each other directly — one says whatever is
## here is inside the hulk, the other says it is outside, and both cannot be true of one volume.
func test_interior_overlapping_a_neighbours_exterior_is_refused_naming_both() -> void:
	var inside: SectionFile = _floored("Pressurised Hold", 2, 2)
	inside.claims = [_claim(SectionClaim.KIND_INTERIOR, Vector3(1.5, 1.0, 0.0), Vector3(2, 2, 1))]
	var outside: SectionFile = _floored("Hull Skin", 2, 2)
	outside.claims = [_claim(SectionClaim.KIND_EXTERIOR, Vector3(0.5, 1.0, 0.0), Vector3(2, 2, 1))]

	var problems: Array[String] = ClaimResolver.describe_conflicts(
		inside, Vector2i.ZERO, outside, Vector2i(2, 0)
	)
	gut.p("\n".join(problems))
	assert_gt(problems.size(), 0, "inside and outside cannot both be true of one volume")
	if problems.is_empty():
		return
	assert_true(problems[0].contains("Pressurised Hold"), "the reason names the interior claimant")
	assert_true(problems[0].contains("Hull Skin"), "and the exterior one")
	assert_true(problems[0].contains("interior"), "and says which verb each asserted")
	assert_true(problems[0].contains("exterior"), "both of them")


## **Two interiors agree.** The conflict is specifically interior-against-exterior, not
## "two claims overlapped" — a rule that refused any overlap would refuse every shared wall.
func test_two_interior_claims_do_not_conflict() -> void:
	var one: SectionFile = _floored("Fore Hold", 2, 2)
	one.claims = [_claim(SectionClaim.KIND_INTERIOR, Vector3(1.5, 1.0, 0.0), Vector3(2, 2, 1))]
	var other: SectionFile = _floored("Aft Hold", 2, 2)
	other.claims = [_claim(SectionClaim.KIND_INTERIOR, Vector3(0.5, 1.0, 0.0), Vector3(2, 2, 1))]

	assert_eq(
		ClaimResolver.describe_conflicts(one, Vector2i.ZERO, other, Vector2i(2, 0)).size(),
		0,
		"two sections agreeing that a volume is inside is agreement, not conflict"
	)


# --- C2: entry is permission --------------------------------------------------------------


## **Two entry volumes resolve to their intersection**, and a big entry meeting a small one
## yields the small one. Asserted on the *measurements*, because "yields the small one" is only
## meaningful if the result is the small one's actual extent rather than merely smaller.
func test_two_entry_volumes_resolve_to_their_intersection() -> void:
	# A wide, tall opening on one side; a narrow, short one on the other.
	var big := _claim(SectionClaim.KIND_ENTRY, Vector3(2.0, 1.5, 0.0), Vector3(0.4, 3.0, 3.0))
	var small := _claim(SectionClaim.KIND_ENTRY, Vector3(0.0, 1.0, 0.0), Vector3(0.4, 2.0, 1.0))

	var shared: AABB = ClaimResolver.entry_intersection(big, Vector2i.ZERO, small, Vector2i(2, 0))
	gut.p("big %s\nsmall %s\nshared %s" % [big.aabb(), small.aabb(Vector3(2, 0, 0)), shared])
	assert_true(shared.has_volume(), "the two openings meet")
	assert_almost_eq(shared.size.y, 2.0, 0.0001, "the shared height is the small one's")
	assert_almost_eq(shared.size.z, 1.0, 0.0001, "and the shared width is too")


## **An entry connecting to nothing becomes a wall.** Otherwise doors overwrite paintings and
## open into the back of an oven — an opening is only an opening if something on the other side
## agrees it is one.
func test_an_entry_connecting_to_nothing_becomes_a_wall() -> void:
	var opener: SectionFile = _floored("Airlock Vestibule", 2, 2)
	opener.claims = [
		_claim(SectionClaim.KIND_ENTRY, Vector3(1.5, 1.0, 0.0), Vector3(0.4, 2.0, 1.0))
	]
	var blank: SectionFile = _floored("Solid Bulkhead", 2, 2)

	var orphans: Array[SectionClaim] = ClaimResolver.entries_becoming_walls(
		opener, Vector2i.ZERO, blank, Vector2i(2, 0)
	)
	assert_eq(orphans.size(), 1, "an entry nobody met is filled rather than left open")

	# And the one that IS met is not filled — otherwise every entry would become a wall and the
	# rule would read the same in a test while being useless.
	blank.claims = [
		_claim(SectionClaim.KIND_ENTRY, Vector3(-0.5, 1.0, 0.0), Vector3(0.4, 2.0, 1.0))
	]
	assert_eq(
		ClaimResolver.entries_becoming_walls(opener, Vector2i.ZERO, blank, Vector2i(2, 0)).size(),
		0,
		"an entry with a partner stays an opening"
	)


## **A door auto-declares an entry volume over its own face**, so a door is a join point without
## the author saying so twice. Measured against the door part's own geometry rather than a
## constant, since "over its own face" is a statement about the part.
func test_a_door_auto_declares_an_entry_over_its_own_face() -> void:
	var door: Part = DataLibrary.get_part(&"wall")
	if door == null:
		pending("no door-shaped part is shipped yet to measure against")
		return
	var placement := MapPlacement.new(Vector2i(1, 0), MapPlacement.KIND_BLOCKER, &"wall", 0.0)

	var claim: SectionClaim = ClaimResolver.entry_for_door(placement, door)
	assert_not_null(claim, "a door declares its own entry")
	if claim == null:
		return
	assert_eq(claim.kind, SectionClaim.KIND_ENTRY)
	var expected: Vector3 = door.volume[0].size
	assert_almost_eq(claim.box.size.y, expected.y, 0.0001, "the entry is the door's own height")


## **A door whose entry volume is deleted is furniture** — not a join point, not overwritable.
## Deleting the claim is the authoring verb, so the check is that a door with no entry claim
## never appears as something a neighbour could negotiate over.
func test_a_door_with_no_entry_volume_is_never_overwritten() -> void:
	var furniture: SectionFile = _floored("Mess Hall", 2, 2)
	furniture.placements.append(
		MapPlacement.new(Vector2i(1, 0), MapPlacement.KIND_BLOCKER, &"wall", 0.0)
	)
	# No entry claim authored over it: it is scenery.
	var neighbour: SectionFile = _floored("Corridor", 2, 2)
	neighbour.claims = [
		_claim(SectionClaim.KIND_ENTRY, Vector3(-0.5, 1.0, 0.0), Vector3(0.4, 2.0, 1.0))
	]

	assert_eq(
		ClaimResolver.entries_becoming_walls(furniture, Vector2i.ZERO, neighbour, Vector2i(2, 0)),
		[] as Array[SectionClaim],
		"a door with no entry volume declares no opening to negotiate"
	)
	var result: Dictionary = SectionSerializer.stitch(furniture, SectionEdge.SIDE_EAST, neighbour)
	# It refuses on the edges (neither declares an open edge), which is the point: the door was
	# never a join point, so nothing about it was negotiable.
	assert_true(result.has("error"), "and it is not a join point either")


# --- C2b: merge ----------------------------------------------------------------------------


## **Two same-type walls merge to ONE part at the original thickness.** The assertion the
## taskblock singles out: **0.4 is the failure.** Two 0.2-thick walls sharing a volume are one
## 0.2-thick wall, because unification is not deduplication — damage, destruction and shot
## resolution must all see one thing.
func test_two_same_type_walls_merge_to_one_part_at_the_original_thickness() -> void:
	var wall: Part = DataLibrary.get_part(&"wall")
	assert_not_null(wall, "sanity: the wall part is shipped")
	if wall == null:
		return
	var thickness: float = wall.volume[0].size.x

	var west: SectionFile = _floored("Barracks", 2, 2)
	west.placements.append(
		MapPlacement.new(Vector2i(1, 0), MapPlacement.KIND_BLOCKER, &"wall", 0.0)
	)
	west.claims = [_claim(SectionClaim.KIND_MERGE, Vector3(1.0, 1.2, 0.0), Vector3(1.0, 2.4, 1.0))]
	var east: SectionFile = _floored("Armoury", 2, 2)
	east.placements.append(
		MapPlacement.new(Vector2i(0, 0), MapPlacement.KIND_BLOCKER, &"wall", 0.0)
	)

	# **The two sections overlap by the wall column**, which is what sharing a wall means. Placed
	# flush they would sit in *adjacent* cells — two walls touching face to face, which is the
	# doubled-wall defect this verb exists to prevent rather than the merge case.
	var result: Dictionary = ClaimResolver.merges(west, Vector2i.ZERO, east, Vector2i(1, 0))
	gut.p("pairs %d, problems %s" % [result["pairs"].size(), result["problems"]])
	assert_eq(result["problems"], [] as Array[String], "same types unify rather than refuse")
	assert_eq(result["pairs"].size(), 1, "two walls in a merge volume are one pair")

	# The thickness assertion, stated against the merged result rather than against the input.
	var merged: MapPlacement = result["pairs"][0]["keep"]
	var merged_volume: AABB = ClaimResolver.placement_aabb(merged, Vector2i.ZERO)
	gut.p("one wall is %.2f thick; merged reads %.2f" % [thickness, merged_volume.size.x])
	assert_almost_eq(
		merged_volume.size.x, thickness, 0.0001, "one part at the original thickness -- 0.4 fails"
	)


## **Differing types refuse the join, with a reason.** A silently doubled wall is the invisible
## defect this system exists to prevent, and picking a winner would be worse than refusing.
func test_two_different_type_walls_refuse_with_a_reason() -> void:
	var west: SectionFile = _floored("Barracks", 2, 2)
	west.placements.append(
		MapPlacement.new(Vector2i(1, 0), MapPlacement.KIND_BLOCKER, &"wall", 0.0)
	)
	west.claims = [_claim(SectionClaim.KIND_MERGE, Vector3(1.0, 1.2, 0.0), Vector3(1.0, 2.4, 1.0))]
	var east: SectionFile = _floored("Armoury", 2, 2)
	east.placements.append(
		MapPlacement.new(Vector2i(0, 0), MapPlacement.KIND_BLOCKER, &"pillar", 0.0)
	)

	var result: Dictionary = ClaimResolver.merges(west, Vector2i.ZERO, east, Vector2i(1, 0))
	gut.p("\n".join(result["problems"] as Array[String]))
	assert_eq(result["pairs"].size(), 0, "differing types do not unify")
	assert_gt(result["problems"].size(), 0, "and they say so rather than doubling silently")
	assert_true(result["problems"][0].contains("wall"), "the reason names one part")
	assert_true(result["problems"][0].contains("pillar"), "and the other")


## **Merge applies to floors too**, for the same reason it applies to walls: two sections whose
## decks overlap share one deck. A merged floor is one part.
func test_a_merged_floor_is_one_part() -> void:
	var west: SectionFile = _floored("Upper Gantry", 2, 2)
	# Over its own east column, which the neighbour's west column will land on.
	west.claims = [_claim(SectionClaim.KIND_MERGE, Vector3(1.0, 0.0, 0.5), Vector3(1.0, 1.0, 2.0))]
	var east: SectionFile = _floored("Lower Gantry", 2, 2)

	var result: Dictionary = ClaimResolver.merges(west, Vector2i.ZERO, east, Vector2i(1, 0))
	assert_eq(result["problems"], [] as Array[String], "two decks of the same part unify")
	assert_gt(result["pairs"].size(), 0, "a merged floor is one part, not two stacked")


# --- C3: whole-section declarations ---------------------------------------------------------


func _garrisoned(count: int, minimum: int, chance: float = 1.0) -> SectionFile:
	var section: SectionFile = _floored("Guard Post", 4, 1)
	section.minimum_garrison = minimum
	for x: int in range(count):
		section.spawns.append(
			SectionSpawn.new(Vector2i(x, 0), SectionSpawn.KIND_SPAWNER, &"guard", chance)
		)
	return section


## **A garrison roll below `minimum_garrison` spawns nothing rather than a reduced number.**
## All-or-nothing: a cavernous room never contains one lonely guard. A minimum that was topped up
## instead would make the declaration a floor on the count, which is a different rule.
func test_a_garrison_roll_below_the_minimum_spawns_nothing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Three candidate cells, each unlikely, against a minimum of three.
	var section: SectionFile = _garrisoned(3, 3, 0.5)
	var rolled: Array[Vector2i] = SectionRoller.roll(section, rng)["garrison"]
	gut.p("rolled %d against a minimum of 3" % rolled.size())
	assert_true(
		rolled.size() == 0 or rolled.size() >= 3, "either held or empty -- never a thin garrison"
	)

	# Pinned deterministically: a minimum nothing could reach must produce exactly none.
	var certain := RandomNumberGenerator.new()
	certain.seed = 7
	var impossible: SectionFile = _garrisoned(2, 5, 1.0)
	assert_eq(
		SectionRoller.roll(impossible, certain)["garrison"],
		[] as Array[Vector2i],
		"two certain spawners against a minimum of five is a section that spawns none"
	)


## The foil, so the rule above is not simply "the garrison is always empty".
func test_a_garrison_roll_meeting_the_minimum_spawns_all_of_them() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var section: SectionFile = _garrisoned(3, 2, 1.0)
	assert_eq(SectionRoller.roll(section, rng)["garrison"].size(), 3, "held, and all of them")


## **A multi-section room rolls one encounter, not one per section.** A room may be several
## sections, and crossing an invisible seam inside one large hold must not trigger anything.
func test_a_multi_section_room_rolls_one_encounter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var hold: SectionFile = _floored("Great Hold, West", 2, 2)
	hold.encounter_types = [&"patrol", &"ambush"]
	var rest_of_hold: SectionFile = _floored("Great Hold, East", 2, 2)
	rest_of_hold.encounter_types = [&"patrol", &"ambush"]
	# The load-bearing declaration: the east half is part of a larger room, not a room itself.
	rest_of_hold.is_room = false

	var rooms: Array[Dictionary] = SectionRoller.roll_encounters([hold, rest_of_hold], rng)
	gut.p("rooms: %s" % str(rooms))
	assert_eq(rooms.size(), 1, "one room, however many sections it took to build")
	assert_eq((rooms[0]["sections"] as Array[int]).size(), 2, "and it knows it spans both")


## The foil: two sections that each declare themselves a room roll separately. Without this the
## test above would also pass against code that simply always produced one room.
func test_two_rooms_roll_one_encounter_each() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var mess: SectionFile = _floored("Mess", 2, 2)
	mess.encounter_types = [&"patrol"]
	var cells: SectionFile = _floored("Cell Block", 2, 2)
	cells.encounter_types = [&"ambush"]

	var rooms: Array[Dictionary] = SectionRoller.roll_encounters([mess, cells], rng)
	assert_eq(rooms.size(), 2, "two rooms, two encounters")
	assert_eq(rooms[0]["encounter"], &"patrol", "each drawing from its own whitelist")
	assert_eq(rooms[1]["encounter"], &"ambush")


## **The encounter field is authored and validated and consumed nowhere**, which is the state the
## taskblock asks for — recorded so sections authored today need not be revisited when the
## encounter system arrives. Pinned so that "nothing consumes it" is a decision rather than an
## oversight somebody later reads as a missing feature.
func test_the_encounter_whitelist_reaches_no_board() -> void:
	var section: SectionFile = _floored("Mess", 2, 2)
	section.encounter_types = [&"patrol"]
	var result: Dictionary = SectionSerializer.to_grid(section)
	assert_eq(result.get("error", ""), "", "sanity: it still builds")
	var grid: Grid = result["grid"]
	assert_eq(grid.blockers.size(), 0, "no encounter placed anything on the board")
	assert_eq(grid.field_items.size(), 0, "nothing at all")


# --- the format carries the vocabulary ------------------------------------------------------


## **The whole vocabulary round-trips.** A declaration that saves and does not load is worse than
## one that never saved: the section opens, looks complete, and silently means something else.
func test_the_authoring_vocabulary_round_trips() -> void:
	var section: SectionFile = _floored("Round Trip", 3, 3)
	section.claims = [
		_claim(SectionClaim.KIND_EMPTY, Vector3(1, 1, 1), Vector3(1, 2, 1)),
		_claim(SectionClaim.KIND_ENTRY, Vector3(2.5, 1, 1), Vector3(0.4, 2, 1)),
		SectionClaim.new(
			SectionClaim.KIND_MERGE, Box.new(Vector3(0, 1, 0), Vector3(1, 2, 1)), &"wall"
		),
	]
	section.spawns = [
		SectionSpawn.new(Vector2i(1, 1), SectionSpawn.KIND_CLUTTER, &"barrel", 0.4),
		SectionSpawn.new(Vector2i(2, 2), SectionSpawn.KIND_SPAWNER, &"guard", 1.0),
	]
	section.maximum_clutter = 3
	section.banned_clutter = [&"goo_barrel"]
	section.minimum_garrison = 1
	section.maximum_garrison = 4
	section.encounter_types = [&"patrol", &"ambush"]
	section.is_room = false

	var path := "user://test_section_vocabulary_round_trip.tres"
	assert_eq(ResourceSaver.save(section, path), OK, "it saves")
	var loaded: SectionFile = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(loaded, "and loads")
	if loaded == null:
		return

	assert_eq(loaded.claims.size(), 3, "every claim survives")
	assert_eq(loaded.claims[0].kind, SectionClaim.KIND_EMPTY)
	assert_almost_eq(loaded.claims[1].box.size.x, 0.4, 0.0001, "extents survive, not just kinds")
	assert_eq(loaded.claims[2].expects, &"wall", "and what a merge expects")
	assert_eq(loaded.spawns.size(), 2)
	assert_almost_eq(loaded.spawns[0].chance, 0.4, 0.0001, "a per-cell chance is data")
	assert_eq(loaded.maximum_clutter, 3)
	assert_eq(loaded.banned_clutter, [&"goo_barrel"] as Array[StringName])
	assert_eq(loaded.minimum_garrison, 1)
	assert_eq(loaded.maximum_garrison, 4)
	assert_eq(loaded.encounter_types, [&"patrol", &"ambush"] as Array[StringName])
	assert_false(loaded.is_room, "including the load-bearing one")


## **A claim with no extent could never claim anything**, and is invisible in the result — it
## validates, serialises, overlaps nothing, and looks exactly like a section that chose not to
## declare. Reported rather than left to be discovered by the thing that did not happen.
func test_a_claim_that_could_never_fire_is_reported() -> void:
	var section: SectionFile = _floored("Silent", 2, 2)
	section.claims = [_claim(SectionClaim.KIND_EMPTY, Vector3(1, 1, 1), Vector3(0, 2, 1))]
	var problems: Array[String] = SectionSerializer.describe_problems(section)
	gut.p("\n".join(problems))
	assert_gt(problems.size(), 0, "a zero-extent claim is said out loud")


## A verb no rule consumes is a typo that behaves as silence. Open vocabularies are the rule
## here, so this is a *warning* rather than a refusal — a fifth verb is a legitimate thing to be
## midway through adding.
func test_a_claim_naming_an_unknown_verb_is_reported() -> void:
	var section: SectionFile = _floored("Typo", 2, 2)
	section.claims = [_claim(&"emtpy", Vector3(1, 1, 1), Vector3(1, 2, 1))]
	assert_gt(SectionSerializer.describe_problems(section).size(), 0, "an unconsumed verb warns")


## **A garrison minimum nothing could reach means the section always spawns none.** Legitimate to
## author deliberately, easy to author by accident, and identical in the board either way.
func test_an_unreachable_garrison_minimum_is_reported() -> void:
	var section: SectionFile = _floored("Empty Watch", 2, 2)
	section.minimum_garrison = 3
	section.spawns = [SectionSpawn.new(Vector2i(0, 0), SectionSpawn.KIND_SPAWNER, &"guard", 1.0)]
	var problems: Array[String] = SectionSerializer.describe_problems(section)
	gut.p("\n".join(problems))
	assert_gt(problems.size(), 0, "one spawner cannot satisfy a minimum of three")


## A section that both offers and bans the same clutter tag contradicts itself, and the ban wins
## silently at roll time.
func test_clutter_that_is_both_offered_and_banned_is_reported() -> void:
	var section: SectionFile = _floored("Contradiction", 2, 2)
	section.banned_clutter = [&"barrel"]
	section.spawns = [SectionSpawn.new(Vector2i(0, 0), SectionSpawn.KIND_CLUTTER, &"barrel", 1.0)]
	assert_gt(SectionSerializer.describe_problems(section).size(), 0, "it says so")


## The inertness guard the rest of these need: **a section declaring nothing is still clean.**
## Every check above must be quiet on a section that simply has no vocabulary on it, or the
## authored sections from taskblock-54 would all start warning.
func test_a_section_with_no_declarations_is_clean() -> void:
	var section: SectionFile = _floored("Plain", 3, 3)
	assert_eq(
		SectionSerializer.describe_problems(section),
		[] as Array[String],
		"declaring nothing is not an error"
	)
