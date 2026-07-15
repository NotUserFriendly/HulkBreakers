class_name Region
extends RefCounted

## One projected slice of the shot plane (docs/02): the on-screen rect a box
## occupies, how far along the line of fire it sits, and which part it came
## from. `resolve_projectile` walks an Array[Region] depth-ascending and
## returns the first rect containing the impact point — this is the entire
## hit-resolution system.

var rect: Rect2
var depth: float
var part: Part
var surface_normal: Vector3


func _init(
	p_rect: Rect2 = Rect2(),
	p_depth: float = 0.0,
	p_part: Part = null,
	p_surface_normal: Vector3 = Vector3.ZERO
) -> void:
	rect = p_rect
	depth = p_depth
	part = p_part
	surface_normal = p_surface_normal
