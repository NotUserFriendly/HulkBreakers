class_name AimResult
extends RefCounted

## Everything the aim UI draws (docs/10 Phase 12.3, docs/08's "no number is
## born in the view"): AimController.resolve()'s whole output.

## Nearest-first, one entry per distinct body touched by the plane.
var layers: Array[AimLayer]
## The body `layer_index` currently reads — what the scroll selected.
var reading: Variant
## `ShotPlane.resolve_projectile(whole_plane, reticle)`, frontmost-first
## against the ENTIRE plane — what the reticle actually hits. Scrolling
## must never change this.
var resolves: Region
## The weapon's resolved scatter rings, for drawing — N rings, never a
## fixed count assumed.
var rings: Array[Ring]


func _init(
	p_layers: Array[AimLayer] = [],
	p_reading: Variant = null,
	p_resolves: Region = null,
	p_rings: Array[Ring] = []
) -> void:
	layers = p_layers
	reading = p_reading
	resolves = p_resolves
	rings = p_rings
