extends GutTest

## taskblock-54 Pass E: **prove a join, and nothing more.**
##
## Two authored sections placed adjacent, the seam validated, and a unit able to walk from one
## into the other. Not a generator: no library selection, no layout algorithm, no whole-board
## assembly. The only question is whether the edge metadata is **sufficient** to decide that two
## sections may join and to place the second correctly relative to the first.


func should_skip_script():
	return SuiteTier.skip_if_fast()


func _section(name: StringName) -> SectionFile:
	return load(SectionCatalog.path_for(name)) as SectionFile


## One character per cell of a stitched board, so the seam is visible in the run log rather than
## inferred from a path cost. CLAUDE.md: a spatial system without a dump is one nobody can verify.
func _dump(grid: Grid, label: String) -> void:
	gut.p("%s — %dx%d   # wall   . floor   (space) nothing" % [label, grid.width, grid.rows])
	for y: int in range(grid.rows):
		var row := ""
		for x: int in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.blockers.has(cell):
				row += "#"
			elif Surface.first_walkable(grid.surfaces_at(cell)) != null:
				row += "."
			else:
				row += " "
		gut.p("  %2d %s" % [y, row])


func test_two_compatible_sections_join_and_a_path_crosses_the_seam() -> void:
	var west: SectionFile = _section(&"West Hall")
	var east: SectionFile = _section(&"East Hall")
	assert_not_null(west, "the authored sections load")
	assert_not_null(east)
	if west == null or east == null:
		return

	var verdict: Dictionary = SectionSerializer.can_join(west, SectionEdge.SIDE_EAST, east)
	assert_true(verdict.ok, "the seam validates: %s" % verdict.reason)

	var result: Dictionary = SectionSerializer.stitch(west, SectionEdge.SIDE_EAST, east)
	assert_eq(result.get("error", ""), "", "and stitches")
	var grid: Grid = result["grid"]
	_dump(grid, "West Hall + East Hall")
	assert_eq(grid.width, 12, "two 6-wide sections make a 12-wide board")
	assert_eq(grid.rows, 4)

	# **The seam is crossed, not merely present.** A path from deep inside one section to deep
	# inside the other has to pass through the joined columns; asserting on reachability rather
	# than on adjacency is what makes this about the join and not about the geometry near it.
	var reachable: Dictionary = MapNavigability.flood(grid, Vector2i(1, 1))
	assert_true(
		reachable.has(Vector2i(10, 1)), "a unit can walk from the west section into the east one"
	)


## **Refused with a reason, and the reason names the section that refused.** `Sealed Bay` is the
## same size and the same shape as `East Hall`; only its edge metadata differs, which is what
## makes this a test of the metadata rather than of geometry.
func test_two_incompatible_sections_are_refused_with_a_reason() -> void:
	var west: SectionFile = _section(&"West Hall")
	var sealed: SectionFile = _section(&"Sealed Bay")
	if west == null or sealed == null:
		return

	assert_eq(sealed.width, 6, "sanity: it is the same size as the one that does join")
	assert_eq(sealed.rows, 4)

	var verdict: Dictionary = SectionSerializer.can_join(west, SectionEdge.SIDE_EAST, sealed)
	assert_false(verdict.ok, "an exterior facing edge refuses")
	gut.p("refused: %s" % verdict.reason)
	assert_true(str(verdict.reason).contains("Sealed Bay"), "and says which section refused")

	var result: Dictionary = SectionSerializer.stitch(west, SectionEdge.SIDE_EAST, sealed)
	assert_false(result.has("grid"), "and nothing is stitched")
	assert_eq(result["error"], verdict.reason, "the refusal is passed through unchanged")


## taskblock-53's asymmetric flood does not care how a board was produced. A stitched pair passes
## it or the join is wrong.
func test_the_joined_board_passes_the_navigability_invariant() -> void:
	var result: Dictionary = SectionSerializer.stitch(
		_section(&"West Hall"), SectionEdge.SIDE_EAST, _section(&"East Hall")
	)
	if not result.has("grid"):
		return
	var grid: Grid = result["grid"]
	# Flooded from an explicit cell rather than from spawn markers: sections carry none, because
	# where a squad starts is a property of a whole mission and not of a fragment.
	var stranded: Array[Vector2i] = MapNavigability.one_way_cells(grid, Vector2i(1, 1))
	gut.p("one-way cells on the stitched board: %d" % stranded.size())
	assert_eq(stranded, [] as Array[Vector2i], "nothing is walk-in-only across the seam")


## **A seeded bout on a stitched board is reproducible** — the same guarantee taskblock-53
## established for a loaded map, checked again for a board that was assembled rather than
## authored whole.
func test_a_seeded_bout_on_a_stitched_board_is_reproducible() -> void:
	var transcripts: Array[Array] = []
	for run: int in range(2):
		var result: Dictionary = SectionSerializer.stitch(
			_section(&"West Hall"), SectionEdge.SIDE_EAST, _section(&"East Hall")
		)
		if not result.has("grid"):
			return
		var grid: Grid = result["grid"]
		var unit: Unit = _walker(Vector2i(1, 1), grid)
		var state := CombatState.new(grid, [unit], 4242)
		state.assign_all_to_human()
		var sink := MemorySink.new()
		state.combat_log.add_sink(sink)

		state.force_current_unit(unit.id)
		var queue := ActionQueue.new(unit)
		# **The path includes the starting cell**, which is `MoveAction`'s own convention
		# (`test_move_action.gd`): a path is where the unit goes, beginning where it already is.
		var path: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)]
		var accepted: bool = queue.enqueue(MoveAction.new(unit, path), state)
		assert_true(accepted, "sanity: the move across the section is legal")
		state.resolve_until(queue)

		var lines: Array = []
		for event: LogEvent in sink.events:
			lines.append("%s|%s" % [event.kind, event.text])
		transcripts.append(lines)

	gut.p("%d events per run" % transcripts[0].size())
	assert_gt(transcripts[0].size(), 0, "sanity: the bout did something")
	assert_eq(transcripts[0], transcripts[1], "the same seed on a stitched board replays exactly")


func _walker(cell: Vector2i, grid: Grid) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.8, 1.0, 0.6))]
	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, 0)
	unit.height = UnitGeometry.true_height_for_cell(cell, grid)
	return unit
