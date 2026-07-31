extends GutTest

## taskblock-51 (`BR26.02`): **what the aim view spends per frame, driven through the real
## nodes.**
##
## The supervisor's session dump reads `min 6.8, avg 18.4 (210 frames in 11.4s)` — and
## crucially **6.0 fps at the two-second idle mark**, with the mouse still. That rules out
## the input-driven costs already fixed (the memoised plane, the clone-free cache key) and
## points at something running every frame regardless of input.
##
## The two per-frame hooks that only do work while aiming are `BattleScene._process`
## (occlusion fading, gated on `board_view.aim_active_unit`) and `BoardView._process`
## (the wall cutout). This drives both against a real scene, on a board the size the
## supervisor plays, and reports microseconds per frame.
##
## **`_process` is called by hand rather than awaited.** Waiting real frames would measure
## the test harness's own idle scheduling; calling the hook directly measures the hook.

const WIDTH := 32
const ROWS := 24
const FRAMES := 30


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _armed(cell: Vector2i, squad: int) -> Unit:
	return DeepStrike.assemble_reference_humanoid(Matrix.new(), cell, squad)


func test_where_an_idle_aim_frame_goes() -> void:
	var grid: Grid = MapCorpus.copy(11, WIDTH, ROWS)
	var units: Array[Unit] = []
	var cells: Array[Vector2i] = [
		Vector2i(2, 2),
		Vector2i(3, 2),
		Vector2i(2, 3),
		Vector2i(8, 8),
		Vector2i(9, 8),
		Vector2i(8, 9),
	]
	for i in range(cells.size()):
		if grid.blockers.has(cells[i]):
			grid.blockers.erase(cells[i])
		units.append(_armed(cells[i], i / 3))
	var state := CombatState.new(grid, units)
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]

	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, mission)
	await get_tree().process_frame

	# What aiming turns on: the occlusion pass keys off this being set.
	battle.board_view.aim_active_unit = state.units[0]
	await get_tree().process_frame

	var clones_before: int = CombatState.dups
	var planes_before: int = ShotPlane.builds

	var battle_start: int = Time.get_ticks_usec()
	for i in range(FRAMES):
		battle._process(1.0 / 60.0)
	var battle_usec: float = float(Time.get_ticks_usec() - battle_start) / float(FRAMES)

	var board_start: int = Time.get_ticks_usec()
	for i in range(FRAMES):
		battle.board_view._process(1.0 / 60.0)
	var board_usec: float = float(Time.get_ticks_usec() - board_start) / float(FRAMES)

	gut.p(
		"--- per idle aim frame, %d blockers, %d units ---" % [grid.blockers.size(), units.size()]
	)
	gut.p("  BattleScene._process   %8.0f usec  (occlusion fade pass)" % battle_usec)
	gut.p("  BoardView._process     %8.0f usec  (wall cutout)" % board_usec)
	gut.p("  --- 60 fps budget is 16667 usec; the supervisor is seeing 6 fps = 166667 ---")
	gut.p(
		(
			"  state clones during %d frames: %d   shot planes: %d"
			% [FRAMES * 2, CombatState.dups - clones_before, ShotPlane.builds - planes_before]
		)
	)

	# **The assertion is the one thing that must never regress silently:** an idle frame
	# must not be cloning the world. The timings are reported for reading, not gated —
	# a wall-clock threshold here would be the machine-dependent flake `SuiteBudget`
	# argues against.
	assert_eq(
		CombatState.dups - clones_before,
		0,
		"an idle aim frame cloned the state — that is 26ms each on a real board"
	)
	assert_eq(ShotPlane.builds - planes_before, 0, "and it must not rebuild the shot plane either")


## **What one mouse motion costs, end to end.**
##
## The supervisor reports ~8 fps live while moving and a session average of 23, with the
## clone fix in place and `wall_cutout` confirmed innocent. A motion event runs exactly two
## handlers — `aim_reticle_at_screen` then `update_aim_hover` from the same position — so
## this times those two against a real controller on a real board.
func test_what_one_mouse_motion_while_aiming_costs() -> void:
	var grid: Grid = MapCorpus.copy(11, WIDTH, ROWS)
	# A clear lane between the two, so the shot is actually legal — the point of the probe
	# is the cost of aiming, not whether this particular generated map allows it.
	for x in range(1, 10):
		grid.blockers.erase(Vector2i(x, 4))
	var units: Array[Unit] = []
	for i in range(2):
		units.append(_armed(Vector2i(2 + i * 6, 4), i))
	var state := CombatState.new(grid, units)
	# The player overlay drives a bout runner for the AI squads; without controllers it
	# refuses to run and the probe's own noise drowns the measurement.
	state.assign_rest_to_ai([0] as Array[int])
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]

	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, mission)
	battle.set_overlay(SquadControlOverlay.new())
	await get_tree().process_frame
	var tactics: TacticsController = (battle.overlay as SquadControlOverlay).tactics
	tactics.click_cell(units[0].cell)
	tactics.arm_action(&"shoot")
	tactics.click_cell(units[1].cell)
	if tactics.aiming_at == null:
		gut.p("could not enter aim on this fixture — nothing measured")
		assert_true(true)
		return
	await get_tree().process_frame

	var screen := Vector2(640.0, 360.0)
	var clones_before: int = CombatState.dups
	var planes_before: int = ShotPlane.builds

	var reticle_start: int = Time.get_ticks_usec()
	for i in range(FRAMES):
		tactics.aim_reticle_at_screen(screen + Vector2(float(i), 0.0))
	var reticle_usec: float = float(Time.get_ticks_usec() - reticle_start) / float(FRAMES)

	var hover_start: int = Time.get_ticks_usec()
	for i in range(FRAMES):
		tactics.update_aim_hover(screen + Vector2(float(i), 0.0))
	var hover_usec: float = float(Time.get_ticks_usec() - hover_start) / float(FRAMES)

	gut.p("--- per mouse motion while aiming, %d blockers ---" % grid.blockers.size())
	gut.p("  aim_reticle_at_screen  %8.0f usec" % reticle_usec)
	gut.p("  update_aim_hover       %8.0f usec" % hover_usec)
	gut.p("  one motion total       %8.0f usec" % (reticle_usec + hover_usec))
	(
		gut
		. p(
			(
				"  clones: %d   shot planes: %d   (over %d motions)"
				% [
					CombatState.dups - clones_before,
					ShotPlane.builds - planes_before,
					FRAMES * 2,
				]
			)
		)
	)
	assert_gt(reticle_usec + hover_usec, 0.0, "the probe measured something")
