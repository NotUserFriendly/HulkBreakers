class_name ModSource
extends RefCounted

## One recorded contribution to a resolved stat (docs/08): what changed it,
## by how much, and how. `source_name` is what the player sees in a
## drill-down (e.g. "Ceramic Plate", "Spin Up", "Incendiary Rounds").

var source_name: String
var source_kind: Enums.ModSourceKind
var op: Enums.ModOp
var delta: float


func _init(
	p_source_name: String, p_source_kind: Enums.ModSourceKind, p_op: Enums.ModOp, p_delta: float
) -> void:
	source_name = p_source_name
	source_kind = p_source_kind
	op = p_op
	delta = p_delta
