extends GutTest

## docs/10 taskblock05 A1: "clicking a unit's body doesn't reliably select
## it" — _cell_at() returns what was actually hit ({kind, unit, cell}), and
## the click handler dispatches on that directly, never re-deriving a unit
## from a cell. Split out of test_tactics_controller.gd purely to stay
## under gdlint's max-public-methods; same conventions (driven directly, no
## live camera required).


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
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
	return {
		"state": state, "controller": controller, "board_view": board_view, "camera_rig": camera_rig
	}


## "clicking a unit's body selects it from every selection state" — nothing
## selected, and already selected (idempotent).
func test_clicking_the_current_unit_selects_it_from_every_selection_state() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	assert_null(controller.selection.selected_unit)
	controller._click_unit(a)
	assert_eq(controller.selection.selected_unit, a)

	# Already selected — clicking it again must still resolve to itself.
	controller._click_unit(a)
	assert_eq(controller.selection.selected_unit, a)


## "clicking the head, torso, and foot of the same unit all resolve to that
## unit" — three boxes stacked at different heights, hit from directly
## above at each height in turn.
func _make_tall_unit(cell: Vector2i) -> Unit:
	var root := Part.new()
	root.id = &"torso"
	root.hp = 5
	root.max_hp = 5
	root.volume = [
		Box.new(Vector3(0.0, 0.2, 0.0), Vector3(0.4, 0.4, 0.4)),  # foot
		Box.new(Vector3(0.0, 1.0, 0.0), Vector3(0.4, 0.4, 0.4)),  # torso
		Box.new(Vector3(0.0, 1.8, 0.0), Vector3(0.4, 0.4, 0.4)),  # head
	]
	return Unit.new(Matrix.new(), Shell.new(root), cell, 0)


func test_hitting_the_head_torso_or_foot_of_a_unit_all_resolve_to_that_unit() -> void:
	var a := _make_tall_unit(Vector2i(0, 0))
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	for height in [0.2, 1.0, 1.8]:
		var hit: Variant = controller._cell_at(Vector3(0.0, height, 0.0), Vector3(0.0, -1.0, 0.0))
		assert_eq((hit as Dictionary)["kind"], Enums.HitKind.UNIT, "height %s" % height)
		assert_eq((hit as Dictionary)["unit"], a, "height %s" % height)


func _make_wide_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(3.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


## docs/10 taskblock03 D1: "raycast against the unit's box meshes as well as
## the board; nearest hit wins." A ray straight down through cell (1,0) hits
## the empty ground there — but a's wide torso overhangs that far enough
## that its box is nearer than the ground.
func test_cell_at_prefers_a_units_overhanging_body_over_the_ground_tile() -> void:
	var a := _make_wide_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	var hit: Variant = controller._cell_at(Vector3(1.0, 5.0, 0.0), Vector3(0.0, -1.0, 0.0))

	assert_eq(
		(hit as Dictionary)["kind"],
		Enums.HitKind.UNIT,
		"the overhanging body wins, not the ground tile beneath it"
	)
	assert_eq((hit as Dictionary)["unit"], a)
	assert_eq((hit as Dictionary)["cell"], Vector2i(0, 0))


func test_cell_at_falls_back_to_the_ground_tile_when_no_body_is_hit() -> void:
	var a := _make_wide_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	var hit: Variant = controller._cell_at(Vector3(5.0, 5.0, 5.0), Vector3(0.0, -1.0, 0.0))

	assert_eq((hit as Dictionary)["kind"], Enums.HitKind.CELL)
	assert_eq((hit as Dictionary)["cell"], Vector2i(5, 5))


## docs/10 taskblock05 A1: a unit hit is never re-derived from a cell — this
## drives the click through the same hit Dictionary a real mouse click
## would produce, not a bare cell, via the branch table's own entry point.
func test_clicking_a_units_overhanging_body_selects_it_via_click_unit() -> void:
	var a := _make_wide_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	var hit: Variant = controller._cell_at(Vector3(1.0, 5.0, 0.0), Vector3(0.0, -1.0, 0.0))
	controller._click_unit((hit as Dictionary)["unit"])

	assert_eq(controller.selection.selected_unit, a)
