class_name SurrogateTier
extends Resource

## One rung of the surrogate degradation ladder (docs/04) — a Resource with
## a rank, not a hardcoded enum, so new tiers between existing ones never
## need a code edit. Lower rank is more intact; rank ascends as the ladder
## degrades toward BRAIN_ONLY.

@export var id: StringName
@export var display_name: String = ""
@export var rank: int = 0

## docs/04 taskblock02 Pass D1: the socket type on a SHELL this tier's own
## surrogate Part attaches into — an explicit column on the ladder (not
## derived from `id`) so it can read `SURROGATE_BRAIN` rather than a
## mechanically-formatted `SURROGATE_BRAIN_ONLY`.
@export var socket_type: StringName = &""

## docs/04 taskblock02 Pass D3: what a docked surrogate at this tier lets
## the shell's own body-gated parts (`Part.body_requires`) actually do.
## Do NOT assume tiers nest supersets of a lower/higher tier's list —
## PERIPHERAL (limbs, hollow core) and TORSIC (organs, no limbs) may carry
## genuinely different sets, not merely more or fewer of the same tags.
@export var capabilities: Array[StringName] = []


func _init(
	p_id: StringName = &"",
	p_display_name: String = "",
	p_rank: int = 0,
	p_socket_type: StringName = &"",
	p_capabilities: Array[StringName] = []
) -> void:
	id = p_id
	display_name = p_display_name
	rank = p_rank
	socket_type = p_socket_type
	capabilities = p_capabilities
