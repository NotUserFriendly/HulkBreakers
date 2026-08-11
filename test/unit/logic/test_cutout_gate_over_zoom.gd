extends GutTest

## **`BR32.05` follow-up: does the sight gate hold as the camera pulls back?** taskblock-61 Pass C1.
##
## The supervisor's report after the gate landed: *"the cutout is still showing if far away, but is
## no longer cutting when close to the unit when there is no wall between camera and unit."* Same
## unit, nothing between it and the camera either way — correct zoomed in, wrong zoomed out.
##
## **Why zoom can change the answer at all, and it is not "further away".** `CameraOrbitState`
## keeps pitch and zoom independent, but the camera orbits a **pivot**, not the unit — so pulling
## back walks the camera *over* a unit sitting on its own side of that pivot and out the far side.
## The camera-to-unit angle is therefore not monotonic in zoom: measured for a unit nine cells in
## front of the pivot, **5.6 degrees down at zoom 3, 83.6 at zoom 12, 46.2 at zoom 30**. What
## actually changes with zoom is how much ground the ray crosses — the supercover line below runs
## **2 cells at zoom 3-6 and 22 at zoom 30** — and a ray that crosses more ground near wall height
## meets more walls. That is the whole mechanism behind "correct close, wrong far".
##
## These sweep the real orbit geometry rather than picking two camera positions by hand, because
## picking positions by hand is how the diagonal case gets missed (docs/00's own camera-yaw
## example).

## `CameraOrbitState.DEFAULT_PITCH`, the tactical camera's own resting angle.
const PITCH := -0.6
const ZOOMS: Array[float] = [3.0, 6.0, 12.0, 18.0, 24.0, 30.0]


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## Where the rig puts the camera at `zoom`, orbiting `pivot` at the resting pitch and yaw 0.
func _camera_at(pivot: Vector3, zoom: float) -> Vector3:
	return pivot + Vector3(0.0, sin(-PITCH), -cos(-PITCH)) * zoom


func _standing_unit(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 1.0, 0.0), Vector3(0.6, 1.6, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


func _blocked(grid: Grid, camera: Vector3, unit: Unit) -> bool:
	return WallLegibility.sight_blocked_to_body(
		grid, camera, unit.cell, UnitGeometry.bounding_box(unit)
	)


## **The decisive case: a board with no blockers at all.** Nothing can possibly be between the
## camera and the unit, so the gate must answer "clear" at every zoom. If it does not, the defect
## is in the gate itself and not in what the board happens to contain.
func test_an_empty_board_is_never_blocked_at_any_zoom() -> void:
	var grid := GridFixture.flat(32, 24)
	var unit := _standing_unit(Vector2i(16, 8))
	var pivot := Vector3(15.5, 0.0, 11.5)

	for zoom: float in ZOOMS:
		var camera: Vector3 = _camera_at(pivot, zoom)
		assert_false(
			_blocked(grid, camera, unit),
			"zoom %.0f: a board with no blockers cannot occlude anything" % zoom
		)


## The same sweep with a real wall on the board, placed well to the side of the camera-to-unit
## line. Still nothing between; the gate must still say clear at every zoom.
func test_a_wall_off_to_the_side_is_never_blocked_at_any_zoom() -> void:
	var grid := GridFixture.flat(32, 24)
	grid.place_blocker(Vector2i(25, 8), DataLibrary.get_part(&"wall"))
	grid.place_blocker(Vector2i(25, 9), DataLibrary.get_part(&"wall"))
	var unit := _standing_unit(Vector2i(16, 8))
	var pivot := Vector3(15.5, 0.0, 11.5)

	for zoom: float in ZOOMS:
		var camera: Vector3 = _camera_at(pivot, zoom)
		assert_false(
			_blocked(grid, camera, unit),
			"zoom %.0f: a wall nine cells off the line hides nothing" % zoom
		)


## **The angle, and which of the three rays answers, on a real generated board.**
##
## The two tests above rule the gate out as a source of invented occlusion, so what is left is the
## board genuinely having something in the way at some angles and not others. This reports the
## camera-to-unit angle and each sample ray's own verdict per zoom, because *which* ray keeps the
## cutout alive is the whole question: the centre ray blocked means the body is genuinely hidden,
## the feet ray alone means a wall is clipping the ankles of a unit in plain view.
##
## **What it found on seed 4242**, recorded so a later reader is not re-running it to find out:
## clear at zoom 3 and 6 (the line is 2 cells — the camera is nearly overhead and nothing can be
## between), and blocked from zoom 12 out, always by cell **(16,6)** — a wall two cells directly in
## front of the unit at (16,8). **The centre ray is blocked every time the gate fires**, so the
## three-point "any ray blocked" bias is NOT what keeps the cutout alive here; the body really is
## behind a wall at those angles. Whether that agrees with what is on screen is what the cutout
## log's own blamed-cell field now answers live.
func test_which_sample_ray_keeps_the_cutout_alive_across_zoom() -> void:
	var grid: Grid = MapCorpus.read(4242, 32, 24)
	var unit := _standing_unit(Vector2i(16, 8))
	unit.height = UnitGeometry.true_height_for_cell(unit.cell, grid)
	var pivot := Vector3(15.5, 0.0, 11.5)
	var box: AABB = UnitGeometry.bounding_box(unit)
	var points: Array[Vector3] = WallLegibility.body_sight_points(box)
	var names: Array[String] = ["centre", "feet", "head"]
	var exclude: Array[Part] = grid.parts_at(unit.cell)
	var feet_only_zooms := 0

	for zoom: float in ZOOMS:
		var camera: Vector3 = _camera_at(pivot, zoom)
		var span: Vector3 = box.get_center() - camera
		var degrees: float = rad_to_deg(atan2(-span.y, Vector2(span.x, span.z).length()))
		var cells: Array[Vector2i] = Grid.line(
			Vector2i(roundi(camera.x), roundi(camera.z)), unit.cell
		)
		var verdicts := PackedStringArray()
		var blocked_count := 0
		var centre_blocked := false
		for i in range(points.size()):
			var one: Array[Vector3] = [points[i]]
			var blamed: Variant = RayCaster.blocker_obstructed_among(
				grid, cells, camera, one, exclude, WallLegibility.CUTOUT_TAG
			)
			var hit: bool = blamed != null
			verdicts.append(
				"%s=%s" % [names[i], "at %d.%d" % [blamed.x, blamed.y] if hit else "clear"]
			)
			if hit:
				blocked_count += 1
				if i == 0:
					centre_blocked = true
		if blocked_count > 0 and not centre_blocked:
			feet_only_zooms += 1
		gut.p(
			(
				"  zoom %5.1f  %5.1f deg  %2d cells  %s"
				% [zoom, degrees, cells.size(), " ".join(verdicts)]
			)
		)

	gut.p("  zooms kept alive WITHOUT the centre ray being blocked: %d" % feet_only_zooms)
	assert_true(true, "a reported measurement, not a pass/fail claim")
