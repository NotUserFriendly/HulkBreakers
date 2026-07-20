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
	plane.append_array(BodyProjector.project_part(plate, dir))
	plane.append_array(BodyProjector.project_part(arm, dir))
	plane.sort_custom(func(a: Region, b: Region) -> bool: return a.depth < b.depth)

	print("\n=== plate over part (left half only) ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 2))

	var over_plate := ShotPlane.resolve_projectile(plane, Vector2(-0.5, 0.5))
	assert_eq(over_plate.part.id, &"plate")

	var over_uncovered_arm := ShotPlane.resolve_projectile(plane, Vector2(0.5, 0.5))
	assert_eq(over_uncovered_arm.part.id, &"arm")


func test_point_with_nothing_in_the_plane_returns_null() -> void:
	var arm := _part(&"arm", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6)))
	var plane: Array[Region] = BodyProjector.project_part(arm, Vector2(0, -1))

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
	plane.append_array(BodyProjector.project_part(left, dir))
	plane.append_array(BodyProjector.project_part(right, dir))
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
	plane.append_array(BodyProjector.project_part(shield, dir))
	plane.append_array(BodyProjector.project_part(body, dir))
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
	var plane: Array[Region] = ShotPlane.build(origin, direction, state)

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

	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)
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

	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)
	assert_eq(ShotPlane.units_along(plane, state), [visible_unit])


func test_destroying_cover_removes_its_region_from_the_plane() -> void:
	var grid := Grid.new(5, 5)
	var state := CombatState.new(grid)
	var crate := _part(&"crate", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6)))
	grid.blockers[Vector2i(2, 2)] = crate

	var origin := Vector2(2, 0)
	var direction := Vector2(0, 1)

	var before: Array[Region] = ShotPlane.build(origin, direction, state)
	print("\n=== cover, standing ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(before, 2.0), 4, 2))
	assert_eq(ShotPlane.resolve_projectile(before, Vector2(0.0, 0.5)).part.id, &"crate")

	crate.hp = 0
	var after: Array[Region] = ShotPlane.build(origin, direction, state)
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

	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)
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

	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)

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

	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)

	for region: Region in plane:
		if region.part == crate:
			assert_eq(region.body, crate)
		else:
			assert_eq(region.body, near_unit)


func test_center_of_returns_the_frontmost_regions_rect_center() -> void:
	var grid := Grid.new(10, 10)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	var state := CombatState.new(grid, [near_unit])
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)

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
	var plane: Array[Region] = ShotPlane.build(Vector2(4, 0), Vector2(0, 1), state)

	assert_eq(ShotPlane.center_of(plane, ghost_unit), Vector2(4, 4))


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
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)

	var hit: Region = ShotPlane.self_obstruction(plane, 0.15, shooter.shell.all_parts())

	assert_not_null(hit, "must find the cover, not stop at the shooter's own body")
	assert_eq(hit.part.id, &"cover")


func test_self_obstruction_returns_null_with_nothing_in_the_way() -> void:
	var shooter_torso := _part(
		&"shooter_torso", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))
	)
	var shooter := Unit.new(Matrix.new(), Shell.new(shooter_torso), Vector2i(2, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter])
	var plane: Array[Region] = ShotPlane.build(Vector2(2, 0), Vector2(0, 1), state)

	assert_null(ShotPlane.self_obstruction(plane, 0.15, shooter.shell.all_parts()))


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
