extends GutTest

## taskblock-56 Pass F1 — **THE ACCEPTANCE: every `EditorController` operation is tested with no
## scene.**
##
## The pass's own words: *"Follow `BuilderController` exactly: a `RefCounted` in `src/logic/`
## holding the whole editing model, with the scene reading it and drawing... Everything here is
## headless-testable and must be tested that way. The scene gets no logic."* So nothing in this
## file builds a node, and the two things that would normally need a running game — a saved file and
## a navigability verdict — are exercised against `user://` and against a hand-built pit
## respectively.
##
## The three claims that matter, in order of how much they would cost to get wrong:
##
## 1. **A map saved and reloaded is the map that was authored.** Round-tripped through real disk, in
##    both formats, because a serializer that only round-trips in memory has not been tested against
##    the thing that actually happens.
## 2. **Undo restores the prior state exactly** — including the interior of a claim's `Box`, which a
##    shallow snapshot would share and therefore fail to restore.
## 3. **Warn, never block.** A board that fails the navigability invariant still becomes a board.

const MAP_PATH := "user://test_editor_round_trip.tres"
const SECTION_PATH := "user://test_editor_round_trip_section.tres"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()
	for path: String in [MAP_PATH, SECTION_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## A small authored board with something of every kind on it — the fixture the round-trip and undo
## tests both work against, so "everything the model holds" is one definition rather than three.
func _authored() -> EditorController:
	var editor := EditorController.new()
	editor.board_name = "Test Board"
	editor.set_size(4, 3)
	for y: int in range(3):
		for x: int in range(4):
			editor.place(Vector2i(x, y), &"ship_floor")
	editor.place(Vector2i(3, 0), &"wall", MapPlacement.KIND_BLOCKER)
	editor.place(Vector2i(1, 1), &"crate", MapPlacement.KIND_FIELD_ITEM)
	editor.set_height(Vector2i(2, 2), 1.0)
	editor.set_facing(Vector2i(2, 2), 1.5)
	editor.set_spawn_marker(Vector2i(0, 0), Enums.SpawnMarker.SPAWN_A)
	editor.set_spawn_marker(Vector2i(0, 2), Enums.SpawnMarker.SPAWN_B)
	editor.add_claim(SectionClaim.KIND_INTERIOR, Box.new(Vector3(1, 1.2, 1), Vector3(2, 2.4, 2)))
	editor.set_edge(
		SectionEdge.SIDE_EAST, SectionEdge.KIND_OPEN, &"corridor_2w", [0, 1] as Array[int]
	)
	editor.set_cell_chance(Vector2i(2, 1), SectionSpawn.KIND_CLUTTER, &"barrel", 0.4)
	editor.set_section_field(&"is_room", false)
	editor.set_section_field(&"minimum_garrison", 0)
	return editor


# ---------------------------------------------------------------- placement


func test_placing_appends_in_authored_order_and_reads_back_at_its_cell() -> void:
	var editor := EditorController.new()
	editor.place(Vector2i(1, 1), &"ship_floor")
	editor.place(Vector2i(1, 1), &"crate", MapPlacement.KIND_FIELD_ITEM)
	editor.place(Vector2i(2, 1), &"ship_floor")

	var here: Array[MapPlacement] = editor.placements_at(Vector2i(1, 1))
	assert_eq(here.size(), 2, "both placements at that cell")
	assert_eq(here[0].part_id, &"ship_floor", "authored order is preserved -- the floor went first")
	assert_eq(here[1].part_id, &"crate")
	assert_eq(editor.placements.size(), 3)


## **No legality gate on the way in.** `GridPlacement.can_place` would refuse a second `GROUND`
## surface on one cell, and refusing here would make a deliberately broken board unauthorable —
## taskblock-53 settled that for the load path and F4 restates it for the editor.
func test_an_illegal_placement_is_still_placed_and_only_warned_about() -> void:
	var editor := EditorController.new()
	editor.set_size(3, 3)
	editor.place(Vector2i(1, 1), &"ship_floor")
	editor.place(Vector2i(1, 1), &"ship_floor")

	assert_eq(editor.placements_at(Vector2i(1, 1)).size(), 2, "it placed what it was told to")
	var warnings: Array[String] = editor.warnings()
	gut.p("\n".join(warnings))
	# **It says the cell is taken, not that nothing holds the floor up.** `GridPlacement.can_place`
	# refuses a GROUND part when the cell already has a surface and a side-attaching part when there
	# is nothing to attach to — opposite problems, reported with one sentence until the UI review
	# asked *"Shipfloor complaining that it doesn't have anything to attach to. Is that expected?"*
	var named: bool = false
	for warning: String in warnings:
		if warning.contains("already has a surface"):
			named = true
	assert_true(named, "and the grammar violation is reported rather than enforced")


func test_remove_top_takes_the_last_thing_authored_at_that_cell_only() -> void:
	var editor := EditorController.new()
	editor.place(Vector2i(1, 1), &"ship_floor")
	editor.place(Vector2i(1, 1), &"crate", MapPlacement.KIND_FIELD_ITEM)
	editor.place(Vector2i(2, 1), &"ship_floor")

	assert_true(editor.remove_top(Vector2i(1, 1)))
	assert_eq(editor.placements_at(Vector2i(1, 1)).size(), 1)
	assert_eq(editor.placements_at(Vector2i(1, 1))[0].part_id, &"ship_floor")
	assert_eq(editor.placements_at(Vector2i(2, 1)).size(), 1, "another cell is untouched")
	assert_false(editor.remove_top(Vector2i(3, 3)), "an empty cell has nothing to remove")


func test_clearing_a_cell_removes_everything_on_it() -> void:
	var editor := EditorController.new()
	editor.place(Vector2i(1, 1), &"ship_floor")
	editor.place(Vector2i(1, 1), &"crate", MapPlacement.KIND_FIELD_ITEM)
	assert_true(editor.clear_cell(Vector2i(1, 1)))
	assert_eq(editor.placements_at(Vector2i(1, 1)).size(), 0)
	assert_false(editor.clear_cell(Vector2i(1, 1)), "and says so when there was nothing there")


## Height and facing are surface fields. A cell holding only a blocker has no surface to set, and
## answering "done" would be a control that silently does nothing.
func test_height_and_facing_apply_to_the_top_surface_and_refuse_without_one() -> void:
	var editor := EditorController.new()
	editor.place(Vector2i(1, 1), &"wall", MapPlacement.KIND_BLOCKER)
	assert_false(editor.set_height(Vector2i(1, 1), 2.0), "a blocker is not a surface")
	assert_false(editor.set_facing(Vector2i(1, 1), 1.0))

	editor.place(Vector2i(1, 1), &"ship_floor")
	assert_true(editor.set_height(Vector2i(1, 1), 2.0))
	assert_true(editor.set_facing(Vector2i(1, 1), 1.0))
	var surface: MapPlacement = editor.placements_at(Vector2i(1, 1))[1]
	assert_almost_eq(surface.height, 2.0, 0.0001)
	assert_almost_eq(surface.facing, 1.0, 0.0001)


func test_a_spawn_marker_of_none_clears_rather_than_records() -> void:
	var editor := EditorController.new()
	editor.set_spawn_marker(Vector2i(1, 1), Enums.SpawnMarker.SPAWN_A)
	assert_true(editor.spawn_markers.has(Vector2i(1, 1)))
	editor.set_spawn_marker(Vector2i(1, 1), Enums.SpawnMarker.NONE)
	assert_false(
		editor.spawn_markers.has(Vector2i(1, 1)), "cleared, so the saved file stays sparse"
	)


# ---------------------------------------------------------------- claims, edges, chance


func test_claims_are_added_resized_retyped_and_removed_by_index() -> void:
	var editor := EditorController.new()
	var index: int = editor.add_claim(SectionClaim.KIND_EMPTY, Box.new(Vector3.ZERO, Vector3.ONE))
	assert_eq(index, 0)
	assert_true(editor.resize_claim(0, Box.new(Vector3.ZERO, Vector3(2, 2, 2))))
	assert_eq(editor.claims[0].box.size, Vector3(2, 2, 2))
	assert_true(editor.set_claim_kind(0, SectionClaim.KIND_ENTRY))
	assert_eq(editor.claims[0].kind, SectionClaim.KIND_ENTRY)

	assert_false(editor.resize_claim(7, Box.new(Vector3.ZERO, Vector3.ONE)), "no claim 7")
	assert_false(editor.set_claim_kind(-1, SectionClaim.KIND_EMPTY))
	assert_false(editor.remove_claim(7))
	assert_true(editor.remove_claim(0))
	assert_eq(editor.claims.size(), 0)


## **One edge per side, enforced by replacing.** `SectionSerializer.describe_problems` treats two
## edges on one side as a defect, so an editor whose only verb produced that state would be an
## editor that makes the mistake for you.
func test_declaring_an_edge_twice_on_one_side_replaces_rather_than_stacks() -> void:
	var editor := EditorController.new()
	editor.set_edge(SectionEdge.SIDE_NORTH, SectionEdge.KIND_OPEN, &"first")
	editor.set_edge(SectionEdge.SIDE_NORTH, SectionEdge.KIND_OPEN, &"second")
	editor.set_edge(SectionEdge.SIDE_SOUTH, SectionEdge.KIND_EXTERIOR)

	assert_eq(editor.edges.size(), 2, "one per side")
	assert_eq(editor.to_section_file().edge_for(SectionEdge.SIDE_NORTH).join_tag, &"second")
	assert_true(editor.clear_edge(SectionEdge.SIDE_NORTH))
	assert_false(editor.clear_edge(SectionEdge.SIDE_NORTH), "and says so when there is none")


## Clutter and a spawner at one cell are two different statements about it, and both are legitimate
## — which is why the kind is part of what a declaration replaces.
func test_a_cell_chance_replaces_its_own_kind_and_leaves_the_other() -> void:
	var editor := EditorController.new()
	editor.set_cell_chance(Vector2i(1, 1), SectionSpawn.KIND_CLUTTER, &"barrel", 0.5)
	editor.set_cell_chance(Vector2i(1, 1), SectionSpawn.KIND_SPAWNER, &"guard", 1.0)
	editor.set_cell_chance(Vector2i(1, 1), SectionSpawn.KIND_CLUTTER, &"pallet", 0.25)

	assert_eq(editor.spawns.size(), 2, "the clutter declaration was replaced, the spawner kept")
	var by_kind: Dictionary = {}
	for spawn: SectionSpawn in editor.spawns:
		by_kind[spawn.kind] = spawn
	assert_eq((by_kind[SectionSpawn.KIND_CLUTTER] as SectionSpawn).tag, &"pallet")
	assert_eq((by_kind[SectionSpawn.KIND_SPAWNER] as SectionSpawn).tag, &"guard")
	assert_true(editor.clear_cell_chance(Vector2i(1, 1), SectionSpawn.KIND_CLUTTER))
	assert_eq(editor.spawns.size(), 1)


## **The whole-section fields are discovered, not listed.** Adding an `@export` to `SectionFile`
## makes it editable here with no code edit, which is the standing open-vocabulary rule applied to
## an authoring surface. Asserted against the resource's own property list rather than a copy of it.
func test_the_declaration_fields_are_discovered_from_the_section_format_itself() -> void:
	var fields: Array[StringName] = EditorController.declaration_fields()
	gut.p("declaration fields: %s" % ", ".join(fields))
	for expected: StringName in [
		&"maximum_clutter",
		&"banned_clutter",
		&"minimum_garrison",
		&"maximum_garrison",
		&"encounter_types",
		&"is_room",
	]:
		assert_true(fields.has(expected), "%s is a whole-section declaration" % expected)
	for structural: StringName in EditorController.STRUCTURAL_FIELDS:
		assert_false(
			fields.has(structural), "%s is modelled explicitly, not as a field" % structural
		)


func test_an_unknown_section_field_is_refused_rather_than_written_into_the_void() -> void:
	var editor := EditorController.new()
	assert_true(editor.set_section_field(&"is_room", false))
	assert_eq(editor.section_field(&"is_room"), false)
	assert_false(editor.set_section_field(&"no_such_declaration", 3), "refused, and says so")
	assert_false(editor.section_fields.has(&"no_such_declaration"))


func test_an_unset_section_field_reads_the_formats_own_default() -> void:
	assert_eq(
		EditorController.new().section_field(&"is_room"),
		SectionFile.new().is_room,
		"no entry means the resource's own default, which is what SectionFile is written to work with"
	)


# ---------------------------------------------------------------- undo


## **THE ACCEPTANCE: undo restores the prior state exactly.** Compared as the full serialized model
## rather than field by field, so a member added later is covered without this test being edited.
func test_undo_restores_the_prior_state_exactly() -> void:
	var editor: EditorController = _authored()
	var before: String = _describe(editor)

	editor.place(Vector2i(0, 0), &"pillar", MapPlacement.KIND_BLOCKER)
	assert_ne(_describe(editor), before, "sanity: the edit changed something")

	assert_true(editor.undo())
	assert_eq(_describe(editor), before, "and undoing put every part of it back")


## The deep-copy half, which a shallow snapshot fails: a `SectionClaim` holds a `Box`, so a
## snapshot sharing that resource would restore a claim whose extent kept changing under it.
func test_undoing_a_claim_resize_restores_the_box_it_had() -> void:
	var editor := EditorController.new()
	editor.add_claim(SectionClaim.KIND_INTERIOR, Box.new(Vector3.ZERO, Vector3(1, 1, 1)))
	editor.resize_claim(0, Box.new(Vector3.ZERO, Vector3(5, 5, 5)))
	assert_eq(editor.claims[0].box.size, Vector3(5, 5, 5))

	assert_true(editor.undo())
	assert_eq(editor.claims[0].box.size, Vector3(1, 1, 1), "the box itself, not a shared reference")


func test_undo_walks_back_several_steps_and_then_refuses() -> void:
	var editor := EditorController.new()
	var empty: String = _describe(editor)
	editor.place(Vector2i(0, 0), &"ship_floor")
	editor.place(Vector2i(1, 0), &"ship_floor")
	editor.set_spawn_marker(Vector2i(0, 0), Enums.SpawnMarker.SPAWN_A)
	assert_eq(editor.undo_depth(), 3)

	assert_true(editor.undo())
	assert_true(editor.undo())
	assert_true(editor.undo())
	assert_eq(_describe(editor), empty, "all the way back to where it started")
	assert_false(editor.undo(), "and nothing further to undo")


## Undoing across a load would restore a board the author is no longer editing, which reads as the
## editor losing their work rather than as an undo.
func test_loading_clears_the_undo_stack() -> void:
	var editor: EditorController = _authored()
	assert_gt(editor.undo_depth(), 0)
	editor.load_map(MapFile.new())
	assert_eq(editor.undo_depth(), 0)
	assert_false(editor.undo())


# ---------------------------------------------------------------- round trip


## **F2's acceptance: a map saved and reloaded is the map that was authored.** Through real disk,
## because a serializer that only round-trips in memory has not been tested against what happens.
func test_a_map_round_trips_through_disk_unchanged() -> void:
	var editor: EditorController = _authored()
	editor.target = EditorController.TARGET_MAP
	assert_eq(editor.save_to(MAP_PATH)["error"], "", "it wrote")

	var reloaded := EditorController.new()
	assert_true(reloaded.load_map(load(MAP_PATH) as MapFile))

	var authored: MapFile = editor.to_map_file()
	var round_tripped: MapFile = reloaded.to_map_file()
	assert_eq(_describe_map(round_tripped), _describe_map(authored), "the map that was authored")


## The section format carries what the map format has nowhere to put — claims, edges, per-cell
## chance and the whole-section declarations — so its round trip is a different claim and gets its
## own test rather than riding on the map's.
func test_a_section_round_trips_through_disk_with_its_whole_vocabulary() -> void:
	var editor: EditorController = _authored()
	editor.target = EditorController.TARGET_SECTION
	assert_eq(editor.save_to(SECTION_PATH)["error"], "", "it wrote")

	var reloaded := EditorController.new()
	assert_true(reloaded.load_section(load(SECTION_PATH) as SectionFile))

	var authored: SectionFile = editor.to_section_file()
	var round_tripped: SectionFile = reloaded.to_section_file()
	gut.p(_describe_section(round_tripped))
	assert_eq(_describe_section(round_tripped), _describe_section(authored))


## A `.tres` written and then read is a resource the game's own catalogs would accept. Asserted
## because "it saved" and "it saved something loadable" are different facts.
func test_a_saved_map_loads_back_as_a_map_file_the_serializer_accepts() -> void:
	var editor: EditorController = _authored()
	editor.save_to(MAP_PATH)
	var result: Dictionary = MapSerializer.to_grid(load(MAP_PATH) as MapFile)
	assert_true(
		result.has("grid"), "the saved file describes a board: %s" % result.get("error", "")
	)
	assert_eq((result["grid"] as Grid).width, 4)


func test_loading_a_null_resource_refuses_rather_than_wiping_the_model() -> void:
	var editor: EditorController = _authored()
	var before: String = _describe(editor)
	assert_false(editor.load_map(null))
	assert_false(editor.load_section(null))
	assert_eq(_describe(editor), before, "a refused load changed nothing")


# ---------------------------------------------------------------- the board, and warnings


func test_the_model_becomes_a_board_through_the_ordinary_serializer() -> void:
	var result: Dictionary = _authored().to_grid()
	assert_true(result.has("grid"), result.get("error", ""))
	var grid: Grid = result["grid"]
	assert_eq(grid.width, 4)
	assert_eq(grid.rows, 3)
	assert_true(grid.blockers.has(Vector2i(3, 0)), "the authored wall is on the board")
	assert_eq(grid.get_spawn_marker(Vector2i(0, 0)), Enums.SpawnMarker.SPAWN_A)


## **F4, and the pass's own words: an authored board that fails the navigability invariant still
## loads.** The pit recipe is `test_map_navigability.gd`'s — a cell dropped exactly 2.0 below its
## neighbours, free to fall into and impossible to climb out of.
func test_a_board_that_fails_navigability_still_loads_and_is_reported() -> void:
	var editor := EditorController.new()
	editor.set_size(5, 5)
	for y: int in range(5):
		for x: int in range(5):
			editor.place(Vector2i(x, y), &"ship_floor", MapPlacement.KIND_SURFACE, 3.0)
	editor.clear_cell(Vector2i(2, 2))
	editor.place(Vector2i(2, 2), &"ship_floor", MapPlacement.KIND_SURFACE, 1.0)
	editor.set_spawn_marker(Vector2i(0, 0), Enums.SpawnMarker.SPAWN_A)

	var warnings: Array[String] = editor.navigability_warnings()
	gut.p("\n".join(warnings))
	assert_eq(warnings.size(), 1, "the pit is named")
	assert_true(warnings[0].contains("walked into and not back out of"))

	assert_true(editor.to_grid().has("grid"), "AND IT STILL LOADS -- warnings are not a gate")


func test_a_navigable_board_reports_nothing() -> void:
	assert_eq(_authored().navigability_warnings(), [] as Array[String])


## The two formats disagree about what a defect is, so `target` picks which question is asked.
## A board with nothing walkable is a broken map and a legitimate section — `SectionFile`'s own
## worked example is a square of empty cells with one exterior wall.
func test_the_target_decides_which_formats_opinion_is_reported() -> void:
	var editor := EditorController.new()
	editor.set_size(3, 3)
	editor.place(Vector2i(1, 1), &"wall", MapPlacement.KIND_BLOCKER)

	editor.target = EditorController.TARGET_MAP
	var as_map: Array[String] = editor.warnings()
	gut.p("as a map: %s" % "\n".join(as_map))
	assert_true(
		"\n".join(as_map).contains("no walkable surface"),
		"a map with nothing to stand on is broken"
	)

	editor.target = EditorController.TARGET_SECTION
	var as_section: Array[String] = editor.warnings()
	gut.p("as a section: %s" % "\n".join(as_section))
	assert_false(
		"\n".join(as_section).contains("no walkable surface"),
		"a section need not contain anything walkable -- that is what makes it not a map"
	)


## The three things `MapSerializer.to_grid` treats as errors rather than authoring opinions. Without
## these the author's only symptom is a board that refuses to load with nothing naming the cause.
func test_a_placement_outside_the_board_is_named() -> void:
	var editor := EditorController.new()
	editor.set_size(3, 3)
	editor.place(Vector2i(9, 9), &"ship_floor")
	assert_true("\n".join(editor.warnings()).contains("outside the board's own 3x3"))


func test_a_placement_naming_a_part_nobody_has_is_named() -> void:
	var editor := EditorController.new()
	editor.set_size(3, 3)
	editor.place(Vector2i(1, 1), &"no_such_part")
	assert_true("\n".join(editor.warnings()).contains("which DataLibrary does not have"))


func test_a_board_with_no_size_says_so_rather_than_listing_every_placement() -> void:
	var editor := EditorController.new()
	editor.set_size(0, 0)
	editor.place(Vector2i(0, 0), &"ship_floor")
	var warnings: Array[String] = editor.warnings()
	assert_true(warnings[0].contains("nothing can be placed on it"))


## Section-format warnings reach the author too — an open edge naming no join tag can never be
## satisfied, and `SectionSerializer` is the thing that knows it.
func test_a_section_edge_nothing_could_satisfy_is_reported() -> void:
	var editor := EditorController.new()
	editor.set_size(3, 3)
	editor.target = EditorController.TARGET_SECTION
	for y: int in range(3):
		for x: int in range(3):
			editor.place(Vector2i(x, y), &"ship_floor")
	editor.set_edge(SectionEdge.SIDE_NORTH, SectionEdge.KIND_OPEN, &"")

	var warnings: Array[String] = editor.warnings()
	gut.p("\n".join(warnings))
	assert_true("\n".join(warnings).contains("names no join_tag"))


func test_a_clean_map_has_nothing_to_say() -> void:
	var editor: EditorController = _authored()
	editor.target = EditorController.TARGET_MAP
	var warnings: Array[String] = editor.warnings()
	gut.p("clean board warnings: %s" % str(warnings))
	assert_eq(warnings, [] as Array[String], "a well-formed board must not cry wolf")


# ---------------------------------------------------------------- describers


## The whole model as one string. Used for the undo comparison so that a field added to the
## controller later is covered without this file being edited to know about it.
func _describe(editor: EditorController) -> String:
	return (
		"%s || %s"
		% [_describe_map(editor.to_map_file()), _describe_section(editor.to_section_file())]
	)


func _describe_map(map: MapFile) -> String:
	var lines: Array[String] = ["%s %dx%d" % [map.map_name, map.width, map.rows]]
	for placement: MapPlacement in map.placements:
		lines.append(
			(
				"%s %s %s h%.3f f%.3f"
				% [
					placement.cell,
					placement.kind,
					placement.part_id,
					placement.height,
					placement.facing
				]
			)
		)
	lines.append("spawns %s %s" % [str(map.spawn_cells), str(map.spawn_markers)])
	return "\n".join(lines)


func _describe_section(section: SectionFile) -> String:
	var lines: Array[String] = ["%s %dx%d" % [section.section_name, section.width, section.rows]]
	for placement: MapPlacement in section.placements:
		lines.append(
			"%s %s %s h%.3f" % [placement.cell, placement.kind, placement.part_id, placement.height]
		)
	for claim: SectionClaim in section.claims:
		lines.append("claim %s %s %s" % [claim.kind, claim.box.center, claim.box.size])
	for edge: SectionEdge in section.edges:
		lines.append(
			(
				"edge %s %s %s %s @%.3f"
				% [edge.side, edge.kind, edge.join_tag, str(edge.openings), edge.opening_height]
			)
		)
	for spawn: SectionSpawn in section.spawns:
		lines.append("spawn %s %s %s %.3f" % [spawn.cell, spawn.kind, spawn.tag, spawn.chance])
	for name: StringName in EditorController.declaration_fields():
		lines.append("%s = %s" % [name, str(section.get(name))])
	return "\n".join(lines)
