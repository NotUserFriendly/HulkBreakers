class_name SurrogateTier
extends Resource

## One rung of the surrogate degradation ladder (docs/04) — a Resource with
## a rank, not a hardcoded enum, so new tiers between existing ones never
## need a code edit. Lower rank is more intact; rank ascends as the ladder
## degrades toward BRAIN_ONLY.

@export var id: StringName
@export var display_name: String = ""
@export var rank: int = 0


func _init(p_id: StringName = &"", p_display_name: String = "", p_rank: int = 0) -> void:
	id = p_id
	display_name = p_display_name
	rank = p_rank
