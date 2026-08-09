extends GutTest

## **What the `BR32.05` sight gate costs per frame.** taskblock-61 Pass C1.
##
## The gate runs in `BoardView.update_wall_cutout`, which is a `_process` path — every unit, every
## frame, while the camera orbits. `test_sight_cost_probe.gd` measured `LoS.has_los` at **662
## usec** on a real board, and three of those per unit across a full roster would be tens of
## milliseconds a frame: a framerate defect manufactured by a correctness fix. So the number is
## taken here rather than assumed.
##
## A probe, not a gate: it prints, and asserts only the shape of the answer, because a wall-clock
## threshold on shared hardware fails for reasons that have nothing to do with the code.

const SAMPLES := 50
## A full-ish roster — `BR51.19` reports more than four a side spawning stacked, so eight a side
## is already past what the game puts on a board today.
const ROSTER := 16


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _usec(runs: int, body: Callable) -> float:
	var start: int = Time.get_ticks_usec()
	for i in range(runs):
		body.call()
	return float(Time.get_ticks_usec() - start) / float(runs)


func _unit_at(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 1.0, 0.0), Vector3(0.6, 1.6, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


func test_the_sight_gate_costs_a_frame_less_than_the_full_obstruction_march() -> void:
	# The real generated board a bout is played on, at the size `BoutSetup` uses.
	var grid: Grid = MapGen.generate(4242, 32, 24)
	var camera_position := Vector3(16, 14, -10)
	var unit: Unit = _unit_at(Vector2i(16, 12))
	gut.p(
		(
			"board: %dx%d, %d blockers, %d placements"
			% [grid.width, grid.rows, grid.blockers.size(), grid.placements().size()]
		)
	)

	var gate_usec: float = _usec(
		SAMPLES, func() -> void: WallLegibility.sight_blocked_to_unit(grid, camera_position, unit)
	)
	var march_usec: float = _usec(
		SAMPLES,
		func() -> void:
			RayCaster.obstructed(
				grid,
				camera_position,
				UnitGeometry.bounding_sphere(unit).center,
				grid.parts_at(unit.cell)
			)
	)

	gut.p("  sight_blocked_to_unit       %9.1f usec   (3 rays, supercover cells)" % gate_usec)
	gut.p("  RayCaster.obstructed        %9.1f usec   (1 ray, every blocker + floors)" % march_usec)
	gut.p(
		(
			"  a %d-unit roster per frame  %9.3f ms   (the number that has to fit in a frame)"
			% [ROSTER, gate_usec * float(ROSTER) / 1000.0]
		)
	)

	# **The claim, as a ratio rather than a wall-clock bound.** The gate's THREE rays must stay
	# well under ONE full march, which is only possible by not iterating every blocker. The first
	# version of the gate did iterate them and measured 629 usec — slower than the full march it
	# was supposed to be a cheap subset of. If the candidate filter is ever lost, this notices.
	assert_lt(
		gate_usec,
		march_usec / 2.0,
		(
			"three filtered rays must stay well under one full march (%f vs %f usec)"
			% [gate_usec, march_usec]
		)
	)
