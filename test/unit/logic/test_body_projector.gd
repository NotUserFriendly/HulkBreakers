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


func test_the_same_arm_resource_at_two_mirrored_sockets_projects_in_two_places() -> void:
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


func test_the_same_weapon_on_left_vs_right_shoulder_projects_at_different_x() -> void:
	var weapon := Part.new()
	weapon.id = &"rifle"
	weapon.hp = 2
	weapon.max_hp = 2
	weapon.volume = [Box.new(Vector3.ZERO, Vector3(0.1, 0.15, 0.7))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var left := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(-1.0, 0.5, 0.0)))
	var right := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(1.0, 0.5, 0.0)))
	left.occupant = weapon
	torso.sockets = [left]
	var unit_left := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var left_x := _center_x(BodyProjector.project(unit_left, Vector2(0, -1)))

	var torso_right := Part.new()
	torso_right.id = &"torso"
	torso_right.hp = 10
	torso_right.max_hp = 10
	right.occupant = weapon
	torso_right.sockets = [right]
	var unit_right := Unit.new(Matrix.new(), Shell.new(torso_right), Vector2i(0, 0))
	var right_x := _center_x(BodyProjector.project(unit_right, Vector2(0, -1)))

	assert_ne(left_x, right_x, "the same weapon Part must project differently per shoulder")


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
