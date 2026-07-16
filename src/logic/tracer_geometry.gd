class_name TracerGeometry
extends RefCounted

## docs/10 taskblock03 F2: "same geometry the tracer will use... so what
## you're shown is what will fire." The box-mesh line construction a
## muzzle->impact tracer needs, pulled out of ResolutionPlayer so the aim
## UI's ghost targeting line can share it exactly — one builder, not two
## kept in sync by hand.


## The Transform3D placing a `thickness`-square box between `from` and `to`,
## oriented along the segment. Identity at `from` if the two points
## coincide (a degenerate, zero-length segment — callers should generally
## skip drawing it rather than render a unit cube there).
static func segment_transform(from: Vector3, to: Vector3) -> Transform3D:
	var direction: Vector3 = to - from
	if direction.length() < 0.001:
		return Transform3D(Basis.IDENTITY, from)
	return Transform3D(Basis.looking_at(-direction.normalized(), Vector3.UP), (from + to) * 0.5)


## The BoxMesh size for that same segment — square in cross-section,
## exactly as long as the segment itself.
static func segment_size(from: Vector3, to: Vector3, thickness: float) -> Vector3:
	return Vector3(thickness, thickness, (to - from).length())
