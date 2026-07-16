class_name UnitPicker
extends RefCounted

## docs/10 taskblock03 D1: "click the body, not just the tile" — ray-vs-box
## hit testing against every living unit's own boxes
## (UnitGeometry.placements(), the exact boxes a UnitView renders and
## docs/10 calls "render is hitbox"), not a per-unit bounding sphere or a
## click on its cell. Pure math, no SceneTree: the Node layer only supplies
## the ray (Camera3D.project_ray_origin/normal need a live viewport) and
## reads the result.


## The nearest living unit whose body the ray actually passes through, and
## the ray parameter `t` of that hit — or an empty Dictionary if none. A
## caller with both this and BoardPicker.plane_hit_t compares the two `t`
## values directly: both parametrize the same (from, dir) ray, so whichever
## is smaller is nearer the camera and wins.
static func hit(units: Array[Unit], from: Vector3, dir: Vector3) -> Dictionary:
	var nearest_unit: Unit = null
	var nearest_t: float = INF
	for unit: Unit in units:
		if not unit.alive:
			continue
		for placement: BoxPlacement in UnitGeometry.placements(unit):
			var t: Variant = _ray_box_t(placement, from, dir)
			if t != null and (t as float) < nearest_t:
				nearest_t = t as float
				nearest_unit = unit
	if nearest_unit == null:
		return {}
	return {"unit": nearest_unit, "t": nearest_t}


## Ray-vs-oriented-box via the standard slab test, done in the box's own
## local frame (placement.transform's basis is orthonormal — unit facing and
## socket-chain rotations only, never a scale) so it reduces to a plain
## axis-aligned test there.
static func _ray_box_t(placement: BoxPlacement, from: Vector3, dir: Vector3) -> Variant:
	var inv: Transform3D = placement.transform.affine_inverse()
	var local_from: Vector3 = inv * from
	var local_dir: Vector3 = inv.basis * dir
	var half: Vector3 = placement.box.size * 0.5
	var box_min: Vector3 = placement.box.center - half
	var box_max: Vector3 = placement.box.center + half

	var t_min: float = -INF
	var t_max: float = INF
	for axis in range(3):
		var o: float = local_from[axis]
		var d: float = local_dir[axis]
		var lo: float = box_min[axis]
		var hi: float = box_max[axis]
		if is_zero_approx(d):
			if o < lo or o > hi:
				return null
			continue
		var t1: float = (lo - o) / d
		var t2: float = (hi - o) / d
		if t1 > t2:
			var tmp: float = t1
			t1 = t2
			t2 = tmp
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_min > t_max:
			return null

	if t_max < 0.0:
		return null
	return maxf(t_min, 0.0)
