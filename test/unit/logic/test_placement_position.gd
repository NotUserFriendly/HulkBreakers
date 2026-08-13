extends GutTest

## taskblock-58 Pass B: **a placement has a position; a cell does not own it.**
##
## `Grid.surfaces` was `Dictionary[Vector2i, Array[Surface]]`, so a floor's position was its
## dictionary *key* — it could not exist except as something a cell held, and moving one meant
## delete-and-re-add. The store is now a flat `Array[Surface]`, each carrying its own `cell`, and
## the per-cell dictionary is an index derived from it.
##
## **This is a storage change with no intended behavioural effect**, so what is asserted here is
## mostly *sameness*: the accessor answers what it answered, the index never disagrees with the
## store, and a real authored map survives the round trip cell for cell.

const MAP_PATH := "res://data/maps/proving_ground.tres"


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## Every placement the store holds must be findable at the cell it says it is at, and every
## placement the index reports at a cell must agree that it is there. **Stated as a mutual
## check** rather than one direction: an index that has lost an entry and a store that has
## gained a ghost are different bugs and only the pair catches both.
func _assert_index_agrees_with_store(grid: Grid, context: String) -> void:
	var indexed := 0
	for cell: Vector2i in grid.occupied_cells():
		for surface: Surface in grid.surfaces_at(cell):
			indexed += 1
			assert_eq(
				surface.cell,
				cell,
				"%s: the index puts %s where it says it is" % [context, surface.part.id]
			)
			assert_true(
				grid.placements().has(surface),
				"%s: the index holds nothing the store does not" % context
			)
	assert_eq(
		indexed, grid.placements().size(), "%s: the index holds every placement, once" % context
	)
	for surface: Surface in grid.placements():
		assert_true(
			grid.surfaces_at(surface.cell).has(surface),
			"%s: every placement is reachable at its own cell" % context
		)


## The acceptance line, against a real authored board rather than a fixture: `surfaces_at()`
## behaves identically while a placement owns its position.
func test_an_authored_map_round_trips_cell_for_cell() -> void:
	var map: MapFile = load(MAP_PATH) as MapFile
	assert_not_null(map, "the committed map loads")
	var swapped: Dictionary = BoardSwap.swap_to_map(
		CombatState.new(GridFixture.flat(4, 4), []), map, true
	)
	assert_eq(swapped["error"], "", "and swaps in cleanly")
	var grid: Grid = swapped["grid"]

	_assert_index_agrees_with_store(grid, "proving_ground")

	# The authored file is the independent record of what the board should be — comparing the
	# grid against `MapFile.placements` checks the load rather than checking the grid against
	# itself, which is the trap CLAUDE.md's camera example is about.
	var authored_surfaces := 0
	for placement: MapPlacement in map.placements:
		if placement.kind == MapPlacement.KIND_SURFACE:
			authored_surfaces += 1
	assert_eq(
		grid.placements().size(),
		authored_surfaces,
		"every authored surface is one placement on the grid"
	)
	print(
		(
			"  proving_ground: %d placements over %d cells"
			% [grid.placements().size(), grid.occupied_cells().size()]
		)
	)


## The thing the old storage could not express. A position that is a dictionary key can only be
## changed by removing the entry and adding it back somewhere else — a different entry as far as
## anything holding a reference is concerned.
func test_moving_a_placement_updates_the_index_and_leaves_no_stale_entry() -> void:
	var grid: Grid = GridFixture.flat(6, 6)
	var moved: Surface = grid.surfaces_at(Vector2i(2, 2))[0]

	assert_true(grid.move_placement(moved, Vector2i(4, 4)), "the grid holds it, so it moves")

	assert_eq(moved.cell, Vector2i(4, 4), "the placement knows where it went")
	assert_false(grid.surfaces_at(Vector2i(2, 2)).has(moved), "and left nothing behind")
	assert_true(grid.surfaces_at(Vector2i(4, 4)).has(moved), "and is findable where it is")
	assert_true(grid.placements().has(moved), "it is the same object, not a replacement")
	_assert_index_agrees_with_store(grid, "after a move")


## A cell emptied of its last placement stops being an index entry at all, rather than becoming
## an empty array that `occupied_cells()` would then report as occupied.
func test_moving_the_last_placement_off_a_cell_empties_that_cell() -> void:
	var grid := Grid.new(4, 4)
	var only := Surface.new(DataLibrary.get_part(&"ship_floor"), 0.0)
	grid.add_surface(Vector2i(1, 1), only)

	grid.move_placement(only, Vector2i(3, 3))

	assert_true(grid.surfaces_at(Vector2i(1, 1)).is_empty())
	assert_false(grid.occupied_cells().has(Vector2i(1, 1)), "the emptied cell is not occupied")
	assert_true(grid.occupied_cells().has(Vector2i(3, 3)))


## A grid never told to hold this surface must not quietly adopt it — the refusal is what keeps
## `move_placement` from doubling as an undeclared `add_surface`.
func test_moving_a_placement_the_grid_does_not_hold_is_refused() -> void:
	var grid: Grid = GridFixture.flat(4, 4)
	var stranger := Surface.new(DataLibrary.get_part(&"ship_floor"), 0.0)

	assert_false(grid.move_placement(stranger, Vector2i(1, 1)), "it was never placed here")
	assert_false(grid.surfaces_at(Vector2i(1, 1)).has(stranger), "so it did not arrive")


## Per-cell order is what `Surface.first_walkable` resolves against and what `MapFile` documents
## as authored order, so the store's order and the index's order have to be the same order.
func test_the_index_preserves_placement_order_within_a_cell() -> void:
	var grid := Grid.new(4, 4)
	var floor_part: Part = DataLibrary.get_part(&"ship_floor")
	var lower := Surface.new(floor_part.duplicate(true), 0.0)
	var upper := Surface.new(floor_part.duplicate(true), 2.0)
	grid.add_surface(Vector2i(1, 1), lower)
	grid.add_surface(Vector2i(1, 1), upper)

	var at: Array[Surface] = grid.surfaces_at(Vector2i(1, 1))
	assert_eq(at.size(), 2)
	assert_eq(at[0], lower, "authored order, not reordered by the index")
	assert_eq(at[1], upper)


## `clear_surfaces` is `MapGen`'s idempotent-carving seam, so it has to leave the store and the
## index agreeing rather than only the one the caller happens to read next.
func test_clearing_a_cell_removes_its_placements_from_the_store_too() -> void:
	var grid: Grid = GridFixture.flat(5, 5)
	var before: int = grid.placements().size()

	grid.clear_surfaces(Vector2i(2, 2))

	assert_eq(grid.placements().size(), before - 1, "one placement left the store")
	assert_true(grid.surfaces_at(Vector2i(2, 2)).is_empty())
	_assert_index_agrees_with_store(grid, "after a clear")


## A TACTICS-time preview clone is a whole independent board (docs/09), which now means an
## independent store *and* an independent index — and in the same order, or `first_walkable`
## could answer differently on the preview than on the real grid.
func test_a_duplicated_grid_gets_its_own_store_and_index() -> void:
	var grid: Grid = GridFixture.flat(5, 5)
	GridFixture.place_floor(grid, Vector2i(2, 2), 2.0)

	var clone: Grid = grid.dup()

	assert_eq(clone.placements().size(), grid.placements().size())
	_assert_index_agrees_with_store(clone, "the clone")
	for i in range(grid.placements().size()):
		var original: Surface = grid.placements()[i]
		var copied: Surface = clone.placements()[i]
		assert_eq(copied.cell, original.cell, "same position, same order")
		assert_almost_eq(copied.height, original.height, 0.0001)
		assert_ne(copied.part, original.part, "and its own Part, never the original")

	clone.move_placement(clone.placements()[0], Vector2i(4, 4))
	assert_eq(
		grid.placements()[0].cell, Vector2i(0, 0), "moving the clone does not move the real board"
	)


## The five callers that used to walk the dictionary all wanted "every placement", and they now
## get it in one call. Asserted against the index so the flat walk and the cell-at-a-time walk
## are pinned to the same set — that equality is the whole reason the swap was safe.
func test_the_flat_walk_and_the_cell_walk_cover_the_same_set() -> void:
	var grid: Grid = GridFixture.enclosed_room(9, 9)
	GridFixture.place_floor(grid, Vector2i(4, 4), 2.0)

	var by_cell: Array[Surface] = []
	for cell: Vector2i in grid.occupied_cells():
		by_cell.append_array(grid.surfaces_at(cell))

	assert_eq(by_cell.size(), grid.placements().size(), "the same count")
	for surface: Surface in grid.placements():
		assert_true(by_cell.has(surface), "and the same members")


## **`GROUND` means "attaches to nothing"**, and the one-per-cell refusal survives as occupancy
## rather than as attachment — **at a height**, since taskblock-69 Pass D.
##
## **Renamed rather than deleted, which is the point of having pinned it.** taskblock-58 Pass B
## wrote this as `test_ground_still_refuses_a_second_placement_on_an_occupied_cell` precisely so
## the loosening would have to be a deliberate edit to a named test instead of a silent change of
## meaning. It is that edit. What it guards now is the refusal that remains: **same cell, same
## height, still refused.**
func test_ground_refuses_a_second_placement_at_the_same_height() -> void:
	var grid := Grid.new(4, 4)
	var floor_part: Part = DataLibrary.get_part(&"ship_floor")
	assert_true(GridPlacement.GROUND in floor_part.attaches_to, "ship_floor is the GROUND case")

	assert_not_null(GridPlacement.place(grid, Vector2i(1, 1), floor_part.duplicate(true), 0.0))
	assert_null(
		GridPlacement.place(grid, Vector2i(1, 1), floor_part.duplicate(true), 0.0),
		"a second floor at the same height is still the thing that is refused"
	)
	assert_eq(grid.surfaces_at(Vector2i(1, 1)).size(), 1, "and nothing was added")


## **The half taskblock-69 Pass D added: two decks in one cell.** *"Loosening it to 'at this
## height' is what lets a floor at 0.0 and a floor at 2.0 share a cell"* — two decks without
## borrowing a catwalk's side-attachment grammar to express them.
func test_ground_lets_two_placements_share_a_cell_at_different_heights() -> void:
	var grid := Grid.new(4, 4)
	var floor_part: Part = DataLibrary.get_part(&"ship_floor")

	assert_not_null(GridPlacement.place(grid, Vector2i(1, 1), floor_part.duplicate(true), 0.0))
	assert_not_null(
		GridPlacement.place(grid, Vector2i(1, 1), floor_part.duplicate(true), 2.0),
		"a second deck two units up is a placement the format can now express"
	)
	assert_eq(grid.surfaces_at(Vector2i(1, 1)).size(), 2, "and both are really there")

	# **No minimum separation, on the supervisor's call.** A floor at 0.0 and one at 0.1 is
	# authorable and is the author's problem — no constant, and no geometric overlap check.
	assert_not_null(
		GridPlacement.place(grid, Vector2i(2, 2), floor_part.duplicate(true), 0.0),
		"sanity: the first deck of a fresh cell"
	)
	assert_not_null(
		GridPlacement.place(grid, Vector2i(2, 2), floor_part.duplicate(true), 0.1),
		"a tenth of a unit apart is authorable, and nothing here has an opinion about it"
	)


## **A two-deck cell survives being saved.** The refusal `can_place` expresses is about *authoring*
## — `MapSerializer` writes through `Grid.add_surface` and never comes through `GridPlacement` at
## all — so this is the assertion that the loosening produced a board the format can carry rather
## than one only the grammar tolerates.
##
## The editor's own grammar check is asserted alongside, because that one **does** read
## `can_place`: before Pass D it would have reported the upper deck as a placement the loader
## refuses, which is a warning about a board that loads perfectly well.
func test_a_two_deck_cell_round_trips_and_the_editor_does_not_complain() -> void:
	var map := MapFile.new()
	map.width = 4
	map.rows = 4
	map.placements.append(
		MapPlacement.new(Vector2i(1, 1), MapPlacement.KIND_SURFACE, &"ship_floor", 0.0)
	)
	map.placements.append(
		MapPlacement.new(Vector2i(1, 1), MapPlacement.KIND_SURFACE, &"ship_floor", 2.0)
	)

	var loaded: Dictionary = MapSerializer.to_grid(map)
	assert_eq(loaded.get("error", ""), "", "a two-deck cell must load")
	var grid: Grid = loaded["grid"]
	assert_eq(grid.surfaces_at(Vector2i(1, 1)).size(), 2, "both decks arrived")

	var back: Dictionary = MapSerializer.to_grid(MapSerializer.to_map_file(grid, "two decks"))
	assert_eq(back.get("error", ""), "", "and must reload after being written out")
	var heights: Array[float] = []
	for surface: Surface in (back["grid"] as Grid).surfaces_at(Vector2i(1, 1)):
		heights.append(surface.height)
	heights.sort()
	assert_eq(heights.size(), 2, "two decks came back")
	assert_almost_eq(heights[0], 0.0, 0.0001, "the lower one")
	assert_almost_eq(heights[1], 2.0, 0.0001, "and the upper one, at the height it was authored")

	# **The grammar complaint specifically**, not every warning: a four-by-four test map has no
	# spawn markers either, and that one is true and unrelated.
	var controller := EditorController.new()
	controller.load_map(map)
	var grammar: Array[String] = []
	for line: String in controller.warnings():
		gut.p("  editor says: %s" % line)
		if "already has a surface" in line:
			grammar.append(line)
	assert_eq(grammar.size(), 0, "the editor must not call a two-deck cell an illegal placement")
