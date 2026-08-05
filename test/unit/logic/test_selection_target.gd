extends GutTest

## taskblock-51 Pass K: **selection that is not necessarily a unit.**
##
## The root was a missing type, not a broken rule: `SelectionController` had one slot,
## `selected_unit: Unit`, so a barrel had nowhere to go and the click looked like it had
## selected the floor. These cases are the shapes a real click produces, taken from the two
## dicts that already exist rather than invented here — which is the mistake `BR51.02` was
## reopened for.


func _grid() -> Grid:
	return GridFixture.flat(8, 8)


func _barrel() -> Part:
	var barrel := Part.new()
	barrel.id = &"goo_barrel"
	barrel.hp = 4
	barrel.max_hp = 4
	return barrel


func _unit(cell: Vector2i = Vector2i(2, 2)) -> Unit:
	return DeepStrike.assemble_reference_humanoid(Matrix.new(), cell, 0)


func test_a_part_target_reports_the_part_not_the_cell() -> void:
	var target: SelectionTarget = SelectionTarget.for_part(_barrel(), Vector2i(3, 4))

	assert_true(target.is_part())
	assert_false(target.is_cell(), "a barrel is not the floor it stands on")
	assert_eq(target.cell, Vector2i(3, 4), "and it still carries a cell, as every target does")


## **`describe()` names the part.** The debug panel called every non-unit hit "Cell", which is
## how the supervisor came to be told they had selected the floor when they had clicked a
## barrel.
func test_a_part_describes_itself_by_id() -> void:
	assert_eq(
		SelectionTarget.for_part(_barrel(), Vector2i(1, 1)).describe(), "goo_barrel at (1, 1)"
	)
	assert_eq(SelectionTarget.for_cell(Vector2i(1, 1)).describe(), "cell (1, 1)")
	assert_eq(SelectionTarget.none().describe(), "nothing")


## **The empty selection answers questions instead of being `null`.** Every call site would
## otherwise guard first, and the one that forgot would be the next bug.
func test_the_empty_target_answers_rather_than_crashing() -> void:
	var empty: SelectionTarget = SelectionTarget.none()

	assert_false(empty.can_inspect())
	assert_false(empty.is_unit())
	assert_false(empty.is_part())
	assert_false(empty.is_cell())


## **A bare cell has nothing to inspect; a prop does.** `BR51.10` — the button was live
## whenever anything had been clicked rather than when the thing clicked has a body.
func test_only_things_with_a_body_can_be_inspected() -> void:
	assert_true(SelectionTarget.for_unit(_unit()).can_inspect())
	assert_true(
		SelectionTarget.for_part(_barrel(), Vector2i.ZERO).can_inspect(), "a prop has parts"
	)
	assert_false(SelectionTarget.for_cell(Vector2i(1, 1)).can_inspect(), "a bare cell has none")


## **The two dict shapes are different and each gets its own door.** `PartPicker.hit` returns
## `{unit, part, cell, t}` with no `kind`; `board_clicked` emits `{kind, unit, part, cell}`.
## Routing a raw pick through `from_hit()` classified every hit as a bare cell, because the
## `kind` lookup returned null and fell to the default arm — which is how the spectator's
## unit clicks stopped pausing the bout mid-pass.
func test_a_raw_pick_and_a_hit_dict_are_read_by_different_constructors() -> void:
	var barrel: Part = _barrel()
	var raw_pick: Dictionary = {"unit": null, "part": barrel, "cell": Vector2i(5, 5), "t": 1.0}

	var from_pick: SelectionTarget = SelectionTarget.from_pick(raw_pick)
	assert_true(from_pick.is_part(), "the raw pick resolves to the part")

	# The same dict lacking `kind`, read as a hit, is a cell — which is the trap, stated.
	assert_true(SelectionTarget.from_hit(raw_pick).is_cell(), "no kind key means no kind")


## Round-tripping through the hit dict is what lets the debug panel take a target without
## learning a new vocabulary.
func test_a_target_round_trips_through_the_hit_dict() -> void:
	var barrel: Part = _barrel()
	var original: SelectionTarget = SelectionTarget.for_part(barrel, Vector2i(6, 1))

	var restored: SelectionTarget = SelectionTarget.from_hit(original.to_hit())

	assert_true(restored.same_as(original), "the same thing came back")
	assert_eq(restored.part, barrel)


func test_from_hit_reads_every_kind_a_click_produces() -> void:
	var unit: Unit = _unit()
	assert_true(SelectionTarget.from_hit(SelectionTarget.for_unit(unit).to_hit()).is_unit())
	assert_true(
		SelectionTarget.from_hit({"kind": Enums.HitKind.CELL, "cell": Vector2i(1, 2)}).is_cell()
	)
	assert_true(SelectionTarget.from_hit({}).empty, "a click that hit nothing is not a cell")


## **Identity, not coordinates.** A prop and a unit can share a cell, so comparing cells would
## call them the same selection.
func test_two_things_in_one_cell_are_not_the_same_selection() -> void:
	var cell := Vector2i(4, 4)
	var unit: Unit = _unit(cell)

	assert_false(SelectionTarget.for_unit(unit).same_as(SelectionTarget.for_part(_barrel(), cell)))
	assert_false(SelectionTarget.for_part(_barrel(), cell).same_as(SelectionTarget.for_cell(cell)))
	assert_true(SelectionTarget.for_cell(cell).same_as(SelectionTarget.for_cell(cell)))


## **`BR35.01`: a distant cell is rejected before the per-box test, and a near one never is.**
##
## `PartPicker.hit` ran a full assembly ray test against every blocker and field item regardless
## of the ray's direction — fine for a handful of props, 200+ wall cells on a real map, on every
## mouse motion. The reject must be **conservative**: admitting a cell the real test then rejects
## costs a little time; rejecting one that would have been hit is a shot passing through a wall.
func test_the_picker_rejects_cells_the_ray_goes_nowhere_near() -> void:
	var from := Vector3.ZERO
	var dir := Vector3(1.0, 0.0, 0.0)

	assert_true(PartPicker.near_ray(Vector2i(5, 0), from, dir), "straight down the ray")
	assert_true(PartPicker.near_ray(Vector2i(5, 1), from, dir), "and just off it")
	assert_false(PartPicker.near_ray(Vector2i(5, 40), from, dir), "far to the side")
	assert_false(PartPicker.near_ray(Vector2i(-40, 0), from, dir), "and well behind it")

	# `BR52.01`, second half: the reject measures distance to the cell's own
	# elevation, not to a point on the ground. It used to hard-code zero, so a
	# blocker on a raised cell was rejected outright for any ray passing above it
	# — the one thing this reject's own contract says must never happen.
	assert_false(
		PartPicker.near_ray(Vector2i(5, 0), Vector3(0.0, 4.0, 0.0), dir),
		"a ray four units up is genuinely nowhere near a ground-level cell"
	)
	assert_true(
		PartPicker.near_ray(Vector2i(5, 0), Vector3(0.0, 4.0, 0.0), dir, 4.0),
		"but it is right beside the same cell raised to meet it"
	)


## The bound has to clear a part whose boxes overhang its own cell, so it is checked against the
## cell size rather than assumed — a tight bound here would clip real hits.
func test_the_reject_radius_clears_more_than_one_cell() -> void:
	assert_gt(PartPicker.SKIP_RADIUS, 1.0, "a part's boxes can overhang its cell")


## taskblock-58 Pass A: **the struck face survives the click path.** `PartPicker` reports it,
## `from_pick` keeps it, and `to_hit()`/`from_hit()` carry it across the `board_clicked` signal —
## which is the whole route between the ray test and an editor tool that places against a face.
func test_the_struck_face_survives_a_pick_and_the_hit_dict_round_trip() -> void:
	var barrel: Part = _barrel()
	var raw_pick: Dictionary = {
		"unit": null,
		"part": barrel,
		"cell": Vector2i(5, 5),
		"t": 1.0,
		"normal": Vector3.UP,
	}

	var picked: SelectionTarget = SelectionTarget.from_pick(raw_pick)
	assert_eq(picked.normal, Vector3.UP, "the pick's own face")

	var restored: SelectionTarget = SelectionTarget.from_hit(picked.to_hit())
	assert_eq(restored.normal, Vector3.UP, "and it comes back across the signal")


## A target built for something that was never resolved against geometry reports **no** face.
## `Vector3.ZERO` would be a direction a caller could dot with and believe.
func test_a_target_with_no_struck_face_reports_null_not_a_zero_vector() -> void:
	assert_null(SelectionTarget.none().normal, "the empty selection struck nothing")
	assert_null(SelectionTarget.for_cell(Vector2i(2, 2)).normal, "a ground-plane cell has no face")
	assert_null(
		SelectionTarget.for_part(_barrel(), Vector2i(1, 1)).normal,
		"and a target built without a pick has not been told one"
	)
	assert_false(SelectionTarget.for_cell(Vector2i(2, 2)).to_hit().has("normal"))


## **`none()` is a shared singleton.** A miss that wrote its normal onto it would leave that face
## on the empty selection for every later caller — a stale answer with no way to notice.
func test_a_miss_never_writes_a_face_onto_the_shared_empty_selection() -> void:
	var missed: SelectionTarget = SelectionTarget.from_pick(
		{"unit": null, "part": null, "cell": Vector2i(3, 3), "normal": Vector3.UP}
	)

	assert_true(missed.empty, "no part means nothing was selected")
	assert_null(SelectionTarget.none().normal, "and the singleton is untouched")
