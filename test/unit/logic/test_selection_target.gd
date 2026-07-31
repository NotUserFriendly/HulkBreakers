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


## **A bare tile has nothing to inspect; a prop does.** `BR51.10` — the button was live
## whenever anything had been clicked rather than when the thing clicked has a body.
func test_only_things_with_a_body_can_be_inspected() -> void:
	assert_true(SelectionTarget.for_unit(_unit()).can_inspect())
	assert_true(
		SelectionTarget.for_part(_barrel(), Vector2i.ZERO).can_inspect(), "a prop has parts"
	)
	assert_false(SelectionTarget.for_cell(Vector2i(1, 1)).can_inspect(), "a bare tile has none")


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
