class_name Ring
extends Resource

## One annulus of a weapon's scatter pattern (docs/02): `radius` is this
## ring's own outer edge, `weight` its share of where projectiles land.
## Ordered inner -> outer in Part.scatter; ring 0's annulus spans (0, radius],
## ring i>0 spans (scatter[i-1].radius, radius]. Author N of these, never a
## fixed three — Dartboard assumes nothing about count.

@export var radius: float = 0.0
@export var weight: float = 1.0


func _init(p_radius: float = 0.0, p_weight: float = 1.0) -> void:
	radius = p_radius
	weight = p_weight
