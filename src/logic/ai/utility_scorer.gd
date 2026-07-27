class_name UtilityScorer
extends RefCounted

## taskblock-45 Pass A: the scoring maths, and the one place the model's two
## load-bearing properties live.
##
## ## Product, not sum
##
## An action's considerations MULTIPLY. A single zero therefore vetoes the action
## outright rather than merely lowering it, which is the difference between
## "unreachable, so no" and "unreachable, so slightly less appealing than the
## alternatives" — and a sum gives you the second whether you wanted it or not.
## Every consideration can only damp or veto; none can inflate. That is why
## `ResponseCurve.apply` clamps to 0–1 at both ends.
##
## ## The compensation factor, which is not a tuning knob
##
## Multiplying values in 0–1 means **an action with five considerations scores
## systematically lower than one with two, at identical quality**, purely for
## having been described in more detail. Left uncorrected this looks exactly like
## a balance problem and is not one: it is arithmetic, and no amount of
## re-weighting fixes it, because the penalty scales with the count rather than
## with the content.
##
## The standard correction (Mark & Dill's infinite-axis design) pulls each factor
## back toward 1 by an amount proportional to how many factors there are:
##
##     modification = 1 - (1 / n)
##     make_up      = (1 - value) * modification
##     compensated  = value + (make_up * value)
##
## With `n == 1` the modification is 0 and the value passes through untouched.
## With larger `n` each factor is lifted toward 1.
##
## **It reduces the dimensional penalty substantially; it does not eliminate it,
## and claiming otherwise would be a comfortable lie in a comment someone later
## relies on.** At every consideration sitting at 0.8, two versus five:
##
##     uncompensated   0.64  vs 0.328  — the five-input action keeps 51%
##     compensated     0.774 vs 0.688  — it keeps 89%
##
## A residual ~11% bias toward fewer considerations remains. That is small enough
## to be swamped by any real weighting difference and is the accepted cost of the
## formula; a geometric mean would equalise exactly but would also turn one
## terrible consideration into a mild average, losing the sharpness that makes
## the product model worth having.
##
## **A zero stays zero at every `n`** — `0 + (make_up * 0)` — so the veto property
## survives the correction untouched.
##
## ## Ties
##
## Ties are common rather than exotic: taskblock-43 found that on open ground a
## whole arc of cells sits at exactly the standoff distance and therefore scores
## identically, and its Pass B test failed because iteration order silently
## picked the winner. **The tiebreak is the lowest candidate index, decided once
## and stated here.** Serial iteration hides the problem; any reordering — a
## different candidate source, a parallel scorer, a reduction — exposes it.

## Scores at or below this are treated as "will not do this at all", so a vetoed
## action is never selected even when every alternative is also vetoed. A caller
## with nothing above it has genuinely found no positive-utility action, which is
## a real state the old planner could not even express — `PLAN.md`'s *Panic* item
## is what eventually answers it.
const VETO_EPSILON := 0.0


## One action's score for one candidate, in `[0, inf)`.
##
## `inputs` is the candidate's normalized 0–1 facts by `input_id`. `trace`, when
## supplied, is appended with one entry per consideration carrying the raw input,
## the curve output and the compensated value — because **a veto is invisible in
## a product**, and "which consideration returned zero" is the question actually
## asked when a decision looks wrong.
##
## **Every consideration is evaluated even after a zero appears.** Short-circuiting
## would be faster and would make the log unable to answer that question, which is
## the whole reason taskblock-45 designs the log in rather than adding it when
## something goes wrong. The counts are small — a handful per action.
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


## Whether `action` is even offered for `candidate`. Separate from scoring so the
## decision log can distinguish "not offered" from "offered and scored zero" —
## different answers to "why didn't it do that".
static func preconditions_hold(action: UtilityActionDef, predicates: Dictionary) -> bool:
	if action == null:
		return false
	for name: StringName in action.preconditions:
		if not bool(predicates.get(name, false)):
			return false
	return true


## The winning index among `scores`, or -1 when nothing clears the veto floor.
##
## **Lowest index wins a tie** — the rule stated at the top of this file. Written
## as an explicit strict `>` against the incumbent so the property is visible at
## the comparison rather than being an emergent consequence of loop order.
static func best_index(scores: Array[float]) -> int:
	var best: int = -1
	var best_score: float = VETO_EPSILON
	for i in range(scores.size()):
		if scores[i] > best_score:
			best_score = scores[i]
			best = i
	return best


## How far the winner beat the runner-up. Recorded per decision because a
## near-tie and a landslide want reading very differently when behaviour looks
## wrong, and the score alone cannot tell them apart. Returns the winning score
## itself when there is no runner-up.
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
