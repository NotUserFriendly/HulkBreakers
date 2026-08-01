class_name UnitPicker
extends RefCounted

## docs/10 taskblock03 D1: "click the body, not just the tile" — ray-vs-box
## hit testing against every living unit's own boxes
## (UnitGeometry.placements(), the exact boxes a HitVolumeView renders and
## docs/10 calls "render is hitbox"), not a per-unit bounding sphere or a
## click on its cell. Pure math, no SceneTree: the Node layer only supplies
## the ray (Camera3D.project_ray_origin/normal need a live viewport) and
## reads the result.


## The nearest living unit whose body the ray actually passes through, the
## specific Part whose own box was hit (docs/10 taskblock05 C: the same
## nearest-box search already knows this — exposing it is what lets a 3D
## hover highlight one exact part rather than a whole unit), and the ray
## parameter `t` of that hit — or an empty Dictionary if none. A caller with
## both this and BoardPicker.plane_hit_t compares the two `t` values
## directly: both parametrize the same (from, dir) ray, so whichever is
## smaller is nearer the camera and wins.
static func hit(units: Array[Unit], from: Vector3, dir: Vector3) -> Dictionary:
	var nearest_unit: Unit = null
	var nearest_part: Part = null
	var nearest_t: float = INF
	for unit: Unit in units:
		if not unit.alive:
			continue
		for placement: BoxPlacement in UnitGeometry.placements(unit):
			var t: Variant = ray_box_t(placement, from, dir)
			if t != null and (t as float) < nearest_t:
				nearest_t = t as float
				nearest_unit = unit
				nearest_part = placement.part
	if nearest_unit == null:
		return {}
	return {"unit": nearest_unit, "part": nearest_part, "t": nearest_t}


## Ray-vs-oriented-box via the standard slab test, done in the box's own
## local frame (placement.transform's basis is orthonormal — unit facing and
## socket-chain rotations only, never a scale) so it reduces to a plain
## axis-aligned test there. Public (tb32 Pass C): `PartPicker` reuses this
## exact math for blocker/field-item boxes rather than duplicating it.
##
## taskblock-52 Pass B: a thin read of `ray_box_hit` below, which is the one
## slab test now. Every existing caller keeps its exact signature and return —
## the face information the ray chain needs is additive, and a second copy of
## this arithmetic is precisely the parallel system this project keeps deleting.
static func ray_box_t(placement: BoxPlacement, from: Vector3, dir: Vector3) -> Variant:
	var hit: Dictionary = ray_box_hit(placement, from, dir)
	return null if hit.is_empty() else hit["t"]


## The same slab test, reporting **which face the ray entered through**.
##
## `{t, normal, inside}` or an empty Dictionary on a miss. `normal` is the
## struck face's real world normal — the box's local axis normal carried out
## through `placement.transform.basis`, which is orthonormal, so no inverse
## transpose is needed. This is what makes the angle of incidence native to a
## ray march: `docs/03`'s deflect/penetrate/stop maths is written against a real
## surface angle, and the shot plane discarded it (a `Region` keeps an
## axis-aligned rect of projected corners and nothing about the face's real
## orientation survives the projection).
##
## `inside` is true when the ray's own origin already sits within the box, where
## there is no entry face to speak of. The normal reported then is the face the
## ray would have entered through had it started outside — an honest answer to a
## question that has no clean one, flagged so a caller can tell the difference
## rather than silently treating it as an ordinary hit. `t` is floored at 0.0
## exactly as it always was.
static func ray_box_hit(placement: BoxPlacement, from: Vector3, dir: Vector3) -> Dictionary:
	var inv: Transform3D = placement.transform.affine_inverse()
	var local_from: Vector3 = inv * from
	var local_dir: Vector3 = inv.basis * dir
	var half: Vector3 = placement.box.size * 0.5
	var box_min: Vector3 = placement.box.center - half
	var box_max: Vector3 = placement.box.center + half

	var t_min: float = -INF
	var t_max: float = INF
	# Which axis produced the current `t_min`, and which side of it — the
	# entry face, tracked as the slabs narrow rather than re-derived from the
	# hit point afterwards (a point exactly on an edge belongs to two faces,
	# and the slab test already knows which one it clipped against).
	var entry_axis: int = -1
	var entry_sign: float = 0.0
	# The same, for the far side: the face the ray leaves through.
	var exit_axis: int = -1
	var exit_sign: float = 0.0
	for axis in range(3):
		var o: float = local_from[axis]
		var d: float = local_dir[axis]
		var lo: float = box_min[axis]
		var hi: float = box_max[axis]
		if is_zero_approx(d):
			if o < lo or o > hi:
				return {}
			continue
		var t1: float = (lo - o) / d
		var t2: float = (hi - o) / d
		# Travelling negatively along this axis enters through the `hi` face,
		# whose outward normal is +1; travelling positively enters through `lo`,
		# normal -1.
		var near_sign: float = 1.0 if d < 0.0 else -1.0
		if t1 > t2:
			var tmp: float = t1
			t1 = t2
			t2 = tmp
		if t1 > t_min:
			t_min = t1
			entry_axis = axis
			entry_sign = near_sign
		if t2 < t_max:
			t_max = t2
			exit_axis = axis
			exit_sign = -near_sign
		if t_min > t_max:
			return {}

	if t_max < 0.0:
		return {}
	var local_normal := Vector3.ZERO
	if entry_axis >= 0:
		local_normal[entry_axis] = entry_sign
	var local_exit_normal := Vector3.ZERO
	if exit_axis >= 0:
		local_exit_normal[exit_axis] = exit_sign
	return {
		"t": maxf(t_min, 0.0),
		"normal": (placement.transform.basis * local_normal).normalized(),
		"inside": t_min < 0.0,
		# taskblock-52 Pass B: **where the ray leaves the box**, which is what a
		# penetrating round needs in order to advance past what it just cleared.
		# Without it a chain re-enters the box it penetrated, striking the same
		# plate over and over — found live: one round logged six impacts on one
		# plate before the damage ran out.
		"t_exit": t_max,
		"exit_normal": (placement.transform.basis * local_exit_normal).normalized(),
	}
