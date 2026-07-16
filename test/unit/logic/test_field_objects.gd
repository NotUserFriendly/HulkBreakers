extends GutTest

## docs/10 taskblock04 C3: starter field objects are data rows, no code —
## these just prove each one is shaped the way the rest of the system
## (shot plane, cook-off, salvage) expects: real volume, a real material,
## positive hp, and (except the plain crate) the tags/numbers its own
## mechanic reads.


func test_scrap_pile_has_real_geometry_material_and_salvage() -> void:
	var part: Part = FieldObjects.scrap_pile()
	assert_eq(part.id, &"scrap_pile")
	assert_true(part.volume.size() > 0)
	assert_ne(part.material, &"")
	assert_true(part.hp > 0)
	assert_eq(part.salvage_yield, {&"metals": 4})


func test_goo_barrel_is_volatile_and_cooks_off() -> void:
	var part: Part = FieldObjects.goo_barrel()
	assert_true(&"VOLATILE" in part.tags)
	assert_gt(part.cook_off_damage, 0.0)
	assert_gt(part.cook_off_radius, 0.0)
	assert_eq(part.salvage_yield, {&"reactives": 2})


func test_crate_has_real_geometry_material_and_salvage() -> void:
	var part: Part = FieldObjects.crate()
	assert_true(part.volume.size() > 0)
	assert_ne(part.material, &"")
	assert_eq(part.salvage_yield, {&"organics": 3})


func test_every_starter_field_object_is_destructible_by_default() -> void:
	# Distinct from MapGen's own randomly-scattered terrain cover, which is
	# deliberately permanent (is_destructible = false) — a field object is
	# meant to be cut apart or destroyed for its salvage.
	for part: Part in [FieldObjects.scrap_pile(), FieldObjects.goo_barrel(), FieldObjects.crate()]:
		assert_true(part.is_destructible, "%s must be destructible" % part.id)
