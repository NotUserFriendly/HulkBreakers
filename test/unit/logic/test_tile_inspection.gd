extends GutTest

## docs/10 taskblock04 E1/E3: "hovering a tile fills the readout... enemy
## parts, HP, materials and DT are fully visible this pass" — no knowledge
## gating, checked directly against an enemy-squad unit.


func _unit(cell: Vector2i, squad: int = 0) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 8
	torso.max_hp = 10
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


func test_inspect_out_of_bounds_returns_empty() -> void:
	var state := CombatState.new(GridFixture.flat(5, 5))
	assert_eq(TileInspection.inspect(state, Vector2i(-1, 0)), {})


## taskblock-16 Pass B2: `field_object` (a real Part), not a separate
## `cover_value` scalar, is the one source of truth for "is this cell
## covered" now.
## taskblock-39 Pass C: `terrain` reads the placed Surface now — a wall
## (floored ground plus a real destructible blocker `Part`, tb31 Pass C's
## own settled model) reads as ordinary OPEN terrain, exactly like any
## other floored cell; `field_object` is where "this cell holds a wall"
## actually surfaces, unchanged.
func test_inspect_reports_terrain_and_the_real_field_object() -> void:
	var grid := GridFixture.flat(5, 5)
	var wall: Part = GridFixture.place_wall(grid, Vector2i(2, 2))
	var state := CombatState.new(grid)

	var info: Dictionary = TileInspection.inspect(state, Vector2i(2, 2))
	assert_eq(info.terrain, TileInspection.PhysicalState.OPEN)
	assert_eq(info.field_object, wall)
	assert_null(info.unit)


## An unfloored cell (no Surface placed at all) is the real placement-
## model equivalent of the old terrain model's own retired physical-
## absence state.
func test_inspect_reports_empty_for_an_unfloored_cell() -> void:
	var grid := GridFixture.flat(5, 5)
	grid.clear_surfaces(Vector2i(2, 2))
	var state := CombatState.new(grid)

	var info: Dictionary = TileInspection.inspect(state, Vector2i(2, 2))
	assert_eq(info.terrain, TileInspection.PhysicalState.EMPTY)


## A ramp-tagged Surface reads back as RAMP, matching what a real
## MapGen-authored ramp tile reports.
func test_inspect_reports_ramp_for_a_ramp_tagged_surface() -> void:
	var grid := GridFixture.flat(5, 5)
	GridFixture.place_ramp(grid, Vector2i(2, 2), 1)
	var state := CombatState.new(grid)

	var info: Dictionary = TileInspection.inspect(state, Vector2i(2, 2))
	assert_eq(info.terrain, TileInspection.PhysicalState.RAMP)


## docs/10 taskblock04 E1: "enemy parts, HP, materials and DT are fully
## visible this pass" — an enemy-squad unit at the hovered cell must come
## back exactly as fully as a friendly one; there is no gate here at all.
func test_inspect_reports_any_unit_at_the_cell_regardless_of_squad() -> void:
	var grid := GridFixture.flat(5, 5)
	var enemy := _unit(Vector2i(3, 3), 1)
	var state := CombatState.new(grid, [enemy])

	var info: Dictionary = TileInspection.inspect(state, Vector2i(3, 3))
	assert_eq(info.unit, enemy)
	assert_eq((info.unit as Unit).shell.root.hp, 8)


func test_inspect_ignores_a_dead_unit_at_the_cell() -> void:
	var grid := GridFixture.flat(5, 5)
	var dead := _unit(Vector2i(3, 3), 0)
	dead.alive = false
	var state := CombatState.new(grid, [dead])

	assert_null((TileInspection.inspect(state, Vector2i(3, 3)) as Dictionary).unit)


func test_inspect_reports_a_field_object_at_the_cell() -> void:
	var grid := GridFixture.flat(5, 5)
	var scrap: Part = DataLibrary.get_part(&"scrap_pile")
	grid.blockers[Vector2i(1, 1)] = scrap
	var state := CombatState.new(grid)

	var info: Dictionary = TileInspection.inspect(state, Vector2i(1, 1))
	assert_eq(info.field_object, scrap)


func test_visible_from_selected_is_null_with_nothing_selected() -> void:
	var state := CombatState.new(GridFixture.flat(5, 5))
	var info: Dictionary = TileInspection.inspect(state, Vector2i(2, 2))
	assert_null(info.visible_from_selected)


func test_visible_from_selected_reflects_line_of_sight_to_the_hovered_cell() -> void:
	var grid := GridFixture.flat(5, 5)
	var selected := _unit(Vector2i(0, 2), 0)
	var state := CombatState.new(grid, [selected])

	var clear: Dictionary = TileInspection.inspect(state, Vector2i(4, 2), selected)
	assert_true(clear.visible_from_selected)

	GridFixture.place_wall(grid, Vector2i(2, 2))
	var blocked: Dictionary = TileInspection.inspect(state, Vector2i(4, 2), selected)
	assert_false(blocked.visible_from_selected)
