extends GutTest


func test_undo_reverts_the_field_and_returns_the_edit() -> void:
	var part := Part.new()
	part.hp = 5
	var stack := ResourceEditStack.new()
	part.hp = 9
	stack.record(part, &"hp", 5, 9)

	var undone: ResourceEdit = stack.undo()
	assert_eq(part.hp, 5)
	assert_eq(undone.resource, part)
	assert_eq(undone.field, &"hp")


func test_redo_reapplies_after_an_undo() -> void:
	var part := Part.new()
	part.hp = 5
	var stack := ResourceEditStack.new()
	part.hp = 9
	stack.record(part, &"hp", 5, 9)

	stack.undo()
	stack.redo()
	assert_eq(part.hp, 9)


func test_a_new_edit_after_undo_clears_the_redo_branch() -> void:
	var part := Part.new()
	part.hp = 5
	var stack := ResourceEditStack.new()
	part.hp = 9
	stack.record(part, &"hp", 5, 9)
	stack.undo()

	part.hp = 12
	stack.record(part, &"hp", 5, 12)
	assert_false(stack.can_redo(), "a fresh edit must fork off the old redo branch")


func test_undo_with_nothing_to_undo_returns_null() -> void:
	var stack := ResourceEditStack.new()
	assert_null(stack.undo())
	assert_false(stack.can_undo())


## C5: "undo reverts the LAST edit" — across two DIFFERENT resources,
## across two DIFFERENT fields, in the right order.
func test_undo_reverts_edits_in_reverse_order_across_resources_and_fields() -> void:
	var torso := Part.new()
	torso.hp = 12
	var pistol := Part.new()
	pistol.damage = 4.0
	var stack := ResourceEditStack.new()

	torso.hp = 20
	stack.record(torso, &"hp", 12, 20)
	pistol.damage = 8.0
	stack.record(pistol, &"damage", 4.0, 8.0)

	stack.undo()
	assert_eq(pistol.damage, 4.0, "the most recent edit (pistol.damage) undoes first")
	assert_eq(torso.hp, 20, "the earlier edit must not be touched yet")

	stack.undo()
	assert_eq(torso.hp, 12)


## C5: "must survive across... sort/filter changes (undo restores the
## VALUE, not the visual position)" — the stack is keyed by
## resource+field identity, never row/column position, so nothing about
## sort/filter state can even reach it. Simulated here by simply never
## touching row/column concepts at all through several edits.
func test_undo_is_independent_of_any_row_or_column_position() -> void:
	var part := Part.new()
	part.mass = 1.0
	var stack := ResourceEditStack.new()
	part.mass = 2.0
	stack.record(part, &"mass", 1.0, 2.0)
	part.mass = 3.0
	stack.record(part, &"mass", 2.0, 3.0)

	stack.undo()
	assert_eq(part.mass, 2.0)
	stack.undo()
	assert_eq(part.mass, 1.0)


## taskblock-11 C4/C5: a `dt_curve` point isn't a plain `resource.field`
## — it's one `Vector2` inside an `Array`, so applying it needs a custom
## setter instead of the default `resource.set(field, value)`.
func test_undo_redo_via_a_custom_setter_for_non_field_edits() -> void:
	var material := MaterialEntry.new()
	material.dt_curve = [Vector2(0.0, 3.0)]
	var stack := ResourceEditStack.new()

	var set_dt := func(value: float) -> void:
		var point: Vector2 = material.dt_curve[0]
		point.y = value
		material.dt_curve[0] = point

	set_dt.call(9.0)
	stack.record(material, &"dt_curve[0].y", 3.0, 9.0, set_dt)
	assert_eq(material.dt_curve[0], Vector2(0.0, 9.0))

	stack.undo()
	assert_eq(material.dt_curve[0], Vector2(0.0, 3.0))

	stack.redo()
	assert_eq(material.dt_curve[0], Vector2(0.0, 9.0))
