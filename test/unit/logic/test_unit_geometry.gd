extends GutTest

## docs/10 "render is hitbox": UnitGeometry.placements() must expose exactly
## the same boxes BodyProjector would hit, fully placed in world space.


func test_no_root_produces_no_placements() -> void:
	var unit := Unit.new(Matrix.new(), Shell.new(null), Vector2i(0, 0))
	assert_eq(UnitGeometry.placements(unit), [] as Array[BoxPlacement])


func test_a_single_box_root_places_at_the_units_cell() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(3, 4))
	var placements: Array[BoxPlacement] = UnitGeometry.placements(unit)

	assert_eq(placements.size(), 1)
	var world_center: Vector3 = placements[0].transform * placements[0].box.center
	assert_almost_eq(world_center.x, 3.0, 0.0001)
	assert_almost_eq(world_center.z, 4.0, 0.0001)
	assert_almost_eq(world_center.y, 0.5, 0.0001)


## taskblock-36 Pass D: "a unit on a level-1 cell has a true Y one level
## above one on level 0." `Unit.level` (not the grid — `UnitGeometry`
## never touches one) drives the root transform's own Y translation,
## `LEVEL_HEIGHT` world units per step.
func test_a_units_true_y_accounts_for_its_own_level() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var ground_unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(3, 4))
	var raised_unit := Unit.new(Matrix.new(), Shell.new(torso.duplicate(true)), Vector2i(3, 4))
	raised_unit.level = 1

	var ground_y: float = (
		(
			UnitGeometry.placements(ground_unit)[0].transform
			* UnitGeometry.placements(ground_unit)[0].box.center
		)
		. y
	)
	var raised_y: float = (
		(
			UnitGeometry.placements(raised_unit)[0].transform
			* UnitGeometry.placements(raised_unit)[0].box.center
		)
		. y
	)

	assert_almost_eq(raised_y - ground_y, UnitGeometry.LEVEL_HEIGHT, 0.0001)


## docs/10 taskblock03 E3: `orientation_override` replaces `unit.orientation`
## for this placement pass only, so a view can render TACTICS' speculative
## preview without cloning the whole Unit.
func test_orientation_override_replaces_the_units_own_orientation() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(1.0, 0.0, 0.0), Vector3(0.2, 0.2, 0.2))]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	unit.orientation = 0.0
	var default_placements: Array[BoxPlacement] = UnitGeometry.placements(unit)
	var overridden: Array[BoxPlacement] = UnitGeometry.placements(unit, PI / 2.0)

	var default_center: Vector3 = default_placements[0].transform * default_placements[0].box.center
	var overridden_center: Vector3 = overridden[0].transform * overridden[0].box.center

	assert_almost_eq(unit.orientation, 0.0, 0.0001, "the real unit must never be mutated")
	assert_false(
		default_center.is_equal_approx(overridden_center),
		"a 90-degree override must actually move the box",
	)


func test_a_null_orientation_override_is_the_same_as_omitting_it() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(1.0, 0.0, 0.0), Vector3(0.2, 0.2, 0.2))]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	unit.orientation = 1.2
	var explicit_null: Array[BoxPlacement] = UnitGeometry.placements(unit, null)
	var omitted: Array[BoxPlacement] = UnitGeometry.placements(unit)

	assert_eq(
		explicit_null[0].transform * explicit_null[0].box.center,
		omitted[0].transform * omitted[0].box.center
	)


func test_dead_parts_produce_no_placements() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 0
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(1, 1, 1))]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	assert_eq(UnitGeometry.placements(unit), [] as Array[BoxPlacement])


func test_a_destroyed_child_part_disappears_but_its_living_siblings_remain() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 0
	arm.max_hp = 4
	arm.volume = [Box.new(Vector3.ZERO, Vector3(0.4, 0.9, 0.4))]

	var leg := Part.new()
	leg.id = &"leg"
	leg.hp = 4
	leg.max_hp = 4
	leg.volume = [Box.new(Vector3.ZERO, Vector3(0.4, 1.0, 0.4))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	var shoulder := Socket.new(&"SHOULDER")
	shoulder.occupant = arm
	var hip := Socket.new(&"HIP")
	hip.occupant = leg
	torso.sockets = [shoulder, hip]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var placements: Array[BoxPlacement] = UnitGeometry.placements(unit)

	var placed_ids: Array[StringName] = []
	for placement: BoxPlacement in placements:
		placed_ids.append(placement.part.id)

	assert_true(placed_ids.has(&"torso"))
	assert_true(placed_ids.has(&"leg"))
	assert_false(placed_ids.has(&"arm"), "a destroyed part must not be placed")


## docs/10 taskblock04 A2: "compute each unit's bounding sphere from its
## ACTUAL geometry... do NOT hardcode humanoid dimensions."
func test_bounding_sphere_of_a_single_box_is_the_boxs_own_half_diagonal() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 2.0, 2.0))]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(5, 5))
	var sphere: Dictionary = UnitGeometry.bounding_sphere(unit)

	assert_almost_eq((sphere.center as Vector3).x, 5.0, 0.0001)
	assert_almost_eq((sphere.center as Vector3).z, 5.0, 0.0001)
	# A 2x2x2 cube's own half-diagonal: sqrt(3) * (2/2).
	assert_almost_eq(sphere.radius, sqrt(3.0), 0.0001)


## tb32 Pass C: the `bounding_sphere_for_part` counterpart — no owning
## Unit at all, same "actual geometry, never a hardcoded size" math,
## needed so camera framing can aim at a wall/cover/downed object the
## way it already does a live unit.
func test_bounding_sphere_for_part_of_a_single_box_is_the_boxs_own_half_diagonal() -> void:
	var wall := Part.new()
	wall.id = &"wall"
	wall.hp = 10
	wall.max_hp = 10
	wall.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 2.0, 2.0))]

	var sphere: Dictionary = UnitGeometry.bounding_sphere_for_part(wall, Vector2i(5, 5))

	assert_almost_eq((sphere.center as Vector3).x, 5.0, 0.0001)
	assert_almost_eq((sphere.center as Vector3).z, 5.0, 0.0001)
	assert_almost_eq(sphere.radius, sqrt(3.0), 0.0001)


## A unit with limbs must get a LARGER sphere than its torso alone — the
## whole point of computing this from real geometry instead of a constant.
func test_bounding_sphere_grows_to_cover_every_living_box() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 4
	arm.volume = [Box.new(Vector3.ZERO, Vector3(0.2, 0.2, 0.2))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.7, 0.3))]
	var shoulder := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(3.0, 0.0, 0.0)))
	shoulder.occupant = arm
	torso.sockets = [shoulder]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var torso_only := Part.new()
	torso_only.id = &"torso"
	torso_only.hp = 10
	torso_only.max_hp = 10
	torso_only.volume = torso.volume
	var torso_only_unit := Unit.new(Matrix.new(), Shell.new(torso_only), Vector2i(0, 0))

	var full_sphere: Dictionary = UnitGeometry.bounding_sphere(unit)
	var torso_sphere: Dictionary = UnitGeometry.bounding_sphere(torso_only_unit)

	assert_gt(full_sphere.radius, torso_sphere.radius, "the far-out arm must widen the sphere")


func test_bounding_sphere_ignores_destroyed_parts() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 0
	arm.max_hp = 4
	arm.volume = [Box.new(Vector3.ZERO, Vector3(0.2, 0.2, 0.2))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.7, 0.3))]
	var shoulder := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(50.0, 0.0, 0.0)))
	shoulder.occupant = arm
	torso.sockets = [shoulder]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var sphere: Dictionary = UnitGeometry.bounding_sphere(unit)

	# A living arm 50 units out would blow the radius up enormously — its
	# absence proves the dead arm was excluded, not just under-weighted.
	assert_lt(sphere.radius, 5.0)


func test_bounding_sphere_with_no_root_falls_back_to_the_units_own_cell() -> void:
	var unit := Unit.new(Matrix.new(), Shell.new(null), Vector2i(3, 4))
	var sphere: Dictionary = UnitGeometry.bounding_sphere(unit)

	assert_almost_eq((sphere.center as Vector3).x, 3.0, 0.0001)
	assert_almost_eq((sphere.center as Vector3).z, 4.0, 0.0001)
	assert_almost_eq(sphere.radius, 0.0, 0.0001)


## docs/10 taskblock05 F2: "a pose moves the boxes" — a socket override
## composes onto the socket's own authored transform, so it must actually
## move the child part it applies to.
func test_a_pose_changes_a_parts_composed_world_transform() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 4
	# Offset in X, off its own socket origin, since the override rotates
	# around Y (UP) below — a box centered on the joint it rotates around,
	# or offset along the rotation's own axis, would never visibly move.
	arm.volume = [Box.new(Vector3(0.3, 0.0, 0.0), Vector3(0.2, 0.2, 0.2))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.7, 0.3))]
	var shoulder := Socket.new(
		&"SHOULDER", Transform3D(Basis(), Vector3(1.0, 0.0, 0.0)), &"ARM_JOINT"
	)
	shoulder.occupant = arm
	torso.sockets = [shoulder]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var idle_arm: BoxPlacement = UnitGeometry.placements(unit)[1]

	var pose := Pose.new()
	pose.overrides = {&"ARM_JOINT": Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3.ZERO)}
	unit.pose = pose
	var posed_arm: BoxPlacement = UnitGeometry.placements(unit)[1]

	assert_false(
		(idle_arm.transform * idle_arm.box.center).is_equal_approx(
			posed_arm.transform * posed_arm.box.center
		),
		"the posed arm must land somewhere different than the idle one"
	)


## docs/10 taskblock05 F3: "poses are data, adding one needs no code" — a
## Pose built entirely ad hoc (never touching the Poses factory class at
## all) must work exactly the same way as one of the three named ones.
## Nothing anywhere special-cases Pose by identity or name.
func test_an_arbitrary_pose_never_seen_in_poses_gd_still_works() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 4
	arm.volume = [Box.new(Vector3.ZERO, Vector3(0.2, 0.2, 0.2))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.7, 0.3))]
	var elbow := Socket.new(&"ELBOW", Transform3D.IDENTITY, &"HOMEBREW_JOINT_ID")
	elbow.occupant = arm
	torso.sockets = [elbow]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var homebrew_pose := Pose.new()
	homebrew_pose.overrides = {&"HOMEBREW_JOINT_ID": Transform3D(Basis(), Vector3(9.0, 0.0, 0.0))}
	unit.pose = homebrew_pose

	var arm_placement: BoxPlacement = UnitGeometry.placements(unit)[1]
	var world: Vector3 = arm_placement.transform * arm_placement.box.center
	assert_almost_eq(world.x, 9.0, 0.0001, "a plain, code-free Pose must still move the socket")


## docs/10 taskblock05 F3: "DOWN puts every box below standing height."
func test_down_puts_every_box_below_standing_height() -> void:
	var unit := DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(0, 0))
	const STANDING_HEIGHT := 1.85  # docs/01: head sits at ~1.60-1.85 upright

	for placement: BoxPlacement in UnitGeometry.placements(unit, null, Poses.down()):
		var half: Vector3 = placement.box.size * 0.5
		var highest_corner := -INF
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var local: Vector3 = (
						placement.box.center + Vector3(sx * half.x, sy * half.y, sz * half.z)
					)
					var world: Vector3 = placement.transform * local
					highest_corner = maxf(highest_corner, world.y)
		assert_lt(
			highest_corner,
			STANDING_HEIGHT,
			"%s's own highest corner must read as lying down, not standing" % placement.part.id
		)


func test_a_socket_transform_offsets_the_child_from_the_root() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 4
	arm.volume = [Box.new(Vector3.ZERO, Vector3(0.4, 0.9, 0.4))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	var shoulder := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(1.0, 0.5, 0.0)))
	shoulder.occupant = arm
	torso.sockets = [shoulder]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var placements: Array[BoxPlacement] = UnitGeometry.placements(unit)

	var arm_placement: BoxPlacement = null
	for placement: BoxPlacement in placements:
		if placement.part.id == &"arm":
			arm_placement = placement
	assert_not_null(arm_placement)
	var arm_world: Vector3 = arm_placement.transform * arm_placement.box.center
	assert_almost_eq(arm_world.x, 1.0, 0.0001)
	assert_almost_eq(arm_world.y, 0.5, 0.0001)


## taskblock-26 Pass A2: muzzle_point() finds the weapon's own composed
## FORWARD TIP (box.center offset by half its own +Z extent — box.gd's
## own documented "+Z forward" convention), not the box's raw center,
## which for anything but a zero-length weapon sits back inside the gun's
## own body — closer to the shooter's own torso than a real muzzle is
## ("the literal shoulder, not from the shoulder").
func test_muzzle_point_returns_the_weapons_own_composed_forward_tip() -> void:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.volume = [Box.new(Vector3.ZERO, Vector3(0.1, 0.1, 0.1))]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	var grip := Socket.new(&"GRIP", Transform3D(Basis(), Vector3(0.3, 0.6, 0.0)))
	grip.occupant = pistol
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	torso.sockets = [wrist]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(5, 5))
	var muzzle: Vector3 = UnitGeometry.muzzle_point(unit, pistol)

	# torso/hand carry no volume of their own here — the pistol is the only
	# box in the whole placements() output.
	var expected: BoxPlacement = UnitGeometry.placements(unit)[0]
	assert_eq(expected.part, pistol)
	var tip: Vector3 = expected.box.center + Vector3(0.0, 0.0, expected.box.size.z * 0.5)
	var expected_point: Vector3 = expected.transform.translated_local(tip).origin
	assert_true(muzzle.is_equal_approx(expected_point))
	# Sanity: the tip must genuinely differ from the box's raw center —
	# proving this isn't accidentally passing on a zero-length box.
	var center_point: Vector3 = expected.transform.translated_local(expected.box.center).origin
	assert_false(muzzle.is_equal_approx(center_point))


## Defensive fallback: a weapon with no placement at all (never attached, or
## no volume) still returns a usable point rather than crashing.
func test_muzzle_point_falls_back_to_the_units_own_cell_when_the_weapon_has_no_placement() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(4, 7))
	var unattached_weapon := Part.new()
	unattached_weapon.id = &"ghost_weapon"

	var muzzle: Vector3 = UnitGeometry.muzzle_point(unit, unattached_weapon)

	assert_almost_eq(muzzle.x, 4.0, 0.0001)
	assert_almost_eq(muzzle.z, 7.0, 0.0001)
	assert_almost_eq(muzzle.y, UnitGeometry.DEFAULT_MUZZLE_HEIGHT, 0.0001)


## taskblock-22 Pass H1: the real authored SHOULDER socket world height —
## same convention data/parts/torso.tres uses (SHOULDER_L/R at world Y
## 1.53), never a guessed constant.
func test_shoulder_height_returns_the_real_shoulder_socket_world_height() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var shoulder := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(0.31, 1.53, 0.0)))
	torso.sockets = [shoulder]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))

	assert_almost_eq(UnitGeometry.shoulder_height(unit), 1.53, 0.0001)


func test_shoulder_height_is_negative_one_with_no_shoulder_socket_anywhere() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var hip := Socket.new(&"HIP", Transform3D(Basis(), Vector3(0.0, 0.9, 0.0)))
	torso.sockets = [hip]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))

	assert_eq(UnitGeometry.shoulder_height(unit), -1.0)


## H1: "the weapon's own real composed lateral/depth position stays
## exactly what muzzle_point already gives — only the firing height is
## overridden."
func test_shouldered_muzzle_point_keeps_lateral_depth_but_overrides_height() -> void:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.volume = [Box.new(Vector3.ZERO, Vector3(0.1, 0.1, 0.1))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	# A LOW grip — hip height, the exact case H1 exists to fix.
	var grip := Socket.new(&"GRIP", Transform3D(Basis(), Vector3(0.2, 0.3, 0.0)))
	grip.occupant = pistol
	var shoulder := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(0.31, 1.53, 0.0)))
	torso.sockets = [grip, shoulder]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(2, 2))
	var natural: Vector3 = UnitGeometry.muzzle_point(unit, pistol)
	var shouldered: Vector3 = UnitGeometry.shouldered_muzzle_point(unit, pistol)

	assert_almost_eq(natural.y, 0.3, 0.0001, "sanity: the natural grip is low")
	assert_almost_eq(shouldered.x, natural.x, 0.0001)
	assert_almost_eq(shouldered.z, natural.z, 0.0001)
	assert_almost_eq(shouldered.y, 1.53, 0.0001, "overridden to the real shoulder height")


func test_shouldered_muzzle_point_falls_back_to_natural_with_no_shoulder_socket() -> void:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.volume = [Box.new(Vector3.ZERO, Vector3(0.1, 0.1, 0.1))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var grip := Socket.new(&"GRIP", Transform3D(Basis(), Vector3(0.2, 0.3, 0.0)))
	grip.occupant = pistol
	torso.sockets = [grip]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(2, 2))

	var natural: Vector3 = UnitGeometry.muzzle_point(unit, pistol)
	var shouldered: Vector3 = UnitGeometry.shouldered_muzzle_point(unit, pistol)

	assert_true(shouldered.is_equal_approx(natural))
