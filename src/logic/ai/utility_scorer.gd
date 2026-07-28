class_name UtilityScorer
extends RefCounted

## The scoring arithmetic. `docs/11` has the model — product-not-sum, why the
## compensation factor exists, and the tiebreak rule. What lives here is the
## implementation of each and the properties that follow from *this* formula.
##
## ## The compensation factor, and the residual it leaves
##
## Mark & Dill's infinite-axis correction, which pulls each factor back toward 1
## by an amount proportional to how many factors there are:
##
##     modification = 1 - (1 / n)
##     make_up      = (1 - value) * modification
##     compensated  = value + (make_up * value)
##
## With `n == 1` the modification is 0 and the value passes through untouched.
##
## **It reduces the dimensional penalty substantially; it does not eliminate it,
## and claiming otherwise would be a comfortable lie in a comment someone later
## relies on.** At every consideration sitting at 0.8, two versus five:
##
##     uncompensated   0.64  vs 0.328  — the five-input action keeps 51%
##     compensated     0.774 vs 0.688  — it keeps 89%
##
## **A residual ~11% bias toward fewer considerations remains** — the accepted cost
## of the formula. If the profile table ever shows actions with many considerations
## being systematically under-chosen, that number is the first place to look, and
## the fix is a different aggregation rather than re-weighting. A geometric mean
## would equalise exactly, and was rejected because it turns one terrible
## consideration into a mild average, losing the sharpness that makes a product
## model worth having.
##
## **A zero stays zero at every `n`** — `0 + (make_up * 0)` — so the veto property
## survives the correction untouched. That is what makes this formula usable and a
## `pow(x, 1/n)` normalisation not.

## Scores at or below this are treated as "will not do this at all", so a vetoed
## action is never selected even when every alternative is also vetoed. A caller
## with nothing above it has genuinely found no positive-utility action — a real
## state, and `PLAN.md`'s *Panic* item is what eventually gives it behaviour.
const VETO_EPSILON := 0.0


## One action's score for one candidate, in `[0, inf)`.
##
## `inputs` is the candidate's normalized 0–1 facts by `input_id`. `trace`, when
## supplied, gets one entry per consideration carrying the raw input, the curve
## output and the compensated value (`docs/11`: the decision log is the
## instrument).
##
## **Every consideration is evaluated even after a zero appears.** Short-circuiting
## would be faster and would leave the trace unable to say which consideration
## vetoed — the one question a product cannot answer after the fact. The counts are
## small, a handful per action, so the cost of not short-circuiting is nil.
static func score(
	action: UtilityActionDef, inputs: Dictionary, profile: UtilityProfile, trace: Array = []
) -> float:
	if action == null:
		return 0.0
	var count: int = action.considerations.size()
	var product: float = 1.0
	var modification: float = 0.0 if count <= 1 else 1.0 - (1.0 / float(count))

	for consideration: ConsiderationDef in action.considerations:
		var raw: float = float(inputs.get(consideration.input_id, 0.0))
		var curved: float = consideration.evaluate(inputs)
		var weighted: float = clampf(
			curved * consideration.weight * _consideration_weight(profile, consideration.input_id),
			0.0,
			1.0
		)
		var make_up: float = (1.0 - weighted) * modification
		var compensated: float = weighted + (make_up * weighted)
		product *= compensated
		if trace != null:
			(
				trace
				. append(
					{
						"input_id": consideration.input_id,
						"raw": raw,
						"curved": curved,
						"weighted": weighted,
						"compensated": compensated,
					}
				)
			)

	return product * action.base_weight * _action_weight(profile, action.id)


## Whether `action` is even offered. Separate from scoring so the decision log can
## distinguish "not offered" from "offered and scored zero" — different answers to
## "why didn't it do that", and an impossible action costs one boolean rather than
## a full curve evaluation.
##
## **An action whose gates no unit can satisfy is offered to nobody and idles it**
## — `docs/11`'s first named failure mode. Ask what a unit failing every gate does
## instead.
static func preconditions_hold(action: UtilityActionDef, predicates: Dictionary) -> bool:
	if action == null:
		return false
	for name: StringName in action.preconditions:
		if not bool(predicates.get(name, false)):
			return false
	return true


## The winning index among `scores`, or -1 when nothing clears the veto floor.
##
## **Lowest index wins a tie** (`docs/11`). Written as an explicit strict `>`
## against the incumbent so the property is visible at the comparison rather than
## being an emergent consequence of loop order — which is exactly how it went
## unnoticed before: serial iteration is stable and hides it.
static func best_index(scores: Array[float]) -> int:
	var best: int = -1
	var best_score: float = VETO_EPSILON
	for i in range(scores.size()):
		if scores[i] > best_score:
			best_score = scores[i]
			best = i
	return best


## How far the winner beat the runner-up. Recorded per decision because a near-tie
## and a landslide want reading very differently when behaviour looks wrong, and
## the winning score alone cannot tell them apart. Returns the winning score itself
## when there is no runner-up.
static func margin(scores: Array[float]) -> float:
	var best: float = -INF
	var second: float = -INF
	for value: float in scores:
		if value > best:
			second = best
			best = value
		elif value > second:
			second = value
	if best == -INF:
		return 0.0
	return best if second == -INF else best - second


static func _action_weight(profile: UtilityProfile, action_id: StringName) -> float:
	return profile.action_weight(action_id) if profile != null else 1.0


static func _consideration_weight(profile: UtilityProfile, input_id: StringName) -> float:
	return profile.consideration_weight(input_id) if profile != null else 1.0
