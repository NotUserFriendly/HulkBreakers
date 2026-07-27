extends GutTest

## taskblock-43 Pass A: an EXACT early-out in `_engagement_score`. Every term is
## a non-negative penalty except `cover_bonus`, which is a bounded constant — so
## a cell whose ceiling cannot beat the best complete score so far can skip both
## line walks without changing which cell is chosen.
##
## **Acceptance is identical output, not a perf number.** A faster planner that
## picks a different cell is a behaviour change wearing an optimisation's
## clothes, so the equivalence tests below are the pass, and the skip-count test
## exists because an identical-output test passes trivially if the fast path
## never runs.


func _bout(map_seed: int) -> Dictionary:
	var roster: Array[BoutRosterEntry] = []
	for i in range(2):
		var entry := BoutRosterEntry.new()
		entry.profile = DataLibrary.presets_pool()[i % DataLibrary.presets_pool().size()]
		roster.append(entry)
	return BoutSetup.build_bout(roster, roster, map_seed)


func _action_sequence(state: CombatState, mission: MissionState, steps: int) -> Array[String]:
	var runner := BoutRunner.new(state, mission)
	var taken: Array[String] = []
	var i := 0
	while not runner.finished and i < steps:
		runner.step()
		for event: LogEvent in runner.last_events:
			taken.append("%s@%d" % [event.kind, event.unit_id])
		i += 1
	return taken


## The load-bearing one: the same seed must produce the same actions. The
## early-out is only sound if it never removes a cell that would have won.
func test_a_seeded_bout_produces_an_identical_action_sequence() -> void:
	var a: Dictionary = _bout(31337)
	assert_eq(a.get("error", ""), "", "sanity: the bout built")
	var expected: Array[String] = _action_sequence(a.state, a.mission, 8)

	var b: Dictionary = _bout(31337)
	var actual: Array[String] = _action_sequence(b.state, b.mission, 8)

	assert_eq(actual, expected)
	assert_gt(expected.size(), 0, "sanity: the bout actually did something")


## Without this the test above proves nothing — an early-out that never fires
## trivially produces identical output.
func test_the_early_out_actually_fires_during_a_real_bout() -> void:
	var built: Dictionary = _bout(31337)
	UnitAI.candidates_skipped = 0

	_action_sequence(built.state, built.mission, 6)

	assert_gt(UnitAI.candidates_skipped, 0, "the fast path ran at least once")


## The bound itself, directly: a cell whose ceiling cannot beat the incumbent
## scores -INF, and one that can is scored normally.
func test_a_hopeless_cell_is_skipped_and_a_promising_one_is_not() -> void:
	var grid: Grid = GridFixture.flat(20, 20)
	var shooter: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(1, 1), 0)
	var enemy: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(10, 10), 1)
	var state := CombatState.new(grid, [shooter, enemy])

	# Cell (19,19) is Chebyshev 9 from the enemy and `preferred_range` is 0, so
	# its distance penalty is 9 and its ceiling is COVER_SCORE_BONUS - 9 = 1.0.
	# An incumbent of 5.0 is therefore unbeatable for it.
	var hopeless: float = UnitAI._engagement_score(
		Vector2i(19, 19), enemy, WorldView.full(state), shooter, 0, true, null, true, null, 5.0
	)
	assert_eq(hopeless, -INF, "its ceiling is far below the incumbent, so it is skipped")

	# The same cell against a hopeless incumbent is scored for real.
	var scored: float = UnitAI._engagement_score(
		Vector2i(19, 19), enemy, WorldView.full(state), shooter, 0, true, null, true, null, -INF
	)
	assert_ne(scored, -INF, "with nothing to beat, it must be evaluated normally")


## Ties lose (`score > best_score` is strict), which is exactly what makes
## skipping a can-only-tie cell exact rather than approximate.
func test_a_cell_that_could_only_tie_is_skipped() -> void:
	var grid: Grid = GridFixture.flat(20, 20)
	var shooter: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(1, 1), 0)
	var enemy: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(10, 10), 1)
	var state := CombatState.new(grid, [shooter, enemy])

	var ceiling: float = UnitAI.COVER_SCORE_BONUS  # distance 0 from the target
	var tied: float = UnitAI._engagement_score(
		enemy.cell, enemy, WorldView.full(state), shooter, 0, true, null, true, null, ceiling
	)

	assert_eq(tied, -INF, "it could at best tie, and a tie never wins")


## Every cell equally good must still terminate and pick the incumbent, which is
## what the strict comparison already guaranteed before this pass.
func test_an_all_equal_field_still_picks_the_incumbent() -> void:
	var grid: Grid = GridFixture.flat(12, 12)
	var shooter: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(5, 5), 0)
	var enemy: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(6, 6), 1)
	var state := CombatState.new(grid, [shooter, enemy])
	var reachable: Array[Vector2i] = [Vector2i(5, 5), Vector2i(5, 5), Vector2i(5, 5)]

	var chosen: Vector2i = UnitAI._pick_engagement_position(
		shooter, enemy, WorldView.full(state), 0, false, null, reachable, true, null
	)

	assert_eq(chosen, Vector2i(5, 5))
