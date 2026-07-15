class_name MaterialEntry
extends Resource

## One row of the material table (docs/03). Armor is not more hitpoints —
## a part's `material` looks up its DT and deflection behavior here, so new
## materials are authored as data, never a code edit.

@export var dt: float = 0.0
## BodyProjector picks whichever of a box's 4 axis-aligned face normals
## faces the shooter most directly, so the incidence angle it ever hands
## resolve_impact cannot exceed 45 degrees (the midpoint between two
## adjacent faces). 30 leaves both STOP_DEAD and DEFLECT reachable; a
## default of 45+ would make deflection unreachable, not merely rare.
@export var deflect_threshold_deg: float = 30.0
## Reserved: docs/03 names this field but specifies no formula for it yet.
## Storage only — do not derive ricochet behavior from it without asking.
@export var ricochet_bias: float = 0.0
@export var tags: Array[StringName] = []


func _init(p_dt: float = 0.0, p_deflect_threshold_deg: float = 30.0) -> void:
	dt = p_dt
	deflect_threshold_deg = p_deflect_threshold_deg
