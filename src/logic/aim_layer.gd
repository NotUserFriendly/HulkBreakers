class_name AimLayer
extends RefCounted

## One distinct body's worth of the shot plane (docs/10 Phase 12.3): every
## Region sharing a `body` (a Unit, or a cover Part with no owning unit).
## AimController orders these nearest-first; layer 0 is the near body,
## layer 1 whatever stands behind it.

var body: Variant
var regions: Array[Region]


func _init(p_body: Variant = null, p_regions: Array[Region] = []) -> void:
	body = p_body
	regions = p_regions
