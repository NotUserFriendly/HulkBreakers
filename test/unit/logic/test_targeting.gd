extends GutTest


func _make_full_part_set() -> Chassis:
	var chassis := Chassis.new()
	var specs: Array = [
		[Enums.SlotType.TORSO, 40.0],
		[Enums.SlotType.LEGS, 26.0],
		[Enums.SlotType.L_ARM, 12.0],
		[Enums.SlotType.R_ARM, 12.0],
		[Enums.SlotType.HEAD, 10.0],
	]
	for spec: Array in specs:
		var part := Part.new()
		part.slot_type = spec[0]
		part.exposure_weight = spec[1]
		part.hp = 5
		part.max_hp = 5
		chassis.install(part)
	return chassis


func _make_unit(cell: Vector2i, chassis: Chassis, squad: int) -> Unit:
	return Unit.new(Matrix.new(), chassis, cell, squad)


func test_resolve_hit_is_deterministic_for_a_given_seed() -> void:
	var grid := Grid.new(10, 10)
	var attacker := _make_unit(Vector2i(0, 0), Chassis.new(), 0)
	var target := _make_unit(Vector2i(5, 0), _make_full_part_set(), 1)

	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 777
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 777

	var hit_a: HitResult = Targeting.resolve_hit(attacker, target, grid, rng_a)
	var hit_b: HitResult = Targeting.resolve_hit(attacker, target, grid, rng_b)
	assert_eq(hit_a.part, hit_b.part)


func test_distribution_tracks_exposure_weight_ratios() -> void:
	var grid := Grid.new(10, 10)
	var attacker := _make_unit(Vector2i(0, 0), Chassis.new(), 0)
	var target := _make_unit(Vector2i(5, 0), _make_full_part_set(), 1)

	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var counts: Dictionary = {}
	var trials := 20000
	for i in range(trials):
		var hit: HitResult = Targeting.resolve_hit(attacker, target, grid, rng)
		var key: Enums.SlotType = hit.part.slot_type
		counts[key] = counts.get(key, 0) + 1

	var expected: Dictionary = {
		Enums.SlotType.TORSO: 0.40,
		Enums.SlotType.LEGS: 0.26,
		Enums.SlotType.L_ARM: 0.12,
		Enums.SlotType.R_ARM: 0.12,
		Enums.SlotType.HEAD: 0.10,
	}
	for slot: Variant in expected.keys():
		var ratio: float = float(counts.get(slot, 0)) / float(trials)
		assert_almost_eq(ratio, expected[slot], 0.03, "slot %s ratio %.4f expected ~%.2f" % [slot, ratio, expected[slot]])


func test_zero_weight_parts_are_never_selected() -> void:
	var grid := Grid.new(10, 10)
	var chassis := Chassis.new()
	var strong := Part.new()
	strong.slot_type = Enums.SlotType.TORSO
	strong.exposure_weight = 10.0
	strong.hp = 5
	strong.max_hp = 5
	var zeroed := Part.new()
	zeroed.slot_type = Enums.SlotType.HEAD
	zeroed.exposure_weight = 0.0
	zeroed.hp = 5
	zeroed.max_hp = 5
	chassis.install(strong)
	chassis.install(zeroed)

	var attacker := _make_unit(Vector2i(0, 0), Chassis.new(), 0)
	var target := _make_unit(Vector2i(5, 0), chassis, 1)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in range(200):
		var hit: HitResult = Targeting.resolve_hit(attacker, target, grid, rng)
		assert_eq(hit.part, strong)


func test_no_selectable_parts_returns_empty_hit() -> void:
	var grid := Grid.new(10, 10)
	var chassis := Chassis.new()
	var zeroed := Part.new()
	zeroed.slot_type = Enums.SlotType.TORSO
	zeroed.exposure_weight = 0.0
	zeroed.hp = 5
	zeroed.max_hp = 5
	chassis.install(zeroed)

	var attacker := _make_unit(Vector2i(0, 0), Chassis.new(), 0)
	var target := _make_unit(Vector2i(5, 0), chassis, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5

	var hit: HitResult = Targeting.resolve_hit(attacker, target, grid, rng)
	assert_null(hit.part)
	assert_null(hit.cover_object)
	assert_false(hit.blocked)


func test_covered_slot_routes_to_destructible_cover_object() -> void:
	var grid := Grid.new(10, 10)
	var cover_cell := Vector2i(3, 0)
	grid.set_cover_value(cover_cell, 0.5)
	var crate := Part.new()
	crate.is_destructible = true
	crate.hp = 5
	crate.max_hp = 5
	grid.blockers[cover_cell] = crate

	var chassis := Chassis.new()
	var legs := Part.new()
	legs.slot_type = Enums.SlotType.LEGS  # HALF cover profile is [LEGS]
	legs.exposure_weight = 10.0
	legs.hp = 5
	legs.max_hp = 5
	chassis.install(legs)

	var attacker := _make_unit(Vector2i(0, 0), Chassis.new(), 0)
	var target := _make_unit(Vector2i(4, 0), chassis, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3

	var hit: HitResult = Targeting.resolve_hit(attacker, target, grid, rng)
	assert_eq(hit.cover_object, crate)
	assert_eq(hit.cover_cell, cover_cell)
	assert_null(hit.part)
	assert_false(hit.blocked)


func test_covered_slot_behind_terrain_cover_is_blocked() -> void:
	var grid := Grid.new(10, 10)
	var cover_cell := Vector2i(3, 0)
	grid.set_cover_value(cover_cell, 0.5)
	var terrain_obj := Part.new()
	terrain_obj.is_destructible = false
	grid.blockers[cover_cell] = terrain_obj

	var chassis := Chassis.new()
	var legs := Part.new()
	legs.slot_type = Enums.SlotType.LEGS
	legs.exposure_weight = 10.0
	legs.hp = 5
	legs.max_hp = 5
	chassis.install(legs)

	var attacker := _make_unit(Vector2i(0, 0), Chassis.new(), 0)
	var target := _make_unit(Vector2i(4, 0), chassis, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9

	var hit: HitResult = Targeting.resolve_hit(attacker, target, grid, rng)
	assert_true(hit.blocked)
	assert_null(hit.part)
	assert_null(hit.cover_object)


func test_slot_not_in_profile_hits_directly_despite_cover() -> void:
	var grid := Grid.new(10, 10)
	var cover_cell := Vector2i(3, 0)
	grid.set_cover_value(cover_cell, 0.5)  # HALF profile is [LEGS] only
	var crate := Part.new()
	crate.is_destructible = true
	crate.hp = 5
	crate.max_hp = 5
	grid.blockers[cover_cell] = crate

	var chassis := Chassis.new()
	var torso := Part.new()
	torso.slot_type = Enums.SlotType.TORSO  # not in HALF profile
	torso.exposure_weight = 10.0
	torso.hp = 5
	torso.max_hp = 5
	chassis.install(torso)

	var attacker := _make_unit(Vector2i(0, 0), Chassis.new(), 0)
	var target := _make_unit(Vector2i(4, 0), chassis, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11

	var hit: HitResult = Targeting.resolve_hit(attacker, target, grid, rng)
	assert_eq(hit.part, torso)
	assert_null(hit.cover_object)
	assert_false(hit.blocked)


func test_chipping_destructible_cover_to_zero_reopens_the_profile() -> void:
	var grid := Grid.new(10, 10)
	var cover_cell := Vector2i(3, 0)
	grid.set_cover_value(cover_cell, 1.0)
	var crate := Part.new()
	crate.is_destructible = true
	crate.hp = 5
	crate.max_hp = 5
	grid.blockers[cover_cell] = crate

	var chassis := Chassis.new()
	var legs := Part.new()
	legs.slot_type = Enums.SlotType.LEGS
	legs.exposure_weight = 10.0
	legs.hp = 5
	legs.max_hp = 5
	chassis.install(legs)

	var attacker := _make_unit(Vector2i(0, 0), Chassis.new(), 0)
	var target := _make_unit(Vector2i(4, 0), chassis, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21

	var first_hit: HitResult = Targeting.resolve_hit(attacker, target, grid, rng)
	assert_eq(first_hit.cover_object, crate)

	Cover.apply_damage_to_object(grid, cover_cell, 5)
	assert_false(grid.blockers.has(cover_cell))

	var second_hit: HitResult = Targeting.resolve_hit(attacker, target, grid, rng)
	assert_eq(second_hit.part, legs)
	assert_null(second_hit.cover_object)
