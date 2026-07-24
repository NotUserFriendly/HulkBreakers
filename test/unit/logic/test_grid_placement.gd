extends GutTest

## taskblock-38 Pass A: the placement model's attachment grammar, proven now
## even with no authored catwalk yet (docs/PLAN.md: "build and test the
## rule now... otherwise the first catwalk discovers the grammar doesn't
## hold"). Fixture parts only — real "Ship Floor"/"Raised Ship Floor"/
## "Catwalk" content is Pass B's job.


func _make_part(id: StringName, attaches_to: Array[StringName] = []) -> Part:
	var p := Part.new()
	p.id = id
	p.attaches_to = attaches_to
	p.hp = 1
	p.max_hp = 1
	return p


func _add_socket(owner: Part, socket_type: StringName) -> void:
	owner.sockets.append(Socket.new(socket_type))


## "A catwalk over a floor is one cell with two walkable surfaces at
## different heights" (docs/PLAN.md) — the catwalk sits at the SAME cell as
## the floor beneath it, but structurally attaches sideways to a raised
## floor one cell over, not downward to the (already occupied) ground.
func test_a_cell_holds_two_surfaces_at_different_heights() -> void:
	var grid := Grid.new(4, 4)
	var floor_part := _make_part(&"floor", [GridPlacement.GROUND])
	var raised_floor := _make_part(&"raised_floor", [GridPlacement.GROUND])
	_add_socket(raised_floor, &"CATWALK_SIDE")
	var catwalk_part := _make_part(&"catwalk", [&"CATWALK_SIDE"])

	var cell := Vector2i(1, 1)
	var neighbor := Vector2i(2, 1)
	assert_not_null(GridPlacement.place(grid, cell, floor_part, 0.0))
	assert_not_null(GridPlacement.place(grid, neighbor, raised_floor, 1.0))
	assert_not_null(GridPlacement.place(grid, cell, catwalk_part, 1.0))

	var here: Array[Surface] = grid.surfaces_at(cell)
	assert_eq(here.size(), 2)
	assert_eq(here[0].part, floor_part)
	assert_eq(here[0].height, 0.0)
	assert_eq(here[1].part, catwalk_part)
	assert_eq(here[1].height, 1.0)


func test_downward_attaching_surface_is_legal_on_an_empty_cell() -> void:
	var grid := Grid.new(4, 4)
	var floor_part := _make_part(&"floor", [GridPlacement.GROUND])
	assert_true(GridPlacement.can_place(grid, Vector2i(0, 0), floor_part))
	assert_not_null(GridPlacement.place(grid, Vector2i(0, 0), floor_part, 0.0))


func test_side_attaching_surface_is_rejected_on_an_empty_cell() -> void:
	var grid := Grid.new(4, 4)
	var catwalk_part := _make_part(&"catwalk", [&"CATWALK_SIDE"])
	assert_false(GridPlacement.can_place(grid, Vector2i(0, 0), catwalk_part))
	assert_null(GridPlacement.place(grid, Vector2i(0, 0), catwalk_part, 0.0))


func test_side_attaching_surface_is_accepted_against_a_compatible_neighbour() -> void:
	var grid := Grid.new(4, 4)
	var raised_floor := _make_part(&"raised_floor", [GridPlacement.GROUND])
	_add_socket(raised_floor, &"CATWALK_SIDE")
	var catwalk_part := _make_part(&"catwalk", [&"CATWALK_SIDE"])

	var host_cell := Vector2i(1, 1)
	var span_cell := Vector2i(2, 1)
	assert_not_null(GridPlacement.place(grid, host_cell, raised_floor, 1.0))

	assert_true(GridPlacement.can_place(grid, span_cell, catwalk_part))
	var placed: Surface = GridPlacement.place(grid, span_cell, catwalk_part, 1.0)
	assert_not_null(placed)
	assert_eq(placed.part, catwalk_part)

	# The attachment is real, not just a legality check: the raised floor's
	# own socket is now occupied by the catwalk, same as body assembly.
	assert_eq(raised_floor.sockets[0].occupant, catwalk_part)


func test_side_attaching_surface_does_not_count_a_diagonal_neighbour() -> void:
	var grid := Grid.new(4, 4)
	var raised_floor := _make_part(&"raised_floor", [GridPlacement.GROUND])
	_add_socket(raised_floor, &"CATWALK_SIDE")
	var catwalk_part := _make_part(&"catwalk", [&"CATWALK_SIDE"])

	assert_not_null(GridPlacement.place(grid, Vector2i(1, 1), raised_floor, 1.0))

	# (2, 2) is diagonal from (1, 1) — must NOT count as an attach point.
	assert_false(GridPlacement.can_place(grid, Vector2i(2, 2), catwalk_part))


func test_side_attaching_surface_is_rejected_once_the_matching_socket_is_full() -> void:
	var grid := Grid.new(4, 4)
	var raised_floor := _make_part(&"raised_floor", [GridPlacement.GROUND])
	_add_socket(raised_floor, &"CATWALK_SIDE")
	var catwalk_a := _make_part(&"catwalk_a", [&"CATWALK_SIDE"])
	var catwalk_b := _make_part(&"catwalk_b", [&"CATWALK_SIDE"])

	assert_not_null(GridPlacement.place(grid, Vector2i(1, 1), raised_floor, 1.0))
	assert_not_null(GridPlacement.place(grid, Vector2i(2, 1), catwalk_a, 1.0))

	# Same neighbour, only one CATWALK_SIDE socket to offer — a second
	# side-attaching span finds no free attach point.
	assert_false(GridPlacement.can_place(grid, Vector2i(0, 1), catwalk_b))
