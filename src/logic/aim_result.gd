class_name AimResult
extends RefCounted

## Everything the aim UI draws (docs/10 Phase 12.3, docs/08's "no number is
## born in the view"): AimController.resolve()'s whole output.

## Nearest-first, one entry per distinct body touched by the plane.
var layers: Array[AimLayer]
## The body `layer_index` currently reads — what the scroll selected.
var reading: Variant
## docs/09 taskblock06 Pass A: the ray-cast hit against the ENTIRE plane —
## what the reticle actually hits. Scrolling must never change this.
var resolves: HitResult
## The weapon's resolved scatter rings, for drawing — N rings, never a
## fixed count assumed.
var rings: Array[Ring]
## tb34 Pass B: the widest burst pull's own outer radius
## (`AimController.recoil_bound_radius`) — 0.0 means "nothing to draw,"
## never a real bound at exactly zero (a zero-radius bound would be
## indistinguishable from the dot anyway).
var recoil_bound_radius: float
## tb34 Pass B: the resolved pellet-spread pattern's own radius
## (`AimController.pellet_circle_radius`) — 0.0 means "not a pellet
## weapon, draw the plain dot."
var pellet_circle_radius: float


func _init(
	p_layers: Array[AimLayer] = [],
	p_reading: Variant = null,
	p_resolves: HitResult = null,
	p_rings: Array[Ring] = [],
	p_recoil_bound_radius: float = 0.0,
	p_pellet_circle_radius: float = 0.0
) -> void:
	layers = p_layers
	reading = p_reading
	resolves = p_resolves
	rings = p_rings
	recoil_bound_radius = p_recoil_bound_radius
	pellet_circle_radius = p_pellet_circle_radius
