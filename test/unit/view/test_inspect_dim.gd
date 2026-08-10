extends GutTest

## taskblock-51 Pass K / `BR48.01`: **the inspect modal opens only for what it can describe.**
##
## The entry's heading — "closing the inspect panel leaves the background dimmed" — is the
## least reliable line in it. The supervisor re-diagnosed the trigger twice, landing on
## *"selecting a bare cell or cover causes the screen to dim"*, and that is a defect on the
## **open** path, not the close one. The two-way-transition theory recorded earlier was built
## on the wrong trigger.
##
## ## Stacking and persisting look identical from the chair
##
## The taskblock asks specifically whether a second open/close makes it *darker* — a question
## nobody can answer by eye, because a dim that stacks and a dim that never lifts look the
## same. It is answerable by reading the real nodes back, which is what these do: the panel's
## own `visible`, and the preview camera's `cull_mask`, which `_isolate_focus` narrows and
## `_isolate_clear` restores.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _barrel() -> Part:
	var barrel := Part.new()
	barrel.id = &"goo_barrel"
	barrel.hp = 4
	barrel.max_hp = 4
	return barrel


func _overlay(cover_cell: Vector2i = Vector2i(5, 5)) -> ControlOverlay:
	var grid: Grid = GridFixture.flat(12, 12)
	grid.place_blocker(cover_cell, _barrel())
	# A second object, so "open a second inspect over the first" can be driven without a unit:
	# `open(unit)` reaches the live-view lookup and needs a real 3D scenario this fixture has
	# no reason to build, and the residue question is about the isolate state either way.
	grid.place_blocker(Vector2i(7, 7), _barrel())
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(2, 2), 0)
	var state := CombatState.new(grid, [unit])
	state.assign_rest_to_ai([] as Array[int])
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, MissionState.new(RunState.new(), state))
	battle.set_overlay(ControlOverlay.for_mode(ViewModes.spectator()))
	return battle.overlay as ControlOverlay


## A cell that really does hold something still opens — the fix must not make cover
## uninspectable while stopping the empty case.
func test_a_cell_holding_cover_still_opens() -> void:
	var overlay: ControlOverlay = _overlay()
	var root: Part = overlay.battle.combat_state.grid.blocker_part_at(Vector2i(5, 5))
	assert_not_null(root, "the fixture put a barrel there")

	overlay.inspect().panel.open_cell(Vector2i(5, 5), root)

	assert_true(overlay.inspect().panel.visible, "a real object is inspectable")


## **Does a second open/close make it darker?** Read the state back rather than judging by
## eye: the preview camera's cull mask is what `_isolate_focus` narrows, and `_isolate_clear`
## restores it from a value captured once at build time — never re-derived — so it cannot
## ratchet. Asserted across two full cycles because "it stacks" and "it never lifts" are
## indistinguishable from the chair.
func test_opening_and_closing_twice_leaves_no_residue() -> void:
	var overlay: ControlOverlay = _overlay()
	var panel: InspectPanel = overlay.inspect().panel
	var root: Part = overlay.battle.combat_state.grid.blocker_part_at(Vector2i(5, 5))
	var rest_mask: int = panel.viewer.camera.cull_mask

	for cycle in range(2):
		panel.open_cell(Vector2i(5, 5), root)
		assert_true(panel.visible, "cycle %d opened" % cycle)
		panel.close()
		assert_false(panel.visible, "cycle %d closed" % cycle)
		gut.p(
			(
				"cycle %d: cull_mask back to %d (rest %d)"
				% [cycle, panel.viewer.camera.cull_mask, rest_mask]
			)
		)
		assert_eq(
			panel.viewer.camera.cull_mask, rest_mask, "cycle %d left no narrowing behind" % cycle
		)


## **Opening a second inspect over the first is one of the three close paths**, and the one
## that never presses a close button. `open()` clears the isolate before focusing, so the
## first target's narrowing cannot survive into the second.
func test_opening_a_second_inspect_over_the_first_leaves_no_residue() -> void:
	var overlay: ControlOverlay = _overlay()
	var panel: InspectPanel = overlay.inspect().panel
	var rest_mask: int = panel.viewer.camera.cull_mask

	var grid: Grid = overlay.battle.combat_state.grid
	panel.open_cell(Vector2i(5, 5), grid.blocker_part_at(Vector2i(5, 5)))
	panel.open_cell(Vector2i(7, 7), grid.blocker_part_at(Vector2i(7, 7)))
	panel.close()

	assert_false(panel.visible)
	assert_eq(panel.viewer.camera.cull_mask, rest_mask, "the first target left nothing behind")


## `close()` is the single restore path, so every caller that closes reaches the same code —
## which is what makes "all three close paths" one assertion rather than three guesses.
func test_close_resets_the_panel_whatever_it_was_showing() -> void:
	var overlay: ControlOverlay = _overlay()
	var panel: InspectPanel = overlay.inspect().panel

	panel.open_cell(
		Vector2i(5, 5), overlay.battle.combat_state.grid.blocker_part_at(Vector2i(5, 5))
	)
	panel.close()

	assert_false(panel.visible)
	assert_null(panel._unit, "and it is not still holding what it was showing")
	assert_false(panel._is_cell, "nor that it was showing a cell")
