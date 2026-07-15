class_name StatValue
extends RefCounted

## The result of one StatResolver.resolve() call: the pre-modifier baseline,
## the fully-resolved number, and full provenance. The tooltip and the
## damage calculation must both come from the same StatValue — that's the
## whole point of the pipeline (docs/08).

var base: float
var current: float
var sources: Array[ModSource] = []


func _init(p_base: float = 0.0, p_current: float = 0.0, p_sources: Array[ModSource] = []) -> void:
	base = p_base
	current = p_current
	sources = p_sources


## True if any source actually moved the value away from base — what
## DescriptionBuilder uses to decide which numbers to highlight.
func changed() -> bool:
	return not sources.is_empty() and not is_equal_approx(base, current)
