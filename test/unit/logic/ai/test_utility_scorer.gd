extends GutTest

## taskblock-45 Pass A: the scoring maths.
##
## Two properties carry the whole model and are tested directly rather than
## through behaviour, because behaviour would only show them indirectly and much
## later: **a single zero vetoes**, and **the compensation factor makes actions
## with different numbers of considerations comparable**. The second is the one
## that would otherwise be mistaken for a balance problem for weeks — it is
## arithmetic, not tuning, and no re-weighting can fix it.


func _curve(shape: StringName = ResponseCurve.LINEAR) -> ResponseCurve:
	return ResponseCurve.new(shape)


func _action(id: StringName, inputs: Array[StringName], weight: float = 1.0) -> UtilityActionDef:
	var action := UtilityActionDef.new(id, &"shoot")
	action.base_weight = weight
	var considerations: Array[ConsiderationDef] = []
	for input_id: StringName in inputs:
		considerations.append(ConsiderationDef.new(input_id, _curve()))
	action.considerations = considerations
	return action


# --- the compensation factor -------------------------------------------------


## **The property the factor actually has**, which is not the one I first wrote
## down. Two actions of equal quality still do not score *identically* when one
## is described in more detail — the compensation shrinks that bias rather than
## erasing it. Asserted as the shrink, with the uncompensated arithmetic below as
## the control, because pinning a false equality would have been a test that
## agreed with a wrong comment.
func test_the_compensation_factor_substantially_shrinks_the_penalty_for_detail() -> void:
	var two: UtilityActionDef = _action(&"two", [&"a", &"b"])
	var five: UtilityActionDef = _action(&"five", [&"a", &"b", &"c", &"d", &"e"])
	var inputs := {&"a": 0.8, &"b": 0.8, &"c": 0.8, &"d": 0.8, &"e": 0.8}

	var two_score: float = UtilityScorer.score(two, inputs, null)
	var five_score: float = UtilityScorer.score(five, inputs, null)
	var retained: float = five_score / two_score
	var uncompensated_retained: float = pow(0.8, 5) / pow(0.8, 2)

	assert_almost_eq(uncompensated_retained, 0.51, 0.01, "control: 51% retained without the factor")
	assert_gt(retained, 0.85, "with it, the five-input action keeps ~89%")
	assert_lt(retained, 1.0, "and the residual bias is real rather than pretended away")
	assert_gt(five_score, 0.5, "neither is crushed toward zero by its own detail")


## The uncompensated arithmetic, asserted directly, so the test above is
## demonstrably guarding against something real rather than against nothing.
func test_the_uncompensated_product_really_would_punish_detail() -> void:
	assert_almost_eq(pow(0.8, 2), 0.64, 0.001)
	assert_almost_eq(pow(0.8, 5), 0.328, 0.001)
	assert_lt(pow(0.8, 5), pow(0.8, 2) * 0.6, "the gap is large enough to change every decision")


## A single consideration must pass through untouched — `modification` is zero at
## `n == 1`, so the factor cannot quietly alter the simplest case.
func test_a_single_consideration_is_not_modified() -> void:
	var one: UtilityActionDef = _action(&"one", [&"a"])

	assert_almost_eq(UtilityScorer.score(one, {&"a": 0.4}, null), 0.4, 0.0001)


# --- the veto ----------------------------------------------------------------


## **A zero anywhere kills the action outright**, which is the difference between
## "unreachable, so no" and "unreachable, so slightly less appealing". This is
## what a sum would not give you.
func test_a_single_zero_consideration_vetoes_regardless_of_the_others() -> void:
	var action: UtilityActionDef = _action(&"act", [&"a", &"b", &"c"])

	var strong: float = UtilityScorer.score(action, {&"a": 1.0, &"b": 1.0, &"c": 1.0}, null)
	var vetoed: float = UtilityScorer.score(action, {&"a": 1.0, &"b": 0.0, &"c": 1.0}, null)

	assert_gt(strong, 0.0, "sanity: it scores when nothing vetoes")
	assert_eq(vetoed, 0.0, "one zero is enough, however good the rest are")


## The veto has to survive the compensation factor — that is precisely why this
## formula was chosen over a `pow(x, 1/n)` normalisation, which would soften a
## zero into a small positive number.
func test_the_compensation_factor_does_not_soften_a_veto() -> void:
	var many: UtilityActionDef = _action(&"many", [&"a", &"b", &"c", &"d", &"e", &"f"])
	var inputs := {&"a": 0.9, &"b": 0.9, &"c": 0.9, &"d": 0.9, &"e": 0.9, &"f": 0.0}

	assert_eq(UtilityScorer.score(many, inputs, null), 0.0)


## A missing input reads as 0.0 and therefore vetoes — deliberately loud. A typo
## that merely lowered a score would be nearly impossible to spot; one that stops
## the action being chosen shows up immediately.
func test_an_unknown_input_id_vetoes_rather_than_scoring_neutrally() -> void:
	var action: UtilityActionDef = _action(&"act", [&"typo_here"])

	assert_eq(UtilityScorer.score(action, {&"the_real_id": 1.0}, null), 0.0)


# --- preconditions are separate from considerations --------------------------


func test_preconditions_gate_the_action_independently_of_its_score() -> void:
	var action: UtilityActionDef = _action(&"act", [&"a"])
	action.preconditions = [&"has_weapon"]

	assert_false(UtilityScorer.preconditions_hold(action, {}), "absent reads as false")
	assert_false(UtilityScorer.preconditions_hold(action, {&"has_weapon": false}))
	assert_true(UtilityScorer.preconditions_hold(action, {&"has_weapon": true}))


func test_every_precondition_must_hold_not_merely_one() -> void:
	var action: UtilityActionDef = _action(&"act", [&"a"])
	action.preconditions = [&"armed", &"in_range"]

	assert_false(UtilityScorer.preconditions_hold(action, {&"armed": true, &"in_range": false}))
	assert_true(UtilityScorer.preconditions_hold(action, {&"armed": true, &"in_range": true}))


# --- the tiebreak ------------------------------------------------------------


## taskblock-43's Pass B test failed because two cells scored identically and
## iteration order silently picked the winner. On open ground a whole arc sits at
## exactly the standoff distance, so ties are common rather than exotic.
func test_a_tie_is_broken_by_lowest_index() -> void:
	var scores: Array[float] = [0.5, 0.5, 0.5]

	assert_eq(UtilityScorer.best_index(scores), 0)


## The tiebreak has to be a property of the rule, not of the order the candidates
## happened to arrive in — otherwise a different candidate source silently
## changes decisions.
func test_the_tiebreak_is_stable_across_a_reordered_candidate_source() -> void:
	var ascending: Array[float] = [0.2, 0.9, 0.9, 0.4]
	var reordered: Array[float] = [0.4, 0.9, 0.9, 0.2]

	assert_eq(UtilityScorer.best_index(ascending), 1)
	assert_eq(UtilityScorer.best_index(reordered), 1, "same rule, same winning position")


func test_repeated_runs_agree() -> void:
	var scores: Array[float] = [0.31, 0.77, 0.77, 0.12]
	var first: int = UtilityScorer.best_index(scores)

	for _i in range(20):
		assert_eq(UtilityScorer.best_index(scores), first)


## Nothing above the veto floor means genuinely no positive-utility action — a
## state the old planner could not express at all, and what `PLAN.md`'s *Panic*
## item eventually answers.
func test_an_all_vetoed_field_selects_nothing() -> void:
	assert_eq(UtilityScorer.best_index([0.0, 0.0] as Array[float]), -1)
	assert_eq(UtilityScorer.best_index([] as Array[float]), -1)


func test_the_margin_separates_a_landslide_from_a_near_tie() -> void:
	assert_almost_eq(UtilityScorer.margin([0.9, 0.1] as Array[float]), 0.8, 0.0001)
	assert_almost_eq(UtilityScorer.margin([0.9, 0.89] as Array[float]), 0.01, 0.0001)
	assert_almost_eq(UtilityScorer.margin([0.7] as Array[float]), 0.7, 0.0001)


# --- the log is sufficient to reproduce a score by hand ----------------------


## **The pass's own acceptance for the decision log.** A scorer produces a number
## and you reconstruct why afterward, or you cannot — BR26.02 sat in exactly that
## hole for three passes. So the trace must carry enough to redo the arithmetic
## without re-running anything.
func test_a_traced_score_can_be_reproduced_by_hand_from_its_entries() -> void:
	var action: UtilityActionDef = _action(&"act", [&"a", &"b", &"c"], 2.0)
	var inputs := {&"a": 0.6, &"b": 0.8, &"c": 0.5}
	var trace: Array = []

	var scored: float = UtilityScorer.score(action, inputs, null, trace)

	assert_eq(trace.size(), 3, "one entry per consideration")
	var rebuilt: float = 1.0
	for entry: Dictionary in trace:
		rebuilt *= float(entry["compensated"])
	rebuilt *= action.base_weight

	assert_almost_eq(rebuilt, scored, 0.0001, "the log alone reproduces the score")


## A veto is invisible in a product, so "which consideration returned zero" has
## to be answerable from the trace — which means every consideration is evaluated
## even after a zero appears, rather than short-circuiting.
func test_the_trace_names_which_consideration_vetoed() -> void:
	var action: UtilityActionDef = _action(&"act", [&"a", &"b", &"c"])
	var trace: Array = []

	UtilityScorer.score(action, {&"a": 1.0, &"b": 0.0, &"c": 1.0}, null, trace)

	assert_eq(trace.size(), 3, "no short-circuit — every consideration is recorded")
	assert_eq(trace[1]["input_id"], &"b")
	assert_eq(trace[1]["compensated"], 0.0, "and the culprit is identifiable")
	assert_gt(trace[2]["compensated"], 0.0, "including the ones after it")


func test_the_trace_carries_the_raw_input_alongside_the_curve_output() -> void:
	var action := UtilityActionDef.new(&"act", &"shoot")
	action.considerations = [ConsiderationDef.new(&"a", _curve(ResponseCurve.QUADRATIC))]
	var trace: Array = []

	UtilityScorer.score(action, {&"a": 0.5}, null, trace)

	assert_almost_eq(float(trace[0]["raw"]), 0.5, 0.0001, "what was asked")
	assert_almost_eq(float(trace[0]["curved"]), 0.25, 0.0001, "and what the curve made of it")


# --- profiles are weights, never code paths ----------------------------------


func test_a_profile_scales_an_action_without_changing_the_scorer() -> void:
	var action: UtilityActionDef = _action(&"aggressive_act", [&"a"])
	var keen := UtilityProfile.new(&"keen")
	keen.action_weights = {&"aggressive_act": 2.0}
	var shy := UtilityProfile.new(&"shy")
	shy.action_weights = {&"aggressive_act": 0.25}

	var neutral: float = UtilityScorer.score(action, {&"a": 0.5}, null)

	assert_almost_eq(UtilityScorer.score(action, {&"a": 0.5}, keen), neutral * 2.0, 0.0001)
	assert_almost_eq(UtilityScorer.score(action, {&"a": 0.5}, shy), neutral * 0.25, 0.0001)


## Consideration weights are shared across every action that reads the input,
## which is what makes considerations shared rather than duplicated per action.
func test_a_profile_scales_one_consideration_everywhere_it_appears() -> void:
	var first: UtilityActionDef = _action(&"first", [&"threat"])
	var second: UtilityActionDef = _action(&"second", [&"threat"])
	var cautious := UtilityProfile.new(&"cautious")
	cautious.consideration_weights = {&"threat": 0.5}

	var a: float = UtilityScorer.score(first, {&"threat": 0.8}, cautious)
	var b: float = UtilityScorer.score(second, {&"threat": 0.8}, cautious)

	assert_almost_eq(a, 0.4, 0.0001)
	assert_almost_eq(b, a, 0.0001, "one weight, both actions")


func test_an_empty_profile_is_fully_neutral() -> void:
	var action: UtilityActionDef = _action(&"act", [&"a"])

	assert_almost_eq(
		UtilityScorer.score(action, {&"a": 0.7}, UtilityProfile.new(&"blank")),
		UtilityScorer.score(action, {&"a": 0.7}, null),
		0.0001
	)


# --- the decision log carries what a reconstruction needs --------------------


func _logged_decision(state: CombatState, unit: Unit, candidates: Array, winner: int) -> LogEvent:
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	AiDecisionLog.emit_utility_decision(
		state, unit, candidates, winner, &"TRAINED", &"cautious", [7, 9]
	)
	state.combat_log.remove_sink(sink)
	for event: LogEvent in sink.events_of_kind(&"ai_utility_decision"):
		return event
	return null


func _scored(label: String, action: UtilityActionDef, inputs: Dictionary) -> Dictionary:
	var trace: Array = []
	var score: float = UtilityScorer.score(action, inputs, null, trace)
	return {"label": label, "action_id": action.id, "score": score, "offered": true, "trace": trace}


## "Why not the other one" is the question actually asked, and the winner alone
## cannot answer it — so every candidate is recorded, not just the chosen one.
func test_the_log_records_every_candidate_not_only_the_winner() -> void:
	var grid: Grid = GridFixture.flat(8, 8)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(1, 1), 0)
	var state := CombatState.new(grid, [unit])
	var action: UtilityActionDef = _action(&"shoot_it", [&"a"])
	var candidates: Array = [
		_scored("cell(2,2)", action, {&"a": 0.9}), _scored("cell(3,3)", action, {&"a": 0.2})
	]

	var event: LogEvent = _logged_decision(state, unit, candidates, 0)

	assert_not_null(event)
	assert_eq((event.data["candidates"] as Array).size(), 2, "both, so the loser is inspectable")
	assert_eq(event.data["winner"], "cell(2,2)")


## Tier, profile and the visible set together are what tell a scoring bug apart
## from a decision that is correct given a degraded world model.
func test_the_log_records_the_tier_the_profile_and_what_was_visible() -> void:
	var grid: Grid = GridFixture.flat(8, 8)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(1, 1), 0)
	var state := CombatState.new(grid, [unit])
	var action: UtilityActionDef = _action(&"act", [&"a"])

	var event: LogEvent = _logged_decision(state, unit, [_scored("only", action, {&"a": 0.5})], 0)

	assert_eq(event.data["tier"], &"TRAINED")
	assert_eq(event.data["profile"], &"cautious")
	assert_eq(event.data["visible_unit_ids"], [7, 9])


## A landslide and a near-tie want reading very differently, and the winning
## score alone cannot distinguish them.
func test_the_log_records_the_margin_over_second_place() -> void:
	var grid: Grid = GridFixture.flat(8, 8)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(1, 1), 0)
	var state := CombatState.new(grid, [unit])
	var action: UtilityActionDef = _action(&"act", [&"a"])
	var candidates: Array = [
		_scored("near", action, {&"a": 0.9}), _scored("far", action, {&"a": 0.88})
	]

	var event: LogEvent = _logged_decision(state, unit, candidates, 0)

	assert_almost_eq(float(event.data["margin"]), 0.02, 0.001, "a near-tie reads as one")


## The whole point of A3: a logged decision is sufficient to redo its arithmetic
## without re-running the planner.
func test_a_logged_candidates_score_can_be_recomputed_from_its_own_trace() -> void:
	var grid: Grid = GridFixture.flat(8, 8)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(1, 1), 0)
	var state := CombatState.new(grid, [unit])
	var action: UtilityActionDef = _action(&"act", [&"a", &"b"], 1.5)
	var candidates: Array = [_scored("here", action, {&"a": 0.6, &"b": 0.4})]

	var event: LogEvent = _logged_decision(state, unit, candidates, 0)

	var logged: Dictionary = (event.data["candidates"] as Array)[0]
	var rebuilt: float = 1.5
	for entry: Dictionary in logged["trace"] as Array:
		rebuilt *= float(entry["compensated"])

	assert_almost_eq(rebuilt, float(logged["score"]), 0.0001)


## "Not offered" and "offered and scored zero" are different answers to "why
## didn't it do that", and the log has to keep them apart.
func test_the_log_distinguishes_an_unoffered_action_from_a_vetoed_one() -> void:
	var grid: Grid = GridFixture.flat(8, 8)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(1, 1), 0)
	var state := CombatState.new(grid, [unit])
	var action: UtilityActionDef = _action(&"act", [&"a"])
	var vetoed: Dictionary = _scored("vetoed", action, {&"a": 0.0})
	var unoffered: Dictionary = {
		"label": "unoffered", "action_id": &"act", "score": 0.0, "offered": false, "trace": []
	}

	var event: LogEvent = _logged_decision(state, unit, [vetoed, unoffered], -1)

	var logged: Array = event.data["candidates"]
	assert_true(logged[0]["offered"], "it was offered and scored zero")
	assert_false(logged[1]["offered"], "this one never got that far")
	assert_eq(event.data["winner"], "nothing", "and nothing was chosen")
