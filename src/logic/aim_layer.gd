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


## docs/09 taskblock06 Pass H: "just in front of the READ layer's frontmost
## part" — the nearest depth among this layer's own regions (a body can
## have several, e.g. an arm in front of and a leg behind the torso's own
## depth). 0.0 for an empty layer (never constructed by AimController's own
## layers_for(), which only ever builds a layer FROM at least one region —
## a defensive default for direct construction, not a real case).
func frontmost_depth() -> float:
	var nearest: float = 0.0
	var found: bool = false
	for region: Region in regions:
		if not found or region.depth < nearest:
			nearest = region.depth
			found = true
	return nearest
