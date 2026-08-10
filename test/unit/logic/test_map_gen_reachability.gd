extends GutTest

## `BR60.01` — **the sweep that runs at the size the game actually plays.**
##
## `test_map_gen.gd` sweeps 32x24, which is `BoutSetup`'s board. `BattleScene` plays **40x30**,
## and the defect reproduces there every run while at 32x24 it surfaces only by accident — tb60
## measured it appearing for exactly one build and vanishing again when an unrelated change
## happened to hand a region an accidental way in. *"A sweep measuring a smaller board than the
## game plays on is the reason a defect this size has gone unseen."*
##
## So this file exists rather than a second sweep bolted onto `test_map_gen.gd`: the questions are
## the same, the board is not, and the maps cannot be shared with a corpus keyed at another size.
##
## ## What is being asked that `MapNavigability.stranding_cells` cannot ask
##
## `one_way_cells` reports cells in the outward flood that are missing from the return flood —
## *"you can get in and not out."* **A region you can never get into is not in the outward flood**,
## so `stranding_cells` returns empty on a board carrying hundreds of cells of unreachable raised
## ground. `MapNavigability.unreachable_cells` is the complement, and it is what these tests read.

const BOUT_WIDTH := BattleScene.GRID_WIDTH
const BOUT_HEIGHT := BattleScene.GRID_HEIGHT
## Matches `test_map_gen.gd`'s own sweep width so the two boards are compared over the same seeds.
const SEED_COUNT := 50

## **`BR60.01` is repaired, and this is the invariant that replaces the defect it pinned.**
##
## Until taskblock-63 this held a list of twelve reproducing regions across eight of fifty
## seeds, five of them 190+ cells — *"a defect being held still, not an invariant being
## asserted"*, with the list existing so the sweep would go red the day the generator moved.
## **The list is empty now**, which is a stronger thing to assert than any list was: every
## generated map at the size the game plays has no walkable ground a spawn cannot reach.
##
## Kept as a named constant rather than collapsed into a bare `assert_eq(found, [])` for two
## reasons. The failure message below reads off it, and — the real one — **an entry appearing
## here should look like a decision somebody made**, not like a literal being edited. The day
## a generator change reintroduces unreachable ground, the honest options are to fix it or to
## write the region down and say why, and that second option should cost a sentence.
##
## **Three repairs got it here**, all in `MapGen` and all judged against this sweep:
## a route stood into every region with a lip to build against, a ladder that serves descent
## as well as ascent (a +4 shelf is otherwise impassable in *both* directions), and sealing
## the walkable pockets the wall ring leaves inside solid rock.
const KNOWN_UNREACHABLE: Array[String] = []


func _sweep() -> Array[String]:
	var found: Array[String] = []
	for map_seed: int in range(SEED_COUNT):
		var grid: Grid = MapCorpus.read(map_seed, BOUT_WIDTH, BOUT_HEIGHT)
		for region: Array in MapNavigability.unreachable_regions(grid):
			var cells: Array[Vector2i] = region
			found.append("seed %d: %d cells @ %s" % [map_seed, cells.size(), cells[0]])
	return found


## The sweep itself. Pinned as **equality** rather than `is_empty()` for the reason
## `test_map_gen.gd`'s own list is: a new entry is a regression *or* another glimpse of
## `BR60.01`, and either wants a human reading it rather than a silently-passing check.
func test_no_walkable_ground_is_unreachable_from_every_spawn_at_the_bout_board_size() -> void:
	var found: Array[String] = _sweep()
	gut.p("unreachable regions at %dx%d over %d seeds:" % [BOUT_WIDTH, BOUT_HEIGHT, SEED_COUNT])
	for line: String in found:
		gut.p("  " + line)
	assert_eq(
		found,
		KNOWN_UNREACHABLE,
		(
			"unreachable ground at the played board size changed — every entry here is a "
			+ (
				"region of walkable ground no spawn can reach, which BR60.01's repair is "
				+ "supposed to leave none of:\n%s" % "\n".join(found)
			)
		)
	)


## **`BR60.01`'s own stated next step: confirm the anchor theory before fixing anything.**
##
## The entry's suspicion is that `_repair_stranded_elevation` floods from `rooms[0]`'s own centre
## and flattens what it cannot reach — so if that anchor sits *inside* a raised region, everything
## connected to the anchor survives the flatten while having no route from the spawn zones, which
## `_place_spawn_zones` only chooses afterwards. **The theory predicts the defect correlates with
## `rooms[0]` being raised.**
##
## This test measures the correlation and reports it. It does not assert a correlation coefficient
## — that would be pinning a number nobody chose — it asserts only that the measurement ran over
## every seed, and prints the contingency table for a human to read.
##
## ## The measured answer, tb61 Pass E2: **strongly supported, and not sufficient**
##
## |               | defective | clean |
## |---------------|-----------|-------|
## | anchor raised | **7**     | 12    |
## | anchor flat   | **1**     | 30    |
##
## A raised anchor is close to **necessary** — seven of the eight defective boards have one,
## against a base rate of 19 in 50 — and nowhere near **sufficient**: twelve boards have a raised
## anchor and are clean. **So the anchor explains which boards are at risk, not which boards
## break**, and one seed breaks with a flat anchor, so it is not the only route in either.
## Re-anchoring the repair at the spawn zones would therefore be a fix aimed at a strong
## correlate rather than at a confirmed cause. Recorded so the next attempt starts from the
## table instead of re-running it.
func test_the_rooms_zero_anchor_theory_is_measured_not_assumed() -> void:
	var raised_anchor_defective: int = 0
	var raised_anchor_clean: int = 0
	var flat_anchor_defective: int = 0
	var flat_anchor_clean: int = 0

	for map_seed: int in range(SEED_COUNT):
		var grid: Grid = MapCorpus.read(map_seed, BOUT_WIDTH, BOUT_HEIGHT)
		var anchor_raised: bool = _anchor_is_raised(map_seed, grid)
		var defective: bool = not MapNavigability.unreachable_cells(grid).is_empty()
		if anchor_raised and defective:
			raised_anchor_defective += 1
		elif anchor_raised:
			raised_anchor_clean += 1
		elif defective:
			flat_anchor_defective += 1
		else:
			flat_anchor_clean += 1

	gut.p("rooms[0] anchor raised, board defective: %d" % raised_anchor_defective)
	gut.p("rooms[0] anchor raised, board clean:     %d" % raised_anchor_clean)
	gut.p("rooms[0] anchor flat,   board defective: %d" % flat_anchor_defective)
	gut.p("rooms[0] anchor flat,   board clean:     %d" % flat_anchor_clean)

	var total: int = (
		raised_anchor_defective + raised_anchor_clean + flat_anchor_defective + flat_anchor_clean
	)
	assert_eq(total, SEED_COUNT, "every seed must land in exactly one cell of the table")


## The height under `_repair_stranded_elevation`'s own anchor — `rooms[0].position + size / 2` —
## read off the FINISHED grid. **That is an approximation of the theory, not the theory itself**:
## the repair reads the scratch mid-generation and the rooms list is not exposed by `generate()`,
## so this re-derives the room split from the same seed to find `rooms[0]`.
func _anchor_is_raised(map_seed: int, grid: Grid) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var probe_grid := Grid.new(BOUT_WIDTH, BOUT_HEIGHT)
	var scratch := MapGenScratch.new(BOUT_WIDTH, BOUT_HEIGHT)
	var rooms: Array[Rect2i] = []
	MapGen._split_and_carve(
		probe_grid, scratch, Rect2i(Vector2i.ZERO, Vector2i(BOUT_WIDTH, BOUT_HEIGHT)), rng, rooms
	)
	if rooms.is_empty():
		return false
	@warning_ignore("integer_division")
	var anchor: Vector2i = rooms[0].position + rooms[0].size / 2
	return UnitGeometry.true_height_for_cell(anchor, grid) > 0.0
