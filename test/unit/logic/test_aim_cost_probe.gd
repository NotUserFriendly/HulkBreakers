extends GutTest

## taskblock-51 (`BR26.02`): **where the aim view's frames actually go.**
##
## The supervisor measured **160+ fps dropping to 8.0** on entering aim, confirmed by
## `fps_dump` in `out/combat.log`. `BR35.01` is the standing suspect — `PartPicker.hit`
## scanning every blocker and field item on every hover — and it has **already absorbed
## three fixes that were reasoned rather than measured**, so this measures before anything
## is changed.
##
## ## What it is and is not
##
## This is a **diagnostic**, not a threshold. It reports microseconds per call for each
## suspect on a board the size the supervisor was playing (32×24, ~160 walls, ~78 cover)
## and asserts only that the numbers were gathered. A wall-clock assertion here would be
## the machine-dependent gate `SuiteBudget`'s own header argues against, and would flap.
##
## The comparison that matters is **between** the suspects, not against any absolute: at
## 8 fps a frame is 125 ms, so whatever is eating that budget will stand out by an order of
## magnitude against everything else in the table.

const WIDTH := 32
const ROWS := 24
const SAMPLES := 40


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## A board with the supervisor's own density: a generated map's real wall and cover counts,
## and six units, which is `WALL_CUTOUT_MAX_UNITS`.
func _board() -> CombatState:
	var grid: Grid = MapCorpus.copy(11, WIDTH, ROWS)
	var units: Array[Unit] = []
	var cells: Array[Vector2i] = [
		Vector2i(2, 2),
		Vector2i(3, 2),
		Vector2i(2, 3),
		Vector2i(28, 20),
		Vector2i(27, 20),
		Vector2i(28, 19),
	]
	for i in range(cells.size()):
		var cell: Vector2i = cells[i]
		if grid.blockers.has(cell):
			grid.blockers.erase(cell)
		units.append(DeepStrike.assemble_reference_humanoid(Matrix.new(), cell, i / 3))
	return CombatState.new(grid, units)


func _usec_per_call(callable: Callable) -> float:
	var start: int = Time.get_ticks_usec()
	for i in range(SAMPLES):
		callable.call()
	return float(Time.get_ticks_usec() - start) / float(SAMPLES)


func test_where_the_aim_frame_budget_goes() -> void:
	var state: CombatState = _board()
	var shooter: Unit = state.units[0]
	var target: Unit = state.units[3]
	var weapon: Part = ActionCatalog.provider_for(shooter, &"shoot")
	assert_not_null(weapon, "sanity: the shooter is armed")

	var from := Vector3(4.0, 12.0, 4.0)
	var dir: Vector3 = (UnitGeometry.bounding_sphere(target).center - from).normalized()

	gut.p(
		(
			"board: %d wall/cover blockers, %d field-item cells, %d units"
			% [state.grid.blockers.size(), state.grid.field_items.size(), state.units.size()]
		)
	)

	var part_picker: float = _usec_per_call(
		func() -> void: PartPicker.hit(state.units, state.grid, from, dir)
	)
	var bounding: float = _usec_per_call(
		func() -> void:
			for unit: Unit in state.units:
				UnitGeometry.bounding_sphere(unit)
	)
	var muzzle: Vector3 = UnitGeometry.muzzle_point(shooter, weapon)
	var origin := Vector2(muzzle.x, muzzle.z) / UnitGeometry.CELL_SIZE
	var plane_dir := Vector2(target.cell) - origin
	var shot_plane: float = _usec_per_call(
		func() -> void:
			ShotPlane.build(
				Vector3(origin.x, muzzle.y, origin.y), Vector3(plane_dir.x, 0.0, plane_dir.y), state
			)
	)

	var state_clone: float = _usec_per_call(func() -> void: state.dup())
	var grid_clone: float = _usec_per_call(func() -> void: state.grid.dup())

	gut.p("--- per call, on the supervisor's board size ---")
	gut.p("  CombatState.dup             %8.0f usec   (every ActionQueue.preview)" % state_clone)
	gut.p("  Grid.dup                    %8.0f usec   (the bulk of it)" % grid_clone)
	gut.p("  PartPicker.hit              %8.0f usec   (BR35.01's suspect)" % part_picker)
	gut.p("  bounding_sphere x6 units    %8.0f usec   (update_wall_cutout, per frame)" % bounding)
	gut.p("  ShotPlane.build             %8.0f usec" % shot_plane)
	gut.p("  --- a frame at 8 fps is 125000 usec; at 160 fps it is 6250 ---")
	gut.p(
		(
			"  aim_state() BEFORE taskblock-51 = dup + build = %.0f usec, x2 per mouse motion"
			% (state_clone + shot_plane)
		)
	)

	assert_gt(part_picker, 0.0, "the probe measured something")
	assert_gt(bounding, 0.0)
	assert_gt(shot_plane, 0.0)
