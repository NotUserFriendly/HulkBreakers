class_name Region
extends RefCounted

## One projected slice of the shot plane (docs/02): the on-screen rect a box
## occupies, how far along the line of fire it sits, and which part it came
## from. `ShotPlane.resolve_projectile` walks an Array[Region] depth-
## ascending and returns the first rect containing a point — that's the
## internal math `ShotPlane.resolve_ray` (docs/09 taskblock06 Pass A) runs
## to answer a real ray cast; Region itself never left the picture, it's
## just plumbing now rather than the resolution entry point.

var rect: Rect2
var depth: float
var part: Part
var surface_normal: Vector3
## taskblock-09 E: the source box's own minimum dimension — "the through
## axis a shot crosses." The single place geometry feeds the DT stat
## (`MaterialEntry.dt_at`): a thicker plate is tougher for free, with no
## extra authoring. Set by BodyProjector._project_box; 0.0 (the default)
## only appears on a Region built by hand outside that path (test
## fixtures), where `dt_at` correctly reads it as "thinnest possible" and
## clamps to the curve's first point.
var thickness: float = 0.0
## The Unit or cover Part this region's whole body belongs to (docs/10
## Phase 12.3's aim layers group by this) — distinct from `part`, which is
## the specific part within that body. Set by ShotPlane.build(); left null
## by direct BodyProjector calls (single-part test fixtures, cover
## placement math) that never needed body identity before.
var body: Variant = null
## taskblock-09 D: non-null only for a JOINT region — one small aimable
## box BodyProjector emits per occupied socket, at that socket's own
## composed transform. `part` still points at the socket's OCCUPANT (the
## child hanging off this joint) so depth-sort/occlusion/ricochet-
## exclusion all keep working unchanged; `socket` is what tells
## resolve_shot to divert into joint damage (`DamageResolver.
## apply_damage_to_joint`/`sever_joint`) instead of the normal part/DT
## path. Null (the default) is an ordinary part region.
var socket: Socket = null


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
