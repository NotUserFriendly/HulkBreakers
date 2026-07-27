class_name ConsiderationDef
extends Resource

## taskblock-45 Pass A: one question an action asks about a candidate.
##
## `input_id` names a normalized 0–1 fact the scoring context supplies — an open
## `StringName` (CLAUDE.md), so a new consideration is a new input published by
## the context plus a new `.tres`, never a code edit to the scorer. `curve` turns
## that fact into utility.
##
## **Considerations are shared across actions and across profiles.** That is what
## makes a profile a weight vector rather than a code path: aggressive and
## cautious both read `own_hp_ratio`, and differ only in the curve over it and
## the weight on it.

## The 0–1 fact this reads, by name. Unknown ids resolve to 0.0 at scoring time,
## which vetoes — deliberately loud rather than silently neutral, because a typo
## that made an action merely score lower would be nearly impossible to spot,
## while one that stops it being chosen at all shows up immediately in the
## decision log.
@export var input_id: StringName = &""
@export var curve: ResponseCurve
## Per-consideration weight. A profile multiplies this (`ProfileDef`), so the
## authored value is the neutral baseline and the profile is the deviation.
@export var weight: float = 1.0


func _init(
	p_input_id: StringName = &"", p_curve: ResponseCurve = null, p_weight: float = 1.0
) -> void:
	input_id = p_input_id
	curve = p_curve if p_curve != null else ResponseCurve.new()
	weight = p_weight


## This consideration's utility for `inputs`, in 0–1, before the scorer's
## compensation and weighting. A missing input is 0.0 — see `input_id`.
func evaluate(inputs: Dictionary) -> float:
	var raw: float = float(inputs.get(input_id, 0.0))
	return curve.apply(raw) if curve != null else clampf(raw, 0.0, 1.0)
