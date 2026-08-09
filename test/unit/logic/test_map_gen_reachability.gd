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

## The pinned reality at 40x30, **as `region cells @ top-left cell` per seed.**
##
## **This is a defect being held still, not an invariant being asserted.** Every line here is
## `BR60.01` reproducing; the list exists so the sweep is a red test the day the generator changes
## and a stable one until somebody fixes it. A line vanishing means the fix landed and the list
## should shrink; a line appearing means something else moved.
##
## Filled from the sweep's own output rather than hand-derived — see the test's `gut.p` dump.
##
## **Eight seeds of fifty, twelve regions, five of them 190+ cells.** At 32x24 the same sweep
## finds nothing, which is the entire content of *"the board size is the whole reason nobody has
## seen it."*
##
## **These numbers are not tb60's and should not be compared to them line for line.** tb60 counted
## *raised* regions with no reachable cell and reported twelve over **sixty** seeds, largest 235.
## This counts every **walkable** cell no spawn can reach, which is a superset: it includes flat
## pockets and it excludes nothing for being at ground level. The single-cell entries here are
## therefore **not** tb60's "cover on a lone raised cell" — a live blocker makes a cell unwalkable
## and `unreachable_cells` never sees it. A 1-cell entry here is a genuinely walkable tile that no
## unit can ever stand on.
const KNOWN_UNREACHABLE: Array[String] = [
	"seed 2: 232 cells @ (2, 1)",
	"seed 2: 1 cells @ (18, 10)",
	"seed 11: 210 cells @ (1, 3)",
	"seed 11: 1 cells @ (12, 1)",
	"seed 17: 3 cells @ (36, 1)",
	"seed 29: 192 cells @ (6, 1)",
	"seed 32: 1 cells @ (13, 8)",
	"seed 41: 209 cells @ (2, 2)",
	"seed 41: 1 cells @ (17, 2)",
	"seed 43: 197 cells @ (3, 3)",
	"seed 43: 6 cells @ (33, 2)",
	"seed 48: 1 cells @ (13, 17)",
]


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
			"unreachable ground at the played board size changed — a NEW entry is a regression, a "
			+ (
				"MISSING one means BR60.01 is fixed and this list should shrink:\n%s"
				% "\n".join(found)
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
