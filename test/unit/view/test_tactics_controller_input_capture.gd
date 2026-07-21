extends GutTest

## taskblock-30/31: `input_capture_mode`/`board_clicked` — the generic
## "borrow the next real click" hook a debug panel's own board-picking
## mode uses, built entirely without this file (or `tactics_controller.gd`
## itself) ever mentioning `BoutInjector` — the routing/guard test in
## test_bout_injector_determinism.gd proves that from source; this file
## proves the mechanism itself works.


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	root.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func _setup(units: Array[Unit]) -> Dictionary:
	var state := CombatState.new(Grid.new(10, 10), units)
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	controller.setup(state, board_view, camera_rig)
	return {"state": state, "controller": controller}


func test_capture_mode_intercepts_click_cell_on_a_unit_and_emits_its_hit() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(3, 0), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var captured := [{}]
	controller.board_clicked.connect(func(hit: Dictionary) -> void: captured[0] = hit)
	controller.input_capture_mode = true

	controller.click_cell(Vector2i(3, 0))

	assert_eq(captured[0].get("kind"), Enums.HitKind.UNIT)
	assert_eq(captured[0].get("unit"), b)
	assert_eq(captured[0].get("cell"), Vector2i(3, 0))
	assert_null(controller.selection.selected_unit, "capture must never fall through to a select")


func test_capture_mode_intercepts_click_cell_on_bare_ground_and_emits_its_cell() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.selection.select(a)
	var captured := [{}]
	controller.board_clicked.connect(func(hit: Dictionary) -> void: captured[0] = hit)
	controller.input_capture_mode = true

	controller.click_cell(Vector2i(5, 5))

	assert_eq(captured[0].get("kind"), Enums.HitKind.CELL)
	assert_null(captured[0].get("unit"))
	assert_eq(captured[0].get("cell"), Vector2i(5, 5))
	assert_eq(
		built.state.units[0].cell, Vector2i(0, 0), "capture must never fall through to a queued move"
	)


func test_capture_mode_off_behaves_exactly_as_before() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var captured := [false]
	controller.board_clicked.connect(func(_hit: Dictionary) -> void: captured[0] = true)

	controller.click_cell(a.cell)

	assert_false(captured[0], "board_clicked must never fire outside capture mode")
	assert_eq(controller.selection.selected_unit, a, "the ordinary click behavior must be untouched")


## The real raycast-driven path (`_handle_mouse_button`), not just
## `click_cell` — same convention `test_tactics_controller_step_out.gd`'s
## own real-click regression test already established.
func test_capture_mode_intercepts_a_real_raycast_driven_click() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(3, 0), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var captured := [{}]
	controller.board_clicked.connect(func(hit: Dictionary) -> void: captured[0] = hit)
	controller.input_capture_mode = true

	var world_point: Vector3 = Vector3(b.cell.x, 0.5, b.cell.y) * UnitGeometry.CELL_SIZE
	var screen_pos: Vector2 = controller.camera.unproject_position(world_point)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen_pos
	controller._unhandled_input(click)

	assert_eq(captured[0].get("kind"), Enums.HitKind.UNIT)
	assert_eq(captured[0].get("unit"), b)
