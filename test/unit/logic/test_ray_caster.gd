extends GutTest

## taskblock-52 Pass B: **the march — what a ray actually meets.**
##
## The properties under test here are the ones the shot plane could not have:
## a real struck-face normal, a real 3D distance, and one membership query rather
## than a list maintained separately by every caller.
##
## **These assert against geometry that was built, not against a second copy of
## the formula.** `test_ray_box_hit_reports_the_face_it_entered_through` places a
## real box, casts at it from four sides, and checks the normal points back the
## way the ray came — a re-derivation of the slab arithmetic would agree with
## itself and with nothing else (CLAUDE.md's own worked example of this trap).

const AIM_HEIGHT := 1.0


func _box_part(id: StringName, size: Vector3, material: StringName = &"steel") -> Part:
	var part := Part.new()
	part.id = id
	part.material = material
	part.hp = 40
	part.max_hp = 40
	part.volume = [Box.new(Vector3.ZERO, size)]
	return part


func _unit_at(cell: Vector2i, id: StringName = &"torso") -> Unit:
	var torso: Part = _box_part(id, Vector3(0.6, 1.2, 0.4))
	torso.volume = [Box.new(Vector3(0.0, 0.9, 0.0), Vector3(0.6, 1.2, 0.4))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell)


func _room(size: int = 11) -> Grid:
	return GridFixture.enclosed_room(size, size)


## The whole point of the type. A box is placed, the ray is cast at each of its
## four side faces in turn, and the reported normal must point back along the
## ray — which is a statement about the box that was built, not about the maths
## that found it.
func test_ray_box_hit_reports_the_face_it_entered_through() -> void:
	var part: Part = _box_part(&"cube", Vector3(1.0, 1.0, 1.0))
	var placement := BoxPlacement.new(
		part, part.volume[0], Transform3D(Basis(), Vector3(5.0, 1.0, 5.0))
	)
	var cases := {
		Vector3(-1, 0, 0): Vector3(-1, 0, 0),  # travelling +X enters the -X face
		Vector3(1, 0, 0): Vector3(1, 0, 0),
		Vector3(0, 0, -1): Vector3(0, 0, -1),
		Vector3(0, 0, 1): Vector3(0, 0, 1),
		Vector3(0, -1, 0): Vector3(0, -1, 0),
		Vector3(0, 1, 0): Vector3(0, 1, 0),
	}
	for offset: Vector3 in cases:
		var from: Vector3 = Vector3(5.0, 1.0, 5.0) + offset * 4.0
		var dir: Vector3 = -offset
		var hit: Dictionary = UnitPicker.ray_box_hit(placement, from, dir)
		assert_false(hit.is_empty(), "a ray fired straight at the box must hit it (%s)" % offset)
		var normal: Vector3 = hit["normal"]
		print("  from %-18s dir %-18s -> normal %s, t %.3f" % [from, dir, normal, hit["t"]])
		assert_almost_eq(
			normal.distance_to(cases[offset]),
			0.0,
			0.0001,
			"the struck face's normal must point back toward the shooter (%s)" % offset
		)
		assert_almost_eq(float(hit["t"]), 3.5, 0.0001, "t is the real distance to the face")
		assert_false(hit["inside"], "a ray starting outside is not inside")


## A rotated box's normal has to come out through its own transform, or every
## incidence angle against a facing unit is wrong. Asserted by reading the built
## node's own basis back rather than re-deriving the rotation.
func test_a_rotated_box_reports_a_rotated_normal() -> void:
	var part: Part = _box_part(&"cube", Vector3(1.0, 1.0, 1.0))
	var basis := Basis(Vector3.UP, deg_to_rad(45.0))
	var placement := BoxPlacement.new(part, part.volume[0], Transform3D(basis, Vector3(5, 1, 5)))
	var hit: Dictionary = UnitPicker.ray_box_hit(
		placement, Vector3(0.0, 1.0, 5.0), Vector3(1, 0, 0)
	)
	assert_false(hit.is_empty())
	var normal: Vector3 = hit["normal"]
	print("  45-degree box struck along +X -> normal %s" % normal)
	# The box's own local -X face, carried out through its 45-degree yaw.
	var expected: Vector3 = (basis * Vector3(-1, 0, 0)).normalized()
	assert_almost_eq(normal.distance_to(expected), 0.0, 0.0001, "the normal turns with the box")
	assert_lt(normal.dot(Vector3(1, 0, 0)), 0.0, "and still faces the incoming round")


## A ray starting inside a box has no genuine entry face, and says so rather than
## reporting a confident one.
func test_a_ray_starting_inside_a_box_is_flagged() -> void:
	var part: Part = _box_part(&"cube", Vector3(2.0, 2.0, 2.0))
	var placement := BoxPlacement.new(part, part.volume[0], Transform3D(Basis(), Vector3(5, 1, 5)))
	var hit: Dictionary = UnitPicker.ray_box_hit(
		placement, Vector3(5.0, 1.0, 5.0), Vector3(1, 0, 0)
	)
	assert_false(hit.is_empty())
	assert_true(hit["inside"], "the origin sits within the box")
	assert_almost_eq(float(hit["t"]), 0.0, 0.0001, "t still floors at zero, as it always did")


## `ray_box_t` is a read of `ray_box_hit` now, so the two can never disagree —
## asserted rather than assumed, because "I refactored it to delegate" is exactly
## the claim a test should be able to check.
func test_ray_box_t_agrees_with_ray_box_hit() -> void:
	var part: Part = _box_part(&"cube", Vector3(1.0, 1.0, 1.0))
	var placement := BoxPlacement.new(part, part.volume[0], Transform3D(Basis(), Vector3(5, 1, 5)))
	for angle in range(0, 360, 23):
		var rad: float = deg_to_rad(angle)
		var from := Vector3(5.0 + cos(rad) * 6.0, 1.0, 5.0 + sin(rad) * 6.0)
		var dir: Vector3 = (Vector3(5, 1, 5) - from).normalized()
		var t: Variant = UnitPicker.ray_box_t(placement, from, dir)
		var hit: Dictionary = UnitPicker.ray_box_hit(placement, from, dir)
		assert_eq(t == null, hit.is_empty(), "both agree on whether there was a hit at %d" % angle)
		if t != null:
			assert_almost_eq(float(t), float(hit["t"]), 0.0, "and on the distance at %d" % angle)


## Nearest wins, and the loser is not reported. The basic march property.
func test_the_nearest_thing_along_the_ray_wins() -> void:
	var grid: Grid = _room()
	var near: Unit = _unit_at(Vector2i(7, 5), &"near_torso")
	var far: Unit = _unit_at(Vector2i(9, 5), &"far_torso")
	var state := CombatState.new(grid, [near, far])
	var hit: RayHit = RayCaster.cast(state, Vector3(3.0, AIM_HEIGHT, 5.0), Vector3(1, 0, 0))
	assert_not_null(hit)
	assert_eq(hit.body, near, "the nearer body takes it")
	assert_eq(hit.kind, RayHit.KIND_UNIT)
	assert_almost_eq(hit.t, 3.7, 0.05, "t is the real distance to the near torso's front face")


## The exclusion the shooter's own body needs — the ray's origin sits at or
## inside the gun's owner.
func test_excluded_parts_are_skipped_entirely() -> void:
	var grid: Grid = _room()
	var shooter: Unit = _unit_at(Vector2i(5, 5), &"shooter_torso")
	var target: Unit = _unit_at(Vector2i(8, 5), &"target_torso")
	var state := CombatState.new(grid, [shooter, target])
	var from := Vector3(5.0, AIM_HEIGHT, 5.0)

	var unfiltered: RayHit = RayCaster.cast(state, from, Vector3(1, 0, 0))
	assert_eq(unfiltered.body, shooter, "without exclusion a shooter hits itself first")

	var filtered: RayHit = RayCaster.cast(
		state, from, Vector3(1, 0, 0), shooter.shell.all_parts_with_joints()
	)
	assert_eq(filtered.body, target, "with it the round reaches downrange")


## A wall is met, and it is met as a blocker with its own cell recorded.
func test_a_wall_is_struck_and_attributed_to_its_cell() -> void:
	var grid: Grid = _room()
	var shooter: Unit = _unit_at(Vector2i(5, 5))
	var state := CombatState.new(grid, [shooter])
	var hit: RayHit = RayCaster.cast(
		state,
		Vector3(5.0, AIM_HEIGHT, 5.0),
		Vector3(1, 0, 0),
		shooter.shell.all_parts_with_joints()
	)
	assert_not_null(hit)
	assert_eq(hit.kind, RayHit.KIND_BLOCKER)
	assert_eq(hit.cell, Vector2i(10, 5), "the perimeter wall on that row")
	assert_almost_eq(hit.t, 4.5, 0.0001, "the wall box's near face, 4.5 units downrange")
	assert_almost_eq(
		hit.normal.distance_to(Vector3(-1, 0, 0)), 0.0, 0.0001, "struck on its shooter-facing face"
	)


## `grid.field_items` is in the march. `ShotPlane.build` never looked at it, even
## though `BodyProjector.project_assembly`'s own doc comment says a dropped
## assembly is what it exists to make shootable.
func test_a_dropped_field_item_is_struck() -> void:
	var grid: Grid = _room()
	var shooter: Unit = _unit_at(Vector2i(5, 5))
	var dropped: Part = _box_part(&"dropped_arm", Vector3(0.5, 0.5, 0.5))
	dropped.volume = [Box.new(Vector3(0.0, 0.25, 0.0), Vector3(0.5, 0.5, 0.5))]
	grid.field_items[Vector2i(8, 5)] = [dropped]
	var state := CombatState.new(grid, [shooter])
	var hit: RayHit = RayCaster.cast(
		state, Vector3(5.0, 0.25, 5.0), Vector3(1, 0, 0), shooter.shell.all_parts_with_joints()
	)
	assert_not_null(hit)
	assert_eq(hit.kind, RayHit.KIND_FIELD_ITEM, "a pile of scrap stops rounds")
	assert_eq(hit.part, dropped)
	assert_eq(hit.cell, Vector2i(8, 5))


## `BR52.01`. The picker took `assembly_placements`' default height of 0.0 while
## `BoardView._spawn_blocker` passes the cell's real height, so on a raised cell
## the hittable volume sat where the mesh is not. **Proved against the renderer's
## own placement call**, not against a re-derived expectation.
func test_a_blocker_on_a_raised_cell_is_hit_where_it_is_drawn() -> void:
	var grid: Grid = GridFixture.flat(11, 11)
	GridFixture.place_floor(grid, Vector2i(8, 5), 2.0)
	var wall: Part = GridFixture.place_wall(grid, Vector2i(8, 5), 2.0)
	var shooter: Unit = _unit_at(Vector2i(5, 5))
	var state := CombatState.new(grid, [shooter])
	var excluded: Array[Part] = shooter.shell.all_parts_with_joints()

	# Where BoardView actually draws it: the same call, same arguments.
	var drawn_height: float = UnitGeometry.true_height_for_cell(Vector2i(8, 5), grid)
	var drawn: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		wall, Vector2i(8, 5), 0.0, null, drawn_height
	)
	var drawn_centre: Vector3 = drawn[0].transform * drawn[0].box.center
	print("  wall drawn centred at %s (cell height %.2f)" % [drawn_centre, drawn_height])

	# A round passing under the raised wall's real footprint must miss it.
	var below: RayHit = RayCaster.cast(state, Vector3(5.0, 1.0, 5.0), Vector3(1, 0, 0), excluded)
	var below_part: Variant = null if below == null else below.part
	assert_ne(below_part, wall, "at height 1.0 the round passes beneath a wall raised to 2.0")

	# One at the drawn box's own height must hit it.
	var through: RayHit = RayCaster.cast(
		state, Vector3(5.0, drawn_centre.y, 5.0), Vector3(1, 0, 0), excluded
	)
	assert_not_null(through)
	assert_eq(through.part, wall, "and one at the drawn centre's height strikes it")
	assert_almost_eq(
		through.point.y, drawn_centre.y, 0.0001, "at the height the mesh actually occupies"
	)


## `PartPicker` and the march must agree about the same board — they are the same
## question asked by the aim UI and by resolution, and two answers is the bug the
## no-parallel-systems rule exists for.
func test_the_picker_and_the_march_agree_about_a_raised_blocker() -> void:
	var grid: Grid = GridFixture.flat(11, 11)
	GridFixture.place_floor(grid, Vector2i(8, 5), 2.0)
	var wall: Part = GridFixture.place_wall(grid, Vector2i(8, 5), 2.0)
	var state := CombatState.new(grid, [])
	var from := Vector3(5.0, 2.6, 5.0)
	var dir := Vector3(1, 0, 0)

	var picked: Dictionary = PartPicker.hit([] as Array[Unit], grid, from, dir)
	var marched: RayHit = RayCaster.cast(state, from, dir)
	assert_false(picked.is_empty(), "the picker finds the raised wall")
	assert_not_null(marched, "and so does the march")
	assert_eq(picked["part"], wall)
	assert_eq(marched.part, wall)
	assert_almost_eq(float(picked["t"]), marched.t, 0.0001, "at the same distance")


## Joints are aimable in the march exactly as they are in the plane, or every
## joint hit would read as a disagreement between the two models for no reason
## other than one of them not knowing joints exist.
func test_a_joint_is_a_candidate_in_the_march() -> void:
	var torso: Part = _box_part(&"torso", Vector3(0.6, 1.2, 0.4))
	torso.volume = [Box.new(Vector3(0.0, 0.9, 0.0), Vector3(0.6, 1.2, 0.4))]
	# **The arm hangs OUTWARD from the joint, not centred on it.** The first
	# version of this fixture centred a 0.2 x 0.2 x 0.6 arm on the socket, which
	# entirely swallows the 0.12 joint cube — the joint was then unreachable by
	# construction, and the test was measuring the fixture rather than the march.
	# The plane would not have hit it either, for the same reason
	# (`_JOINT_DEPTH_BIAS` deliberately puts a joint behind flush geometry).
	var arm: Part = _box_part(&"arm", Vector3(0.6, 0.2, 0.2))
	arm.attaches_to = [&"SHOULDER"]
	arm.volume = [Box.new(Vector3(0.4, 0.0, 0.0), Vector3(0.6, 0.2, 0.2))]
	var socket := Socket.new(&"SHOULDER")
	socket.occupant = arm
	socket.transform = Transform3D(Basis(), Vector3(0.8, 1.0, 0.0))
	torso.sockets = [socket]
	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(8, 5))

	var joints := 0
	for placement: BoxPlacement in UnitGeometry.placements(unit, null, null, true):
		if placement.socket != null:
			joints += 1
	assert_eq(joints, 1, "one occupied socket, one joint placement")

	var without := 0
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		if placement.socket != null:
			without += 1
	assert_eq(without, 0, "and none at all unless asked for — the view never wants them")

	var grid: Grid = _room()
	var state := CombatState.new(grid, [unit])
	# Fired down the one lane where the joint is the only thing standing: the
	# torso spans x 7.7-8.3, the arm x 8.9-9.5, and the joint cube x 8.74-8.86.
	var hit: RayHit = RayCaster.cast(state, Vector3(8.8, 1.0, 1.0), Vector3(0, 0, 1))
	assert_not_null(hit)
	assert_eq(hit.kind, RayHit.KIND_JOINT, "the joint is what stands there")
	assert_not_null(hit.socket, "and it carries the socket resolution diverts on")
	assert_eq(hit.part, socket.joint_handle(), "reported as the joint handle, never the occupant")


## Determinism, at the level the march itself controls. Traversal is geometric —
## nearest `t` wins — rather than dictionary order, which is a stronger guarantee
## than the plane's `sort_custom` over `Dictionary` iteration.
func test_the_same_ray_resolves_identically_across_runs() -> void:
	var grid: Grid = _room()
	var shooter: Unit = _unit_at(Vector2i(5, 5))
	var state := CombatState.new(grid, [shooter])
	var excluded: Array[Part] = shooter.shell.all_parts_with_joints()
	for angle in range(0, 360, 17):
		var rad: float = deg_to_rad(angle)
		var dir := Vector3(cos(rad), 0.0, sin(rad))
		var first: RayHit = RayCaster.cast(state, Vector3(5.0, AIM_HEIGHT, 5.0), dir, excluded)
		var second: RayHit = RayCaster.cast(state, Vector3(5.0, AIM_HEIGHT, 5.0), dir, excluded)
		assert_eq(first == null, second == null, "same answer about whether anything was hit")
		if first != null:
			assert_eq(first.cell, second.cell, "same cell at %d degrees" % angle)
			assert_eq(first.part, second.part, "same part at %d degrees" % angle)
			assert_almost_eq(first.t, second.t, 0.0, "same distance at %d degrees" % angle)
