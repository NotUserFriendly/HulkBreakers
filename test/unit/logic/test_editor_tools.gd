extends GutTest

## taskblock-58 Pass D: **the tool vocabulary, asked with no scene at all.**
##
## Which tools exist and what kind each authors moved out of `EditorModule` when that file went
## over its 1000-line limit, and the move is what makes these headless — the questions never had a
## widget in them.

const EXPECTED_TOOL_COUNT := 7


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## The pass's headline, stated as a number so it cannot drift back up by accident.
func test_ten_tools_became_seven() -> void:
	assert_eq(EditorTools.TOOLS.size(), EXPECTED_TOOL_COUNT, "ten became seven")
	for tool: StringName in EditorTools.TOOLS:
		assert_ne(tool, &"", "a nameless tool cannot be armed or labelled")
	var seen: Dictionary = {}
	for tool: StringName in EditorTools.TOOLS:
		assert_false(seen.has(tool), "%s appears twice in the vocabulary" % tool)
		seen[tool] = true


## The retired verbs, named individually rather than counted. **`sight_blocking` is in this list**
## because Pass C retired it with `Grid.opacity` and the pass acceptance asks that no tool by that
## name survives.
func test_the_retired_verbs_are_gone_from_the_vocabulary() -> void:
	var retired: Array[StringName] = [
		&"place",
		&"remove",
		&"height",
		&"spawn_a",
		&"spawn_b",
		&"spawn_none",
		&"claim",
		&"chance",
		&"gizmo",
		&"sight_blocking",
	]
	for verb: StringName in retired:
		assert_does_not_have(EditorTools.TOOLS, verb, "%s survived as a tool" % verb)


## The five things *Place Map Thing* absorbed. Four of them were tools; all five are selections now,
## and the point of the assertion is that nothing was dropped on the way.
func test_every_verb_that_folded_into_place_map_thing_is_reachable_as_one() -> void:
	assert_has(EditorTools.TOOLS, &"place_map_thing")
	for thing: StringName in [&"spawn_a", &"spawn_b", &"spawn_none", &"chance", &"claim"]:
		assert_has(EditorTools.MAP_THINGS, thing)


## **Terrain spans two kinds, which is why its tool derives rather than declares.** A floor attaches
## to `GROUND` and is the ground; a wall does not and stands on it. Asked of the real parts, so a
## content change that moved either one would fail here rather than silently author a placement the
## loader refuses.
func test_place_terrain_derives_the_kind_from_the_part() -> void:
	assert_eq(
		EditorTools.kind_for(&"place_terrain", &"ship_floor"),
		MapPlacement.KIND_SURFACE,
		"a floor is the ground"
	)
	assert_eq(
		EditorTools.kind_for(&"place_terrain", &"wall"),
		MapPlacement.KIND_BLOCKER,
		"a wall stands on it"
	)


## The other two placing tools ARE their kind, which is what makes them separate tools.
func test_the_other_place_tools_carry_their_own_kind() -> void:
	assert_eq(EditorTools.kind_for(&"place_big_part", &"barrel"), MapPlacement.KIND_BLOCKER)
	assert_eq(EditorTools.kind_for(&"place_part", &"barrel"), MapPlacement.KIND_FIELD_ITEM)
	# The part is not consulted for these, which is the difference from terrain — asserted by
	# handing them a part whose own attachment would say otherwise.
	assert_eq(EditorTools.kind_for(&"place_part", &"ship_floor"), MapPlacement.KIND_FIELD_ITEM)


## *Place Terrain* offers the terrain-tagged parts and the others offer the rest — a real partition,
## so nothing is unreachable and nothing is offered twice.
func test_the_place_tools_partition_the_pool() -> void:
	var pool: Array[StringName] = []
	for part: Part in DataLibrary.parts_pool():
		pool.append(part.id)
	assert_gt(pool.size(), 0, "sanity: there are parts")

	var terrain: Array[StringName] = EditorTools.part_ids_for(&"place_terrain", pool)
	var others: Array[StringName] = EditorTools.part_ids_for(&"place_big_part", pool)
	gut.p(
		(
			"  %d terrain parts, %d others, %d in the pool"
			% [terrain.size(), others.size(), pool.size()]
		)
	)

	assert_has(terrain, &"wall", "a wall is terrain")
	assert_has(terrain, &"ship_floor", "so is a floor")
	assert_does_not_have(others, &"wall", "and it is not offered as cover as well")
	assert_eq(terrain.size() + others.size(), pool.size(), "every part lands in exactly one")
	assert_eq(
		EditorTools.part_ids_for(&"place_part", pool),
		others,
		"the two non-terrain tools offer the same set — they differ in kind, not in catalogue"
	)


## A tool that does not place a part offers none, rather than offering everything.
func test_a_tool_that_places_nothing_offers_nothing() -> void:
	var pool: Array[StringName] = [&"wall", &"barrel"] as Array[StringName]
	for tool: StringName in [&"select", &"scale", &"delete", &"place_map_thing"]:
		assert_false(EditorTools.is_place_tool(tool), "%s does not place a part" % tool)
		assert_true(
			EditorTools.part_ids_for(tool, pool).is_empty(), "%s offered a parts list" % tool
		)
