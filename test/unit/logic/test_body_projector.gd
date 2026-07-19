extends GutTest

## docs/02: no facings, continuous projection. All view_dir values are
## "direction of travel" — the way a shot moving from the shooter into the
## world would go — so a part with a *lower* depth is physically nearer the
## shooter and occludes anything with a higher depth behind it.


func _find(regions: Array[Region], part_id: StringName) -> Region:
	for region: Region in regions:
		if region.part.id == part_id:
			return region
	fail_test("no region for part %s" % part_id)
	return null


## The min x across every visible face's rect — a box can show 1 or 2 faces
## now, but their union is the same whole-box silhouette the old single-rect
## model produced, so continuity is a property of the union, not of any one
## face.
func _union_min_x(regions: Array[Region]) -> float:
	var result := INF
	for region: Region in regions:
		result = minf(result, region.rect.position.x)
	return result


func test_rotating_view_angle_produces_continuously_changing_rects() -> void:
	var part := Part.new()
	part.id = &"plate"
	part.hp = 1
	part.max_hp = 1
	part.volume = [Box.new(Vector3(0.4, 0.5, 0.3), Vector3(0.6, 1.0, 0.6))]

	var seen_x: Dictionary = {}
	var positions: Array[float] = []
	const SAMPLES := 16
	for i in range(SAMPLES):
		var angle: float = i * TAU / SAMPLES
		var view_dir := Vector2(cos(angle), sin(angle))
		var regions: Array[Region] = BodyProjector.project_part(part, view_dir)
		var min_x: float = _union_min_x(regions)
		positions.append(min_x)
		seen_x[snappedf(min_x, 0.0001)] = true

	assert_eq(
		seen_x.size(), SAMPLES, "no two of %d evenly-spaced angles should snap to the same rect"
	)

	var max_jump := 0.0
	for i in range(1, positions.size()):
		max_jump = maxf(max_jump, absf(positions[i] - positions[i - 1]))
	assert_true(max_jump < 1.0, "adjacent angles must not produce a discontinuous jump")


## docs/03: a box viewed corner-on shows two faces in adjacent, non-
## overlapping screen spans whose union reconstructs exactly the silhouette
## the old single-whole-box projection produced — the split must not change
## the shape of anything, only which surface_normal each slice reports.
func test_visible_face_rects_union_to_the_same_silhouette_as_the_whole_box() -> void:
	var box := Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 1.4))
	var orientation := 0.0
	var dir := Vector2(3, 4).normalized()  # oblique: two faces visible
	var perp := Vector2(-dir.y, dir.x)

	var half := box.size * 0.5
	var whole_box_xs: Array[float] = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var local := Vector2(box.center.x + sx * half.x, box.center.z + sz * half.z)
			whole_box_xs.append(local.rotated(orientation).dot(perp))
	var whole_min: float = whole_box_xs.min()
	var whole_max: float = whole_box_xs.max()

	var part := Part.new()
	part.id = &"box"
	part.hp = 1
	part.max_hp = 1
	part.volume = [box]
	var regions: Array[Region] = BodyProjector.project_part(part, dir, orientation)

	assert_eq(regions.size(), 2, "an oblique corner-on view must show exactly two faces")
	var union_min := INF
	var union_max := -INF
	for region: Region in regions:
		union_min = minf(union_min, region.rect.position.x)
		union_max = maxf(union_max, region.rect.position.x + region.rect.size.x)
	assert_almost_eq(union_min, whole_min, 0.0001)
	assert_almost_eq(union_max, whole_max, 0.0001)

	# Non-overlapping: the two faces tile the silhouette, they don't double it.
	var total_face_width: float = 0.0
	for region: Region in regions:
		total_face_width += region.rect.size.x
	assert_almost_eq(total_face_width, whole_max - whole_min, 0.0001)


## The old "pick whichever face is closest" model capped incidence at 45
## degrees by construction. Per-face projection removes that ceiling: a
## nearly-edge-on secondary face reads a steep, near-grazing incidence.
func test_a_near_edge_on_face_reads_incidence_well_past_45_degrees() -> void:
	var part := Part.new()
	part.id = &"box"
	part.hp = 1
	part.max_hp = 1
	part.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var dir := Vector2(0.1, -0.995).normalized()
	var regions: Array[Region] = BodyProjector.project_part(part, dir)
	assert_eq(regions.size(), 2, "a near-axis-aligned direction still shows a sliver side face")

	var max_incidence_deg := 0.0
	for region: Region in regions:
		var normal_2d := Vector2(region.surface_normal.x, region.surface_normal.z)
		var incidence: float = rad_to_deg(acos(clampf((-dir).dot(normal_2d), -1.0, 1.0)))
		max_incidence_deg = maxf(max_incidence_deg, incidence)

	assert_true(
		max_incidence_deg > 45.0,
		"the near-edge-on face must read well past the old 45 degree ceiling"
	)


func _torso_with_rear_ammo_rack() -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var rack := Part.new()
	rack.id = &"rack"
	rack.hp = 5
	rack.max_hp = 5
	rack.attaches_to = [&"BACK"]
	rack.volume = [Box.new(Vector3(0.0, 0.5, -0.3), Vector3(0.8, 1.0, 0.2))]

	var socket := Socket.new(&"BACK")
	socket.occupant = rack
	torso.sockets = [socket]

	return Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))


func test_rear_part_is_occluded_from_the_front_but_frontmost_from_behind() -> void:
	var unit := _torso_with_rear_ammo_rack()

	var front: Array[Region] = BodyProjector.project(unit, Vector2(0, -1))
	var torso_front := _find(front, &"torso")
	var rack_front := _find(front, &"rack")
	assert_true(torso_front.depth < rack_front.depth, "front view: torso must occlude the rack")

	var rear: Array[Region] = BodyProjector.project(unit, Vector2(0, 1))
	var torso_rear := _find(rear, &"torso")
	var rack_rear := _find(rear, &"rack")
	assert_true(rack_rear.depth < torso_rear.depth, "rear view: the rack must be frontmost")

	print("\n=== rear ammo rack: viewed from the front (rack fully hidden) ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(front, 2.0), 4, 2))
	print("\n=== rear ammo rack: viewed from behind (rack now frontmost) ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(rear, 2.0), 4, 2))


func test_surface_normal_is_the_actual_face_hit_not_always_toward_the_shooter() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))

	var front: Region = BodyProjector.project(unit, Vector2(0, -1))[0]
	assert_eq(front.surface_normal, Vector3(0.0, 0.0, 1.0), "front hit: the front face was hit")

	var flank: Region = BodyProjector.project(unit, Vector2(1, 0))[0]
	assert_eq(flank.surface_normal, Vector3(-1.0, 0.0, 0.0), "flank hit: the side face was hit")


## Phase 12.0: Socket.transform makes modularity geometrically real. A box's
## `volume` is authored part-local (near its own origin); where it actually
## lands is entirely the hosting socket's composed transform.
func _small_box_part(id: StringName) -> Part:
	var part := Part.new()
	part.id = id
	part.hp = 4
	part.max_hp = 4
	part.volume = [Box.new(Vector3.ZERO, Vector3(0.4, 0.9, 0.4))]
	return part


func _center_x(regions: Array[Region]) -> float:
	var min_x := INF
	var max_x := -INF
	for region: Region in regions:
		min_x = minf(min_x, region.rect.position.x)
		max_x = maxf(max_x, region.rect.position.x + region.rect.size.x)
	return (min_x + max_x) * 0.5


func test_the_same_arm_resource_projects_per_socket_transform_together_and_alone() -> void:
	var arm := _small_box_part(&"arm")

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var left := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(-1.0, 0.5, 0.0)))
	var right := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(1.0, 0.5, 0.0)))
	left.occupant = arm
	right.occupant = arm  # the exact same Part resource, not a duplicate
	torso.sockets = [left, right]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var regions: Array[Region] = BodyProjector.project(unit, Vector2(0, -1))

	var arm_regions: Array[Region] = []
	for region: Region in regions:
		if region.part == arm:
			arm_regions.append(region)
	assert_eq(arm_regions.size(), 2, "the shared resource must project once per socket")

	var region_a := [arm_regions[0]] as Array[Region]
	var region_b := [arm_regions[1]] as Array[Region]
	assert_ne(
		_center_x(region_a),
		_center_x(region_b),
		"two sockets sharing one Part resource must still project at two different places"
	)

	# The same claim again, one socket transform at a time rather than both
	# at once (taskblock-12 Pass B: merged from a standalone test — strictly
	# weaker than the dual-socket case just proven above, since it never
	# exercises them in the same tree-walk, but its own assertion is kept
	# rather than dropped).
	var solo_left := Socket.new(&"SHOULDER", left.transform)
	solo_left.occupant = arm
	var torso_left := Part.new()
	torso_left.id = &"torso"
	torso_left.hp = 10
	torso_left.max_hp = 10
	torso_left.sockets = [solo_left]
	var unit_left := Unit.new(Matrix.new(), Shell.new(torso_left), Vector2i(0, 0))
	var left_x: float = _center_x(BodyProjector.project(unit_left, Vector2(0, -1)))

	var solo_right := Socket.new(&"SHOULDER", right.transform)
	solo_right.occupant = arm
	var torso_right := Part.new()
	torso_right.id = &"torso"
	torso_right.hp = 10
	torso_right.max_hp = 10
	torso_right.sockets = [solo_right]
	var unit_right := Unit.new(Matrix.new(), Shell.new(torso_right), Vector2i(0, 0))
	var right_x: float = _center_x(BodyProjector.project(unit_right, Vector2(0, -1)))

	assert_ne(left_x, right_x, "the same Part must also project differently one socket at a time")


func test_twelve_shoulder_sockets_project_twelve_non_overlapping_arms() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10

	const SOCKET_COUNT := 12
	const SPACING := 0.6  # wider than the arm box (0.4) so none can overlap
	var sockets: Array[Socket] = []
	for i in range(SOCKET_COUNT):
		var x: float = (i - (SOCKET_COUNT - 1) / 2.0) * SPACING
		var socket := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(x, 0.5, 0.0)))
		socket.occupant = _small_box_part(StringName("arm_%d" % i))
		sockets.append(socket)
	torso.sockets = sockets

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var regions: Array[Region] = BodyProjector.project(unit, Vector2(0, -1))

	var arm_ids: Array[StringName] = []
	for socket: Socket in sockets:
		arm_ids.append(socket.occupant.id)

	var centers: Array[float] = []
	for arm_id: StringName in arm_ids:
		var arm_regions: Array[Region] = []
		for region: Region in regions:
			if region.part.id == arm_id:
				arm_regions.append(region)
		assert_true(arm_regions.size() > 0, "arm %s must appear in the plane" % arm_id)
		centers.append(_center_x(arm_regions))

	centers.sort()
	assert_eq(centers.size(), SOCKET_COUNT)
	for i in range(1, centers.size()):
		assert_true(
			centers[i] - centers[i - 1] > 0.0001,
			"12 shoulder sockets must produce 12 distinct, non-overlapping positions"
		)


## shoulder -> upper_arm -> forearm -> hand -> pistol: a deep chain composes,
## so rotating the shoulder socket must move the pistol at the far end.
func _deep_chain_torso(shoulder_transform: Transform3D) -> Part:
	var pistol := _small_box_part(&"pistol")
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	var grip := Socket.new(&"GRIP", Transform3D(Basis(), Vector3(0.0, 0.0, 0.2)))
	grip.occupant = pistol
	hand.sockets = [grip]

	var forearm := Part.new()
	forearm.id = &"forearm"
	forearm.hp = 4
	forearm.max_hp = 4
	var wrist := Socket.new(&"WRIST", Transform3D(Basis(), Vector3(0.0, -0.5, 0.0)))
	wrist.occupant = hand
	forearm.sockets = [wrist]

	var upper_arm := Part.new()
	upper_arm.id = &"upper_arm"
	upper_arm.hp = 5
	upper_arm.max_hp = 5
	var elbow := Socket.new(&"FOREARM", Transform3D(Basis(), Vector3(0.0, -0.5, 0.0)))
	elbow.occupant = forearm
	upper_arm.sockets = [elbow]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var shoulder := Socket.new(&"SHOULDER", shoulder_transform)
	shoulder.occupant = upper_arm
	torso.sockets = [shoulder]
	return torso


func test_rotating_the_shoulder_socket_moves_the_pistol_at_the_end_of_the_chain() -> void:
	var straight := Transform3D(Basis(), Vector3(1.0, 0.5, 0.0))
	var unit_straight := Unit.new(
		Matrix.new(), Shell.new(_deep_chain_torso(straight)), Vector2i(0, 0)
	)
	var straight_x := _center_x(
		_find_all(BodyProjector.project(unit_straight, Vector2(0, -1)), &"pistol")
	)

	var rotated := Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)), Vector3(1.0, 0.5, 0.0))
	var unit_rotated := Unit.new(
		Matrix.new(), Shell.new(_deep_chain_torso(rotated)), Vector2i(0, 0)
	)
	var rotated_x := _center_x(
		_find_all(BodyProjector.project(unit_rotated, Vector2(0, -1)), &"pistol")
	)

	assert_ne(
		straight_x, rotated_x, "rotating the shoulder socket must move the pistol at the far end"
	)


## docs/10 taskblock05 F2: "AIMING changes the projected shot plane vs
## IDLE" — the mechanic itself, asserted: a pose is never cosmetic, it
## moves real geometry BodyProjector.project() (and therefore the shot
## plane) reads.
func test_aiming_pose_changes_the_projected_shot_plane_vs_idle() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 4
	# Offset off its own socket origin — a box centered exactly on the
	# joint it rotates around would never visibly move, rotation or not.
	arm.volume = [Box.new(Vector3(0.0, -0.3, 0.0), Vector3(0.4, 0.9, 0.4))]
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var shoulder_r := Socket.new(
		&"SHOULDER", Transform3D(Basis(), Vector3(0.31, 1.53, 0.0)), &"SHOULDER_R"
	)
	shoulder_r.occupant = arm
	torso.sockets = [shoulder_r]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var idle_regions: Array[Region] = _find_all(BodyProjector.project(unit, Vector2(0, -1)), &"arm")

	unit.pose = Poses.aiming()
	var aiming_regions: Array[Region] = _find_all(
		BodyProjector.project(unit, Vector2(0, -1)), &"arm"
	)

	# AIMING rotates the shoulder about the horizontal (RIGHT) axis, which
	# moves height/depth, not lateral spread (_center_x, this view's world
	# X) — depth is what actually shifts here.
	var idle_depth := INF
	for region: Region in idle_regions:
		idle_depth = minf(idle_depth, region.depth)
	var aiming_depth := INF
	for region: Region in aiming_regions:
		aiming_depth = minf(aiming_depth, region.depth)

	assert_ne(
		idle_depth, aiming_depth, "AIMING must actually move the arm's projected region vs IDLE"
	)


func _find_all(regions: Array[Region], part_id: StringName) -> Array[Region]:
	var found: Array[Region] = []
	for region: Region in regions:
		if region.part.id == part_id:
			found.append(region)
	return found


## docs/09 taskblock06 Pass I2 TESTS: "the shot plane is identical
## regardless of what's rendered — the mesh must never affect resolution."
## A part's own `mesh_scene` is purely HitVolumeView's concern
## (src/view/); BodyProjector reads `volume` alone, so setting/clearing
## mesh_scene must never change a single projected Region.
func test_setting_mesh_scene_never_changes_the_projected_shot_plane() -> void:
	var part := Part.new()
	part.id = &"plate"
	part.hp = 1
	part.max_hp = 1
	part.volume = [Box.new(Vector3(0.4, 0.5, 0.3), Vector3(0.6, 1.0, 0.6))]
	var unit := Unit.new(Matrix.new(), Shell.new(part), Vector2i(0, 0))

	var without_mesh: Array[Region] = BodyProjector.project(unit, Vector2(0.0, -1.0))

	part.mesh_scene = PackedScene.new()
	var with_mesh: Array[Region] = BodyProjector.project(unit, Vector2(0.0, -1.0))

	assert_eq(without_mesh.size(), with_mesh.size())
	for i in range(without_mesh.size()):
		assert_eq(without_mesh[i].rect, with_mesh[i].rect)
		assert_almost_eq(without_mesh[i].depth, with_mesh[i].depth, 0.0001)
		assert_eq(without_mesh[i].part, with_mesh[i].part)


## docs/09 taskblock07 Pass B1a: the load-bearing proof. An asymmetric unit
## (a part on ONE side only) at a non-axis, non-symmetric orientation must
## render and project on the exact SAME side — if BodyProjector and
## UnitGeometry ever disagreed about which way "left" rotates, it would be
## invisible in every symmetric fixture (front-vs-back is symmetric) but
## is caught immediately here (left-vs-right is not).
func test_an_asymmetric_part_projects_on_the_same_side_it_renders() -> void:
	var pod := Part.new()
	pod.id = &"pod"
	pod.hp = 1
	pod.max_hp = 1
	pod.volume = [Box.new(Vector3.ZERO, Vector3(0.2, 0.2, 0.2))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 1
	torso.max_hp = 1
	# One side only — a socket offset along local -Z, nothing on +Z.
	var pod_socket := Socket.new(&"POD", Transform3D(Basis(), Vector3(0.0, 0.0, -0.5)))
	pod_socket.occupant = pod
	torso.sockets = [pod_socket]

	var orientation := deg_to_rad(85.0)
	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	unit.orientation = orientation

	# What actually renders (UnitGeometry — the ground truth HitVolumeView
	# draws exactly).
	var placement: BoxPlacement = null
	for candidate: BoxPlacement in UnitGeometry.placements(unit):
		if candidate.part == pod:
			placement = candidate
	assert_not_null(placement)
	var rendered_x: float = (placement.transform * placement.box.center).x

	# What the shot plane puts there — view_dir (0,-1) makes `perp` exactly
	# world +X, so a Region's own rect-center x IS the world x directly, no
	# screen-space translation needed to compare the two.
	var regions: Array[Region] = BodyProjector.project(unit, Vector2(0.0, -1.0))
	var pod_region: Region = _find(regions, &"pod")
	var projected_x: float = pod_region.rect.get_center().x

	assert_true(absf(rendered_x) > 0.1, "sanity: the pod must actually sit off-center")
	assert_eq(
		signf(projected_x),
		signf(rendered_x),
		"the shot plane must put the pod on the same side it actually renders"
	)
	assert_almost_eq(projected_x, rendered_x, 0.01)


## taskblock-17 Pass B: `orientation_for` is the formal inverse of
## `forward_for` — for a spread of directions across every quadrant
## (never just the axis-aligned ones an earlier, buggy formula happened
## to get right), round-tripping through both must land back on the
## original direction. This is the general form of the bug
## `FaceAction.orientation_toward` shipped with: `WORLD_FORWARD.angle_to
## (delta)` (Vector2.rotated()'s own STANDARD convention) instead of this
## file's own established, mirrored one — correct only when the target
## sat dead ahead, up to 180 degrees off everywhere else.
func test_orientation_for_round_trips_through_forward_for_across_every_quadrant() -> void:
	var directions: Array[Vector2] = [
		Vector2(1.0, 0.0),
		Vector2(0.0, 1.0),
		Vector2(-1.0, 0.0),
		Vector2(0.0, -1.0),
		Vector2(1.0, 1.0),
		Vector2(-1.0, 1.0),
		Vector2(-1.0, -1.0),
		Vector2(1.0, -1.0),
		Vector2(1.0, 3.0),
		Vector2(-2.0, 1.0),
	]
	for direction: Vector2 in directions:
		var normalized: Vector2 = direction.normalized()
		var orientation: float = BodyProjector.orientation_for(normalized)
		var round_tripped: Vector2 = BodyProjector.forward_for(orientation)
		assert_almost_eq(
			round_tripped.x, normalized.x, 0.0001, "direction %s round-trip x" % direction
		)
		assert_almost_eq(
			round_tripped.y, normalized.y, 0.0001, "direction %s round-trip y" % direction
		)


## docs/09 taskblock07 Pass B1/TESTS: "grep finds no `.rotated(orientation)`
## outside the single helper" — rotate_by_orientation/forward_for are the
## ONE place a body-local point or facing direction gets turned into world
## space by a unit's own orientation; every other spot doing this via
## Vector2.rotated() directly is the OTHER, mirrored convention this pass
## deleted, and must never come back.
func test_rotated_by_orientation_is_used_only_inside_body_projector_itself() -> void:
	var allowed_files: Array[String] = ["body_projector.gd"]
	var offending: Array[String] = []
	_scan_dir_for_rotated_orientation("res://src", allowed_files, offending)
	assert_eq(
		offending,
		[] as Array[String],
		"Vector2.rotated(orientation) used outside body_projector.gd: %s" % [offending]
	)


func _scan_dir_for_rotated_orientation(
	path: String, allowed_files: Array[String], offending: Array[String]
) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue
		var full_path: String = path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir_for_rotated_orientation(full_path, allowed_files, offending)
		elif entry.ends_with(".gd") and not allowed_files.has(entry):
			var text: String = FileAccess.get_file_as_string(full_path)
			if (
				text.contains(".rotated(orientation")
				or text.contains(".rotated(overwatcher.orientation")
			):
				offending.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


## taskblock-09 A1/A2: a MANGLE/DISABLE-failed part stays fully attached
## (docs/03) — the old blanket "hp<=0 vanishes" rule would have made it
## silently untargetable, which contradicts "sockets stay live and
## hittable." A DETONATE/FRAGMENT/MELTDOWN-consumed part still vanishes
## exactly like before; only the two attached failure modes are exempt.
func test_a_mangled_or_disabled_part_still_projects_at_zero_hp() -> void:
	var mangled := Part.new()
	mangled.id = &"mangled"
	mangled.hp = 0
	mangled.max_hp = 3
	mangled.is_mangled = true
	mangled.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.5, 0.5))]
	assert_false(
		BodyProjector.project_part(mangled, Vector2(0, 1)).is_empty(),
		"a mangled part must still occlude/be hittable"
	)

	var disabled := Part.new()
	disabled.id = &"disabled"
	disabled.hp = 0
	disabled.max_hp = 3
	disabled.is_disabled = true
	disabled.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.5, 0.5))]
	assert_false(
		BodyProjector.project_part(disabled, Vector2(0, 1)).is_empty(),
		"a disabled part must still occlude/be hittable"
	)


func test_a_plain_destroyed_part_still_vanishes_at_zero_hp() -> void:
	var consumed := Part.new()
	consumed.id = &"consumed"
	consumed.hp = 0
	consumed.max_hp = 3
	consumed.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.5, 0.5))]
	assert_eq(
		BodyProjector.project_part(consumed, Vector2(0, 1)),
		[] as Array[Region],
		"a part destroyed with neither flag set (DETONATE/FRAGMENT/MELTDOWN) still vanishes"
	)


## taskblock-09 D: an occupied socket must produce at least one aimable
## region tagged with that exact socket — the actual discriminator
## resolve_shot reads to divert into joint damage.
func test_an_occupied_socket_produces_an_aimable_joint_region_at_its_transform() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var arm := _small_box_part(&"arm")
	var shoulder := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(1.3, 0.5, 0.0)))
	shoulder.occupant = arm
	torso.sockets = [shoulder]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var regions: Array[Region] = BodyProjector.project(unit, Vector2(0, -1))

	var joint_regions: Array[Region] = []
	for region: Region in regions:
		if region.socket == shoulder:
			joint_regions.append(region)
	assert_false(
		joint_regions.is_empty(), "an occupied socket must produce an aimable joint region"
	)
	for region: Region in joint_regions:
		assert_eq(region.part, shoulder.joint_handle())


func test_an_empty_socket_has_no_region() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	torso.sockets = [Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(1.3, 0.5, 0.0)))]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var regions: Array[Region] = BodyProjector.project(unit, Vector2(0, -1))

	for region: Region in regions:
		assert_null(region.socket, "an empty socket must never produce a joint region")


## taskblock-09 D: an extra box directly on the torso's OWN volume (a
## bolted-on plate, not a separately socketed part — sidesteps that
## destroying a socketed occupant leaves ITS OWN joint region behind,
## taskblock-09 D's own second-order case, not what this test is about),
## nearer the shooter and wide enough to cover the shoulder joint's own
## small footprint. The joint only becomes reachable once that extra box
## is gone.
func test_a_joint_occluded_by_a_plate_isnt_hittable_until_the_plate_is_gone() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var body_box := Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))
	var plate_box := Box.new(Vector3(1.3, 0.5, 0.2), Vector3(0.6, 0.6, 0.1))
	torso.volume = [body_box, plate_box]

	# Offset outward from the shoulder's own attach point (like a real
	# limb extending from its joint), so the arm's own body never
	# occludes its own joint the way a zero-centered box would.
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 4
	arm.volume = [Box.new(Vector3(0.7, 0.5, 0.0), Vector3(0.6, 0.3, 0.3))]
	var shoulder := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(1.3, 0.5, 0.0)))
	shoulder.occupant = arm
	torso.sockets = [shoulder]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(2, 2))
	var state := CombatState.new(Grid.new(10, 10), [unit])

	var origin := Vector2(2, 8)
	var direction := Vector2(0, -1)
	var plane_before: Array[Region] = ShotPlane.build(origin, direction, state)

	var joint_region: Region = null
	for region: Region in plane_before:
		if region.socket == shoulder:
			joint_region = region
			break
	assert_not_null(joint_region, "the joint must still produce a region even while occluded")
	var aim_point: Vector2 = joint_region.rect.get_center()

	var hit_before: Region = ShotPlane.resolve_projectile(plane_before, aim_point)
	assert_ne(hit_before.socket, shoulder, "occluded: the plate in front must win, not the joint")

	torso.volume = [body_box]
	var plane_after: Array[Region] = ShotPlane.build(origin, direction, state)
	var hit_after: Region = ShotPlane.resolve_projectile(plane_after, aim_point)
	assert_eq(hit_after.socket, shoulder, "plate gone: the joint is finally reachable")


## taskblock-09 E: "the through axis a shot crosses" — a box's own
## MINIMUM dimension becomes the region's thickness, regardless of which
## dimension that is, so a plate authored thin along any axis is
## correctly thin for DT purposes.
func test_a_boxs_minimum_dimension_becomes_the_regions_thickness() -> void:
	var part := Part.new()
	part.id = &"plate"
	part.hp = 5
	part.max_hp = 5
	part.volume = [Box.new(Vector3.ZERO, Vector3(1.2, 0.9, 0.05))]

	var region: Region = BodyProjector.project_part(part, Vector2(0, -1))[0]
	assert_almost_eq(region.thickness, 0.05, 0.0001, "0.05 is the smallest of (1.2, 0.9, 0.05)")
