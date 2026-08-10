extends GutTest

## **A click on a floor must strike the floor.** taskblock-59 follow-up.
##
## > *"It's not that 'floors in the same place' is a problem, it's that I'm able to place one there
## > with a click. If I'm clicking a space with a floor, I should be striking a face of that floor,
## > and placing atop or to the side of it."*
##
## `PartPicker.hit` had only ever considered units, `Grid.blockers` and `Grid.field_items` — its own
## header lists *"unit parts, scatter cover, walls, downed bots, field objects"*, and floors are in
## none of them. So a plain tile answered `{}`, the editor read that as **no face**, and
## `FacePlacement` fell back to the authored height in the cell just clicked. The author had clicked
## a floor and struck nothing.

## Straight down from well above the middle of a cell.
const FROM_ABOVE := Vector3(0.0, 12.0, 0.0)


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _grid_with_a_floor(height: float = 0.0) -> Grid:
	var grid := Grid.new(4, 4)
	grid.add_surface(Vector2i(1, 1), Surface.new(DataLibrary.get_part(&"ship_floor"), height, 0.0))
	return grid


func _straight_down_at(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * UnitGeometry.CELL_SIZE, 12.0, cell.y * UnitGeometry.CELL_SIZE)


# ---------------------------------------------------------------- the pick


func test_a_ray_onto_a_floor_strikes_it_when_surfaces_are_included() -> void:
	var grid: Grid = _grid_with_a_floor()

	var struck: Dictionary = PartPicker.hit(
		[] as Array[Unit], grid, _straight_down_at(Vector2i(1, 1)), Vector3.DOWN, true
	)

	gut.p("struck: %s" % str(struck))
	assert_false(struck.is_empty(), "a click on a floor struck nothing at all")
	assert_eq((struck["part"] as Part).id, &"ship_floor")
	assert_eq(struck["cell"], Vector2i(1, 1))


## **The top face**, which is what makes `FacePlacement` put the next thing on top of it rather
## than inside it.
func test_the_struck_face_of_a_floor_from_above_is_its_top() -> void:
	var grid: Grid = _grid_with_a_floor()

	var struck: Dictionary = PartPicker.hit(
		[] as Array[Unit], grid, _straight_down_at(Vector2i(1, 1)), Vector3.DOWN, true
	)

	var normal: Vector3 = struck["normal"]
	gut.p("normal %s -> axis %d" % [normal, Gizmo.axis_of(normal)])
	assert_gt(normal.y, 0.5, "a ray from above must enter through the top face")


## **And the placement lands on top of it**, which is the whole point — the end-to-end claim rather
## than the pick in isolation.
func test_a_click_on_a_floor_places_on_top_of_it() -> void:
	var placements: Array[MapPlacement] = [
		MapPlacement.new(Vector2i(1, 1), MapPlacement.KIND_SURFACE, &"ship_floor", 0.0)
	]

	var target: Dictionary = FacePlacement.target_from(placements, Vector2i(1, 1), Vector3.UP, 0.0)

	gut.p("target cell %s h %.2f" % [target["cell"], target["height"]])
	assert_eq(target["cell"], Vector2i(1, 1), "a top face keeps the cell")
	assert_almost_eq(
		float(target["height"]), 0.0, 0.001, "and lands on the floor's top, not inside it"
	)


## The elevated case, so what is asserted is "the struck floor's top" rather than "zero".
func test_a_click_on_a_raised_floor_places_on_that_floor() -> void:
	var grid: Grid = _grid_with_a_floor(2.5)

	var struck: Dictionary = PartPicker.hit(
		[] as Array[Unit], grid, _straight_down_at(Vector2i(1, 1)), Vector3.DOWN, true
	)

	assert_false(struck.is_empty(), "the raised floor was not struck")
	assert_almost_eq(float(struck["t"]), 12.0 - 2.5, 0.01, "it struck at the deck's own height")


# ---------------------------------------------------------------- and the aim path is unchanged


## **Off by default, and that is deliberate.** `TacticsController` uses this same call to resolve
## what a shot is pointed at, and making the ground a target there is a change to targeting rather
## than a fix to the editor.
func test_surfaces_are_not_picked_unless_asked_for() -> void:
	var grid: Grid = _grid_with_a_floor()

	var struck: Dictionary = PartPicker.hit(
		[] as Array[Unit], grid, _straight_down_at(Vector2i(1, 1)), Vector3.DOWN
	)

	assert_true(
		struck.is_empty(), "the aim path can now target the floor, which it could not before"
	)


## A blocker still wins over the floor it is standing on — the nearest hit, unchanged.
func test_a_blocker_still_wins_over_the_floor_under_it() -> void:
	var grid: Grid = _grid_with_a_floor()
	grid.place_blocker(Vector2i(1, 1), DataLibrary.get_part(&"pillar"))

	var struck: Dictionary = PartPicker.hit(
		[] as Array[Unit], grid, _straight_down_at(Vector2i(1, 1)), Vector3.DOWN, true
	)

	gut.p("struck %s" % (struck["part"] as Part).id)
	assert_eq((struck["part"] as Part).id, &"pillar", "the floor was picked through the pillar")
