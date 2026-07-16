extends GutTest

## docs/05 taskblock04 D1: "neither is an upgrade of the other — they're
## better at different things." Not a ladder: a backpack must not simply
## dominate or be dominated by a trash barrel on every axis at once.


func test_backpack_is_soft_with_the_better_mass_discount_but_less_capacity() -> void:
	var part: Part = Containers.backpack()
	assert_true(part.is_container)
	assert_false(part.rigid)
	assert_true(&"BACK" in part.attaches_to)
	assert_eq(part.mass_multiplier, 0.5)


func test_trash_barrel_is_rigid_with_the_floor_discount_but_more_capacity() -> void:
	var part: Part = Containers.trash_barrel()
	assert_true(part.is_container)
	assert_true(part.rigid)
	assert_true(&"BACK" in part.attaches_to)
	assert_eq(part.mass_multiplier, 0.8)


func test_neither_container_dominates_the_other() -> void:
	var backpack: Part = Containers.backpack()
	var barrel: Part = Containers.trash_barrel()
	assert_lt(
		backpack.mass_multiplier, barrel.mass_multiplier, "the backpack wins on mass discount"
	)
	assert_lt(backpack.max_bulk, barrel.max_bulk, "the barrel wins on capacity")
