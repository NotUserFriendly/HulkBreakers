extends GutTest

## Checkpoint 2 artifact (docs/09): one cyborg's shot plane dumped from 12
## angles swept continuously around a full circle, so a human can eyeball
## "do the boxes track the angle sanely" and "does the rear ammo rack
## appear only from behind." Run via ./checkpoint.sh 2 — its stdout is what
## lands in out/checkpoints/02/output.txt.

const ANGLE_COUNT := 12
const CANVAS_WIDTH := 6
const CANVAS_HEIGHT := 2
const RECENTER_X := 3.0


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


func _find(plane: Array[Region], part_id: StringName) -> Region:
	for region: Region in plane:
		if region.part.id == part_id:
			return region
	return null


## The rack only reads as "visible" if it wins depth against the torso —
## same rule resolve_projectile uses at any shared pixel.
func _rack_wins_depth(plane: Array[Region]) -> bool:
	var torso := _find(plane, &"torso")
	var rack := _find(plane, &"rack")
	return rack.depth < torso.depth


func test_shot_plane_sweeps_continuously_across_a_dozen_angles() -> void:
	var unit := _torso_with_rear_ammo_rack()

	var previous_torso_x := INF
	var rack_visible_count := 0

	for i in range(ANGLE_COUNT):
		var angle: float = i * TAU / ANGLE_COUNT
		var view_dir := Vector2(cos(angle), sin(angle))
		var plane: Array[Region] = BodyProjector.project(unit, view_dir)
		plane.sort_custom(func(a: Region, b: Region) -> bool: return a.depth < b.depth)

		print("\n=== angle %d/%d (%.0f deg) ===" % [i + 1, ANGLE_COUNT, rad_to_deg(angle)])
		print(
			AsciiRender.plane_to_text(
				AsciiRender.recenter(plane, RECENTER_X), CANVAS_WIDTH, CANVAS_HEIGHT
			)
		)

		var torso_x: float = _find(plane, &"torso").rect.position.x
		if previous_torso_x != INF:
			var jump: float = absf(torso_x - previous_torso_x)
			assert_true(jump < 1.0, "angle %d: torso rect must not pop between adjacent angles" % i)
		previous_torso_x = torso_x

		if _rack_wins_depth(plane):
			rack_visible_count += 1

	assert_true(rack_visible_count > 0, "the rack must win depth from some angles")
	assert_true(
		rack_visible_count < ANGLE_COUNT,
		"the rack must NOT win depth from every angle — it's mounted on the back"
	)
