class_name ConsiderationDef
extends Resource

## One question an action asks about a candidate: a normalized 0–1 fact published
## by `UtilityContext`, turned into utility by a curve. `docs/11` has the model.
##
## **Considerations are shared across actions and profiles.** That is what makes a
## profile a weight vector rather than a code path — aggressive and cautious both
## read `own_hp_ratio` and differ only in what they weight it at.

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
