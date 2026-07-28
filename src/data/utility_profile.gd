class_name UtilityProfile
extends Resource

## What kind of unit this is, as numbers rather than code. `docs/11`: profiles are
## a separate axis from intelligence — tier says what a unit can know and do,
## profile says what it wants.
##
## Absent entries are 1.0, so a profile states only where it deviates from neutral
## and an empty profile is a legitimate one.
##
## **A weight on an input that two actions read in OPPOSITE directions is
## ambiguous, and the model cannot express what you want.** `own_integrity` is read
## forwards by an approach ("I am healthy, so charge") and backwards by a
## take-cover ("I am hurt, so hide"); one weight pushes both the same way. Publish a
## second input rather than reusing one inverted.

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
