extends GutTest

## taskblock-50 Pass E2: the shared map corpus.
##
## Two properties worth pinning, and a third that exists because writing this corpus
## immediately broke a test with it.

const WIDTH := 32
const ROWS := 24


func before_each() -> void:
	MapCorpus.forget()


func after_each() -> void:
	MapCorpus.forget()


## The point of the thing: asking twice generates once.
func test_a_second_read_generates_nothing() -> void:
	var first: Grid = MapCorpus.read(3, WIDTH, ROWS)
	var after_first: int = MapCorpus.generated

	var second: Grid = MapCorpus.read(3, WIDTH, ROWS)

	assert_eq(after_first, 1, "the first read generated exactly one map")
	assert_eq(MapCorpus.generated, after_first, "and the second generated nothing")
	assert_true(first == second, "because it is the same grid, not an equal one")


func test_a_different_seed_or_size_is_a_different_map() -> void:
	MapCorpus.read(3, WIDTH, ROWS)
	MapCorpus.read(4, WIDTH, ROWS)
	MapCorpus.read(3, 12, 10)

	assert_eq(MapCorpus.generated, 3, "seed and dimensions both key the cache")


## **`copy` is the escape hatch, and it must really be a copy.** A test that mutated a
## shared grid would corrupt every later reader and fail somewhere with no connection to
## its cause — the shared-fixture bug `BoutCorpus` refuses to risk at all.
func test_copy_hands_back_something_safe_to_mutate() -> void:
	var shared: Grid = MapCorpus.read(5, WIDTH, ROWS)
	var mine: Grid = MapCorpus.copy(5, WIDTH, ROWS)

	assert_false(mine == shared, "a copy is a different object")

	var cell: Vector2i = (
		shared.blockers.keys()[0] if not shared.blockers.is_empty() else Vector2i.ZERO
	)
	if not shared.blockers.is_empty():
		mine.blockers.erase(cell)
		assert_true(shared.blockers.has(cell), "mutating the copy left the shared grid alone")


## **The hazard itself, asserted rather than only warned about** (tb65 Pass C).
##
## The test above proves `copy()` is safe. This proves the other half — that `read()` is
## genuinely *not* — because tb65 pointed ten more files at this corpus and the failure mode
## they now share is worth having in front of a reader as an executable fact rather than as a
## sentence in a header.
##
## **What makes it nasty is the distance, not the mutation.** A file that erases one blocker
## from a `read()` grid corrupts every later reader of that seed, in a different script, and
## the red test is some unrelated sweep counting cover on a board it never touched. Nothing
## about that failure points back here. So the corpus takes the deliberate design position of
## sharing anyway — the sharing is the entire saving — and this is the receipt for that choice.
func test_a_mutation_through_read_is_visible_to_every_later_reader() -> void:
	var shared: Grid = MapCorpus.read(7, WIDTH, ROWS)
	assert_gt(shared.blockers.size(), 0, "sanity: the board has blockers to remove")
	var cell: Vector2i = shared.blockers.keys()[0]

	shared.blockers.erase(cell)

	var later: Grid = MapCorpus.read(7, WIDTH, ROWS)
	assert_false(
		later.blockers.has(cell),
		(
			"a mutation through read() reaches every later reader — which is why a mutating "
			+ "consumer must call copy(), and why this is asserted rather than assumed"
		)
	)
	assert_eq(MapCorpus.generated, 1, "and the corpus never notices, because it generated once")


## **The trap this corpus sets, pinned so nobody re-sets it.**
##
## `test_generate_is_seed_deterministic` compares two generations of one seed. Routed
## through `read()` it would receive the *same object twice* and pass unconditionally —
## the suite would keep a green test that had stopped checking anything. That happened
## during this pass's own conversion and was caught by reading the diff, not by a test,
## which is why there is now a test.
##
## Asserted as the property that makes it dangerous: `read` returns identity, so identity
## comparisons on it are meaningless and only `MapGen.generate` can answer them.
func test_read_returns_identity_so_determinism_checks_must_not_use_it() -> void:
	var shared_once: Grid = MapCorpus.read(9, WIDTH, ROWS)
	var shared_again: Grid = MapCorpus.read(9, WIDTH, ROWS)
	assert_true(
		shared_once == shared_again,
		"read is identity — a determinism test using it would compare a grid with itself"
	)
	var a: Grid = MapGen.generate(9, WIDTH, ROWS)
	var b: Grid = MapGen.generate(9, WIDTH, ROWS)
	assert_false(a == b, "the generator hands back genuinely separate grids to compare")


## A cache that quietly returned an empty grid would satisfy the counter assertions above
## while making every consumer's sweep vacuous.
func test_the_cached_map_is_a_real_generated_map() -> void:
	var grid: Grid = MapCorpus.read(11, WIDTH, ROWS)

	assert_eq(grid.width, WIDTH)
	assert_eq(grid.rows, ROWS)
	assert_gt(grid.placements().size(), 0, "it has floor")
	assert_gt(grid.blockers.size(), 0, "and walls")
