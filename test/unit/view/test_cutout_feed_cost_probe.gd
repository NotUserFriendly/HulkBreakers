extends GutTest

## **What one frame of `BoardView.update_wall_cutout` actually costs**, against a real generated
## board, real assembled shells and a real `Camera3D`. taskblock-61 Pass C1.
##
## `test_cutout_gate_cost_probe.gd` measures the sight gate in isolation and that is exactly how
## this pass already went wrong once: the gate measured 41 usec against a one-box torso fixture,
## shipped, and the supervisor's live session came back at 13 fps. A component measured headlessly
## is not the system — this file measures the whole per-frame call the `_process` path makes, with
## nothing stubbed.
##
## A probe, not a gate: it prints, and asserts only the shape of the answer.

const FRAMES := 20
## What `BoutSetup` puts on a board a side, doubled — the feed iterates `combat_state.units`
## whole, not just the units it ends up cutting for.
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


func test_one_frame_of_the_cutout_feed_against_a_real_board() -> void:
	var grid: Grid = MapCorpus.read(4242, 32, 24)
	var preset: BotPreset = DataLibrary.get_preset(&"combat_tester_chaingun")
	var units: Array[Unit] = []
	for i in range(ROSTER):
		var cell := Vector2i(4 + (i % 8) * 3, 6 + (i / 8) * 6)
		var unit: Unit = DeepStrike.assemble_from_preset(preset, Matrix.new(), cell, i % 2)
		unit.height = UnitGeometry.true_height_for_cell(cell, grid)
		units.append(unit)

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())
	view.wall_cutout_units = units

	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(16, 22, -14)
	camera.look_at(Vector3(16, 0, 12), Vector3.UP)

	var frame_usec: float = _usec(FRAMES, func() -> void: view.update_wall_cutout(camera))
	# **The floor this feed cannot go below**: it has to know where every body is, and one
	# `bounding_box` walk per unit is what that costs. Measured rather than assumed, so the
	# assertion below is about the gate's own share and not about this machine's speed.
	var geometry_usec: float = _usec(
		FRAMES,
		func() -> void:
			for unit: Unit in units:
				UnitGeometry.bounding_box(unit)
	)

	gut.p("  roster: %d units, %d blockers" % [ROSTER, grid.blockers.size()])
	gut.p(
		"  body geometry alone         %9.1f usec/frame   (the irreducible floor)" % geometry_usec
	)
	gut.p("  update_wall_cutout          %9.1f usec/frame" % frame_usec)
	gut.p("  everything above the floor  %9.1f usec/frame" % (frame_usec - geometry_usec))
	gut.p("  as a share of a 60 fps frame  %7.1f %%" % (frame_usec / 16666.0 * 100.0))
	gut.p("  as a share of a 144 fps frame %7.1f %%" % (frame_usec / 6944.0 * 100.0))

	# **A ratio, not a wall-clock bound** — the other cost probes in this suite say why: a
	# millisecond threshold on shared hardware fails for reasons that have nothing to do with the
	# code. What is asserted is that the `BR32.05` sight gate stays a MINORITY of the feed. It did
	# not when it shipped: the feed went 3 020 -> 5 281 usec, the gate costing more than the body
	# geometry it sat on top of. Everything above the floor is projection, logging and the gate.
	assert_lt(
		frame_usec,
		geometry_usec * 2.0,
		(
			"the cutout gate must stay a minority of the feed (%.1f usec against a %.1f floor)"
			% [frame_usec, geometry_usec]
		)
	)
