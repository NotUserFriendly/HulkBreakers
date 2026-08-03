extends GutTest

## taskblock-54 Pass C: the section format.
##
## A `MapFile` is a complete board defined by its interior. A **section** is a fragment defined
## by its **edges** — which is the thing a map format has nowhere to put, and the whole reason
## this is a second format rather than a smaller one.


func _floor(cell: Vector2i) -> MapPlacement:
	return MapPlacement.new(cell, MapPlacement.KIND_SURFACE, &"ship_floor", 0.0)


func _wall(cell: Vector2i) -> MapPlacement:
	return MapPlacement.new(cell, MapPlacement.KIND_BLOCKER, &"wall")


## A 4x4 room of floor with a walled north side and an open south side.
func _room(name: String, open_side: StringName, tag: StringName) -> SectionFile:
	var section := SectionFile.new()
	section.section_name = name
	section.width = 4
	section.rows = 4
	for y: int in range(4):
		for x: int in range(4):
			section.placements.append(_floor(Vector2i(x, y)))
	section.edges = [
		SectionEdge.new(open_side, SectionEdge.KIND_OPEN, tag),
		SectionEdge.new(SectionEdge.opposite(open_side), SectionEdge.KIND_EXTERIOR),
	]
	return section


# --- round trip ---------------------------------------------------------------------------


func test_a_section_round_trips_through_resource_save_and_load() -> void:
	var section: SectionFile = _room("Round Trip", SectionEdge.SIDE_SOUTH, &"corridor_4w")
	var path := "user://test_section_round_trip.tres"
	assert_eq(ResourceSaver.save(section, path), OK, "it saves")

	var loaded := load(path) as SectionFile
	assert_not_null(loaded, "and loads back as a SectionFile")
	if loaded == null:
		return
	assert_eq(loaded.section_name, section.section_name)
	assert_eq(loaded.width, 4)
	assert_eq(loaded.rows, 4)
	assert_eq(loaded.placements.size(), section.placements.size(), "every placement survives")
	assert_eq(loaded.edges.size(), 2, "and both edges")
	var south: SectionEdge = loaded.edge_for(SectionEdge.SIDE_SOUTH)
	assert_not_null(south, "the open edge is found by side")
	if south != null:
		assert_eq(south.kind, SectionEdge.KIND_OPEN)
		assert_eq(south.join_tag, &"corridor_4w", "and keeps what a neighbour must offer")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_section_previews_as_a_board_of_its_own_size() -> void:
	var section: SectionFile = _room("Preview", SectionEdge.SIDE_SOUTH, &"corridor_4w")
	var result: Dictionary = SectionSerializer.to_grid(section)
	assert_eq(result.get("error", ""), "", "a well-formed section builds a board")
	var grid: Grid = result["grid"]
	assert_eq(grid.width, 4)
	assert_eq(grid.rows, 4)
	assert_not_null(
		Surface.first_walkable(grid.surfaces_at(Vector2i(2, 2))), "with its floor placed"
	)


# --- the shape that makes it a section, not a small map -------------------------------------


## **The taskblock's own worked example.** A square of empty cells with one exterior wall and no
## interior walls — an edge piece of a very large room, meaningless alone and only whole once its
## neighbours exist. **`MapSerializer` rejects this shape and is right to**, because a *map* with
## nothing to stand on is broken. A format that could not express it would be a map format
## wearing a different name.
func test_a_section_of_empty_cells_with_one_exterior_wall_is_valid() -> void:
	var section := SectionFile.new()
	section.section_name = "Edge Piece"
	section.width = 4
	section.rows = 4
	for x: int in range(4):
		section.placements.append(_wall(Vector2i(x, 0)))
	section.edges = [SectionEdge.new(SectionEdge.SIDE_NORTH, SectionEdge.KIND_EXTERIOR)]

	assert_eq(
		SectionSerializer.describe_problems(section),
		[] as Array[String],
		"empty cells and one exterior wall is a legitimate section"
	)

	# The contrast, stated as a test so the two formats' rules cannot quietly converge.
	var as_map := MapFile.new()
	as_map.map_name = section.section_name
	as_map.width = 4
	as_map.rows = 4
	as_map.placements = section.placements
	assert_gt(
		MapSerializer.describe_problems(as_map).size(),
		0,
		"the same content is a broken MAP — nothing to stand on, nowhere to spawn"
	)


# --- unsatisfiable joins are rejected with a reason -----------------------------------------


func test_an_open_edge_with_no_join_tag_is_reported() -> void:
	var section: SectionFile = _room("Untagged", SectionEdge.SIDE_SOUTH, &"")
	var problems: Array[String] = SectionSerializer.describe_problems(section)
	gut.p("problems: %s" % str(problems))
	assert_gt(problems.size(), 0, "an opening nothing could match is reported")
	assert_true(str(problems).contains("join_tag"), "and the reason names what is missing")


## **An opening where there is no floor can never be satisfied**, which is the check that makes
## an edge mean something: you may declare a doorway anywhere, but not where nothing could ever
## walk through it.
func test_an_opening_with_nothing_walkable_behind_it_is_reported() -> void:
	var section := SectionFile.new()
	section.section_name = "Doorway To Nowhere"
	section.width = 4
	section.rows = 4
	# Floor everywhere except the cell the edge claims to open at.
	for y: int in range(4):
		for x: int in range(4):
			if not (x == 1 and y == 3):
				section.placements.append(_floor(Vector2i(x, y)))
	section.edges = [
		SectionEdge.new(
			SectionEdge.SIDE_SOUTH, SectionEdge.KIND_OPEN, &"corridor", [1] as Array[int]
		)
	]

	var problems: Array[String] = SectionSerializer.describe_problems(section)
	gut.p("problems: %s" % str(problems))
	assert_gt(problems.size(), 0, "reported")
	assert_true(str(problems).contains("walkable"), "and says why nothing could join there")


func test_an_opening_outside_its_own_span_is_reported() -> void:
	var section: SectionFile = _room("Overshoot", SectionEdge.SIDE_SOUTH, &"corridor")
	section.edge_for(SectionEdge.SIDE_SOUTH).openings = [9] as Array[int]
	assert_true(
		str(SectionSerializer.describe_problems(section)).contains("outside its own span"),
		"an index off the end of the side is reported"
	)


func test_two_edges_on_one_side_are_reported() -> void:
	var section: SectionFile = _room("Doubled", SectionEdge.SIDE_SOUTH, &"corridor")
	section.edges.append(SectionEdge.new(SectionEdge.SIDE_SOUTH, SectionEdge.KIND_EXTERIOR))
	assert_true(
		str(SectionSerializer.describe_problems(section)).contains("two edges"),
		"a side has one edge"
	)


func test_a_malformed_section_warns_rather_than_crashing() -> void:
	assert_eq(SectionSerializer.describe_problems(null), ["no section resource"] as Array[String])
	var empty := SectionFile.new()
	assert_gt(SectionSerializer.describe_problems(empty).size(), 0, "zero dimensions are reported")
	assert_false(SectionSerializer.to_grid(empty).has("grid"), "and it builds no board")


# --- joins ----------------------------------------------------------------------------------


func test_two_sections_with_matching_tags_and_openings_may_join() -> void:
	var north: SectionFile = _room("North", SectionEdge.SIDE_SOUTH, &"corridor_4w")
	var south: SectionFile = _room("South", SectionEdge.SIDE_NORTH, &"corridor_4w")
	var verdict: Dictionary = SectionSerializer.can_join(north, SectionEdge.SIDE_SOUTH, south)
	assert_true(verdict.ok, "matching tags and spans join: %s" % verdict.reason)


func test_mismatched_join_tags_are_refused_with_both_named() -> void:
	var north: SectionFile = _room("North", SectionEdge.SIDE_SOUTH, &"corridor_4w")
	var south: SectionFile = _room("South", SectionEdge.SIDE_NORTH, &"hangar_mouth")
	var verdict: Dictionary = SectionSerializer.can_join(north, SectionEdge.SIDE_SOUTH, south)
	assert_false(verdict.ok, "different tags do not join")
	gut.p("refused: %s" % verdict.reason)
	assert_true(str(verdict.reason).contains("corridor_4w"), "the reason names both offers")
	assert_true(str(verdict.reason).contains("hangar_mouth"))


## **Both sides must agree, and neither is the host** — the first place the socket analogy
## breaks. A section joined to an exterior wall is refused no matter what the other side offers.
func test_an_exterior_edge_refuses_a_join_from_either_direction() -> void:
	var open_section: SectionFile = _room("Open", SectionEdge.SIDE_SOUTH, &"corridor_4w")
	var sealed: SectionFile = _room("Sealed", SectionEdge.SIDE_SOUTH, &"corridor_4w")
	# Its north side is exterior by construction, so it cannot receive from the north.
	var verdict: Dictionary = SectionSerializer.can_join(
		open_section, SectionEdge.SIDE_SOUTH, sealed
	)
	assert_false(verdict.ok, "an exterior facing edge refuses")
	assert_true(str(verdict.reason).contains("Sealed"), "and names which section refused")


# --- the authored sections ------------------------------------------------------------------


## taskblock-54 Pass D: **every authored section round-trips.** Committed content and the format
## cannot drift apart — a format change that broke a shipped section would otherwise only show up
## the next time someone opened it.
func test_every_authored_section_round_trips_and_is_well_formed() -> void:
	var entries: Array[Dictionary] = SectionCatalog.entries()
	assert_gt(entries.size(), 0, "there are authored sections to check")
	for entry: Dictionary in entries:
		var section := load(entry["path"]) as SectionFile
		assert_not_null(section, "%s loads as a SectionFile" % entry["path"])
		if section == null:
			continue
		assert_eq(
			SectionSerializer.describe_problems(section),
			[] as Array[String],
			"%s is well-formed" % section.section_name
		)
		var result: Dictionary = SectionSerializer.to_grid(section)
		assert_eq(result.get("error", ""), "", "%s builds a board" % section.section_name)
		var grid: Grid = result["grid"]
		assert_eq(grid.width, section.width, "%s keeps its width" % section.section_name)
		assert_eq(grid.rows, section.rows, "%s keeps its rows" % section.section_name)
		(
			gut
			. p(
				(
					"%s — %dx%d, %d placements, %d edges"
					% [
						section.section_name,
						section.width,
						section.rows,
						section.placements.size(),
						section.edges.size(),
					]
				)
			)
		)
