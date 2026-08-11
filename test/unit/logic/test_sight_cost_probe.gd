extends GutTest

## taskblock-58 Pass C: **the two numbers the pass is required to report.**
##
## `PLAN.md`'s own note: *"A per-cell array lookup is one index; asking geometry is a ray.
## `VisibilityField`'s bitboards exist precisely to make that affordable, so the shape is likely
## build the field from geometry rather than cast per query — but take the number before
## assuming it."* This is that number, taken rather than assumed — and it is what ruled out
## casting per query: `LoS.has_los` per cell measured **535 ms** per field build.
##
## Measured on this board at the Pass B commit and again after, same seed, same size:
##
## | | array-backed | geometry-backed |
## |---|---|---|
## | `VisibilityField.build` | 3 695 usec | 7 784 usec |
## | `field.allows` | 0.46 usec | 0.49 usec |
## | `LoS.has_los` | 3.8 usec | 662 usec |
##
## Field construction happens once per target per turn and roughly doubled, which is the half the
## taskblock calls affordable. **Per-query cost must stay a bit test**, and it did.
## `LoS.has_los` is two orders dearer because it stopped being an array lookup and became the real
## answer — and it is now asked by the handful of per-shot gates rather than per candidate cell,
## because `Cover` reads the field.
##
## A probe, not a gate: it prints, and asserts only the shape of the answer, because a wall-clock
## threshold on shared hardware fails for reasons that have nothing to do with the code.

const SAMPLES := 200


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _usec(runs: int, body: Callable) -> float:
	var start: int = Time.get_ticks_usec()
	for i in range(runs):
		body.call()
	return float(Time.get_ticks_usec() - start) / float(runs)


func test_field_build_and_per_query_cost() -> void:
	# The real generated board a bout is played on, at the size `BoutSetup` uses.
	var grid: Grid = MapCorpus.read(4242, 32, 24)
	var target := Vector2i(16, 12)
	gut.p(
		(
			"board: %dx%d, %d blockers, %d placements"
			% [grid.width, grid.rows, grid.blockers.size(), grid.placements().size()]
		)
	)

	var build_usec: float = _usec(3, func() -> void: VisibilityField.build(grid, target))
	var field: VisibilityField = VisibilityField.build(grid, target)
	var cell := Vector2i(4, 4)
	var query_usec: float = _usec(SAMPLES, func() -> void: field.allows(cell))
	var los_usec: float = _usec(SAMPLES, func() -> void: LoS.has_los(grid, target, cell))

	gut.p("  VisibilityField.build       %9.1f usec   (once per target per turn)" % build_usec)
	gut.p(
		(
			"  field.allows                %9.4f usec   (per candidate — must stay a bit test)"
			% query_usec
		)
	)
	gut.p("  LoS.has_los                 %9.1f usec   (one geometric sight line)" % los_usec)
	gut.p(
		(
			"  a field cast per cell would be %9.1f ms   (the shape this measurement ruled out)"
			% (los_usec * float(grid.width * grid.rows) / 1000.0)
		)
	)

	# **The per-query claim, stated as a ratio rather than as a wall-clock bound.** A bit test
	# against a packed array is orders below a ray march; if reading the field ever became a
	# march again, this is the assertion that would notice.
	assert_lt(
		query_usec,
		los_usec / 10.0,
		(
			"a field read must stay a bit test, not become a ray march (%f vs %f usec)"
			% [query_usec, los_usec]
		)
	)
	assert_gt(build_usec, 0.0, "the build did something")
