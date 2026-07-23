extends GutTest

## docs/02: ShotPlane.build flattens every unit and cover part along one line
## of fire into a single depth-sorted Array[Region]; resolve_projectile is
## the entire hit-resolution system — it only ever asks "does this rect
## contain the point," nearest first. Fixtures are authored symmetric about
## x == 0 (the line of fire) since that's the natural body-space origin;
## AsciiRender.recenter() shifts a copy into positive space for the printed
## dumps only, it never touches the coordinates assertions run against.


func _part(id: StringName, box: Box) -> Part:
	var part := Part.new()
	part.id = id
	part.hp = 5
	part.max_hp = 5
	part.volume = [box]
	return part


func test_plate_over_part_returns_the_plate_and_uncovered_point_returns_the_part_beneath() -> void:
	var arm := _part(&"arm", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6)))
	var plate := _part(&"plate", Box.new(Vector3(-0.5, 0.5, 0.4), Vector3(1.0, 1.0, 0.2)))

	var dir := Vector2(0, -1)
	var plane: Array[Region] = []
	plane.append_array(BodyProjector.project_part(plate, Vector3(dir.x, 0.0, dir.y)))
	plane.append_array(BodyProjector.project_part(arm, Vector3(dir.x, 0.0, dir.y)))
	plane.sort_custom(func(a: Region, b: Region) -> bool: return a.depth < b.depth)

	print("\n=== plate over part (left half only) ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 2))

	var over_plate := ShotPlane.resolve_projectile(plane, Vector2(-0.5, 0.5))
	assert_eq(over_plate.part.id, &"plate")

	var over_uncovered_arm := ShotPlane.resolve_projectile(plane, Vector2(0.5, 0.5))
	assert_eq(over_uncovered_arm.part.id, &"arm")


func test_point_with_nothing_in_the_plane_returns_null() -> void:
	var arm := _part(&"arm", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6)))
	var plane: Array[Region] = BodyProjector.project_part(arm, Vector3(0, 0.0, -1))

	print("\n=== a shot slipping clean past the only part on the plane ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 2))

	assert_null(ShotPlane.resolve_projectile(plane, Vector2(5.0, 0.5)))


## taskblock-25 Pass D: "a stab hits if a disc of the weapon's width
## intersects a region." `radius <= 0.0` is exactly `rect.has_point`.
func test_disc_overlaps_rect_zero_radius_is_exactly_has_point() -> void:
	var rect := Rect2(0.0, 0.0, 1.0, 1.0)
	assert_true(ShotPlane.disc_overlaps_rect(rect, Vector2(0.5, 0.5), 0.0))
	assert_false(ShotPlane.disc_overlaps_rect(rect, Vector2(2.0, 2.0), 0.0))


func test_disc_overlaps_rect_reaches_a_point_outside_the_rect_within_its_radius() -> void:
	var rect := Rect2(0.0, 0.0, 1.0, 1.0)
	assert_true(ShotPlane.disc_overlaps_rect(rect, Vector2(1.3, 0.5), 0.5))
	assert_false(ShotPlane.disc_overlaps_rect(rect, Vector2(1.3, 0.5), 0.1))


## docs/PLAN.md Pass D: "the sniper's gap-fall-through works because
## bullets are tiny; a spear tip is too wide to slip through a hairline
## gap." Two walls with a real 0.2-wide gap between them (x -0.1 to 0.1):
## a point-radius shot passes clean through to nothing behind it; a wide
## enough disc can't fit and catches on a wall instead.
func _walls_with_a_gap() -> Array[Region]:
	var left := _part(&"left_wall", Box.new(Vector3(-0.55, 0.5, 0.0), Vector3(0.9, 1.0, 0.6)))
	var right := _part(&"right_wall", Box.new(Vector3(0.55, 0.5, 0.0), Vector3(0.9, 1.0, 0.6)))
	var dir := Vector2(0, -1)
	var plane: Array[Region] = []
	plane.append_array(BodyProjector.project_part(left, Vector3(dir.x, 0.0, dir.y)))
	plane.append_array(BodyProjector.project_part(right, Vector3(dir.x, 0.0, dir.y)))
	plane.sort_custom(func(a: Region, b: Region) -> bool: return a.depth < b.depth)
	return plane


func test_a_point_shot_falls_through_a_narrow_gap() -> void:
	var plane: Array[Region] = _walls_with_a_gap()
	assert_null(ShotPlane.resolve_projectile(plane, Vector2(0.0, 0.5)))


func test_a_wide_disc_cannot_thread_the_same_gap_a_point_shot_passes_through() -> void:
	var plane: Array[Region] = _walls_with_a_gap()
	var hit: Region = ShotPlane.resolve_projectile(plane, Vector2(0.0, 0.5), [], 0.15)
	assert_not_null(hit, "a disc wider than the gap must catch on a wall")


func test_a_narrow_disc_still_threads_a_gap_a_wide_one_cannot() -> void:
	var plane: Array[Region] = _walls_with_a_gap()
	assert_null(
		ShotPlane.resolve_projectile(plane, Vector2(0.0, 0.5), [], 0.05),
		"a narrow enough disc (a stiletto) still fits where a wide one (a spear) can't"
	)


func test_a_disc_still_hits_a_region_it_overlaps_even_off_center() -> void:
	var plane: Array[Region] = _walls_with_a_gap()
	var hit: Region = ShotPlane.resolve_projectile(plane, Vector2(-0.05, 0.5), [], 0.1)
	assert_eq(hit.part.id, &"left_wall")


func test_shield_authored_as_boxes_around_a_hole_lets_a_point_in_the_hole_hit_the_part_behind(
) -> void:
	var shield := Part.new()
	shield.id = &"shield"
	shield.hp = 5
	shield.max_hp = 5
	shield.volume = [
		Box.new(Vector3(-1.5, 2.0, 0.5), Vector3(1.0, 4.0, 0.2)),  # left strip
		Box.new(Vector3(1.5, 2.0, 0.5), Vector3(1.0, 4.0, 0.2)),  # right strip
		Box.new(Vector3(0.0, 0.5, 0.5), Vector3(2.0, 1.0, 0.2)),  # bottom strip
		Box.new(Vector3(0.0, 3.5, 0.5), Vector3(2.0, 1.0, 0.2)),  # top strip
	]
	var body := _part(&"body", Box.new(Vector3(0.0, 2.0, 0.0), Vector3(4.0, 4.0, 0.6)))

	var dir := Vector2(0, -1)
	var plane: Array[Region] = []
	plane.append_array(BodyProjector.project_part(shield, Vector3(dir.x, 0.0, dir.y)))
	plane.append_array(BodyProjector.project_part(body, Vector3(dir.x, 0.0, dir.y)))
	plane.sort_custom(func(a: Region, b: Region) -> bool: return a.depth < b.depth)

	print("\n=== shield with a hole ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 4))

	var through_the_hole := ShotPlane.resolve_projectile(plane, Vector2(0.0, 2.0))
	assert_eq(through_the_hole.part.id, &"body")

	var off_the_strip := ShotPlane.resolve_projectile(plane, Vector2(-1.5, 2.0))
	assert_eq(off_the_strip.part.id, &"shield")


func _standing_unit(id: StringName, half_width: float, cell: Vector2i) -> Unit:
	var body := _part(id, Box.new(Vector3(0.0, 0.5, 0.0), Vector3(half_width * 2.0, 1.0, 0.6)))
	return Unit.new(Matrix.new(), Shell.new(body), cell)


func test_layered_targets_a_gap_in_the_near_unit_falls_through_to_the_far_unit() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	var far_unit := _standing_unit(&"far", 1.0, Vector2i(2, 6))
	state.add_unit(near_unit)
	state.add_unit(far_unit)

	var origin := Vector2(2, 0)
	var direction := Vector2(0, 1)
	var plane: Array[Region] = ShotPlane.build(
		Vector3(origin.x, 0.0, origin.y), Vector3(direction.x, 0.0, direction.y), state
	)

	print("\n=== layered targets: a narrow near unit, a wide far unit ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 2))

	var missed_near_hit_far := ShotPlane.resolve_projectile(plane, Vector2(0.8, 0.5))
	assert_eq(missed_near_hit_far.part.id, &"far")

	var hit_near := ShotPlane.resolve_projectile(plane, Vector2(0.2, 0.5))
	assert_eq(hit_near.part.id, &"near")


## docs/08: a UI must be able to show a stat panel for a partially obscured
## target deeper in the plane, not only the one a shot at a given point
## would actually hit.
func test_units_along_lists_every_layered_target_nearest_first() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	var far_unit := _standing_unit(&"far", 1.0, Vector2i(2, 6))
	state.add_unit(near_unit)
	state.add_unit(far_unit)

	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)
	var units: Array[Unit] = ShotPlane.units_along(plane, state)

	assert_eq(units, [near_unit, far_unit])


func test_units_along_excludes_a_dead_unit_with_no_region_in_the_plane() -> void:
	# BodyProjector/ShotPlane.build project every *alive* unit regardless of
	# how far off-axis it sits (there's no distance culling) — the one
	# thing that actually removes a unit from the plane entirely is not
	# being alive.
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var visible_unit := _standing_unit(&"visible", 0.5, Vector2i(2, 2))
	var dead_unit := _standing_unit(&"dead", 0.5, Vector2i(2, 4))
	dead_unit.alive = false
	state.add_unit(visible_unit)
	state.add_unit(dead_unit)

	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)
	assert_eq(ShotPlane.units_along(plane, state), [visible_unit])


func test_destroying_cover_removes_its_region_from_the_plane() -> void:
	var grid := Grid.new(5, 5)
	var state := CombatState.new(grid)
	var crate := _part(&"crate", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6)))
	grid.blockers[Vector2i(2, 2)] = crate

	var origin := Vector2(2, 0)
	var direction := Vector2(0, 1)

	var before: Array[Region] = ShotPlane.build(
		Vector3(origin.x, 0.0, origin.y), Vector3(direction.x, 0.0, direction.y), state
	)
	print("\n=== cover, standing ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(before, 2.0), 4, 2))
	assert_eq(ShotPlane.resolve_projectile(before, Vector2(0.0, 0.5)).part.id, &"crate")

	crate.hp = 0
	var after: Array[Region] = ShotPlane.build(
		Vector3(origin.x, 0.0, origin.y), Vector3(direction.x, 0.0, direction.y), state
	)
	print("\n=== cover, destroyed ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(after, 2.0), 4, 2))
	assert_null(ShotPlane.resolve_projectile(after, Vector2(0.0, 0.5)))


## docs/10 taskblock04 C1/C2: a field object (a dropped assembly) can be a
## whole part TREE — "a dropped arm renders as an actual arm — plate,
## pistol and all," and it must be just as shootable. `project_part` alone
## (the old cover path) only ever saw the root's own boxes.
func test_a_multi_part_blocker_projects_every_box_not_just_the_root() -> void:
	var grid := Grid.new(5, 5)
	var state := CombatState.new(grid)
	# Offset sideways off the arm's own lateral span, the same
	# "shield with a hole" trick used above — a point that only lands on
	# the pistol's own rect, never the arm's, is what actually proves the
	# pistol is there to hit at all (nested inside it would always resolve
	# to the nearer arm first).
	var pistol := _part(&"pistol", Box.new(Vector3(0.5, 0.5, 0.0), Vector3(0.2, 0.2, 0.2)))
	var arm := _part(&"arm", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.5, 1.0, 0.2)))
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	arm.sockets = [grip]
	grid.blockers[Vector2i(2, 2)] = arm

	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)
	print("\n=== dropped assembly: arm + pistol riding along ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 2))

	assert_not_null(
		ShotPlane.resolve_projectile(plane, Vector2(0.0, 0.5)), "the arm's own box must be hit"
	)
	var pistol_hit: Region = ShotPlane.resolve_projectile(plane, Vector2(-0.5, 0.5))
	assert_not_null(
		pistol_hit,
		(
			"the pistol riding along the arm must also be hit — a shot into a dropped body is"
			+ " absorbed by it, not passed through"
		)
	)
	assert_eq(pistol_hit.part.id, &"pistol")


## docs/10 taskblock04 C1: "blow a shoulder off and the entire subtree
## drops as one item" — the dropped root can itself already be destroyed
## (nothing of its own left to hit) while a living child is still there to
## stop a round.
func test_a_dead_root_blockers_living_child_still_projects() -> void:
	var grid := Grid.new(5, 5)
	var state := CombatState.new(grid)
	var hand := _part(&"hand", Box.new(Vector3(0.5, 0.5, 0.0), Vector3(0.2, 0.2, 0.2)))
	var shoulder := _part(&"shoulder", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.2, 0.2, 0.2)))
	shoulder.hp = 0
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	shoulder.sockets = [wrist]
	grid.blockers[Vector2i(2, 2)] = shoulder

	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)

	assert_null(
		ShotPlane.resolve_projectile(plane, Vector2(0.0, 0.5)),
		"the destroyed shoulder itself has nothing left to hit"
	)
	var hit: Region = ShotPlane.resolve_projectile(plane, Vector2(-0.5, 0.5))
	assert_not_null(hit)
	assert_eq(hit.part.id, &"hand")


## docs/10 Phase 12.3: AimController groups the plane into layers by owning
## body — a unit's regions all point back to that Unit, cover's own regions
## point back to the cover Part itself.
func test_build_tags_every_region_with_its_owning_body() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	state.add_unit(near_unit)
	var crate := _part(&"crate", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6)))
	grid.blockers[Vector2i(2, 4)] = crate

	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)

	for region: Region in plane:
		if region.part == crate:
			assert_eq(region.body, crate)
		else:
			assert_eq(region.body, near_unit)


func test_center_of_returns_the_frontmost_regions_rect_center() -> void:
	var grid := Grid.new(10, 10)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	var state := CombatState.new(grid, [near_unit])
	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)

	var center: Vector2 = ShotPlane.center_of(plane, near_unit)
	var expected: Region = ShotPlane.resolve_projectile(plane, center)
	assert_eq(
		expected.part.id, &"near", "the returned point must land inside the unit's own region"
	)


func test_center_of_falls_back_to_the_targets_cell_with_no_regions() -> void:
	var no_volume := Part.new()
	no_volume.id = &"ghost"
	no_volume.hp = 5
	no_volume.max_hp = 5
	var ghost_unit := Unit.new(Matrix.new(), Shell.new(no_volume), Vector2i(4, 4))
	var state := CombatState.new(Grid.new(10, 10), [ghost_unit])
	var plane: Array[Region] = ShotPlane.build(Vector3(4, 0.0, 0), Vector3(0, 0.0, 1), state)

	assert_eq(ShotPlane.center_of(plane, ghost_unit), Vector2(4, 4))


## tb32 Pass C: the PartPicker counterpart — matched by `region.body`
## (a blocker/field item's own root Part identity, ShotPlane.build's own
## `region.body = part`) instead of a Unit's `shell.all_parts()`.
func test_center_of_part_returns_the_frontmost_regions_rect_center() -> void:
	var grid := Grid.new(10, 10)
	var wall := _part(&"wall", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(1.0, 1.0, 0.2)))
	grid.blockers[Vector2i(2, 2)] = wall
	var state := CombatState.new(grid, [])
	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)

	var center: Vector2 = ShotPlane.center_of_part(plane, wall, Vector2i(2, 2))
	var expected: Region = ShotPlane.resolve_projectile(plane, center)
	assert_eq(
		expected.part.id, &"wall", "the returned point must land inside the wall's own region"
	)


func test_center_of_part_falls_back_to_the_given_cell_with_no_matching_region() -> void:
	var unrelated := _part(&"unrelated", Box.new(Vector3.ZERO, Vector3(1.0, 1.0, 1.0)))

	assert_eq(ShotPlane.center_of_part([], unrelated, Vector2i(4, 4)), Vector2(4, 4))


## taskblock-22 Pass H2: self_obstruction excludes the shooter's own body
## — without this, a shooter's own torso (at the ray's own near-zero
## depth) would register as its own obstruction before ever reaching any
## real cover further along the line of fire.
func test_self_obstruction_excludes_the_shooters_own_body() -> void:
	var shooter_torso := _part(
		&"shooter_torso", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))
	)
	var shooter := Unit.new(Matrix.new(), Shell.new(shooter_torso), Vector2i(2, 0))
	var cover := _part(&"cover", Box.new(Vector3(0.0, 0.15, 0.0), Vector3(1.0, 0.3, 0.6)))
	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(2, 2)] = cover
	var state := CombatState.new(grid, [shooter])
	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)

	var hit: Region = ShotPlane.self_obstruction(plane, 0.15, shooter.shell.all_parts())

	assert_not_null(hit, "must find the cover, not stop at the shooter's own body")
	assert_eq(hit.part.id, &"cover")


func test_self_obstruction_returns_null_with_nothing_in_the_way() -> void:
	var shooter_torso := _part(
		&"shooter_torso", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))
	)
	var shooter := Unit.new(Matrix.new(), Shell.new(shooter_torso), Vector2i(2, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter])
	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)

	assert_null(ShotPlane.self_obstruction(plane, 0.15, shooter.shell.all_parts()))


## tb35 Pass B (BR27.02/BR34.06): a wall standing BEHIND the shooter (present
## in the built plane at negative depth on purpose — `ShotPlane.build`'s own
## doc comment) must never win `self_obstruction`'s resolution just because
## it sorts first unfloored. Real cover AHEAD must still be found; with
## nothing ahead at all, the answer is null, never the rearward wall.
func test_self_obstruction_never_resolves_to_a_wall_behind_the_shooter() -> void:
	var shooter_torso := _part(
		&"shooter_torso", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))
	)
	var shooter := Unit.new(Matrix.new(), Shell.new(shooter_torso), Vector2i(2, 5))
	var behind_wall := _part(
		&"behind_wall", Box.new(Vector3(0.0, 0.15, 0.0), Vector3(1.0, 2.4, 1.0))
	)
	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(2, 1)] = behind_wall
	var state_with_nothing_ahead := CombatState.new(grid, [shooter])
	var plane_with_nothing_ahead: Array[Region] = ShotPlane.build(
		Vector3(2, 0.0, 5), Vector3(0, 0.0, 1), state_with_nothing_ahead
	)

	assert_null(
		ShotPlane.self_obstruction(plane_with_nothing_ahead, 0.15, shooter.shell.all_parts()),
		"a wall behind the shooter must never register as its own forward obstruction"
	)

	var forward_cover := _part(
		&"forward_cover", Box.new(Vector3(0.0, 0.15, 0.0), Vector3(1.0, 0.3, 0.6))
	)
	grid.blockers[Vector2i(2, 7)] = forward_cover
	var state_with_cover := CombatState.new(grid, [shooter])
	var plane_with_cover: Array[Region] = ShotPlane.build(
		Vector3(2, 0.0, 5), Vector3(0, 0.0, 1), state_with_cover
	)

	var hit: Region = ShotPlane.self_obstruction(plane_with_cover, 0.15, shooter.shell.all_parts())
	assert_not_null(hit, "must still find real forward cover")
	assert_eq(hit.part.id, &"forward_cover")


## BR36.01: `shell.all_parts()` never covers a socket's own synthetic
## `joint_handle()` (`region.part` for a joint Region, `BodyProjector.
## _project_joint`'s own tag) — a self-exclusion list built from it can
## resolve to the shooter's OWN joint region instead of real cover or the
## target downrange. `all_parts_with_joints()` is the fix: the joint region
## really is in the built plane, and only the new list actually excludes
## it.
func test_self_obstruction_excludes_the_shooters_own_joint_regions() -> void:
	var weapon := _part(&"weapon", Box.new(Vector3.ZERO, Vector3(0.1, 0.1, 0.1)))
	var hand := _part(&"hand", Box.new(Vector3.ZERO, Vector3(0.2, 0.2, 0.2)))
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]
	var shooter_torso := _part(
		&"shooter_torso", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))
	)
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	shooter_torso.sockets = [wrist]
	var shooter := Unit.new(Matrix.new(), Shell.new(shooter_torso), Vector2i(2, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter])
	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)

	var joint_region: Region = null
	for region: Region in plane:
		if region.socket != null:
			joint_region = region
			break
	assert_not_null(
		joint_region, "the fixture must actually project a joint region to test against"
	)

	assert_false(
		shooter.shell.all_parts().has(joint_region.part),
		"the OLD exclusion list never covers the shooter's own joint region"
	)
	assert_true(
		shooter.shell.all_parts_with_joints().has(joint_region.part),
		"the fixed exclusion list must cover it"
	)
	assert_null(
		ShotPlane.self_obstruction(plane, 0.0, shooter.shell.all_parts_with_joints()),
		"nothing real is in the way — the joint region itself must not register as an obstruction"
	)


## Reading (the aim window's own `layers_for`/`window_depth`) and resolving
## (`self_obstruction`/a real fired shot) are two paths on purpose — the
## floor only applies to the latter. Same plane, same point: unfloored
## (`floor_at_zero` default false, what a raw plane read uses) still finds
## the rearward region; floored (what resolution opts into) does not.
func test_resolve_projectile_floor_at_zero_is_opt_in() -> void:
	var behind := Region.new(Rect2(-0.5, 0.0, 1.0, 1.0), -3.0, _part(&"behind", Box.new()))
	var plane: Array[Region] = [behind]

	assert_eq(ShotPlane.resolve_projectile(plane, Vector2(0.0, 0.5)).part.id, &"behind")
	assert_null(ShotPlane.resolve_projectile(plane, Vector2(0.0, 0.5), [], 0.0, true))


## BR30.10: a wall cell between shooter and target must actually stop a
## shot. MapGen only ever gave a WALL cell `opacity = 1.0` (the abstract
## LoS/tactical-gating check) — never a `grid.blockers` entry — so
## ShotPlane.build (which only ever reads `state.units`/`state.grid.
## blockers`, never `opacity`) had nothing standing in for it; a shot
## resolved as if the wall wasn't there. Fixed by giving MapGen-generated
## walls a real, indestructible Part in `blockers`
## (`MapGen._stamp_wall_geometry`, `data/parts/wall.tres`). This exercises
## that same shipped data the way a real wall cell now carries it.
func test_a_wall_part_between_shooter_and_target_blocks_the_shot() -> void:
	var grid := Grid.new(5, 6)
	var state := CombatState.new(grid)
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 5))
	state.add_unit(target)
	var wall_part: Part = DataLibrary.get_part(&"wall")
	grid.blockers[Vector2i(2, 2)] = wall_part

	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)
	print("\n=== a wall cell standing between shooter and target ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 6))

	var hit: Region = ShotPlane.resolve_projectile(plane, Vector2(0.0, 0.5))
	assert_eq(hit.part.id, &"wall", "the wall must be the nearest region at this point")

	var past_the_wall: Region = ShotPlane.resolve_projectile(plane, Vector2(0.0, 0.5), [wall_part])
	assert_eq(
		past_the_wall.part.id, &"target", "the target is still there once the wall is excluded"
	)


## tb31 Pass C: "a wall is just high-DT destructible cover" — once
## destroyed it must leave the shot plane exactly like any other dead
## cover (`test_destroying_cover_removes_its_region_from_the_plane`'s own
## pattern, applied to the real `wall.tres` data instead of a fixture
## part).
func test_destroying_a_wall_removes_its_region_from_the_plane() -> void:
	var grid := Grid.new(5, 6)
	var state := CombatState.new(grid)
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 5))
	state.add_unit(target)
	var wall_part: Part = DataLibrary.get_part(&"wall")
	grid.blockers[Vector2i(2, 2)] = wall_part

	var before: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)
	assert_eq(ShotPlane.resolve_projectile(before, Vector2(0.0, 0.5)).part.id, &"wall")

	wall_part.hp = 0
	var after: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)

	assert_eq(
		ShotPlane.resolve_projectile(after, Vector2(0.0, 0.5)).part.id,
		&"target",
		"a destroyed wall must stop blocking the shot, same as any other dead cover"
	)


## docs/09 taskblock07 Pass A1: "no file under src/ calls resolve_projectile
## except shot_plane.gd itself" — resolve_projectile is the internal
## rect-lookup resolve_ray runs, never a second, parallel resolution door a
## caller reaches for directly (that's exactly the drift risk this pass
## exists to close: a caller doing a rect lookup while resolve_ray casts a
## real ray against real geometry would silently disagree the day
## resolve_ray stops being resolve_projectile in disguise).
func test_resolve_projectile_is_called_only_from_shot_plane_itself() -> void:
	var allowed_files: Array[String] = ["shot_plane.gd"]
	var offending: Array[String] = []
	_scan_dir_for_resolve_projectile("res://src", allowed_files, offending)
	assert_eq(
		offending,
		[] as Array[String],
		"resolve_projectile called outside shot_plane.gd: %s" % [offending]
	)


func _scan_dir_for_resolve_projectile(
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
			_scan_dir_for_resolve_projectile(full_path, allowed_files, offending)
		elif entry.ends_with(".gd") and not allowed_files.has(entry):
			var text: String = FileAccess.get_file_as_string(full_path)
			if text.contains("resolve_projectile("):
				offending.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


## taskblock-36 Pass A: `build`'s own `origin`/`direction` widened to
## `Vector3`, but a caller with `y == 0.0` on both must still get exactly
## the old 2D-call's regions. Placing the cover part AT the origin cell
## makes `_offset` a no-op (`cell - origin == Vector2.ZERO`), so `build`'s
## own per-region math reduces to a bare `BodyProjector.project_assembly`
## call — the actual pre-Pass-A code path — and this compares against
## THAT real call, field by field, rather than re-deriving `_offset`'s own
## formula by hand.
func test_build_with_a_flat_direction_matches_a_bare_project_assembly_call() -> void:
	var box := Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))
	var part := _part(&"crate", box)
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	grid.blockers[Vector2i(3, 3)] = part

	var origin := Vector3(3.0, 0.0, 3.0)
	var direction := Vector3(0.0, 0.0, 1.0)
	var built: Array[Region] = ShotPlane.build(origin, direction, state)
	var direct: Array[Region] = BodyProjector.project_assembly(part, direction)

	assert_eq(built.size(), direct.size())
	assert_true(built.size() > 0, "the fixture must actually project something")
	for i in range(built.size()):
		assert_eq(built[i].rect, direct[i].rect, "region %d rect" % i)
		assert_eq(built[i].depth, direct[i].depth, "region %d depth" % i)
		assert_eq(built[i].surface_normal, direct[i].surface_normal, "region %d surface_normal" % i)
		assert_eq(built[i].thickness, direct[i].thickness, "region %d thickness" % i)
		assert_eq(built[i].part, direct[i].part, "region %d part" % i)


## taskblock-37 Pass A: `elevation_for` is the one shared helper every
## production caller now builds its plane from — a real level delta
## between origin and target cells must carry through as a real
## `direction.y`/`vertical_slope`, never the old hardcoded-flat
## `Vector3(x, 0.0, y)` every one of the six callers used to construct by
## hand.
func test_elevation_for_reflects_the_level_delta_not_flat_zero() -> void:
	var grid := Grid.new(10, 10)
	grid.set_level(Vector2i(0, 3), 3)

	var elevation: Dictionary = ShotPlane.elevation_for(
		Vector2(0, 0), 1.25, Vector2i(0, 0), Vector2i(0, 3), grid
	)

	assert_eq(elevation.origin, Vector3(0.0, 1.25, 0.0))
	assert_eq(elevation.direction, Vector3(0.0, 3.0, 3.0))
	assert_almost_eq(elevation.vertical_slope, 1.0, 0.0001)


## A uniform raise — both cells on the SAME (nonzero) level — must cancel
## back to a flat shot: tb36's own confirmed "two standing bodies raised
## together resolve identically" behaviour, now proven at the `elevation_for`
## level rather than only through a full resolved shot.
func test_elevation_for_is_flat_when_origin_and_target_share_a_level() -> void:
	var grid := Grid.new(10, 10)
	grid.set_level(Vector2i(0, 0), 5)
	grid.set_level(Vector2i(0, 3), 5)

	var elevation: Dictionary = ShotPlane.elevation_for(
		Vector2(0, 0), 6.25, Vector2i(0, 0), Vector2i(0, 3), grid
	)

	assert_eq(elevation.direction.y, 0.0)
	assert_eq(elevation.vertical_slope, 0.0)


## `origin_height` is a caller-supplied real muzzle height, never
## re-derived from the origin cell's own ground level — a shooter's
## muzzle always sits above their own cell's floor, and re-deriving it
## here would silently double-count that offset (the exact bug this pass
## found and fixed: an artificial tilt on an ordinary same-level shot).
func test_elevation_for_uses_the_given_origin_height_verbatim() -> void:
	var grid := Grid.new(10, 10)

	var elevation: Dictionary = ShotPlane.elevation_for(
		Vector2(0, 0), 0.9, Vector2i(0, 0), Vector2i(0, 3), grid
	)

	assert_almost_eq(elevation.origin.y, 0.9, 0.0001)


func test_depth_of_returns_the_frontmost_regions_own_depth() -> void:
	var grid := Grid.new(10, 10)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	var state := CombatState.new(grid, [near_unit])
	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)

	var expected: Region = ShotPlane.resolve_projectile(
		plane, ShotPlane.center_of(plane, near_unit)
	)
	assert_eq(ShotPlane.depth_of(plane, near_unit), expected.depth)


func test_depth_of_falls_back_to_zero_with_no_regions() -> void:
	var no_volume := Part.new()
	no_volume.id = &"ghost"
	no_volume.hp = 5
	no_volume.max_hp = 5
	var ghost_unit := Unit.new(Matrix.new(), Shell.new(no_volume), Vector2i(4, 4))

	assert_eq(ShotPlane.depth_of([], ghost_unit), 0.0)


func test_depth_of_part_returns_the_frontmost_regions_own_depth() -> void:
	var grid := Grid.new(10, 10)
	var wall := _part(&"wall", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(1.0, 1.0, 0.2)))
	grid.blockers[Vector2i(2, 2)] = wall
	var state := CombatState.new(grid, [])
	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)

	var expected: Region = ShotPlane.resolve_projectile(
		plane, ShotPlane.center_of_part(plane, wall, Vector2i(2, 2))
	)
	assert_eq(ShotPlane.depth_of_part(plane, wall), expected.depth)


func test_depth_of_part_falls_back_to_zero_with_no_matching_region() -> void:
	var unrelated := _part(&"unrelated", Box.new(Vector3.ZERO, Vector3(1.0, 1.0, 1.0)))

	assert_eq(ShotPlane.depth_of_part([], unrelated), 0.0)
