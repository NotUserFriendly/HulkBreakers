class_name UtilityProfile
extends Resource

## taskblock-45 Pass A: what kind of unit this is, as numbers rather than code.
##
## A profile is a **weight vector**, never a behaviour: aggressive and cautious
## run the identical scorer over the identical action pool and disagree only
## about what things are worth. That is the property that stops the profile table
## from becoming a pile of per-personality branches, and it is why
## `PLAN.md` can say the playstyle enum dissolves into this — `AGGRESSIVE`,
## `SKIRMISHER`, `MARKSMAN` and `COVER_SEEKER` mix profile with role and range,
## and both halves become weights here.
##
## Absent entries are 1.0, so a profile only states where it *deviates* from
## neutral. An empty profile is a legitimate, fully neutral one.

@export var id: StringName = &""
@export var display_name: String = ""
## `action_id -> float`. Scales a whole action's appeal.
@export var action_weights: Dictionary = {}
## `input_id -> float`. Scales one consideration wherever it appears, across
## every action that reads it — which is what makes considerations shared rather
## than duplicated per action.
@export var consideration_weights: Dictionary = {}


func _init(p_id: StringName = &"", p_display_name: String = "") -> void:
	id = p_id
	display_name = p_display_name


func action_weight(action_id: StringName) -> float:
	return float(action_weights.get(action_id, 1.0))


func consideration_weight(input_id: StringName) -> float:
	return float(consideration_weights.get(input_id, 1.0))
