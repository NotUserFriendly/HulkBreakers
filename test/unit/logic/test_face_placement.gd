extends GutTest

## taskblock-58 Pass E: **placing attaches to the struck face.**
##
## The pass's own test line — *"aiming at a top face places above and a side face places beside"* —
## asked headlessly, because deciding where a placement lands has no widget in it. The ghost half of
## the acceptance is in `test_parts_list.gd`, against real modules.


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## taskblock-59 follow-up: **the kind is a parameter now, and it was hardcoded to `KIND_SURFACE`.**
## That was inert while nothing read a placement's kind here, and stopped being inert when
## `FacePlacement.ground_of` began distinguishing a deck from a thing standing on one — a `wall`
## authored as a surface then *was* the ground, so a side placement landed on top of it.
func _placement(
	part_id: StringName, cell: Vector2i, height: float, kind: StringName = MapPlacement.KIND_SURFACE
) -> MapPlacement:
	return MapPlacement.new(cell, kind, part_id, height)


## **THE PASS'S OWN LINE.** A top face places above; a side face places beside.
func test_a_top_face_places_above_and_a_side_face_places_beside() -> void:
	var cell := Vector2i(4, 4)
	# A wall: a 1.0-wide cell cube 2.4 tall, sitting on the deck. **A blocker, which is what a wall
	# is** — authored as a surface it would be the ground, and a thing placed beside it would stand
	# on its roof.
	var standing: Array[MapPlacement] = [_placement(&"wall", cell, 0.0, MapPlacement.KIND_BLOCKER)]
	var span: Dictionary = FacePlacement.span_of(standing)
	gut.p("  the struck wall spans %.2f to %.2f" % [span["bottom"], span["top"]])

	var above: Dictionary = FacePlacement.target_from(standing, cell, Vector3.UP, 0.0)
	assert_eq(above["cell"], cell, "a top face keeps the cell")
	assert_almost_eq(
		float(above["height"]), float(span["top"]), 0.0001, "and lands on what it was clicked on"
	)

	var beside: Dictionary = FacePlacement.target_from(standing, cell, Vector3.RIGHT, 0.0)
	assert_eq(beside["cell"], cell + Vector2i(1, 0), "a side face steps into the neighbour")
	assert_almost_eq(
		float(beside["height"]),
		float(span["bottom"]),
		0.0001,
		"at the struck thing's own footing, not on top of it"
	)


## Every side, so "beside" is not accidentally right for one axis and wrong for the other.
func test_each_side_face_steps_into_its_own_neighbour() -> void:
	var cell := Vector2i(5, 5)
	var standing: Array[MapPlacement] = [_placement(&"wall", cell, 0.0)]
	var cases := {
		Vector3.RIGHT: Vector2i(1, 0),
		Vector3.LEFT: Vector2i(-1, 0),
		Vector3.BACK: Vector2i(0, 1),
		Vector3.FORWARD: Vector2i(0, -1),
	}
	for normal: Vector3 in cases:
		var target: Dictionary = FacePlacement.target_from(standing, cell, normal, 0.0)
		assert_eq(
			target["cell"],
			cell + (cases[normal] as Vector2i),
			"normal %s must step to %s" % [normal, cases[normal]]
		)


## A bottom face puts the new thing under what was clicked — the third face, and the one an author
## reaches for when hanging something below a catwalk.
func test_a_bottom_face_places_under_what_was_clicked() -> void:
	var cell := Vector2i(2, 2)
	var raised: Array[MapPlacement] = [_placement(&"ship_floor", cell, 3.0)]
	var span: Dictionary = FacePlacement.span_of(raised)

	var under: Dictionary = FacePlacement.target_from(raised, cell, Vector3.DOWN, 0.0)

	assert_eq(under["cell"], cell)
	assert_almost_eq(float(under["height"]), float(span["bottom"]), 0.0001)


## **A diagonal normal must never produce a diagonal step.** `GridPlacement`'s grammar has no
## corner attachment — *"a bridge span reads as N/E/S/W, never a corner graft"* — so a normal
## between two axes resolves to the one it leans further along rather than to both.
func test_a_diagonal_normal_resolves_to_one_orthogonal_step() -> void:
	var cell := Vector2i(3, 3)
	var standing: Array[MapPlacement] = [_placement(&"wall", cell, 0.0)]

	var leaning_x: Dictionary = FacePlacement.target_from(
		standing, cell, Vector3(0.9, 0.0, 0.4).normalized(), 0.0
	)
	var leaning_z: Dictionary = FacePlacement.target_from(
		standing, cell, Vector3(0.4, 0.0, -0.9).normalized(), 0.0
	)

	assert_eq(leaning_x["cell"], cell + Vector2i(1, 0), "it leans along X")
	assert_eq(leaning_z["cell"], cell + Vector2i(0, -1), "and this one along Z")
	for target: Dictionary in [leaning_x, leaning_z]:
		var step: Vector2i = (target["cell"] as Vector2i) - cell
		assert_eq(absi(step.x) + absi(step.y), 1, "a diagonal step has no orthogonal neighbour")


## No struck face at all — a click that resolved off the ground plane rather than off geometry.
## **The editor's authored height, which is what it did before faces existed.**
func test_no_struck_face_falls_back_to_the_authored_height() -> void:
	var cell := Vector2i(1, 1)
	var empty: Array[MapPlacement] = []

	var target: Dictionary = FacePlacement.target_from(empty, cell, null, 2.5)

	assert_eq(target["cell"], cell, "with no face there is no step")
	assert_almost_eq(float(target["height"]), 2.5, 0.0001, "the authored height")


## Bare board is not a refusal. An author dropping the first floor onto an empty cell gets it at the
## deck rather than nothing at all.
func test_an_empty_cell_reports_a_span_at_the_ground() -> void:
	var span: Dictionary = FacePlacement.span_of([] as Array[MapPlacement])
	assert_almost_eq(float(span["top"]), 0.0, 0.0001)
	assert_almost_eq(float(span["bottom"]), 0.0, 0.0001)

	var target: Dictionary = FacePlacement.target_from(
		[] as Array[MapPlacement], Vector2i(0, 0), Vector3.UP, 9.0
	)
	assert_almost_eq(float(target["height"]), 0.0, 0.0001, "on the deck, not at the fallback")


## The span covers **everything** at the cell, not just the first row — a wall standing on a floor
## is two placements and its top is the wall's.
func test_the_span_covers_every_placement_at_the_cell() -> void:
	var cell := Vector2i(6, 6)
	var stacked: Array[MapPlacement] = [
		_placement(&"ship_floor", cell, 0.0),
		_placement(&"wall", cell, 0.0),
	]

	var span: Dictionary = FacePlacement.span_of(stacked)
	var floor_only: Dictionary = FacePlacement.span_of(
		[_placement(&"ship_floor", cell, 0.0)] as Array[MapPlacement]
	)

	gut.p("  floor alone tops at %.2f, floor + wall at %.2f" % [floor_only["top"], span["top"]])
	assert_gt(float(span["top"]), float(floor_only["top"]), "the wall raised the top")
