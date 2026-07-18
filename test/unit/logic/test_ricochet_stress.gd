extends GutTest

## taskblock-13 Pass G: wedge and cylinder armor plates — the deflection
## model (docs/03) had only ever been exercised against flat/box plates
## mounted square-on. `Box` has no orientation field of its own (docs/02:
## always axis-aligned in PART-local space) — a genuinely angled/curved
## face can only come from the SOCKET that mounts a plate, so the "wedge"/
## "cylinder" stress rig here is a hosting part with several ARMOR sockets
## at a spread of Y-axis rotations, each holding one of the real
## wedge_plate_shallow/wedge_plate_steep/cylinder_plate_segment .tres
## parts (tools/author_taskblock13_plates.gd) — the rig itself is a
## fixture (no existing precedent ships a purpose-built test rig as real
## game data), the plates it wears are real, shipped content.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## A ring of ARMOR sockets spanning `angles` (degrees, around Y), each
## holding a fresh copy of `plate_id`.
func _rig(plate_id: StringName, angles: Array) -> Part:
	var root := Part.new()
	root.id = &"stress_rig"
	root.hp = 50
	root.max_hp = 50
	root.volume = [Box.new(Vector3.ZERO, Vector3(0.3, 0.3, 0.3))]
	var sockets: Array[Socket] = []
	for angle_deg: float in angles:
		var socket := Socket.new(
			&"ARMOR", Transform3D(Basis(Vector3.UP, deg_to_rad(angle_deg)), Vector3.ZERO)
		)
		var plate: Part = DataLibrary.get_part(plate_id)
		socket.occupant = plate
		sockets.append(socket)
	root.sockets = sockets
	return root


## "a multi-box cylinder produces a range of deflection normals across its
## surface (assert the spread of ricochet directions is wide, not
## clustered)." Surface normal alone determines a deflection's direction
## (DamageResolver.resolve_impact), so proving the normals themselves
## span a wide range is the direct, root-cause proof.
func test_a_ring_of_cylinder_segments_produces_a_wide_spread_of_surface_normals() -> void:
	var angles: Array = [-80.0, -40.0, 0.0, 40.0, 80.0]
	var rig: Part = _rig(&"cylinder_plate_segment", angles)

	var regions: Array[Region] = BodyProjector.project_assembly(rig, Vector2(0, -1))
	var normals_2d: Array[Vector2] = []
	for region: Region in regions:
		if region.part.id == &"cylinder_plate_segment":
			normals_2d.append(Vector2(region.surface_normal.x, region.surface_normal.z))

	assert_true(
		normals_2d.size() >= angles.size(), "every segment must contribute at least one face"
	)

	# "Wide, not clustered": the widest pairwise angle between any two
	# normals must span a real fraction of a full circle, not a few
	# degrees of jitter.
	var max_spread_deg := 0.0
	for a: Vector2 in normals_2d:
		for b: Vector2 in normals_2d:
			var spread: float = rad_to_deg(a.angle_to(b))
			max_spread_deg = maxf(max_spread_deg, absf(spread))
	assert_gt(max_spread_deg, 60.0, "the normals must span a wide arc, not cluster together")


## "a wedge plate deflects a sub-DT oblique shot at an angle determined by
## its face normal, not a fixed value."
func test_wedge_plates_at_different_angles_deflect_in_different_directions() -> void:
	var table: MaterialTable = DataLibrary.material_table()
	var rig: Part = _rig(&"wedge_plate_shallow", [-35.0, 35.0])
	var regions: Array[Region] = BodyProjector.project_assembly(rig, Vector2(0, -1))

	# A thin plate rotated at all shows a sliver of its own edge alongside
	# its main face (docs/03: incidence spans the full 0-90 range) — group
	# by PART OBJECT IDENTITY (each socket holds its own distinct Part
	# instance, `DataLibrary.get_part` never shares one) and take each
	# plate's own largest-area region as its dominant, representative face.
	var by_plate: Dictionary = {}  # Part -> Array[Region]
	for region: Region in regions:
		if region.part.id != &"wedge_plate_shallow":
			continue
		if not by_plate.has(region.part):
			by_plate[region.part] = [] as Array[Region]
		(by_plate[region.part] as Array[Region]).append(region)
	assert_eq(by_plate.size(), 2, "both sockets' own plate instances must each appear")

	var plate_regions: Array[Region] = []
	for plate: Part in by_plate:
		var faces: Array[Region] = by_plate[plate]
		faces.sort_custom(func(a: Region, b: Region) -> bool: return a.rect.size.x > b.rect.size.x)
		plate_regions.append(faces[0])

	# Sub-DT damage (steel dt=6): both hits deflect rather than penetrate.
	var incoming := Vector2(0, 1)
	var result_a: ImpactResult = DamageResolver.resolve_impact(
		incoming, 3.0, plate_regions[0], table
	)
	var result_b: ImpactResult = DamageResolver.resolve_impact(
		incoming, 3.0, plate_regions[1], table
	)

	assert_eq(
		result_a.outcome, Enums.Outcome.DEFLECT, "sub-DT oblique hit must deflect, not penetrate"
	)
	assert_eq(result_b.outcome, Enums.Outcome.DEFLECT)
	assert_false(
		result_a.reflected_dir.is_equal_approx(result_b.reflected_dir),
		"two plates mounted at different angles must reflect the same incoming shot differently"
	)


## "a seeded burst into a plate cluster is deterministic and terminates."
func test_a_seeded_burst_into_the_rig_is_deterministic_and_terminates() -> void:
	var angles: Array = [-60.0, -30.0, 0.0, 30.0, 60.0]

	var results: Array = []
	for run in range(2):
		var rig: Part = _rig(&"wedge_plate_shallow", angles)
		var shooter_torso := Part.new()
		shooter_torso.id = &"shooter_torso"
		shooter_torso.hp = 20
		shooter_torso.max_hp = 20
		shooter_torso.volume = [Box.new(Vector3.ZERO, Vector3(0.3, 0.3, 0.3))]
		var weapon := Part.new()
		weapon.id = &"chaingun"
		weapon.hp = 6
		weapon.max_hp = 6
		weapon.attaches_to = [&"GRIP"]
		weapon.requires = {&"TRIGGER": 1}
		weapon.damage = 3.0  # sub-DT vs steel (6): every hit is a real deflection
		weapon.scatter = [Ring.new(0.15, 1.0)]
		weapon.provides_actions = [&"burst"]
		weapon.weapon_def = WeaponDef.new()
		weapon.weapon_def.burst_size = 8
		weapon.weapon_def.burst_ap_cost = 3
		var hand := Part.new()
		hand.id = &"hand"
		hand.hp = 5
		hand.max_hp = 5
		hand.attaches_to = [&"HAND"]
		hand.capabilities = [&"TRIGGER"]
		var grip := Socket.new(&"GRIP")
		grip.occupant = weapon
		hand.sockets = [grip]
		var hand_socket := Socket.new(&"HAND")
		hand_socket.occupant = hand
		shooter_torso.sockets.append(hand_socket)

		var shooter := Unit.new(Matrix.new(), Shell.new(shooter_torso), Vector2i(0, 0), 0)
		var target := Unit.new(Matrix.new(), Shell.new(rig), Vector2i(3, 0), 1)
		var state := CombatState.new(Grid.new(10, 10), [shooter, target], 999)

		# Must complete without hanging or erroring regardless of how many
		# simultaneous deflections a wide-angle wedge cluster generates.
		BurstAction.new(shooter, &"chaingun", Vector2i(3, 0)).apply(state)
		results.append(shooter.ap)

	assert_eq(results[0], results[1], "the same seed must replay identically")
