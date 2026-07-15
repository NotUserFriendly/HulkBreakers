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
		var region: Region = BodyProjector.project_part(part, view_dir)[0]
		positions.append(region.rect.position.x)
		seen_x[snappedf(region.rect.position.x, 0.0001)] = true

	assert_eq(
		seen_x.size(), SAMPLES, "no two of %d evenly-spaced angles should snap to the same rect"
	)

	var max_jump := 0.0
	for i in range(1, positions.size()):
		max_jump = maxf(max_jump, absf(positions[i] - positions[i - 1]))
	assert_true(max_jump < 1.0, "adjacent angles must not produce a discontinuous jump")


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
