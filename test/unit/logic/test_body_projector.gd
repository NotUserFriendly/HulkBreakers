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

	return Unit.new(Matrix.new(), Frame.new(torso), Vector2i(0, 0))


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
	var unit := Unit.new(Matrix.new(), Frame.new(torso), Vector2i(0, 0))

	var front: Region = BodyProjector.project(unit, Vector2(0, -1))[0]
	assert_eq(front.surface_normal, Vector3(0.0, 0.0, 1.0), "front hit: the front face was hit")

	var flank: Region = BodyProjector.project(unit, Vector2(1, 0))[0]
	assert_eq(flank.surface_normal, Vector3(-1.0, 0.0, 0.0), "flank hit: the side face was hit")
