extends GutTest

## taskblock-50 Pass C: the scripted corpus.
##
## Two properties, and the second is the one that makes it worth having: a scripted bout
## resolves identically every run, and **it never invokes the planner**. A corpus that
## quietly planned would be slower than what it replaced while presenting as the cheap
## option, and its determinism would depend on the AI it exists to exclude.

const STEPS: Array[Array] = [
	[0, Vector2i(6, 6)],
	[1, Vector2i(9, 9)],
	[0, Vector2i(8, 4)],
	[1, Vector2i(7, 11)],
]


## taskblock-47 Pass C: this file builds bouts, so the fast gate skips it.
##
## **Untyped on purpose, against this project's static-typing rule.** GUT declares
## `func should_skip_script():` with no return type, and Godot treats an override that
## adds `-> Variant` as a signature mismatch — the script then fails to parse and GUT
## reports it as "does not extend GutTest", which is a long way from the real cause.
func should_skip_script():
	return SuiteTier.skip_if_fast()


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## **The board is a real one.** If this ever starts returning an error the whole corpus is
## worthless, so it is checked here rather than left to surface as a confusing failure in
## whichever test happens to read it first.
func test_the_corpus_builds_a_real_board() -> void:
	var built: Dictionary = ScriptedCorpus.fresh()

	assert_eq(String(built.get("error", "")), "", "the fixture built")
	var state: CombatState = built["state"]
	assert_eq(ScriptedCorpus.units(state).size(), ScriptedCorpus.SQUAD_SIZE * 2, "both squads")
	assert_true(state.all_squads_assigned(), "and nobody is left unassigned to drive itself")


## The load-bearing one. `AiPlanner.plans` is the same counter the suite profile reports,
## so "no planning" here means what it means in the budget.
func test_a_scripted_bout_never_invokes_the_planner() -> void:
	var before: int = AiPlanner.plans

	var built: Dictionary = ScriptedCorpus.fresh()
	var events: Array[LogEvent] = ScriptedCorpus.drive(built, STEPS)

	assert_gt(events.size(), 0, "sanity: it actually resolved something")
	assert_eq(AiPlanner.plans, before, "a scripted bout plans nothing at all")


## **The companion assertion.** The check above would pass just as well against a corpus
## that resolved nothing — so this proves the counter it reads does move when something
## really does plan, on the same board, in the same test.
func test_the_planner_counter_would_notice_if_it_did_plan() -> void:
	var built: Dictionary = ScriptedCorpus.fresh()
	var state: CombatState = built["state"]
	var before: int = AiPlanner.plans

	# **Both squads**, not just one: `BoutRunner.step()` is a no-op while the current unit
	# belongs to a human squad, so handing only squad 1 to the AI proved nothing and this
	# assertion sat green-by-vacuity until it was pointed at the unit actually up.
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var runner := BoutRunner.new(state, built["mission"], 2)
	await runner.step()

	assert_gt(AiPlanner.plans, before, "the counter moves when a planner actually runs")


func test_the_same_script_resolves_identically_every_run() -> void:
	var first: String = ScriptedCorpus.reduce(ScriptedCorpus.drive(ScriptedCorpus.fresh(), STEPS))
	var second: String = ScriptedCorpus.reduce(ScriptedCorpus.drive(ScriptedCorpus.fresh(), STEPS))

	assert_eq(first, second, "the same script on the same seed is the same stream")


## A stream with nothing in it would satisfy every assertion above. This is the same
## guard `test_tb38_flat_bout_guard.gd` learned to keep after its own scripted rewrite.
func test_the_script_actually_moves_and_ends_turns() -> void:
	var reduced: String = ScriptedCorpus.reduce(ScriptedCorpus.drive(ScriptedCorpus.fresh(), STEPS))

	gut.p("scripted bout emitted %d line(s)" % reduced.split("\n").size())
	assert_true(reduced.contains("move"), "the units moved")
	assert_true(reduced.contains("faced"), "and faced as they went")
	assert_true(reduced.contains("turn_end"), "and their turns ended")


## A different seed must be a different board, or "preset seed" is hiding the fact that
## the fixture ignores it — which would make every reader's board the same by accident
## rather than by design.
func test_a_different_seed_is_a_different_board() -> void:
	var a: String = ScriptedCorpus.reduce(ScriptedCorpus.drive(ScriptedCorpus.fresh(), STEPS))
	var b: String = ScriptedCorpus.reduce(
		ScriptedCorpus.drive(ScriptedCorpus.fresh(ScriptedCorpus.MAP_SEED + 1), STEPS)
	)

	assert_ne(a, b, "the seed reaches the board")
